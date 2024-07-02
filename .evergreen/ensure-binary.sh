#!/bin/bash
#
# Ensure the given binary is on the PATH.

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

NAME=$1
if [ -z "$NAME" ]; then
  echo "Must supply a binary name!"
  exit 1
fi

if command -v $NAME &> /dev/null; then
  echo "$NAME found in PATH!"
  exit 0
fi

OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
MARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
TARGET=${DRIVERS_TOOLS}/.bin/$NAME
URL=""
PATH=""

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
    PATH="google-cloud-sdk/bin/gcloud"
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
  exit 1
fi

echo "Downloading $NAME..."
mkdir -p ${DRIVERS_TOOLS}/.bin
if [ -z "$PATH" ]; then
  curl -L -s --fail-with-body $URL -o $TARGET
else
  curl -L -s --fail-with-body $URL -o /tmp/$NAME
  tar xfz /tmp/$NAME
  mv /tmp/$NAME/$PATH $TARGET
  rm -rf /tmp/$NAME
fi
chmod +x $TARGET
echo "Downloading $NAME... done."
