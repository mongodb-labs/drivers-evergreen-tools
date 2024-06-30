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

case $NAME in
  kubectl)
    VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    case "$OS_NAME-$MARCH" in
        linux-x86_64)
          URL="https://dl.k8s.io/release/$VERSION/bin/linux/amd64/kubectl"
        ;;
        linux-aarch64)
          URL="https://dl.k8s.io/release/$VERSION/bin/linux/arm64/kubectl"
        ;;
        darwin-x86_64)
          URL="https://dl.k8s.io/release/$VERSION/bin/darwin/amd64/kubectl"
        ;;
        darwin-arm64)
          URL="https://dl.k8s.io/release/$VERSION/bin/darwin/arm64/kubectl"
        ;;
        windows64*)
          URL="https://dl.k8s.io/release/$VERSION/bin/windows/amd64/kubectl.exe"
        ;;
    esac
esac

if [ -z "$URL" ]; then
  echo "Unsupported for $NAME: $OS_NAME-$MARCH"
  exit 1
fi

echo "Downloading $NAME..."
mkdir -p ${DRIVERS_TOOLS}/.bin
curl -L -s --fail-with-body $URL -o $TARGET
chmod +x $TARGET
echo "Downloading $NAME... done."
