#!/usr/bin/env bash
# start the kmip server in the background.
set -eu

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

CSFLE_TLS_CA_FILE=${CSFLE_TLS_CA_FILE:-"../x509gen/ca.pem"}
CSFLE_TLS_CERT_FILE=${CSFLE_TLS_CERT_FILE:-"../x509gen/server.pem"}

. ./stop_servers.sh
. ./activate-kmstlsvenv.sh

# The -u options forces the stdout and stderr streams to be unbuffered.
# TMPDIR is required to avoid "AF_UNIX path too long" errors.
TMPDIR=$(mktemp -u) python -u kms_kmip_server.py --ca_file $CSFLE_TLS_CA_FILE --cert_file $CSFLE_TLS_CERT_FILE --port 5698 &
echo "$!" > kmip_pids.pid
sleep 1
python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/expired.pem --port 8000 &
echo "$!" >> kmip_pids.pid
sleep 1
python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/wrong-host.pem --port 8001 &
echo "$!" >> kmip_pids.pid
sleep 1
python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/server.pem --port 8002 --require_client_cert &
echo "$!" >> kmip_pids.pid
sleep 1
python bottle.py fake_azure:imds &
echo "$!" >> kmip_pids.pid
sleep 1

# Wait for KMIP server to be available.
python -u kms_kmip_client.py

 # Ensure other mock servers are running before starting tests.
await_server() {
    echo "Waiting on $1 server on port $2"
    for i in $(seq 300); do
        # Exit code 7: "Failed to connect to host".
        if curl -s "localhost:$2"; test $? -ne 7; then
            echo "Waiting on $1 server on port $2...done"
            return 0
        else
            sleep 1
        fi
    done
    echo "could not detect '$1' server on port $2"
}
# * List servers to await here ...
await_server "KMS" 8000
await_server "KMS" 8001
await_server "KMS" 8002
await_server "Azure" 8080

echo "Finished awaiting servers"
