#!/bin/sh
#
# This script launches a docker-based for mongohoused for testing.
#
# There is no corresponding 'shutdown' script; this project relies
# on Evergreen to terminate processes and clean up when tasks end.
set -eu

DRIVERS_TOOLS=${DRIVERS_TOOLS:-$(readlink -f ../..)}
DOCKER=$(command -v docker || command -v podman)
USE_TTY=""
test -t 1 && USE_TTY="-t"
$DOCKER run -e DRIVERS_TOOLS=$DRIVERS_TOOLS -p 27017:27017 -i $USE_TTY 904697982180.dkr.ecr.us-east-1.amazonaws.com/atlas-query-engine-test --config ./testdata/config/external/drivers/config.yaml
