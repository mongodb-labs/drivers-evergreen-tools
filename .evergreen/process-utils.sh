#!/usr/bin/env bash
#
# process-utils.sh
#
# Usage:
#   . /path/to/process]-utils.sh
#
# This file defines the following functions:
#   - killport
# These functions may be invoked from any working directory.


# killport
#
# Usage:
#   killport 8889
#
# Parameters:
#   "$1": The port of the process to kill.
#   "$2": The signal to send, defaults to SIGTERM.
#
# Kill the process listening on the given port.
killport() {
  local -r port="${1:?'killport requires a port'}"
  local -r signal="${2:-15}"
  local pid=""

  if [[ "${OSTYPE:?}" == cygwin || "${OSTYPE:?}" == msys ]]; then
    for pid in $(netstat -ano | grep ":$port .* LISTENING" | awk '{print $5}' | tr -d '[:space:]'); do
      echo "Killing pid $pid for port $port with signal $signal using taskkill" 1>&2
      taskkill /F /T /PID "$pid" || true
    done
  elif [ -x "$(command -v lsof)" ]; then
    for pid in $(lsof -t "-i:$port" || true); do
      echo "Killing pid $pid for port $port with signal $signal using kill" 1>&2
      kill "$pid" -${signal} || true
    done
  elif [ -x "$(command -v fuser)" ]; then
    echo "Killing process using port $port with signal $signal using fuser" 1>&2
    fuser --kill -${signal} "$port/tcp" || true
  elif [ -x "$(command -v ss)" ]; then
    for pid in $(ss -tlnp "sport = :$port" | awk 'NR>1 {split($7,a,","); print a[1]}' | tr -d '[:space:]'); do
      echo "Killing pid $pid for port $port with signal $signal using kill" 1>&2
      kill "$pid" -${signal} || true
    done
  else
    echo "Unable to identify the OS (${OSTYPE:?}) or find necessary utilities (fuser/lsof/ss) to kill the process."
    exit 1
  fi
}
