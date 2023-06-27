#/bin/bash

# This script is a sample script used in tests that exists with the exit code passed as the first argument
# It prints all arguemnts if more than 2 params are passed

if [ $# -gt 1 ]; then
  # {@:2} - Skip first argument, which is the exit code
  echo "${@:2}"
fi

exit $1
