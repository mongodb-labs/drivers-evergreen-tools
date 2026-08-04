"""Compute the next release version from the latest version tag in git."""

import argparse
import os
import re
import subprocess
import sys

TAG_PATTERN = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
LEVELS = ("patch", "minor", "major")


def parse_version(tag):
    """Return (major, minor, patch) for a vX.Y.Z tag, or None for anything else."""
    match = TAG_PATTERN.match(tag)
    if match is None:
        return None
    return tuple(int(part) for part in match.groups())


def latest_version(tags):
    """Return the highest version among tags, or None when none is a version."""
    versions = [
        parsed for parsed in (parse_version(tag) for tag in tags) if parsed is not None
    ]
    if not versions:
        return None
    return max(versions)


def bump(version, level):
    """Return version bumped at level, one of patch, minor, or major."""
    major, minor, patch = version
    if level == "patch":
        return (major, minor, patch + 1)
    if level == "minor":
        return (major, minor + 1, 0)
    if level == "major":
        return (major + 1, 0, 0)
    raise ValueError(f"unknown bump level: {level}")


def format_tag(version):
    """Return the tag name for a version."""
    major, minor, patch = version
    return f"v{major}.{minor}.{patch}"


def list_tags():
    """Return the repository's tags that start with v."""
    completed = subprocess.run(
        ["git", "tag", "--list", "v*"],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.split()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "level", choices=LEVELS, help="which part of the version to bump"
    )
    args = parser.parse_args(argv)

    current = latest_version(list_tags())
    if current is None:
        print(
            "error: no vX.Y.Z tag found, create and push the first tag (v1.0.0) before releasing",
            file=sys.stderr,
        )
        return 1

    outputs = [
        f"current-version={format_tag(current)}",
        f"next-version={format_tag(bump(current, args.level))}",
    ]
    for line in outputs:
        print(line)

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a") as fid:
            fid.write("\n".join(outputs) + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
