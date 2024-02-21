#!/usr/bin/env bash
#
# Run a driver test in a docker container that targets the
# the server running in docker.
#
set -eu

# Docker related variables.
IMAGE=${TARGET_IMAGE:-ubuntu20.04}
PLATFORM=${DOCKER_PLATFORM:-}
# e.g. --platform linux/amd64

# Mongo orchestration related variables.
MONGODB_VERSION=${MONGODB_VERSION:-latest}
TOPOLOGY=${TOPOLOGY:-replica_set}
ORCHESTRATION_FILE=${ORCHESTRATION_FILE:-basic.json}
SKIP_CRYPT_SHARED_LIB=${SKIP_CRYPT_SHARED_LIB:-false}
AUTH=${AUTH:-""}
SSL=${SSL:-""}

# Internal variables.
ROOT_DRIVERS_TOOLS=/root/drivers-evergeen-tools
MONGODB_BINARIES="ROOT_DRIVERS_TOOLS/.evergreen/docker/$IMAGE/mongodb/bin"

# Build up the arguments.
ARGS="$PLATFORM --rm -i"
ARGS+=" -e MONGODB_VERSION=$MONGODB_VERSION -e TOPOLOGY=$TOPOLOGY"
ARGS+=" -e SSL=$SSL -e AUTH=$AUTH"
ARGS+=" -e MONGODB_BINARIES=$MONGODB_BINARIES"
ARGS+=" -e CRYPT_SHARED_LIB_PATH=$MONGODB_BINARIES/mongosh_crypt_v1.so"
ARGS+=" -e ORCHESTRATION_FILE=$ORCHESTRATION_FILE"
ARGS+=" -e SKIP_CRYPT_SHARED_LIB=$SKIP_CRYPT_SHARED_LIB"
ARGS+=" -e DRIVERS_TOOLS=$ROOT_DRIVERS_TOOLS"

# Ensure host.docker.internal is available on MacOS.
if [ "$(uname -s)" = "Darwin" ]; then
    ARGS+=" -e MONGODB_URI=mongodb://host.docker.internal"
fi

# Ensure host network is available on Linux.
if [ "$(uname -s)" = "Linux" ]; then
    ARGS+=" --network=host"
fi

# If there is a tty, add the -t arg.
test -t 1 && ARGS+=" -t"

# Map the cwd to /src and map in DRIVERS_TOOLS.
ARGS+=" -v `pwd`:/src"
ARGS+=" -v $DRIVERS_TOOLS:/root/drivers-evergreen-tools"

# Launch client docker container.
docker run $ARGS "$@"
