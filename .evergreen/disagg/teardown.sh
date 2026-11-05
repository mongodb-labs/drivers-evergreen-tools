#!/usr/bin/env bash
# Collect logs from and destroy a deployment started by setup.sh. No-op if none was started.
#
# Output: sls-logs.txt.gz (in the working directory), when a deployment was running.

set -o pipefail

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "${SCRIPT_DIR}/../handle-paths.sh"
# shellcheck source=.evergreen/disagg/common.sh
. "${SCRIPT_DIR}/common.sh"

# setup.sh writes the tag file before it changes anything else, so without it there is nothing to clean up.
if [[ ! -f "${TAG_FILE}" ]]; then
  echo "OK - no DSC deployment running"
  exit 0
fi

# Remove the replica set member names added to /etc/hosts by setup.sh.
sudo sed -i "/${HOSTS_MARKER}\$/d" /etc/hosts || true

run_slslocal --compose logs --follow=false >"$(pwd)/sls-logs.txt" 2>&1 || true
gzip -f "$(pwd)/sls-logs.txt" || true
run_slslocal --compose destroy || true
# slslocal runs as root in its container, so some of the state it writes is owned by root.
sudo rm -rf "${STATE_DIR}" || true
