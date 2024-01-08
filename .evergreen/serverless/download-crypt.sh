#!/bin/sh

MONGODB_VERSION=${MONGODB_VERSION:-latest}

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

# Functions to fetch MongoDB binaries
. $SCRIPT_DIR/../download-mongodb.sh

get_distro
get_mongodb_download_url_for "$DISTRO" "$MONGODB_VERSION"

# Don't need to install the legacy shell
download_and_extract_package "$MONGODB_DOWNLOAD_URL" "$EXTRACT"

if [ -z $MONGO_CRYPT_SHARED_DOWNLOAD_URL ]; then
  echo "There is no crypt_shared library for distro='$DISTRO' and version='$MONGODB_VERSION'".
else
  echo "Downloading crypt_shared package from $MONGO_CRYPT_SHARED_DOWNLOAD_URL"
  download_and_extract_crypt_shared "$MONGO_CRYPT_SHARED_DOWNLOAD_URL" "$EXTRACT" CRYPT_SHARED_LIB_PATH
  echo "CRYPT_SHARED_LIB_PATH:" $CRYPT_SHARED_LIB_PATH
  if [ -z $CRYPT_SHARED_LIB_PATH ]; then
    echo "CRYPT_SHARED_LIB_PATH must be assigned, but wasn't" 1>&2 # write to stderr"
    exit 1
  fi
cat <<EOT >> serverless-expansion.yml
CRYPT_SHARED_LIB_PATH: "$CRYPT_SHARED_LIB_PATH"
EOT

fi
