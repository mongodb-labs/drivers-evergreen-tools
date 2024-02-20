#!/usr/bin/env bash
#
# This script sets up the local docker image for mongohoused.
#
set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
REPO="904697982180.dkr.ecr.us-east-1.amazonaws.com/atlas-query-engine-test"
. ../secrets_handling/setup-secrets.sh drivers/adl
source secrets-export.sh
unset AWS_SESSION_TOKEN
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REPO
docker pull $REPO
popd