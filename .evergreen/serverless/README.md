# Serverless Scripts

The scripts in this directory are used to test MongoDB Serverless instances on Atlas.

Note: This functionality is deprecated and will be removed after DRIVERS-3115 is complete.

## Prerequisites

See [Secrets Handling](../secrets_handling/README.md) for details on how to access the secrets
from the `drivers/serverless` or `drivers/serverless_next` vault.

## Usage

First, get the appropriate secrets from the vault using:

```bash
bash $DRIVERS_TOOLS/.evergreen/serverless/setup-secrets.sh
```

If targeting the proxy version of Serverless, use:

```bash
bash $DRIVERS_TOOLS/.evergreen/serverless/setup-secrets.sh serverless_next
```

Next, start the cluster with:

```bash
bash ${DRIVERS_TOOLS}/.evergreen/serverless/create-instance.sh
```

Make sure you shut down the instance with:

```bash
bash ${DRIVERS_TOOLS}/.evergreen/serverless/delete-instance.sh
```

If running only on a Linux EVG host, the following setup could be used, where `VAULT_NAME`
is `serverless` or `serverless_next`:

```yaml
  - name: serverless_task_group
  setup_group_can_fail_task: true
  setup_group_timeout_secs: 1800
  teardown_group_can_fail_task: true
  teardown_group_timeout_secs: 1800
    setup_group:
      - func: "fetch source"
      - func: "prepare resources"
      - command: ec2.assume_role
        params:
          role_arn: ${aws_test_secrets_role}
      - command: subprocess.exec
        params:
          binary: bash
          include_expansions_in_env: [AWS_SECRET_ACCESS_KEY, AWS_ACCESS_KEY_ID, AWS_SESSION_TOKEN]
          env:
            VAULT_NAME: ${VAULT_NAME}
          args: |
            - ${DRIVERS_TOOLS}/.evergreen/serverless/setup.sh
    teardown_task:
      - command: subprocess.exec
        params:
          binary: bash
          args: |
            - ${DRIVERS_TOOLS}/.evergreen/serverless/teardown.sh
      - func: "upload test results"
    tasks:
      - ".serverless"
```

If other OSes are needed, use the `setup-secrets.sh` script in this directory with the full `ec2.assume_role`
method described in [Secrets Handling](../secrets_handling/README.md).

To access `SERVERLESS_URI` and the secrets values in your serverless task, source the secrets file.

```bash
source ${DRIVERS_TOOLS}/.evergreen/serverless/secrets-export.sh
```
