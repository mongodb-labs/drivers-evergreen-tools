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
export CSFLE_TLS_EXPIRED_FILE=${CSFLE_TLS_EXPIRED_FILE:-"$PARENT_DIR/x509gen/expired.pem"}
export CSFLE_TLS_WRONG_HOST_FILE=${CSFLE_TLS_WRONG_HOST_FILE:-"$PARENT_DIR/x509gen/wrong-host.pem"}
export CSFLE_TLS_FAILPOINT_CA_FILE=${CSFLE_TLS_FAILPOINT_CA_FILE:-"$PARENT_DIR/x509gen/ca.pem"}
export CSFLE_TLS_FAILPOINT_CERT_FILE=${CSFLE_TLS_FAILPOINT_CERT_FILE:-"$PARENT_DIR/x509gen/server.pem"}

if [[ "${OSTYPE:?}" == cygwin ]]; then
    CSFLE_TLS_CA_FILE=$(cygpath -m $CSFLE_TLS_CA_FILE)
    CSFLE_TLS_CERT_FILE=$(cygpath -m $CSFLE_TLS_CERT_FILE)
    CSFLE_TLS_CLIENT_CERT_FILE=$(cygpath -m $CSFLE_TLS_CLIENT_CERT_FILE)
    CSFLE_TLS_EXPIRED_FILE=$(cygpath -m $CSFLE_TLS_EXPIRED_FILE)
    CSFLE_TLS_WRONG_HOST_FILE=$(cygpath -m $CSFLE_TLS_WRONG_HOST_FILE)
    CSFLE_TLS_FAILPOINT_CA_FILE=$(cygpath -m $CSFLE_TLS_FAILPOINT_CA_FILE)
    CSFLE_TLS_FAILPOINT_CERT_FILE=$(cygpath -m $CSFLE_TLS_FAILPOINT_CERT_FILE)
fi

pushd $SCRIPT_DIR
. $PARENT_DIR/secrets_handling/setup-secrets.sh drivers/csfle
. ./activate-kmstlsvenv.sh
if [[ "${FLE_AZURE_USE_CORPORATE:-}" == "YES" ]]; then
    echo "Using corporate Azure credentials"
    # Append corporate Azure credentials to secrets-export.sh:
    echo "export FLE_AZURE_TENANTID='$FLE_AZURE_TENANTID_CORPORATE'" >> secrets-export.sh
    echo "export FLE_AZURE_CLIENTID='$FLE_AZURE_CLIENTID_CORPORATE'" >> secrets-export.sh
    echo "export FLE_AZURE_CLIENTSECRET='$FLE_AZURE_CLIENTSECRET_CORPORATE'" >> secrets-export.sh
    # Source again to apply corporate credentials. Needed to generate an Azure token in setup_secrets.py.
    source secrets-export.sh
else
    echo "WARNING: Using deprecated Azure credentials. These will be migrated to corporate credentials. See DRIVERS-3392."
fi
python ./setup_secrets.py
cp secrets-export.sh $CURRENT || true
popd
