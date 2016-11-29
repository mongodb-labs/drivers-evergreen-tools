#!/bin/sh
set -o xtrace   # Write all commands first to stderr
set -o errexit  # Exit the script with error if any of the commands fail


OS=$(uname -s | tr '[:upper:]' '[:lower:]')
BUILDTOOL=${BUILDTOOL:-autotools}

case "$OS" in
   cygwin*)
      sh ./.evergreen/compile-windows.sh
   ;;

   *)
      # If compiling using multiple different build tools or variants
      # that require wildly different scripting,
      # this would be a good place to call the different scripts
      case "$BUILDTOOL" in
         cmake)
            sh ./.evergreen/compile-unix-cmake.sh
         ;;
         autotools)
            sh ./.evergreen/compile-unix.sh
         ;;
      esac
   ;;
esac

