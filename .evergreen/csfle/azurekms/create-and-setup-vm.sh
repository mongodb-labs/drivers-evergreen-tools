#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

CURR_DIR=$(pwd)
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

pushd $SCRIPT_DIR

# Handle secrets from vault.
if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${AZUREKMS_PUBLICKEY:-}" ]; then
    . ./setup-secrets.sh
fi

if [ -n "${AZUREKMS_PUBLICKEY:-}" ]; then
    echo "${AZUREKMS_PUBLICKEY}" > /tmp/testazurekms_publickey
    printf -- "${AZUREKMS_PRIVATEKEY}" > /tmp/testazurekms_privatekey
    # Set 600 permissions on private key file. Otherwise ssh / scp may error with permissions "are too open".
    chmod 600 /tmp/testazurekms_privatekey
    export AZUREKMS_PUBLICKEYPATH="/tmp/testazurekms_publickey"
    export AZUREKMS_PRIVATEKEYPATH="/tmp/testazurekms_privatekey"
fi

VARLIST=(
AZUREKMS_VMNAME_PREFIX
AZUREKMS_CLIENTID
AZUREKMS_TENANTID
AZUREKMS_SECRET
AZUREKMS_RESOURCEGROUP
AZUREKMS_PUBLICKEYPATH
AZUREKMS_PRIVATEKEYPATH
AZUREKMS_SCOPE
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
[[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# Set defaults.
# If this default changes, update the azurekms base_image in
# .evergreen/tests/test-remote-kms-provisioning.sh to match.
export AZUREKMS_IMAGE=${AZUREKMS_IMAGE:-"Debian:debian-11:11:0.20221020.1174"}

# Login.
. "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/login.sh
# Create VM.
. "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/create-vm.sh
export AZUREKMS_VMNAME="$AZUREKMS_VMNAME"
# Store items needed for teardown.
cat <<EOT > "$CURR_DIR/testazurekms-expansions.yml"
AZUREKMS_VMNAME: $AZUREKMS_VMNAME
AZUREKMS_RESOURCEGROUP: $AZUREKMS_RESOURCEGROUP
AZUREKMS_SCOPE: $AZUREKMS_SCOPE
EOT
if [ -f secrets-export.sh ]; then
    echo "export AZUREKMS_VMNAME=\"$AZUREKMS_VMNAME\"" >> secrets-export.sh
    echo "export AZUREKMS_RESOURCEGROUP=\"$AZUREKMS_RESOURCEGROUP\"" >> secrets-export.sh
    echo "export AZUREKMS_SCOPE=\"$AZUREKMS_SCOPE\"" >> secrets-export.sh
    echo "export AZUREKMS_PRIVATEKEYPATH=\"$AZUREKMS_PRIVATEKEYPATH\"" >> secrets-export.sh
fi
# Assign role.
"$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/assign-role.sh
# Install dependencies.
AZUREKMS_SRC="$DRIVERS_TOOLS/.evergreen/csfle/azurekms/remote-scripts/setup-azure-vm.sh" \
AZUREKMS_DST="./" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_CMD="./setup-azure-vm.sh" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh
# Ship this checkout so the VM runs the same revision that provisioned it. On
# failure start-mongodb.sh falls back to cloning the default branch, so this must
# not abort the task.
AZUREKMS_ARCHIVE_DIR=$(mktemp -d)
if bash "$DRIVERS_TOOLS"/.evergreen/make-drivers-tools-archive.sh "$AZUREKMS_ARCHIVE_DIR/drivers-evergreen-tools.tgz"; then
    AZUREKMS_SRC="$AZUREKMS_ARCHIVE_DIR/drivers-evergreen-tools.tgz" \
    AZUREKMS_DST="./" \
        "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
else
    echo "WARNING: could not archive $DRIVERS_TOOLS; the VM will clone the default branch, which may not match this checkout."
fi
rm -rf "$AZUREKMS_ARCHIVE_DIR"

# Start mongodb.
AZUREKMS_SRC="$DRIVERS_TOOLS/.evergreen/csfle/azurekms/remote-scripts/start-mongodb.sh" \
AZUREKMS_DST="./" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/copy-file.sh
AZUREKMS_CMD="./start-mongodb.sh" \
    "$DRIVERS_TOOLS"/.evergreen/csfle/azurekms/run-command.sh

popd
