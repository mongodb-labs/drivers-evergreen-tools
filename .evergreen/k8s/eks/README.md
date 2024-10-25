# EKS Cluster Management

Scripts to manage a drivers test cluster on AWS.

## Cluster Management

These steps must be done by an account with admin access (one time):

1. Run `setup-cluster.sh`
2. Set up an Access entry for the drivers test secrets role.
   - Go to the cluster on the AWS Console.
   - Click "Access".
   - Click "Create access entry".
   - Use the drivers test secrets role.
   - Give it admin access to the cluster.
3. Store the secrets in the AWS vault.
   - When re-creating the cluster, you must update `K8S_OIDC_ISSUER` in the eks vault
     with the new issuer which can be found in IAM > Identity Providers
     (prepending the Provider with `https://`).
     You must also update the issuer in Atlas cloud-dev.

## Usage

These steps can be run using the drivers test secrets role:

1. Run `setup.sh`
2. Run the desired tests in the pod.
3. Run `teardown.sh`
