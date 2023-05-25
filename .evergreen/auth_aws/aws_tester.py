#!/usr/bin/env python3
"""
Script for testing MONGDOB-AWS authentication.
"""
import argparse
import os
import json
import sys
import subprocess
from pymongo import MongoClient
from urllib.parse import quote_plus


HERE = os.path.abspath(os.path.dirname(__file__))

ASSUMED_ROLE = "arn:aws:sts::557821124784:assumed-role/authtest_user_assume_role/*";
ASSUMED_WEB_ROLE = "arn:aws:sts::857654397073:assumed-role/webIdentityTestRole/*"

# This varies based on hosting EC2 as the account id and role name can vary
AWS_ACCOUNT_ARN = "arn:aws:sts::557821124784:assumed-role/evergreen_task_hosts_instance_role_production/*"


with open(os.path.join(HERE, 'aws_e2e_setup.json')) as fid:
   CONFIG = json.load(fid)


def run(args, env):
    """Run a python command in a subprocess."""
    return subprocess.run([sys.executable] + args, env=env).returncode


def create_user(user, kwargs):
    """Create a user and verify access."""
    print('Creating user', user)
    client = MongoClient(username="bob", password="pwd123")
    db = client['$external']
    db.command(dict(createUser=user, roles=[{"role": "read", "db": "aws"}]))
    client.close()

    # Verify access.
    client = MongoClient(authMechanism='MONGODB-AWS', **kwargs)
    client.aws.command('count', 'test')
    client.close()


def handle_creds(args, env):
    """Call a python process to handle credentials."""
    shell = os.name == "nt"
    creds = subprocess.check_output([sys.executable] + args, env=env, shell=shell)
    creds = json.loads(creds.decode('utf8'))
    with open('creds.json', 'w') as fid:
        json.dump(creds, fid)
    return creds


def setup_assume_role():
    # Assume the role to get temp creds.
    env = dict(
        AWS_ACCESS_KEY_ID=CONFIG["iam_auth_assume_aws_account"],
        AWS_SECRET_ACCESS_KEY=CONFIG["iam_auth_assume_aws_secret_access_key"],
    )

    role_name = CONFIG["iam_auth_assume_role_name"]
    creds = handle_creds(["lib/aws_assume_role.py", f"--role_name={role_name}"], env)

    # Create the user.
    token = quote_plus(creds['SessionToken'])
    kwargs = dict(username=creds["AccessKeyId"], password=creds["SecretAccessKey"], authmechanismproperties=f"AWS_SESSION_TOKEN:{token}")
    create_user(ASSUMED_ROLE, kwargs)


def setup_ec2():
    # Create the user.
    create_user(AWS_ACCOUNT_ARN, dict())


def setup_ecs():
    # Set up commands.
    mongo_binaries = os.environ['MONGODB_BINARIES']
    project_dir = os.environ['PROJECT_DIRECTORY']
    base_command = f"{sys.executable} -u  lib/container_tester.py"
    run_prune_command = f"{base_command} -v remote_gc_services --cluster {CONFIG['iam_auth_ecs_cluster']}"
    run_test_command = f"{base_command} -d -v run_e2e_test --cluster {CONFIG['iam_auth_ecs_cluster']} --task_definition {CONFIG['iam_auth_ecs_task_definition']} --subnets {CONFIG['iam_auth_ecs_subnet_a']} --subnets {CONFIG['iam_auth_ecs_subnet_b']} --security_group {CONFIG['iam_auth_ecs_security_group']} --files {mongo_binaries}/mongod:/root/mongod {mongo_binaries}/mongosh:/root/mongosh lib/ecs_hosted_test.js:/root/ecs_hosted_test.js {project_dir}:/root --script lib/ecs_hosted_test.sh"

    # Pass in the AWS credentials as environment variables
    # AWS_SHARED_CREDENTIALS_FILE does not work in evergreen for an unknown
    #  reason
    env = dict(AWS_ACCESS_KEY_ID=CONFIG['iam_auth_ecs_account'],
               AWS_SECRET_ACCESS_KEY=CONFIG['iam_auth_ecs_secret_access_key'])

    # Prune other containers
    subprocess.check_call(['/bin/sh', '-c', run_prune_command], env=env)

    # Run the test in a container
    subprocess.check_call(['/bin/sh', '-c', run_test_command], env=env)

def setup_regular():
    # Create the user.
    kwargs = dict(
        username=CONFIG["iam_auth_ecs_account"],
        password=CONFIG["iam_auth_ecs_secret_access_key"]
    )
    create_user(CONFIG["iam_auth_ecs_account_arn"], kwargs)


def setup_web_identity():
    # Unassign the instance profile.
    env = dict(AWS_ACCESS_KEY_ID=CONFIG["iam_auth_ec2_instance_account"],
               AWS_SECRET_ACCESS_KEY=CONFIG["iam_auth_ec2_instance_secret_access_key"])
    ret = run(['lib/aws_unassign_instance_profile.py'], env)
    if ret == 2:
        raise RuntimeError("Request limit exceeded for AWS API");

    if ret != 0:
        print('ret was', ret)
        raise RuntimeError("Failed to unassign an instance profile from the current machine")

    # Handle the OIDC credentials.
    env = dict(
        IDP_ISSUER=CONFIG["iam_web_identity_issuer"],
        IDP_JWKS_URI=CONFIG["iam_web_identity_jwks_uri"],
        IDP_RSA_KEY=CONFIG["iam_web_identity_rsa_key"],
        AWS_WEB_IDENTITY_TOKEN_FILE=CONFIG['iam_web_identity_token_file']
    )

    ret = run(['lib/aws_handle_oidc_creds.py', 'token'], env)
    if ret != 0:
        raise RuntimeWarning("Failed to write the web token")

    # Assume the web role to get temp credentials.
    env = dict(
        AWS_WEB_IDENTITY_TOKEN_FILE=CONFIG['iam_web_identity_token_file'],
        AWS_ROLE_ARN=CONFIG["iam_auth_assume_web_role_name"]
    )
    creds = handle_creds(['lib/aws_assume_web_role.py'], env)

    # Create the user.
    token = quote_plus(creds['SessionToken'])
    kwargs = dict(username=creds["AccessKeyId"], password=creds["SecretAccessKey"], authmechanismproperties=f"AWS_SESSION_TOKEN:{token}")
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