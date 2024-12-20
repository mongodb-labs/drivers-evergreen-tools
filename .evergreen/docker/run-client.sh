#!/usr/bin/env bash
#
# Run a driver test in a docker container that targets the
# the server running in docker.
#
set -eu

# Docker related variables.
PLATFORM=${DOCKER_PLATFORM:-}
# e.g. --platform linux/amd64

if command -v podman &> /dev/null; then
    DOCKER="podman --storage-opt ignore_chown_errors=true"
else
    DOCKER=docker
fi
if [ -n "${DOCKER_COMMAND:-}" ]; then
    DOCKER=$DOCKER_COMMAND
fi

# Mongo orchestration related variables.
MONGODB_VERSION=${MONGODB_VERSION:-latest}
TOPOLOGY=${TOPOLOGY:-replica_set}
ORCHESTRATION_FILE=${ORCHESTRATION_FILE:-basic.json}
SKIP_CRYPT_SHARED_LIB=${SKIP_CRYPT_SHARED_LIB:-false}
AUTH=${AUTH:-""}
SSL=${SSL:-""}

CONT_DRIVERS_TOOLS=/root/drivers-tools

# Build up the arguments.
ARGS="$PLATFORM --rm -i"
ARGS+=" -e MONGODB_VERSION=$MONGODB_VERSION -e TOPOLOGY=$TOPOLOGY"
ARGS+=" -e SSL=$SSL -e AUTH=$AUTH"
ARGS+=" -e MONGO_ORCHESTRATION_HOME=$CONT_DRIVERS_TOOLS/.evergreen/orchestration"
ARGS+=" -e MONGODB_BINARIES=$CONT_DRIVERS_TOOLS/mongodb/bin"
ARGS+=" -e DOCKER_RUNNING=true"
ARGS+=" -e CRYPT_SHARED_LIB_PATH=$CONT_DRIVERS_TOOLS/mongosh_crypt_v1.so"
ARGS+=" -e ORCHESTRATION_FILE=$ORCHESTRATION_FILE"
ARGS+=" -e SKIP_CRYPT_SHARED_LIB=$SKIP_CRYPT_SHARED_LIB"

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
ARGS+=" -v $DRIVERS_TOOLS:$CONT_DRIVERS_TOOLS"

# Launch client docker container.
$DOCKER run $ARGS "$@"
