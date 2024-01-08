#!/bin/sh
#
# This script sets up the local docker image for mongohoused.
#
set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
REPO="904697982180.dkr.ecr.us-east-1.amazonaws.com/atlas-query-engine-test"
pushd $DRIVERS_TOOLS/.evergreen/auth_aws
bash setup_secrets.sh drivers/adl
source secrets-export.sh
unset AWS_SESSION_TOKEN
popd
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REPO
docker pull $REPO
