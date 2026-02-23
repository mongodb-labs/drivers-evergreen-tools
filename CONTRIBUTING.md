# Contributing Guide

## Server Version Considerations

New server major and minor versions will automatically phased in using `mongodl.py` though
`latest`, `rapid` (for minor releases), and then though stable versions (e.g. `8.0`, `7.2`).
Add explicit tests for each server version and topology to `.evergreen/config.yml` and any
of the test files in `.evergreen/tests` where appropriate.

Support for deprecated server versions can only be removed once all drivers have completed
the relevant DRIVERS ticket.

## Python Considerations

This repository supports CPython 3.9+, and will use either the Python toolchain or the system
python on Evergreen hosts.  See `find_python3.sh` for details on Python binary selection.
The minimum supported version must also be reflected in the `project.requires-python` metadata
in any `pyproject.toml` files in this repository.

We use isolated virtual environments to run all of the python scripts.

### Updating Dependencies

The MongoDB server management scripts under [`.evergreen/orchestration`](https://github.com/mongodb-labs/drivers-evergreen-tools/tree/master/.evergreen/orchestration)
depend on [PyMongo](https://pymongo.readthedocs.io/en/stable/). Package dependencies are pinned by the
[`.evergreen/orchestration/uv.lock`](https://github.com/eramongodb/drivers-evergreen-tools/blob/master/.evergreen/orchestration/uv.lock)
lockfile. When the lockfile is updated, ensure the updated PyMongo version still supports old server versions which are
still in use by downstream projects.

If a [recent release](https://pymongo.readthedocs.io/en/stable/changelog.html) of PyMongo drops support for an old
server version that is still in use by downstream projects, add a dependency override to
[`.evergreen/orchestration/setup.sh`](https://github.com/mongodb-labs/drivers-evergreen-tools/blob/master/.evergreen/orchestration/setup.sh).
Otherwise, an error similar to the following may occur during mongo-orchestration operations (e.g. with server 4.0 and
PyMongo 4.14):

```python
[ERROR] mongo_orchestration.apps:68 - ...
Traceback (most recent call last):
  ...
  File ".../drivers-orchestration/lib/python3.13/site-packages/pymongo/synchronous/topology.py", line 369, in _select_servers_loop
    self._description.check_compatible()
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^
  File ".../drivers-orchestration/lib/python3.13/site-packages/pymongo/topology_description.py", line 168, in check_compatible
    raise ConfigurationError(self._incompatible_err)
pymongo.errors.ConfigurationError: Server at localhost:27017 reports wire version 7, but this version of PyMongo requires at least 8 (MongoDB 4.2).
```

The dependency override may be removed once all downstream projects have also dropped support for the old server version.

## Linters and Formatters

This repo uses [pre-commit](https://pre-commit.com/) for managing linting and formatting of the codebase.
`pre-commit` performs various checks on all files in the repo and uses tools that help follow a consistent code
style.  The python formatting rules are governed by the `ruff.toml` file.

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

## New Features

When adding a new feature to the repo, it should be done as a new folder in `.evergreen`.  It should
contain a README.md with usage instructions, including example Evergreen config where appropriate.

It should also have a test file in `.evergreen/tests` and be run as a dedicated task in this repository.
If it does not use assets like Atlas or a VM, then it should have a "pr" tag so that it runs on PRs.

## Helpful Links

See the [Drivers Cloud Services](https://wiki.corp.mongodb.com/spaces/DRIVERS/pages/473895023/Drivers+Cloud+Services) wiki
for background on our usage of AWS, GCP, and Azure.

See the [Atlas QA Admin](https://wiki.corp.mongodb.com/spaces/DRIVERS/pages/473895025/Atlas+QA+Admin) wiki for background
on our usage of Atlas QA for FaaS Lambda, Search Index, and OIDC testing.

See the [Evergreen Project Configuration](https://docs.devprod.prod.corp.mongodb.com/evergreen/Project-Configuration/) docs
for background on Evergreen project commands and configuration files.

See the [Auth Spec Owner Guide](https://docs.google.com/document/d/1WNSAr2vTGxdi7iA7P0tpmTnIbnKtUD23UpP5Hn_dGNE/edit?tab=t.0#heading=h.vu70wi8bkr9d) for background on the roles and responsibilities of the Authentication Spec Owner.
