#!/bin/sh
#
# This script launches a pre-built local mongohoused for testing.
#
# There is no corresponding 'shutdown' script; this project relies
# on Evergreen to terminate processes and clean up when tasks end.

cd mongohouse
if [ "Windows_NT" = "$OS" ]; then
  export MONGOHOUSE_MQLRUN="$(cygpath -m "$(pwd)")/artifacts/mqlrun.exe"
else
  export MONGOHOUSE_MQLRUN=`pwd`/artifacts/mqlrun
fi;
./artifacts/mongohoused --config ${DRIVERS_TOOLS}/.evergreen/atlas_data_lake/config.yml
