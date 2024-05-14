#!/usr/bin/env bash
set -eu

export DRIVERS_TOOLS=/root/drivers-evergreen-tools
export PROJECT_ORCHESTRATION_HOME=/root/drivers-evergreen-tools/.evergreen/orchestration
export MONGODB_BINARIES=/root/drivers-evergreen-tools/.evergreen/docker/ubuntu20.04/mongodb/bin
export MONGODB_BINARY_ROOT=/root/drivers-evergreen-tools/.evergreen/docker/ubuntu20.04/
export MONGO_ORCHESTRATION_HOME=/root/drivers-evergreen-tools/.evergreen/docker/ubuntu20.04/orchestration
export DOCKER_RUNNING=true

rm -f $DRIVERS_TOOLS/results.json
rm -rf /tmp/mongo*
cd $DRIVERS_TOOLS/.evergreen
bash run-orchestration.sh

# Preserve host permissions of files we have created.
cd $DRIVERS_TOOLS
files=(results.json uri.txt .evergreen/mongo_crypt_v1.so .evergreen/mo-expansion.yml)
chown --reference=action.yml "${files[@]}"
chmod --reference=action.yml "${files[@]}"

echo "Server started!"
