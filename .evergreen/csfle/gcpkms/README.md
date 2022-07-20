Scripts in this directory can be used to run driver CSFLE tests on a remote Google Compute Engine (GCE) instance.

The expected flow is:

- Create a GCE instance.
- Setup the GCE instance. Install dependencies and run a MongoDB server.
- Copy driver test files to the GCE instance.
- Run driver tests on the GCE instance.
- Delete the GCE instance.

The included mock_server may be useful for local development. It simulates a [Metadata Server](https://cloud.google.com/compute/docs/access/create-enable-service-accounts-for-instances#applications).