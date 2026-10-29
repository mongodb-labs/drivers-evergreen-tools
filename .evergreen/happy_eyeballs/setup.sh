#!/usr/bin/env bash
# Start a happy eyeballs server.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR

# Ensure uv is available here.
. ../ensure-uv.sh
ensure_uv || exit 1

echo "Starting Happy Eyeballs server..."

COMMAND="uv run python -u"
if [ "$(uname -s)" != "Darwin" ]; then
  # On windows host, we need to use nohup to daemonize the process
  # and prevent the task from hanging.
  # The macos hosts do not support nohup.
  COMMAND="nohup $COMMAND"
fi

$COMMAND server.py "$@" > server.log 2>&1 &
sleep 1
uv run python -u server.py "$@" --wait
cat server.log

echo "Starting Happy Eyeballs server... done."

popd
