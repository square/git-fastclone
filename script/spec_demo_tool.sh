#/bin/bash

# This script is a sample script used in integration tests that exits with the code passed as the first argument
# Also, it prints all extra arguments

exit_code="$1"

if [ $# -gt 1 ]; then
  # Skip first argument, which is the exit code
  shift
  echo "$@"
fi

exit $exit_code
