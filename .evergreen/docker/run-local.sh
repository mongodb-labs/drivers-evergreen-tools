#!/usr/bin/env bash
#
# Run a local MongoDB orchestration inside a docker container
#
set -eu

NAME=drivers-evergreen-tools
ENTRYPOINT=${ENTRYPOINT:-/root/local-entrypoint.sh}
IMAGE=${TARGET_IMAGE:-ubuntu20.04}
PLATFORM=${DOCKER_PLATFORM:-}

docker build $PLATFORM -t $NAME $IMAGE
pushd ../..

AUTH=${AUTH:-noauth}
SSL=${SSL:-nossl}
TOPOLOGY=${TOPOLOGY:-server}
LOAD_BALANCER=${LOAD_BALANCER:-}
STORAGE_ENGINE=${STORAGE_ENGINE:-}
REQUIRE_API_VERSION=${REQUIRE_API_VERSION:-}
DISABLE_TEST_COMMANDS=${DISABLE_TEST_COMMANDS:-}
MONGODB_VERSION=${MONGODB_VERSION:-latest}
MONGODB_DOWNLOAD_URL=${MONGODB_DOWNLOAD_URL:-}
ORCHESTRATION_FILE=${ORCHESTRATION_FILE:-basic.json}

ENV="-e MONGODB_VERSION=$MONGODB_VERSION"
ENV="$ENV -e TOPOLOGY=$TOPOLOGY"
ENV="$ENV -e AUTH=$AUTH"
ENV="$ENV -e SSL=$SSL"
ENV="$ENV -e ORCHESTRATION_FILE=$ORCHESTRATION_FILE"
ENV="$ENV -e LOAD_BALANCER=$LOAD_BALANCER"
ENV="$ENV -e STORAGE_ENGINE=$STORAGE_ENGINE"
ENV="$ENV -e REQUIRE_API_VERSION=$REQUIRE_API_VERSION"
ENV="$ENV -e DISABLE_TEST_COMMANDS=$DISABLE_TEST_COMMANDS"
ENV="$ENV -e MONGODB_DOWNLOAD_URL=$MONGODB_DOWNLOAD_URL"

if [ "$TOPOLOGY" == "server" ]; then
    PORT="-p 27017:2017"
else
    PORT="-p 27017:2017 -p 27018:2018 -p 27019:2019"
fi

VOL="-v `pwd`:/root/drivers-evergreen-tools"

docker run $PLATFORM --rm $ENV $PORT $VOL -t $NAME $ENTRYPOINT
