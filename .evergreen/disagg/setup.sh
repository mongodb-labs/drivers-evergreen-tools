#!/usr/bin/env bash
# Start an SLS deployment + disaggregated storage (DSC) mongods with `slslocal --compose`: one shard, a replica set of
# three mongods, across three cells.
#
# Inputs (environment):
#   DSC_SLS_TAG            SLS ECR image tag (default: newest mainline tag; see resolve_sls_tag).
#   DSC_MONGOD_TAG         mock-data-plane image tag, i.e. server commit (default: slslocal's pinned default).
#   AWS_*                  Credentials with ECR pull access (from ec2.assume_role).
#
# Output: dsc-expansion.yml (in the working directory) containing MONGODB_URI.

set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "${SCRIPT_DIR}/../handle-paths.sh"
# shellcheck source=.evergreen/disagg/common.sh
. "${SCRIPT_DIR}/common.sh"

[[ "$(uname -m)" == "x86_64" ]] || fail "expected an x86_64 host"
command -v docker >/dev/null 2>&1 || fail "'docker' is not installed on this host"
command -v aws >/dev/null 2>&1 || fail "the 'aws' CLI is not installed on this host"
command -v python3 >/dev/null 2>&1 || fail "'python3' is not installed on this host"
[[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || fail "AWS_ACCESS_KEY_ID is not set (expected ec2.assume_role credentials)"

# Ensure uv is available here.
. "${SCRIPT_DIR}/../ensure-uv.sh"
ensure_uv || exit 1

uri_py() {
  uv run --no-project --with "pymongo~=4.0" python "${SCRIPT_DIR}/uri.py" "${STATE_DIR}" "$@"
}

mkdir -p "${STATE_DIR}"

declare tag="${DSC_SLS_TAG:-}"
[[ -n "${tag}" ]] || tag="$(resolve_sls_tag)"
# Written before launching so teardown.sh knows a deployment may be running.
echo "${tag}" >"${TAG_FILE}"
echo "Using SLS image tag: ${tag}"

docker_login
write_aws_profile

declare image="${ECR_ROOT}/disagg-storage/slslocal:${tag}"
docker pull "${image}" || fail "docker pull of '${image}' failed"

declare -a launch_args=(
  --sls-ecr-tag "${tag}"
  --localstack
  --aws-profile-name default
  --num-cells 3
  --mongods-per-shard 3
)
if [[ -n "${DSC_MONGOD_TAG:-}" ]]; then
  launch_args+=(--mongod-tag "${DSC_MONGOD_TAG}")
fi

run_slslocal --compose launch "${launch_args[@]}" || fail "slslocal launch failed"
run_slslocal --compose wait --timeout 10m || fail "cluster did not become healthy within 10 minutes"

# The replica set members advertise names (shardN-nodeM-mongod) that only resolve inside the containers, but their
# ports are published on the host. Map the names to loopback so that replica set discovery works from the host.
declare -a member_names
mapfile -t member_names < <(uri_py --member-names)
[[ "${#member_names[@]}" -gt 0 ]] || fail "unable to determine replica set member names"
echo "127.0.0.1 ${member_names[*]} ${HOSTS_MARKER}" | sudo tee -a /etc/hosts >/dev/null ||
  fail "unable to add replica set member names to /etc/hosts"

# Build the connection string from ports.json, asking one node for the replica set name.
uri_py >dsc-expansion.yml || fail "unable to determine MONGODB_URI"
cat dsc-expansion.yml
