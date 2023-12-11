# Drivers Evergreen Tools Dockerfile

The `Dockerfile` and scripts can be used to run a local server in docker container.

Additionally, you can build a Docker [container](#driver-testing-using-this-docker-container)
for your Driver that shares the binary files and communicates with this container.

You will need Docker (or podman aliased to Docker) installed and running
locally.

# Run Local Server

To run a local server, change to this directory and run:

```bash
bash ./run-server.sh
```

This will build the docker image and run it with appropriate settings.
Note that any of the environment variables used by `run-orchestration`
will be passed through to the container.
The appropriate port(s) will be exposed, allowing you to run local test against
the running docker container.

The default image can be overridden with `IMAGE`, and the entrypoint with `ENTRYPOINT`.
To use a specific architecture, use `PLATFORM`, e.g. `--platform linux/amd64`.

The script also supports the standard environment variables used in mongo-orchestration:

```
AUTH
SSL
TOPOLOGY
LOAD_BALANCER
STORAGE_ENGINE
REQUIRE_API_VERSION
DISABLE_TEST_COMMANDS
MONGODB_VERSION
MONGODB_DOWNLOAD_URL
ORCHESTRATION_FILE
```

## Driver Testing using this Docker container

First, start this container with the appropriate environment variables, running as:

```bash
bash ./run-server.sh
```

You may wish to launch other services at this point, like a load balancer or the
csfle KMIP server.

To launch your driver's Dockerfile, prep the necessary environment variables
and args, and run:

```bash
$DRIVERS_TOOLS/.evergreen/docker/run-client.sh $ARGS
```

You'll have the following env variables available in your container by default.

```
AUTH
SSL
TOPOLOGY
MONGODB_VERSION
MONGODB_BINARIES
CRYPT_SHARED_LIB_PATH
ORCHESTRATION_FILE
SKIP_CRYPT_SHARED_LIB
DRIVERS_TOOLS
```

In the entry point of your container, ensure to run the following to add the
crypt shared and other binaries to your PATH:

```bash
export PATH="$MONGODB_BINARIES:$PATH"
```
