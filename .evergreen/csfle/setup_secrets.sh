#!/usr/bin/env bash
# setup secrets for csfle testing.
set -eu

CURRENT=$(pwd)
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR
bash ../auth_aws/setup_secrets.sh drivers/csfle
source secrets-export.sh

export AWS_ACCESS_KEY_ID="$FLE_AWS_KEY"
export AWS_SECRET_ACCESS_KEY="$FLE_AWS_SECRET"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_SESSION_TOKEN=""

. ./activate-kmsltsvenv.sh

get_creds() {
    python - "$@" << 'EOF'
import sys
import boto3

client = boto3.client('sts')
credentials = client.get_session_token()["Credentials"]
sys.stdout.write(credentials["AccessKeyId"] + " " + credentials["SecretAccessKey"] + " " + credentials["SessionToken"])
EOF
}

echo "Getting CSFLE temp creds"
CREDS=$(get_creds)
echo "Getting CSFLE temp creds...done"
CSFLE_AWS_TEMP_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
CSFLE_AWS_TEMP_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
CSFLE_AWS_TEMP_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')

echo "export CSFLE_AWS_TEMP_ACCESS_KEY_ID=$CSFLE_AWS_TEMP_ACCESS_KEY_ID\n" >> secrets-export.sh
echo "export CSFLE_AWS_TEMP_SECRET_ACCESS_KEY=$CSFLE_AWS_TEMP_SECRET_ACCESS_KEY\n" >> secrets-export.sh
echo "export CSFLE_AWS_TEMP_SESSION_TOKEN=$CSFLE_AWS_TEMP_SESSION_TOKEN\n" >> secrets-export.sh

cp secrets-export.sh $CURRENT
