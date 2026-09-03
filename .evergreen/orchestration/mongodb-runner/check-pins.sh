#!/usr/bin/env bash
# Check each committed mongodb-runner pin set. See the README in this directory.
# Takes any files inside a pin set and checks the set they belong to.
set -eu

# python3 is not guaranteed on PATH on Windows, where only "python" may resolve.
python=python3
command -v "$python" >/dev/null 2>&1 || python=python

status=0
while IFS= read -r pin; do
  if grep -q '"node_modules/mongodb-runner/node_modules/mongodb"' \
    "$pin/package-lock.json"; then
    echo "$pin: mongodb is nested under mongodb-runner, so this pin never reaches" \
      "the runner. See .evergreen/orchestration/mongodb-runner/README.md."
    status=1
  fi

  if ! "$python" -c '
import json, pathlib, sys

pin = pathlib.Path(sys.argv[1])
manifest = json.loads((pin / "package.json").read_text()).get("dependencies", {})
locked = json.loads((pin / "package-lock.json").read_text())["packages"][""]
if manifest != locked.get("dependencies", {}):
    sys.exit(
        f"{pin}: package.json and package-lock.json disagree; regenerate it with "
        "npm install --package-lock-only"
    )
' "$pin"; then
    status=1
  fi
done < <(for path in "$@"; do dirname "$path"; done | sort -u)
exit "$status"
