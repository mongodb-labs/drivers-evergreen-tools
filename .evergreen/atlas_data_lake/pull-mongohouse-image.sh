#!/bin/sh
#
# This script sets up the local docker image for mongohoused.
#
set -eux

DRIVERS_TOOLS=${DRIVERS_TOOLS:-$(readlink -f ../..)}
REPO="904697982180.dkr.ecr.us-east-1.amazonaws.com/atlas-query-engine-test"
pushd $DRIVERS_TOOLS/.evergreen/auth_aws
bash setup_secrets.sh drivers/adl
source secrets-export.sh
unset AWS_SESSION_TOKEN
popd
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REPO
docker pull $REPO
