#!/usr/bin/env python3
"""
Script for assuming an aws role using AssumeRoleWithWebIdentity.
"""

import argparse
import os
import uuid
import logging

import boto3

LOGGER = logging.getLogger(__name__)

def _assume_role_with_web_identity():
    sts_client = boto3.client("sts")

    token_file = os.environ['AWS_WEB_IDENTITY_TOKEN_FILE']
    with open(token_file) as fid:
        token = fid.read()
    role_name = os.environ['AWS_ROLE_ARN']

    response = sts_client.assume_role_with_web_identity(RoleArn=role_name, RoleSessionName=str(uuid.uuid4()), WebIdentityToken=token, DurationSeconds=900)

    creds = response["Credentials"]

    print(f"""{{
  "AccessKeyId" : "{creds["AccessKeyId"]}",
  "SecretAccessKey" : "{creds["SecretAccessKey"]}",
  "SessionToken" : "{creds["SessionToken"]}",
  "Expiration" : "{str(creds["Expiration"])}"
}}""")
    return creds


def main() -> None:
    """Execute Main entry point."""

    parser = argparse.ArgumentParser(description='Assume Role frontend.')

    parser.add_argument('-v', "--verbose", action='store_true', help="Enable verbose logging")
    parser.add_argument('-d', "--debug", action='store_true', help="Enable debug logging")

    args = parser.parse_args()

    if args.debug:
        logging.basicConfig(level=logging.DEBUG)
    elif args.verbose:
        logging.basicConfig(level=logging.INFO)

    _assume_role_with_web_identity()


if __name__ == "__main__":
    main()
