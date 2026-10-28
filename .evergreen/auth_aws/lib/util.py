import urllib.error
import urllib.request

IMDS_URL = "http://169.254.169.254"


def get_key(key: str, uppercase: bool) -> str:
    if uppercase:
        return key.upper()
    return key


def imds_get(path: str, timeout: float = 10) -> str:
    """Read EC2 instance metadata using an IMDSv2 session token."""
    token_req = urllib.request.Request(
        IMDS_URL + "/latest/api/token",
        method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
    )
    try:
        token = urllib.request.urlopen(token_req, timeout=timeout).read().decode()
    except urllib.error.URLError as e:
        # Token failures must not look like a 404 (no instance profile) to callers.
        raise RuntimeError(f"Failed to get an IMDSv2 session token: {e}") from e

    req = urllib.request.Request(
        IMDS_URL + path, headers={"X-aws-ec2-metadata-token": token}
    )
    return urllib.request.urlopen(req, timeout=timeout).read().decode()
