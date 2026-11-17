#!/usr/bin/env bash
#
# Runs one oidc k8s test stage: sets up the pod, runs the self test (for
# atlas, also the driver test against a checkout archive), reports
# results, and tears the pod down when the stage ends, success or failure.
#
# Usage: run-test.sh <atlas|local> <eks|gke|aks>
set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

MODE=${1:?mode is required: atlas or local}
export K8S_VARIANT=${2:?variant is required: eks, gke, or aks}
case $MODE in
  atlas|local) ;;
  *) echo "Unknown mode: $MODE" >&2; exit 1 ;;
esac
# Per-stage kubeconfig, so the group backstop can retry any stage's pod.
export KUBECONFIG=$DRIVERS_TOOLS/.evergreen/k8s/$K8S_VARIANT/kubeconfig
# Tag-policy gate on the pod flow: aks checks cluster, node resources, and
# identity; eks the cluster. gke ignores the flag.
export VERIFY_MONGODB_TAGS=1
# Delete this stage's pod when the stage ends. Bounded at 60s: kubectl's
# --timeout does not bound the credential plugins, and a stall must
# neither hang the task nor mask the stage's status.
stage_exit() {
  rc=$?
  timeout 60 bash "${DRIVERS_TOOLS}/.evergreen/auth_oidc/k8s/teardown-pod.sh" || echo "WARNING: pod teardown failed; the pod above may need manual cleanup"
  exit $rc
}
trap stage_exit EXIT

cd $DRIVERS_TOOLS
bash ./.evergreen/auth_oidc/k8s/setup-pod.sh
if [ "$MODE" == "atlas" ]; then
  bash ./.evergreen/auth_oidc/k8s/run-self-test.sh
  export K8S_DRIVERS_TAR_FILE=/tmp/drivers-tools.tgz
  bash ./.evergreen/make-drivers-tools-archive.sh "$K8S_DRIVERS_TAR_FILE"
  export K8S_TEST_CMD="echo 'hello'"
  bash ./.evergreen/auth_oidc/k8s/run-driver-test.sh
else
  bash ./.evergreen/auth_oidc/k8s/start-server.sh
  bash ./.evergreen/auth_oidc/k8s/run-self-test.sh
fi
# Generate a test results file for the task's upload step.
cd "${PROJECT_DIRECTORY:-$DRIVERS_TOOLS}"
make test
