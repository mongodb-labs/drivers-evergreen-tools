# Atlas Data Lake Testing

## Git Checkout

Two scripts in this directory are required to build and launch a local
`mongohoused` for testing. In the Evergreen configuration file, execute
the following command in the foreground to build the server:

```
sh ${DRIVERS_TOOLS}/.evergreen/atlas_data_lake/build-mongohouse-local.sh
```

and the following command in the background to run the server:

```
sh ${DRIVERS_TOOLS}/.evergreen/atlas_data_lake/run-mongohouse-local.sh
```

`$DRIVERS_TOOLS` is an environment variable set to the root directory
of the clone of the `drivers-evergreen-tools` repository.

## Docker Image

Two scripts in this directory are required to pull and run the
`mongohoused` docker image.  In the Evergreen configuration file, execute
the following command in the foreground to build the server:

```
bash ${DRIVERS_TOOLS}/.evergreen/atlas_data_lake/pull-mongohouse-image.sh
```

and the following command in the foreground to run the server:

```
bash ${DRIVERS_TOOLS}/.evergreen/atlas_data_lake/run-mongohouse-image.sh
```

`$DRIVERS_TOOLS` is an environment variable set to the root directory
of the clone of the `drivers-evergreen-tools` repository.
