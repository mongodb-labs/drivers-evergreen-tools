#!/usr/bin/env bash
set -o errexit
set -o pipefail

source env.sh
# Copy the env.sh file to secrets-export.sh, but leave env.sh
# for backwards compatibility.
cp env.sh secrets-export.sh
pushd ./drivers-evergreen-tools/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh

# Run the Python Driver Test. The activated environment is uv-managed and has
# no pip of its own, so install with `uv pip` (targets the active venv).
git clone https://github.com/mongodb/mongo-python-driver
pushd mongo-python-driver
uv pip install -q .
popd
uv pip install -q requests
python azure/remote-scripts/test.py
popd
