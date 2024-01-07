#!/bin/sh
#
# This script will handle the correct cross-platform paths for a script
# directory and DRIVERS_TOOLS.  It is meant to be called as
# ". $DIR/../handle-paths.sh", if called from one of the top level
# folders in this directory.  It handles "DIR" and finds the correct
# "DRIVERS_TOOLS".
#
# This script expects the following environment variables:
#
# DIR - the absolute directory of the source script, found using
#   "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

set -o errexit  # Exit the script with error if any of the commands fail

if [ "Windows_NT" = "${OS:-}" ]; then # Magic variable in cygwin
  DIR=$(cygdrive -m $DIR)
fi

# Find the DRIVERS_TOOLS by walking up the folder tree until there
# is a .evergreen folder in the same directory.
if [ -z "${DRIVERS_TOOLS:-}" ]; then
  DRIVER_TOOLS=$(dirname $DIR)
  while 1
  do
    if [ -d "$DRIVERS_TOOLS/.evergreen" ]; then 
      break 
    fi
  done
fi
