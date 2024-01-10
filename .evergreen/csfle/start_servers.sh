#!/usr/bin/env bash
# start the kmip server in the background.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

if [ ! -f ./secrets-export.sh ]; then
    echo "Please run the setup_secrets.sh script"
    exit 1
fi

source ./secrets-export.sh

if [ -z "${CSFLE_TLS_CA_FILE-}" ]; then
    echo "Please run the setup_secrets.sh script"
    exit 1
fi

. ./stop_servers.sh
. ./activate-kmstlsvenv.sh

# The -u options forces the stdout and stderr streams to be unbuffered.
# TMPDIR is required to avoid "AF_UNIX path too long" errors.
echo "Starting KMIP Server..."
TMPDIR="$(dirname "$DRIVERS_TOOLS")" python -u kms_kmip_server.py --ca_file $CSFLE_TLS_CA_FILE --cert_file $CSFLE_TLS_CERT_FILE --port 5698 &
echo "$!" > kmip_pids.pid
echo "Starting KMIP Server...done."
sleep 1

echo "Starting HTTP Server 1..."
nohup python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/expired.pem --port 8000 &
echo "$!" >> kmip_pids.pid
echo "Starting HTTP Server 1...done."
sleep 1

echo "Starting HTTP Server 2..."
nohup python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/wrong-host.pem --port 8001 &
echo "$!" >> kmip_pids.pid
echo "Starting HTTP Server 2...done."
sleep 1

echo "Starting HTTP Server 3..."
nohup python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/server.pem --port 8002 --require_client_cert &
echo "$!" >> kmip_pids.pid
echo "Starting HTTP Server 3...done."
sleep 1

echo "Starting Fake Azure IMDS..."
nohup python bottle.py fake_azure:imds &
echo "$!" >> kmip_pids.pid
echo "Starting Fake Azure IMDS...done."
sleep 1

bash ./await_servers.sh

# Set up the kms server with initial SecretData.
set=0
echo "Setting up KMS Server..."
for _ in $(seq 1 1 10); do
   sleep 1
   if python -u kms_kmip_client.py; then
      echo "Setting up KMS Server...done."
      set=1
      break
   fi
done
if [ $set != 1 ]; then 
    echo 'Failed to start KMIP server!'
fi