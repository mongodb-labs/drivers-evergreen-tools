#!/usr/bin/env bash
#
# Regression test for DRIVERS-3737: the auth_oidc k8s teardown scripts must
# exit cleanly and say what they skipped when setup fails early, instead of
# dying on unbound variables and skipping the remaining cleanup.
set -eu -o pipefail

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR/../handle-paths.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/k8s-teardown-test.XXXXXX")
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

# The fixtures run against an isolated copy of the scripts under $WORK, never
# against this checkout: a checkout can hold the cleanup state of a live
# deployment (the secrets-export.sh files are gitignored), and overwriting or
# deleting it here would leave that deployment unidentifiable for teardown.
FAKE="$WORK/drivers-tools"
K8S_DIR="$FAKE/.evergreen/auth_oidc/k8s"
ATLAS_SECRETS="$FAKE/.evergreen/atlas/secrets-export.sh"
EKS_SECRETS="$FAKE/.evergreen/k8s/eks/secrets-export.sh"
mkdir -p "$K8S_DIR" "$FAKE/.evergreen/k8s/eks" "$FAKE/.evergreen/k8s/aks" "$FAKE/.evergreen/k8s/gke" "$FAKE/.evergreen/atlas"
cp "$DRIVERS_TOOLS/.evergreen/handle-paths.sh" "$FAKE/.evergreen/"
cp "$DRIVERS_TOOLS/.evergreen/ensure-binary.sh" "$FAKE/.evergreen/"
cp "$DRIVERS_TOOLS/.evergreen/auth_oidc/k8s/teardown-pod.sh" \
  "$DRIVERS_TOOLS/.evergreen/auth_oidc/k8s/teardown.sh" "$K8S_DIR/"
cp "$DRIVERS_TOOLS/.evergreen/k8s/eks/teardown.sh" "$FAKE/.evergreen/k8s/eks/"
cp "$DRIVERS_TOOLS/.evergreen/k8s/aks/teardown.sh" "$FAKE/.evergreen/k8s/aks/"
cp "$DRIVERS_TOOLS/.evergreen/k8s/gke/teardown.sh" "$FAKE/.evergreen/k8s/gke/"
cp "$DRIVERS_TOOLS/.evergreen/k8s/delete-pod.sh" "$FAKE/.evergreen/k8s/"

# run_and_expect <description> <expected-substring> <command...>
run_and_expect() {
  local desc="$1" want="$2"
  shift 2
  local out rc
  set +e
  out=$("$@" 2>&1)
  rc=$?
  set -e
  echo "$out"
  if [ $rc -ne 0 ]; then
    echo "FAIL: $desc: expected exit 0, got $rc" >&2
    return 1
  fi
  if ! grep -q -- "$want" <<<"$out"; then
    echo "FAIL: $desc: expected output to contain '$want'" >&2
    return 1
  fi
  echo "PASS: $desc"
}

# 1. setup.sh never ran: no secrets files anywhere.
run_and_expect "teardown-pod.sh with no setup" "Skipping pod teardown" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"
run_and_expect "teardown.sh with no setup" "Skipping Atlas teardown" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown.sh"

# 2. setup.sh fetched secrets and failed at create_deployment (the evidence
#    case): k8s secrets exist, but no CLUSTER_NAME was recorded.
cat <<EOF > "$K8S_DIR/secrets-export.sh"
export OIDC_SERVER_TYPE=atlas
export OIDC_ATLAS_PUBLIC_API_KEY=fake
export OIDC_ATLAS_PRIVATE_API_KEY=fake
export OIDC_ATLAS_GROUP_ID=fake
export OIDC_ADMIN_USER=bob
export OIDC_ADMIN_PWD=pwd123
EOF
run_and_expect "teardown-pod.sh after setup.sh failure" "Skipping pod teardown" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"
run_and_expect "teardown.sh after setup.sh failure" "never created" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown.sh"

# 3. setup-pod.sh started but the variant setup failed before creating the
#    pod: the variant is recorded, but there is no K8S_POD_NAME.
cat <<EOF >> "$K8S_DIR/secrets-export.sh"
export K8S_VARIANT=eks
export K8S_VARIANT_DIR=$FAKE/.evergreen/k8s/eks
EOF
run_and_expect "teardown-pod.sh after variant setup failure" "no pod was created" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"
run_and_expect "teardown.sh after variant setup failure" "never created" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown.sh"

# 4. The pod was recorded but is already gone: kubectl reports NotFound, and
#    teardown must still succeed (--ignore-not-found), naming the namespace
#    the pod was created in rather than the kubeconfig's current one.
mkdir -p "$WORK/bin"
cat <<'EOF' > "$WORK/bin/kubectl"
#!/usr/bin/env bash
# Record the invocation and the kubeconfig it was handed; emulate a
# missing pod: fail unless --ignore-not-found is passed.
echo "FAKE-KUBECTL: kubectl $* (KUBECONFIG=${KUBECONFIG:-unset})"
case " $* " in
  *" --ignore-not-found "*) exit 0 ;;
esac
echo 'Error from server (NotFound): pods "test-eks-1" not found' >&2
exit 1
EOF
chmod +x "$WORK/bin/kubectl"
export PATH="$WORK/bin:$PATH"
echo "export K8S_POD_NAME=test-eks-1" > "$EKS_SECRETS"
run_and_expect "teardown-pod.sh deletes the eks pod from its namespace" \
  "FAKE-KUBECTL: kubectl delete pod test-eks-1 --namespace default --ignore-not-found --timeout=60s" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"

# 5. The deployment was created but the k8s secrets file carries no Atlas API
#    keys: teardown cannot delete it, so it must name the deployment that
#    needs manual cleanup (the task group's final cleanup step deletes the
#    secrets file the warning points at).
cat <<EOF > "$K8S_DIR/secrets-export.sh"
export OIDC_SERVER_TYPE=atlas
EOF
cat <<EOF > "$ATLAS_SECRETS"
export CLUSTER_NAME=regression-test-cluster
EOF
run_and_expect "teardown.sh without credentials names the deployment" "regression-test-cluster" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown.sh"

# 6. AKS: the pod is created in AKS_SERVICE_ACCOUNT_NAMESPACE, not the
#    kubeconfig's current namespace. Deletion must name that namespace
#    explicitly, or --ignore-not-found turns a wrong-namespace NotFound into
#    reported success while the pod keeps running.
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/az"
chmod +x "$WORK/bin/az"
cat <<EOF > "$FAKE/.evergreen/k8s/aks/secrets-export.sh"
export AKS_CLUSTER_NAME=fake-cluster
export AKS_RESOURCE_GROUP=fake-group
export AKS_SERVICE_ACCOUNT_NAMESPACE=aks-test-ns
export K8S_POD_NAME=test-aks-1
EOF
cat <<EOF > "$K8S_DIR/secrets-export.sh"
export OIDC_SERVER_TYPE=atlas
export K8S_VARIANT=aks
export K8S_VARIANT_DIR=$FAKE/.evergreen/k8s/aks
EOF
run_and_expect "teardown-pod.sh deletes the aks pod from its namespace" \
  "FAKE-KUBECTL: kubectl delete pod test-aks-1 --namespace aks-test-ns --ignore-not-found --timeout=60s" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"

# 7. GKE: the pod is created in the default namespace; deletion must name it
#    explicitly for the same reason as eks.
cat <<EOF > "$FAKE/.evergreen/k8s/gke/secrets-export.sh"
export K8S_POD_NAME=test-gke-1
EOF
cat <<EOF > "$K8S_DIR/secrets-export.sh"
export OIDC_SERVER_TYPE=atlas
export K8S_VARIANT=gke
export K8S_VARIANT_DIR=$FAKE/.evergreen/k8s/gke
EOF
run_and_expect "teardown-pod.sh deletes the gke pod from its namespace" \
  "FAKE-KUBECTL: kubectl delete pod test-gke-1 --namespace default --ignore-not-found --timeout=60s" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"

# 8. The deployment is recorded and the credentials are present: teardown must
#    hand them to teardown-atlas-cluster.sh. The real script talks to the Atlas
#    API, so the isolated tree gets a stub that records what it was handed.
cat <<'EOF' > "$FAKE/.evergreen/atlas/teardown-atlas-cluster.sh"
#!/usr/bin/env bash
echo "FAKE-ATLAS-TEARDOWN: ${DRIVERS_ATLAS_PUBLIC_API_KEY}/${DRIVERS_ATLAS_GROUP_ID}/${CLUSTER_NAME}"
EOF
cat <<EOF > "$K8S_DIR/secrets-export.sh"
export OIDC_SERVER_TYPE=atlas
export OIDC_ATLAS_PUBLIC_API_KEY=atlas-pub
export OIDC_ATLAS_PRIVATE_API_KEY=atlas-priv
export OIDC_ATLAS_GROUP_ID=atlas-grp
EOF
run_and_expect "teardown.sh deletes the recorded deployment" \
  "FAKE-ATLAS-TEARDOWN: atlas-pub/atlas-grp/regression-test-cluster" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown.sh"

# 9. AKS setup failed before fetching vault secrets: neither the pod nor the
#    namespace was ever recorded. Teardown must skip cleanly, not fail on the
#    missing namespace.
rm -f "$FAKE/.evergreen/k8s/aks/secrets-export.sh"
cat <<EOF > "$K8S_DIR/secrets-export.sh"
export OIDC_SERVER_TYPE=atlas
export K8S_VARIANT=aks
export K8S_VARIANT_DIR=$FAKE/.evergreen/k8s/aks
EOF
run_and_expect "teardown-pod.sh with no aks state skips" "no pod was created" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"

# 10. The group backstop loop: retries EVERY variant's pod, each with its
#    own kubeconfig and namespace. Without this, an earlier stage whose
#    in-stage deletion failed stays leaked once a later stage overwrites
#    the shared kubeconfig — the identity survives only in the log.
touch "$FAKE/.evergreen/k8s/eks/kubeconfig" \
  "$FAKE/.evergreen/k8s/gke/kubeconfig" \
  "$FAKE/.evergreen/k8s/aks/kubeconfig"
cat <<EOF > "$FAKE/.evergreen/k8s/aks/secrets-export.sh"
export AKS_CLUSTER_NAME=fake-cluster
export AKS_RESOURCE_GROUP=fake-group
export AKS_SERVICE_ACCOUNT_NAMESPACE=aks-test-ns
export K8S_POD_NAME=test-aks-1
EOF
cp "$DRIVERS_TOOLS/.evergreen/k8s/teardown-all-pods.sh" "$FAKE/.evergreen/k8s/"
run_and_expect "backstop loop deletes the eks pod with its own kubeconfig" \
  "FAKE-KUBECTL: kubectl delete pod test-eks-1 --namespace default --ignore-not-found --timeout=60s (KUBECONFIG=$FAKE/.evergreen/k8s/eks/kubeconfig)" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"
run_and_expect "backstop loop deletes the gke pod with its own kubeconfig" \
  "FAKE-KUBECTL: kubectl delete pod test-gke-1 --namespace default --ignore-not-found --timeout=60s (KUBECONFIG=$FAKE/.evergreen/k8s/gke/kubeconfig)" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"
run_and_expect "backstop loop deletes the aks pod with its own kubeconfig" \
  "FAKE-KUBECTL: kubectl delete pod test-aks-1 --namespace aks-test-ns --ignore-not-found --timeout=60s (KUBECONFIG=$FAKE/.evergreen/k8s/aks/kubeconfig)" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"

# 11. One variant's deletion failing must not mask the others: the loop
#    keeps going and says which variant needs manual cleanup.
cat <<'EOF' > "$WORK/bin/kubectl"
#!/usr/bin/env bash
echo "FAKE-KUBECTL: kubectl $* (KUBECONFIG=${KUBECONFIG:-unset})"
case "$*" in
  *test-gke-1*) echo 'simulated gke deletion failure' >&2; exit 1 ;;
esac
exit 0
EOF
run_and_expect "backstop loop names the variant whose teardown failed" \
  "WARNING: gke pod teardown failed" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"
run_and_expect "backstop loop still deletes later variants after a failure" \
  "FAKE-KUBECTL: kubectl delete pod test-aks-1 --namespace aks-test-ns --ignore-not-found --timeout=60s (KUBECONFIG=$FAKE/.evergreen/k8s/aks/kubeconfig)" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"

# 12. A kubeconfig without a secrets file (environment-supplied credentials
#    let setup reach the credential fetch, which then failed before any pod
#    was recorded): the backstop must skip that variant and still retry the
#    later ones, not die on the unguarded source.
cat <<'EOF' > "$WORK/bin/kubectl"
#!/usr/bin/env bash
echo "FAKE-KUBECTL: kubectl $* (KUBECONFIG=${KUBECONFIG:-unset})"
exit 0
EOF
rm "$EKS_SECRETS"
run_and_expect "backstop loop skips a variant with no secrets file" \
  "Skipping eks pod teardown: no secrets file" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"
run_and_expect "backstop loop still retries later variants" \
  "FAKE-KUBECTL: kubectl delete pod test-gke-1 --namespace default --ignore-not-found --timeout=60s (KUBECONFIG=$FAKE/.evergreen/k8s/gke/kubeconfig)" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"
run_and_expect "backstop loop retries the last variant too" \
  "FAKE-KUBECTL: kubectl delete pod test-aks-1 --namespace aks-test-ns --ignore-not-found --timeout=60s (KUBECONFIG=$FAKE/.evergreen/k8s/aks/kubeconfig)" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"

# 13. The kubeconfigs the stages write hold cluster credentials: they must
#     be gitignored like the secrets files, or a git add of the checkout
#     stages them.
for VARIANT in eks gke aks; do
  if ! git -C "$DRIVERS_TOOLS" check-ignore -q ".evergreen/k8s/$VARIANT/kubeconfig"; then
    echo "FAIL: .evergreen/k8s/$VARIANT/kubeconfig is not gitignored" >&2
    exit 1
  fi
done
echo "PASS: per-variant kubeconfigs are gitignored"

# 14. Environment-based AKS setup (env supplies the vault variables, so no
#     secrets write happens): setup must still persist the cluster, resource
#     group, and namespace it used, or teardown crashes on unbound variables
#     in shells that do not inherit the setup environment (the group
#     backstop) and the pod leaks.
mkdir -p "$FAKE/.evergreen/csfle/azurekms"
cp "$DRIVERS_TOOLS/.evergreen/csfle/azurekms/login.sh" "$FAKE/.evergreen/csfle/azurekms/"
cp "$DRIVERS_TOOLS/.evergreen/k8s/aks/setup.sh" "$FAKE/.evergreen/k8s/aks/"
# configure-pod.sh's pod setup is out of scope here; its kubectl/jq plumbing
# would need the whole retry machinery mocked.
printf '#!/usr/bin/env bash\necho "FAKE-CONFIGURE-POD: $*"\n' > "$FAKE/.evergreen/k8s/configure-pod.sh"
cat <<'EOF' > "$WORK/bin/az"
#!/usr/bin/env bash
case "$1 $2" in
  "version -o") echo "2.30.0" ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/az"
cat <<'EOF' > "$WORK/bin/kubectl"
#!/usr/bin/env bash
cat > /dev/null
echo "FAKE-KUBECTL: kubectl $* (KUBECONFIG=${KUBECONFIG:-unset})"
exit 0
EOF
chmod +x "$WORK/bin/kubectl"
rm "$FAKE/.evergreen/k8s/aks/secrets-export.sh"
env DRIVERS_TOOLS="$FAKE" \
  AZUREKMS_TENANTID=env-tenant AZUREKMS_CLIENTID=env-client AZUREKMS_SECRET=env-secret \
  AKS_CLUSTER_NAME=env-cluster AKS_RESOURCE_GROUP=env-group \
  AKS_SERVICE_ACCOUNT_NAMESPACE=env-ns AKS_SERVICE_ACCOUNT_NAME=env-sa \
  bash "$FAKE/.evergreen/k8s/aks/setup.sh" > /dev/null
if ! grep -q "export AKS_CLUSTER_NAME=env-cluster" "$FAKE/.evergreen/k8s/aks/secrets-export.sh" ||
  ! grep -q "export AKS_RESOURCE_GROUP=env-group" "$FAKE/.evergreen/k8s/aks/secrets-export.sh" ||
  ! grep -q "export AKS_SERVICE_ACCOUNT_NAMESPACE=env-ns" "$FAKE/.evergreen/k8s/aks/secrets-export.sh"; then
  echo "FAIL: aks setup did not persist the cluster settings teardown needs" >&2
  exit 1
fi
echo "PASS: env-based aks setup persists the cluster settings"
run_and_expect "aks teardown deletes the env-based pod from its persisted namespace" \
  "--namespace env-ns --ignore-not-found --timeout=60s" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/aks/teardown.sh"

make -C "$DRIVERS_TOOLS" test

# upload test results attaches ${PROJECT_DIRECTORY}/test-results.json, which
# the pre-task setup seeds with a failing placeholder: overwrite it on
# success (a failing run exits above). PROJECT_DIRECTORY is CI-only, so
# local runs fall back to the drivers-tools copy.
RESULTS_FILE="${PROJECT_DIRECTORY:-$DRIVERS_TOOLS}/test-results.json"
echo '{"results": [{ "status": "PASS", "test_file": "test-auth-oidc-k8s-teardown", "log_raw": "all teardown regression scenarios passed" }]}' > "$RESULTS_FILE"
