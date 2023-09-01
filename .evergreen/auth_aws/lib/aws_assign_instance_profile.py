#!/usr/bin/env python3
"""
Script for assign an instance policy to the current machine.
"""

import argparse
import urllib.request
import logging
import json
import os
import sys
import time
from functools import partial

import boto3
import botocore

sys.path.insert(1, os.path.join(sys.path[0], '..'))

from util import get_key as _get_key

LOGGER = logging.getLogger(__name__)
HERE = os.path.abspath(os.path.dirname(__file__))


def _get_local_instance_id():
    return urllib.request.urlopen('http://169.254.169.254/latest/meta-data/instance-id').read().decode()


def _has_instance_profile():
    base_url = "http://169.254.169.254/latest/meta-data/iam/security-credentials/"
    try:
        print("Reading: " + base_url)
        iam_role = urllib.request.urlopen(base_url).read().decode()
    except urllib.error.HTTPError as e:
        print(e)
        if e.code == 404:
            return False
        raise e

    try:
        url = base_url + iam_role
        print("Reading: " + url)
        req = urllib.request.urlopen(url)
        print("Assigned " + iam_role)
    except urllib.error.HTTPError as e:
        print(e)
        if e.code == 404:
            return False
        raise e

    return True


def _wait_instance_profile():
    retry = 60
    while not _has_instance_profile() and retry:
        time.sleep(5)
        retry -= 1

    if retry == 0:
        raise ValueError("Timeout on waiting for instance profile")


def _handle_config():
    try:
        with open(os.path.join(HERE, '..', 'aws_e2e_setup.json')) as fid:
            CONFIG = json.load(fid)
            get_key = partial(_get_key, uppercase=False)

    except FileNotFoundError:
        CONFIG = os.environ
        get_key = partial(_get_key, uppercase=True)

    try:
        os.environ.setdefault('AWS_ACCESS_KEY_ID', CONFIG[get_key('iam_auth_ec2_instance_account')])
        os.environ.setdefault('AWS_SECRET_ACCESS_KEY',
                              CONFIG[get_key('iam_auth_ec2_instance_secret_access_key')])
        return CONFIG[get_key('iam_auth_ec2_instance_profile')]
    except Exception as e:
        print(e)
        return ''


DEFAULT_ARN = _handle_config()


def _assign_instance_policy(iam_instance_arn=DEFAULT_ARN):
    if _has_instance_profile():
        print("IMPORTANT: Found machine already has instance profile, skipping the assignment")
        return

    instance_id = _get_local_instance_id()

    ec2_client = boto3.client("ec2", 'us-east-1')

    # https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2.html#EC2.Client.associate_iam_instance_profile
    try:
        response = ec2_client.associate_iam_instance_profile(
            IamInstanceProfile={
                'Arn': iam_instance_arn,
            },
            InstanceId=instance_id)

        print(response)

        # Wait for the instance profile to be assigned by polling the local instance metadata service
        _wait_instance_profile()

    except botocore.exceptions.ClientError as ce:
        if ce.response["Error"]["Code"] == "RequestLimitExceeded":
            print("WARNING: RequestLimitExceeded, exiting with error code 2")
            sys.exit(2)
        raise


def main() -> None:
    """Execute Main entry point."""

    parser = argparse.ArgumentParser(description='IAM Assign Instance frontend.')

    parser.add_argument('-v', "--verbose", action='store_true', help="Enable verbose logging")
    parser.add_argument('-d', "--debug", action='store_true', help="Enable debug logging")

    parser.add_argument('--instance_profile_arn', type=str, help="Name of instance profile", default=DEFAULT_ARN)

    args = parser.parse_args()

    if args.debug:
        logging.basicConfig(level=logging.DEBUG)
    elif args.verbose:
        logging.basicConfig(level=logging.INFO)

    _assign_instance_policy(args.instance_profile_arn)


if __name__ == "__main__":
    main()
