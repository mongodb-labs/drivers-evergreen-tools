#!/usr/bin/env bash
#
# Entry point for Dockerfile for launching an oidc-enabled server.
#
export MONGODB_VERSION=latest
export TOPOLOGY=server
export ORCHESTRATION_FILE=auth-oidc.json
export DRIVERS_TOOLS=/home/root/drivers-evergreen-tools/
export PROJECT_ORCHESTRATION_HOME=$DRIVERS_TOOLS/.evergreen/orchestration
export MONGO_ORCHESTRATION_HOME=/home/root
bash $DRIVERS_TOOLS/.evergreen/run-orchestration.sh
# Wait for the port to be listening.
while ! netstat -tna | grep 'LISTEN\>' | grep -q ':27017\>'; do
  sleep 1
done
$DRIVERS_TOOLS/mongodb/bin/mongo $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc.js
tail -f $MONGO_ORCHESTRATION_HOME/server.log