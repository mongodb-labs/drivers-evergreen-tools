#!/usr/bin/env bash
# start the kmip server in the background.
set -eux

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
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
set -x
TMPDIR=$(mktemp -u) python -u kms_kmip_server.py --ca_file $CSFLE_TLS_CA_FILE --cert_file $CSFLE_TLS_CERT_FILE --port 5698 &
echo "$!" > kmip_pids.pid
sleep 1
nohup python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/expired.pem --port 8000 &
echo "$!" >> kmip_pids.pid
sleep 1
nohup python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/wrong-host.pem --port 8001 &
echo "$!" >> kmip_pids.pid
sleep 1
nohup python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/server.pem --port 8002 --require_client_cert &
echo "$!" >> kmip_pids.pid
sleep 1
nohup python bottle.py fake_azure:imds &
echo "$!" >> kmip_pids.pid
sleep 1
