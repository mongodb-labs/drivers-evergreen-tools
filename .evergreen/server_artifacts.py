"""Resolve credentials and build presigned URLs for private server artifacts."""

import json
import os

_SERVER_ARTIFACTS_BUCKET = "origin-mongodb-server-latest"
_SERVER_ARTIFACTS_PREFIX = "server-latest"
_SERVER_ARTIFACTS_REGION = "us-east-1"
_DEFAULT_SECRET_VAULT = "drivers/devprod-release-infrastructure"


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
    s3 = _resolve_s3_client(key)
    full_key = f"{_SERVER_ARTIFACTS_PREFIX}/{key}"
    return s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": _SERVER_ARTIFACTS_BUCKET, "Key": full_key},
        ExpiresIn=3600,
    )
