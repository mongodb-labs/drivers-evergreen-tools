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

After the cluster is started, its URI is exposed via the `cluster-uri` output.
This configuration snippet sets an environment variable with the cluster URI
returned from the `setup-mongodb` workflow step when running tests:
```yaml
    steps:
      # [...]
      - name: "Run Tests"
        run: "run-tests.sh"
        env:
          MONGODB_URI: ${{ steps.setup-mongodb.outputs.cluster-uri }}
```

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

`$DRIVERS_TOOLS/.evergreen/teardown-all.sh` will clean up assets and services, including any
that were started in the subfolders, by invoking the `teardown.sh` script in each folder.
Using this script in a `post:` task can remove the need for `task_groups` to ensure that services
are properly torn down.  The script will also consolidate all logs into a single
`${DRIVERS_TOOLS}/.evergreen/test_logs.tar.gz` for convenient uploading.

NOTE: The use of the `teardown.sh` scripts requires first migrating from
EVG project variables to using [Secrets Handling](./.evergreen/secrets_handling/README.md).

## evergreen_config_generator

This repo also contains a Python package for use in scripts that generate
Evergreen config files from Python dicts. See evergreen_config_generator/README.
