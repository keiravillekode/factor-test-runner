#!/usr/bin/env python3
"""Combine per-test metadata with Factor harness output into a v3 results.json.

Usage:
    assemble_results.py <metadata-ndjson-path>

Reads the raw harness stdout+stderr from stdin. Writes v3 JSON to stdout.

The harness emits, for each test, three marker lines plus body content:

    __BEGIN__<idx>__
    __PASS__              (or __FAIL__, or __ERROR__)
    <captured body>
    __END__<idx>__

A trailing "__DONE__" line indicates the harness ran to completion; if it's
missing, the whole run is treated as status:error (load failure, parse
failure, or Factor crash).
"""

import json
import re
import sys

MAX_OUTPUT = 500
TRUNC_SUFFIX = " [output truncated]"


def truncate(s):
    if s is None:
        return None
    if len(s) <= MAX_OUTPUT:
        return s
    return s[: MAX_OUTPUT - len(TRUNC_SUFFIX)] + TRUNC_SUFFIX


def parse_blocks(raw):
    pattern = re.compile(
        r"__BEGIN__(\d+)__[^\n]*\n(.*?)__END__\1__",
        re.DOTALL,
    )
    results = {}
    for m in pattern.finditer(raw):
        idx = int(m.group(1))
        block = m.group(2)
        head = re.match(r"__(PASS|FAIL|ERROR)__[^\n]*\n?(.*)", block, re.DOTALL)
        if head:
            word = head.group(1)
            body = head.group(2).strip("\n")
            if word == "PASS":
                status = "pass"
            elif word == "FAIL":
                status = "fail"
            else:
                status = "error"
        else:
            status = "error"
            body = block.strip("\n")
        results[idx] = {"status": status, "body": body}
    return results


def strip_noise(s):
    lines = []
    for line in s.splitlines():
        if line.startswith("fatal error for monitor root"):
            continue
        if line.startswith("(U) ["):
            break
        if not line.strip():
            continue
        lines.append(line)
    return "\n".join(lines)


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} <metadata-ndjson>", file=sys.stderr)
        return 1

    with open(argv[1]) as f:
        metadata = [json.loads(line) for line in f if line.strip()]

    raw = sys.stdin.read()
    harness_completed = "__DONE__" in raw
    parsed = parse_blocks(raw)

    tests = []
    for meta in metadata:
        idx = meta["index"]
        block = parsed.get(idx)
        entry = {
            "name": f"Test {idx}",
            "test_code": meta["test_code"],
        }
        if meta.get("task_id") is not None:
            entry["task_id"] = meta["task_id"]

        if block is None:
            entry["status"] = "error"
            entry["message"] = "Test did not run."
        else:
            status = block["status"]
            body = block["body"]
            entry["status"] = status
            if status == "pass":
                if body:
                    entry["output"] = truncate(body)
            else:
                entry["message"] = truncate(body or "Test failed.")
        tests.append(entry)

    if not harness_completed:
        message = truncate(strip_noise(raw) or "Harness did not run to completion.")
        out = {"version": 3, "status": "error", "message": message}
        if tests and any(t["status"] in ("pass", "fail") for t in tests):
            out["tests"] = tests
    else:
        if all(t["status"] == "pass" for t in tests):
            status = "pass"
        else:
            status = "fail"
        out = {"version": 3, "status": status, "tests": tests}

    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
