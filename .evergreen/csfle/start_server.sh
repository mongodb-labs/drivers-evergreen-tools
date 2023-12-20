#!/usr/bin/env bash
# start the kmip server in the background.
set -eu

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

. ./stop_server.sh
. ./activate-kmstlsvenv.sh

# The -u options forces the stdout and stderr streams to be unbuffered.
# TMPDIR is required to avoid "AF_UNIX path too long" errors.
export TMPDIR="$(dirname "$SCRIPT_DIR")"
python -u kms_kmip_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/server.pem  --port 5698 &
python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/expired.pem --port 8000 &
sleep 1
python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/wrong-host.pem --port 8001 &
sleep 1
python -u kms_http_server.py --ca_file ../x509gen/ca.pem --cert_file ../x509gen/server.pem --port 8002 --require_client_cert &
sleep 1

pgrep -f "kms_...._server.py" > kmip_pids.pid

python -u kms_kmip_client.py
