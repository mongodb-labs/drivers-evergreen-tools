# Scripts for In-Use Encryption testing

This folder contains scripts for use with In-Use Encryption.

See the [Azure KMS](./azurekms/README.md) and [GCP KMS](./gcpkms/README.md)
for more information on those specific scenarios.

## Prerequisities

The system you are running on must have Python 3 and have access to the
`drivers/csfle` AWS [Vault](https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets).
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

## Legacy Usage

The legacy usage involved putting the required secrets in EVG Project config, and using several steps:

- Start the kmip server and http servers individually in the background.
- Run the client in a loop until it was able to connect.
- Use the `set-temp-creds.sh` to exchange EVG creds for CSFLE temporary credentials.
