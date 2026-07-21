#!/usr/bin/env bash
#
# ensure-uv.sh
#
# Usage:
#   . /path/to/ensure-uv.sh
#   ensure_uv || exit 1
#
# This file defines the following utility function:
#   - ensure_uv
# This function may be invoked from any working directory.

if [ -z "$BASH" ]; then
  echo "ensure-uv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# ensure_uv
#
# Usage:
#   ensure_uv
#
# Return 0 (true) if `uv` is available on PATH, installing it with
# `pip install --user uv` first if it was not already present.
# Return a non-zero value (false) otherwise, after printing an actionable
# error message to stderr.
#
# This does not scan the filesystem for toolchain-specific Python
# installations: it only checks PATH and falls back to a plain
# `pip install --user`.
ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    return 0
  fi

  local py=""
  if command -v python3 >/dev/null 2>&1; then
    py=python3
  elif command -v python >/dev/null 2>&1; then
    py=python
  fi

  if [ -n "$py" ]; then
    echo "uv not found on PATH; installing with '$py -m pip install --user uv'..." >&2
    "$py" -m pip install --user -q uv || true

    # `--user` installs console scripts into a version/platform-specific
    # directory (e.g. ~/.local/bin on Linux, ~/Library/Python/X.Y/bin on
    # macOS, %APPDATA%\Python\PythonXY\Scripts on Windows); ask the
    # interpreter where that is rather than assuming.
    declare user_base
    user_base="$("$py" -m site --user-base 2>/dev/null)" || user_base=""
    if [ -n "$user_base" ]; then
      export PATH="$user_base/bin:$user_base/Scripts:$PATH"
    fi
  fi

  if command -v uv >/dev/null 2>&1; then
    return 0
  fi

  cat <<'EOF' >&2
ERROR: could not find or install `uv`.

Install it manually, then re-run:
  https://docs.astral.sh/uv/getting-started/installation/

If you believe uv/pip should already be available in this environment,
please file a ticket in the DEVPROD Jira project:
  https://jira.mongodb.org/projects/DEVPROD
EOF
  return 1
}
