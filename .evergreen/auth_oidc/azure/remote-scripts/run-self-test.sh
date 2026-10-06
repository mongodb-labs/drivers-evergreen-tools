#!/usr/bin/env bash
set -o errexit
set -o pipefail

source env.sh
# Copy the env.sh file to secrets-export.sh, but leave env.sh
# for backwards compatibility.
cp env.sh secrets-export.sh
pushd ./drivers-evergreen-tools/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh

# The activated environment has no pip, so install with `uv pip`. Run uv from
# this directory: inside the clone, uv enforces mongo-python-driver's own
# required-version pin.
git clone https://github.com/mongodb/mongo-python-driver
uv pip install -q ./mongo-python-driver
uv pip install -q requests
python azure/remote-scripts/test.py
popd
