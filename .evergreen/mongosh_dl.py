#!/usr/bin/env python3
"""
Download and extract MongoSH.

Use '--help' for more information.
"""

import argparse
import json
import logging
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

LOGGER = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(levelname)-8s %(message)s")

HERE = Path(__file__).absolute().parent
sys.path.insert(0, str(HERE))
from mongodl import LOGGER as DL_LOGGER
from mongodl import (
    SSL_CONTEXT,
    DownloadRetrier,
    ExpandResult,
    _expand_archive,
    infer_arch,
)


def _get_latest_version():
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    url = "https://api.github.com/repos/mongodb-js/mongosh/releases"
    req = urllib.request.Request(url, headers=headers)
    try:
        resp = urllib.request.urlopen(req, context=SSL_CONTEXT, timeout=10)
    except Exception:
        return _get_latest_version_git()

    data = json.loads(resp.read().decode("utf-8"))
    for item in data:
        if item["prerelease"]:
            continue
        return item["tag_name"].replace("v", "").strip()


def _get_latest_version_git():
    with tempfile.TemporaryDirectory() as td:
        cmd = "git clone --depth 1 https://github.com/mongodb-js/mongosh.git"
        subprocess.check_call(
            shlex.split(cmd), cwd=td, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        cmd = "git fetch origin --tags"
        path = os.path.join(td, "mongosh")
        subprocess.check_call(
            shlex.split(cmd), cwd=path, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        cmd = "git --no-pager tag"
        output = subprocess.check_output(
            shlex.split(cmd), cwd=path, stderr=subprocess.PIPE
        )
        for line in reversed(output.decode("utf-8").splitlines()):
            if re.match(r"^v\d+\.\d+\.\d+$", line):
                LOGGER.debug("Found version %s", line)
                return line.replace("v", "").strip()


def _download(
    out_dir: Path,
    version: str,
    target: str,
    arch: str,
    pattern: "str | None",
    strip_components: int,
    test: bool,
    no_download: bool,
    retries: int,
) -> int:
    LOGGER.info(f"Download {version} mongosh for {target}-{arch}")
    if version == "latest":
        version = _get_latest_version()
    if arch == "x86_64":
        arch = "x64"
    elif arch == "aarch64":
        arch = "arm64"
    if target == "linux":
        suffix = ".tgz"
        if sys.platform == "linux" and arch in ["x64", "arm64"]:
            openssl = subprocess.check_output(["openssl", "version"])
            if "3.0" in openssl.decode("utf-8"):
                suffix = "-openssl3.tgz"
            elif re.match("1.1.1[e-w] ", openssl.decode("utf-8")):
                suffix = "-openssl11.tgz"
    else:
        suffix = ".zip"
    dl_url = f"https://downloads.mongodb.com/compass/mongosh-{version}-{target}-{arch}{suffix}"
    # This must go to stdout to be consumed by the calling program.
    print(dl_url)
    LOGGER.info("Download url: %s", dl_url)

    if no_download:
        return ExpandResult.Okay

    req = urllib.request.Request(dl_url)
    retrier = DownloadRetrier(retries)
    while True:
        try:
            resp = urllib.request.urlopen(req, context=SSL_CONTEXT, timeout=30)
            with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as fp:
                shutil.copyfileobj(resp, fp)
                fp.close()
                result = _expand_archive(
                    Path(fp.name), out_dir, pattern, strip_components, test=test
                )
                os.remove(fp.name)
            return result
        except Exception:
            if not retrier.retry():
                raise


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Whether to log at the DEBUG level"
    )
    parser.add_argument(
        "--quiet", "-q", action="store_true", help="Whether to log at the WARNING level"
    )
    dl_grp = parser.add_argument_group(
        "Download arguments",
        description="Select what to download and extract. "
        "Some arguments will be inferred "
        "based on the host system.",
    )
    dl_grp.add_argument(
        "--target",
        "-T",
        default="auto",
        help="The target platform for which to download. "
        'Use "--list" to list available targets.',
    )
    dl_grp.add_argument(
        "--arch", "-A", default="auto", help="The architecture for which to download"
    )
    dl_grp.add_argument(
        "--out",
        "-o",
        help="The directory in which to download components.",
        type=Path,
    )
    dl_grp.add_argument(
        "--version",
        "-V",
        default="latest",
        help='The product version to download. Use "latest" to download '
        "the newest available stable version.",
    )
    dl_grp.add_argument(
        "--only",
        help="Restrict extraction to items that match the given globbing expression. "
        'The full archive member path is matched, so a pattern like "*.exe" '
        'will only match "*.exe" at the top level of the archive. To match '
        'recursively, use the "**" pattern to match any number of '
        "intermediate directories.",
    )
    dl_grp.add_argument(
        "--strip-path-components",
        "-p",
        dest="strip_components",
        metavar="N",
        default=0,
        type=int,
        help="Strip the given number of path components from archive members before "
        "extracting into the destination. The relative path of the archive "
        "member will be used to form the destination path. For example, a "
        "member named [bin/mongod.exe] will be extracted to [<out>/bin/mongod.exe]. "
        "Using --strip-components=1 will remove the first path component, extracting "
        "such an item to [<out>/mongod.exe]. If the path has fewer than N components, "
        "that archive member will be ignored.",
    )
    dl_grp.add_argument(
        "--no-download",
        action="store_true",
        help="Do not download the file, only print its url.",
    )
    dl_grp.add_argument(
        "--test",
        action="store_true",
        help="Do not extract or place any files/directories. "
        "Only print what will be extracted without placing any files.",
    )
    dl_grp.add_argument("--retries", help="The number of times to retry", default=0)
    args = parser.parse_args(argv)

    target = args.target
    if target == "auto":
        target = sys.platform
    arch = args.arch
    if arch == "auto":
        arch = infer_arch()
    out = args.out or Path.cwd()
    out = out.absolute()
    if args.verbose:
        LOGGER.setLevel(logging.DEBUG)
        DL_LOGGER.setLevel(logging.DEBUG)
    elif args.quiet:
        LOGGER.setLevel(logging.WARNING)
        DL_LOGGER.setLevel(logging.WARNING)
    result = _download(
        out,
        version=args.version,
        target=target,
        arch=arch,
        pattern=args.only,
        strip_components=args.strip_components,
        test=args.test,
        no_download=args.no_download,
        retries=int(args.retries),
    )
    if result is ExpandResult.Empty:
        sys.exit(1)


if __name__ == "__main__":
    main()
