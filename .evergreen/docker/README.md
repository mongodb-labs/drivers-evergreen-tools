# Drivers Evergreen Tools Dockerfile

The `Dockerfile` and scripts can be used to run a local server in a container.

Additionally, you can build a [container](#driver-testing-using-this-container)
for your Driver that shares the binary files and communicates with this container.

You will need podman (or Docker) installed and running locally.

# Run Local Server

To run a local server, change to this directory and run:

```bash
bash ./run-server.sh
```

This will build the container image and run it with appropriate settings.
Note that any of the environment variables used by `run-orchestration`
will be passed through to the container.
The appropriate port(s) will be exposed, allowing you to run local test against
the running container.

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

Note that the default `TOPOLOGY` is [`servers`](https://github.com/mongodb-labs/drivers-evergreen-tools/tree/master/.evergreen/orchestration/configs/servers) and the default `ORCHESTRATION_FILE` is `basic.json`. For example, to run a replica using the [auth](https://github.com/mongodb-labs/drivers-evergreen-tools/blob/master/.evergreen/orchestration/configs/replica_sets/auth.json) orchestration:

```bash
TOPOLOGY=replica_set ORCHESTRATION_FILE=auth.json bash ./run-server.sh
```

If you want to test server versions older than 4.4, you can use the rhel8 image, e.g.:

You must also specify `ARCH=amd64` in order to run MongoDB versions older than 4.4 on RHEL8, since `aarch` support
is not available in RHEL8 for those versions.

```bash
ARCH=amd64 TOPOLOGY=sharded_cluster MONGODB_VERSION=4.2 TARGET_IMAGE=rhel8 ./run-server.sh
```

### Get Logs

The orchestration logs can be found using `podman logs`:

```bash
podman logs mongodb
```

The server logs can be found on the container in /tmp, with the scheme `/tmp/mongo-<port>/mongo.log`.
You can pull them locally using `podman cp`:

```bash
podman cp mongodb:/tmp/mongo-27017/mongod.log mongod.log
```

## Driver Testing using this container

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

## Using Rancher

When using [Rancher Desktop](https://rancherdesktop.io/) on Apple Silicon or other ARM-based systems, it's often necessary to specify the amd64 architecture since some dependencies and tools are more reliable or only available for amd64. 

```
ARCH=amd64 MONGODB_VERSION="8.0" TOPOLOGY=replica_set ./run-server.sh  
```
