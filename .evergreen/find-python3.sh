#!/usr/bin/env bash
#
# find-python3.sh
#
# Usage:
#   . /path/to/find-python3.sh
#
# This file defines the following utility functions:
#   - is_python3
#   - is_venv_capable
#   - is_virtualenv_capable
#   - find_python3
# These functions may be invoked from any working directory.

if [ -z "$BASH" ]; then
  echo "find-python3.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# is_python3
#
# Usage:
#   is_python3 python
#   is_python3 /path/to/python
#
# Parameters:
#   "$1": The name or path of the python binary to test.
#
# Return 0 (true) if the given argument "$1" is a Python 3 binary.
# Return a non-zero value (false) otherwise.
#
# Diagnostic messages may be printed to stderr (pipe 2). Redirect to /dev/null
# to silence these messages.
is_python3() (
  set -o errexit
  set -o pipefail

  # Binary to use, e.g. "python".
  local -r bin="${1:?'is_python3 requires a name or path of a python binary to test'}"

  # Binary must be executable.
  command -V "$bin" &>/dev/null || return

  # Reject binaries that do not support argument "-V".
  "$bin" -V &>/dev/null || return

  # Expect an output of the form: "Python x.y.z".
  # Note: Python 2 binaries output to stderr rather than stdout.
  local -r version_output="$("$bin" -V 2>&1 | tr -d '\n')"

  # For diagnostic purposes.
  echo " - $bin: $version_output"

  # Evaluate result of this function.
  # Note: Python True (1) and False (0) is treated as fail (1) and success (0)
  # by Bash; therefore `is_python3` returns "true" when `v < 3` is false.
  "$bin" -c "import sys; exit(sys.version_info[0] < 3)"
) 1>&2

# is_venv_capable
#
# Usage:
#   is_venv_capable python
#   is_venv_capable /path/to/python
#
# Parameters:
#   "$1": The name or path of the python binary to test.
#
# Return 0 (true) if the given argument "$1" can successfully evaluate the
# command:
#   "$1" -m venv venv
# and activate the created virtual environment.
# Return a non-zero value (false) otherwise.
#
# Diagnostic messages may be printed to stderr (pipe 2). Redirect to /dev/null
# to silence these messages.
is_venv_capable() (
  set -o errexit
  set -o pipefail

  local -r bin="${1:?'is_venv_capable requires a name or path of a python binary to test'}"

  # Use a temporary directory to avoid polluting the caller's environment.
  local -r tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  if [[ "$OSTYPE" == cygwin ]]; then
    local -r real_path="$(cygpath -aw "$tmp")" || return
  else
    local -r real_path="$tmp"
  fi

  "$bin" -m venv "$real_path" || return

  if [[ -f "$tmp/bin/activate" ]]; then
    # shellcheck source=/dev/null
    . "$tmp/bin/activate"
  elif [[ -f "$tmp/Scripts/activate" ]]; then
    dos2unix "$tmp/Scripts/activate" || return
    # shellcheck source=/dev/null
    . "$tmp/Scripts/activate"
  else
    echo "Could not find an activation script in $tmp!"
    return 1
  fi
) 1>&2

# is_virtualenv_capable
#
# Usage:
#   is_virtualenv_capable python
#   is_virtualenv_capable /path/to/python
#
# Parameters:
#   "$1": The name or path of the python binary to test.
#
# Return 0 (true) if the given argument $1 can successfully evaluate the
# command:
#   "$1" -m virtualenv -p "$1" venv
# and activate the created virtual environment.
# Return a non-zero value (false) otherwise.
#
# Diagnostic messages may be printed to stderr (pipe 2). Redirect to /dev/null
# to silence these messages.
is_virtualenv_capable() (
  set -o errexit
  set -o pipefail

  local -r bin="${1:?'is_virtualenv_capable requires a name or path of a python binary to test'}"

  # Use a temporary directory to avoid polluting the caller's environment.
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  local real_path
  if [[ "$OSTYPE" == cygwin ]]; then
    real_path="$(cygpath -aw "$tmp")" || return
  else
    real_path="$tmp"
  fi

  # -p: some old versions of virtualenv (e.g. installed on Debian 10) are buggy.
  # Without -p, the created virtual environment may use the wrong Python binary
  # (e.g. using a Python 2 binary even if it was created by a Python 3 binary).
  "$bin" -m virtualenv -p "$bin" "$real_path" || return

  if [[ -f "$tmp/bin/activate" ]]; then
    # shellcheck source=/dev/null
    . "$tmp/bin/activate"
  elif [[ -f "$tmp/Scripts/activate" ]]; then
    dos2unix "$tmp/Scripts/activate" || return
    # shellcheck source=/dev/null
    . "$tmp/Scripts/activate"
  else
    echo "Could not find an activation script in $tmp!"
    return 1
  fi
) 1>&2

# find_python3
#
# Usage:
#   find_python3
#   PYTHON_BINARY=$(find_python3)
#   PYTHON_BINARY=$(find_python3 2>/dev/null)
#
# Return 0 (true) if a Python 3 binary capable of creating a virtual environment
# with either venv or virtualenv can be found.
# Return a non-zero (false) value otherwise.
#
# If successful, print the name of the binary stdout (pipe 1).
# Otherwise, no output is printed to stdout (pipe 1).
#
# Diagnostic messages may be printed to stderr (pipe 2). Redirect to /dev/null
# with `2>/dev/null` to silence these messages.
#
# Example:
#   PYTHON_BINARY=$(find_python3)
#   if [[ -z "$PYTHON_BINARY" ]]; then
#     # Handle missing Python binary situation.
#   fi
#
#   if "$PYTHON_BINARY" -m venv -h; then
#     "$PYTHON_BINARY" -m venv venv
#   else
#     "$PYTHON_BINARY" -m virtualenv -p "$PYTHON_BINARY" venv
#   fi
find_python3() (
  set -o errexit
  set -o pipefail

  local -a bins=()
  local bin=""

  # The list of Python binaries to test for venv or virtualenv support.
  # The binaries are tested in the order of their position in the array.
  {
    echo "Finding python3 binaries to test..."

    append_bins() {
      local -r path="${1:?'missing path'}"
      shift
      local -r pattern="${1:?'missing pattern'}"
      shift
      local -ar suffixes=("${@:?'missing suffixes'}")

      for dir in $(find "$path" -maxdepth 1 -name "$pattern" -type d 2>/dev/null | sort -rV); do
        for bin in "${suffixes[@]}"; do
          if is_python3 "$dir/$bin"; then
            bins+=("$dir/$bin")
          fi
        done
      done
    }

    # C:/python/Python3X/bin/python
    append_bins "C:/python" "Python3[0-9]*" "python3.exe" "python.exe"

    # /opt/python/3.X/bin/python
    append_bins "/opt/python" "3.[0-9]*" "bin/python3" "bin/python"

    # /opt/mongodbtoolchain/vX/bin/python
    append_bins "/opt/mongodbtoolchain" "v[0-9]*" "bin/python3" "bin/python"

    bin="python3"
    if is_python3 "$bin"; then bins+=("$bin"); fi

    bin="python"
    if is_python3 "$bin"; then bins+=("$bin"); fi
  } 1>&2

  {
    # Some environments trigger an unbound variable error if "${bins[@]}" is empty when used below.
    if (("${#bins[@]}" == 0)); then
      echo "Could not find any python3 binaries!"
      return 1
    fi

    # For diagnostic purposes.
    echo "List of python3 binaries to test:"
    for bin in "${bins[@]}"; do
      echo " - $bin"
    done
  } 1>&2

  # Find a binary that is capable of venv or virtualenv and set it as `res`.
  local res=""
  {
    echo "Testing python3 binaries..."
    for bin in "${bins[@]}"; do
      {
        if ! is_venv_capable "$bin"; then
          echo " - $bin is not capable of venv"

          if ! is_virtualenv_capable "$bin"; then
            echo " - $bin is not capable of virtualenv"
            continue
          else
            echo " - $bin is capable of virtualenv"
          fi
        else
          echo " - $bin is capable of venv"
        fi
      } 1>&2

      res="$bin"
      break
    done

    if [[ -z "$res" ]]; then
      echo "Could not find a python3 binary capable of creating a virtual environment!"
      return 1
    fi
  } 1>&2

  echo "$res"

  return 0
)
