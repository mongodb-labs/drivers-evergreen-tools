# This Repository is NOT a supported MongoDB product

# drivers-evergreen-tools

This repo is meant for MongoDB drivers to bootstrap their Evergreen
configuration files.
It contains set of scripts for tasks that most drivers will need to perform,
such as downloading MongoDB for the current platform, and launching various
topologies.

# Using

## In Evergreen

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

## evergreen_config_generator

This repo also contains a Python package for use in scripts that generate
Evergreen config files from Python dicts. See evergreen_config_generator/README.

# Using With GitHub Actions

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
