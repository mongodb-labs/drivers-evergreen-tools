#!/usr/bin/env python3
"""
Script for testing MONGDOB-AWS authentication.
"""
import argparse
import os
import json
import sys
import subprocess
from functools import partial

from pymongo import MongoClient
from pymongo.errors import OperationFailure
from urllib.parse import quote_plus

HERE = os.path.abspath(os.path.dirname(__file__))

def join(*parts):
    return os.path.join(*parts).replace(os.sep, '/')


sys.path.insert(0, join(HERE, 'lib'))
from util import get_key as _get_key
from aws_assume_role import _assume_role
from aws_assume_web_role import _assume_role_with_web_identity
from aws_assign_instance_profile import _assign_instance_policy

ASSUMED_ROLE = "arn:aws:sts::557821124784:assumed-role/authtest_user_assume_role/*"
ASSUMED_WEB_ROLE = "arn:aws:sts::857654397073:assumed-role/webIdentityTestRole/*"

# This varies based on hosting EC2 as the account id and role name can vary
AWS_ACCOUNT_ARN = "arn:aws:sts::557821124784:assumed-role/evergreen_task_hosts_instance_role_production/*"
_USE_AWS_SECRETS = False

try:
    with open(join(HERE, 'aws_e2e_setup.json')) as fid:
        CONFIG = json.load(fid)
        get_key = partial(_get_key, uppercase=False)
except FileNotFoundError:
    CONFIG = os.environ
    get_key = partial(_get_key, uppercase=True)


def run(args, env):
    """Run a python command in a subprocess."""
    newenv = os.environ.copy()
    newenv.update(env)
    return subprocess.run([sys.executable] + args, env=newenv).returncode


def create_user(user, kwargs):
    """Create a user and verify access."""
    print('Creating user', user)
    client = MongoClient(username="bob", password="pwd123")
    db = client['$external']
    try:
        db.command(dict(createUser=user, roles=[{"role": "read", "db": "aws"}]))
    except OperationFailure as e:
        if "already exists" not in e.details['errmsg']:
            raise
    client.close()

    # Verify access.
    client = MongoClient(authMechanism='MONGODB-AWS', **kwargs)
    client.aws.command('count', 'test')
    client.close()


def setup_assume_role():
    # Assume the role to get temp creds.
    os.environ['AWS_ACCESS_KEY_ID'] = CONFIG[get_key("iam_auth_assume_aws_account")]
    os.environ['AWS_SECRET_ACCESS_KEY'] = CONFIG[get_key("iam_auth_assume_aws_secret_access_key")]

    role_name = CONFIG[get_key("iam_auth_assume_role_name")]
    creds = _assume_role(role_name, quiet=True)
    with open(join(HERE, 'creds.json'), 'w') as fid:
        json.dump(creds, fid)

    # Create the user.
    token = quote_plus(creds['SessionToken'])
    kwargs = dict(username=creds["AccessKeyId"], password=creds["SecretAccessKey"],
                  authmechanismproperties=f"AWS_SESSION_TOKEN:{token}")
    create_user(ASSUMED_ROLE, kwargs)


def setup_ec2():
    # Create the user.
    _assign_instance_policy()
    os.environ.pop("AWS_ACCESS_KEY_ID", None)
    os.environ.pop("AWS_SECRET_ACCESS_KEY", None)
    create_user(AWS_ACCOUNT_ARN, dict())


def setup_ecs():
    # Set up commands.
    mongo_binaries = os.environ['MONGODB_BINARIES']
    project_dir = os.environ['PROJECT_DIRECTORY']
    base_command = f"{sys.executable} -u  lib/container_tester.py"
    run_prune_command = f"{base_command} -v remote_gc_services --cluster {CONFIG[get_key('iam_auth_ecs_cluster')]}"
    run_test_command = f"{base_command} -d -v run_e2e_test --cluster {CONFIG[get_key('iam_auth_ecs_cluster')]} --task_definition {CONFIG[get_key('iam_auth_ecs_task_definition')]} --subnets {CONFIG[get_key('iam_auth_ecs_subnet_a')]} --subnets {CONFIG[get_key('iam_auth_ecs_subnet_b')]} --security_group {CONFIG[get_key('iam_auth_ecs_security_group')]} --files {mongo_binaries}/mongod:/root/mongod {mongo_binaries}/mongosh:/root/mongosh lib/ecs_hosted_test.js:/root/ecs_hosted_test.js {project_dir}:/root --script lib/ecs_hosted_test.sh"

    # Pass in the AWS credentials as environment variables
    # AWS_SHARED_CREDENTIALS_FILE does not work in evergreen for an unknown
    #  reason
    env = dict(AWS_ACCESS_KEY_ID=CONFIG[get_key('iam_auth_ecs_account')],
               AWS_SECRET_ACCESS_KEY=CONFIG[get_key('iam_auth_ecs_secret_access_key')])

    # Prune other containers
    subprocess.check_call(['/bin/sh', '-c', run_prune_command], env=env)

    # Run the test in a container
    subprocess.check_call(['/bin/sh', '-c', run_test_command], env=env)


def setup_regular():
    # Create the user.
    kwargs = dict(
        username=CONFIG[get_key("iam_auth_ecs_account")],
        password=CONFIG[get_key("iam_auth_ecs_secret_access_key")]
    )
    create_user(CONFIG[get_key("iam_auth_ecs_account_arn")], kwargs)


def setup_web_identity():
    # Unassign the instance profile.
    env = dict(AWS_ACCESS_KEY_ID=CONFIG[get_key("iam_auth_ec2_instance_account")],
               AWS_SECRET_ACCESS_KEY=CONFIG[get_key("iam_auth_ec2_instance_secret_access_key")])
    ret = run(['lib/aws_unassign_instance_profile.py'], env)
    if ret == 2:
        raise RuntimeError("Request limit exceeded for AWS API")

    if ret != 0:
        print('ret was', ret)
        raise RuntimeError("Failed to unassign an instance profile from the current machine")

    token_file = os.environ.get('AWS_WEB_IDENTITY_TOKEN_FILE', CONFIG[get_key('iam_web_identity_token_file')])

    # Handle the OIDC credentials.
    env = dict(
        IDP_ISSUER=CONFIG[get_key("iam_web_identity_issuer")],
        IDP_JWKS_URI=CONFIG[get_key("iam_web_identity_jwks_uri")],
        IDP_RSA_KEY=CONFIG[get_key("iam_web_identity_rsa_key")],
        AWS_WEB_IDENTITY_TOKEN_FILE=token_file
    )

    ret = run(['lib/aws_handle_oidc_creds.py', 'token'], env)
    if ret != 0:
        raise RuntimeWarning("Failed to write the web token")

    # Assume the web role to get temp credentials.
    os.environ['AWS_WEB_IDENTITY_TOKEN_FILE'] = token_file
    os.environ['AWS_ROLE_ARN'] = CONFIG[get_key("iam_auth_assume_web_role_name")]

    creds = _assume_role_with_web_identity(True)
    with open(join(HERE, 'creds.json'), 'w') as fid:
        json.dump(creds, fid)

    # Create the user.
    token = quote_plus(creds['SessionToken'])
    kwargs = dict(username=creds["AccessKeyId"], password=creds["SecretAccessKey"],
                  authmechanismproperties=f"AWS_SESSION_TOKEN:{token}")
    create_user(ASSUMED_WEB_ROLE, kwargs)


def main():
    parser = argparse.ArgumentParser(description='MONGODB-AWS tester.')
    sub = parser.add_subparsers(title="Tester subcommands", help="sub-command help")

    run_assume_role_cmd = sub.add_parser('assume-role', help='Assume role test')
    run_assume_role_cmd.set_defaults(func=setup_assume_role)

    run_ec2_cmd = sub.add_parser('ec2', help='EC2 test')
    run_ec2_cmd.set_defaults(func=setup_ec2)

    run_ecs_cmd = sub.add_parser('ecs', help='ECS test')
    run_ecs_cmd.set_defaults(func=setup_ecs)

    run_regular_cmd = sub.add_parser('regular', help='Regular credentials test')
    run_regular_cmd.set_defaults(func=setup_regular)

    run_web_identity_cmd = sub.add_parser('web-identity', help='Web identity test')
    run_web_identity_cmd.set_defaults(func=setup_web_identity)

    args = parser.parse_args()
    args.func()


if __name__ == '__main__':
    main()
