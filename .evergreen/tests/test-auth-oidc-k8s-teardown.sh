#!/usr/bin/env bash
#
# Regression test for DRIVERS-3737: the auth_oidc k8s teardown scripts must
# exit cleanly and say what they skipped when setup fails early, instead of
# dying on unbound variables and skipping the remaining cleanup.
set -eu -o pipefail

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR/../handle-paths.sh"

K8S_DIR="$DRIVERS_TOOLS/.evergreen/auth_oidc/k8s"
ATLAS_SECRETS="$DRIVERS_TOOLS/.evergreen/atlas/secrets-export.sh"
EKS_SECRETS="$DRIVERS_TOOLS/.evergreen/k8s/eks/secrets-export.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/k8s-teardown-test.XXXXXX")
cleanup() {
  rm -f "$K8S_DIR/secrets-export.sh" "$ATLAS_SECRETS" "$EKS_SECRETS"
  rm -rf "$WORK"
}
trap cleanup EXIT
rm -f "$K8S_DIR/secrets-export.sh" "$ATLAS_SECRETS" "$EKS_SECRETS"

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
  if ! grep -q "$want" <<<"$out"; then
    echo "FAIL: $desc: expected output to contain '$want'" >&2
    return 1
  fi
  echo "PASS: $desc"
}

# 1. setup.sh never ran: no secrets files anywhere.
run_and_expect "teardown-pod.sh with no setup" "Skipping pod teardown" bash "$K8S_DIR/teardown-pod.sh"
run_and_expect "teardown.sh with no setup" "Skipping Atlas teardown" bash "$K8S_DIR/teardown.sh"

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
run_and_expect "teardown-pod.sh after setup.sh failure" "Skipping pod teardown" bash "$K8S_DIR/teardown-pod.sh"
run_and_expect "teardown.sh after setup.sh failure" "never created" bash "$K8S_DIR/teardown.sh"

# 3. setup-pod.sh started but the variant setup failed before creating the
#    pod: the variant is recorded, but there is no K8S_POD_NAME.
cat <<EOF >> "$K8S_DIR/secrets-export.sh"
export K8S_VARIANT=eks
export K8S_VARIANT_DIR=$DRIVERS_TOOLS/.evergreen/k8s/eks
EOF
run_and_expect "teardown-pod.sh after variant setup failure" "no pod was created" bash "$K8S_DIR/teardown-pod.sh"
run_and_expect "teardown.sh after variant setup failure" "never created" bash "$K8S_DIR/teardown.sh"

# 4. The pod was recorded but is already gone: kubectl reports NotFound, and
#    teardown must still succeed (--ignore-not-found).
mkdir -p "$WORK/bin"
cat <<'EOF' > "$WORK/bin/kubectl"
#!/usr/bin/env bash
# Emulate a missing pod: fail unless --ignore-not-found is passed.
echo 'Error from server (NotFound): pods "test-eks-1" not found' >&2
case " $* " in
  *" --ignore-not-found "*) exit 0 ;;
esac
exit 1
EOF
chmod +x "$WORK/bin/kubectl"
export PATH="$WORK/bin:$PATH"
echo "export K8S_POD_NAME=test-eks-1" > "$EKS_SECRETS"
run_and_expect "teardown-pod.sh with a missing pod" "Tearing down eks pod... done." bash "$K8S_DIR/teardown-pod.sh"

make -C "$DRIVERS_TOOLS" test
