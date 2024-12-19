#!/usr/bin/env bash
set -eu

bash $ENTRYPOINTS/base-entrypoint.sh
tail -f $MONGO_ORCHESTRATION_HOME/server.log
