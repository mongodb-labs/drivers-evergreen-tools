"""Unit tests for drivers_orchestration helpers. Run with:
python -m unittest test_drivers_orchestration -v
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from drivers_orchestration import (
    OTEL_EXTERNAL_TRACING_JSON,
    OTEL_SAMPLING_JSON,
    handle_otel_config,
    normalize_path,
    validate_otel_opts,
)

EXPECTED_PARAMS = {
    "featureFlagOtelTraceSampling": "true",
    "openTelemetryTracingSampling": OTEL_SAMPLING_JSON,
    "openTelemetryExternalTracing": OTEL_EXTERNAL_TRACING_JSON,
    "openTelemetryTracingFileFlushCount": 1,
}


class TestHandleOtelConfig(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.otel_root = Path(self._tmp.name) / "otel"

    def tearDown(self):
        self._tmp.cleanup()

    def assert_member(self, params, port):
        for key, value in EXPECTED_PARAMS.items():
            self.assertEqual(params["setParameter"][key], value)
        trace_dir = params["setParameter"]["opentelemetryTraceDirectory"]
        self.assertEqual(trace_dir, normalize_path(self.otel_root / str(port)))
        self.assertTrue((self.otel_root / str(port)).is_dir())

    def test_standalone(self):
        data = {
            "name": "mongod",
            "procParams": {"ipv6": True, "bind_ip": "127.0.0.1,::1", "port": 27017},
        }
        handle_otel_config(data, self.otel_root)
        self.assert_member(data["procParams"], 27017)

    def test_replica_set(self):
        data = {
            "id": "repl0",
            "members": [
                {"procParams": {"ipv6": True, "port": 27017}, "rsParams": {}},
                {"procParams": {"ipv6": True, "port": 27018}, "rsParams": {}},
            ],
        }
        handle_otel_config(data, self.otel_root)
        for member, port in zip(data["members"], (27017, 27018)):
            self.assert_member(member["procParams"], port)

    def test_sharded_cluster_includes_routers(self):
        data = {
            "id": "shard_cluster_1",
            "shards": [
                {
                    "id": "sh01",
                    "shardParams": {
                        "members": [
                            {
                                "procParams": {
                                    "ipv6": True,
                                    "shardsvr": True,
                                    "port": 27217,
                                }
                            }
                        ]
                    },
                }
            ],
            "routers": [
                {"ipv6": True, "bind_ip": "127.0.0.1,::1", "port": 27017},
            ],
        }
        handle_otel_config(data, self.otel_root)
        self.assert_member(
            data["shards"][0]["shardParams"]["members"][0]["procParams"], 27217
        )
        # Router entries hold proc params directly (no procParams wrapper).
        self.assert_member(data["routers"][0], 27017)

    def test_preserves_existing_set_parameter(self):
        data = {
            "name": "mongod",
            "procParams": {
                "ipv6": True,
                "port": 27017,
                "setParameter": {"enableTestCommands": 1},
            },
        }
        handle_otel_config(data, self.otel_root)
        self.assertEqual(data["procParams"]["setParameter"]["enableTestCommands"], 1)
        self.assert_member(data["procParams"], 27017)

    def test_missing_port_raises(self):
        data = {"name": "mongod", "procParams": {"ipv6": True}}
        with self.assertRaises(ValueError):
            handle_otel_config(data, self.otel_root)

    def test_sampling_json_is_valid_and_pinned(self):
        # defaultSampling carries its own tokenBucketRateLimit per the server
        # IDL (trace_sampling_parameters.idl); it must be raised alongside
        # samplingFactor or internally-initiated spans are still capped at
        # the default 10-burst.
        parsed = json.loads(OTEL_SAMPLING_JSON)
        self.assertEqual(parsed["defaultSampling"]["samplingFactor"], 1.0)
        self.assertEqual(
            parsed["defaultSampling"]["tokenBucketRateLimit"],
            {"refillRate": 1000.0, "maxTokens": 1000},
        )

    def test_external_tracing_json_is_valid_and_pinned(self):
        # openTelemetryExternalTracing is a separate top-level setParameter
        # from openTelemetryTracingSampling on the server (verified against
        # a 9.0 build via getParameter "*"); it is NOT a nested "external"
        # field inside openTelemetryTracingSampling.
        parsed = json.loads(OTEL_EXTERNAL_TRACING_JSON)
        self.assertEqual(
            parsed["tokenBucketRateLimit"],
            {"refillRate": 1000.0, "maxTokens": 1000},
        )


def make_opts(**kwargs):
    defaults = {
        "otel": True,
        "version": "latest",
        "local_atlas": False,
        "mongodb_runner": False,
    }
    defaults.update(kwargs)
    return SimpleNamespace(**defaults)


class TestValidateOtelOpts(unittest.TestCase):
    def setUp(self):
        os.environ.pop("DOCKER_RUNNING", None)

    tearDown = setUp

    def test_noop_when_otel_unset(self):
        # Must not raise even in an otherwise-invalid combination.
        validate_otel_opts(make_opts(otel=False, version="4.2", local_atlas=True))

    def test_latest_and_rapid_allowed(self):
        validate_otel_opts(make_opts(version="latest"))
        validate_otel_opts(make_opts(version="rapid"))

    def test_90_and_above_allowed(self):
        validate_otel_opts(make_opts(version="9.0"))
        validate_otel_opts(make_opts(version="10.1"))

    def test_below_90_rejected(self):
        for version in ("4.2", "8.0", "8.2"):
            with self.assertRaisesRegex(ValueError, "9.0"):
                validate_otel_opts(make_opts(version=version))

    def test_bare_major_version_below_90_rejected(self):
        with self.assertRaisesRegex(ValueError, "9.0"):
            validate_otel_opts(make_opts(version="8"))

    def test_bare_major_version_90_allowed(self):
        validate_otel_opts(make_opts(version="9"))

    def test_v_prefixed_perf_aliases_rejected(self):
        # mongodl resolves these to 6.0.x / 8.0.x servers.
        for version in ("v6.0-perf", "v8.0-perf"):
            with self.assertRaisesRegex(ValueError, "9.0"):
                validate_otel_opts(make_opts(version=version))

    def test_v_prefixed_90_allowed(self):
        validate_otel_opts(make_opts(version="v9.0"))

    def test_docker_running_rejected(self):
        os.environ["DOCKER_RUNNING"] = "true"
        with self.assertRaisesRegex(ValueError, "DOCKER_RUNNING"):
            validate_otel_opts(make_opts())

    def test_local_atlas_rejected(self):
        with self.assertRaisesRegex(ValueError, "local-atlas"):
            validate_otel_opts(make_opts(local_atlas=True))

    def test_mongodb_runner_rejected(self):
        with self.assertRaisesRegex(ValueError, "mongodb-runner"):
            validate_otel_opts(make_opts(mongodb_runner=True))


if __name__ == "__main__":
    unittest.main()
