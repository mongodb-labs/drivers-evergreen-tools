#!/usr/bin/env bash
#
# This script sets up the local docker image for mongohoused.
#
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR
REPO="904697982180.dkr.ecr.us-east-1.amazonaws.com/atlas-query-engine-test"
if [ ! -f secrets-export.sh ]; then
  . ../secrets_handling/setup-secrets.sh drivers/adl
fi
source secrets-export.sh
unset AWS_SESSION_TOKEN
if command -v podman &> /dev/null; then
    DOCKER=podman
else
    DOCKER=docker
fi
aws ecr get-login-password --region us-east-1 | $DOCKER login --username AWS --password-stdin $REPO
$DOCKER pull $REPO
popd
