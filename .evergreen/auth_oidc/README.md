# Scripts for OIDC testing


## Local Testing

OIDC is only supported on Linux, so the following steps can be used
to each local development and testing.

Dockerfile, docker_entry.sh, and local_bootstrap.sh are used to launch a local
docker container running mongo-orchestration with OIDC enabled.
To run locally, docker and python must be installed locally (both can be
installed using brew).
To run the file locally, the following environment variables are required:
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_ROLE_ARN.
Additionally, USE_MULTIPLE_PRINCIPALS can be set to "true" if testing against
multiple principals.

Running `./local_bootstrap.sh` will create local OIDC tokens as /tmp/tokens/test1 and /tmp/tokens/test2.  It will use docker to launch the server
with the correct configuration, and expose the server on local port 27017.


## Evergreen Testing

On Evergreen, use `ec2.assume_role` to assume the Drivers Secrets role
and set the three AWS variables accordingly.

The orchestration file must be created before the server is launched.
Optionally set USE_MULTIPLE_PRINCIPALS to "true" to enable two Identity
Providers.

. ./activate_venv.sh
python oidc_bootstrap.py

This will create tokens in /tmp/tokens/test1 and /tmp/tokens/test2 and
create the file $DRIVERS_TOOLS/orchestration/configs/servers/oidc.json.

You can then run mongo orchestration with `TOPOLOGY=server` and `ORCHESTRATION_FILE=auth-oidc.json`.

To set up the server auth roles, run "mongo setup_oidc.js".

Then, tests can be run against the server.  Set `AWS_WEB_IDENTITY_TOKEN_FILE` to either `/tmp/tokens/test1` or `/tmp/tokens/test2` as desired.
Also set `USE_MULTIPLE_PRINCIPALS=true` as desired.