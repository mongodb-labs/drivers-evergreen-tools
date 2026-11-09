#!/usr/bin/env bash
# Clean up after setup.sh and compress the logs it streamed. No-op if no deployment was started.
#
# In Evergreen, the containers are already removed when this runs from `post` (see README.md). Run this in the same
# working directory as setup.sh.
#
# Output: sls-logs.txt.gz (in the working directory), when a deployment was started.

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

# Stop the log stream if it is still running (e.g. when processes are shared with this command). The stream runs in a
# subshell, so stop its children too.
if [[ -f "${LOGS_PID_FILE}" ]]; then
  declare logs_pid
  logs_pid="$(cat "${LOGS_PID_FILE}")"
  pkill -P "${logs_pid}" 2>/dev/null || true
  kill "${logs_pid}" 2>/dev/null || true
fi
if [[ -f "${LOGS_FILE}" ]]; then
  gzip -f "${LOGS_FILE}" || true
fi

# Evergreen's process cleanup has already removed the containers and images. Destroy the deployment only if it may still
# exist (e.g. when run locally), which avoids pulling the slslocal image again just to find nothing to delete.
if docker image inspect "${ECR_ROOT}/disagg-storage/slslocal:$(cat "${TAG_FILE}")" >/dev/null 2>&1; then
  run_slslocal --compose destroy || true
fi

# slslocal runs as root in its container, so some of the state it writes is owned by root.
sudo rm -rf "${STATE_DIR}" || true
