#!/usr/bin/env bash
#
# Bootstrapping file to launch a local oidc-enabled server and create
# OIDC tokens that can be used for local testing.  See README for
# prerequisites and usage.
#
set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Get the tokens.
rm -f secrets-export.sh
bash ./oidc_get_tokens.sh

# Write the expected secrets to the file.
URI="mongodb://localhost"
cat <<EOF >> "secrets-export.sh"
export MONGODB_URI="$URI"
export MONGODB_URI_SINGLE="$URI/?authMechanism=MONGODB-OIDC"
export MONGODB_URI_MULTI="$URI:27018/?directConnection=true&authMechanism=MONGODB-OIDC"
export OIDC_ADMIN_USER=bob
export OIDC_ADMIN_PWD=pwd123
export OIDC_IS_LOCAL=1
EOF

ENTRYPOINT=${ENTRYPOINT:-/root/docker_entry.sh}
USE_TTY=""
VOL="-v ${DRIVERS_TOOLS}:/root/drivers-evergreen-tools"
AWS_PROFILE=${AWS_PROFILE:-""}

if [ -z "$AWS_PROFILE" ]; then
    if [[ -z "${AWS_SESSION_TOKEN:-}" ||  -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        echo "Please set AWS_PROFILE or set AWS credentials environment variables" 1>&2
       exit 1
    fi
    ENV="-e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
    ENV="$ENV -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
else
    ENV="-e AWS_PROFILE=$AWS_PROFILE"
    VOL="$VOL -v $HOME/.aws:/root/.aws"
fi

test -t 1 && USE_TTY="-t"

echo "Drivers tools: $DRIVERS_TOOLS"
pushd ../docker
rm -rf ./ubuntu20.04/mongodb
rm -rf ./ubuntu20.04/orchestration
docker build -t drivers-evergreen-tools ./ubuntu20.04
popd
docker build -t oidc-test .
docker run --rm -i $USE_TTY $VOL $ENV -p 27017:27017 -p 27018:27018 oidc-test $ENTRYPOINT
