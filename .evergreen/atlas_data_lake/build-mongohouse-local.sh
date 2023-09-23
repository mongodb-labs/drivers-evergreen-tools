#!/bin/sh
#
# This script sets up the local docker image for mongohoused.
#
set -eu

DRIVERS_TOOLS=${DRIVERS_TOOLS:-$(readlink -f ../..)}
bash $DRIVERS_TOOLS/.evergreen/auth_aws/setup_secrets.sh drivers/adl
source secrets-export.sh
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 904697982180.dkr.ecr.us-east-1.amazonaws.com/atlas-query-engine-test
docker pull 904697982180.dkr.ecr.us-east-1.amazonaws.com/atlas-query-engine-test
