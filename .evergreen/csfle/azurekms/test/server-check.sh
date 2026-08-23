#!/usr/bin/env bash
#
# Check the server the azurekms setup group started.
#
# setup.sh has already provisioned the VM and run start-mongodb.sh, which runs
# run-orchestration.sh, so this only has to prove the server answers and that it
# came from this revision.
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR/../../../handle-paths.sh"
pushd "$SCRIPT_DIR/.." > /dev/null

# setup.sh wrote the VM name and key path here.
# shellcheck source=/dev/null
source ./secrets-export.sh

# start-mongodb.sh clones the default branch when the archive is missing and still
# starts a working server, so the ping below cannot tell the two apart. A clone
# that went unnoticed would leave this variant testing master rather than the
# checkout under test. The archive ships no .git, a clone leaves one.
if ! AZUREKMS_CMD='[ ! -d ./drivers-evergreen-tools/.git ]' ./run-command.sh < /dev/null; then
  echo "ERROR: the VM cloned drivers-evergreen-tools instead of unpacking the archive." >&2
  echo "It is running the default branch, so this run does not test this revision." >&2
  exit 1
fi

# On the legacy variant, check the VM really has no pip. Provisioning is the only
# thing that decides that, so a base image that started shipping pip would leave
# this passing while testing the ordinary path. ensure_uv installs uv into a
# virtual environment rather than the system, so pip stays absent afterwards.
#
# Carried by the exit status rather than the output, because run-command.sh echoes
# the command it runs and a sentinel string would match its own echo.
if [ "${kms_legacy_provisioning:-}" = "true" ]; then
  if ! AZUREKMS_CMD='if python3 -m pip --version; then exit 17; fi' ./run-command.sh < /dev/null; then
    echo "ERROR: the VM has pip, so this run did not exercise the venv fallback." >&2
    echo "Has remote-scripts/legacy/setup-azure-vm.sh drifted, or the base image changed?" >&2
    exit 1
  fi
fi

AZUREKMS_CMD='./drivers-evergreen-tools/mongodb/bin/mongosh --quiet --eval "db.runCommand({ping:1})" mongodb://localhost:27017' \
  ./run-command.sh < /dev/null

popd > /dev/null
