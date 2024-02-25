#!/usr/bin/env bash
# Handle proper teardown of all assets and services created by drivers-evergreen-tools.

set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

pushd $SCRIPT_DIR

# Initialize log directory.
rm -rf ./log_dir
mkdir ./log_dir

# Stop orchestration if it is running.
if [ -f "${MONGO_ORCHESTRATION_HOME}/server.log" ]; then
    # Purposely use sh here to ensure backwards compatibility.
    sh ${DRIVERS_TOOLS}/.evergreen/stop-orchestration.sh
    # Consolidate the logs into the log directory.
    find $MONGO_ORCHESTRATION_HOME -name \*.log -exec sh -c 'x="{}"; mv $x ./log_dir/$(basename $(dirname $x))_$(basename $x)' \;
fi

# Stop the load balancer.
if [ -f "$DRIVERS_TOOLS/haproxy.conf" ]; then
    bash /.evergreen/run-load-balancer.sh stop
fi

# Clean up docker
DOCKER=$(command -v docker) || true
if [ -n "$DOCKER" ]; then
    # Kill all containers
    docker rm $(docker ps -a -q)&> /dev/null || true
    # Remove all images
    docker rmi -f $(docker images -a -q) &> /dev/null || true
fi

# Execute all available teardown scripts.
find . -name "teardown.sh" -exec bash {} \;

# Move all child log files into $DRIVERS_TOOLS/test_logs.tar.gz
find . -name \*.log -exec sh -c 'x="{}"; mv $x ./log_dir/$(basename $(dirname $x))_$(basename $x)' \;
tar zcvf $DRIVERS_TOOLS/test_logs.tar.gz -C log_dir/ .
rm -rf log_dir

popd
