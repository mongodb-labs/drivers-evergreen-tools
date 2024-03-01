#!/usr/bin/env bash
# Delete GCE instance.
set -o errexit # Exit on first command error.

# Handle paths.
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

# Source the secrets
source $SCRIPT_DIR/secrets-export.sh

# Call the parent delete script.
bash $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/delete-instance.sh
