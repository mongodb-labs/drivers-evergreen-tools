#!/usr/bin/env bash

# Test mongodl and mongosh_dl.
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/..

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
  ./mongodl_test/bin/mongosh --version
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
./mongodl --edition enterprise --version 3.6 --component archive --test --retries 5
./mongodl --edition enterprise --version 4.0 --component archive --test --retries 5
./mongodl --edition enterprise --version 4.2 --component archive --test --retries 5
./mongodl --edition enterprise --version 4.4 --component archive --test --retries 5
./mongodl --edition enterprise --version 5.0 --component archive --test --retries 5
./mongodl --edition enterprise --version 6.0 --component crypt_shared --test --retries 5
./mongodl --edition enterprise --version 8.0 --component archive --test --retries 5
./mongodl --edition enterprise --version rapid --component archive --test --retries 5
./mongodl --edition enterprise --version latest --component archive --out ${DOWNLOAD_DIR} --retries 5
./mongodl --edition enterprise --version latest-build --component archive --test --retries 5 >latest-build.log 2>&1
# The master-nightly artifact is always published with a signature, so a host
# with gpg must verify it; only a host without gpg may skip verification. A
# missing signature would be a publication regression.
if command -v gpg >/dev/null 2>&1; then
  grep -q "Verified GPG signature" latest-build.log
  # A regression that accepts any signature must fail the download: check
  # that a garbage signature is rejected. This exercises the real gpg and
  # the real pinned keys, so no gpg shim is needed.
  uv run --no-project python - <<'EOF'
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, ".evergreen")
from server_artifacts import _verify_gpg_signature

with tempfile.TemporaryDirectory() as tmp:
    archive = Path(tmp) / "archive.tgz"
    archive.write_bytes(b"an archive body")
    try:
        _verify_gpg_signature("gpg", archive, b"not really a signature")
    except ValueError:
        pass  # expected: the garbage signature must be rejected
    else:
        raise AssertionError("a garbage signature was accepted")
EOF
else
  grep -q "gpg is not installed" latest-build.log
fi
./mongodl --edition enterprise --version latest-release --component archive --test --retries 5
./mongodl --edition enterprise --version latest-stable --component archive --test --retries 5
./mongodl --edition enterprise --version v6.0-perf --component cryptd --test --retries 5
./mongodl --edition enterprise --version v8.0-perf --component cryptd --test --retries 5

popd
make -C ${DRIVERS_TOOLS} test
