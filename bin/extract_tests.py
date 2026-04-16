#!/usr/bin/env python3
"""Extract Exercism test metadata from a Factor -tests.factor file and
build a wrapped harness file that runs each test in isolation and
prints structured markers.

Usage:
    extract_tests.py <tests-file> <harness-out-file>

Writes NDJSON metadata to stdout, one object per test:
    {"index": 1, "task_id": 1, "test_code": "{ t } [ f foo ] unit-test"}

Writes the wrapped harness Factor file to <harness-out-file>. When Factor
runs the harness file it prints, for each test:

    __BEGIN__<index>__
    PASS                (or FAIL + message, or ERROR + message)
    __END__<index>__

Conventions:
- TASK: N on its own line (a parsing word, no-op at runtime) attributes
  every subsequent unit-test to task_id N until the next TASK:.
- Tests inside ``: ... ;`` word definitions, ``USING: ... ;``, etc. are
  ignored.
- String literals and ``!`` / ``#!`` line comments are respected.
"""

import json
import os
import re
import sys

DEFINER_WORDS = {
    ":", "::", "SYNTAX:", "USING:", "USE:", "FROM:", "IN:", "DEFER:",
    "GENERIC:", "GENERIC#:", "HOOK:", "MIXIN:", "TUPLE:", "C-TYPE:",
    "M:", "MACRO:", "MEMO:", "PREDICATE:", "PRIMITIVE:", "SINGLETON:",
    "SYMBOL:", "SYMBOLS:", "VARIANT:", "ALIAS:", "CONSTANT:",
    "SLOT:", "UNION:", "INTERSECTION:",
}


def tokenize(text):
    """Yield (token, start_pos). Strings and line comments are consumed as
    single tokens; the token text for a string starts with '"'."""
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
            continue
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\" and j + 1 < n:
                    j += 2
                elif text[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            yield text[i:j], i
            i = j
            continue
        j = i
        while j < n and not text[j].isspace():
            j += 1
        tok = text[i:j]
        if tok == "!" or tok == "#!":
            # Line comment — skip to end of line, emit nothing.
            while i < n and text[i] != "\n":
                i += 1
            continue
        yield tok, i
        i = j


def parse(text):
    tokens = list(tokenize(text))
    tests = []
    in_word_def = False
    depth_curly = 0
    depth_square = 0
    depth_paren = 0  # stack-effect comment
    test_start = None
    current_task = None

    idx = 0
    while idx < len(tokens):
        tok, pos = tokens[idx]

        # Stack-effect comment: ( ... ) — only when we're inside a word def.
        if in_word_def and tok == "(":
            depth_paren += 1
            idx += 1
            continue
        if in_word_def and tok == ")":
            depth_paren -= 1
            idx += 1
            continue

        if in_word_def:
            if tok == ";" and depth_paren == 0:
                in_word_def = False
            idx += 1
            continue

        # Top-level handling
        if tok == "TASK:":
            line_end = text.find("\n", pos)
            if line_end == -1:
                line_end = len(text)
            rest = text[pos + len("TASK:"):line_end]
            m = re.search(r"\d+", rest)
            if m:
                current_task = int(m.group())
            # Skip every token starting before line_end (including TASK: itself)
            while idx < len(tokens) and tokens[idx][1] < line_end:
                idx += 1
            continue

        if tok in DEFINER_WORDS:
            in_word_def = True
            idx += 1
            continue

        if tok == "{":
            if test_start is None and depth_curly == 0 and depth_square == 0:
                test_start = pos
            depth_curly += 1
            idx += 1
            continue

        if tok == "}":
            depth_curly -= 1
            idx += 1
            continue

        if tok == "[":
            if test_start is None and depth_curly == 0 and depth_square == 0:
                test_start = pos
            depth_square += 1
            idx += 1
            continue

        if tok == "]":
            depth_square -= 1
            idx += 1
            continue

        if tok == "unit-test" and depth_curly == 0 and depth_square == 0:
            if test_start is not None:
                end_pos = pos + len("unit-test")
                code = text[test_start:end_pos].strip()
                tests.append({
                    "index": len(tests) + 1,
                    "task_id": current_task,
                    "test_code": code,
                    "start": test_start,
                    "end": end_pos,
                })
                test_start = None
            idx += 1
            continue

        idx += 1

    return tests


HARNESS_PRELUDE = """
USING: continuations io io.streams.string kernel prettyprint tools.test ;
"""


def wrap_test(test):
    # Run one test, classify the outcome, and print structured markers
    # delimiting status + body. unit-test throws assert-sequence on a
    # mismatch — that's a FAIL; any other thrown error is an ERROR.
    idx = test["index"]
    code = test["test_code"]
    return (
        f'"__BEGIN__{idx}__" print flush\n'
        f'[\n'
        f'    [ {code} ] with-string-writer\n'
        f'    "__PASS__\\n" write write\n'
        f'] [\n'
        f'    dup assert-sequence?\n'
        f'    [ "__FAIL__\\n" write unparse print ]\n'
        f'    [ "__ERROR__\\n" write unparse print ] if\n'
        f'] recover\n'
        f'"__END__{idx}__" print flush\n'
    )


def strip_task_machinery(prelude):
    # Concept exercises define TASK: as a parsing word and use it on the
    # same lines that group tests. Both the definition and the call sites
    # are markers we've already consumed (task_id is in the metadata), so
    # remove them — keeping them would force two cross-file workarounds:
    # (1) the legacy "parsing" word that no longer ships, and (2) Factor's
    # rule that a parsing word can't be used in the file that defines it.
    prelude = re.sub(
        r"^:\s+TASK:.*?;\s*parsing\b[^\n]*\n?",
        "",
        prelude,
        flags=re.DOTALL | re.MULTILINE,
    )
    prelude = re.sub(r"^TASK:[^\n]*\n?", "", prelude, flags=re.MULTILINE)
    return prelude


def build_harness(prelude, tests):
    out = [
        "IN: harness\n",
        strip_task_machinery(prelude).rstrip() + "\n",
        HARNESS_PRELUDE,
    ]
    for t in tests:
        out.append(wrap_test(t))
    out.append('"__DONE__" print flush\n')
    return "".join(out)


def main(argv):
    if len(argv) != 3:
        print(f"usage: {argv[0]} <tests-file> <harness-out-file>",
              file=sys.stderr)
        return 1
    tests_path, harness_path = argv[1], argv[2]
    with open(tests_path) as f:
        text = f.read()
    tests = parse(text)

    prelude = text[:tests[0]["start"]] if tests else text

    harness = build_harness(prelude, tests)
    os.makedirs(os.path.dirname(os.path.abspath(harness_path)), exist_ok=True)
    with open(harness_path, "w") as f:
        f.write(harness)

    for t in tests:
        print(json.dumps({
            "index": t["index"],
            "task_id": t["task_id"],
            "test_code": t["test_code"],
        }))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
