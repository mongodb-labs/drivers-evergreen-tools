#!/usr/bin/env bash
#
# Bootstrapping file to launch a local oidc-enabled server and create
# OIDC tokens that can be used for local testing.  See README for
# prequisites and usage.
#
set -eux

DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DRIVERS_TOOLS=$(dirname $(dirname $DIR))
ENTRYPOINT=${ENTRYPOINT:-/root/docker_entry.sh}
USE_TTY=""
VOL="-v ${DRIVERS_TOOLS}:/root/drivers-evergreen-tools"
AWS_PROFILE=${AWS_PROFILE:-""}

if [ -z "$AWS_PROFILE" ]; then
    if [[ -z "${AWS_SESSION_TOKEN}" ||  -z "${AWS_ACCESS_KEY_ID}" || -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
        echo "Please set AWS_PROFILE or set AWS credentials environment variables" 1>&2
       exit 1
    fi
    ENV="-e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
    ENV="$ENV -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
else
    ENV="-e AWS_PROFILE=$AWS_PROFILE"
    VOL="$VOL -v $HOME/.aws:/root/.aws"
fi

rm -rf $DRIVERS_TOOLS/.evergreen/auth_oidc/authoidcvenv
test -t 1 && USE_TTY="-t"

echo "Drivers tools: $DRIVERS_TOOLS"
pushd ../docker
docker build -t drivers-evergreen-tools ./ubuntu20.04
popd
docker build -t oidc-test .
docker run --rm -i $USE_TTY $VOL $ENV -p 27017:27017 -p 27018:27018 oidc-test $ENTRYPOINT
