#!/usr/bin/env bash
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

if command -v realpath >/dev/null 2>&1
then
    SCRIPT_DIR=$(realpath $SCRIPT_DIR)
else
  SCRIPT_DIR="$( cd -- "$SCRIPT_DIR" > /dev/null 2>&1 && pwd )"
fi

# Find the DRIVERS_TOOLS by walking up the folder tree until there
# is a .evergreen folder in the same directory.
if [ -z "${DRIVERS_TOOLS:-}" ]; then
  DRIVERS_TOOLS=$(dirname $SCRIPT_DIR)
  while true
  do
    if [ -d "$DRIVERS_TOOLS/.evergreen" ]; then
      break
    fi
    DRIVERS_TOOLS=$(dirname $DRIVERS_TOOLS)
  done
fi

case "$(uname -s)" in
  CYGWIN*)
    SCRIPT_DIR=$(cygpath -m $SCRIPT_DIR)
    DRIVERS_TOOLS=$(cygpath -m $DRIVERS_TOOLS)
    # USERPROFILE is required by Python for pathlib.Path().expanduser(~).
    if [ -z "${USERPROFILE:-}" ]; then
      USERPROFILE=$(cygpath -m $HOME)
    fi
  ;;
esac

# Handle .env files
if [ -f "$DRIVERS_TOOLS/.env" ]; then
  echo "Reading $DRIVERS_TOOLS/.env file"
  export $(grep -v '^#' $DRIVERS_TOOLS/.env | xargs)
fi

if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Reading $SCRIPT_DIR/.env file"
  export $(grep -v '^#' $SCRIPT_DIR/.env | xargs)
fi

MONGODB_BINARIES=${MONGODB_BINARIES:-${DRIVERS_TOOLS}/mongodb/bin}
MONGO_ORCHESTRATION_HOME=${MONGO_ORCHESTRATION_HOME:-${DRIVERS_TOOLS}/.evergreen/orchestration}

# Add the local .bin dir to the path.
case "$PATH" in
  *"$DRIVERS_TOOLS/.bin"*)
  ;;
  *)
    PATH=$PATH:$DRIVERS_TOOLS/.bin
  ;;
esac
