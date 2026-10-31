"""Tests for mongodl signature verification, invoked by test-cli.sh."""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import mongodl
from server_artifacts import GpgEnvironmentError, _gpg_path, _verify_gpg_signature


def _write_archive(directory):
    archive = Path(directory) / "archive.tgz"
    archive.write_bytes(b"an archive body")
    return archive


class VerifySignatureRejectionTest(unittest.TestCase):
    """A working gpg must reject signatures it cannot trust."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        assert (
            shutil.which("gpg") is not None
        ), "gpg must be installed on test hosts; install the full gnupg2 package"

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
        # A deep $TMPDIR must not push the gpg home's sockets past the
        # AF_UNIX sun_path buffer (108 bytes on Linux and Cygwin, 104 on
        # macOS), or the key import fails with a GpgEnvironmentError
        # (DRIVERS-3663).
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


class _FakeDownloadedFile:
    def __init__(self, path):
        self.path = path


class _FakeCache:
    def __init__(self, path):
        self._path = path

    def download_file(self, url):
        return _FakeDownloadedFile(self._path)


class VerificationErrorHandlingTest(unittest.TestCase):
    """
    _dl_component fails fast on GpgEnvironmentError on every host (a broken
    gpg environment is never retried), and retries other download errors.
    """

    def setUp(self):
        self.saved = (
            mongodl.verify_latest_build,
            mongodl._latest_build_url,
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
            mongodl._expand_archive,
            mongodl.time.sleep,
        ) = self.saved

    def _drive(self, error):
        """Drive _dl_component with an always-raising verifier; return attempts."""
        attempts = []

        def verify(archive, sig_url):
            attempts.append(1)
            raise error

        mongodl.verify_latest_build = verify
        with tempfile.TemporaryDirectory() as tmp:
            raised = None
            try:
                mongodl._dl_component(
                    cache=_FakeCache(Path(tmp) / "archive.tgz"),
                    out_dir=Path(tmp),
                    version="latest-build",
                    target="amazon2023",
                    arch="x86_64",
                    edition="enterprise",
                    component="archive",
                    pattern=None,
                    strip_components=0,
                    test=True,
                    no_download=False,
                    latest_build_branch=None,
                    retries=5,
                )
            except type(error) as raised_exc:
                raised = raised_exc
        self.assertIsNotNone(raised, "expected the error to propagate")
        return attempts

    def test_gpg_environment_error_fails_fast(self):
        attempts = self._drive(GpgEnvironmentError("no agent"))
        self.assertEqual(len(attempts), 1)

    def test_other_errors_retry(self):
        attempts = self._drive(ValueError("bad download"))
        self.assertEqual(len(attempts), 6)


if __name__ == "__main__":
    unittest.main()
