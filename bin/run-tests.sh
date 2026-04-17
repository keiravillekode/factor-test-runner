#!/usr/bin/env sh

# Synopsis:
# Test the test runner by running it against every fixture under tests/ and
# comparing the emitted results.json to the fixture's expected_results.json.
# Runs the runner locally (not in Docker); see bin/test.sh for the Docker
# equivalent.
#
# The emitted results.json is compared to expected_results.json using diff.

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

    echo "${fixture}: comparing results.json to expected_results.json"
    if diff "${test_dir_path}/results.json" "${test_dir_path}/expected_results.json" >/dev/null; then
        echo "OK:   ${fixture}"
    else
        diff "${test_dir_path}/results.json" "${test_dir_path}/expected_results.json" >&2
        echo "FAIL: ${fixture}"
        exit_code=1
    fi
done

exit ${exit_code}
