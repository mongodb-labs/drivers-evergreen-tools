# Scripts for OIDC testing

## Testing with the Decidicated Atlas Clusters

We have two dedicated Atlas clusters that are configured with OIDC, one with a single Identity Provider (Idp), and one
with multiple IdPs configured. The credentials and variables are stored in the `drivers/oidc` AWS
[Vault](https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets).

These include:

```
OIDC_ALTAS_USER         # Atlas admin username and password
OIDC_ATLAS_PASSWORD
OIDC_ATLAS_URI_MULTI    # URI for the cluster with multiple IdPs configured
OIDC_ATLAS_URI_SINGLE   # URI for the cluster with single IdP configured
OIDC_CLIENT_SECRET      # The client secret used by the IdPs
OIDC_RSA_KEY            # The RSA key used by the IdPs
OIDC_JWKS_URI           # The JWKS URI used by the IdPs
OIDC_ISSUER_1_URI       # The issuer URI for mock IdP 1
OIDC_ISSUER_2_URI       # The issuer URI for mock IdP 2
```

### Prerequisites

See the The `oidc_get_tokens.sh` script will automatically fetch the credentials from the `drivers/oidc` vault.

### Usage

Use the `oidc_get_tokens.sh` script to create a set of OIDC tokens in a temporary, including `test_user1` and
`test_user1_expires`. The temp file location is exported as `OIDC_TOKEN_DIR`

```bash
source ./oidc_get_tokens.sh
AWS_WEB_IDENTITY_TOKEN_FILE="$OIDC_TOKEN_DIR/test_user1" /my/test/command
```

## Local Server Testing

`MONGODB-OIDC` is only supported on Linux, so the following steps can be used to each local development and testing.

`Dockerfile`, `docker_entry.sh`, and `start_local_server.sh` are used to launch a local docker container running
`mongo-orchestration` with OIDC enabled. To run locally, docker and python must be installed locally (both can be
installed using brew). To run the file locally, set up your local environment according to the
[Wiki](https://wiki.corp.mongodb.com/display/DRIVERS/Using+AWS+Secrets+Manager+to+Store+Testing+Secrets) and make sure
you have `AWS_PROFILE` set.

Running `./start_local_server.sh` will use docker to launch the server with the correct configuration, and expose the
server on local ports 27017 and 27018.

## Evergreen Testing With Local Server - Linux Only

On Evergreen, use `ec2.assume_role` to assume the Drivers Secrets role and set the three AWS variables accordingly.

```bash
. ./activate-authoidcvenv.sh
python oidc_write_orchestration.py
source ./oidc_get_tokens.sh
```

This will create the tokens in `OIDC_TOKEN_DIR` and create the file
`$DRIVERS_TOOLS/orchestration/configs/servers/auth-oidc.json`.

You can then run mongo orchestration with `TOPOLOGY=replicaset` and `ORCHESTRATION_FILE=auth-oidc.json`.

To set up the server auth roles, run `mongosh setup_oidc.js`.

Then, tests can be run against the server. Set `AWS_WEB_IDENTITY_TOKEN_FILE` to either `$OIDC_TOKEN_DIR/test_user1` or
`$OIDC_TOKEN_DIR/test_user2` as desired.

The token in `$OIDC_TOKEN_DIR/test_user1_expires` can be used to test expired credentials.

## Azure Testing

See the readme \[./azure/README.md\].
