#!/usr/bin/env bash

# Build the Docker image and run every fixture under tests/. Compares the
# generated results.json against expected_results.json.
#
# Usage:
#   bin/test.sh              # run every fixture
#   bin/test.sh fixture...   # run only the named fixtures

set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
root_dir=$(cd "${script_dir}/.." && pwd)

cd "${root_dir}"

image=${FACTOR_TEST_RUNNER_IMAGE:-factor-test-runner:local}

echo "Building image ${image}..."
docker build --quiet -t "${image}" . >/dev/null

if [ $# -gt 0 ]; then
    fixtures=("$@")
else
    fixtures=()
    for d in tests/*/; do
        fixtures+=("$(basename "$d")")
    done
fi

fail_count=0
for fixture in "${fixtures[@]}"; do
    fixture_dir="${root_dir}/tests/${fixture}"
    if [ ! -d "${fixture_dir}" ]; then
        echo "MISSING: tests/${fixture}"
        fail_count=$((fail_count + 1))
        continue
    fi
    slug=$(find "${fixture_dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -n1)
    if [ -z "${slug}" ]; then
        echo "MISSING-SLUG: tests/${fixture}"
        fail_count=$((fail_count + 1))
        continue
    fi
    rm -f "${fixture_dir}/results.json"
    docker run --rm \
        -v "${fixture_dir}:/solution" \
        -v "${fixture_dir}:/output" \
        "${image}" "${slug}" /solution /output >/dev/null 2>&1 || true

    echo "${fixture}: comparing results.json to expected_results.json"
    if diff "${fixture_dir}/results.json" "${fixture_dir}/expected_results.json" >/dev/null; then
        echo "OK:   ${fixture}"
    else
        diff "${fixture_dir}/results.json" "${fixture_dir}/expected_results.json" >&2
        echo "FAIL: ${fixture}"
        fail_count=$((fail_count + 1))
    fi
done

if [ "${fail_count}" -gt 0 ]; then
    echo
    echo "${fail_count} fixture(s) failed."
    exit 1
fi
