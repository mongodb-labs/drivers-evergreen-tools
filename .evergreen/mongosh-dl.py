#!/usr/bin/env python3
"""
Download and extract MongoSH.

Use '--help' for more information.
"""
import argparse
import json
import sys
import tempfile
import subprocess
import shlex
import os
from pathlib import Path
from typing import Sequence
import urllib.request
import re
import ssl

HERE = Path(__file__).absolute().parent
sys.path.insert(0, str(HERE))
from mongodl import _expand_archive, infer_arch, ExpandResult


def _get_latest_version():
    headers = { "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28" }
    url = "https://api.github.com/repos/mongodb-js/mongosh/releases"
    req = urllib.request.Request(url, headers=headers)
    try:
        resp = urllib.request.urlopen(req)
    except Exception:
        return _get_latest_version_git()

    data = json.loads(resp.read().decode('utf-8'))
    for item in data:
        if item['prerelease']:
            continue
        return item['tag_name'].replace('v', '').strip()


def _get_latest_version_git():
    with tempfile.TemporaryDirectory() as td:
        cmd = 'git clone --depth 1 https://github.com/mongodb-js/mongosh.git'
        subprocess.check_call(shlex.split(cmd), cwd=td, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cmd = 'git fetch origin --tags'
        path = os.path.join(td, 'mongosh')
        subprocess.check_call(shlex.split(cmd), cwd=path, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cmd = 'git --no-pager tag'
        output = subprocess.check_output(shlex.split(cmd), cwd=path, stderr=subprocess.PIPE)
        for line in reversed(output.decode('utf-8').splitlines()):
            if re.match('^v\d+\.\d+\.\d+$', line):
                print('Found version', line, file=sys.stderr)
                return line.replace('v', '').strip()


def _download(out_dir: Path, version: str, target: str,
                  arch: str,
                  pattern: 'str | None', strip_components: int, test: bool,
                  no_download: bool,) -> int:
    print('Download {} mongosh for {}-{}'.format(version, target, arch), file=sys.stderr)
    if version == "latest":
        version = _get_latest_version()
    if arch == "x86_64":
        arch = "x64"
    elif arch == "aarch64":
        arch = "arm64"
    if target == "linux":
        suffix = '.tgz'
        print('hello', sys.platform, arch, repr(ssl.OPENSSL_VERSION_INFO[0]))
        if sys.platform == 'linux' and arch in ["x64", "arm64"]:
            if ssl.OPENSSL_VERSION_INFO[0] == 3:
                suffix = "-openssl3.tgz"
    else:
        suffix = ".zip"
    dl_url = f"https://downloads.mongodb.com/compass/mongosh-{version}-{target}-{arch}{suffix}"
    print(dl_url)
    if no_download:
        print(dl_url)
        return ExpandResult.Okay

    req = urllib.request.Request(dl_url)
    resp = urllib.request.urlopen(req)

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as fp:
        buf = resp.read(1024 * 1024 * 4)
        while buf:
            fp.write(buf)
            buf = resp.read(1024 * 1024 * 4)
        fp.close()
        resp = _expand_archive(Path(fp.name),
                            out_dir, pattern,
                            strip_components,
                            test=test)
        os.remove(fp.name)
    return resp


def main(argv: 'Sequence[str]'):
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    dl_grp = parser.add_argument_group(
        'Download arguments',
        description='Select what to download and extract. '
        'Non-required arguments will be inferred '
        'based on the host system.')
    dl_grp.add_argument('--target',
                        '-T',
                        help='The target platform for which to download. '
                        'Use "--list" to list available targets.')
    dl_grp.add_argument('--arch',
                        '-A',
                        help='The architecture for which to download')
    dl_grp.add_argument(
        '--out',
        '-o',
        help='The directory in which to download components. (Required)',
        type=Path)
    dl_grp.add_argument(
        '--version',
        '-V',
        default="latest",
        help=
        'The product version to download (Required). Use "latest" to download '
        'the newest available stable version.')
    dl_grp.add_argument(
        '--only',
        help=
        'Restrict extraction to items that match the given globbing expression. '
        'The full archive member path is matched, so a pattern like "*.exe" '
        'will only match "*.exe" at the top level of the archive. To match '
        'recursively, use the "**" pattern to match any number of '
        'intermediate directories.')
    dl_grp.add_argument(
        '--strip-path-components',
        '-p',
        dest='strip_components',
        metavar='N',
        default=0,
        type=int,
        help=
        'Strip the given number of path components from archive members before '
        'extracting into the destination. The relative path of the archive '
        'member will be used to form the destination path. For example, a '
        'member named [bin/mongod.exe] will be extracted to [<out>/bin/mongod.exe]. '
        'Using --strip-components=1 will remove the first path component, extracting '
        'such an item to [<out>/mongod.exe]. If the path has fewer than N components, '
        'that archive member will be ignored.')
    dl_grp.add_argument(
        '--no-download',
        action='store_true',
        help='Do not download the file, only print its url.')
    dl_grp.add_argument(
        '--test',
        action='store_true',
        help='Do not extract or place any files/directories. '
        'Only print what will be extracted without placing any files.')
    args = parser.parse_args(argv)

    if args.out is None and args.test is None and args.no_download is None:
        raise argparse.ArgumentError(None,
                                     'A "--out" directory should be provided')

    target = args.target
    if target in (None, 'auto'):
        target = sys.platform
    arch = args.arch
    if arch in (None, 'auto'):
        arch = infer_arch()
    out = args.out or Path.cwd()
    out = out.absolute()
    result = _download(out,
        version=args.version,
        target=target,
        arch=arch,
        pattern=args.only,
        strip_components=args.strip_components,
        test=args.test,
        no_download=args.no_download)
    if result is ExpandResult.Empty:
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
