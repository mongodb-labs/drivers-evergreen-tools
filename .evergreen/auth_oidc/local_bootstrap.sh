# So, what are the steps?
# We should be able to set env vars and then run a local script to
# get everything up and running locally.
# Need to add a script that uses boto3 to get the creds for the 
# iam role, sets those, does the oidc_bootstrap locally, - it should 
# not use ipv6
# launches docker with the above script (except oidc.json)
# the only other env var is whether to use multiple
# then, we have everything we need locally to verify this thing

# prerequisites: docker + python3 from brew
# aws_access_key_id and aws_secret_access_key and role arn

export AWS_TOKEN_DIR=/tmp/tokens  
rm -rf .venv 
python3 -m venv .venv
./.venv/bin/activate
python -m pip install boto3 pyop
python oidc_bootstrap.py
docker build -t oidc-test .
# TODO: add volume mapping.
docker run -it -e USE_MULTIPLE_PRINCIPALS=$USE_MULTIPLE_PRINCIPALS
