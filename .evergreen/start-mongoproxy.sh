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
      export GOROOT="/usr/local/go" # likely place for local development
    else
      export GOROOT="/opt/golang/go${GOVERSION}" # for spawn host
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

# Enter the mongoproxy sub‐directory
cd "$PROJECT_ROOT/.evergreen/mongoproxy"

# Build the mongproxy binary.
bash build.sh

if [[ ! -x "./bin/mongoproxy" ]]; then
  echo "Error: ./bin/mongoproxy not found or not executable. Please run 'bash build.sh' first." >&2
  exit 1
else
  echo "Found ./bin/mongoproxy"
fi

: "${MONGODB_URI:?Error: MONGODB_URI must be set}"

echo "Starting mongoproxy at ${MONGODB_URI}..."

# Build the proxy command
CMD=("./bin/mongoproxy" "--target-uri" "$MONGODB_URI")

# only if SSL exactly equals "ssl", inject certs
if [ "${SSL:-}" = "ssl" ]; then
  CMD+=(
    "--ca-file" "$DRIVERS_TOOLS/.evergreen/x509gen/ca.pem"
    "--key-file" "$DRIVERS_TOOLS/.evergreen/x509gen/client.pem"
  )
fi

exec "${CMD[@]}"
