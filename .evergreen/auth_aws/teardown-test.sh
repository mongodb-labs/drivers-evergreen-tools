#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR
. ./activate-authawsvenv.sh
python ./lib/aws_assign_instance_profile.py
popd
