#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail


SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
BUILDTOOL=${BUILDTOOL:-autotools}

case "$OS" in
   cygwin*)
      bash $SCRIPT_DIR/compile-windows.sh
   ;;

   *)
      # If compiling using multiple different build tools or variants
      # that require wildly different scripting,
      # this would be a good place to call the different scripts
      case "$BUILDTOOL" in
         cmake)
            bash $SCRIPT_DIR/compile-unix-cmake.sh
         ;;
         autotools)
            bash $SCRIPT_DIR/compile-unix.sh
         ;;
      esac
   ;;
esac
