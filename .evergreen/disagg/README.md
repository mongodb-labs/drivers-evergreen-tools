# Disaggregated storage (DSC) test deployments

Scripts to start a deployment of DSC mongods backed by the SLS storage layer, using `slslocal --compose`, and to run
driver tests against it.

All server-side components (the SLS services, localstack and the mongods) run as containers pulled from a private ECR
registry. The host needs an x86_64 Linux machine with Docker, the `aws` CLI, `python3` and `sudo`.

## Scripts

- [`setup.sh`](setup.sh): pulls the `slslocal` image, launches the deployment (a three-member replica set across
    three cells) and waits for it to become healthy. Writes `dsc-expansion.yml` with `MONGODB_URI` to the working
    directory.
- [`teardown.sh`](teardown.sh): writes the deployment's logs to `sls-logs.txt.gz` in the working directory and
    destroys it. Does nothing if no deployment was started.
- [`download-crypt.sh`](download-crypt.sh): downloads `crypt_shared` for client-side encryption tests,
    without starting a server. Writes `crypt-shared-expansion.yml` with `CRYPT_SHARED_LIB_PATH`.

`setup.sh` takes these environment variables:

| Variable         | Description                                                                           |
| ---------------- | ------------------------------------------------------------------------------------- |
| `DSC_SLS_TAG`    | SLS image tag. Default: the newest mainline tag. Pinning a known-good tag is advised. |
| `DSC_MONGOD_TAG` | mongod image tag. Default: the one pinned by `slslocal`.                              |
| `AWS_*`          | Credentials with pull access to the SLS ECR repositories (see below).                 |

## Networking

The replica set members advertise names like `shard1-node0-mongod:<port>`, which resolve only inside the containers.
Their ports are published on the host. `setup.sh` maps the names to `127.0.0.1` in `/etc/hosts` so that replica set
discovery works from the host, and the URI it writes is seeded with those names. The line is tagged with a
`# dsc-evergreen` comment, and `teardown.sh` removes it.

## Integration with Evergreen

The ECR images require assuming `arn:aws:iam::664315256653:role/disagg-storage-tf-project-ro`. The Evergreen project
must be allowed to assume that role.

```yaml
functions:
  "start dsc":
    - command: ec2.assume_role
      params:
        role_arn: arn:aws:iam::664315256653:role/disagg-storage-tf-project-ro
    - command: subprocess.exec
      params:
        working_dir: src
        binary: bash
        include_expansions_in_env: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN]
        args:
          - ${DRIVERS_TOOLS}/.evergreen/disagg/setup.sh
    - command: expansions.update
      params:
        file: src/dsc-expansion.yml
  "stop dsc":
    - command: subprocess.exec
      params:
        working_dir: src
        binary: bash
        args:
          - ${DRIVERS_TOOLS}/.evergreen/disagg/teardown.sh
```

Include the `"stop dsc"` function in `post` or a `teardown_task` section so the deployment is destroyed and the
`/etc/hosts` entry removed when the task ends. Upload `src/sls-logs.txt.gz` afterwards to keep the deployment's logs.

Downloading `crypt_shared` for the `latest` version requires AWS credentials (see DRIVERS-3628).
