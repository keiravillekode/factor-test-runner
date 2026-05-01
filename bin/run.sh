#!/usr/bin/env bash

# Synopsis:
# Run the test runner on a solution, producing v3-format results.json.
#
# Strategy: post-process the text output from
# `factor -roots=. -run=exercism-tools <slug>`. Factor's tools.test prints a
# `Unit Test: <args>` header before each test, the test body's stdout, then
# `--> test failed!` on failure. After all tests run, exercism-tools prints
# per-failure blocks bracketed by `###FAIL_BEGIN###`/`###FAIL_END###`,
# each containing `<path>: <line#>` and either an `=== Expected: / === Got:`
# diff or a thrown error message.
#
# Spec: https://exercism.org/docs/building/tooling/test-runners/interface

# Arguments:
# $1: exercise slug
# $2: path to solution folder
# $3: path to output directory

set -euo pipefail

if [[ -z "${1:-}" || -z "${2:-}" || -z "${3:-}" ]]; then
    echo "usage: $0 <slug> <solution-dir> <output-dir>" >&2
    exit 1
fi

slug="$1"
solution_dir=$(realpath "${2%/}")
output_dir=$(realpath "${3%/}")
mkdir -p "$output_dir"
results_file="${output_dir}/results.json"
canonical_root="/opt/test-runner/tests/${slug}"
test_file="${solution_dir}/${slug}/${slug}-tests.factor"

echo "${slug}: testing..."

if [[ ! -f "$test_file" ]]; then
    jq -n --arg msg "test file not found: ${slug}-tests.factor" \
        '{version: 3, status: "error", message: $msg}' >"$results_file"
    exit 0
fi

# Copy the fixture to a fresh temp dir so `sed -i` does not mutate the source.
tmp_dir=$(mktemp -d -t "factor-runner-${slug}-XXXXX")
trap 'rm -rf "$tmp_dir"' EXIT
cp -r "${solution_dir}/." "$tmp_dir"
sed -i '/^STOP-HERE$/d' "${tmp_dir}/${slug}/${slug}-tests.factor"

# Run Factor; capture combined stdout/stderr.
set +e
raw_output=$(cd "$tmp_dir" && factor -roots=. -run=exercism-tools "$slug" 2>&1)
set -e
# Normalize the tmp path to the canonical Docker path.
raw_output=${raw_output//$tmp_dir/$canonical_root}

# Awk parser shared by all stages: JSON-escape a single string field.
read -r -d '' AWK_JSON <<'AWK' || true
function json_str(s,    r) {
    r = s
    gsub(/\\/, "\\\\", r)
    gsub(/"/, "\\\"", r)
    gsub(/\b/, "\\b", r)
    gsub(/\f/, "\\f", r)
    gsub(/\n/, "\\n", r)
    gsub(/\r/, "\\r", r)
    gsub(/\t/, "\\t", r)
    return "\"" r "\""
}
AWK

# 1. Extract source-test records (one JSON object per line, NDJSON):
#    {"line_no":N,"task_id":N|null,"test_code":"..."}
#    Reads the post-strip file so line numbers match what Factor reports.
src_tests=$(awk "$AWK_JSON"'
    BEGIN { task = "null" }
    /^[[:space:]]*TASK:[[:space:]]+[0-9]+/ {
        match($0, /TASK:[[:space:]]+[0-9]+/)
        s = substr($0, RSTART, RLENGTH)
        sub(/^TASK:[[:space:]]+/, "", s)
        task = s
        next
    }
    /(unit-test|unit-test~|unit-test-v~|long-unit-test|must-fail-with|must-fail|must-not-fail|must-infer|must-infer-as)[[:space:]]*$/ {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        printf "{\"line_no\":%d,\"task_id\":%s,\"test_code\":%s}\n", NR, task, json_str(line)
    }
' "${tmp_dir}/${slug}/${slug}-tests.factor")

# 2. Parse Factor stdout into NDJSON segments and failures:
#    segments: {"type":"segment","idx":N,"failed":bool,"output":"..."}
#    failures: {"type":"failure","line_no":N,"message":"..."}
parsed=$(printf '%s\n' "$raw_output" | awk "$AWK_JSON"'
    function close_segment(   out, i) {
        if (idx == 0) return
        out = ""
        for (i = 1; i <= seg_n; i++) out = out (i > 1 ? "\n" : "") seg[i]
        sub(/^\n+/, "", out); sub(/\n+$/, "", out)
        printf "{\"type\":\"segment\",\"idx\":%d,\"failed\":%s,\"output\":%s}\n",
            idx, (seg_failed ? "true" : "false"), json_str(out)
    }
    function close_failure(   body, i) {
        body = ""
        for (i = 1; i <= fail_n; i++) body = body (i > 1 ? "\n" : "") fail[i]
        sub(/^\n+/, "", body); sub(/\n+$/, "", body)
        printf "{\"type\":\"failure\",\"line_no\":%d,\"message\":%s}\n",
            fail_line, json_str(body)
    }
    BEGIN { state = "inline"; idx = 0 }
    state == "inline" && /^Unit Test: / {
        close_segment()
        idx++; seg_failed = 0; seg_n = 0; delete seg
        next
    }
    state == "inline" && $0 == "###FAIL_BEGIN###" {
        close_segment(); idx = 0
        state = "fail_loc"; next
    }
    state == "inline" && $0 == "--> test failed!" {
        seg_failed = 1; next
    }
    state == "inline" {
        if (idx > 0) { seg_n++; seg[seg_n] = $0 }
        next
    }
    state == "fail_loc" {
        if (match($0, /:[[:space:]]*[0-9]+[[:space:]]*$/)) {
            n = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", n)
            fail_line = n + 0
        } else { fail_line = 0 }
        fail_n = 0; delete fail
        state = "fail_body"; next
    }
    state == "fail_body" && $0 == "###FAIL_END###" {
        close_failure()
        state = "fail_between"; next
    }
    state == "fail_body" {
        fail_n++; fail[fail_n] = $0; next
    }
    state == "fail_between" && $0 == "###FAIL_BEGIN###" {
        state = "fail_loc"; next
    }
    END { close_segment() }
')

segments=$(printf '%s\n' "$parsed" | awk '/"type":"segment"/' || true)
failures=$(printf '%s\n' "$parsed" | awk '/"type":"failure"/' || true)

# 3. If no segments emitted, surface a top-level error from the raw output.
if [[ -z "$segments" ]]; then
    cleaned=$(printf '%s\n' "$raw_output" | awk '/^\([UO]\) /{exit} {print}' \
        | sed -e '/^$/N;/\n$/D')
    if [[ -z "$cleaned" ]]; then cleaned="No tests were executed"; fi
    jq -n --arg msg "$cleaned" '{version:3, status:"error", message:$msg}' >"$results_file"
    exit 0
fi

# 4. Compose the v3 JSON.
#    --slurpfile would require files; instead pass NDJSON via --argjson after
#    converting each line. We use jq -s on a pipeline of NDJSON inputs.
jq -n \
    --argjson srcs   "$(printf '%s\n' "$src_tests"  | jq -s '.')" \
    --argjson segs   "$(printf '%s\n' "$segments"   | jq -s '.')" \
    --argjson fails  "$(printf '%s\n' "$failures"   | jq -s '.')" \
    '
    ($fails | map({(.line_no|tostring): .message}) | add // {}) as $fail_by_line
    | $segs | sort_by(.idx)
    | to_entries
    | map(
        .value as $seg
        | (.key) as $i
        | ($srcs[$i] // null) as $src
        | ($src.line_no | tostring) as $ln
        | ($fail_by_line[$ln] // null) as $msg
        | (
            if $seg.failed then
                if ($msg // "" | startswith("=== Expected:")) then "fail"
                elif $msg then "error"
                else "fail" end
            else "pass" end
          ) as $status
        | {
            name: ("Test " + ((.key + 1) | tostring)),
            status: $status,
            test_code: ($src.test_code // ""),
          }
          + (if $src.task_id then {task_id: $src.task_id} else {} end)
          + (if $seg.failed then {message: ($msg // "test failed")} else {} end)
          + (if $seg.output != "" then {output: ($seg.output[0:500])} else {} end)
      )
    | (if all(.status == "pass") then "pass" else "fail" end) as $top
    | {version: 3, status: $top, tests: .}
    ' >"$results_file"

echo "${slug}: done"
