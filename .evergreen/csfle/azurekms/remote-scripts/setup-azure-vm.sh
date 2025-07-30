#!/usr/bin/env bash
set -o errexit
set -o pipefail
# Do not error on unset variables. run-orchestration.sh accesses unset variables.

echo "Installing dependencies ... begin"
# Skip the "Processing triggers for man-db" step.
echo "set man-db/auto-update false" | sudo debconf-communicate
sudo dpkg-reconfigure -f noninteractive man-db || true  # This may fail if the lock file is held.
sudo apt-get -qq update
OPTIONS="-qq -y -o DPkg::Lock::Timeout=-1"
# Fix for the error:
# E: The repository 'http://debian-archive.trafficmanager.net/debian bullseye-backports Release' does not have a Release file
sudo sed -i 's/stable\/updates/stable-security\/updates/' /etc/apt/sources.list
# Dependencies for mongod: https://www.mongodb.com/docs/manual/tutorial/install-mongodb-enterprise-on-debian-tarball/
sudo DEBIAN_FRONTEND=noninteractive apt-get $OPTIONS install libcurl4 libgssapi-krb5-2 libldap-2.4-2 libwrap0 libsasl2-2 libsasl2-modules libsasl2-modules-gssapi-mit snmp openssl liblzma5 < /dev/null > /dev/null
# Dependencies for drivers-evergreen-tools
sudo DEBIAN_FRONTEND=noninteractive apt-get $OPTIONS install software-properties-common
sudo add-apt-repository ppa:deadsnakes/ppa
sudo DEBIAN_FRONTEND=noninteractive apt-get $OPTIONS install python3.10-venv git < /dev/null > /dev/null
echo "Installing dependencies ... end"
