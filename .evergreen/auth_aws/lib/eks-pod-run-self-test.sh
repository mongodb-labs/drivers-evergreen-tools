#!/usr/bin/env bash
set -eu

echo "Installing dependencies ... begin"
rm -rf .venv
python3 -m venv .venv
source .venv/bin/activate
pip install -U -q pip "pymongo[aws]"
echo "Installing dependencies ... end"

# Run the Python Driver Self Test
SCRIPT_DIR=$(realpath "$(dirname ${BASH_SOURCE[0]})")
pushd $SCRIPT_DIR
export MONGODB_URI=$1
python test.py
