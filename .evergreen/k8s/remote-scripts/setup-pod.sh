#!/usr/bin/env bash
set -eux

echo "Installing dependencies ... begin"
# Make apt-get non-interactive.
echo "debconf debconf/frontend select noninteractive" | debconf-set-selections
apt-get -qq update
OPTIONS="-y -qq -o DPkg::Lock::Timeout=-1"
# Dependencies for mongod: https://www.mongodb.com/docs/manual/tutorial/install-mongodb-enterprise-on-debian-tarball/
apt-get install $OPTIONS libcurl4 libgssapi-krb5-2 libldap-2.4-2 libwrap0 libsasl2-2 libsasl2-modules libsasl2-modules-gssapi-mit snmp openssl liblzma5
# Dependencies for drivers-evergreen-tools
apt-get install $OPTIONS python3-pip python3.9-venv git sudo
echo "Installing dependencies ... end"
