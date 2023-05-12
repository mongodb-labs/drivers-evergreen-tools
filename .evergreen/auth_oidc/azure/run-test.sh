#!/usr/bin/env bash
set -o errexit
set -o pipefail

source env.sh
pushd ./drivers-evergreen-tools/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh
popd

# Run the Python Driver Test
if [ ! -d mongo-python-driver ]; then
    git clone https://github.com/mongodb/mongo-python-driver
fi
pushd mongo-python-driver
python setup.py install --no_ext
pip install requests
popd
python test.py