# GKE Cluster Management

Scripts to manage a drivers test cluster on Google Cloud Platform.

## Cluster Management

These steps must be done by an admin (one time):

1. Create a service account
2. Assign Kubernetes Engine Admin permission to the service account
2. Store the secrets in the AWS vault
3. Run `setup-cluster.sh`

## Usage

These steps can be run using the drivers test secrets role:

1. Run `setup.sh`
2. Run the desired tests in the pod.
3. Run `teardown.sh`
