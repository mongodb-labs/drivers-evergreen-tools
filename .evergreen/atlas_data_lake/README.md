# Atlas Data Lake Testing

The files in this directory are required to build and launch a local
`mongohoused` for testing. In the Evergreen configuration file, execute
the following command:

```
sh ${DRIVERS_TOOLS}/.evergreen/atlas_data_lake/run-mongohouse-local.sh
```

`$DRIVERS_TOOLS` is an environment variable set to the root directory
of the clone of the `drivers-evergreen-tools` repository.
