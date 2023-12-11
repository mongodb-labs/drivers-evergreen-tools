#!/usr/bin/env bash
#
# Run a driver test in a docker container that targets the 
# the server running in docker.
#
set -eu

# Docker related variables.
IMAGE=${TARGET_IMAGE:-ubuntu20.04}
PLATFORM=${DOCKER_PLATFORM:-}

# Mongo orchestration related variables.
MONGODB_VERSION=${MONGODB_VERSION:-latest}
TOPOLOGY=${TOPOLOGY:-replica_set}
ORCHESTRATION_FILE=${ORCHESTRATION_FILE:-basic.json}
SKIP_CRYPT_SHARED_LIB=${SKIP_CRYPT_SHARED_LIB:-false}
AUTH=${AUTH:-""}
SSL=${SSL:=""}


export ROOT_DRIVERS_TOOLS=/root/drivers-evergeen-tools
MONGODB_BINARIES="ROOT_DRIVERS_TOOLS/.evergreen/docker/$IMAGE/mongodb/bin"

ARGS="$PLATFORM --rm -i"
ARGS="$ARGS -e MONGODB_VERSION=$MONGODB_VERSION -e TOPOLOGY=$TOPOLOGY"
ARGS="$ARGS -e SSL=$SSL -e AUTH=$AUTH"
ARGS="$ARGS -e MONGODB_BINARIES=$MONGODB_BINARIES"
ARGS="$ARGS -e CRYPT_SHARED_LIB_PATH=$MONGODB_BINARIES/mongosh_crypt_v1.so"
ARGS="$ARGS -e ORCHESTRATION_FILE=$ORCHESTRATION_FILE"
ARGS="$ARGS -e SKIP_CRYPT_SHARED_LIB=$SKIP_CRYPT_SHARED_LIB"
ARGS="$ARGS -e DRIVERS_TOOLS="

# Ensure host.docker.internal is available on MacOS.
if [ "$(uname -s)" = "Darwin" ]; then
    ARGS="$ARGS -e MONGODB_URI=mongodb://host.docker.internal"
fi

# Ensure host network is available on Linux.
if [ "$(uname -s)" = "Linux" ]; then
    ARGS="$ARGS --network=host"
fi

# If there is a tty, add the -t arg.
test -t 1 && ARGS="-t $ARGS"

ARGS="$ARGS -v `pwd`:/src"
ARGS="$ARGS -v $DRIVERS_TOOLS:/root/drivers-evergreen-tools"

docker run $ARGS $@
