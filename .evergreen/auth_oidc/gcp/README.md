# GCP OIDC Testing

Testing OIDC with GCP integration involves launching an GCP VM,
pushing the code to the VM, running the OIDC tests for the driver,
and then tearing down the VM and its resources.

## Background

There are a set of scripts that facilitate these operations.
They build on top of the scripts used in `csfle/gcpkms`.

See [Secrets Handling](../secrets_handling/README.md) for details on how the script accesses the `drivers/gcpoidc` vault.

See the "Overview of GCP Infrastructure" section of the GCP OIDC Configuration [wiki](https://wiki.corp.mongodb.com/display/KERNEL/external_auth_oidc_gcp+Evergreen+Test+Suite) for more information about the GCP integration.

## Usage

To ensure proper setup and teardown, we use a task group in Evergreen config.  The setup portion
should run the equivalent of the following, substituting your driver name:

```bash
export GCPOIDC_VMNAME_PREFIX="PYTHON_DRIVER"
$DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/create-and-setup-vm.sh
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

In your tests, you can use the environment variables in `secrets-export.sh` to define the `TOKEN_AUDIENCE`
auth mechanism property, e.g.

```python
TOKEN_AUDIENCE=os.environ["GCPOIDC_AUDIENCE"]
```

Finally, we tear down the vm:

```bash
$DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/delete-vm.sh
```

An example task group would look like:

```yaml
- name: testgcpeoidc_task_group
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
        $DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/create-and-setup-vm.sh
  teardown_task:
    - command: shell.exec
      params:
        shell: bash
        script: |-
        ${PREPARE_SHELL}
        $DRIVERS_TOOLS/.evergreen/auth_oidc/gcp/delete-vm.sh
  setup_group_can_fail_task: true
  setup_group_timeout_secs: 1800
  tasks:
    - oidc-auth-test-gcp-latest
```

### Environment Variables

Below is an explananion of the environment variables used in the test:

- GCPOIDC_AUDIENCE - The value to use in the `TOKEN_AUDIENCE` auth mechanism property.
- GCPOIDC_ATLAS_URI - The URI of the Atlas cluster configured for OIDC GCP testing.
- GCPOIDC_SERVICEACCOUNT - The GCP Service Account to use for GCP access.
- GCPOIDC_KEYFILE_CONTENT - The base64-encoded GCP keyfile content.
- GCPOIDC_MACHINE - The GCE machine type to use for the VM.
