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

cd ../..
docker build -t drivers-oidc --build-arg AWS_ROLE_ARN=${AWS_ROLE_ARN} --build-arg AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} --build-arg AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} --build-arg NO_IPV6=true -f .evergreen/auth_oidc/Dockerfile .
docker run -it -p 27017:27017 -p 27018:27018 drivers-oidc
