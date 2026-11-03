# AKS Cluster Management

Scripts to manage a drivers test cluster on Azure.

## Cluster Management

These steps must be done by an account with admin access (one time):

1. Create an App Registration
2. Store the secrets in the AWS vault
3. Run `setup-cluster.sh`

`setup-cluster.sh` tags all resources it creates with
`mongodb-owner=client-libraries-managers@mongodb.com`, `mongodb-env=dev`.
Override with `MONGODB_OWNER_TAG`/`MONGODB_ENV_TAG`. Set `VERIFY_MONGODB_TAGS=1`
to verify after creation.

## Usage

These steps can be run using the drivers test secrets role:

1. Run `setup.sh`
2. Run the desired tests in the pod.
3. Run `teardown.sh`
