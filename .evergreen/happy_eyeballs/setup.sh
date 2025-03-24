#!/usr/bin/env bash
# Start a happy eyeballs server.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR

# Ensure python3 here
. ../find-python3.sh

echo "Ensuring python binary..."
PYTHON="$(ensure_python3 2>/dev/null)"
if [ -z "${PYTHON}" ]; then
  # For debug purposes
  find_python3
  exit 1
fi
echo "Ensuring python binary... done."

echo "Starting Happy Eyeballs server..."

COMMAND="$PYTHON -u"
if [ "$(uname -s)" != "Darwin" ]; then
  # On windows host, we need to use nohup to daemonize the process
  # and prevent the task from hanging.
  # The macos hosts do not support nohup.
  COMMAND="nohup $COMMAND"
fi

$COMMAND server.py "$@" > server.log 2>&1 &
sleep 1
$PYTHON -u server.py "$@" --wait
cat server.log

echo "Starting Happy Eyeballs server... done."

popd
