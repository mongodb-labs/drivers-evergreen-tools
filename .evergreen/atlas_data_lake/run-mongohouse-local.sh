#!/bin/sh
#
# This script launches a pre-built local mongohoused for testing.
#
# There is no corresponding 'shutdown' script; this project relies
# on Evergreen to terminate processes and clean up when tasks end.

cd mongohouse
export MONGOHOUSE_MQLRUN=`pwd`/artifacts/mqlrun
./artifacts/mongohoused --config ${DRIVERS_TOOLS}/.evergreen/atlas_data_lake/config.yml
