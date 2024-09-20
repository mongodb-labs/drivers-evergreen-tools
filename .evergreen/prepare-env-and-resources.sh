#!/bin/bash

# PREPARE EVERGREEN ENVINROMENT
# Get the current unique version of this checkout
if [ "${is_patch}" = "true" ]; then
    CURRENT_VERSION=$(git describe)-patch-${version_id}
else
    CURRENT_VERSION=latest
fi

export DRIVERS_TOOLS="$(pwd)/../drivers-tools"
export PROJECT_DIRECTORY="$(pwd)"

# Python has cygwin path problems on Windows. Detect prospective mongo-orchestration home directory
if [[ "$(uname -s)" == CYGWIN* ]]; then
    export DRIVERS_TOOLS=$(cygpath -m $DRIVERS_TOOLS)
    export PROJECT_DIRECTORY=$(cygpath -m $PROJECT_DIRECTORY)
fi

export MONGO_ORCHESTRATION_HOME="$DRIVERS_TOOLS/.evergreen/orchestration"
export PROJECT_ORCHESTRATION_HOME="$PROJECT_DIRECTORY/.evergreen/orchestration"
export MONGODB_BINARIES="$DRIVERS_TOOLS/mongodb/bin"
export UPLOAD_BUCKET="${project}"

cat <<EOT >expansion.yml
CURRENT_VERSION: "$CURRENT_VERSION"
DRIVERS_TOOLS: "$DRIVERS_TOOLS"
MONGO_ORCHESTRATION_HOME: "$MONGO_ORCHESTRATION_HOME"
PROJECT_ORCHESTRATION_HOME: "$PROJECT_ORCHESTRATION_HOME"
MONGODB_BINARIES: "$MONGODB_BINARIES"
UPLOAD_BUCKET: "$UPLOAD_BUCKET"
PROJECT_DIRECTORY: "$PROJECT_DIRECTORY"
EOT

cat <<EOT >.env
CURRENT_VERSION="$CURRENT_VERSION"
DRIVERS_TOOLS="$DRIVERS_TOOLS"
MONGO_ORCHESTRATION_HOME="$MONGO_ORCHESTRATION_HOME"
PROJECT_ORCHESTRATION_HOME="$PROJECT_ORCHESTRATION_HOME"
MONGODB_BINARIES="$MONGODB_BINARIES"
UPLOAD_BUCKET="$UPLOAD_BUCKET"
PROJECT_DIRECTORY="$PROJECT_DIRECTORY"
EOT

# See what we've done
cat expansion.yml

# PREPARE RESOURCES
rm -rf ${DRIVERS_TOOLS}
if [ "${project}" = "drivers-tools" ]; then
    # If this was a patch build, doing a fresh clone would not actually test the patch
    cp -R ${PROJECT_DIRECTORY}/ ${DRIVERS_TOOLS}
else
    git clone https://github.com/mongodb-labs/drivers-evergreen-tools.git ${DRIVERS_TOOLS}
fi
${DRIVERS_TOOLS}/.evergreen/setup.sh
