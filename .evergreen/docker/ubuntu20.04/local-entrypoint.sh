#!/usr/bin/env bash
set -eu

bash /root/base-entrypoint.sh
tail -f $MONGO_ORCHESTRATION_HOME/server.log
