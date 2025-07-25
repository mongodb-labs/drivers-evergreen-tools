#!/usr/bin/env bash
#
# Ensure the given binary is on the PATH.
# Should be called as:
# . $DRIVERS_TOOLS/.evergreen/ensure-binary.sh <binary-name>
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

_NAME=$1
if [ -z "$_NAME" ]; then
  echo "Must supply a binary name!"
  return 1
fi

if [ -z "$DRIVERS_TOOLS" ]; then
  echo "Must supply DRIVERS_TOOLS env variable!"
  return 1
fi

if command -v $_NAME &> /dev/null; then
  echo "$_NAME found in PATH!"
  return 0
fi

_OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
_MARCH=$(uname -m | tr '[:upper:]' '[:lower:]')

mkdir -p "${DRIVERS_TOOLS}/.bin"

case $_NAME in
  kubectl)
    _VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    _BASE="https://dl.k8s.io/release/$_VERSION/bin"
    case "$_OS_NAME-$_MARCH" in
        linux-x86_64)
          _URL="$_BASE/linux/amd64/kubectl"
        ;;
        linux-aarch64)
          _URL="$_BASE/linux/arm64/kubectl"
        ;;
        darwin-x86_64)
          _URL="$_BASE/darwin/amd64/kubectl"
        ;;
        darwin-arm64)
          _URL="$_BASE/darwin/arm64/kubectl"
        ;;
        *)
           echo "Unsupported for $_NAME: $_OS_NAME-$_MARCH"
           return 1
        ;;
    esac
    pushd "${DRIVERS_TOOLS}/.bin"
    "$SCRIPT_DIR/retry-with-backoff.sh" curl -L -s -O "$_URL"
    "$SCRIPT_DIR/retry-with-backoff.sh" curl -L -s -O "$_URL.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    chmod +x kubectl
    popd
  ;;
  gcloud)
    # NOTE: Google Cloud does not expose stable downloads with known shasums
    # https://cloud.google.com/sdk/docs/install#installation_instructions lists
    # shasums that change for every release.
    _BASE="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads"
    case "$_OS_NAME-$_MARCH" in
       linux-x86_64)
          _URL="$_BASE/google-cloud-cli-linux-x86_64.tar.gz"
        ;;
        linux-aarch64)
          _URL="$_BASE/google-cloud-cli-linux-arm.tar.gz"
        ;;
        darwin-x86_64)
          _URL="$_BASE/google-cloud-cli-darwin-x86_64.tar.gz"
        ;;
        darwin-arm64)
          _URL="$_BASE/google-cloud-cli-darwin-arm.tar.gz"
        ;;
        *)
           echo "Unsupported for $_NAME: $_OS_NAME-$_MARCH"
           return 1
        ;;
    esac

    # Google Cloud needs special handling: we need a symlink to the source location.
    pushd /tmp
    rm -rf google-cloud-sdk
    _FNAME=google-cloud-sdk.tgz
    "$SCRIPT_DIR/retry-with-backoff.sh" curl -L -s "$_URL" -o "/tmp/$_FNAME"
    tar xfz $_FNAME
    popd
    ln -s /tmp/google-cloud-sdk/bin/gcloud "$DRIVERS_TOOLS/.bin/gcloud"
  ;;
  *)
    echo "Unsupported download type $_NAME"
    return 1
  ;;
esac
