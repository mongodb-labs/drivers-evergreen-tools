#!/usr/bin/env bash
set -o errexit
set -o pipefail
# Do not error on unset variables. run-orchestration.sh accesses unset variables.

if grep -qs "bullseye" /etc/os-release; then
    echo "Overwrite repositories to fix DRIVERS-3238 ... begin"
    echo "deb http://deb.debian.org/debian bullseye main" | sudo tee /etc/apt/sources.list
    echo "deb http://deb.debian.org/debian-security bullseye-security main" | sudo tee -a /etc/apt/sources.list
    echo "deb http://deb.debian.org/debian bullseye-updates main" | sudo tee -a /etc/apt/sources.list
    echo "Overwrite repositories to fix DRIVERS-3238 ... end"
fi

echo "Installing dependencies ... begin"
# Skip the "Processing triggers for man-db" step.
echo "set man-db/auto-update false" | sudo debconf-communicate
sudo dpkg-reconfigure -f noninteractive man-db || true  # This may fail if the lock file is held.
sudo apt-get -qq update
OPTIONS="-qq -y -o DPkg::Lock::Timeout=-1"
# Dependencies for mongod: https://www.mongodb.com/docs/manual/tutorial/install-mongodb-enterprise-on-debian-tarball/
sudo DEBIAN_FRONTEND=noninteractive apt-get $OPTIONS install libcurl4 libgssapi-krb5-2 libldap-common libwrap0 libsasl2-2 libsasl2-modules libsasl2-modules-gssapi-mit openssl liblzma5 < /dev/null > /dev/null
# Dependencies for drivers-evergreen-tools
sudo DEBIAN_FRONTEND=noninteractive apt-get $OPTIONS install python3 python3-venv git < /dev/null > /dev/null
echo "Installing dependencies ... end"
