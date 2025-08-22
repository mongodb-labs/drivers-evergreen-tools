# This Repository is NOT a supported MongoDB product

## drivers-evergreen-tools

This repo is meant for MongoDB drivers to bootstrap their Evergreen
configuration files.
It contains set of scripts for tasks that most drivers will need to perform,
such as downloading MongoDB for the current platform, and launching various
topologies.

## Using In Evergreen

The bundled [`.evergreen/config.yml`](.evergreen/config.yml) file contains a
suggested template for drivers to use.
This file can either be taken and used as is, or used as a recipe to copy&paste from.

It is recommended to copy the entire directory and modify the following scripts:
- [`install-dependencies.sh`](.evergreen/install-dependencies.sh) - Install any platform dependencies not currently available on Evergreen
- [`run-tests.sh`](.evergreen/run-tests.sh) - How to run the test suite
- [`compile.sh`](.evergreen/compile.sh) - Configure any alternative environment routes
- [`compile-unix.sh`](.evergreen/compile-unix.sh) - Instructions to run the compile stage on *nix
- [`compile-windows.sh`](.evergreen/compile-windows.sh) - Instructions to run the compile stage on Windows
- [`make-docs.sh`](.evergreen/make-docs.sh) - Instructions how to compile the driver docs
- [`make-release.sh`](.evergreen/make-release.sh) - Instructions how to package and release the driver


The normal matrix (e.g. all tasks with the exception on those in the `** Release Archive Creator` buildvariant) runs the following two shell scripts:
- The `install-dependencies.sh` file is always executed by all tasks.
- The `run-tests.sh` is run by all tasks, except for the `** Release Archive Creator`.

The `** Release Archive Creator` buildvariant is special, and does not run the "standard test matrix", but in stead runs the following:
- The `compile*.sh` is executed by the `release-compile` and `release-compile-cmake` tasks. These are no commonly used by drivers, so feel free to ignore.
- The `make-docs.sh` is executed by the `make-docs` task
- The `make-release.sh` is executed by the `make-release-archive` task


See also:
https://evergreen.mongodb.com/waterfall/drivers-tools

## Using With GitHub Actions

This repository includes a metadata file for GitHub Actions to allow downloading
MongoDB and launching topologies from a GitHub Action Workflow. To use this
action, use the following template:

```yaml
    steps:
      # [...]
      - id: setup-mongodb
        uses: mongodb-labs/drivers-evergreen-tools@master
        # Set configuration
        with:
          version: ${{ matrix.mongodb-version }}
```

The following inputs exist:

| Name | Description |
| --- | --- |
| `version` | MongoDB version to install |
| `topology` | Topology of the deployment (server, replica_set, sharded_cluster) |
| `auth` | Whether to enable auth |
| `ssl` | Whether to enable SSL |
| `storage-engine` | Storage engine to use |
| `require-api-version` | Whether to start the server with requireApiVersion enabled (defaults to false) |

These correspond to the respective environment variables that are passed to `run-orchestration.sh`.

After the cluster is started, its URI is exposed via the `cluster-uri` output. In addition, the action also exposes the
path to `crypt_shared` via the `crypt-shared-lib-path` output, unless the installation was not requested or failed.
This configuration snippet environment variables with the cluster URI and `crypt_shared` lib path
returned from the `setup-mongodb` workflow step when running tests:
```yaml
    steps:
      # [...]
      - name: "Run Tests"
        run: "run-tests.sh"
        env:
          MONGODB_URI: ${{ steps.setup-mongodb.outputs.cluster-uri }}
          CRYPT_SHARED_LIB_PATH: ${{ steps.setup-mongodb.outputs.crypt-shared-lib-path }}
```

### Starting and Stopping Servers Locally or on an Evergreen Host

There are two options for running a MongoDB server configuration.
One is to use [docker](./.evergreen/docker/README.md).
The other is to run `./evergreen/run-orchestration.sh` locally.
For convenience, you can run `make run-server` and `make stop-server` to start and stop the server(s).

For example:

```bash
TOPOLOGY=replica_set MONGODB_VERSION=7.0 make run-server
```

You can also run:  `make run-local-atlas` to run a local atlas server in a container.

See (run-orchestration.sh)[./evergreen/run-orchestration.sh] for the available environment variables.
Run `bash ./evergreen/run-orchestration.sh --help` for usage of command line flags.

In order to use custom certificates in your server, set the following environment variables:

```bash
export TLS_CERT_KEY_FILE=<path-to>/client.pem
export TLS_PEM_KEY_FILE=<path-to>/server.pem
export TLS_CA_FILE=<path-to>/ca.pem
```

### Manual use of start-orchestration

The (start-orchestration.sh)[./evergreen/start-orchestration.sh] script can be used directly as a way to
start the orchestration server without downloading binaries or starting a local server.
You are still responsible for having a directory containing the MongoDB binaries in the default
MONGODB_BINARIES folder or setting MONGODB_BINARIES to the appropriate folder.

See (run-orchestration.sh)[./evergreen/run-orchestration.sh] for the available environment variables.

Run `bash ./evergreen/start-orchestration.sh --help` for usage of command line flags.

## Linters and Formatters

This repo uses [pre-commit](https://pre-commit.com/) for managing linting and formatting of the codebase.
`pre-commit` performs various checks on all files in the repo and uses tools that help follow a consistent code
style.

To set up `pre-commit` locally, run:

```bash
brew install pre-commit
pre-commit install
```

To run pre-commit manually, run:

```bash
pre-commit run --all-files
```

To run an individual hook like `shellcheck` manually, run:

```bash
pre-commit run --all-files shellcheck
```

## Setup and Teardown

For convenience, there are two scripts that can be used for setup and teardown of assets and services
used by `drivers-evergreen-tools`.

`$DRIVERS_TOOLS/.evergreen/setup-test.sh` will handle common setup actions that have previously
been spread through multiple `pre:` tasks in drivers.

`$DRIVERS_TOOLS/.evergreen/teardown-test.sh` will clean up common assets and services.
This script will also collect all logs files recursively found in the `${DRIVERS_TOOLS}` directory into a single `${DRIVERS_TOOLS}/.evergreen/test_logs.tar.gz` file
for convenient uploading.

Subfolders that have setup and teardown requirements are encouraged to also provide
`setup-test.sh` and `teardown-test.sh`.

NOTE: The subfolder setup/teardown scripts requires users to have configured
support for [Secrets Handling](./.evergreen/secrets_handling/README.md).


## Secrets Handling

See the Secrets Handling [readme](./.evergreen/secrets_handling/README.md) for more information on how secrets are managed
locally and on on Evergreen.

# Python CLIs

We make some of our Python scripts available as self-contained clis that do not require setting up a Python
virtual environment.  For example, after running `.evergreen/setup.sh` you can run the resulting `.evergreen/mongodl`,
`.evergreen/mongosh-dl` and `.evergreen/socks5srv` scripts directly.

## Env Files

This repo supports the use of `.env` files, which can be placed in `$DRIVERS_TOOLS` and in the sub-directories.
The script will first read `$DRIVERS_TOOLS/.env` if it exists, and then `$SCRIPT_DIR/.env` if it exists, to give
the local file higher precedence.  This pattern can be used to replace the use of legacy `${PREPARE_SHELL}`
invocations in a  `shell.exec` Evergreen command, enabling the use of `subprocess.exec` instead.

## evergreen_config_generator

This repo also contains a Python package for use in scripts that generate
Evergreen config files from Python dicts. See evergreen_config_generator/README.
