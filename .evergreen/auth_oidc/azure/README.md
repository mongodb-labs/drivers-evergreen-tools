# Azure OIDC Testing

Testing OIDC with Azure integration involves launching an Azure VM,
pushing the code to the VM, running the OIDC tests for the driver,
and then tearing down the VM and its resources.

## Background

There are a set of scripts that facilitate these operations.
They build on top of the scripts used in `csfle/azurekms`.

See [Secrets Handling](../secrets_handling/README.md) for details on how the script accesses the `drivers/azureoidc` vault.
These secrets are used to log in to Azure, and the rest of the secrets are fetched from the "OIDC-Key-Vault" in our Drivers Azure Subscription (https://portal.azure.com/#home).

See the Azure machine flows section of the OIDC Configuration [wiki](https://wiki.corp.mongodb.com/display/ENG/OIDC+Configuration#OIDCConfiguration-ServiceAccounts/ManagedIdentities/MachineFlows) for more information
about the Azure integration.

## Prerequisites

First, ensure you are running either locally or on an Evergreen host
that has the Azure CLI 2.25+ installed.  At time of writing, distros with `az` installed include:

- debian10
- debian11
- ubuntu2004
- ubuntu2204

Locally, it can be installed as `brew install az`.

## Usage

To ensure proper setup and teardown, we use a task group in Evergreen config.  The setup portion
should run the equivalent of the following, substituting your driver name:

```bash
export AZUREOIDC_VMNAME_PREFIX="PYTHON_DRIVER"
$DRIVERS_TOOLS/.evergreen/auth_oidc/azure/setup.sh
```

This script can be run locally or in CI.  The script also runs a self-test on the VM using the Python driver.

Next, compile/build and bundle our driver and test code, and run the test:

```bash
# Prep the source tarball - first make sure the patch changes are committed before using `git archive`.
git add .
git commit -m "add files"
export AZUREOIDC_DRIVERS_TAR_FILE=/tmp/mongo-python-driver.tgz
git archive -o $AZUREOIDC_DRIVERS_TAR_FILE HEAD
# Define the command to run on the VM.
# Ensure that we source the environment file created for us, set up any other variables we need,
# and then run our test suite on the vm.
export AZUREOIDC_TEST_CMD="source ./secrets-export.sh && OIDC_ENV=azure ./.evergreen/run-mongodb-oidc-test.sh"
bash $DRIVERS_TOOLS/.evergreen/auth_oidc/azure/run-driver-test.sh
```

In your tests, you can use the environment variables in `secrets-export.sh` to define the `username` and `TOKEN_RESOURCE`
auth mechanism property, e.g.

```python
username=os.environ["AZUREOIDC_USERNAME"]
TOKEN_RESOURCE=os.environ["AZUREOIDC_RESOURCE"]
```

The full set of variables available is:

```bash
OIDC_TOKEN_DIR      # The directory containing the token files
OIDC_TOKEN_FILE     # The default token file for use with Workload (machine) callbacks
MONGODB_URI         # The base, admin URI
MONGODB_URI_SINGLE  # The URI with the Workload Provider
OIDC_ADMIN_USER     # The username and password for use with an admin connection
OIDC_ADMIN_PWD
AZUREOIDC_RESOURCE  # The resource to request for the token
AZUREOIDC_USERNAME  # The username, which is the client_id for the identity on the VM
OIDC_TOKEN_DIR      # The directory containing the token files
OIDC_TOKEN_FILE     # The default token file for use with Workload callbacks
```

Finally, we tear down the vm:

```bash
$DRIVERS_TOOLS/.evergreen/auth_oidc/azure/delete-vm.sh
```

An example task group would look like:

```yaml
- name: testazureoidc_task_group
  setup_group_can_fail_task: true
  setup_group_timeout_secs: 1800
  teardown_group_can_fail_task: true
  teardown_group_timeout_secs: 1800
  setup_group:
    - func: fetch source
    - func: other setup function
    - command: shell.exec
    params:
        shell: bash
        script: |-
        set -o errexit
        ${PREPARE_SHELL}
        export AZUREOIDC_VMNAME_PREFIX="PYTHON_DRIVER"
        $DRIVERS_TOOLS/.evergreen/auth_oidc/azure/setup.sh
  teardown_task:
    - command: subprocess.exec
      params:
        binary: bash
        args:
          - ${DRIVERS_TOOLS}/.evergreen/auth_oidc/azure/teardown.sh
    - func: other teardown function
  tasks:
    - oidc-auth-test-azure-latest
```

### Environment Variables

Below is an explananion of the environment variables stored in the Azure key vault.

- AZUREOIDC_AUTHPREFIX - The auth prefix used for DB user and role names.
- AZUREOIDC_AUTHCLAIM - The object ID of the Azure Group, used in the DB role name.
- AZUREOIDC_USERNAME - The Object (principal) ID of the Azure Manager Identity, used for the `username`.
- AZUREOIDC_RESOURCE - The escaped Application ID URI to use in the `TOKEN_RESOURCE` auth mechanism property.
- AZUREOIDC_CLIENTID - The client ID of the Azure App registration, used to generate the unescaped Application ID URI.
- AZUREOIDC_TENANTID - The tenant ID of the Azure App registration, used to derive the `issuer` URI.
- AZUREKMS_IDENTITY - A space separated string with the Resource ID of the managed identity (`/subscriptions/...`).  Used to assign the identity to the VM.
- AZUREOIDC_RESOURCEGROUP - The name of the Azure Resource Group, used when accessing the VM through the CLI.
