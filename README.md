# This Repository is NOT a supported MongoDB product

# drivers-evergreen-tools

This repo is meant for MongoDB drivers to bootstrap their Evergreen
configuration files.
It contains set of scripts for tasks that most drivers will need to perfrom,
such as downloading MongoDB for the current platform, and launching various
topologies.

# Using

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

# evergreen_config_generator

This repo also contains a Python package for use in scripts that generate
Evergreen config files from Python dicts. See evergreen_config_generator/README.
