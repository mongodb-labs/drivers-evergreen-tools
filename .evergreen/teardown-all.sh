#!/usr/bin/env bash
# Handle proper teardown of all assets and services created by drivers-evergreen-tools.

set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

pushd $SCRIPT_DIR

# Stop orchestration if it is running.
if [ -f "${MONGO_ORCHESTRATION_HOME}/server.log" ]; then
    # Purposely use sh here to ensure backwards compatibility.
    sh ${DRIVERS_TOOLS}/.evergreen/stop-orchestration.sh
    # Ensure that the logs are accessible to the child log scraper below.
    cp "${MONGO_ORCHESTRATION_HOME}/*.log" $DRIVERS_TOOLS/.evergreen/orchestration
fi

# Stop the load balancer if it is running.
if [ -f "$DRIVERS_TOOLS/haproxy.conf" ]; then
    bash /.evergreen/run-load-balancer.sh stop
fi

# Clean up docker.
DOCKER=$(command -v docker) || true
if [ -n "$DOCKER" ]; then
    # Kill all containers.
    docker rm $(docker ps -a -q) &> /dev/null || true
    # Remove all images.
    docker rmi -f $(docker images -a -q) &> /dev/null || true
fi

# Execute all available teardown scripts.
find . -name "teardown.sh" -exec bash {} \;

# Move all child log files into $DRIVERS_TOOLS/.evergreen/test_logs.tar.gz.
LOG_DIR=./log_dir
rm -rf $LOG_DIR
mkdir $LOG_DIR
# Prepend the parent directory name to the file name.
find "$(pwd -P)" -name \*.log -exec bash -c 'x="{}"; cp $x ./log_dir/$(basename $(dirname $x))_$(basename $x)' \;
# Delete the log_dir prefixed files.
pushd $LOG_DIR
find . -name log_dir_\* | xargs rm
# Handle files from the .evergreen directory.
find . -name .evergreen_\* -exec bash -c 'mv $0 ${0/.evergreen_/}' {} \;
popd
# Slurp into a tar file.
tar zcvf $(pwd -P)/test_logs.tar.gz -C $LOG_DIR/ .
rm -rf $LOG_DIR

popd
