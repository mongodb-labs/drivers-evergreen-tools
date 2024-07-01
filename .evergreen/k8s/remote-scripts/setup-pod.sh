#!/usr/bin/env bash
set -eux

echo "Installing dependencies ... begin"
apt-get -qq update
# Same dependencies used in KMS testing.
DEBIAN_FRONTEND=noninteractive apt-get -qq -y -o DPkg::Lock::Timeout=-1 install libcurl4 libgssapi-krb5-2 libldap-2.4-2 libwrap0 libsasl2-2 \
    libsasl2-modules-gssapi-mit snmp openssl liblzma5 \
    python3-pip python3.9-venv git sudo
echo "Installing dependencies ... end"
