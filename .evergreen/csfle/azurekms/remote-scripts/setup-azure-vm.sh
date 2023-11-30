#!/usr/bin/env bash
set -o errexit
set -o pipefail
# Do not error on unset variables. run-orchestration.sh accesses unset variables.
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update

echo "Install jq ... begin"
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install jq
echo "Install jq ... end"

echo "Installing MongoDB dependencies ... begin"
# Dependencies for mongod: https://www.mongodb.com/docs/manual/tutorial/install-mongodb-enterprise-on-debian-tarball/
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install libcurl4 libgssapi-krb5-2 libldap-2.4-2 libwrap0 libsasl2-2 libsasl2-modules libsasl2-modules-gssapi-mit snmp openssl liblzma5
# Dependencies for run-orchestration.sh
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install python3.9-venv
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install python3-pip
# Install git.
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install git
echo "Installing MongoDB dependencies ... end"
