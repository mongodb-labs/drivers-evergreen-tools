#!/usr/bin/env bash

# Delete old Azure Virtual Machines and related orphaned resources.

set -o errexit
set -o nounset

# Get absolute path to drivers-evergreen-tools:
{
    SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
    . "$SCRIPT_DIR/../../handle-paths.sh"
}

# Ensure uv is available. The deletion script's dependencies come from the
# azurekms dependency group in the root pyproject.toml:
{
    . "$DRIVERS_TOOLS/.evergreen/ensure-uv.sh"
    ensure_uv || exit 1
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
    uv run --project "$DRIVERS_TOOLS" --group azurekms python "$DRIVERS_TOOLS/.evergreen/csfle/azurekms/delete_old_azure_resources.py"
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
    uv run --project "$DRIVERS_TOOLS" --group azurekms python "$DRIVERS_TOOLS/.evergreen/csfle/azurekms/delete_old_azure_resources.py"
    rm secrets-export.sh
}
