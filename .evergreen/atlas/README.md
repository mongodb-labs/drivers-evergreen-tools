# Atlas Setup and Teardown Scripts

The scripts in this folder are used to setup and teardown Atlas clusters.

## Prerequisities

See [Secrets Handling](../secrets_handling/README.md) for details on how to access the secrets 
from the `drivers/atlas` vault.

## Usage

It is recommended that you use task group to ensure the cluster is shut down properly.  
An example task group running on a Linux EVG host might look like:

```yaml
- name: test_aws_lambda_task_group
  setup_group:
    - func: fetch source
    - func: prepare resources
    - command: subprocess.exec
      params:
        binary: bash
        args:
          - ${DRIVERS_TOOLS}/.evergreen/atlas/setup-atlas-cluster.sh
    - command: expansions.update
      params:
        # Set MONGODB_URI
        file: atlas-expansion.yml
  teardown_task:
    - command: subprocess.exec
      params:
        working_dir: src
        binary: bash
        args:
          - ${DRIVERS_TOOLS}/.evergreen/atlas/teardown-atlas-cluster.sh
  setup_group_can_fail_task: true
  setup_group_timeout_secs: 1800
  tasks:
    - test-aws-lambda-deployed
```

If other OSes are needed, use the `setup-secrets.sh` script in this directory with the full `ec2.assume_role`
method described in [Secrets Handling](../secrets_handling/README.md).