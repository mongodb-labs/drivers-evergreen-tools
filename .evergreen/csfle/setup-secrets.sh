#!/usr/bin/env bash
# setup secrets for csfle testing.
set -eu

if [ -z "$BASH" ]; then
  echo "setup-secrets.sh must be run in a Bash shell!" 1>&2
  return 1
fi

CURRENT=$(pwd)
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
PARENT_DIR=$(dirname $SCRIPT_DIR)

export CSFLE_TLS_CA_FILE=${CSFLE_TLS_CA_FILE:-"$PARENT_DIR/x509gen/ca.pem"}
export CSFLE_TLS_CERT_FILE=${CSFLE_TLS_CERT_FILE:-"$PARENT_DIR/x509gen/server.pem"}
export CSFLE_TLS_CLIENT_CERT_FILE=${CSFLE_TLS_CLIENT_CERT_FILE:-"$PARENT_DIR/x509gen/client.pem"}

if [[ "${OSTYPE:?}" == cygwin ]]; then
    CSFLE_TLS_CA_FILE=$(cygpath -m $CSFLE_TLS_CA_FILE)
    CSFLE_TLS_CERT_FILE=$(cygpath -m $CSFLE_TLS_CERT_FILE)
    CSFLE_TLS_CLIENT_CERT_FILE=$(cygpath -m $CSFLE_TLS_CLIENT_CERT_FILE)
fi

pushd $SCRIPT_DIR
. $PARENT_DIR/secrets_handling/setup-secrets.sh drivers/csfle
. ./activate-kmstlsvenv.sh
python ./setup_secrets.py
cp secrets-export.sh $CURRENT || true
popd
