# GCP OIDC Testing

Testing OIDC with GCP integration involves launching an Atlas cluster and GCP VM,
pushing the code to the VM, running the OIDC tests for the driver,
and then tearing down the Atlas cluster, and VM and its resources.

## Background

There are a set of scripts that facilitate these operations.
They build on top of the scripts used in `csfle/gcpkms`.

See [Secrets Handling](../secrets_handling/README.md) for details on how the script accesses the `drivers/gcpoidc` vault.

See the [How-To: Set up GCP OIDC Infrastructure](https://wiki.corp.mongodb.com/display/DRIVERS/How-To%3A+Set+up+GCP+OIDC+Infrastructure) wiki for information on how the infrastructure is set up.

## Usage

To ensure proper setup and teardown, we use a task group in Evergreen config.  The setup portion
should run the equivalent of the following, substituting your driver name:

```bash
export GCPOIDC_VMNAME_PREFIX="PYTHON_DRIVER"
$DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/setup.sh
```

This script can be run locally or in CI.  The script also runs a self-test on the VM using the Python driver.

Next, compile/build and bundle our driver and test code, and run the test:

```bash
# Prep the source tarball - first make sure the patch changes are committed before using `git archive`.
git add .
git commit -m "add files"
export GCPOIDC_DRIVERS_TAR_FILE=/tmp/mongo-python-driver.tgz
git archive -o $GCPOIDC_DRIVERS_TAR_FILE HEAD
# Define the command to run on the VM.
# Ensure that we source the environment file created for us, set up any other variables we need,
# and then run our test suite on the vm.
export GCPOIDC_TEST_CMD="source ./env.sh && OIDC_PROVIDER_NAME=gcp ./.evergreen/run-mongodb-oidc-test.sh"
bash $DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/run-driver-test.sh
```

The following variables can be used in your tests by sourcing `$DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/secrets-export.sh`:

```bash
MONGODB_URI         # The base, admin URI
MONGODB_URI_SINGLE  # The OIDC connection string with auth mechanism and properties.
OIDC_ADMIN_USER     # The username and password for use with an admin connection
OIDC_ADMIN_PWD
```

Finally, we tear down the vm:

```bash
$DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/teardown.sh
```

An example task group would look like:

```yaml
- name: testgcpoidc_task_group
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
          export GCPOIDC_VMNAME_PREFIX="PYTHON_DRIVER"
          $DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/setup.sh
  teardown_group:
    - command: subprocess.exec
      params:
        binary: bash
        args:
          - ${DRIVERS_TOOLS}/.evergreen/auth_oidc/gcp/teardown.sh
    - func: other teardown function
  tasks:
    - oidc-auth-test-gcp
```
