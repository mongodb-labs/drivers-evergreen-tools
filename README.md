# drivers-evergreen-tools

This repo is meant for MongoDB drivers to bootstrap their Evergreen
configuration files.
It contains set of scripts for tasks that most drivers will need to perfrom,
such as downloading MongoDB for the current platform, and launching various
topologies.

# Installing

git clone this repository in a `pre:` section of your evergreen config file.

# Using

The bundled [`.evergreen/config.yml`](.evergreen/config.yml) file contains a
suggested template for drivers to use.


