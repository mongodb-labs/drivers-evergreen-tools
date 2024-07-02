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
TARPATH=""

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
    TARPATH="google-cloud-sdk/bin/gcloud"
    BASE="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads"
    case "$OS_NAME-$MARCH" in
       linux-x86_64)
          # Use 393.0.0 for compat with debian 10.
          URL="$BASE/google-cloud-cli-393.0.0-linux-x86_64.tar.gz"
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
if [ -z "$TARPATH" ]; then
  curl -L -s $URL -o $TARGET || curl -L $URL -o $TARGET
else
  BASE_PATH=$(echo $TARPATH | cut -d/ -f1)
  pushd /tmp
  rm -rf $BASE_PATH
  curl -L -s $URL -o /tmp/$NAME.tgz || curl -L $URL -o $TARGET
  tar xfz $NAME.tgz
  mv $TARPATH $TARGET
  if [ "$NAME" == "gcloud" ]; then
    mv google-cloud-sdk/lib ${DRIVERS_TOOLS}/.bin/lib
  fi
  rm -rf $NAME $TARPATH
  popd
fi
chmod +x $TARGET
echo "Downloading $NAME... done."
