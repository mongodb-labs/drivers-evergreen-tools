#!/usr/bin/env bash
set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

POD_NAME=$1
if [ -z ${POD_NAME} ]; then
    echo "Must supply a pod name as the first argument!"
    exit 1
fi
. ./download-kubectl.sh
$KUBECTL wait --for=condition=Ready pod/${POD_NAME} --timeout=60s
$KUBECTL cp ./remote-scripts/setup-pod.sh ${POD_NAME}:/tmp/setup-pod.sh
$KUBECTL exec ${POD_NAME} -- /tmp/setup-pod.sh
$KUBECTL exec ${POD_NAME} -- git --version
