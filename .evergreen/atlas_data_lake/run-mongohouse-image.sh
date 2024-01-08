#!/bin/sh
#
# This script launches a docker-based mongohoused for testing.
#
# There is no corresponding 'shutdown' script; this project relies
# on Evergreen to terminate processes and clean up when tasks end.
set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
IMAGE=904697982180.dkr.ecr.us-east-1.amazonaws.com/atlas-query-engine-test
USE_TTY=""
test -t 1 && USE_TTY="-t"
docker run -d -p 27017:27017 -v "$DRIVERS_TOOLS/.evergreen/atlas_data_lake:/src" -i $USE_TTY $IMAGE --config ./testdata/config/external/drivers/config.yaml
