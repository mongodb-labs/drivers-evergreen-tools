#!/usr/bin/env python3
"""
Script for fetching AWS Secrets Vault secrets for use in testing.
"""
import argparse
import json
import os
import boto3


def get_secrets(vaults, region, profile):
    """Get the driver secret values."""
    # Handle local credentials.
    try:
        if profile is not None:
            session = boto3.Session(profile_name=profile)
        else:
            session = boto3.Session()
        client = session.client(service_name='secretsmanager', region_name=region)
    except Exception:
        print("Failed to connect using AWS credentials, trying with environment variables")
        if "AWS_SESSION_TOKEN" not in os.environ:
            if "AWS_ROLE_ARN" in os.environ:
                session = boto3.Session(aws_access_key_id=os.environ['AWS_ACCESS_KEY_ID'],
                                        aws_secret_access_key=os.environ['AWS_SECRET_ACCESS_KEY'])
                client = session.client(service_name='sts', region_name=region)
                creds = client.assume_role(RoleArn=os.environ['AWS_ROLE_ARN'], RoleSessionName='test')['Credentials']
                os.environ['AWS_ACCESS_KEY_ID'] = creds['AccessKeyId']
                os.environ['AWS_SECRET_ACCESS_KEY'] = creds['SecretAccessKey']
                os.environ['AWS_SESSION_TOKEN'] = creds['SessionToken']
            else:
                raise ValueError('Missing AWS credentials')

        # Create a session using the given creds
        session = boto3.Session(aws_access_key_id=os.environ['AWS_ACCESS_KEY_ID'],
                                aws_secret_access_key=os.environ['AWS_SECRET_ACCESS_KEY'],
                                aws_session_token=os.environ['AWS_SESSION_TOKEN'])
        client = session.client(service_name='secretsmanager', region_name=region)

    secrets = []
    try:
        for vault in vaults:
            secrets.append(client.get_secret_value(
                SecretId=vault
            )['SecretString'])
    except Exception as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        raise e

    # Decrypts secret using the associated KMS key.
    return [json.loads(s) for s in secrets]


def write_secrets(vaults, region, profile):
    pairs = {}
    secrets = get_secrets(vaults, region, profile)
    for secret in secrets:
        for key, val in secret.items():
            pairs[key.upper()] = val

    with open("secrets-export.sh", "w", newline="\n") as out:
        # These values are secrets, do not print them
        out.write("#!/usr/bin/env bash\n\nset +x\n")
        for key, val in pairs.items():
            out.write("export " + key + "=" + "\"" + val + "\"\n")


def main():
    parser = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter,
                                     description='MongoDB AWS Secrets Vault fetcher. If connecting with the given AWS '
                                                 'profile fails, will attempt to use local environment variables '
                                                 'instead.')

    parser.add_argument("-p", "--profile", type=str, nargs="?", metavar="profile", help="a local AWS profile "
                                                                                        "to use credentials "
                                                                                        "from. Defaults to "
                                                                                        "AWS_PROFILE if not provided.")
    parser.add_argument("-r", "--region", type=str, metavar="region", default="us-east-1",
                        help="the AWS region containing the given vaults.")
    parser.add_argument("vaults", metavar="V", type=str, nargs="+", help="a vault to fetch secrets from")

    args = parser.parse_args()

    write_secrets(args.vaults, args.region, args.profile)


if __name__ == '__main__':
    main()
