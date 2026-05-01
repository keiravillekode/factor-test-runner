#!/usr/bin/env sh

# Synopsis:
# Run the test runner on a solution.

# Arguments:
# $1: exercise slug
# $2: path to solution folder
# $3: path to output directory

# Output:
# Writes the test results to a results.json file in the passed-in output directory.
# Results conform to the v3 spec at:
# https://exercism.org/docs/building/tooling/test-runners/interface

# Example:
# ./bin/run.sh two-fer path/to/solution/folder/ path/to/output/directory/

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "usage: ./bin/run.sh exercise-slug path/to/solution/folder/ path/to/output/directory/"
    exit 1
fi

slug="$1"
echo "${slug}: testing..."

exec python3 "$(dirname "$0")/run.py" "$@"
