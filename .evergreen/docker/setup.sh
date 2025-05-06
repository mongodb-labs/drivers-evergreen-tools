#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
if [ ! -f secrets-export.sh ]; then
  . $SCRIPT_DIR/../secrets_handling/setup-secrets.sh drivers/docker
fi
source secrets-export.sh

# Python script that uses boto3 to assume the role and get the login password, then passes it to docker login
. ./activate-dockerenv.sh
python login.py
