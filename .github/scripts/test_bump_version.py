"""Tests for bump_version."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "bump_version.py"
sys.path.insert(0, str(HERE))

import bump_version


def make_repo(tags):
    """Create a temporary git repository with one empty commit and the given tags."""
    tmp = tempfile.TemporaryDirectory()
    path = Path(tmp.name)
    git = ["git", "-c", "user.email=test@example.com", "-c", "user.name=Test"]
    subprocess.run([*git, "init", "-q", "-b", "main", "."], cwd=path, check=True)
    subprocess.run(
        [*git, "commit", "-q", "--allow-empty", "-m", "init"], cwd=path, check=True
    )
    for tag in tags:
        subprocess.run([*git, "tag", tag], cwd=path, check=True)
    return tmp


def run_script(cwd, level, env=None):
    """Run the script in cwd and return the CompletedProcess.

    GITHUB_OUTPUT is dropped unless a test sets it, so a test run inside GitHub
    Actions does not append to the real step output file.
    """
    if env is None:
        env = {
            key: value for key, value in os.environ.items() if key != "GITHUB_OUTPUT"
        }
    return subprocess.run(
        [sys.executable, str(SCRIPT), level],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


class TestParseVersion(unittest.TestCase):
    def test_accepts_plain_version_tag(self):
        self.assertEqual(bump_version.parse_version("v1.2.3"), (1, 2, 3))
        self.assertEqual(bump_version.parse_version("v10.0.11"), (10, 0, 11))

    def test_rejects_anything_else(self):
        for tag in [
            "v1.2",
            "1.2.3",
            "v1.2.3.4",
            "v1.2.3-rc1",
            "v6.0-perf",
            "vlatest",
            "",
        ]:
            with self.subTest(tag=tag):
                self.assertIsNone(bump_version.parse_version(tag))


class TestLatestVersion(unittest.TestCase):
    def test_compares_numerically_not_as_strings(self):
        tags = ["v1.9.0", "v1.10.0", "v0.1.0"]
        self.assertEqual(bump_version.latest_version(tags), (1, 10, 0))

    def test_ignores_tags_that_are_not_versions(self):
        tags = ["v6.0-perf", "v1.0.0", "not-a-tag"]
        self.assertEqual(bump_version.latest_version(tags), (1, 0, 0))

    def test_returns_none_when_no_tag_is_a_version(self):
        self.assertIsNone(bump_version.latest_version(["v6.0-perf", "latest"]))
        self.assertIsNone(bump_version.latest_version([]))


class TestBump(unittest.TestCase):
    def test_patch_increments_patch(self):
        self.assertEqual(bump_version.bump((1, 2, 3), "patch"), (1, 2, 4))

    def test_minor_increments_minor_and_zeroes_patch(self):
        self.assertEqual(bump_version.bump((1, 2, 3), "minor"), (1, 3, 0))

    def test_major_increments_major_and_zeroes_the_rest(self):
        self.assertEqual(bump_version.bump((1, 2, 3), "major"), (2, 0, 0))

    def test_rejects_an_unknown_level(self):
        with self.assertRaises(ValueError):
            bump_version.bump((1, 2, 3), "epoch")


class TestFormatTag(unittest.TestCase):
    def test_renders_a_version_tuple(self):
        self.assertEqual(bump_version.format_tag((1, 10, 2)), "v1.10.2")


class TestMain(unittest.TestCase):
    def test_reports_current_and_next_version(self):
        tmp = make_repo(["v1.0.0", "v1.10.0", "v6.0-perf"])
        self.addCleanup(tmp.cleanup)
        result = run_script(tmp.name, "minor")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("current-version=v1.10.0", result.stdout)
        self.assertIn("next-version=v1.11.0", result.stdout)

    def test_writes_github_output_when_set(self):
        tmp = make_repo(["v2.3.4"])
        self.addCleanup(tmp.cleanup)
        output = Path(tmp.name) / "github_output"
        env = dict(os.environ, GITHUB_OUTPUT=str(output))
        result = run_script(tmp.name, "patch", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        written = output.read_text()
        self.assertIn("current-version=v2.3.4\n", written)
        self.assertIn("next-version=v2.3.5\n", written)

    def test_fails_when_no_version_tag_exists(self):
        tmp = make_repo(["v6.0-perf"])
        self.addCleanup(tmp.cleanup)
        result = run_script(tmp.name, "patch")
        self.assertEqual(result.returncode, 1)
        self.assertIn("v1.0.0", result.stderr)

    def test_rejects_an_invalid_level(self):
        tmp = make_repo(["v1.0.0"])
        self.addCleanup(tmp.cleanup)
        result = run_script(tmp.name, "epoch")
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
