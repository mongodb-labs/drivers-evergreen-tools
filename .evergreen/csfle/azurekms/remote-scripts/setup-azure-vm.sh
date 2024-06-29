#!/usr/bin/env bash
set -o errexit
set -o pipefail
# Do not error on unset variables. run-orchestration.sh accesses unset variables.

echo "Installing dependencies ... begin"
# Make apt-get non-interactive.
echo "debconf debconf/frontend select noninteractive" | sudo debconf-set-selections
# Skip the "Processing triggers for man-db" step.
echo "set man-db/auto-update false" | sudo debconf-communicate; sudo dpkg-reconfigure -f noninteractive man-db
sudo apt-get -qq update
OPTIONS="-y -o DPkg::Lock::Timeout=-1"
# Dependencies for mongod: https://www.mongodb.com/docs/manual/tutorial/install-mongodb-enterprise-on-debian-tarball/
sudo apt-get -qq install $OPTIONS libcurl4 libgssapi-krb5-2 libldap-2.4-2 libwrap0 libsasl2-2 libsasl2-modules libsasl2-modules-gssapi-mit snmp openssl liblzma5
# Dependencies for drivers-evergreen-tools
sudo apt-get -qq install $OPTIONS python3-pip python3.9-venv git
echo "Installing dependencies ... end"
