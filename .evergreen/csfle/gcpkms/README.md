Scripts in this directory can be used to run driver CSFLE tests on a remote Google Compute Engine (GCE) instance.

The expected flow is:

- Create a GCE instance.
- Setup the GCE instance. Install dependencies and run a MongoDB server.
- Copy driver test files to the GCE instance.
- Run driver tests on the GCE instance.
- Delete the GCE instance.

The included mock_server may be useful for local development. It simulates a [Metadata Server](https://cloud.google.com/compute/docs/access/create-enable-service-accounts-for-instances#applications).

# Usage with AWS Vault

See [Secrets Handling](../secrets_handling/README.md) for details on how to access the secrets
from the `drivers/gcpkms` vault.

```yaml
- name: testgcpkms_task_group
  setup_group_can_fail_task: true
  setup_group_timeout_secs: 1800
  teardown_group_can_fail_task: true
  teardown_group_timeout_secs: 1800
  setup_group:
      - func: fetch source
      - func: prepare resources
      - command: subprocess.exec
        params:
          binary: bash
          args:
            - ${DRIVERS_TOOLS}/.evergreen/csfle/gcpkms/setup.sh
  teardown_group:
      - command: subprocess.exec
        params:
          binary: bash
          args:
            - ${DRIVERS_TOOLS}/.evergreen/csfle/gcpkms/teardown.sh
      - func: "upload test results"
  tasks:
  - testgcpkms-task
```

And your task should include a script that does something like:

```bash
source $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/secrets-export.sh
tar czf /tmp/mongo-python-driver.tgz .
GCPKMS_SRC=/tmp/mongo-python-driver.tgz GCPKMS_DST=$GCPKMS_INSTANCENAME: $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/copy-file.sh
echo "Copying files ... end"
echo "Untarring file ... begin"
GCPKMS_CMD="tar xf mongo-python-driver.tgz" $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/run-command.sh
echo "Untarring file ... end"
GCPKMS_CMD="SUCCESS=true TEST_FLE_GCP_AUTO=1 ./.evergreen/tox.sh -m test-eg" $DRIVERS_TOOLS/.evergreen/csfle/gcpkms/run-command.sh
```
