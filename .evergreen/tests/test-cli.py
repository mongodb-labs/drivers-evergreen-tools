"""Tests for mongodl signature verification, invoked by test-cli.sh."""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import mongodl
from server_artifacts import GpgEnvironmentError, _gpg_path, _verify_gpg_signature

# TODO (DRIVERS-3666): remove the amazon2023 skip markers and
# Amazon2023HostTest once DEVPROD-44314 ships full gnupg2.
IS_AMAZON2023 = mongodl._is_amazon2023_host()


def _write_archive(directory):
    archive = Path(directory) / "archive.tgz"
    archive.write_bytes(b"an archive body")
    return archive


@unittest.skipUnless(shutil.which("gpg"), "gpg is not installed")
@unittest.skipIf(IS_AMAZON2023, "amazon2023 hosts cannot verify signatures")
class VerifySignatureRejectionTest(unittest.TestCase):
    """A working gpg must reject signatures it cannot trust."""

    def test_garbage_signature_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = _write_archive(tmp)
            with self.assertRaises(ValueError):
                _verify_gpg_signature("gpg", archive, b"not really a signature")

    def test_unpinned_key_signature_rejected(self):
        # Temporary paths are spelled with _gpg_path, since the MSYS/Cygwin
        # gpg on the Windows hosts treats native paths as relative.
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            archive = _write_archive(work)
            gpg_home = work / "gpg"
            gpg_home.mkdir()
            gpg_home.chmod(0o700)
            gpg = [
                "gpg",
                "--homedir",
                _gpg_path(gpg_home),
                "--batch",
                "--pinentry-mode",
                "loopback",
                "--passphrase",
                "",
            ]
            subprocess.run(
                [*gpg, "--quick-gen-key", "unpinned-test-key"],
                check=True,
                capture_output=True,
            )
            sig = work / "archive.tgz.sig"
            subprocess.run(
                [*gpg, "--output", _gpg_path(sig), "--detach-sign", _gpg_path(archive)],
                check=True,
                capture_output=True,
            )
            with self.assertRaises(ValueError):
                _verify_gpg_signature("gpg", archive, sig.read_bytes())

    def test_deep_tmpdir_signature_rejected(self):
        # A deep $TMPDIR must not push the gpg-agent socket past the AF_UNIX
        # limit (108 bytes on Linux, 104 on macOS), or the key import fails
        # with a RuntimeError (DRIVERS-3663).
        if sys.platform == "win32":
            self.skipTest("windows gpg does not use AF_UNIX sockets")
        with tempfile.TemporaryDirectory() as tmp:
            deep = Path(tmp) / ("d" * 100)
            deep.mkdir()
            archive = _write_archive(deep)
            old_tempdir = tempfile.tempdir
            tempfile.tempdir = str(deep)
            try:
                with self.assertRaises(ValueError):
                    _verify_gpg_signature("gpg", archive, b"not really a signature")
            finally:
                tempfile.tempdir = old_tempdir


class Amazon2023HostTest(unittest.TestCase):
    """amazon2023 images ship gnupg2-minimal: gpg without gpg-agent."""

    @unittest.skipUnless(IS_AMAZON2023, "only meaningful on amazon2023 hosts")
    def test_verification_raises_gpg_environment_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = _write_archive(tmp)
            with self.assertRaises(GpgEnvironmentError):
                _verify_gpg_signature("gpg", archive, b"not really a signature")


class _FakeDownloadedFile:
    def __init__(self, path):
        self.path = path


class _FakeCache:
    def __init__(self, path):
        self._path = path

    def download_file(self, url):
        return _FakeDownloadedFile(self._path)


class VerificationToleranceTest(unittest.TestCase):
    """
    _dl_component tolerates GpgEnvironmentError on amazon2023 (with a
    DEVPROD-44314 note), fails it fast elsewhere, and retries other errors.
    """

    def setUp(self):
        self.saved = (
            mongodl.verify_latest_build,
            mongodl._latest_build_url,
            mongodl._is_amazon2023_host,
            mongodl._expand_archive,
            mongodl.time.sleep,
        )
        mongodl._latest_build_url = lambda *args, **kwargs: (
            "http://x/archive.tgz",
            "http://x/archive.tgz.sig",
        )
        mongodl._expand_archive = lambda *args, **kwargs: None
        mongodl.time.sleep = lambda seconds: None

    def tearDown(self):
        (
            mongodl.verify_latest_build,
            mongodl._latest_build_url,
            mongodl._is_amazon2023_host,
            mongodl._expand_archive,
            mongodl.time.sleep,
        ) = self.saved

    def _drive(self, error, amazon_host, expect_raise):
        """Drive _dl_component with an always-raising verifier; return attempts."""
        attempts = []

        def verify(archive, sig_url):
            attempts.append(1)
            raise error

        mongodl.verify_latest_build = verify
        mongodl._is_amazon2023_host = lambda: amazon_host
        with tempfile.TemporaryDirectory() as tmp:
            raised = None
            try:
                mongodl._dl_component(
                    _FakeCache(Path(tmp) / "archive.tgz"),
                    Path(tmp),
                    "latest-build",
                    "amazon2023",
                    "x86_64",
                    "enterprise",
                    "archive",
                    None,
                    0,
                    True,
                    False,
                    None,
                    5,
                )
            except type(error) as raised_exc:
                raised = raised_exc
        if expect_raise:
            self.assertIsNotNone(raised, "expected the error to propagate")
        return attempts

    def test_amazon_host_tolerates_gpg_environment_error(self):
        with self.assertLogs("mongodl", level="WARNING") as logs:
            attempts = self._drive(
                GpgEnvironmentError("no agent"),
                amazon_host=True,
                expect_raise=False,
            )
        self.assertEqual(len(attempts), 1)
        self.assertTrue(
            any("DEVPROD-44314" in line for line in logs.output),
            f"no DEVPROD-44314 note in {logs.output}",
        )

    def test_amazon_host_retries_bad_signatures(self):
        attempts = self._drive(
            ValueError("bad signature"),
            amazon_host=True,
            expect_raise=True,
        )
        self.assertEqual(len(attempts), 6)

    def test_gpg_environment_error_fails_fast_on_other_hosts(self):
        attempts = self._drive(
            GpgEnvironmentError("no agent"),
            amazon_host=False,
            expect_raise=True,
        )
        self.assertEqual(len(attempts), 1)

    def test_other_hosts_retry_other_errors(self):
        attempts = self._drive(
            ValueError("bad download"),
            amazon_host=False,
            expect_raise=True,
        )
        self.assertEqual(len(attempts), 6)


if __name__ == "__main__":
    unittest.main()
