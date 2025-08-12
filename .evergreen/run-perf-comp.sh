#!/usr/bin/env bash
set -eux pipefail

GOVERSION="${GOVERESION:-1.24}"
GOPATH="${GOPATH:-$HOME/go}"

# Detect OS
OS="$(uname -s)"

# If GOROOT is not set, determine it based on the OS and user-provided
# GOVERSION.
if [[ -z "${GOROOT:-}" ]]; then
  case "$OS" in
  Darwin)
    if [[ -d "/usr/local/go" ]]; then
      GOROOT="/usr/local/go" # likely place for local development
    else
      GOROOT="/opt/golang/go${GOVERSION}" # for spawn host
    fi
    ;;
  Linux)
    GOROOT="/opt/golang/go${GOVERSION}"
    ;;
  MINGW* | MSYS* | CYGWIN*)
    GOROOT="C:\\golang\\go${GOVERSION}"
    ;;
  *)
    echo "unsupported OS: $OS"
    exit 1
    ;;
  esac
fi

PATH="${GOROOT}/bin:${GOPATH}/bin:${PATH}"
export GOROOT PATH

echo "Using Go SDK at: $GOROOT (version: $GOVERSION)"

test -x "${GOROOT}/bin/go" || {
  echo "Go SDK not found at: $GOROOT"
  exit 1
}

# Resolve this script’s dir, then go up one level
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Enter the perfcomp sub‐directory
cd "$PROJECT_ROOT/.evergreen/perfcomp"

# Build the mongproxy binary.
bash build.sh

if [[ ! -x "./bin/perfcomp" ]]; then
  echo "Error: ./bin/perfcomp not found or not executable. Please run 'bash build.sh' first." >&2
  exit 1
else
  echo "Found ./bin/perfcomp"
fi

: "${PERF_URI_PRIVATE_ENDPOINT:?Error: PERF_URI_PRIVATE_ENDPOINT must be set}"
: "${VERSION_ID:?Error: VERSION_ID must be set}"

./bin/perfcomp compare ${VERSION_ID}

if [[ -n "${HEAD_SHA+set}" ]]; then
  ./bin/perfcomp mdreport
  rm perf-report.txt
fi
