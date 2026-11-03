#!/usr/bin/env bash
# DRIVERS-3712 verification helpers for the MongoDB Cloud Tag Policy.
#
# Source this file, then pass each function a description and the JSON
# returned by the API/CLI call; it exits non-zero if mongodb-owner or
# mongodb-env is missing. Callers gate on VERIFY_MONGODB_TAGS. Uses python3
# (resolved via find-python3.sh, honoring DRIVERS_TOOLS_PYTHON) rather than
# jq, which not every distro has.

# Resolve the python binary once, at source time.
if [ -z "${VERIFY_TAGS_PYTHON:-}" ]; then
  # shellcheck source=./find-python3.sh
  . "$(dirname "${BASH_SOURCE[0]}")/find-python3.sh"
  VERIFY_TAGS_PYTHON=$(ensure_python3)
  if [ -z "${VERIFY_TAGS_PYTHON}" ]; then
    echo "verify-tags: no python3 found; cannot verify tags" 1>&2
    return 1
  fi
fi

# Checks a tags map as returned by the aws/az CLIs, e.g.
#   {"mongodb-owner": "...", "mongodb-env": "dev"}
# With a key argument (e.g. "labels"), the map is read from that key of the
# passed object instead (gcloud's `--format json(labels)` output).
verify_cloud_tags ()
{
  local description=$1
  local tags=$2
  local key=${3:-}
  echo "verify-tags: ${description} tags: ${tags}"
  if ! "${VERIFY_TAGS_PYTHON}" -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
except ValueError:
    sys.exit(1)
if sys.argv[2]:
    data = data.get(sys.argv[2]) if isinstance(data, dict) else None
if not isinstance(data, dict) or not data.get("mongodb-owner") or not data.get("mongodb-env"):
    sys.exit(1)
' "${tags}" "${key}" > /dev/null; then
    echo "verify-tags FAILED: ${description} lacks mongodb-owner/mongodb-env tags" 1>&2
    exit 1
  fi
  echo "verify-tags OK: ${description} carries mongodb-owner/mongodb-env"
}

# Checks a tags array as returned by the Atlas API, e.g.
#   [{"key": "mongodb-owner", "value": "..."}, {"key": "mongodb-env", ...}]
# With a key argument (e.g. "tags"), the array is read from that key of the
# passed object, so callers can pass the raw API response.
verify_atlas_tags ()
{
  local description=$1
  local tags=$2
  local key=${3:-}
  echo "verify-tags: ${description} tags: ${tags}"
  if ! "${VERIFY_TAGS_PYTHON}" -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
except ValueError:
    sys.exit(1)
if sys.argv[2]:
    data = data.get(sys.argv[2]) if isinstance(data, dict) else None
if not isinstance(data, list):
    sys.exit(1)
values = {t.get("key"): t.get("value") for t in data if isinstance(t, dict)}
if not values.get("mongodb-owner") or not values.get("mongodb-env"):
    sys.exit(1)
' "${tags}" "${key}" > /dev/null; then
    echo "verify-tags FAILED: ${description} lacks mongodb-owner/mongodb-env tags" 1>&2
    exit 1
  fi
  echo "verify-tags OK: ${description} carries mongodb-owner/mongodb-env"
}
