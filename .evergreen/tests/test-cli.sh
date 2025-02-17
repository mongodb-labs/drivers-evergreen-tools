#!/usr/bin/env bash

# Test mongodl and mongosh_dl.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/..

bash install-cli.sh .
DOWNLOAD_DIR=mongodl_test

./socks5srv --help
./mongodl --help
./mongosh-dl --help

# Make sure we can install again.
bash install-cli.sh .

if [ "${OS:-}" != "Windows_NT" ]; then
  ./mongodl --edition enterprise --version 7.0 --component archive-debug --no-download
else
  DOWNLOAD_DIR=$(cygpath -m $DOWNLOAD_DIR)
fi

./mongodl --edition enterprise --version 7.0 --component archive --test
./mongodl --edition enterprise --version 7.0 --component cryptd --out ${DOWNLOAD_DIR} --strip-path-components 1
./mongosh-dl --no-download
./mongosh-dl --version 2.1.1 --no-download

export PATH="${DOWNLOAD_DIR}/bin:$PATH"
if [ "${OS:-}" != "Windows_NT" ]; then
  ./mongosh-dl --version 2.1.1 --out ${DOWNLOAD_DIR} --strip-path-components 1
  chmod +x ./mongodl_test/bin/mongosh
  ./mongodl_test/bin/mongosh --version
else
  ./mongosh-dl --version 2.1.1 --out ${DOWNLOAD_DIR} --strip-path-components 1
fi

# Ensure that we can use a downloaded mongodb directory.
rm -rf ${DOWNLOAD_DIR}
bash install-cli.sh "$(pwd)/orchestration"
./mongodl --edition enterprise --version 7.0 --component archive --out ${DOWNLOAD_DIR} --strip-path-components 2
./orchestration/drivers-orchestration run --existing-binaries-dir=${DOWNLOAD_DIR}
${DOWNLOAD_DIR}/mongod --version | grep v7.0
./orchestration/drivers-orchestration stop

if [ ${1:-} == "partial" ]; then
  popd
  make -C ${DRIVERS_TOOLS} test
  exit 0
fi

# Ensure that all distros are accounted for in DISTRO_ID_TO_TARGET
export VALIDATE_DISTROS=1
./mongodl --list
./mongodl --edition enterprise --version 7.0.6 --component archive --no-download
./mongodl --edition enterprise --version 3.6 --component archive --test
./mongodl --edition enterprise --version 4.0 --component archive --test
./mongodl --edition enterprise --version 4.2 --component archive --test
./mongodl --edition enterprise --version 4.4 --component archive --test
./mongodl --edition enterprise --version 5.0 --component archive --test
./mongodl --edition enterprise --version 6.0 --component crypt_shared --test
./mongodl --edition enterprise --version 8.0 --component archive --test
./mongodl --edition enterprise --version rapid --component archive --test
./mongodl --edition enterprise --version latest --component archive --out ${DOWNLOAD_DIR}
./mongodl --edition enterprise --version latest-build --component archive --test
./mongodl --edition enterprise --version latest-release --component archive --test
./mongodl --edition enterprise --version v6.0-perf --component cryptd --test
./mongodl --edition enterprise --version v8.0-perf --component cryptd --test

popd
make -C ${DRIVERS_TOOLS} test
