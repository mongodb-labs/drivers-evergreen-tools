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

# A signature that does not verify must fail the download. The shim fails only
# the gpg --verify call, so the key imports and the rest of the download run
# for real. It needs a real gpg to forward to, and does not work on Windows.
if command -v gpg >/dev/null 2>&1 && [ "${OS:-}" != "Windows_NT" ]; then
  latest_url=$(./mongodl --edition enterprise --version latest-build --component archive --no-download | tail -n 1)
  case "$latest_url" in
    https://downloads.10gen.com/*)
      # The legacy host serves .sig files too, so the shim test could run
      # there as well; keep it scoped to the private S3 artifacts, which is
      # what Evergreen uses.
      ;;
    *)
      bad_gpg_dir=$(mktemp -d)
      cat > $bad_gpg_dir/gpg <<'EOF'
#!/bin/sh
for arg in "$@"; do
  if [ "$arg" = "--verify" ]; then
    echo "simulated bad signature" >&2
    exit 1
  fi
done
for candidate in $(which -a gpg); do
  if [ "$candidate" != "$0" ]; then
    exec "$candidate" "$@"
  fi
done
echo "no real gpg found" >&2
exit 127
EOF
      chmod +x $bad_gpg_dir/gpg
      if PATH="$bad_gpg_dir:$PATH" ./mongodl --edition enterprise --version latest-build --component archive --test >bad-signature.log 2>&1; then
        echo "ERROR: a bad signature should fail the download" >&2
        exit 1
      fi
      grep -q "Signature verification for .* failed" bad-signature.log
      rm -rf $bad_gpg_dir
      ;;
  esac
fi

# The fingerprint and key-status checks are the security boundary, so exercise
# them with real gpg and throwaway keys, not just the shim above.
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
archive.write_bytes(b"drivers-evergreen-tools signature test\n")
real_pins = mongodl.PINNED_FINGERPRINTS


def gnupg(home, *args):
    """Run gpg against a throwaway keyring."""
    proc = subprocess.run(
        ["gpg", "--batch", "--no-tty", "--pinentry-mode", "loopback",
         "--passphrase", "", *args],
        env=dict(os.environ, GNUPGHOME=str(home)),
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    return proc.stdout


def key_fprs(home):
    out = gnupg(home, "--list-keys", "--with-colons")
    return [
        line.split(":")[9] for line in out.splitlines() if line.startswith("fpr:")
    ]


def sign(home, out, *select):
    gnupg(home, *select, "--detach-sign", "--output", str(out), str(archive))
    return out.read_bytes()


def verify(keys, pinned, signature, needle=None):
    mongodl.SERVER_9_KEY, mongodl.SERVER_8_0_KEY = keys
    mongodl.PINNED_FINGERPRINTS = frozenset(pinned)
    try:
        fingerprint = mongodl._verify_gpg_signature(gpg, archive, signature)
        assert needle is None, f"verification should have failed: {needle}"
        return fingerprint
    except ValueError as e:
        assert needle is not None and needle in str(e), e


# A well-formed signature by a signer that is not pinned must be rejected,
# even though gpg itself verifies it happily.
attacker = work / "attacker"
attacker.mkdir()
gnupg(attacker, "--quick-generate-key", "Attacker <attacker@example.invalid>", "ed25519", "sign", "0")
attacker_key = gnupg(attacker, "--armor", "--export")
verify(
    (attacker_key, attacker_key),
    real_pins,
    sign(attacker, work / "unpinned.sig"),
    "not made by a pinned MongoDB release signing key",
)
print("unpinned signer rejected")

# A tampered signature must be rejected.
pinned = work / "pinned"
pinned.mkdir()
gnupg(pinned, "--quick-generate-key", "Pinned <pinned@example.invalid>", "ed25519", "sign", "0")
pinned_key = gnupg(pinned, "--armor", "--export")
pinned_fpr = key_fprs(pinned)[0]
signature = bytearray(sign(pinned, work / "pinned.sig"))
signature[-10:] = b"XXXXXXXXXX"
verify((pinned_key, pinned_key), (pinned_fpr,), bytes(signature), "failed")
print("tampered signature rejected")

# An expired pinned key must be rejected, even though gpg exits 0 and still
# emits VALIDSIG for it.
expired = work / "expired"
expired.mkdir()
gnupg(expired, "--quick-generate-key", "Expired <expired@example.invalid>", "ed25519", "sign", "seconds=3")
expired_key = gnupg(expired, "--armor", "--export")
signature = sign(expired, work / "expired.sig")
time.sleep(4)
verify((expired_key, expired_key), (key_fprs(expired)[0],), signature, "expired or revoked")
print("expired key rejected")

# A revoked pinned key must be rejected. Import the revocation certificate as
# the second key, after the key itself; its armor header is deliberately
# colon-prefixed in openpgp-revocs.d and must be stripped before importing.
revoked = work / "revoked"
revoked.mkdir()
gnupg(revoked, "--quick-generate-key", "Revoked <revoked@example.invalid>", "ed25519", "sign", "0")
revoked_key = gnupg(revoked, "--armor", "--export")
signature = sign(revoked, work / "revoked.sig")
revocation = next(iter(revoked.glob("openpgp-revocs.d/*.rev")))
lines = revocation.read_text().splitlines()
begin = next(i for i, line in enumerate(lines) if "BEGIN PGP" in line)
end = next(i for i, line in enumerate(lines) if "END PGP" in line)
block = lines[begin : end + 1]
block[0] = block[0].lstrip(":")
revocation_block = "\n".join(block)
verify((revoked_key, revocation_block), (key_fprs(revoked)[0],), signature, "expired or revoked")
print("revoked key rejected")

# A signature by a pinned key's signing subkey must verify, with the primary
# fingerprint pinned.
with_subkey = work / "with-subkey"
with_subkey.mkdir()
gnupg(with_subkey, "--quick-generate-key", "Subkeyed <subkeyed@example.invalid>", "ed25519", "sign", "0")
primary = key_fprs(with_subkey)[0]
gnupg(with_subkey, "--quick-add-key", primary, "ed25519", "sign", "0")
subkey = key_fprs(with_subkey)[1]
subkeyed_key = gnupg(with_subkey, "--armor", "--export")
signature = sign(with_subkey, work / "subkeyed.sig", "-u", subkey)
fingerprint = verify((subkeyed_key, subkeyed_key), (primary,), signature)
assert fingerprint == primary, (fingerprint, primary)
print("subkey signature verified with the primary pinned")

shutil.rmtree(work, ignore_errors=True)
print("GPG verification tests passed")
PYEOF
fi

popd
make -C ${DRIVERS_TOOLS} test
