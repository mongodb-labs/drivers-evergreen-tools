# Serverless Scripts

The scripts in this directory are used to test MongoDB Serverless instances on Atlas.

## Prequisites

Set up your environment to obtain secrets from the Drivers [AWS Vault](https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets).

## Usage

First, get the appropriate secrets from the vault using:

```bash
bash $DRIVERS_TOOLS/.evergreen/serverless/setup-secrets.sh
```

If targeting the dev version of Serverless, use:

```bash
$DRIVERS_TOOLS/.evergreen/serverless/setup-secrets.sh serverless-next
```

Next, start the cluster with:

```bash
bash ${DRIVERS_TOOLS}/.evergreen/serverless/create-instance.sh
```

Make sure you shut down the instance with:

```bash
bash ${DRIVERS_TOOLS}/.evergreen/serverless/delete-instance.sh
```

A full Evergreen task group might look like:

```yaml
  - name: serverless_task_group
    setup_group_can_fail_task: true
    setup_group_timeout_secs: 1800 # 30 minutes
    setup_group:
      - func: "fetch source"
      - func: "prepare resources"
      - command: shell.exec
        params:
          shell: "bash"
          script: |
            ${PREPARE_SHELL}
            bash ${DRIVERS_TOOLS}/.evergreen/serverless/setup-secrets.sh
            bash ${DRIVERS_TOOLS}/.evergreen/serverless/create-instance.sh
      - command: expansions.update
        params:
          file: serverless-expansion.yml
    teardown_group:
      - command: shell.exec
        params:
          script: |
            ${PREPARE_SHELL}
            bash ${DRIVERS_TOOLS}/.evergreen/serverless/delete-instance.sh
      - func: "upload test results"
    tasks:
      - ".serverless"
```