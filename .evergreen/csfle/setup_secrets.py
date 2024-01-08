

#! /usr/bin/env python3
"""
Set up encryption secrets.
"""
import os
import boto3

os.environ['AWS_ACCESS_KEY_ID']=os.environ['FLE_AWS_KEY']
os.environ['AWS_SECRET_ACCESS_KEY']=os.environ['FLE_AWS_SECRET']
os.environ['AWS_DEFAULT_REGION']="us-east-1"
os.environ['AWS_SESSION_TOKEN']=""

print("Getting CSFLE temp creds")
client = boto3.client('sts')
credentials = client.get_session_token()["Credentials"]

with open('secrets-export.sh', 'ab') as fid:
    fid.write(f'\nexport CSFLE_AWS_TEMP_ACCESS_KEY_ID="{credentials["AccessKeyId"]}"'.encode('utf8'))
    fid.write(f'\nexport CSFLE_AWS_TEMP_SECRET_ACCESS_KEY="{credentials["SecretAccessKey"]}"'.encode('utf8'))
    fid.write(f'\nexport CSFLE_AWS_TEMP_SESSION_TOKEN="{credentials["SessionToken"]}"'.encode('utf8'))
    for key in ['AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 
                'AWS_SESSION_TOKEN', 'CSFLE_TLS_CA_FILE', 'CSFLE_TLS_CERT_FILE',
                'CSFLE_TLS_CLIENT_CERT_FILE']:
        fid.write(f'\nexport {key}="{os.environ[key]}"'.encode('utf8'))
    fid.write('\n'.encode('utf8'))

print("Getting CSFLE temp creds...done")
