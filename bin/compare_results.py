#!/usr/bin/env python3
"""Structural comparison of an expected_results.json to an actual results.json.

Usage:
    compare_results.py <expected> <actual>

Rules:
- Top-level "version" and "status" must match exactly.
- A "tests" array must be present if expected has one, with the same
  length. Per-test fields are compared:
    * name, test_code, task_id, status — exact match required
    * message / output — sentinel-aware:
        "<any non-empty>" — actual must be a non-empty string
        "<truncated>"     — actual must be exactly MAX_OUTPUT chars
                            and end with TRUNC_SUFFIX
        anything else     — exact match required
- Top-level "message" follows the same sentinel rules.

Exit code: 0 on match, 1 on mismatch (with a diff printed to stderr).
"""

import json
import sys


ANY_NON_EMPTY = "<any non-empty>"
TRUNCATED = "<truncated>"
MAX_OUTPUT = 500
TRUNC_SUFFIX = " [output truncated]"


def fail(msg):
    print(f"MISMATCH: {msg}", file=sys.stderr)
    sys.exit(1)


def compare_string(field, expected, actual):
    if expected == ANY_NON_EMPTY:
        if not isinstance(actual, str) or not actual.strip():
            fail(f"{field}: expected non-empty string, got {actual!r}")
    elif expected == TRUNCATED:
        if not isinstance(actual, str):
            fail(f"{field}: expected string, got {actual!r}")
        if len(actual) != MAX_OUTPUT:
            fail(f"{field}: expected length {MAX_OUTPUT}, got {len(actual)}")
        if not actual.endswith(TRUNC_SUFFIX):
            fail(f"{field}: expected to end with {TRUNC_SUFFIX!r}, got {actual!r}")
    else:
        if expected != actual:
            fail(f"{field}: expected {expected!r}, got {actual!r}")


def compare_test(idx, expected, actual):
    for key in ("name", "test_code", "task_id", "status"):
        if key in expected or key in actual:
            exp = expected.get(key)
            act = actual.get(key)
            if exp != act:
                fail(f"tests[{idx}].{key}: expected {exp!r}, got {act!r}")
    for key in ("message", "output"):
        if key in expected:
            if key not in actual:
                fail(f"tests[{idx}].{key}: missing from actual")
            compare_string(f"tests[{idx}].{key}", expected[key], actual[key])


def main(argv):
    if len(argv) != 3:
        print(f"usage: {argv[0]} <expected> <actual>", file=sys.stderr)
        return 1
    with open(argv[1]) as f:
        expected = json.load(f)
    try:
        with open(argv[2]) as f:
            actual = json.load(f)
    except FileNotFoundError:
        fail(f"actual file not found: {argv[2]}")
    except json.JSONDecodeError as e:
        fail(f"actual file not valid JSON: {e}")

    if expected.get("version") != actual.get("version"):
        fail(f"version: expected {expected.get('version')!r}, got {actual.get('version')!r}")
    if expected.get("status") != actual.get("status"):
        fail(f"status: expected {expected.get('status')!r}, got {actual.get('status')!r}")

    if "message" in expected:
        if "message" not in actual:
            fail("top-level message: missing from actual")
        compare_string("message", expected["message"], actual["message"])

    exp_tests = expected.get("tests")
    act_tests = actual.get("tests")
    if exp_tests is not None:
        if act_tests is None:
            fail("tests: missing from actual")
        if len(exp_tests) != len(act_tests):
            fail(f"tests length: expected {len(exp_tests)}, got {len(act_tests)}")
        for i, (e, a) in enumerate(zip(exp_tests, act_tests)):
            compare_test(i, e, a)

    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
