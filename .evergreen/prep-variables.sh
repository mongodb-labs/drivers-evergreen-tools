#!/bin/sh
set -o xtrace   # Write all commands first to stderr
set -o errexit  # Exit the script with error if any of the commands fail

echo "" > expansion.yml

# Get the current unique version of this checkout
if [ "${is_patch}" = "true" ]; then
   cd src
   VERSION=$(git describe)-patch-${version_id}
   cd ..
else
   VERSION=latest
fi

echo "CURRENT_VERSION: $VERSION" >> expansion.yml

# Python has path problems on Windows. Detect prospective mongo-orchestration home directory
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
   cygwin*)
      # Python has problems with unix style paths in cygwin. Must use c:\\ paths
      export DRIVERS_TOOLS="c:/drivers-tools"
      ;;
   *)
      export DRIVERS_TOOLS="$PWD/drivers-tools"
      ;;
esac
export MONGO_ORCHESTRATION_HOME="$DRIVERS_TOOLS/.evergreen/orchestration"
export MONGODB_BINARIES="$DRIVERS_TOOLS/mongodb/bin"

echo 'DRIVERS_TOOLS: "$DRIVERS_TOOLS"' >> expansion.yml
echo 'MONGO_ORCHESTRATION_HOME: "$MONGO_ORCHESTRATION_HOME"' >> expansion.yml
echo 'MONGODB_BINARIES: "$MONGODB_BINARIES"' >> expansion.yml
echo 'UPLOAD_BUCKET: "mongo-c-driver/changeme"' >> expansion.yml

# Make it easier to get a good shell
cat <<EOT >> expansion.yml
PREPARE_SHELL: |
   set -o errexit
   set -o xtrace
   export DRIVERS_TOOLS="$DRIVERS_TOOLS"
   export MONGO_ORCHESTRATION_HOME="$MONGO_ORCHESTRATION_HOME"
   export MONGODB_BINARIES="$MONGODB_BINARIES"
   export UPLOAD_BUCKET="mongo-c-driver/changeme"

   export TMPDIR="$MONGO_ORCHESTRATION_HOME/db"
   export PATH="$MONGODB_BINARIES:$PATH"
   export PROJECT="${project}"
EOT


