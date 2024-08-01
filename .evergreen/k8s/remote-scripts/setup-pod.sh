#!/usr/bin/env bash
set -eu

echo "Installing dependencies ... begin"
apt-get -qq update
# Same dependencies used in KMS testing.
export DEBIAN_FRONTEND=noninteractive
apt-get -qq -y -o DPkg::Lock::Timeout=-1 install libcurl4 libgssapi-krb5-2 libldap-common libwrap0 libsasl2-2 \
    libsasl2-modules-gssapi-mit snmp openssl liblzma5 \
    python3-pip python3.11-venv git sudo < /dev/null > /dev/null
echo "Installing dependencies ... end"
