#!/usr/bin/env bash
# Handle proper teardown of all assets and services created by drivers-evergreen-tools.

set -o errexit  # Exit the script with error if any of the commands fail

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

if [ -n "${MONGO_ORCHESTRATION_HOME:-}" ]; then
    bash ${DRIVERS_TOOLS}/.evergreen/stop-orchestration.sh
fi

# Remove all Docker images
DOCKER=$(command -v docker) || true
if [ -n "$DOCKER" ]; then
    echo "TODO"
    # docker rmi -f $(docker images -a -q) &> /dev/null || true
fi

# Execute all available teardown scripts.
find $SCRIPT_DIR -name "teardown.sh" -exec bash {} \;

# Move all log files into $DRIVERS_TOOLS/logs.tar.gz
pushd $SCRIPT_DIR
find $MONGO_ORCHESTRATION_HOME -name \*.log -exec sh -c 'x="{}"; mv $x ./log_dir/$(basename $(dirname $x))_$(basename $x)' \;
find $SCRIPT_DIR -name \*.log -exec sh -c 'x="{}"; mv $x ./log_dir/$(basename $(dirname $x))_$(basename $x)' \;
tar zcvf $DRIVERS_TOOLS/logs.tar.gz -C log_dir/ .
rm -rf log_dir
popd
