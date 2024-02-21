#!/usr/bin/env bash
# Handle proper teardown of all assets and services created by drivers-evergreen-tools.

set -o errexit  # Exit the script with error if any of the commands fail

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

pushd $SCRIPT_DIR

if [ -n "${MONGO_ORCHESTRATION_HOME:-}" ]; then
    bash ./stop-orchestration.sh
    # Consolidate the logs into the log directory.
    find $MONGO_ORCHESTRATION_HOME -name \*.log -exec sh -c 'x="{}"; mv $x ./log_dir/$(basename $(dirname $x))_$(basename $x)' \;
fi

# Remove all Docker images
DOCKER=$(command -v docker) || true
if [ -n "$DOCKER" ]; then
    echo "TODO"
    # docker rmi -f $(docker images -a -q) &> /dev/null || true
fi

# Execute all available teardown scripts.
find . -name "teardown.sh" -exec bash {} \;

# Move all child log files into $DRIVERS_TOOLS/logs.tar.gz
find . -name \*.log -exec sh -c 'x="{}"; mv $x ./log_dir/$(basename $(dirname $x))_$(basename $x)' \;
tar zcvf $DRIVERS_TOOLS/logs.tar.gz -C log_dir/ .
rm -rf log_dir

popd
