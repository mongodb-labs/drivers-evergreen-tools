#!/usr/bin/env bash
#
# Provision the azurekms VM for the KMS test variants and start a server on it.
#
# Pairs with server-check.sh, which checks what this leaves running.
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR/../../../handle-paths.sh"

"$SCRIPT_DIR/../../../commit-checkout.sh"

export AZUREKMS_VMNAME_PREFIX="DRIVERS_TOOLS"

# The legacy variant provisions from a frozen copy of the pre-PYTHON-5985 script.
if [ "${kms_legacy_provisioning:-}" = "true" ]; then
  export AZUREKMS_SETUP_SCRIPT="$SCRIPT_DIR/../remote-scripts/legacy/setup-azure-vm.sh"
fi

# create-and-setup-vm.sh writes its expansions file to the working
# directory, so run from the same place the inline setup this replaced did.
cd "$DRIVERS_TOOLS"
"$SCRIPT_DIR/../setup.sh"
