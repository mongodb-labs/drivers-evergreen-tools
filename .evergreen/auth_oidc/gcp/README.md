# GCP OIDC Testing

Testing OIDC with GCP integration involves launching a GCP VM,
pushing the code to the VM, running the OIDC tests for the driver,
and then tearing down the VM and its resources.

## Background

There are a set of scripts that facilitate these operations.
They build on top of the scripts used in `csfle/gcpkms`.

See https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets for more background
on how the secrets are managed for these tests.  These secrets are used to log in to Azure, and the 
rest of the secrets are fetched from the "OIDC-Key-Vault" in our Drivers Azure Subscription (https://portal.azure.com/#home).

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
$DRIVERS_TOOLS/.evergreen/auth_oidc/azure/create-and-setup-vm.sh
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
export AZUREOIDC_TEST_CMD="source ./env.sh && OIDC_PROVIDER_NAME=azure ./.evergreen/run-mongodb-oidc-test.sh"
bash $DRIVERS_TOOLS/.evergreen/auth_oidc/azure/run-driver-test.sh
```

In your tests, you can use the environment variables in `env.sh` to define the `username` and `TOKEN_AUDIENCE` 
auth mechanism property, e.g.

```python
username=os.environ["AZUREOIDC_USERNAME"]
TOKEN_AUDIENCE=os.environ["AZUREOIDC_AUDIENCE"]
```

Finally, we tear down the vm:

```bash
$DRIVERS_TOOLS/.evergreen/auth_oidc/azure/delete-vm.sh
```

An example task group would look like:

```yaml
- name: testazureoidc_task_group
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
        $DRIVERS_TOOLS/.evergreen/auth_oidc/azure/create-and-setup-vm.sh
  teardown_task:
    - command: shell.exec
      params:
        shell: bash
        script: |-
        ${PREPARE_SHELL}
        $DRIVERS_TOOLS/.evergreen/auth_oidc/azure/delete-vm.sh
  setup_group_can_fail_task: true
  setup_group_timeout_secs: 1800
  tasks:
    - oidc-auth-test-azure-latest
```

### Environment Variables

Below is an explanantion of the environment variables stored in the Azure key vault.

- AZUREOIDC_AUTHPREFIX - The auth prefix used for DB user and role names.
- AZUREOIDC_AUTHCLAIM - The object ID of the Azure Group, used in the DB role name.
- AZUREOIDC_USERNAME - The Object (principal) ID of the Azure Manager Identity, used for the `username`.
- AZUREOIDC_AUDIENCE - The escaped Application ID URI to use in the `TOKEN_AUDIENCE` auth mechanism property.
- AZUREOIDC_CLIENTID - The client ID of the Azure App registration, used to generate the unescaped Application ID URI.
- AZUREOIDC_TENANTID - The tenant ID of the Azure App registration, used to derive the `issuer` URI.
- AZUREKMS_IDENTITY - A space separated string with the Resource ID of the managed identity (`/subscriptions/...`).  Used to assign the identity to the VM.
- AZUREOIDC_RESOURCEGROUP - The name of the Azure Resource Group, used when accessing the VM through the CLI.
