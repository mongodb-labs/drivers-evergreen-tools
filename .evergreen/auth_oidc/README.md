# Scripts for OIDC testing


## Local Testing

OIDC is only supported on Linux, so the following steps can be used
to each local development and testing.

`Dockerfile`, `docker_entry.sh`, and `start_local_server.sh` are used to launch a
local docker container running mongo-orchestration with OIDC enabled.
To run locally, docker and python must be installed locally (both can be
installed using brew).
To run the file locally, the following environment variables are required:
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_ROLE_ARN`.

Running `./oidc_get_tokens.sh`  will create local OIDC tokens as `/tmp/tokens/test_user1` and `/tmp/tokens/test_user2`. The token in `/tmp/tokens/test_user1_expires` can be used to test expired credentials.

Running `./start_local_server.sh` will use docker to launch the server
with the correct configuration, and expose the server on local ports 27017
and 27018.


## Evergreen Testing - Linux Only for Now

On Evergreen, use `ec2.assume_role` to assume the Drivers Secrets role
and set the three AWS variables accordingly.

. ./activate-authoidcvenv.sh
python oidc_write_orchestration.py
python oidc_get_tokens.py

This will create the tokens in `/tmp/tokens` and
create the file `$DRIVERS_TOOLS/orchestration/configs/servers/auth-oidc.json`.

You can then run mongo orchestration with `TOPOLOGY=replicaset` and `ORCHESTRATION_FILE=auth-oidc.json`.

To set up the server auth roles, run `mongosh setup_oidc.js`.

Then, tests can be run against the server.  Set `AWS_WEB_IDENTITY_TOKEN_FILE` to either `/tmp/tokens/test_user1` or `/tmp/tokens/test_user2` as desired.

The token in `/tmp/tokens/test_user1_expires` can be used to test expired credentials.

## Azure Testing

See the readme [./azure/README.md].
