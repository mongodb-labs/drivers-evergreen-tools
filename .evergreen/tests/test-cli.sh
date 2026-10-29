#!/usr/bin/env bash

# Test mongodl and mongosh_dl.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
. $SCRIPT_DIR/../ensure-uv.sh

pushd $SCRIPT_DIR/..

# The gpg checks below invoke uv directly, and install-cli.sh's own ensure_uv
# runs in a child process, whose PATH changes never reach this shell.
ensure_uv || exit 1

# Ensure we can run clean before the cli is installed.
make clean

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

./mongodl --edition enterprise --version 7.0 --component archive --test --retries 5
./mongodl --edition enterprise --version 7.0 --component cryptd --out ${DOWNLOAD_DIR} --strip-path-components 1 --retries 5
./mongosh-dl --no-download
./mongosh-dl --version 2.1.1 --no-download

export PATH="${DOWNLOAD_DIR}/bin:$PATH"
if [ "${OS:-}" != "Windows_NT" ]; then
  ./mongosh-dl --version 2.1.1 --out ${DOWNLOAD_DIR} --strip-path-components 1 --retries 5
  # mongosh 2.1.1's bundled OpenSSL rejects RHEL 9's crypto-policy option in
  # /etc/pki/tls/openssl.cnf; an empty config keeps this download check running.
  OPENSSL_CONF=/dev/null ./mongodl_test/bin/mongosh --version
else
  ./mongosh-dl --version 2.1.1 --out ${DOWNLOAD_DIR} --strip-path-components 1 --retries 5
fi

# Ensure that we can use a downloaded mongodb directory.
rm -rf ${DOWNLOAD_DIR}
bash install-cli.sh "$(pwd)/orchestration"
./mongodl --edition enterprise --version 7.0 --component archive --out ${DOWNLOAD_DIR} --strip-path-components 2 --retries 5
./orchestration/drivers-orchestration run --existing-binaries-dir=${DOWNLOAD_DIR} --version 7.0
${DOWNLOAD_DIR}/mongod --version | grep v7.0
./orchestration/drivers-orchestration stop

# Ensure we can use a downloaded mongodb directory in start-orchestration.
./orchestration/drivers-orchestration start --mongodb-binaries=${DOWNLOAD_DIR}
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
# TODO (DRIVERS-3666): remove the IS_AMAZON2023 detection and its guards
# once DEVPROD-44314 ships full gnupg2.
IS_AMAZON2023=0
if [ -r /etc/os-release ]; then
  . /etc/os-release
  if [ "${ID:-}" = "amzn" ] && [ "${VERSION_ID:-}" = "2023" ]; then
    IS_AMAZON2023=1
  fi
fi
if [ ${IS_AMAZON2023} = 0 ]; then
  # MongoDB has never published enterprise builds of the legacy series
  # (3.6-5.0) for amazon2023, so their URL resolution can only be exercised
  # on other distros.
  ./mongodl --edition enterprise --version 3.6 --component archive --test --retries 5
  ./mongodl --edition enterprise --version 4.0 --component archive --test --retries 5
  ./mongodl --edition enterprise --version 4.2 --component archive --test --retries 5
  ./mongodl --edition enterprise --version 4.4 --component archive --test --retries 5
  ./mongodl --edition enterprise --version 5.0 --component archive --test --retries 5
fi
./mongodl --edition enterprise --version 6.0 --component crypt_shared --test --retries 5
./mongodl --edition enterprise --version 8.0 --component archive --test --retries 5
./mongodl --edition enterprise --version rapid --component archive --test --retries 5
./mongodl --edition enterprise --version latest --component archive --out ${DOWNLOAD_DIR} --retries 5
./mongodl --edition enterprise --version latest-build --component archive --test --retries 5 >latest-build.log 2>&1
# The master-nightly artifact is always published with a signature; a
# missing signature would be a publication regression.
if command -v gpg >/dev/null 2>&1; then
  if [ ${IS_AMAZON2023} = 1 ]; then
    grep -q "DEVPROD-44314" latest-build.log
    # Broken gpg is a host property: --target must not re-enable verification.
    ./mongodl --edition enterprise --version latest-build --component archive --target amazon2023 --test --retries 5 >latest-build-target.log 2>&1
    grep -q "DEVPROD-44314" latest-build-target.log
  else
    grep -q "Verified GPG signature" latest-build.log
    # A capable host must verify amazon2023 artifacts: tolerance is host-keyed.
    ./mongodl --edition enterprise --version latest-build --component archive --target amazon2023 --test --retries 5 >latest-build-target.log 2>&1
    grep -q "Verified GPG signature" latest-build-target.log
  fi
else
  grep -q "gpg is not installed" latest-build.log
fi
SERVER_ARTIFACTS_SKIP_SIGNATURE_VERIFICATION=1 ./mongodl --edition enterprise --version latest-build --component archive --test --retries 5 >latest-build-skip.log 2>&1
grep -q "SERVER_ARTIFACTS_SKIP_SIGNATURE_VERIFICATION is set" latest-build-skip.log
# Signature-verification and retry-loop tests; each test skips itself where
# it cannot apply. Relative to cwd: SCRIPT_DIR is invalid after the pushd.
PYTHONPATH=. uv run --no-project python tests/test-cli.py -v
./mongodl --edition enterprise --version latest-release --component archive --test --retries 5
./mongodl --edition enterprise --version latest-stable --component archive --test --retries 5
if [ ${IS_AMAZON2023} = 0 ]; then
  # The perf tags' cryptd builds may not exist for every target (the 6.0
  # pin predates amazon2023); the fully-featured distros cover them.
  ./mongodl --edition enterprise --version v6.0-perf --component cryptd --test --retries 5
  ./mongodl --edition enterprise --version v8.0-perf --component cryptd --test --retries 5
fi

popd
make -C ${DRIVERS_TOOLS} test
