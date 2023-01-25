import json
import os
import sys

import boto3

HERE = os.path.abspath(os.path.dirname(__file__))
aws_lib = os.path.join(os.path.dirname(HERE), 'auth_aws', 'lib')
sys.path.insert(0, aws_lib)
from aws_handle_oidc_creds import get_id_token, MOCK_ENDPOINT

DEFAULT_CLIENT = "0oadp0hpl7q3UIehP297"


def get_secrets():
    """Get the driver secret values."""
    # Handle local credentials.
    if "AWS_SESSION_TOKEN" not in os.environ:
        if "AWS_ROLE_ARN" in os.environ:
            session = boto3.Session(aws_access_key_id=os.environ['AWS_ACCESS_KEY_ID'], aws_secret_access_key=os.environ['AWS_SECRET_ACCESS_KEY'])
            client = session.client(service_name='sts', region_name='us-west-2')
            creds = client.assume_role(RoleArn=os.environ['AWS_ROLE_ARN'], RoleSessionName='test')['Credentials']
            os.environ['AWS_ACCESS_KEY_ID'] = creds['AccessKeyId']
            os.environ['AWS_SECRET_ACCESS_KEY'] = creds['SecretAccessKey']
            os.environ['AWS_SESSION_TOKEN'] = creds['SessionToken']

        else:
            raise ValueError('Missing AWS credentials')

    # Create a session using the given creds
    session = boto3.Session(aws_access_key_id=os.environ['AWS_ACCESS_KEY_ID'], aws_secret_access_key=os.environ['AWS_SECRET_ACCESS_KEY'], aws_session_token=os.environ['AWS_SESSION_TOKEN'])
    client = session.client(service_name='secretsmanager', region_name='us-west-2')
    try:
        get_secret_value_response = client.get_secret_value(
            SecretId='drivers/test'
        )
    except Exception as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        raise e

    # Decrypts secret using the associated KMS key.
    return json.loads(get_secret_value_response['SecretString'])