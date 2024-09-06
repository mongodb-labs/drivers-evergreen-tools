#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

POD_NAME=$1
if [ -z ${POD_NAME} ]; then
    echo "Must supply a pod name as the first argument!"
    exit 1
fi
. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl

# Delete pods over one hour old in case they were not torn down.
echo "Deleting old pods..."
# Delete successful pods more than an hour old.
kubectl get pods -l app=test-pod -o go-template --template '{{range .items}}{{.metadata.name}} {{.metadata.creationTimestamp}}{{"\n"}}{{end}}' | awk '$2 <= "'$(date -d'now-1 hours' -Ins --utc | sed 's/+0000/Z/')'" { print $1 }' | xargs --no-run-if-empty kubectl delete pod
# Delete pending (stuck) pods more than 5 minutes old.
kubectl get pods --all-namespaces -l app=test-pod --field-selector=status.phase=Pending -o json | jq '.items[] | select((now - (.metadata.creationTimestamp | fromdateiso8601)) > 600) | .metadata.name' | xargs -I{} kubectl delete pod {} --force --grace-period=0
echo "Deleting old pods... done."

# Wait for the new pod to be ready.
echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/${POD_NAME} --timeout=2000s
kubectl get pods
echo "Waiting for pod to be ready... done."

# Run the setup script and ensure git was installed.
echo "Configuring pod $POD_NAME..."
set -x
# Account for initial error in connecting to pod.
. "$SCRIPT_DIR/../retry-with-backoff.sh"
retry_with_backoff kubectl cp ./remote-scripts/setup-pod.sh ${POD_NAME}:/tmp/setup-pod.sh
kubectl exec ${POD_NAME} -- /tmp/setup-pod.sh
kubectl exec ${POD_NAME} -- git --version
set +x
echo "Configuring pod $POD_NAME... done."

popd
