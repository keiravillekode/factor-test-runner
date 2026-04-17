#!/usr/bin/env bash

# Synopsis:
# Run the Exercism Factor test runner on a solution.
#
# Arguments:
#   $1: exercise slug
#   $2: path to solution folder
#   $3: path to output directory
#
# Output:
# Writes a v3 results.json to the output directory, per
# https://github.com/exercism/docs/blob/main/building/tooling/test-runners/interface.md

set -eu

if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
    echo "usage: $0 exercise-slug path/to/solution-folder path/to/output-dir"
    exit 1
fi

slug="$1"
solution_dir=$(realpath "${2%/}")
output_dir=$(realpath "${3%/}")
results_file="${output_dir}/results.json"
tests_file="${solution_dir}/${slug}/${slug}-tests.factor"

mkdir -p "${output_dir}"

echo "${slug}: testing..."

# Strip STOP-HERE markers so all tests run
if [ -f "${tests_file}" ]; then
    sed -i '/STOP-HERE/d' "${tests_file}"
fi

script_dir=$(dirname "$(readlink -f "$0")")
workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT

harness="${workdir}/harness.factor"

if [ ! -f "${tests_file}" ]; then
    printf '{\n  "version": 3,\n  "status": "error",\n  "message": "Tests file not found: %s"\n}\n' "${tests_file}" > "${results_file}"
    echo "${slug}: done"
    exit 0
fi

# Build a Factor harness that runs each test and writes results.json itself.
factor -roots=/opt/test-runner \
    -e="USING: harness-builder ; \"${tests_file}\" \"${harness}\" \"${results_file}\" build-harness" 2>&1

# Make sure no stale results.json from a prior run survives — the fallback
# below depends on its absence as a "harness didn't complete" signal.
rm -f "${results_file}"

raw_output=$(
    cd "${solution_dir}" && \
    factor -e="USING: vocabs.loader ; \".\" add-vocab-root \"${harness}\" run-file" 2>&1
) || true

# If the harness wrote results.json itself, we're done. Otherwise Factor
# crashed before reaching emit-results — wrap the captured output as a
# top-level error.
if [ ! -s "${results_file}" ]; then
    sanitized=$(printf '%s' "${raw_output}" \
        | grep -v '^fatal error for monitor root' \
        | sed '/^(U) \[/,$d' \
        | sed '/^[[:space:]]*$/d' \
        | sed "s#${workdir}/##g")
    [ -z "${sanitized}" ] && sanitized="Harness did not run to completion."
    jq -n --arg msg "${sanitized}" '{version: 3, status: "error", message: $msg}' > "${results_file}"
fi

echo "${slug}: done"
