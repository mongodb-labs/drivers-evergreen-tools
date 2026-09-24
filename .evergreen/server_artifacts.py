"""Resolve credentials, build presigned URLs, and verify signatures for private server artifacts."""

import json
import logging
import os
import shutil
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Callable

LOGGER = logging.getLogger(__name__)

_SERVER_ARTIFACTS_BUCKET = "origin-mongodb-server-latest"
_SERVER_ARTIFACTS_PREFIX = "server-latest"
_SERVER_ARTIFACTS_REGION = "us-east-1"
_DEFAULT_SECRET_VAULT = "drivers/devprod-release-infrastructure"

#: The MongoDB release signing public keys, fetched at verification time.
#: Detached signatures for "latest"/"latest-build" builds are verified
#: against these keys.
MONGODB_GPG_KEY_URLS = (
    "https://pgp.mongodb.com/server-9.asc",
    "https://pgp.mongodb.com/server-8.0.asc",
)

#: The fingerprints of the MongoDB release signing keys that a signature of a
#: "latest"/"latest-build" build must match. A signature made by any other key
#: fails the download.
MONGODB_GPG_KEY_FINGERPRINTS = frozenset(
    (
        "B3B42B6C39E5CDDEC0A27E3CF366D55B602E502D",
        "4B0752C1BCA238C0B4EE14DC41DE058A4E7DCA05",
    )
)

SSL_CONTEXT = ssl.create_default_context()
try:
    import certifi

    SSL_CONTEXT.load_verify_locations(certifi.where())
except ImportError:
    pass


class PrivateArtifactsUnavailableError(RuntimeError):
    """Raised when credentials for the private server artifacts cannot be resolved."""


class NoAWSCredentialsError(PrivateArtifactsUnavailableError):
    """Raised when no usable AWS credentials are available at all."""


class VaultAccessDeniedError(PrivateArtifactsUnavailableError):
    """Raised when the ambient identity may not read the credentials vault."""


class RoleAssumptionError(PrivateArtifactsUnavailableError):
    """Raised when the ambient identity may not assume the required roles."""


def _boto3_client(service: str, region: str, creds: "dict|None" = None):
    import boto3

    kwargs = {"region_name": region}
    if creds:
        kwargs.update(
            aws_access_key_id=creds["AccessKeyId"],
            aws_secret_access_key=creds["SecretAccessKey"],
            aws_session_token=creds["SessionToken"],
        )
    return boto3.client(service, **kwargs)


def _has_s3_access(s3, key: str) -> bool:
    from botocore.exceptions import ClientError, NoCredentialsError

    full_key = f"{_SERVER_ARTIFACTS_PREFIX}/{key}"
    try:
        s3.head_object(Bucket=_SERVER_ARTIFACTS_BUCKET, Key=full_key)
        return True
    except ClientError as err:
        # A 404 means the credentials were accepted but the object is absent;
        # the download surfaces that as "no matching file" on its own.
        if err.response["ResponseMetadata"]["HTTPStatusCode"] == 404:
            return True
        if err.response["ResponseMetadata"]["HTTPStatusCode"] == 403:
            return False
        raise
    except NoCredentialsError:
        return False


def _resolve_s3_client(key: str):
    from botocore.exceptions import BotoCoreError, ClientError, NoCredentialsError

    # Stage 1: use whatever identity is already ambient.
    s3 = _boto3_client("s3", _SERVER_ARTIFACTS_REGION)
    if _has_s3_access(s3, key):
        return s3

    vault = os.environ.get("SERVER_ARTIFACTS_SECRET_VAULT", _DEFAULT_SECRET_VAULT)
    try:
        secretsmanager = _boto3_client("secretsmanager", _SERVER_ARTIFACTS_REGION)
        config = json.loads(
            secretsmanager.get_secret_value(SecretId=vault)["SecretString"]
        )
    except BotoCoreError as err:
        # Covers NoCredentialsError, ProfileNotFound, and the other client-side
        # errors: there is no usable ambient identity at all.
        raise NoAWSCredentialsError(
            "cannot resolve credentials for the private server artifacts: no "
            "usable AWS identity. Set AWS_PROFILE (or AWS_ACCESS_KEY_ID / "
            "AWS_SECRET_ACCESS_KEY), or use --version latest-stable, which "
            "needs no AWS access."
        ) from err
    except ClientError as err:
        raise VaultAccessDeniedError(
            "cannot resolve credentials for the private server artifacts; the "
            f"ambient identity cannot read the {vault!r} vault"
        ) from err

    sts = _boto3_client("sts", _SERVER_ARTIFACTS_REGION)

    # Stage 2: assume the artifacts role directly from the ambient identity.
    try:
        artifacts_creds = sts.assume_role(
            RoleArn=config["SERVER_ARTIFACTS_ROLE_ARN"], RoleSessionName="mongodl"
        )["Credentials"]
    except (ClientError, NoCredentialsError):
        artifacts_creds = None
    if artifacts_creds is not None:
        s3 = _boto3_client("s3", _SERVER_ARTIFACTS_REGION, artifacts_creds)
        if _has_s3_access(s3, key):
            return s3

    # Stage 3: assume the secrets role first, then the artifacts role.
    try:
        secrets_creds = sts.assume_role(
            RoleArn=config["DRIVERS_TEST_SECRETS_ROLE_ARN"], RoleSessionName="mongodl"
        )["Credentials"]
        artifacts_creds = _boto3_client(
            "sts", _SERVER_ARTIFACTS_REGION, secrets_creds
        ).assume_role(
            RoleArn=config["SERVER_ARTIFACTS_ROLE_ARN"], RoleSessionName="mongodl"
        )["Credentials"]
    except (ClientError, NoCredentialsError) as err:
        raise RoleAssumptionError(
            "cannot resolve credentials for the private server artifacts; the "
            "ambient identity cannot assume the required roles"
        ) from err

    return _boto3_client("s3", _SERVER_ARTIFACTS_REGION, artifacts_creds)


def presigned_url(key: str) -> str:
    """
    Build a presigned HTTPS URL for a private server artifact.

    Credentials are tried in order: the ambient identity, the artifacts role
    assumed directly, then the artifacts role reached through the
    drivers-test-secrets role.
    """
    return presigned_urls(key)[0]


def presigned_urls(*keys: str) -> "list[str]":
    """
    Build presigned HTTPS URLs for several private server artifacts.

    Credentials are resolved once, probing the first key; the other keys are
    presigned with the same client without probing, so an absent or
    access-hidden object among them cannot degrade the credential resolution.
    """
    s3 = _resolve_s3_client(keys[0])
    return [
        s3.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": _SERVER_ARTIFACTS_BUCKET,
                "Key": f"{_SERVER_ARTIFACTS_PREFIX}/{key}",
            },
            ExpiresIn=3600,
        )
        for key in keys
    ]


def _download_bytes(url: str) -> bytes:
    """Download the content at the given URL as bytes."""
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, context=SSL_CONTEXT, timeout=30) as resp:
        return resp.read()


def _fetch_signature(sig_url: str) -> "bytes | None":
    """
    Download a detached GPG signature, or None if it was not published.

    S3 answers 404 for a missing key, or 403 when the caller cannot list the
    bucket and the missing object is hidden behind the denial, so both codes
    mean "not published here". Any other failure propagates and fails the
    download. Callers must pass a freshly authorized URL: an expired
    presigned URL also answers 403, and would be mistaken for a signature
    that was never published.
    """
    try:
        return _download_bytes(sig_url)
    except urllib.error.HTTPError as e:
        if e.code in (403, 404):
            return None
        raise


def _gpg_path(path: Path) -> str:
    """
    Spell 'path' the way the host's gpg expects.

    The Cygwin/MSYS gpg builds on the Windows CI hosts resolve POSIX-style
    paths only: both the native spelling (C:\\...) and the forward-slash form
    (C:/...) are taken for a relative path. cygpath (or an MSYS equivalent)
    yields the right spelling, /cygdrive/c/... or /c/...; on hosts whose gpg
    is a native Windows build there is no cygpath, and the forward-slash form
    is correct instead. Elsewhere the absolute native path is what gpg, and
    the gpg-agent it starts, expect.
    """
    if sys.platform == "win32":
        try:
            proc = subprocess.run(
                ["cygpath", "-u", str(path)],
                capture_output=True,
                text=True,
                check=True,
            )
        except (OSError, subprocess.CalledProcessError):
            return path.as_posix()
        return proc.stdout.strip()
    return str(path)


def _import_gpg_keys(gpg_exe: str, home_arg: str) -> None:
    """
    Import the pinned MongoDB release signing keys into the given gpg home.
    """
    for url in MONGODB_GPG_KEY_URLS:
        key = _download_bytes(url)
        proc = subprocess.run(
            [gpg_exe, "--homedir", home_arg, "--batch", "--import"],
            input=key,
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0:
            stderr = proc.stderr.decode(errors="replace")
            raise RuntimeError(
                f"Failed to import the MongoDB release signing key [{url}]:\n{stderr}"
            )


def _verify_gpg_signature(gpg_exe: str, archive: Path, signature: bytes) -> str:
    """
    Verify a detached GPG signature against the pinned MongoDB release keys.

    Returns the fingerprint of the signing key, or raises ValueError if the
    signature is bad or was not made by a pinned key.
    """
    with tempfile.TemporaryDirectory(prefix="mongodl-gpg") as tmp:
        home = Path(tmp)
        # gpg refuses to use a home directory with loose permissions.
        home.chmod(0o700)
        home_arg = _gpg_path(home)
        sig_path = home / f"{archive.name}.sig"
        sig_path.write_bytes(signature)
        sig_arg = _gpg_path(sig_path)
        _import_gpg_keys(gpg_exe, home_arg)
        proc = subprocess.run(
            [
                gpg_exe,
                "--homedir",
                home_arg,
                "--batch",
                "--no-tty",
                "--status-fd",
                "1",
                "--verify",
                sig_arg,
                _gpg_path(archive),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        # A good signature reports a "VALIDSIG" line naming the fingerprint
        # of the signing key and (for a subkey signature) of the primary
        # key. Parse the fingerprints ourselves: only a pinned key may sign
        # a build, even if gpg itself is happy (it exits 0 for expired keys
        # and expired signatures, too). Every field is checked rather than a
        # fixed index, since the number of VALIDSIG arguments varies across
        # gpg versions.
        fingerprints = set()
        expired_or_revoked = False
        for line in proc.stdout.splitlines():
            fields = line.split()
            if len(fields) < 3 or fields[0] != "[GNUPG:]":
                continue
            if fields[1] == "VALIDSIG":
                fingerprints.update(
                    field for field in fields if field in MONGODB_GPG_KEY_FINGERPRINTS
                )
            elif fields[1] in ("EXPKEYSIG", "EXPSIG", "REVKEYSIG"):
                expired_or_revoked = True
        if proc.returncode != 0 or expired_or_revoked or not fingerprints:
            if expired_or_revoked:
                detail = (
                    "the signature or the key that made it has expired, or "
                    "the key has been revoked"
                )
            elif proc.returncode == 0:
                detail = (
                    "the signature was not made by a pinned MongoDB release "
                    "signing key"
                )
            else:
                detail = proc.stderr
            raise ValueError(
                f"Signature verification for [{archive.name}] failed: {detail}"
            )
        return next(iter(fingerprints))


def verify_latest_build(archive: Path, get_sig_url: "Callable[[], str]") -> None:
    """
    Verify the detached signature of a "latest"/"latest-build" archive.

    A bad signature raises, failing the download. A missing signature
    (stable-branch staging builds may not be signed yet), or a missing gpg,
    only produces a warning, and the download continues. The signature URL
    is fetched through get_sig_url, so the caller authorizes the fetch when
    it happens: a presigned URL that outlived the archive download would
    answer 403 and be mistaken for a missing signature.
    """
    gpg_exe = shutil.which("gpg")
    if gpg_exe is None:
        LOGGER.warning(
            "gpg is not installed, so the signature of %s will not be verified",
            archive.name,
        )
        return
    signature = _fetch_signature(get_sig_url())
    if signature is None:
        LOGGER.warning(
            "No signature was published for this build, so the signature of "
            "%s will not be verified",
            archive.name,
        )
        return
    fingerprint = _verify_gpg_signature(gpg_exe, archive, signature)
    LOGGER.info("Verified GPG signature of %s with key %s", archive.name, fingerprint)
