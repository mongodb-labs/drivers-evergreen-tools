# Scripts for In-Use Encryption testing

This folder contains scripts for use with In-Use Encryption.

See the [Azure KMS](./azurekms/README.md) and [GCP KMS](./gcpkms/README.md)
for more information on those specific scenarios.

## Prerequisites

See [Secrets Handling](../secrets_handling/README.md) for details on how to access the secrets 
from the `drivers/csfle` vault.

Add `secrets-export.sh` to your `.gitignore` to prevent checking in credentials in your repo.

## Usage

Set up In-Use Encryption by first fetching the secrets and then launching the kms servers:

```bash
$DRIVERS_TOOLS/.evergreen/csfle/setup-secrets.sh
$DRIVERS_TOOLS/.evergreen/csfle/start-servers.sh
```

The generated `secrets-export.sh` file can be sourced from your `cwd` to get the required credentials for testing.

The following servers will be started:

- Mock KMIP server on port 5698
- KMS HTTP server with an expired cert on port 8000
- KMS HTTP server with an "wrong host" cert on port 8001
- KMS HTTP server with a correct cert on port 8002
- Mock Azure IMDS server on port 8080

When finished, stop the servers by running:

```bash
$DRIVERS_TOOLS/.evergreen/csfle/stop-servers.sh
```

If you are starting your CSFLE servers in a separate Evergreen function, it is recommended that you setup secrets
and start the servers in the background, and then have a separate function that uses `await-servers.sh`
in the foreground to wait for the servers to be ready.  This will ensure the servers are not torn down
between functions (or the function may stall and not finish because there are processes still running).
If you are starting the servers in a step within the same function as your tests, you
can just start the servers directly in a foreground step.



```yaml
start-csfle-servers:
  - command: ec2.assume_role
      params:
      role_arn: ${aws_test_secrets_role}
  - command: subprocess.exec
      params:
      working_dir: src
      binary: bash
      include_expansions_in_env: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"]
      args: |
          ${DRIVERS_TOOLS}/.evergreen/csfle/setup-secrets.sh
  - command: subprocess.exec
      params:
      working_dir: src
      binary: bash
      background: true
      args:
          - ${DRIVERS_TOOLS}/.evergreen/csfle/start-servers.sh
  - command: subprocess.exec
      params:
      working_dir: src
      binary: bash
      args:
          - ${DRIVERS_TOOLS}/.evergreen/csfle/await-servers.sh
```

## Legacy Usage

The legacy usage involved putting the required secrets in EVG Project config, and used several steps:

- Start the kmip server and http servers individually in the background.
- Run the client in a loop until it was able to connect.
- Use the `set-temp-creds.sh` to exchange EVG creds for CSFLE temporary credentials.
