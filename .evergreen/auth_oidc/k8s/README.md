# OIDC on K8S

Scripts to manage OIDC integration tests on kubernetes: eks, aks, and gke.

## Background

Uses the scripts in `$DRIVERS_TOOLS/.evergreen/k8s` to launch and configure
a kubernetes pod in the given cloud provider, and allows you to run a driver
test on the pod.

## Local Usage

The scripts can be run locally as follows:

```bash
bash setup.sh local  # needs to be done once to set up variables
bash setup-pod.sh aks  # or gke, or eks
bash start-server.sh
bash run-self-test.sh
```

Or if running tests for a specific driver:

```bash
bash setup.sh local  # needs to be done once to set up variables
bash setup-pod.sh aks  # or gke, or eks
bash start-server.sh
pushd $PROJECT_HOME
export K8S_DRIVERS_TAR_FILE=/tmp/driver.tgz
git archive -o $K8S_DRIVERS_TAR_FILE HEAD
export K8S_TEST_CMD="OIDC_PROVIDER_NAME=k8s ./.evergreen/run-mongodb-oidc-test.sh"
popd
bash run-driver-test.sh
```

### Local EKS Testing

Local EKS testing requires assuming a role to interact with the EKS cluster.
See the [Wiki](https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets) for details.


## EVG Usage

The test should use a task group to ensure the resources are cleaned up properly.

```yaml
  - name: test_oidc_k8s_task_group
    setup_group_can_fail_task: true
    setup_group_timeout_secs: 1800
    teardown_task_can_fail_task: true
    teardown_group_timeout_secs: 1800 # 30 minutes
    setup_group:
      - func: fetch source
      - func: prepare resources
      - command: subprocess.exec
        params:
          binary: bash
          args:
            - ${DRIVERS_TOOLS}/.evergreen/auth_oidc/k8s/setup.sh
    teardown_group:
      - command: subprocess.exec
        params:
          binary: bash
          args:
            - ${DRIVERS_TOOLS}/.evergreen/auth_oidc/k8s/teardown.sh
      - func: "teardown assets"
      - func: "upload logs"
      - func: "upload test results"
      - func: "cleanup"
    tasks:
      - test-oidc-k8s
```

And should be run for all three variants:

```yaml
- name: "test-oidc-k8s"
    tags: ["latest", "oidc", "pr"]
    commands:
    - func: "run oidc k8s test"
        vars:
        VARIANT: eks
    - func: "run oidc k8s test"
        vars:
        VARIANT: gke
    - func: "run oidc k8s test"
        vars:
        VARIANT: aks
```

Where the test looks something like:

```yaml
"run oidc k8s test":
- command: ec2.assume_role
params:
    role_arn: ${drivers_test_secrets_role}
- command: shell.exec
    type: test
    params:
    shell: bash
    working-directory: "src"
    include_expansions_in_env: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"]
    script: |-
        set -o errexit
        export K8S_VARIANT=${VARIANT}
        export K8S_DRIVERS_TAR_FILE=/tmp/driver.tgz
        git archive -o $K8S_DRIVERS_TAR_FILE HEAD
        export K8S_TEST_CMD="OIDC_PROVIDER_NAME=k8s ./.evergreen/run-mongodb-oidc-test.sh"
        bash ./.evergreen/auth_oidc/k8s/run-driver-test.sh
```
