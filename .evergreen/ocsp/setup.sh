#!/usr/bin/env bash
# Start an ocsp server.
set -o errexit # Exit on first command error.

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR

VARLIST=(
  OCSP_ALGORITHM
  SERVER_TYPE
)

# Ensure that all variables required to run the test are set, otherwise throw
# an error.
for VARNAME in "${VARLIST[@]}"; do
  [[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

. ./activate-ocspvenv.sh

CA_FILE="${OCSP_ALGORITHM}/ca.pem"
ARGS="-p 8100 -v"

case $SERVER_TYPE in
  valid)
    CERT="${OCSP_ALGORITHM}/ca.crt"
    KEY="${OCSP_ALGORITHM}/ca.key"
    ;;
  revoked)
    CERT="${OCSP_ALGORITHM}/ca.crt"
    KEY="${OCSP_ALGORITHM}/ca.key"
    ARGS="$ARGS --fault revoked"
    ;;
  valid-delegate)
    CERT="${OCSP_ALGORITHM}/ocsp-responder.crt"
    KEY="${OCSP_ALGORITHM}/ocsp-responder.key"
    ;;
  revoked-delegate)
    CERT="${OCSP_ALGORITHM}/ocsp-responder.crt"
    KEY="${OCSP_ALGORITHM}/ocsp-responder.key"
    ARGS="$ARGS --fault revoked"
    ;;
  *)
    echo "Invalid SERVER_TYPE: $SERVER_TYPE"
    exit 1
    ;;
esac

python ocsp_mock.py \
  --ca_file $CA_FILE \
  --ocsp_responder_cert $CERT \
  --ocsp_responder_key $KEY \
  $ARGS
