"""OpenTelemetry file-exporter configuration for trace-context prose tests
(DRIVERS-3454). Requires MongoDB 9.0+. See README.md in this directory.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

PLATFORM = sys.platform.lower()

# samplingFactor 1.0 samples every span (production default is ~0.000045,
# which would make span assertions flake). Per the server IDL
# (src/mongo/otel/traces/trace_sampling_parameters.idl), every sampling
# strategy -- including defaultSampling -- also carries its own
# tokenBucketRateLimit (default refillRate 1/s, maxTokens 10) that throttles
# spans independently of samplingFactor, so it must be raised here too or
# internally-initiated spans still get capped at a 10-burst.
OTEL_SAMPLING_JSON = (
    '{"defaultSampling":{"samplingFactor":1.0,'
    '"tokenBucketRateLimit":{"refillRate":1000.0,"maxTokens":1000}}}'
)
# Externally-propagated contexts (driver traceparents) bypass the probability
# sampler entirely and go through the separate openTelemetryExternalTracing
# setParameter -- NOT nested under openTelemetryTracingSampling -- which
# needs the same raise.
OTEL_EXTERNAL_TRACING_JSON = (
    '{"tokenBucketRateLimit":{"refillRate":1000.0,"maxTokens":1000}}'
)
OTEL_DIR_NAME = "otel"


def normalize_path(path: Path | str) -> str:
    if PLATFORM != "win32":
        return str(path)
    path = Path(path).as_posix()
    return re.sub("/cygdrive/(.*?)(/)", r"\1://", path, count=1)


def handle_otel_config(data, otel_root):
    """Configure every mongod/mongos to export OTel spans as NDJSON files.

    Each member gets its own trace directory (keyed by port) under otel_root
    so files from different members never interleave.
    """
    members = []

    def traverse(root):
        if isinstance(root, list):
            [traverse(i) for i in root if isinstance(i, (dict, list))]
            return
        if "ipv6" in root:
            members.append(root)
            return
        for value in root.values():
            if isinstance(value, (dict, list)):
                traverse(value)

    traverse(data)

    if not members:
        raise ValueError(
            "--otel found no cluster members to configure in the "
            "orchestration config (members are identified by an 'ipv6' key "
            "in their process settings)"
        )

    for member in members:
        if "port" not in member:
            raise ValueError(
                "--otel requires an explicit port for every cluster member "
                "so each gets its own trace directory"
            )
        member_dir = Path(otel_root) / str(member["port"])
        os.makedirs(member_dir, exist_ok=True)
        set_param = member.setdefault("setParameter", {})
        # Pre-existing OTel settings (e.g. opentelemetryHttpEndpoint, or a
        # tracing compression the file exporter rejects) can conflict with
        # the parameters injected below and would only fail at server
        # startup, after the download. The tracing feature flags are also
        # rejected: featureFlagTracing=false would start fine yet silently
        # export no spans (the server requires it alongside
        # featureFlagOtelTraceSampling), and a pre-set
        # featureFlagOtelTraceSampling would be silently overwritten below.
        # Fail fast instead.
        conflicts = [
            k
            for k in set_param
            if k.lower().startswith("opentelemetry")
            or k in ("featureFlagTracing", "featureFlagOtelTraceSampling")
        ]
        if conflicts:
            raise ValueError(
                f"--otel conflicts with OpenTelemetry setParameters already "
                f"present in the orchestration config: {conflicts}"
            )
        set_param["opentelemetryTraceDirectory"] = normalize_path(member_dir)
        set_param["featureFlagOtelTraceSampling"] = "true"
        set_param["openTelemetryTracingSampling"] = OTEL_SAMPLING_JSON
        set_param["openTelemetryExternalTracing"] = OTEL_EXTERNAL_TRACING_JSON
        # The file exporter buffers 256 export batches (flushed every 30s) by
        # default, on top of the 1s batch processor; tests emit few spans, so
        # flush every batch to disk like the server's own file-export tests.
        set_param["openTelemetryTracingFileFlushCount"] = 1


def validate_otel_opts(opts):
    """Fail fast on option combinations incompatible with --otel.

    The OTel file exporter requires MongoDB 9.0+ and a cluster that shares
    the host filesystem with the test process (the only way to read spans).

    This only rejects what can be decided locally from the options; the
    authoritative version check is check_mongod_version(), which probes the
    actual binary after it is downloaded or copied and therefore also covers
    version aliases, nightlies, and --existing-binaries-dir uniformly.
    """
    if not getattr(opts, "otel", False):
        return
    if os.environ.get("DOCKER_RUNNING"):
        raise ValueError(
            "--otel is not supported with DOCKER_RUNNING: the container "
            "filesystem is not readable by the host test process"
        )
    if opts.local_atlas:
        raise ValueError("--otel is not supported with --local-atlas")
    # Courtesy pre-check: reject obviously sub-9.0 version strings (e.g.
    # "8.0", "v8.0-perf") before any download. Skipped when
    # --existing-binaries-dir is set, where the requested version is not
    # what runs. Aliases like "rapid" pass through here and are decided by
    # the binary probe instead.
    if not getattr(opts, "existing_binaries_dir", None):
        match = re.match(r"^v?(\d+)(?:\.(\d+))?", opts.version)
        if match and (int(match.group(1)), int(match.group(2) or 0)) < (9, 0):
            raise ValueError(
                f"--otel requires MongoDB 9.0+ (OTel setParameters do not "
                f"exist on {opts.version})"
            )


def check_mongod_version(binaries_dir):
    """Raise ValueError unless the mongod in binaries_dir reports 9.0+.

    This is the authoritative --otel version gate: it measures the binary
    that will actually run, so it covers explicit versions, aliases,
    nightlies (including stale ones on dropped targets), and
    --existing-binaries-dir with a single mechanism.
    """
    ext = ".exe" if PLATFORM == "win32" else ""
    mongod = Path(binaries_dir) / f"mongod{ext}"
    try:
        output = subprocess.check_output(
            [str(mongod), "--version"], encoding="utf-8", stderr=subprocess.STDOUT
        )
    except (OSError, subprocess.CalledProcessError) as e:
        raise ValueError(
            f"--otel could not determine the server version from "
            f"{mongod} --version: {e}"
        ) from e
    version = _version_from_mongod_output(output)
    if version is None:
        raise ValueError(
            f"--otel could not parse the server version from "
            f"{mongod} --version output: {output.splitlines()[:1]}"
        )
    if version < (9, 0):
        raise ValueError(
            f"--otel requires MongoDB 9.0+, but the mongod binary reports "
            f"db version v{version[0]}.{version[1]}"
        )


def _version_from_mongod_output(output):
    """(major, minor) from `mongod --version` output, or None."""
    match = re.search(r"db version v(\d+)\.(\d+)", output)
    if match is None:
        return None
    return (int(match.group(1)), int(match.group(2)))
