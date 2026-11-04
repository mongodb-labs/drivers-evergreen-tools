# EKS Cluster Management

Scripts to manage a drivers test cluster on AWS.

## Cluster Management

These steps must be done by an account with admin access (one time):

1. Run `setup-cluster.sh`
   - The cluster, the iamserviceaccount, the IAM role, and the node groups'
     launch templates are tagged
     `mongodb-owner=client-libraries-managers@mongodb.com`, `mongodb-env=dev`.
     Override with `MONGODB_OWNER_TAG`/`MONGODB_ENV_TAG`. Set `VERIFY_MONGODB_TAGS=1`
     to verify after creation. The launch templates need tagging from the
     script: the cluster's `--tags` does not reach them (eksctl creates its
     starter template untagged, and EKS creates its generated copy with only
     EKS's own service tags).
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

## Tag Verification

Run `verify-eks-setup.sh` against an existing cluster — with the cluster's
credentials, exporting `EKS_CLUSTER_NAME`, `EKS_REGION`, and
`EKS_IAM_ROLE_NAME`, or with none of them set so it reads the eks vault — to
re-check that the cluster, the IAM role, and every node group launch template
still carry the policy tags. It exits non-zero naming the first resource
found lacking them.

## Usage

These steps can be run using the drivers test secrets role:

1. Run `setup.sh`
2. Run the desired tests in the pod.
3. Run `teardown.sh`
