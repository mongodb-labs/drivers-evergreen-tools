# Atlas Data Lake Testing

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
