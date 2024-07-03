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
bash ../ensure-binary.sh kubectl

# Delete pods over one hour old in case they were not torn down.
kubectl get pods -o go-template --template '{{range .items}}{{.metadata.name}} {{.metadata.creationTimestamp}}{{"\n"}}{{end}}' | awk '$2 <= "'$(date -d'now-1 hours' -Ins --utc | sed 's/+0000/Z/')'" { print $1 }' | xargs --no-run-if-empty kubectl delete pod

# Wait for the new pod to be ready.
kubectl wait --for=condition=Ready pod/${POD_NAME} --timeout=600s

# Run the setup script and ensure git was installed.
kubectl cp ./remote-scripts/setup-pod.sh ${POD_NAME}:/tmp/setup-pod.sh
kubectl exec ${POD_NAME} -- /tmp/setup-pod.sh
kubectl exec ${POD_NAME} -- git --version

popd
