#!/usr/bin/env bash
#
# Ensure the given binary is on the PATH.
# Should be called as:
# . $DRIVERS_TOOLS/.evergreen/ensure-binary.sh <binary-name>
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

NAME=$1
if [ -z "$NAME" ]; then
  echo "Must supply a binary name!"
  return 1
fi

if [ -z "$DRIVERS_TOOLS" ]; then
  echo "Must supply DRIVERS_TOOLS env variable!"
  return 1
fi

# if command -v $NAME &> /dev/null; then
#   echo "$NAME found in PATH!"
#   return 0
# fi

OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
MARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
URL=""

case $NAME in
  kubectl)
    VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    BASE="https://dl.k8s.io/release/$VERSION/bin"
    case "$OS_NAME-$MARCH" in
        linux-x86_64)
          URL="$BASE/linux/amd64/kubectl"
        ;;
        linux-aarch64)
          URL="$BASE/linux/arm64/kubectl"
        ;;
        darwin-x86_64)
          URL="$BASE/darwin/amd64/kubectl"
        ;;
        darwin-arm64)
          URL="$BASE/darwin/arm64/kubectl"
        ;;
    esac
  ;;
  gcloud)
    BASE="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads"
    case "$OS_NAME-$MARCH" in
       linux-x86_64)
          URL="$BASE/google-cloud-cli-linux-x86_64.tar.gz"
        ;;
        linux-aarch64)
          URL="$BASE/google-cloud-cli-linux-arm.tar.gz"
        ;;
        darwin-x86_64)
          URL="$BASE/google-cloud-cli-darwin-x86_64.tar.gz"
        ;;
        darwin-arm64)
          URL="$BASE/google-cloud-cli-darwin-arm.tar.gz"
        ;;
      esac
esac

if [ -z "$URL" ]; then
  echo "Unsupported for $NAME: $OS_NAME-$MARCH"
  return 1
fi

echo "Installing $NAME..."

if [ "$NAME" != "gcloud" ]; then
  mkdir -p ${DRIVERS_TOOLS}/.bin
  TARGET=${DRIVERS_TOOLS}/.bin/$NAME
  "$SCRIPT_DIR/retry-with-backoff.sh" curl -L -s $URL -o $TARGET
  chmod +x $TARGET

else
  # Google Cloud needs special handling: we need a symlink to the source location.
  pushd /tmp
  rm -rf google-cloud-sdk
  FNAME=/tmp/google-cloud-sdk.tgz
  "$SCRIPT_DIR/retry-with-backoff.sh" curl -L -s $URL -o $FNAME
  tar xfz $FNAME
  popd
  ln -s /tmp/google-cloud-sdk/bin/gcloud $DRIVERS_TOOLS/.bin/gcloud
fi

echo "Installing $NAME... done."
