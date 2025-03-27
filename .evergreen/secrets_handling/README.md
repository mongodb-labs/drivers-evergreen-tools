# Secrets Handling

This folder has a script that can be used to access the drivers AWS Vaults, see
[Using AWS Secrets Manager to Store Testing Secrets wiki](https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets) for more information.

Many of the sibling folders like `csfle` have their own `setup-secrets.sh` script that should be used
to ensure the proper secrets are written to that folder for local usage.

NOTE: Add `secrets-export.sh` to your `.gitignore` to prevent checking in credentials in your repo,
since some of the scripts (including `csfle`) will copy the `secrets-export.sh` to your repo.

The `setup-secrets.sh` script in this folder can be used for other vaults such as `drivers/enterprise_auth` or
`drivers/atlas_connect`.  A full list of vaults and their usages is as follows:

| Vault                     | Usage |
| -----                     | ------|
| drivers/adl               | Used in [`atlas_data_lake`](../atlas_data_lake/README.md) for Atlas Data Lake testing. |
| drivers/atlas             | Can be manually used in conjunction with [`atlas`](../atlas/README.md) to launch an atlas cluster in the prod environment. |
| drivers/atlas-dev         | Used in [`atlas`](../atlas/README.md) to launch an atlas cluster in the dev environment. |
| drivers/atlas-qa         | Used in [`atlas`](../atlas/README.md) to launch an atlas cluster in the qa environment. |
| drivers/atlas_connect     | Has the URIs used in the Atlas Connect Drivers tests. |
| drivers/aws_auth          | Used in [`auth_aws`](../auth_aws/README.md)  for AWS Auth testing. |
| drives/azurekms           | Used in [`csfle/azurekms`](../csfle/azurekms/README.md) for Azure KMS testing. |
| drivers/azure_oidc        | Used in [`auth_oidc/azure`](../auth_oidc/azure/README.md) for OIDC Testing on Azure. |
| drivers/comment-bot       | Used in [`github_app`](../github_app/README.md) for the DBX Comment bot. |
| drivers/csfle             | Used in [`cslfe`](../csfle/README.md) for encryption related tests. |
| drivers/enterprise_auth   | Has the creds needed for Enterprise Auth testing. |
| drivers/gcpkms            | Used in [`cslfe/gcpkms`](../csfle/gcpkms/README.md) for GCP KMS testing. |
| drivers/gcpoidc           | Used in [`auth_oidc/gcp`](../auth_oidc/gcp/README.md) for OIDC Testing on GCP. |
| drivers/oidc              | Used in [`oidc`](../oidc/README.md) for OIDC Auth testing. |
| drivers/serverless        | Used in [`serverless`](../serverless/README.md) for serverless testing. |
| drivers/serverless_next   | Used in [`serverless`](../serverless/README.md) for serverless proxy testing. |

## Evergreen Secrets Handling

If using a Linux host on Evergreen, the shorthand version of the script can be used to get the credentials, e.g.

```yaml
- command: subprocess.exec
  params:
    working_dir: src
    binary: bash
    args:
      - ${DRIVERS_TOOLS}/.evergreen/atlas/setup-secrets.sh
```

If using one of the convenience scripts in one of the subfolders, or the following to use the
script in this directory:

```yaml
- command: subprocess.exec
  params:
    working_dir: src
    binary: bash
    args:
      - -c
      - ${DRIVERS_TOOLS}/.evergreen/secrets_handling/setup-secrets.sh drivers/enterprise_auth
```

If using other hosts, the following form should be used:

```yaml
- command: ec2.assume_role
  params:
    role_arn: ${aws_test_secrets_role}
- command: subprocess.exec
  params:
    working_dir: src
    binary: bash
    include_expansions_in_env: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"]
    args:
      - ${DRIVERS_TOOLS}/.evergreen/atlas/setup-secrets.sh
```

## Local Credential Access

Define `AWS_PROFILE` to according to the Wiki instructions for "Setting up Local AWS Credentials".
If your credentials have expired, run the following to refresh:

```bash
aws sso login --profile $AWS_PROFILE
```

Now you can call any of the `setup-secrets.sh` scripts locally.
