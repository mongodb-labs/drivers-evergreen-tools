#!/bin/sh
#
# This script will handle the correct cross-platform absolute
# paths for a script directory and DRIVERS_TOOLS.  
# It is meant to be invoked as follows:
#
# DIR=$(dirname ${BASH_SOURCE:-$0})
# . $DIR/../handle-path.sh

set -o errexit  # Exit the script with error if any of the commands fail

if [ -z "$DIR" ]; then 
  echo "Please set $DIR first"
  exit 1
fi

DIR="$( cd -- "$DIR" &> /dev/null && pwd )"
if [ "Windows_NT" = "${OS:-}" ]; then # Magic variable in cygwin
  DIR=$(cygpath -m $DIR)
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
