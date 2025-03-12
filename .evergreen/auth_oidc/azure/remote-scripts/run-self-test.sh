#!/usr/bin/env bash
set -o errexit
set -o pipefail

source env.sh
# Copy the env.sh file to secrets-export.sh, but leave env.sh
# for backwards compatibility.
cp env.sh secrets-export.sh
pushd ./drivers-evergreen-tools/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh

# Run the Python Driver Test
git clone https://github.com/mongodb/mongo-python-driver
pushd mongo-python-driver
pip install -U -q pip
pip install .
popd
pip install -q requests
python azure/remote-scripts/test.py
popd
