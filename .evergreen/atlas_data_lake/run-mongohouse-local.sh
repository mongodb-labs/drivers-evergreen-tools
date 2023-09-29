#!/bin/sh
#
# This script launches a docker-based for mongohoused for testing.
#
# There is no corresponding 'shutdown' script; this project relies
# on Evergreen to terminate processes and clean up when tasks end.
set -eux

DRIVERS_TOOLS=${DRIVERS_TOOLS:-$(readlink -f ../..)}
DOCKER=$(command -v docker || command -v podman)
USE_TTY=""
test -t 1 && USE_TTY="-t"
$DOCKER run -p 27017:27017 -e DRIVERS_TOOLS=$DRIVERS_TOOLS -v "$DRIVERS_TOOLS/.evergreen/atlas_data_lake:/src" -i $USE_TTY 904697982180.dkr.ecr.us-east-1.amazonaws.com/atlas-query-engine-test  --config /src/test.yaml
