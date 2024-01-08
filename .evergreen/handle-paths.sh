#!/bin/sh
#
# This script will handle the correct cross-platform absolute
# paths for a script directory and DRIVERS_TOOLS.  
# It is meant to be invoked as follows:
#
# SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
# . $SCRIPT_DIR/../handle-path.sh

set -o errexit  # Exit the script with error if any of the commands fail

if [ -z "$SCRIPT_DIR" ]; then 
  echo "Please set $SCRIPT_DIR first"
  exit 1
fi

if command -v realpath &> /dev/null
then
    SCRIPT_DIR=$(realpath $SCRIPT_DIR)
else 
  SCRIPT_DIR="$( cd -- "$SCRIPT_DIR" &> /dev/null && pwd )"
fi
if [ "Windows_NT" = "${OS:-}" ]; then # Magic variable in cygwin
  SCRIPT_DIR=$(cygpath -m $SCRIPT_DIR)
fi

# Find the DRIVERS_TOOLS by walking up the folder tree until there
# is a .evergreen folder in the same directory.
if [ -z "${DRIVERS_TOOLS:-}" ]; then
  DRIVERS_TOOLS=$(dirname $SCRIPT_DIR)
  while 1
  do
    if [ -d "$DRIVERS_TOOLS/.evergreen" ]; then 
      break 
    fi
    DRIVERS_TOOLS=$(dirname $DRIVERS_TOOLS)
  done
fi
