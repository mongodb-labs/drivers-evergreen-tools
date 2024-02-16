#!/usr/bin/env bash
set -o errexit
set -o pipefail

echo "Installing dependencies ... begin"
sudo apt-get update
# Install git.
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install git
echo "Installing dependencies ... end"

# Run the Python Driver Self Test
git clone https://github.com/mongodb/mongo-python-driver
pushd mongo-python-driver
python3 setup.py install --no_ext
popd
pip install -q requests
python3 test.py
popd
