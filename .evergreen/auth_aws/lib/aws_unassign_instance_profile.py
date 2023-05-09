#!/usr/bin/env python3
"""
Script for unassigning an instance policy from the current machine.
"""

import argparse
import urllib.error
import urllib.request
import logging
import sys
import time

import boto3
import botocore

LOGGER = logging.getLogger(__name__)

def _get_local_instance_id():
    return urllib.request.urlopen('http://169.254.169.254/latest/meta-data/instance-id', timeout=5).read().decode()

def _has_instance_profile():
    base_url = "http://169.254.169.254/latest/meta-data/iam/security-credentials/"
    try:
        print("Reading: " + base_url)
        iam_role = urllib.request.urlopen(base_url).read().decode()
    except urllib.error.HTTPError as e:
        print(e)
        if e.code == 404:
            print('returning false here')
            return False
        print('raising?')
        raise e
    except Exception as e:
        print('what?', type(e))
        raise e

    try:
        url = base_url + iam_role
        print("Reading: " + url)
        req = urllib.request.urlopen(url)
    except urllib.error.HTTPError as e:
        print(e)
        if e.code == 404:
            print('returning false there')
            return False
        raise e

    return True

def _wait_no_instance_profile():
    retry = 60
    while retry:
        if not _has_instance_profile():
            print('returning here')
            return
        time.sleep(5)
        retry -= 1

    if retry == 0:
        print('raising here')
        raise ValueError("Timeout on waiting for no instance profile")

def _unassign_instance_policy():

    try:
        instance_id = _get_local_instance_id()
    except urllib.error.URLError as e:
        print(e)
        sys.exit(0)

    ec2_client = boto3.client("ec2", 'us-east-1')

    #https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2.html#EC2.Client.describe_iam_instance_profile_associations
    try:
        response = ec2_client.describe_iam_instance_profile_associations(Filters=[{"Name":"instance-id","Values": [instance_id]}])
        associations = response['IamInstanceProfileAssociations']
        if associations:
            print('disassociating')
            ec2_client.disassociate_iam_instance_profile(AssociationId=associations[0]['AssociationId'])

        # Wait for the instance profile to be unassigned by polling the local instance metadata service
        _wait_no_instance_profile()
        print('no more instance profile')

    except botocore.exceptions.ClientError as ce:
        print('what is this?', ce)
        if ce.response["Error"]["Code"] == "RequestLimitExceeded":
            print("WARNING: RequestLimitExceeded, exiting with error code 2")
            sys.exit(2)
        raise

def main() -> None:
    """Execute Main entry point."""

    parser = argparse.ArgumentParser(description='IAM UnAssign Instance frontend.')

    parser.add_argument('-v', "--verbose", action='store_true', help="Enable verbose logging")
    parser.add_argument('-d', "--debug", action='store_true', help="Enable debug logging")

    args = parser.parse_args()

    if args.debug:
        logging.basicConfig(level=logging.DEBUG)
    elif args.verbose:
        logging.basicConfig(level=logging.INFO)

    _unassign_instance_policy()
    print('and we are done')


if __name__ == "__main__":
    main()
    print('main was called')
