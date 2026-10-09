#!/usr/bin/env bash

# Test csfle
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
. $SCRIPT_DIR/../ensure-uv.sh
ensure_uv || exit 1

root=$(cd "$SCRIPT_DIR/../.." && pwd)

pushd $SCRIPT_DIR/../csfle

# The Python version is self-managed by uv.
bash ./setup.sh
bash ./teardown.sh

# The kms servers must also work on the newer interpreters the hosts will
# pick up. uv provisions 3.13/3.14 where it can; the legs reuse the fetched
# secrets.
for PY in 3.13 3.14; do
  if ! uv python find "$PY" > /dev/null 2>&1 && ! uv python install "$PY" > /dev/null 2>&1; then
    echo "Python $PY unavailable; skipping its kms server check"
    continue
  fi
  echo "Checking the kms servers on Python $PY"
  uv sync --project "$root" --group csfle --python "$PY"
  bash ./start-servers.sh
  bash ./teardown.sh
done

popd
