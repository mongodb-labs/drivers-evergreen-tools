#!/usr/bin/env bash
# wait for the kmip servers to start.
set -eux

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

. ./activate-kmstlsvenv.sh

 # Ensure servers are running.
await_server() {
    echo "Waiting on $1 server on port $2"
    for i in $(seq 10); do
        # Exit code 7: "Failed to connect to host".
        if curl -s "localhost:$2"; test $? -ne 7; then
            echo "Waiting on $1 server on port $2...done"
            return 0
        else
            echo "Could not connect, sleeping."
            sleep $i
        fi
    done
    echo "Could not detect '$1' server on port $2"
}
# * List servers to await here ...
await_server "HTTP" 8000
await_server "HTTP" 8001
await_server "HTTP" 8002
await_server "Azure" 8080
await_server "KMIP" 5698

# Ensure the kms server is working properly.
source ./secrets-export.sh
python -u kms_kmip_client.py

echo "Finished awaiting servers"
