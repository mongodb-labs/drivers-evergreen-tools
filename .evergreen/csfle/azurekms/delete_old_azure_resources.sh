#!/usr/bin/env bash

# Delete old Azure Virtual Machines and related orphaned resources.

set -o errexit
set -o nounset

# Get absolute path to drivers-evergreen-tools:
{
    SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
    . "$SCRIPT_DIR/../../handle-paths.sh"
}

# Create virtualenv with Azure dependencies installed:
{
    . "$DRIVERS_TOOLS/.evergreen/venv-utils.sh"
    if [[ -d azure_deletion_venv ]]; then
        venvactivate azure_deletion_venv
    else
        . "$DRIVERS_TOOLS/.evergreen/find-python3.sh"
        PYTHON=$(ensure_python3)
        echo "Creating virtual environment 'azure_deletion_venv'..."
        venvcreate "${PYTHON:?}" azure_deletion_venv
        pythom -m pip install requirements.txt
        echo "Creating virtual environment 'azure_deletion_venv'... done."
    fi
}

# Delete resources for Azure KMS testing (DRIVERS-2411):
{
    "$DRIVERS_TOOLS/.evergreen/secrets_handling/setup-secrets.sh" drivers/azurekms
    # shellcheck source=/dev/null
    source secrets-export.sh
    export AZURE_SUBSCRIPTION_ID="$AZUREKMS_SUBSCRIPTION"
    export AZURE_RESOURCE_GROUP="$AZUREKMS_RESOURCEGROUP"
    export AZURE_CLIENT_SECRET="$AZUREKMS_SECRET"
    export AZURE_CLIENT_ID="$AZUREKMS_CLIENTID"
    export AZURE_TENANT_ID="$AZUREKMS_TENANTID"
    python "$DRIVERS_TOOLS/.evergreen/csfle/azurekms/delete_old_azure_resources.py"
    rm secrets-export.sh
}

# Delete resources for Azure OIDC testing (DRIVERS-2415):
{
    "$DRIVERS_TOOLS/.evergreen/secrets_handling/setup-secrets.sh" drivers/azureoidc
    # shellcheck source=/dev/null
    source secrets-export.sh
    export AZURE_SUBSCRIPTION_ID="$AZUREOIDC_SUBSCRIPTION"
    export AZURE_RESOURCE_GROUP="$AZUREOIDC_RESOURCEGROUP"
    export AZURE_CLIENT_SECRET="$AZUREOIDC_SECRET"
    export AZURE_CLIENT_ID="$AZUREOIDC_CLIENTID"
    export AZURE_TENANT_ID="$AZUREOIDC_TENANTID"
    python "$DRIVERS_TOOLS/.evergreen/csfle/azurekms/delete_old_azure_resources.py"
    rm secrets-export.sh
}
