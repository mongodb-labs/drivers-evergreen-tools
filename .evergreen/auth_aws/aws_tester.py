#!/usr/bin/env python3
"""
Script for testing MONGDOB-AWS authentication.
"""

import argparse
import json
import logging
import os
import subprocess
import sys
from functools import partial
from pathlib import Path
from urllib.parse import quote_plus

from pymongo import MongoClient
from pymongo.errors import OperationFailure

HERE = Path(__file__).absolute().parent
LOGGER = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(levelname)-8s %(message)s")


def join(*parts):
    return os.path.join(*parts).replace(os.sep, "/")


sys.path.insert(0, str(HERE / "lib"))
from aws_assign_instance_profile import _assign_instance_policy
from aws_assume_role import _assume_role
from aws_assume_web_role import _assume_role_with_web_identity
from util import get_key as _get_key

ASSUMED_ROLE = "arn:aws:sts::557821124784:assumed-role/authtest_user_assume_role/*"
ASSUMED_WEB_ROLE = "arn:aws:sts::857654397073:assumed-role/webIdentityTestRole/*"

# This varies based on hosting EC2 as the account id and role name can vary
AWS_ACCOUNT_ARN = "arn:aws:sts::557821124784:assumed-role/evergreen_task_hosts_instance_role_production/*"
_USE_AWS_SECRETS = False

try:
    with (HERE / "aws_e2e_setup.json").open() as fid:
        CONFIG = json.load(fid)
        get_key = partial(_get_key, uppercase=False)
except FileNotFoundError:
    CONFIG = os.environ
    get_key = partial(_get_key, uppercase=True)


def run(args, env):
    """Run a python command in a subprocess."""
    env.update(os.environ.copy())
    return subprocess.run([sys.executable, *args], env=env, check=False).returncode


def create_user(user, kwargs):
    """Create a user and verify access."""
    LOGGER.info("Creating user %s", user)
    client = MongoClient(username="bob", password="pwd123")
    db = client["$external"]
    try:
        db.command(dict(createUser=user, roles=[{"role": "read", "db": "aws"}]))
    except OperationFailure as e:
        if "already exists" not in e.details["errmsg"]:
            raise
    client.close()

    # Verify access.
    client = MongoClient(authMechanism="MONGODB-AWS", **kwargs)
    client.aws.command("count", "test")
    client.close()


def setup_assume_role():
    # Assume the role to get temp creds.
    os.environ["AWS_ACCESS_KEY_ID"] = CONFIG[get_key("iam_auth_assume_aws_account")]
    os.environ["AWS_SECRET_ACCESS_KEY"] = CONFIG[
        get_key("iam_auth_assume_aws_secret_access_key")
    ]

    role_name = CONFIG[get_key("iam_auth_assume_role_name")]
    creds = _assume_role(role_name, quiet=True)
    with (HERE / "creds.json").open("w") as fid:
        json.dump(creds, fid)

    # Create the user.
    token = quote_plus(creds["SessionToken"])
    kwargs = dict(
        username=creds["AccessKeyId"],
        password=creds["SecretAccessKey"],
        authmechanismproperties=f"AWS_SESSION_TOKEN:{token}",
    )
    create_user(ASSUMED_ROLE, kwargs)
    return dict(
        USER=kwargs["username"],
        PASS=kwargs["password"],
        SESSION_TOKEN=creds["SessionToken"],
    )


def setup_ec2():
    # Create the user.
    _assign_instance_policy()
    os.environ.pop("AWS_ACCESS_KEY_ID", None)
    os.environ.pop("AWS_SECRET_ACCESS_KEY", None)
    create_user(AWS_ACCOUNT_ARN, dict())
    return dict()


def setup_ecs():
    # Set up commands.
    mongo_binaries = os.environ["MONGODB_BINARIES"]
    project_dir = os.environ["PROJECT_DIRECTORY"]
    base_command = f"{sys.executable} -u  lib/container_tester.py"
    run_prune_command = f"{base_command} -v remote_gc_services --cluster {CONFIG[get_key('iam_auth_ecs_cluster')]}"

    # Get the appropriate task definition based on the version of Ubuntu.
    with open("/etc/lsb-release") as fid:
        text = fid.read()
    if "jammy" in text:
        task_definition = CONFIG.get(
            get_key("iam_auth_ecs_task_definition_jammy"), None
        )
        if task_definition is None:
            raise ValueError('Please set "iam_auth_ecs_task_definition_jammy" variable')
    elif "focal" in text:
        task_definition = CONFIG.get(
            get_key("iam_auth_ecs_task_definition_focal"), None
        )
        # Fall back to previous task definition for backward compat.
        if task_definition is None:
            task_definition = CONFIG[get_key("iam_auth_ecs_task_definition")]
    else:
        raise ValueError("Unsupported ubuntu release")
    run_test_command = f"{base_command} -d -v run_e2e_test --cluster {CONFIG[get_key('iam_auth_ecs_cluster')]} --task_definition {task_definition} --subnets {CONFIG[get_key('iam_auth_ecs_subnet_a')]} --subnets {CONFIG[get_key('iam_auth_ecs_subnet_b')]} --security_group {CONFIG[get_key('iam_auth_ecs_security_group')]} --files {mongo_binaries}/mongod:/root/mongod {mongo_binaries}/mongosh:/root/mongosh lib/ecs_hosted_test.js:/root/ecs_hosted_test.js {project_dir}:/root --script lib/ecs_hosted_test.sh"

    # Pass in the AWS credentials as environment variables
    # AWS_SHARED_CREDENTIALS_FILE does not work in evergreen for an unknown
    #  reason
    env = dict(
        AWS_ACCESS_KEY_ID=CONFIG[get_key("iam_auth_ecs_account")],
        AWS_SECRET_ACCESS_KEY=CONFIG[get_key("iam_auth_ecs_secret_access_key")],
    )

    # Prune other containers
    subprocess.check_call(["/bin/sh", "-c", run_prune_command], env=env)

    # Run the test in a container
    subprocess.check_call(["/bin/sh", "-c", run_test_command], env=env)

    return dict()


def setup_regular():
    # Create the user.
    kwargs = dict(
        username=CONFIG[get_key("iam_auth_ecs_account")],
        password=CONFIG[get_key("iam_auth_ecs_secret_access_key")],
    )
    create_user(CONFIG[get_key("iam_auth_ecs_account_arn")], kwargs)

    return dict(USER=kwargs["username"], PASS=kwargs["password"])


def setup_web_identity():
    # Unassign the instance profile.
    env = dict(
        AWS_ACCESS_KEY_ID=CONFIG[get_key("iam_auth_ec2_instance_account")],
        AWS_SECRET_ACCESS_KEY=CONFIG[
            get_key("iam_auth_ec2_instance_secret_access_key")
        ],
    )
    ret = run(["lib/aws_unassign_instance_profile.py"], env)
    if ret == 2:
        raise RuntimeError("Request limit exceeded for AWS API")

    if ret != 0:
        LOGGER.debug("return code was %s", ret)
        raise RuntimeError(
            "Failed to unassign an instance profile from the current machine"
        )

    token_file = os.environ.get(
        "AWS_WEB_IDENTITY_TOKEN_FILE", CONFIG[get_key("iam_web_identity_token_file")]
    )
    if os.name == "nt" and token_file.startswith("/tmp"):
        token_file = token_file.replace("/tmp", "C:/cygwin/tmp/")

    # Handle the OIDC credentials.
    env = dict(
        IDP_ISSUER=CONFIG[get_key("iam_web_identity_issuer")],
        IDP_JWKS_URI=CONFIG[get_key("iam_web_identity_jwks_uri")],
        IDP_RSA_KEY=CONFIG[get_key("iam_web_identity_rsa_key")],
        AWS_WEB_IDENTITY_TOKEN_FILE=token_file,
    )

    ret = run(["lib/aws_handle_oidc_creds.py", "token"], env)
    if ret != 0:
        raise RuntimeWarning("Failed to write the web token")

    # Assume the web role to get temp credentials.
    os.environ["AWS_WEB_IDENTITY_TOKEN_FILE"] = token_file
    role_arn = CONFIG[get_key("iam_auth_assume_web_role_name")]
    os.environ["AWS_ROLE_ARN"] = role_arn

    creds = _assume_role_with_web_identity(True)
    with (HERE / "creds.json").open("w") as fid:
        json.dump(creds, fid)

    # Create the user.
    token = quote_plus(creds["SessionToken"])
    kwargs = dict(
        username=creds["AccessKeyId"],
        password=creds["SecretAccessKey"],
        authmechanismproperties=f"AWS_SESSION_TOKEN:{token}",
    )
    create_user(ASSUMED_WEB_ROLE, kwargs)

    return dict(AWS_WEB_IDENTITY_TOKEN_FILE=token_file, AWS_ROLE_ARN=role_arn)


def handle_creds(creds: dict):
    if "USER" in creds:
        USER = quote_plus(creds.pop("USER"))
        PASS = quote_plus(creds.pop("PASS"))
        MONGODB_URI = f"mongodb://{USER}:{PASS}@localhost"
    else:
        MONGODB_URI = "mongodb://localhost"
    MONGODB_URI = f"{MONGODB_URI}/aws?authMechanism=MONGODB-AWS"
    if "SESSION_TOKEN" in creds:
        SESSION_TOKEN = quote_plus(creds.pop("SESSION_TOKEN"))
        MONGODB_URI = (
            f"{MONGODB_URI}&authMechanismProperties=AWS_SESSION_TOKEN:{SESSION_TOKEN}"
        )
    with (HERE / "test-env.sh").open("w", newline="\n") as fid:
        fid.write("#!/usr/bin/env bash\n\n")
        fid.write("set +x\n")
        for key, value in creds.items():
            fid.write(f"export {key}={value}\n")
        fid.write(f"export MONGODB_URI={MONGODB_URI}\n")
        # USER and PASS are always exported.
        if "USER" not in creds:
            fid.write("export USER=''\n")
        if "PASS" not in creds:
            fid.write("export PASS=''\n")


def main():
    parser = argparse.ArgumentParser(description="MONGODB-AWS tester.")
    sub = parser.add_subparsers(title="Tester subcommands", help="sub-command help")

    run_assume_role_cmd = sub.add_parser(
        "assume-role", aliases=["session-creds"], help="Assume role test"
    )
    run_assume_role_cmd.set_defaults(func=setup_assume_role)

    run_ec2_cmd = sub.add_parser("ec2", help="EC2 test")
    run_ec2_cmd.set_defaults(func=setup_ec2)

    run_ecs_cmd = sub.add_parser("ecs", help="ECS test")
    run_ecs_cmd.set_defaults(func=setup_ecs)

    run_regular_cmd = sub.add_parser(
        "regular", aliases=["env-creds"], help="Regular credentials test"
    )
    run_regular_cmd.set_defaults(func=setup_regular)

    run_web_identity_cmd = sub.add_parser("web-identity", help="Web identity test")
    run_web_identity_cmd.set_defaults(func=setup_web_identity)

    args = parser.parse_args()
    func_name = args.func.__name__.replace("setup_", "")
    LOGGER.info("Running aws_tester.py with %s...", func_name)
    creds = args.func()
    handle_creds(creds)
    LOGGER.info("Running aws_tester.py with %s... done.", func_name)


if __name__ == "__main__":
    main()
