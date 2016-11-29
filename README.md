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



See also:
https://evergreen.mongodb.com/waterfall/drivers-tools
