#!/usr/bin/env bash
set -o errexit
set -o pipefail

echo "Installing dependencies ... begin"
sudo apt-get update
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install git python3-pip python3-venv
git clone https://github.com/mongodb/mongo-python-driver
pushd mongo-python-driver
python3 -m venv .venv
source .venv/bin/activate
pip install -U -q pip
pip install -U -q requests setuptools
python setup.py install --no_ext
popd
echo "Installing dependencies ... end"

# Run the Python Driver Self Test
source secrets-export.sh
python test.py
