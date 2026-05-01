#!/usr/bin/env python3
"""Factor test runner producing v3-format results.json.

Strategy: post-process the text output from
`factor -roots=. -run=exercism-tools <slug>`. Factor's tools.test prints a
`Unit Test: <args>` header before each test, the test body's stdout, then
`--> test failed!` on failure. After all tests run, exercism-tools prints
per-failure blocks bracketed by `###FAIL_BEGIN###` / `###FAIL_END###`,
each containing `<path>: <line#>`, the Unit Test header, and either an
`=== Expected: / === Got:` diff or a thrown error message.

We pair these with the test file's source lines (read directly from the
copy that Factor saw, with STOP-HERE removed) to populate test_code and
task_id for each test.

Spec: https://exercism.org/docs/building/tooling/test-runners/interface
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

OUTPUT_LIMIT = 500
MESSAGE_LIMIT = 65_535
TEST_KEYWORDS = (
    "unit-test",
    "unit-test~",
    "unit-test-v~",
    "long-unit-test",
    "must-fail-with",
    "must-fail",
    "must-not-fail",
    "must-infer",
    "must-infer-as",
)
TEST_KEYWORD_RE = re.compile(
    r"\b(?:" + "|".join(re.escape(k) for k in TEST_KEYWORDS) + r")\s*$"
)
TASK_RE = re.compile(r"^\s*TASK:\s+(\d+)(?:\s+.*)?$")
HEADER_PREFIX = "Unit Test: "
FAIL_MARKER = "--> test failed!"
FAIL_BEGIN = "###FAIL_BEGIN###"
FAIL_END = "###FAIL_END###"
FAIL_LOC_RE = re.compile(r"^(.+?):\s*(\d+)\s*$")
STACK_TRACE_RE = re.compile(r"^\((U|O)\) ")


@dataclass
class SourceTest:
    line_no: int           # 1-based line of the test keyword in the file Factor saw
    test_code: str         # stripped source line
    task_id: int | None


@dataclass
class FailureBlock:
    line_no: int
    body: str  # the formatted Expected/Got text or thrown error message


def parse_source(test_file: Path) -> list[SourceTest]:
    tests: list[SourceTest] = []
    current_task: int | None = None
    for line_no, raw in enumerate(test_file.read_text().splitlines(), start=1):
        line = raw.rstrip()
        m = TASK_RE.match(line)
        if m:
            current_task = int(m.group(1))
            continue
        if TEST_KEYWORD_RE.search(line):
            tests.append(SourceTest(line_no=line_no, test_code=line.strip(), task_id=current_task))
    return tests


def split_inline_and_failures(stdout: str) -> tuple[list[str], list[str]]:
    """Return (lines-before-first-fail-block, lines-from-first-fail-block-on)."""
    lines = stdout.splitlines()
    for i, line in enumerate(lines):
        if line == FAIL_BEGIN:
            return lines[:i], lines[i:]
    return lines, []


def parse_inline(lines: list[str]) -> list[dict]:
    """Slice inline output into per-test segments by Unit Test: headers."""
    segments: list[dict] = []
    current: dict | None = None
    for line in lines:
        if line.startswith(HEADER_PREFIX):
            if current is not None:
                segments.append(current)
            current = {"header": line[len(HEADER_PREFIX):], "output_lines": [], "failed": False}
            continue
        if current is None:
            continue  # Preamble noise; ignore.
        if line == FAIL_MARKER:
            current["failed"] = True
            continue
        current["output_lines"].append(line)
    if current is not None:
        segments.append(current)
    return segments


def parse_failure_blocks(lines: list[str]) -> list[FailureBlock]:
    """Walk fail-section lines, returning one FailureBlock per ###FAIL_BEGIN###...###FAIL_END### pair."""
    blocks: list[FailureBlock] = []
    i = 0
    while i < len(lines):
        if lines[i] != FAIL_BEGIN:
            i += 1
            continue
        i += 1  # consume FAIL_BEGIN
        if i >= len(lines):
            break
        loc_match = FAIL_LOC_RE.match(lines[i])
        if not loc_match:
            # Malformed block; skip until FAIL_END.
            while i < len(lines) and lines[i] != FAIL_END:
                i += 1
            continue
        line_no = int(loc_match.group(2))
        i += 1  # consume location line
        # Consume the Unit Test header line.
        if i < len(lines) and lines[i].startswith(HEADER_PREFIX):
            i += 1
        body_lines: list[str] = []
        while i < len(lines) and lines[i] != FAIL_END:
            body_lines.append(lines[i])
            i += 1
        if i < len(lines):
            i += 1  # consume FAIL_END
        # Strip leading/trailing blank lines from body.
        while body_lines and not body_lines[0].strip():
            body_lines.pop(0)
        while body_lines and not body_lines[-1].strip():
            body_lines.pop()
        blocks.append(FailureBlock(line_no=line_no, body="\n".join(body_lines)))
    return blocks


def truncate(s: str, limit: int) -> str:
    return s if len(s) <= limit else s[: limit - 1] + "…"


def make_test_objs(
    source_tests: list[SourceTest],
    segments: list[dict],
    failure_blocks: list[FailureBlock],
) -> list[dict]:
    failures_by_line: dict[int, FailureBlock] = {fb.line_no: fb for fb in failure_blocks}
    objs: list[dict] = []
    for index, seg in enumerate(segments):
        src = source_tests[index] if index < len(source_tests) else None
        name = f"Test {index + 1}"
        test_code = src.test_code if src else seg["header"].rstrip("} ").strip()
        output_text = "\n".join(seg["output_lines"]).strip("\n")

        if seg["failed"]:
            fb = failures_by_line.get(src.line_no) if src else None
            message = (fb.body.strip() if fb and fb.body.strip() else "test failed")
            # Heuristic: assertion-failure bodies start with `=== Expected:` →
            # status "fail". Anything else is a thrown error → status "error".
            status = "fail" if message.startswith("=== Expected:") else "error"
        else:
            status = "pass"
            message = None

        obj: dict = {"name": name, "status": status, "test_code": test_code}
        if src and src.task_id is not None:
            obj["task_id"] = src.task_id
        if message is not None:
            obj["message"] = message
        if output_text:
            obj["output"] = truncate(output_text, OUTPUT_LIMIT)
        objs.append(obj)
    return objs


def normalize_paths(text: str, real_root: Path, canonical_root: str) -> str:
    return text.replace(str(real_root), canonical_root)


def clean_for_top_level_error(raw: str) -> str:
    """Strip Factor stack-trace noise from a top-level error message."""
    cleaned: list[str] = []
    for line in raw.splitlines():
        if STACK_TRACE_RE.match(line):
            break
        cleaned.append(line)
    return "\n".join(cleaned).strip() or "No tests were executed"


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: run.py <slug> <solution-dir> <output-dir>", file=sys.stderr)
        return 1
    slug = sys.argv[1]
    solution_dir = Path(sys.argv[2]).resolve()
    output_dir = Path(sys.argv[3]).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    results_path = output_dir / "results.json"
    canonical_root = f"/opt/test-runner/tests/{slug}"

    test_file = solution_dir / slug / f"{slug}-tests.factor"
    if not test_file.exists():
        results_path.write_text(json.dumps({
            "version": 3, "status": "error",
            "message": f"test file not found: {test_file.name}",
        }, indent=2) + "\n")
        return 0

    with tempfile.TemporaryDirectory(prefix=f"factor-runner-{slug}-") as tmp:
        tmp_path = Path(tmp)
        for entry in solution_dir.iterdir():
            dest = tmp_path / entry.name
            if entry.is_dir():
                shutil.copytree(entry, dest)
            else:
                shutil.copy2(entry, dest)
        # Strip STOP-HERE so all tests run.
        tmp_test = tmp_path / slug / f"{slug}-tests.factor"
        if tmp_test.exists():
            tmp_test.write_text(
                "\n".join(
                    l for l in tmp_test.read_text().splitlines() if l.strip() != "STOP-HERE"
                ) + "\n"
            )
        # Source tests are read from the post-strip file so line numbers match
        # what Factor reports.
        source_tests = parse_source(tmp_test) if tmp_test.exists() else []
        proc = subprocess.run(
            ["factor", "-roots=.", "-run=exercism-tools", slug],
            cwd=tmp,
            capture_output=True,
            text=True,
        )
        raw_output = (proc.stdout or "") + (proc.stderr or "")
        raw_output = normalize_paths(raw_output, tmp_path, canonical_root)

    inline_lines, failures_lines = split_inline_and_failures(raw_output)
    segments = parse_inline(inline_lines)
    failure_blocks = parse_failure_blocks(failures_lines)

    if not segments:
        # Nothing executed — top-level error.
        msg = clean_for_top_level_error(raw_output)
        results_path.write_text(json.dumps({
            "version": 3, "status": "error",
            "message": truncate(msg, MESSAGE_LIMIT),
        }, indent=2) + "\n")
        return 0

    test_objs = make_test_objs(source_tests, segments, failure_blocks)
    status = "pass" if all(t["status"] == "pass" for t in test_objs) else "fail"
    results_path.write_text(
        json.dumps({"version": 3, "status": status, "tests": test_objs}, indent=2) + "\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
