# Scripts for OIDC testing

`MONGODB-OIDC` is only supported on Linux, but can be run using docker.  It is recommended to use the
[Local Server](#local-server-testing) during development, so you can access the server logs locally.

### Prerequisites

The `setup.sh` or `start_local_server.sh` scripts will automatically fetch the credentials from the `drivers/oidc` vault.
See [Secrets Handling](../secrets_handling/README.md) for details on how the script accesses the vault.
Add `secrets-export.sh` to your `.gitignore` to prevent checking in credentials in your repo.

The values in the vault are:

```bash
OIDC_ATLAS_USER             # Atlas admin username and password
OIDC_ATLAS_PASSWORD
OIDC_ATLAS_PUBLIC_API_KEY   # The public Atlas API key used to launch clusters
OIDC_ATLAS_PRIVATE_API_KEY
OIDC_ATLAS_GROUP_ID         # The Atlas group used to launch clusters
OIDC_DOMAIN                 # The domain associated with the Workforce Provider in Atlas
OIDC_CLIENT_SECRET          # The client secret used by the IdPs
OIDC_RSA_KEY                # The RSA key used by the IdPs
OIDC_JWKS_URI               # The JWKS URI used by the IdPs
OIDC_ISSUER_1_URI           # The issuer URI for mock IdP 1
OIDC_ISSUER_2_URI           # The issuer URI for mock IdP 2
```

## Usage

Run either `setup.sh` for Atlas clusters or `start_local_server.sh` for a local server (see below).

Both scripts will do the following:

- Fetch secrets
- Configure the cluster
- Generate token files

Once finished, the following variables can be used in your tests by sourcing `secrets-export.sh` in this
folder:

```bash
OIDC_DOMAIN         # The domain associated with the Workforce Provider in Atlas
OIDC_TOKEN_DIR      # The directory containing the token files
OIDC_TOKEN_FILE     # The default token file for use with Workload (machine) callbacks
MONGODB_URI         # The base, admin URI
MONGODB_URI_SINGLE  # The URI with a single Workforce Provider configured, as well as one or more Workload Providers.
                    # The URI will contain the `authMechanism` parameter.
MONGODB_URI_MULTI   # The URI with multiple Workforce Providers configured.  This will only be set if a local
                    # server is launched, as only a single Workforce Provider is allowed on Atlas.
                    # The URI will contain the `authMechanism` parameter.
OIDC_ADMIN_USER     # The username and password for use with an admin connection
OIDC_ADMIN_PWD
```

## Local Server Testing

`MONGODB-OIDC` is only supported on Linux, but we support running locally in
a Docker container.

To run locally, `docker` and `python` must be installed locally (both can be
installed using brew).

Running `./start_local_server.sh` will use docker to launch the server
with the correct configuration, and expose the server on local ports 27017
and 27018.

See [instructions](../docker/README.md#get-logs) for how to get the server logs from the box.

## Evergreen Testing

Running `setup.sh` in this folder will launch an Atlas cluster on all three platforms.
On a Linux EVG host, it will also start a local server that is used for `MONGODB_URI_MULTI`.

To support MacOS hosts, you must first use `ec2.assume_role` to assume the Drivers Secrets role
and set the three AWS variables accordingly.

A full task group will look something like:

```yaml
- name: testoidc_task_group
  setup_group:
    - func: fetch source
    - func: prepare resources
    - func: assume ec2 role
    - command: subprocess.exec
      params:
        binary: bash
        include_expansions_in_env: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"]
        args:
        - ${DRIVERS_TOOLS}/.evergreen/auth_oidc/setup.sh
  teardown_task:
    - command: subprocess.exec
      params:
        binary: bash
        args:
        - ${DRIVERS_TOOLS}/.evergreen/auth_oidc/teardown.sh
  setup_group_can_fail_task: true
  setup_group_timeout_secs: 1800
  tasks:
    - oidc-auth-test
```

## Azure Testing

See the [Azure README](./azure/README.md).
