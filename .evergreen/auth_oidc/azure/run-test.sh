#!/usr/bin/env bash
set -o errexit
set -o pipefail

source env.sh

# Run the Python Driver Test
if [ ! -d mongo-python-driver ]; then
    git clone --branch PYTHON-3460 https://github.com/blink1073/mongo-python-driver
fi
pushd mongo-python-driver
. ./activate-authoidcvenv.sh
python setup.py install --no_ext
pip install requests
popd
python test.py