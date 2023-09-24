#!/bin/sh
#
# This script launches a docker-based for mongohoused for testing.
#
# There is no corresponding 'shutdown' script; this project relies
# on Evergreen to terminate processes and clean up when tasks end.
set -eu

DRIVERS_TOOLS=${DRIVERS_TOOLS:-$(readlink -f ../..)}
DOCKER=$(command -v docker || command -v podman)
$DOCKER run -e DRIVERS_TOOLS=$DRIVERS_TOOLS -it 904697982180.dkr.ecr.us-east-1.amazonaws.com/atlas-query-engine-test -p 27017:27017 --config ./testdata/config/external/drivers/config.yaml
