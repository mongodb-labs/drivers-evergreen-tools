# Azure OIDC Testing

Testing OIDC with Azure integration involves launching an Azure VM,
pushing the code to the VM, running the OIDC tests for the driver,
and then tearing down the VM and its resources.

There are a set of scripts that facilitate these operations.
First, ensure you are running either locally or on an Evergreen host
that has the Azure CLI 2.25+ installed.  At time of writing, distros with `az` installed include:

- debian10
- debian11
- ubuntu2004
- ubuntu2204

Locally, it can be installed as `brew install az`.

See https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets for more background
on how the secrets are managed for these tests.
Additionally, there are secrets stored in the "OIDC-Key-Vault" in our Drivers Azure Subscription <TODO, link to the wiki>.

To ensure proper setup and teardown, we use a task group in Evergreen config.  The setup portion 
should run the equivalent of the following, substituting your driver name:

```bash
export AZUREOIDC_VMNAME_PREFIX="PYTHON_DRIVER"
$DRIVERS_TOOLS/.evergreen/auth_oidc/azure/create-and-setup-vm.sh
```

This script can be run locally or in CI.  The script also runs a self-test on the VM using the Python driver.

Next, compile/build and bundle our driver and test code, and run the test:

```bash
# This variable points to the tarball that we will push to the VM and unpack.
export AZUREOIDC_DRIVERS_TAR_FILE=/tmp/mongo-python-driver.tgz
git archive -o $AZUREOIDC_DRIVERS_TAR_FILE HEAD
# Define the command to run on the VM.
# Ensure that we source the environment file created for us, set up any other variables we need,
# and then run our test suite on the vm.
export AZUREOIDC_TEST_CMD="source ./env.sh && OIDC_PROVIDER_NAME=azure ./.evergreen/run-mongodb-oidc-test.sh"
bash $DRIVERS_TOOLS/.evergreen/auth_oidc/azure/run-driver-test.sh
```

In your tests, you can use the environment variables in `env.sh` to define the `TOKEN_AUDIENCE` and `TOKEN_CLIENT_ID` 
auth mechanism properties, e.g.

```python
TOKEN_AUDIENCE="api://" + os.environ["AZUREOIDC_CLIENTID"]
TOKEN_CLIENT_ID=os.environ["AZUREOIDC_TOKENCLIENT"]  # For first user
TOKEN_CLIENT_ID=os.environ["AZUREOIDC_TOKENCLIENT2"]  # For second user
```

Note: If you are creating a uri, you will have to escape `TOKEN_AUDIENCE` value, e.g.

```bash
MONGODB_URI="${MONGODB_URI}/?authMechanism=MONGODB-OIDC"
MONGODB_URI="${MONGODB_URI}&authMechanismProperties=PROVIDER_NAME:azure"
MONGODB_URI="${MONGODB_URI},TOKEN_AUDIENCE:api%3A%2F%2F${AZUREOIDC_CLIENTID}"
```

Finally, we tear down the vm:

```bash
$DRIVERS_TOOLS/.evergreen/auth_oidc/azure/delete-vm.sh
```
