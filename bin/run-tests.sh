#!/usr/bin/env sh

# Synopsis:
# Test the test runner by running it against every fixture under tests/ and
# comparing the emitted results.json to the fixture's expected_results.json.
# Runs the runner locally (not in Docker); see bin/test.sh for the Docker
# equivalent.
#
# Structural fields (version, status, per-test name/test_code/task_id/status)
# must match exactly. message and output are compared via compare_results.py:
# an expected value of "<any non-empty>" matches any non-blank string, so
# Factor's variable error messages don't require byte-exact fixtures.

set -eu

script_dir=$(cd "$(dirname "$0")" && pwd)
root_dir=$(cd "${script_dir}/.." && pwd)

exit_code=0

for test_dir in "${root_dir}"/tests/*/; do
    fixture=$(basename "${test_dir}")
    test_dir_path=$(realpath "${test_dir}")
    slug=$(find "${test_dir_path}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -n1)

    if [ -z "${slug}" ]; then
        echo "SKIP: ${fixture} (no slug directory found)"
        continue
    fi

    rm -f "${test_dir_path}/results.json"
    "${script_dir}/run.sh" "${slug}" "${test_dir_path}" "${test_dir_path}" >/dev/null 2>&1 || true

    if python3 "${script_dir}/compare_results.py" \
        "${test_dir_path}/expected_results.json" \
        "${test_dir_path}/results.json"; then
        echo "OK:   ${fixture}"
    else
        echo "FAIL: ${fixture}"
        exit_code=1
    fi
done

exit ${exit_code}
