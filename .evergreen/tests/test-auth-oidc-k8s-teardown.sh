#!/usr/bin/env bash
#
# Regression test for DRIVERS-3737: the auth_oidc k8s teardown must skip
# cleanly when setup fails early, delete every pod with an explicit
# namespace, and retry every variant in the group backstop.
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
  "$DRIVERS_TOOLS/.evergreen/auth_oidc/k8s/teardown.sh" \
  "$DRIVERS_TOOLS/.evergreen/auth_oidc/k8s/run-test.sh" "$K8S_DIR/"
cp "$DRIVERS_TOOLS/.evergreen/k8s/eks/teardown.sh" "$FAKE/.evergreen/k8s/eks/"
cp "$DRIVERS_TOOLS/.evergreen/k8s/aks/teardown.sh" "$FAKE/.evergreen/k8s/aks/"
cp "$DRIVERS_TOOLS/.evergreen/k8s/gke/teardown.sh" "$FAKE/.evergreen/k8s/gke/"
cp "$DRIVERS_TOOLS/.evergreen/k8s/delete-pod.sh" \
  "$DRIVERS_TOOLS/.evergreen/k8s/teardown-all-pods.sh" "$FAKE/.evergreen/k8s/"

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

# run_expect_status <expected-rc> <description> <expected-substring> <command...>
run_expect_status() {
  local want_rc="$1" desc="$2" want="$3"
  shift 3
  local out rc
  set +e
  out=$("$@" 2>&1)
  rc=$?
  set -e
  echo "$out"
  if [ $rc -ne $want_rc ]; then
    echo "FAIL: $desc: expected exit $want_rc, got $rc" >&2
    return 1
  fi
  if ! grep -q -- "$want" <<<"$out"; then
    echo "FAIL: $desc: expected output to contain '$want'" >&2
    return 1
  fi
  echo "PASS: $desc"
}

# 1. Teardown skips cleanly at each setup-failure depth instead of dying on
#    unbound variables or skipping the remaining cleanup.
run_and_expect "teardown-pod.sh with no setup" "Skipping pod teardown" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"
run_and_expect "teardown.sh with no setup" "Skipping Atlas teardown" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown.sh"
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
cat <<EOF >> "$K8S_DIR/secrets-export.sh"
export K8S_VARIANT=eks
export K8S_VARIANT_DIR=$FAKE/.evergreen/k8s/eks
EOF
run_and_expect "teardown-pod.sh after variant setup failure" "no pod was created" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"
cat <<EOF > "$K8S_DIR/secrets-export.sh"
export OIDC_SERVER_TYPE=atlas
export K8S_VARIANT=aks
export K8S_VARIANT_DIR=$FAKE/.evergreen/k8s/aks
EOF
run_and_expect "teardown-pod.sh with no aks state skips" "no pod was created" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"

# 2. The stage trap path deletes the pod from the namespace it was created
#    in (--ignore-not-found, bounded), not the kubeconfig's current one.
mkdir -p "$WORK/bin"
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
cat <<EOF > "$K8S_DIR/secrets-export.sh"
export OIDC_SERVER_TYPE=atlas
export K8S_VARIANT=eks
export K8S_VARIANT_DIR=$FAKE/.evergreen/k8s/eks
EOF
run_and_expect "teardown-pod.sh deletes the eks pod from its namespace" \
  "FAKE-KUBECTL: kubectl delete pod test-eks-1 --namespace default --ignore-not-found --timeout=60s" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown-pod.sh"

# 3. The Atlas teardown: name the deployment when it cannot delete it, and
#    hand the recorded credentials to teardown-atlas-cluster.sh when it can.
cat <<EOF > "$K8S_DIR/secrets-export.sh"
export OIDC_SERVER_TYPE=atlas
EOF
cat <<EOF > "$ATLAS_SECRETS"
export CLUSTER_NAME=regression-test-cluster
EOF
run_and_expect "teardown.sh without credentials names the deployment" "regression-test-cluster" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/teardown.sh"
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

# 4. The group backstop retries EVERY variant's pod, each with its own
#    kubeconfig and namespace: an earlier stage whose in-stage deletion
#    failed stays retryable after later stages run.
touch "$FAKE/.evergreen/k8s/eks/kubeconfig" \
  "$FAKE/.evergreen/k8s/gke/kubeconfig" \
  "$FAKE/.evergreen/k8s/aks/kubeconfig"
printf 'export K8S_POD_NAME=test-gke-1\n' > "$FAKE/.evergreen/k8s/gke/secrets-export.sh"
cat <<EOF > "$FAKE/.evergreen/k8s/aks/secrets-export.sh"
export AKS_CLUSTER_NAME=fake-cluster
export AKS_RESOURCE_GROUP=fake-group
export AKS_SERVICE_ACCOUNT_NAMESPACE=aks-test-ns
export K8S_POD_NAME=test-aks-1
EOF
run_and_expect "backstop loop deletes the eks pod with its own kubeconfig" \
  "FAKE-KUBECTL: kubectl delete pod test-eks-1 --namespace default --ignore-not-found --timeout=60s (KUBECONFIG=$FAKE/.evergreen/k8s/eks/kubeconfig)" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"
run_and_expect "backstop loop deletes the gke pod with its own kubeconfig" \
  "FAKE-KUBECTL: kubectl delete pod test-gke-1 --namespace default --ignore-not-found --timeout=60s (KUBECONFIG=$FAKE/.evergreen/k8s/gke/kubeconfig)" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"
run_and_expect "backstop loop deletes the aks pod with its own kubeconfig" \
  "FAKE-KUBECTL: kubectl delete pod test-aks-1 --namespace aks-test-ns --ignore-not-found --timeout=60s (KUBECONFIG=$FAKE/.evergreen/k8s/aks/kubeconfig)" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"

# 5. One variant's deletion failing must not mask the others: the loop
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
  "--namespace aks-test-ns --ignore-not-found --timeout=60s" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"

# 6. A kubeconfig without a secrets file (environment-supplied credentials,
#    or a failure before the pod record): skip that variant, retry the rest.
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
  "--namespace aks-test-ns --ignore-not-found --timeout=60s" \
  env DRIVERS_TOOLS="$FAKE" bash "$FAKE/.evergreen/k8s/teardown-all-pods.sh"

# 7. The kubeconfigs the stages write hold cluster credentials: gitignore
#    them like the secrets files.
for VARIANT in eks gke aks; do
  if ! git -C "$DRIVERS_TOOLS" check-ignore -q ".evergreen/k8s/$VARIANT/kubeconfig"; then
    echo "FAIL: .evergreen/k8s/$VARIANT/kubeconfig is not gitignored" >&2
    exit 1
  fi
done
echo "PASS: per-variant kubeconfigs are gitignored"

# 8. Environment-based aks setup (env supplies the vault variables) must
#    persist the cluster settings teardown needs, or teardown crashes on
#    unbound variables in shells that do not inherit the setup environment.
mkdir -p "$FAKE/.evergreen/csfle/azurekms"
cp "$DRIVERS_TOOLS/.evergreen/csfle/azurekms/login.sh" "$FAKE/.evergreen/csfle/azurekms/"
cp "$DRIVERS_TOOLS/.evergreen/k8s/aks/setup.sh" "$FAKE/.evergreen/k8s/aks/"
# configure-pod.sh's pod setup is out of scope here; its kubectl/jq plumbing
# would need the whole retry machinery mocked.
printf '#!/usr/bin/env bash\necho "FAKE-CONFIGURE-POD: $*"\n' > "$FAKE/.evergreen/k8s/configure-pod.sh"
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

# 9. The stage's EXIT trap: a mid-stage failure still tears the pod down
#    and reports the stage's own status; a teardown failure warns without
#    masking it.
cat <<EOF > "$K8S_DIR/secrets-export.sh"
export OIDC_SERVER_TYPE=atlas
export K8S_VARIANT=eks
export K8S_VARIANT_DIR=$FAKE/.evergreen/k8s/eks
EOF
echo "export K8S_POD_NAME=test-eks-1" > "$EKS_SECRETS"
printf '#!/usr/bin/env bash\necho FAKE-SETUP-POD\n' > "$K8S_DIR/setup-pod.sh"
printf '#!/usr/bin/env bash\nexit 7\n' > "$K8S_DIR/run-self-test.sh"
run_expect_status 7 "the stage trap tears down the pod and preserves the failure status" \
  "delete pod test-eks-1 --namespace default" \
  env DRIVERS_TOOLS="$FAKE" bash "$K8S_DIR/run-test.sh" atlas eks
run_expect_status 7 "the stage trap warns without masking when teardown fails" \
  "WARNING: pod teardown failed" \
  env DRIVERS_TOOLS="$FAKE" PATH="/usr/bin:/bin" bash "$K8S_DIR/run-test.sh" atlas eks

# 10. Both k8s test functions must call the stage runner.
if [ "$(grep -c 'auth_oidc/k8s/run-test.sh' "$DRIVERS_TOOLS/.evergreen/config.yml")" -ne 2 ]; then
  echo "FAIL: both k8s test functions must call auth_oidc/k8s/run-test.sh" >&2
  exit 1
fi
echo "PASS: both k8s test functions call the stage runner"

make -C "$DRIVERS_TOOLS" test

# upload test results attaches ${PROJECT_DIRECTORY}/test-results.json, which
# the pre-task setup seeds with a failing placeholder: overwrite it on
# success (a failing run exits above). PROJECT_DIRECTORY is CI-only, so
# local runs fall back to the drivers-tools copy.
RESULTS_FILE="${PROJECT_DIRECTORY:-$DRIVERS_TOOLS}/test-results.json"
echo '{"results": [{ "status": "PASS", "test_file": "test-auth-oidc-k8s-teardown", "log_raw": "all teardown regression scenarios passed" }]}' > "$RESULTS_FILE"
