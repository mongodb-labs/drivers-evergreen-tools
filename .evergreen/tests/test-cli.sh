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
else
  grep -q "gpg is not installed" latest-build.log
fi
./mongodl --edition enterprise --version latest-release --component archive --test --retries 5
./mongodl --edition enterprise --version latest-stable --component archive --test --retries 5
./mongodl --edition enterprise --version v6.0-perf --component cryptd --test --retries 5
./mongodl --edition enterprise --version v8.0-perf --component cryptd --test --retries 5

# A signature that gpg rejects, or one made by a key we do not pin, must fail
# verification. These cases use throwaway keys; no network is needed.
if command -v gpg >/dev/null 2>&1 && [ "${OS:-}" != "Windows_NT" ]; then
  uv run python - <<'PYEOF'
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

import mongodl

gpg = shutil.which("gpg")
work = Path(tempfile.mkdtemp(prefix="mongodl-gpg-test"))
archive = work / "mongodb-test.tgz"
archive.write_bytes(b"signature verification test\n")


def gpg_run(home, *args):
    proc = subprocess.run(
        ["gpg", "--batch", "--no-tty", "--pinentry-mode", "loopback",
         "--passphrase", "", *args],
        env=dict(os.environ, GNUPGHOME=str(home)),
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    return proc.stdout


def new_key(name, *gen):
    home = work / name
    home.mkdir()
    gpg_run(home, "--quick-generate-key", f"{name} <{name}@example.invalid>", *gen)
    return home, gpg_run(home, "--armor", "--export")


def fpr(home):
    out = gpg_run(home, "--list-keys", "--with-colons")
    return out.split("fpr:")[1].lstrip(":").split(":")[0]


def sign(home, sig, *select):
    gpg_run(home, *select, "--detach-sign", "--output", str(sig), str(archive))
    return sig.read_bytes()


def verify(key, pinned, signature):
    # Serve the throwaway key for every key URL, and pin as instructed.
    mongodl._download_bytes = lambda url: key
    mongodl.MONGODB_GPG_KEY_FINGERPRINTS = frozenset(pinned)
    try:
        mongodl._verify_gpg_signature(gpg, archive, signature)
        raise AssertionError("verification should have failed")
    except ValueError:
        pass


real_pins = mongodl.MONGODB_GPG_KEY_FINGERPRINTS

# A signer that is not pinned, even though gpg verifies it happily.
home, key = new_key("unpinned", "ed25519", "sign", "0")
verify(key, real_pins, sign(home, work / "unpinned.sig"))

# A tampered signature.
home, key = new_key("pinned", "ed25519", "sign", "0")
tampered = bytearray(sign(home, work / "tampered.sig"))
tampered[-10:] = b"XXXXXXXXXX"
verify(key, (fpr(home),), bytes(tampered))

# A pinned but expired key: gpg exits 0 and still emits VALIDSIG for it.
home, key = new_key("expired", "ed25519", "sign", "seconds=3")
signature = sign(home, work / "expired.sig")
time.sleep(4)
verify(key, (fpr(home),), signature)

shutil.rmtree(work, ignore_errors=True)
print("GPG verification tests passed")
PYEOF
fi

popd
make -C ${DRIVERS_TOOLS} test
