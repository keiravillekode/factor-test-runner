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
metadata="${workdir}/metadata.ndjson"

if [ ! -f "${tests_file}" ]; then
    # Produce a graceful error response if the tests file is missing
    printf '{\n  "version": 3,\n  "status": "error",\n  "message": "Tests file not found: %s"\n}\n' "${tests_file}" > "${results_file}"
    echo "${slug}: done"
    exit 0
fi

# Extract per-test metadata + build the wrapped harness Factor file
python3 "${script_dir}/extract_tests.py" "${tests_file}" "${harness}" > "${metadata}"

# Run Factor over the harness; add solution_dir as a vocab root.
raw_output=$(
    cd "${solution_dir}" && \
    factor -e="USING: vocabs.loader ; \".\" add-vocab-root \"${harness}\" run-file" 2>&1
) || true

# Assemble the v3 JSON from metadata + harness output
printf '%s' "${raw_output}" | python3 "${script_dir}/assemble_results.py" "${metadata}" > "${results_file}"

echo "${slug}: done"
