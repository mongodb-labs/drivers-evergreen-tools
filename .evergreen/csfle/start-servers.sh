#!/usr/bin/env bash
# start the KMS servers in the background.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

if [ ! -f ./secrets-export.sh ]; then
    echo "Please run the setup-secrets.sh script"
    exit 1
fi

source ./secrets-export.sh

if [ -z "${CSFLE_TLS_CA_FILE-}" ]; then
    echo "Please run the setup-secrets.sh script"
    exit 1
fi

. ./stop-servers.sh

# Forcibly kill the process listening on the desired ports, most likely
# left running from a previous task.
. "$SCRIPT_DIR/../process-utils.sh"
for port in 5698 9000 9001 9002 8080; do
  killport $port 9
done

. ./activate-kmstlsvenv.sh

# The -u options forces the stdout and stderr streams to be unbuffered.
COMMAND="python -u"
if [ "$(uname -s)" != "Darwin" ]; then
  # On linux and windows host, we need to use nohup to daemonize the process
  # and prevent the task from hanging.
  # The macos hosts do not support nohup.
  COMMAND="nohup $COMMAND"
fi


echo "Starting KMIP Server..."
# TMPDIR is required to avoid "AF_UNIX path too long" errors.
TMPDIR="$(dirname "$DRIVERS_TOOLS")" $COMMAND kms_kmip_server.py --ca_file $CSFLE_TLS_CA_FILE --cert_file $CSFLE_TLS_CERT_FILE --port 5698 > kms_kmip_server.log 2>&1 &
echo "$!" > kmip_pids.pid
sleep 1
cat kms_kmip_server.log
echo "Starting KMIP Server...done."


echo "Starting HTTP Server 1..."
$COMMAND kms_http_server.py --ca_file $CSFLE_TLS_CA_FILE --cert_file ../x509gen/expired.pem --port 9000 > http1.log 2>&1 &
echo "$!" >> kmip_pids.pid
sleep 1
cat http1.log
echo "Starting HTTP Server 1...done."


echo "Starting HTTP Server 2..."
$COMMAND kms_http_server.py --ca_file $CSFLE_TLS_CA_FILE --cert_file ../x509gen/wrong-host.pem --port 9001 > http2.log 2>&1 &
echo "$!" >> kmip_pids.pid
sleep 1
cat http2.log
echo "Starting HTTP Server 2...done."


echo "Starting HTTP Server 3..."
$COMMAND kms_http_server.py --ca_file $CSFLE_TLS_CA_FILE --cert_file $CSFLE_TLS_CERT_FILE --port 9002 --require_client_cert > http3.log 2>&1 &
echo "$!" >> kmip_pids.pid
sleep 1
cat http3.log
echo "Starting HTTP Server 3...done."


echo "Starting Failpoint Server..."
$COMMAND kms_failpoint_server.py --port 9003 > failpoint.log 2>&1 &
echo "$!" >> kmip_pids.pid
echo "Starting Failpoint Server...done."
sleep 1

echo "Starting Fake Azure IMDS..."
$COMMAND bottle.py fake_azure:imds > fake_azure.log 2>&1 &
echo "$!" >> kmip_pids.pid
sleep 1
cat fake_azure.log
echo "Starting Fake Azure IMDS...done."

# Wait for all of the servers to start.
bash ./await-servers.sh
