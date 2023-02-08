#!/usr/bin/env bash
#
# Bootstrapping file to launch a local oidc-enabled server and create
# OIDC tokens that can be used for local testing.  See README for
# prequisites and usage.
#
set -eux
if [[ -z "${AWS_ROLE_ARN}" ||  -z "${AWS_ACCESS_KEY_ID}" || -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
    echo "Missing AWS credentials"
    exit 1
fi

DRIVERS_TOOLS=${DRIVERS_TOOLS:-$(readlink -f ../..)}
echo "Drivers tools: $DRIVERS_TOOLS"
rm -rf $DRIVERS_TOOLS/.evergreen/auth_oidc/authoidcvenv
rm -rf $DRIVERS_TOOLS/mongodb
rm -rf $DRIVERS_TOOLS/legacy-shell-download
docker build -t oidc-test .
docker run -it -v ${DRIVERS_TOOLS}:/home/root/drivers-evergreen-tools -p 27017:27017 -p 27018:27018 -e HOME=/home/root -e AWS_ROLE_ARN=${AWS_ROLE_ARN} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} -e NO_IPV6=true oidc-test
