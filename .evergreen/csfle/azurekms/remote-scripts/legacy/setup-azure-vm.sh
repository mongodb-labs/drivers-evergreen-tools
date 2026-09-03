#!/usr/bin/env bash
#
# FROZEN. Do not modernize this script.
#
# This is setup-azure-vm.sh as it stood before PYTHON-5985 added
# python3-pip, taken verbatim from 4c63815^. Release branches still pin
# drivers-tools revisions from before that change, and their VM-side
# start-mongodb.sh clones master, so they provision like this and then run
# current ensure_uv. It installs python3-venv and no pip, the only case that
# still needs the virtual environment fallback in ensure_uv.
#
# Updating this in step with the real script would silently end that
# coverage. It goes away with the fallback, once DRIVERS-3624 confirms no
# branch that runs these tests pins that far back.
set -o errexit
set -o pipefail
# Do not error on unset variables. run-orchestration.sh accesses unset variables.

if grep -qs "bullseye" /etc/os-release; then
    echo "Overwrite repositories to fix DRIVERS-3238 ... begin"
    cat /etc/apt/sources.list | grep -v bullseye-backports | sudo tee /etc/apt/sources.list
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
