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

bash teardown.sh

. ./activate-ocspvenv.sh

echo "Starting OCSP server ${OCSP_ALGORITHM}-${SERVER_TYPE}..."

CA_FILE="${OCSP_ALGORITHM}/ca.pem"
PORT=8100
ARGS="-p $PORT -v"

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

COMMAND="python -u"
if [ "$(uname -s)" != "Darwin" ]; then
  # On linux and windows host, we need to use nohup to daemonize the process
  # and prevent the task from hanging.
  # The macos hosts do not support nohup.
  COMMAND="nohup $COMMAND"
fi

$COMMAND ocsp_mock.py \
  --ca_file $CA_FILE \
  --ocsp_responder_cert $CERT \
  --ocsp_responder_key $KEY \
  $ARGS > ocsp_mock_server.log 2>&1 &
echo "$!" > ocsp.pid

await_server() {
    echo "Waiting on $1 server on port $2"
    for _ in $(seq 10); do
        # Exit code 7: "Failed to connect to host".
        if curl -s "localhost:$2"; test $? -ne 7; then
            echo "Waiting on $1 server on port $2...done"
            return 0
        else
            echo "Could not connect, sleeping."
            sleep 2
        fi
    done
    echo "Could not detect '$1' server on port $2"
    exit 1
}
await_server ocsp_mock.py $PORT
cat ocsp_mock_server.log
sleep 3

echo "Starting OCSP server ${OCSP_ALGORITHM}-${SERVER_TYPE}... done."
