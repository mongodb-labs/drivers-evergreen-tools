#!/usr/bin/env bash
# wait for the KMS servers to start.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

# Wait until the pids file has been created.
echo "Waiting for servers to start..."
await_pidfile() {
    for _ in $(seq 300); do
        if [ -f ./kmip_pids.pid ]; then
            return 0
        fi
        echo "PID file not detected ... sleeping"
        sleep 2
    done
    echo "Could not detect PID file"
    exit 1
}
await_pidfile
echo "Waiting for servers to start...done"

 # Ensure servers are running.
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
# * List servers to await here ...
await_server "HTTP" 9000
await_server "HTTP" 9001
await_server "HTTP" 9002
await_server "KMS Failpoint" 9003
await_server "Azure" 8080
await_server "KMIP" 5698

echo "Finished awaiting servers"
