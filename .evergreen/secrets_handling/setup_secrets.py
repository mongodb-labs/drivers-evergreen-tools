#!/usr/bin/env python3
"""
Script for fetching AWS Secrets Vault secrets for use in testing.
"""

import argparse
import json
import os
import sys
import uuid

import boto3
import botocore.exceptions

AWS_ROLE_ARN = "arn:aws:iam::857654397073:role/drivers-test-secrets-role"


def get_secrets(vaults, region, profile):
    """Get the driver secret values."""
    # Handle local credentials.
    profile = profile or os.environ.get("AWS_PROFILE", "")
    if profile:
        session = boto3.Session(profile_name=profile)
    else:
        session = boto3.Session()
    print(sorted(os.environ))
    creds = None
    kwargs = dict(region_name=region)
    if "AWS_ACCESS_KEY_ID" not in os.environ and not profile:
        client = session.client(service_name="sts", **kwargs)
        try:
            # This will only fail locally.
            resp = client.assume_role(
                RoleArn=AWS_ROLE_ARN, RoleSessionName=str(uuid.uuid4())
            )
        except Exception as e:
            raise ValueError(
                "Please provide a profile (typically using AWS_PROFILE)"
            ) from e

        creds = resp["Credentials"]

    if creds:
        kwargs.update(
            aws_access_key_id=creds["AccessKeyId"],
            aws_secret_access_key=creds["SecretAccessKey"],
            aws_session_token=creds["SessionToken"],
        )
    client = session.client(service_name="secretsmanager", **kwargs)

    secrets = []
    try:
        for vault in vaults:
            secret = client.get_secret_value(SecretId=vault)["SecretString"]
            secrets.append(secret)
    except botocore.exceptions.BotoCoreError as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        print(f"\nERROR: {e}\n")
        sys.exit(1)
    except Exception as e:
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
            out.write("export " + key + "=" + '"' + val + '"\n')


def main():
    parser = argparse.ArgumentParser(
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
        description="MongoDB AWS Secrets Vault fetcher. If connecting with the given AWS "
        "profile fails, will attempt to use local environment variables "
        "instead.",
    )

    parser.add_argument(
        "-p",
        "--profile",
        type=str,
        nargs="?",
        metavar="profile",
        help="a local AWS profile "
        "to use credentials "
        "from. Defaults to "
        "AWS_PROFILE if not provided.",
    )
    parser.add_argument(
        "-r",
        "--region",
        type=str,
        metavar="region",
        default="us-east-1",
        help="the AWS region containing the given vaults.",
    )
    parser.add_argument(
        "vaults", metavar="V", type=str, nargs="+", help="a vault to fetch secrets from"
    )

    args = parser.parse_args()

    write_secrets(args.vaults, args.region, args.profile)


if __name__ == "__main__":
    main()
