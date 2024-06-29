#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

# Functions to fetch MongoDB binaries
. $SCRIPT_DIR/download-mongodb.sh
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

get_distro

# See .evergreen/download-mongodb.sh for most possible values
case "$DISTRO" in
   cygwin*)
      echo "Install Windows dependencies"
      ;;

   darwin*)
      echo "Install macOS dependencies"
      ;;

   linux-rhel*)
      echo "Install RHEL dependencies"
      ;;

   linux-ubuntu*)
      echo "Install Ubuntu dependencies"
      sudo -qq apt-get update || true
      sudo -qq apt-get -y -o DPkg::Lock::Timeout=-1 install awscli || true
      ;;

   sunos*)
      echo "Install Solaris dependencies"
      sudo /opt/csw/bin/pkgutil -y -i sasl_dev || true
      ;;

   *)
      echo "All other platforms..."
      ;;
esac
