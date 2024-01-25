# Scripts for In-Use Encryption testing

This folder contains scripts for use with In-Use Encryption.

See the [Azure KMS](./azurekms/README.md) and [GCP KMS](./gcpkms/README.md)
for more information on those specific scenarios.

## Prerequisities

The system you are running on must have Python 3 and have access to the
`drivers/csfle` [AWS Vault](https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets).
For legacy usage, see below.

## Usage

Set up In-Use Encryption by first fetching the secrets and then launching the kms servers:

```bash
$DRIVERS_TOOLS/.evergreen/csfle/setup_secrets.sh
$DRIVERS_TOOLS/.evergreen/csfle/start_servers.sh
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
$DRIVERS_TOOLS/.evergreen/csfle/stop_servers.sh
```

If you are starting your CSFLE servers in a separate Evergreen function, it is recommended that you setup secrets
and start the servers in the background, and then have a separate function that uses `await_servers.sh`
in the foreground to wait for the servers to be ready.  This will ensure the servers are not torn down
between functions (or the function may stall and not finish because there are processes still running).  
If you are starting the servers in a step within the same function as your tests, you
can just start the servers directly in a foreground step.

```yaml
start-csfle-servers:
- command: subprocess.exec
    params:
    working_dir: src
    binary: bash
    background: true
    include_expansions_in_env: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "DRIVERS_TOOLS"]
    args:
        - ./scripts/setup-encryption.sh
- command: subprocess.exec
    params:
    working_dir: src
    binary: bash
    include_expansions_in_env: ["DRIVERS_TOOLS"]
    args:
        - ${DRIVERS_TOOLS}/.evergreen/csfle/await_servers.sh
```

Where `./scripts/setup-encryption.sh` would be:

```bash
#!/usr/bin/env bash
# Whatever other setup needed here, like setting CSFLE_TLS_CA_FILE
bash $DRIVERS_TOOLS/.evergreen/csfle/setup_secrets.sh
bash $DRIVERS_TOOLS/.evergreen/csfle/start_servers.sh
```

## Legacy Usage

The legacy usage involved putting the required secrets in EVG Project config, and used several steps:

- Start the kmip server and http servers individually in the background.
- Run the client in a loop until it was able to connect.
- Use the `set-temp-creds.sh` to exchange EVG creds for CSFLE temporary credentials.
