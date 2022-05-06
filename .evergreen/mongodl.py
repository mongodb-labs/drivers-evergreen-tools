#!/usr/bin/env python3

"""
Download and extract MongoDB components.

Can also be imported and used as a module. Refer:

- class Cache           - Manage, query, and use a cache
- class CacheDB         - Manage and query a cache db
- func infer_target()   - Infer the download target of the host OS
- func infer_arch()     - Infer the architecture of the host OS
- user_caches_root()    - Where programs should put their cache data
- default_cache_dir()   - Default directory for mongodl cache data

Use '--help' for more information.
"""
import argparse
import enum
import hashlib
import json
import os
import platform
import re
import shutil
import sqlite3
import sys
import tarfile
import textwrap
import urllib.error
import urllib.request
import zipfile
from collections import namedtuple
from contextlib import contextmanager
from fnmatch import fnmatch
from pathlib import Path, PurePath, PurePosixPath
import re

try:
    # We want to support Python3.4 for now, which does not have a 'typing' module
    from typing import (IO, TYPE_CHECKING, Any, Callable, Iterable, Iterator,
                        NamedTuple, Sequence, cast)
except ImportError:
    TYPE_CHECKING = False

    if not TYPE_CHECKING:

        def cast(t, x):
            return x


#: Map common distribution names to the distribution named used in the MongoDB download list
DISTRO_ID_MAP = {
    'elementary': 'ubuntu',
    'fedora': 'rhel',
    'centos': 'rhel',
    'mint': 'ubuntu',
    'opensuse-leap': 'sles',
    'opensuse': 'sles',
    'redhat': 'rhel',
    'rocky': 'rhel',
}

#: Map derived distro versions to their base distribution versions
DISTRO_VERSION_MAP = {
    'elementary': {
        '6': '20.04'
    },
}

#: Map distribution IDs with version fnmatch() patterns to download platform targets
DISTRO_ID_TO_TARGET = {
    'ubuntu': {
        '22.*': 'ubuntu2204',
        '20.*': 'ubuntu2004',
        '18.*': 'ubuntu1804',
        '16.*': 'ubuntu1604',
        '14.*': 'ubuntu1404',
    },
    'debian': {
        '9': 'debian92',
        '10': 'debian10',
        '11': 'debian11',
    },
    'rhel': {
        '6': 'rhel60',
        '6.*': 'rhel60',
        '7': 'rhel70',
        '7.*': 'rhel70',
        '8': 'rhel80',
        '8.*': 'rhel80',
    },
    'sles': {
        '10.*': 'suse10',
        '11.*': 'suse11',
        '12.*': 'suse12',
        '13.*': 'suse13',
        '15.*': 'suse15',
    },
    'amzn': {
        '2018.*': 'amzn64',
        '2': 'amazon2',
    },
}


def infer_target() -> str:
    """
    Infer the download target of the current host system.
    """
    if sys.platform == 'win32':
        return 'windows'
    if sys.platform == 'darwin':
        return 'macos'
    # Now the tricky bit
    osr = Path('/etc/os-release')
    if osr.is_file():
        with osr.open('r', encoding='utf-8') as f:
            osr_content = f.read()
        return infer_target_from_os_release(osr_content)
    raise RuntimeError("We don't know how to find the default '--target'"
                       " option for this system. Please contribute!")


def infer_target_from_os_release(os_rel: str) -> str:
    """
    Infer the download target based on the content of os-release
    """
    # Extract the "ID" field
    id_re = re.compile(r'\bID=("?)(.*)\1')
    mat = id_re.search(os_rel)
    assert mat, 'Unable to detect ID from [/etc/os-release] content:\n{}'.format(
        os_rel)
    os_id = mat.group(2)
    if os_id == 'arch':
        # There are no Archlinux-specific MongoDB downloads, so we'll just use
        # the build for RHEL8, which is reasonably compatible with other modern
        # distributions (including Arch).
        return 'rhel80'
    # Extract the "VERSION_ID" field
    ver_id_re = re.compile(r'VERSION_ID=("?)(.*?)\1')
    mat = ver_id_re.search(os_rel)
    assert mat, 'Unable to detect VERSION_ID from [/etc/os-release] content:\n{}'.format(
        os_rel)
    ver_id = mat.group(2)
    # Map the ID to the download ID
    mapped_id = DISTRO_ID_MAP.get(os_id)
    if mapped_id:
        ver_mapper = DISTRO_VERSION_MAP.get(os_id)
        if ver_mapper:
            mapped_version = ver_mapper[ver_id]
            ver_id = mapped_version
        os_id = mapped_id
    os_id = os_id.lower()
    if os_id not in DISTRO_ID_TO_TARGET:
        raise RuntimeError("We don't know how to map '{}' to a distribution "
                           "download target. Please contribute!".format(os_id))
    # Find the download target based on a filename-style pattern:
    ver_table = DISTRO_ID_TO_TARGET[os_id]
    for pattern, target in ver_table.items():
        if fnmatch(ver_id, pattern):
            return target
    raise RuntimeError(
        "We don't know how to map '{}' version '{}' to a distribution "
        "download target. Please contribute!".format(os_id, ver_id))


def user_caches_root() -> Path:
    """
    Obtain the directory for user-local caches
    """
    if sys.platform == 'win32':
        return Path(os.environ['LocalAppData'])
    if sys.platform == 'darwin':
        return Path(os.environ['HOME'] + '/Library/Caches')
    xdg_cache = os.getenv('XDG_CACHE_HOME')
    if xdg_cache:
        return Path(xdg_cache)
    return Path(os.environ['HOME'] + '/.cache')


def default_cache_dir() -> Path:
    """
    Get the path to the default directory of mongodl caches.
    """
    return user_caches_root().joinpath('mongodl').absolute()


if TYPE_CHECKING:
    DownloadResult = NamedTuple('DownloadResult', [('is_changed', bool),
                                                   ('path', Path)])
    DownloadableComponent = NamedTuple('DownloadableComponent', [
        ('version', str),
        ('target', str),
        ('arch', str),
        ('edition', str),
        ('key', str),
        ('data_json', str),
    ])
else:
    DownloadResult = namedtuple('DownloadResult', ['is_changed', 'path'])
    DownloadableComponent = namedtuple(
        'DownloadableComponent',
        ['version', 'target', 'arch', 'edition', 'key', 'data_json'])

#: Regular expression that matches the version numbers from 'full.json'
VERSION_RE = re.compile(r'(\d+)\.(\d+)\.(\d+)(?:-([a-z]+)(\d+))?')
STABLE_MAX_RC = 9999


def version_tup(version: str) -> 'tuple[int, int, int, int, int]':
    mat = VERSION_RE.match(version)
    assert mat, ('Failed to parse "{}" as a version number'.format(version))
    major, minor, patch, tag, tagnum = list(mat.groups())
    if tag is None:
        # No rc tag is greater than an equal base version with any rc tag
        tag = STABLE_MAX_RC
        tagnum = 0
    else:
        tag = {
            'alpha': 1,
            'beta': 2,
            'rc': 3,
        }[tag]
    return tuple(map(int, (major, minor, patch, tag, tagnum)))


def collate_mdb_version(left: str, right: str) -> int:
    lhs = version_tup(left)
    rhs = version_tup(right)
    if lhs < rhs:
        return -1
    if lhs > rhs:
        return 1
    return 0


def mdb_version_not_rc(version: str) -> bool:
    tup = version_tup(version)
    return version[-1] == STABLE_MAX_RC


class CacheDB:
    """
    Abstract a mongodl cache SQLite database.
    """

    def __init__(self, db: sqlite3.Connection) -> None:
        self._db = db
        # Use a cursor to get access to lastrowid
        self._cursor = self._db.cursor()

    @staticmethod
    def open(fpath: Path) -> 'CacheDB':
        """
        Open a caching database at the given filepath.
        """
        db = sqlite3.connect(str(fpath), isolation_level=None)
        db.execute(r'''
            CREATE TABLE IF NOT EXISTS mdl_http_downloads (
            url TEXT NOT NULL UNIQUE,
            etag TEXT,
            last_modified TEXT
        )''')
        db.create_collation('mdb_version', collate_mdb_version)
        db.create_function('mdb_version_not_rc',
                           1,
                           mdb_version_not_rc,
                           deterministic=True)
        return CacheDB(db)

    def __call__(
        self, query: str, **params: 'str | int | bool | float | None'
    ) -> 'Iterable[sqlite3.Row]':
        """
        Execute a query with the given named parameters.
        """
        return self._cursor.execute(query, params)

    @contextmanager
    def transaction(self) -> 'Iterator[None]':
        """
        Create a context for a database transaction.
        """
        if self._db.in_transaction:
            yield
            return

        with self._db:
            # Must do an explicit BEGIN because isolation_level=None
            self('BEGIN')
            yield

    def import_json_file(self, json_file: Path) -> None:
        """
        Import the given downloads content from the given JSON file
        """
        with json_file.open('r', encoding='utf-8') as f:
            data = json.load(f)
        self.import_json_data(data)

    def import_json_data(self, data: 'Any') -> None:
        """
        Import the given downloads content from the given JSON-like data
        """
        with self.transaction():
            self._import_json_data(data)

    def _import_json_data(self, data: 'Any') -> None:
        # We're reloading everything, so just drop and re-create the tables.
        # Bonus: We don't have to worry about schema changes
        self('DROP TABLE IF EXISTS mdl_components')
        self('DROP TABLE IF EXISTS mdl_downloads')
        self('DROP TABLE IF EXISTS mdl_versions')
        self(r'''
            CREATE TABLE mdl_versions (
                version_id INTEGER PRIMARY KEY,
                date TEXT NOT NULL,
                version TEXT NOT NULL,
                githash TEXT NOT NULL
            )
        ''')
        self(r'''
            CREATE TABLE mdl_downloads (
                download_id INTEGER PRIMARY KEY,
                version_id INTEGER NOT NULL REFERENCES mdl_versions,
                target TEXT NOT NULL,
                arch TEXT NOT NULL,
                edition TEXT NOT NULL,
                ar_url TEXT NOT NULL,
                data TEXT NOT NULL
            )
        ''')
        self(r'''
            CREATE TABLE mdl_components (
                component_id INTEGER PRIMARY KEY,
                key TEXT NOT NULL,
                download_id INTEGER NOT NULL REFERENCES mdl_downloads,
                data NOT NULL,
                UNIQUE(key, download_id)
            )
        ''')
        for ver in data['versions']:
            version = ver['version']
            githash = ver['githash']
            date = ver['date']
            self(
                r'''
                INSERT INTO mdl_versions (date, version, githash)
                VALUES (:date, :version, :githash)
                ''',
                date=date,
                version=version,
                githash=githash,
            )
            version_id = self._cursor.lastrowid
            for dl in ver['downloads']:
                arch = dl.get('arch', 'null')
                target = dl.get('target', 'null')
                edition = dl['edition']
                ar_url = dl['archive']['url']
                self(
                    r'''
                    INSERT INTO mdl_downloads (version_id,
                                               target,
                                               arch,
                                               edition,
                                               ar_url,
                                               data)
                    VALUES (:version_id,
                            :target,
                            :arch,
                            :edition,
                            :ar_url,
                            :data)
                    ''',
                    version_id=version_id,
                    target=target,
                    arch=arch,
                    edition=edition,
                    ar_url=ar_url,
                    data=json.dumps(dl),
                )
                dl_id = self._cursor.lastrowid
                for key, data in dl.items():
                    if 'url' not in data:
                        # Some fields aren't downloadable items. Skip them
                        continue
                    self(
                        r'''
                        INSERT INTO mdl_components (key, download_id, data)
                        VALUES (:key, :dl_id, :data)
                        ''',
                        key=key,
                        dl_id=dl_id,
                        data=json.dumps(data),
                    )

    def iter_available(
            self,
            *,
            version: 'str | None' = None,
            target: 'str | None' = None,
            arch: 'str | None' = None,
            edition: 'str | None' = None,
            component: 'str | None' = None
    ) -> 'Iterable[DownloadableComponent]':
        """
        Iterate over the matching downloadable components according to the
        given attribute filters.
        """
        rows = self(
            r'''
            SELECT version, target, arch, edition, key, mdl_components.data
              FROM mdl_components,
                   mdl_downloads USING(download_id),
                   mdl_versions USING(version_id)
            WHERE (:component IS NULL OR key=:component)
              AND (:target IS NULL OR target=:target)
              AND (:arch IS NULL OR arch=:arch)
              AND (:edition IS NULL OR edition=:edition)
              AND (
                  CASE
                    WHEN :version='latest'
                        THEN 1
                    WHEN :version='latest-stable'
                        THEN mdb_version_not_rc(version)
                    WHEN :version IS NULL
                        THEN 1
                    ELSE version=:version
                  END)
            ORDER BY version COLLATE mdb_version DESC
            ''',
            version=version,
            target=target,
            arch=arch,
            edition=edition,
            component=component,
        )
        for row in rows:
            yield DownloadableComponent(*row)  # type: ignore


class Cache:
    """
    Abstraction over a mongodl downloads cache directory.
    """

    def __init__(self, dirpath: Path, db: CacheDB) -> None:
        self._dirpath = dirpath
        self._db = db

    @staticmethod
    def open_default() -> 'Cache':
        """
        Open the default user-local cache directory
        """
        return Cache.open_in(default_cache_dir())

    @staticmethod
    def open_in(dirpath: Path) -> 'Cache':
        """
        Open or create a cache directory at the given path.
        """
        _mkdir(dirpath)
        db = CacheDB.open(dirpath / 'data.db')
        return Cache(dirpath, db)

    @property
    def db(self):
        """The backing cache database"""
        return self._db

    def download_file(self, url: str) -> DownloadResult:
        """
        Obtain a local copy of the file at the given URL.
        """
        info = self._db(
            'SELECT etag, last_modified '
            'FROM mdl_http_downloads WHERE url=:url',
            url=url)
        etag = None  # type: str|None
        modtime = None  # type: str|None
        etag, modtime = next(iter(info), (None, None))  # type: ignore
        headers = {}  # type: dict[str, str]
        if etag:
            headers['If-None-Match'] = etag
        if modtime:
            headers['If-Modified-Since'] = modtime
        req = urllib.request.Request(url, headers=headers)
        digest = hashlib.md5(url.encode("utf-8")).hexdigest()[:4]
        dest = self._dirpath / 'files' / digest / PurePosixPath(url).name

        try:
            resp = urllib.request.urlopen(req)
        except urllib.error.HTTPError as e:
            if e.code != 304:
                raise
            assert dest.is_file(), (
                'The download cache is missing an expected file', dest)
            return DownloadResult(False, dest)

        _mkdir(dest.parent)
        got_etag = resp.getheader("ETag")
        got_modtime = resp.getheader('Last-Modified')
        with dest.open('wb') as of:
            buf = resp.read(1024 * 1024 * 4)
            while buf:
                of.write(buf)
                buf = resp.read(1024 * 1024 * 4)
        self._db(
            'INSERT OR REPLACE INTO mdl_http_downloads (url, etag, last_modified) '
            'VALUES (:url, :etag, :mtime)',
            url=url,
            etag=got_etag,
            mtime=got_modtime)
        return DownloadResult(True, dest)

    def refresh_full_json(self) -> None:
        """
        Sync the content of the MongoDB full.json downloads list.
        """
        with self._db.transaction():
            dl = self.download_file('https://downloads.mongodb.org/full.json')
            if not dl.is_changed:
                # We still have a good cache
                return
            self._db.import_json_file(dl.path)


def _mkdir(dirpath: Path) -> None:
    """
    Ensure a directory at ``dirpath``, and all parent directories thereof.

    (Cannot using Path.mkdir(parents, exist_ok) on some Python versions that
    we need to support.)
    """
    if dirpath.is_dir():
        return
    par = dirpath.parent
    if par != dirpath:
        _mkdir(par)
    try:
        dirpath.mkdir()
    except FileExistsError:
        pass


def _print_list(db: CacheDB, version: 'str | None', target: 'str | None',
                arch: 'str | None', edition: 'str | None',
                component: 'str | None'):

    if version or target or arch or edition or component:
        counter = 0
        matching = db.iter_available(version=version,
                                     target=target,
                                     arch=arch,
                                     edition=edition,
                                     component=component)
        for version, target, arch, edition, comp_key, comp_data in matching:
            counter += 1
            print('Download: {}\n'
                  ' Version: {}\n'
                  '  Target: {}\n'
                  '    Arch: {}\n'
                  ' Edition: {}\n'
                  '    Info: {}\n\n'.format(comp_key, version, target, arch,
                                            edition, comp_data))
        if counter == 1:
            print('Only one matchin item')
        elif counter == 0:
            print('No items matched the listed filters')
        else:
            print('{} available downloadable components'.format(counter))
        print('(Omit filter arguments for a list of available filters)')
        return

    tup = next(
        iter(  # type: ignore
            db(r'''
        VALUES(
            (select group_concat(arch, ', ') from (select distinct arch from mdl_downloads)),
            (select group_concat(target, ', ') from (select distinct target from mdl_downloads)),
            (select group_concat(edition, ', ') from (select distinct edition from mdl_downloads)),
            (select group_concat(version, ', ') from (
                select distinct version from mdl_versions
                ORDER BY version COLLATE mdb_version)),
            (select group_concat(key, ', ') from (select distinct key from mdl_components))
        )
        ''')))  # type: tuple[str, str, str, str, str]
    arches, targets, editions, versions, components = tup
    versions = '\n'.join(
        textwrap.wrap(versions,
                      width=78,
                      initial_indent='  ',
                      subsequent_indent='  '))
    targets = '\n'.join(
        textwrap.wrap(targets,
                      width=78,
                      initial_indent='  ',
                      subsequent_indent='  '))
    print('Architectures:\n'
          '  {}\n'
          'Targets:\n'
          '{}\n'
          'Editions:\n'
          '  {}\n'
          'Versions:\n'
          '{}\n'
          'Components:\n'
          '  {}\n'.format(arches, targets, editions, versions, components))


def infer_arch():
    a = platform.machine() or platform.processor()
    # Remap platform names to the names used for downloads
    return {
        'AMD64': 'x86_64',
    }.get(a, a)


class ExpandResult(enum.Enum):
    Empty = 0
    "No files were/would be extracted"
    Okay = 1
    "One or more files were/would be extracted"


def _dl_component(cache: Cache, out_dir: Path, version: str, target: str,
                  arch: str, edition: str, component: str,
                  pattern: 'str | None', strip_components: int,
                  test: bool) -> ExpandResult:
    print('Download {} {}-{} for {}-{}'.format(component, version, edition,
                                               target, arch))
    matching = cache.db.iter_available(version=version,
                                       target=target,
                                       arch=arch,
                                       edition=edition,
                                       component=component)
    tup = next(iter(matching), None)
    if tup is None:
        raise ValueError(
            'No download for "{}" was found for '
            'the requested version+target+architecture+edition'.format(
                component))
    data = json.loads(tup.data_json)
    cached = cache.download_file(data['url']).path
    return _expand_archive(cached,
                           out_dir,
                           pattern,
                           strip_components,
                           test=test)


def _pathjoin(items: 'Iterable[str]') -> PurePath:
    """
    Return a path formed by joining the given path components
    """
    return PurePath('/'.join(items))


def _test_pattern(path: PurePath, pattern: 'PurePath | None') -> bool:
    """
    Test whether the given 'path' string matches the globbing pattern 'pattern'.

    Supports the '**' pattern to match any number of intermediate directories.
    """
    if pattern is None:
        return True
    # Split pattern into parts
    pattern_parts = pattern.parts
    if not pattern_parts:
        # An empty pattern always matches
        return True
    path_parts = path.parts
    if not path_parts:
        # Non-empty pattern requires more path components
        return False
    pattern_head = pattern_parts[0]
    pattern_tail = _pathjoin(pattern_parts[1:])
    if pattern_head == '**':
        # Special "**" pattern matches any suffix of the path
        # Generate each suffix:
        tails = (path_parts[i:] for i in range(len(path_parts)))
        # Test if any of the suffixes match the remainder of the pattern:
        return any(_test_pattern(_pathjoin(t), pattern_tail) for t in tails)
    if not fnmatch(path.parts[0], pattern_head):
        # Leading path component cannot match
        return False
    # The first component matches. Test the remainder:
    return _test_pattern(_pathjoin(path_parts[1:]), pattern_tail)


def _expand_archive(ar: Path, dest: Path, pattern: 'str | None',
                    strip_components: int, test: bool) -> ExpandResult:
    '''
    Expand the archive members from 'ar' into 'dest'. If 'pattern' is not-None,
    only extracts members that match the pattern.
    '''
    print('Extract from: [{}]'.format(ar.name))
    print('        into: [{}]'.format(dest))
    if ar.suffix == '.zip':
        n_extracted = _expand_zip(ar,
                                  dest,
                                  pattern,
                                  strip_components,
                                  test=test)
    elif ar.suffix == '.tgz':
        n_extracted = _expand_tgz(ar,
                                  dest,
                                  pattern,
                                  strip_components,
                                  test=test)
    else:
        raise RuntimeError('Unknown archive file extension: ' + ar.suffix)
    verb = 'would be' if test else 'were'
    if n_extracted == 0:
        if pattern and strip_components:
            print('NOTE: No files {verb} extracted. Likely all files {verb} '
                  'excluded by "--only={p}" and/or "--strip-components={s}"'.
                  format(p=pattern, s=strip_components, verb=verb))
        elif pattern:
            print('NOTE: No files {verb} extracted. Likely all files {verb} '
                  'excluded by the "--only={p}" filter'.format(p=pattern,
                                                               verb=verb))
        elif strip_components:
            print('NOTE: No files {verb} extracted. Likely all files {verb} '
                  'excluded by "--strip-components={s}"'.format(
                      s=strip_components, verb=verb))
        else:
            print('NOTE: No files {verb} extracted. Empty archive?'.format(
                verb=verb))
        return ExpandResult.Empty
    elif n_extracted == 1:
        print('One file {v} extracted'.format(v='would be' if test else 'was'))
        return ExpandResult.Okay
    else:
        print('{n} files {verb} extracted'.format(n=n_extracted, verb=verb))
        return ExpandResult.Okay


def _expand_tgz(ar: Path, dest: Path, pattern: 'str | None',
                strip_components: int, test: bool) -> int:
    'Expand a tar.gz archive'
    n_extracted = 0
    with tarfile.open(str(ar), 'r:*') as tf:
        for mem in tf.getmembers():
            n_extracted += _maybe_extract_member(
                dest,
                PurePath(mem.name),
                pattern,
                strip_components,
                mem.isdir(),
                lambda: cast('IO[bytes]', tf.extractfile(mem)),
                mem.mode,
                test=test,
            )
    return n_extracted


def _expand_zip(ar: Path, dest: Path, pattern: 'str | None',
                strip_components: int, test: bool) -> int:
    'Expand a .zip archive.'
    n_extracted = 0
    with zipfile.ZipFile(ar, 'r') as zf:
        for item in zf.infolist():
            n_extracted += _maybe_extract_member(
                dest,
                PurePath(item.filename),
                pattern,
                strip_components,
                item.is_dir(),
                lambda: zf.open(item, 'r'),
                0o655,
                test=test,
            )
    return n_extracted


def _maybe_extract_member(out: Path, relpath: PurePath, pattern: 'str | None',
                          strip: int, is_dir: bool,
                          opener: 'Callable[[], IO[bytes]]', modebits: int,
                          test: bool) -> int:
    """
    Try to extract an archive member according to the given arguments.

    :return: Zero if the file was excluded by filters, one otherwise.
    """
    relpath = PurePath(relpath)
    print('  | {:-<65} |'.format(str(relpath) + ' '), end='')
    if len(relpath.parts) <= strip:
        # Not enough path components
        print(' (Excluded by --strip-components)')
        return 0
    if not _test_pattern(relpath, PurePath(pattern) if pattern else None):
        # Doesn't match our pattern
        print(' (excluded by pattern)')
        return 0
    stripped = _pathjoin(relpath.parts[strip:])
    dest = Path(out) / stripped
    print('\n    -> [{}]'.format(dest))
    if test:
        # We are running in test-only mode: Do not do anything
        return 1
    if is_dir:
        _mkdir(dest)
        return 1
    with opener() as infile:
        _mkdir(dest.parent)
        with dest.open('wb') as outfile:
            shutil.copyfileobj(infile, outfile)
        os.chmod(str(dest), modebits)
    return 1


def main(argv: 'Sequence[str]'):
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        '--cache-dir',
        type=Path,
        default=default_cache_dir(),
        help='Directory where download caches and metadata will be stored')
    grp = parser.add_argument_group('List arguments')
    grp.add_argument('--list',
                     action='store_true',
                     help='List available components, targets, editions, and '
                     'architectures. Download arguments will act as filters.')
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
        '--edition',
        '-E',
        help='The edition of the product to download (Default is "enterprise"). '
        'Use "--list" to list available editions.')
    dl_grp.add_argument(
        '--out',
        '-o',
        help='The directory in which to download components. (Required)',
        type=Path)
    dl_grp.add_argument(
        '--version',
        '-V',
        help=
        'The product version to download (Required). Use "latest" to download '
        'the newest available version (including release candidates). Use '
        '"latest-stable" to download the newest version, excluding release '
        'candidates. Use "--list" to list available versions.')
    dl_grp.add_argument('--component',
                        '-C',
                        help='The component to download (Required). '
                        'Use "--list" to list available components.')
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
        '--test',
        action='store_true',
        help='Do not extract or place any files/directories. '
        'Only print what will be extracted without placing any files.')
    dl_grp.add_argument('--empty-is-error',
                        action='store_true',
                        help='If all files are excluded by other filters, '
                        'treat that situation as an error and exit non-zero.')
    args = parser.parse_args()
    cache = Cache.open_in(args.cache_dir)
    cache.refresh_full_json()

    if args.list:
        _print_list(cache.db, args.version, args.target, args.arch,
                    args.edition, args.component)
        return

    if args.version is None:
        raise argparse.ArgumentError(None, 'A "--version" is required')
    if args.component is None:
        raise argparse.ArgumentError(
            None, 'A "--component" name should be provided')
    if args.out is None:
        raise argparse.ArgumentError(None,
                                     'A "--out" directory should be provided')

    target = args.target
    if target in (None, 'auto'):
        target = infer_target()
    arch = args.arch
    if arch in (None, 'auto'):
        arch = infer_arch()
    edition = args.edition or 'enterprise'
    out = args.out or Path.cwd()
    out = out.absolute()
    result = _dl_component(cache,
                           out,
                           version=args.version,
                           target=target,
                           arch=arch,
                           edition=edition,
                           component=args.component,
                           pattern=args.only,
                           strip_components=args.strip_components,
                           test=args.test)
    if result is ExpandResult.Empty and args.empty_is_error:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
