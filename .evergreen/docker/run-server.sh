#!/usr/bin/env bash
#
# Run a local MongoDB orchestration inside a container
#
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

NAME=drivers-evergreen-tools
ENTRYPOINT=${ENTRYPOINT:-/root/local-entrypoint.sh}
IMAGE=${TARGET_IMAGE:-ubuntu20.04}
PLATFORM=${DOCKER_PLATFORM:-}
ARCH=${ARCH:-}
# e.g. --platform linux/amd64

if [[ -z $PLATFORM && -n $ARCH ]]; then
    PLATFORM="--platform linux/$ARCH"
fi

if command -v podman &> /dev/null; then
    DOCKER="podman --storage-opt ignore_chown_errors=true"
else
    DOCKER=docker
fi
if [ -n "${DOCKER_COMMAND:-}" ]; then
    DOCKER=$DOCKER_COMMAND
fi

# Build from the root directory so we can include files.
pushd $DRIVERS_TOOLS
cp .gitignore .dockerignore
USER="--build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g)"
$DOCKER build $PLATFORM -t $NAME -f $SCRIPT_DIR/$IMAGE/Dockerfile $USER .
popd

# Handle environment variables.
AUTH=${AUTH:-noauth}
SSL=${SSL:-nossl}
TOPOLOGY=${TOPOLOGY:-server}
LOAD_BALANCER=${LOAD_BALANCER:-}
STORAGE_ENGINE=${STORAGE_ENGINE:-}
REQUIRE_API_VERSION=${REQUIRE_API_VERSION:-}
DISABLE_TEST_COMMANDS=${DISABLE_TEST_COMMANDS:-}
MONGODB_VERSION=${MONGODB_VERSION:-latest}
MONGODB_DOWNLOAD_URL=${MONGODB_DOWNLOAD_URL:-}
ORCHESTRATION_FILE=${ORCHESTRATION_FILE:-}

# Build up the args.
ARGS="$PLATFORM --rm -i --name mongodb"
ARGS+=" -e MONGODB_VERSION=$MONGODB_VERSION"
ARGS+=" -e TOPOLOGY=$TOPOLOGY"
ARGS+=" -e AUTH=$AUTH"
ARGS+=" -e SSL=$SSL"
ARGS+=" -e ORCHESTRATION_FILE=$ORCHESTRATION_FILE"
ARGS+=" -e LOAD_BALANCER=$LOAD_BALANCER"
ARGS+=" -e STORAGE_ENGINE=$STORAGE_ENGINE"
ARGS+=" -e REQUIRE_API_VERSION=$REQUIRE_API_VERSION"
ARGS+=" -e DISABLE_TEST_COMMANDS=$DISABLE_TEST_COMMANDS"
ARGS+=" -e MONGODB_DOWNLOAD_URL=$MONGODB_DOWNLOAD_URL"

# Expose the required ports.
if [ "$TOPOLOGY" == "server" ]; then
    ARGS+=" -p 27017:27017"
elif [ "$TOPOLOGY" == "replica_set" ]; then
    ARGS+=" -p 27017:27017 -p 27018:27018 -p 27019:27019"
elif [ "$TOPOLOGY" == "sharded_cluster" ]; then
    ARGS+=" -p 27017:27017 -p 27018:27018 -p 27217:27217 -p 27218:27218 -p 27219:27219"
fi
if [ -n "$LOAD_BALANCER" ]; then
    ARGS+=" -p 27050:27050 -p 27051:27051"
fi

# If there is a tty, add the -t arg.
test -t 1 && ARGS+=" -t"

# Launch server container.
$DOCKER run $ARGS $NAME $ENTRYPOINT

# Restore the clis
bash $DRIVERS_TOOLS/.evergreen/orchestration/setup.sh
