#!/usr/bin/env bash
set -o errexit
set -o pipefail

source env.sh
# Copy the env.sh file to secrets-export.sh, but leave env.sh
# for backwards compatibility.
cp env.sh secrets-export.sh
pushd ./drivers-evergreen-tools/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh

git clone https://github.com/mongodb/mongo-python-driver
pip install -q ./mongo-python-driver
pip install -q requests
python azure/remote-scripts/test.py
popd
