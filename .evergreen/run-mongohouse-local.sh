#!/bin/sh
#
# This script builds and launches a local mongohoused for testing.
#
# There is no corresponding 'shutdown' script; this project relies
# on Evergreen to terminate processes and clean up when tasks end.

set -o xtrace   # Write all commands first to stderr
set -o errexit  # Exit the script with error if any of the commands fail

ORIG_DIR="$(pwd)"

# Configure git to use the git protocol
git config --global url."git@github.com:".insteadof "https://github.com/"

AP_START=$(date +%s)

# Set up environment variables for Go
GO_VERSION=1.14
export PATH="/opt/golang/go${GO_VERSION}/bin:$PATH"
export GOROOT="/opt/golang/go${GO_VERSION}"
export GOPATH=`pwd`/.gopath
go version

# Clone the mongohouse repo
DL_START=$(date +%s)
cd "$ORIG_DIR"
rm -rf mongohouse
git clone git@github.com:10gen/mongohouse.git
cd mongohouse
GO111MODULE=on go mod download
DL_END=$(date +%s)

# Build mqlrun
./build.sh tools:download:mqlrun
export MONGOHOUSE_MQLRUN=`pwd`/artifacts/mqlrun

# Build mongohouse
./build.sh build:mongohoused

# Run mongohouse local
./artifacts/mongohoused --config ${DRIVERS_TOOLS}/.evergreen/atlas_data_lake/drivers-test-local.yaml

AP_END=$(date +%s)

# Write results file
DL_ELAPSED=$(expr $DL_END - $DL_START)
AP_ELAPSED=$(expr $AP_END - $AP_START)
cat <<EOT >> $DRIVERS_TOOLS/results.json
{"results": [
  {
    "status": "PASS",
    "test_file": "Mongohouse local Start",
    "start": $AP_START,
    "end": $AP_END,
    "elapsed": $AP_ELAPSED
  },
  {
    "status": "PASS",
    "test_file": "Download Mongohouse",
    "start": $DL_START,
    "end": $DL_END,
    "elapsed": $DL_ELAPSED
  }
]}

EOT
