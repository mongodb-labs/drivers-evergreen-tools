#!/usr/bin/env bash
set -eu

cd $DRIVERS_TOOLS/.evergreen
bash run-orchestration.sh
tail -f $MONGO_ORCHESTRATION_HOME/server.log
