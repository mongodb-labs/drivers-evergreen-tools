#!/usr/bin/env bash
# setup secrets for csfle testing.
set -eu

CURRENT=$(pwd)
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

CSFLE_TLS_CA_FILE=${CSFLE_TLS_CA_FILE:-"$SCRIPT_DIR/x509gen/ca.pem"}
CSFLE_TLS_CERT_FILE=${CSFLE_TLS_CERT_FILE:-"$SCRIPT_DIR/x509gen/server.pem"}
CSFLE_TLS_CLIENT_CERT_FILE=${CSFLE_TLS_CLIENT_CERT_FILE:-"$SCRIPT_DIR/x509gen/client.pem"}

if [ "Windows_NT" = "${OS:-}" ]; then # Magic variable in cygwin
    CSFLE_TLS_CA_FILE=$(cygpath -m $CSFLE_TLS_CA_FILE)
    CSFLE_TLS_CERT_FILE=$(cygpath -m $CSFLE_TLS_CERT_FILE)
    CSFLE_TLS_CLIENT_CERT_FILE=$(cygpath -m $CSFLE_TLS_CLIENT_CERT_FILE)
fi

bash ../auth_aws/setup_secrets.sh drivers/csfle
source secrets-export.sh

. ./activate-kmstlsvenv.sh
python ./setup_secrets.py

cp secrets-export.sh $CURRENT
