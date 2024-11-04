#!/usr/bin/env bash

# Test mongodl and mongosh-dl.
set -eux

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/..

. find-python3.sh
PYTHON=$(ensure_python3)
echo "Using PYTHON: $PYTHON"
DOWNLOAD_DIR=mongodl_test

if [ "${OS:-}" != "Windows_NT" ]; then
  $PYTHON mongodl.py --edition enterprise --version 7.0 --component archive-debug --no-download
else
  DOWNLOAD_DIR=$(cygpath -m $DOWNLOAD_DIR)
fi

$PYTHON mongodl.py --edition enterprise --version 7.0 --component archive --test
$PYTHON mongodl.py --edition enterprise --version 7.0 --component cryptd --out ${DOWNLOAD_DIR} --strip-path-components 1
$PYTHON mongosh-dl.py --no-download
$PYTHON mongosh-dl.py --version 2.1.1 --no-download

export PATH="${DOWNLOAD_DIR}/bin:$PATH"
if [ "${OS:-}" != "Windows_NT" ]; then
  $PYTHON mongosh-dl.py --version 2.1.1 --out ${DOWNLOAD_DIR} --strip-path-components 1
  chmod +x ./mongodl_test/bin/mongosh
  ./mongodl_test/bin/mongosh --version
else
  $PYTHON mongosh-dl.py --version 2.1.1 --out ${DOWNLOAD_DIR} --strip-path-components 1
fi

if [ ${1:-} == "partial" ]; then
  popd
  make -C ${DRIVERS_TOOLS} test
  exit 0
fi

# Ensure that all distros are accounted for in DISTRO_ID_TO_TARGET
export VALIDATE_DISTROS=1
$PYTHON mongodl.py --list
$PYTHON mongodl.py --edition enterprise --version 7.0.6 --component archive --no-download
$PYTHON mongodl.py --edition enterprise --version 3.6 --component archive --test
$PYTHON mongodl.py --edition enterprise --version 4.0 --component archive --test
$PYTHON mongodl.py --edition enterprise --version 4.2 --component archive --test
$PYTHON mongodl.py --edition enterprise --version 4.4 --component archive --test
$PYTHON mongodl.py --edition enterprise --version 5.0 --component archive --test
$PYTHON mongodl.py --edition enterprise --version 6.0 --component crypt_shared --test
$PYTHON mongodl.py --edition enterprise --version 8.0 --component archive --test
$PYTHON mongodl.py --edition enterprise --version rapid --component archive --test
$PYTHON mongodl.py --edition enterprise --version latest --component archive --out ${DOWNLOAD_DIR}
$PYTHON mongodl.py --edition enterprise --version v6.0-perf --component cryptd --test
$PYTHON mongodl.py --edition enterprise --version v8.0-perf --component cryptd --test

popd
make -C ${DRIVERS_TOOLS} test
