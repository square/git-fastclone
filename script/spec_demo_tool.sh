#/bin/bash

# This script is a sample script used in integration tests that exits with the code passed as the first argument
# Also, it prints all extra arguments

if [ $# -gt 1 ]; then
  # {@:2} - Skip first argument, which is the exit code
  echo "${@:2}"
fi

exit $1
