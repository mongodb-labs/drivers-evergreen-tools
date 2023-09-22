# Drivers Evergreen Tools Dockerfile

This ``Dockerfile`` and scripts serves dual purposes.

- Run a local server in docker container.
- Extend and run a driver test in a docker container.

You will need Docker (or podman aliased to Docker) installed and running
locally.

# Run Local Server

To run a local server, change to this directory and run:

```bash
bash ./run-local.sh
```

This will build the docker image and run it with appropriate settings.
Note that any of the environment variables used by `run-orchestration`
will be passed through to the container.
The appropriate port(s) will be exposed, allowing you to run local test against
the running docker container.

## Driver Testing in Docker

To extend this image and run against a driver test suite, first build the
image locally.

```bash
docker build -t drivers-evergreen-tools .
```

Then, in your `Dockerfile`, use `FROM drivers-evergreen-tools`.

When running your derived image, use `-v $DRIVERS_TOOLS:/root/drivers-evergreen-tools`
to use the local checkout.

In your entry point script, run `run-orchestration.sh` before running your test suite.
Note that you will probably want to expose the environment variables as is done in `run-local.sh`.
