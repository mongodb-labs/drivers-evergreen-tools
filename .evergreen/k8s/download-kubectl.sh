#!/usr/bin/env bash
# Download kubectl CLI for Linux 64-bit (x86_64).
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

if command -v kubectl &> /dev/null; then
    echo "kubectl is on the path"
    KUBECTL=kubectl
elif [ -f $(pwd)/kubectl ]; then
    KUBECTL=$(pwd)/kubectl
else
    echo "Download kubectl ... begin"
    wget -q https://dl.k8s.io/release/v1.24.0/bin/linux/amd64/kubectl
    chmod +x kubectl
    KUBECTL=$(pwd)/kubectl
    echo "Download kubectl... end"
fi

popd
