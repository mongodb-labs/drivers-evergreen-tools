"""
Python script to log in to the Dev Prod ECR registry.
"""

import base64
import os
import shlex
import shutil
import subprocess

import boto3

registry = os.environ["ECR_REGISTRY"]
account = registry.split(".")[0]
if "CI" in os.environ:
    sts_client = boto3.client("sts", region_name=os.environ["AWS_REGION"])
    resp = sts_client.assume_role(
        RoleArn=os.environ["AWS_ROLE_ARN"],
        RoleSessionName=f"{account}-test",
        ExternalId=os.environ["AWS_EXTERNAL_ID"],
    )
    creds = resp["Credentials"]
    sts_client.close()
else:
    creds = dict(AccessKeyId=None, SecretAccessKey=None, SessionToken=None)

ecr_client = boto3.client(
    "ecr",
    aws_access_key_id=creds["AccessKeyId"],
    aws_secret_access_key=creds["SecretAccessKey"],
    aws_session_token=creds["SessionToken"],
    region_name=os.environ["AWS_REGION"],
)
resp = ecr_client.get_authorization_token(registryIds=[account])
ecr_client.close()

token = resp["authorizationData"][0]["authorizationToken"]
_, _, token = base64.b64decode(token).partition(b":")

docker = shutil.which("podman") or shutil.which("docker")
if "podman" in docker:
    docker = f"sudo {docker}"

cmd = f"{docker} login --username AWS --password-stdin {registry}"
proc = subprocess.Popen(
    shlex.split(cmd),
    stdout=subprocess.PIPE,
    stdin=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
stdout, stderr = proc.communicate(token)
if stdout:
    print(stdout.decode("utf-8").strip())
if stderr:
    print(stderr.decode("utf-8").strip())
