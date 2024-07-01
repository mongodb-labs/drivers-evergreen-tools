#!/usr/bin/env bash
set -eux

echo "Installing dependencies ... begin"
git clone https://github.com/mongodb/mongo-python-driver
pushd mongo-python-driver
python3 -m venv .venv
source .venv/bin/activate
pip install -U -q pip
pip install .
popd
echo "Installing dependencies ... end"

# Run the Python Driver Self Test
cd /tmp
source secrets-export.sh
python test.py
