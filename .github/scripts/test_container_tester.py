"""Regression tests for the DRIVERS-3712 ECS tag work in container_tester.py.

Runs in the static job of tests.yml (unittest discovery); boto3 is stubbed
so no dependency is needed.
"""

import importlib.util
import os
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

# Stub boto3 (imported at module level by container_tester.py) before import.
if "boto3" not in sys.modules:
    _boto3_stub = types.ModuleType("boto3")
    _boto3_stub.client = mock.MagicMock(name="boto3.client")
    sys.modules["boto3"] = _boto3_stub

_CONTAINER_TESTER_PATH = (
    Path(__file__).resolve().parents[2]
    / ".evergreen"
    / "auth_aws"
    / "lib"
    / "container_tester.py"
)
_spec = importlib.util.spec_from_file_location(
    "container_tester_under_test", _CONTAINER_TESTER_PATH
)
container_tester = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(container_tester)

CLUSTER = "arn:aws:ecs:us-east-2:579766882180:cluster/tf-mcb-ecs-cluster"
SERVICE = "script-test"
TAGS = [
    {"key": "mongodb-owner", "value": "someone@mongodb.com"},
    {"key": "mongodb-env", "value": "dev"},
]


def _ecs_client(tags):
    """Build a MagicMock ECS client modeling the calls remote_create_container makes."""
    ecs = mock.MagicMock(name="ecs_client")
    ecs.create_service.return_value = {"service": {"serviceArn": "arn:service"}}
    ecs.describe_services.return_value = {"services": [{"tags": tags}]}
    return ecs


@mock.patch.dict(os.environ, {"VERIFY_MONGODB_TAGS": "1"})
class TestRemoteCreateContainer(unittest.TestCase):
    def create(self, ecs):
        """Call remote_create_container with the given mocked ECS client."""
        with mock.patch.object(container_tester, "boto3") as boto3_mock:
            boto3_mock.client.return_value = ecs
            container_tester.remote_create_container(
                CLUSTER, "task-def", SERVICE, ["subnet"], "sg"
            )
        return ecs

    def test_create_service_propagates_tags_to_tasks(self):
        """The service must pass its tags down to the Fargate tasks."""
        ecs = self.create(_ecs_client(TAGS))
        __, kwargs = ecs.create_service.call_args
        self.assertEqual(kwargs["propagateTags"], "SERVICE")

    def test_verify_failure_stops_service_and_raises(self):
        """A failed tag check must stop the service before exiting."""
        ecs = _ecs_client([{"key": "unrelated", "value": "x"}])
        with mock.patch.object(container_tester, "remote_stop_container") as stop:
            with self.assertRaises(SystemExit):
                self.create(ecs)
        stop.assert_called_once_with(CLUSTER, SERVICE)

    def test_verify_failure_raises_when_stop_fails(self):
        """A cleanup error must not mask the verification failure."""
        ecs = _ecs_client([])
        with mock.patch.object(
            container_tester,
            "remote_stop_container",
            side_effect=RuntimeError("aws down"),
        ):
            with self.assertRaises(SystemExit):
                self.create(ecs)

    def test_verify_read_failure_stops_service_and_reraises(self):
        """A failed tag read must stop the service and re-raise the error."""
        ecs = _ecs_client(TAGS)
        ecs.describe_services.side_effect = RuntimeError("api down")
        with mock.patch.object(container_tester, "remote_stop_container") as stop:
            with self.assertRaises(RuntimeError):
                self.create(ecs)
        stop.assert_called_once_with(CLUSTER, SERVICE)

    def test_verify_empty_services_stops_service(self):
        """An empty describe response must stop the service and raise."""
        ecs = _ecs_client(TAGS)
        ecs.describe_services.return_value = {"services": []}
        with mock.patch.object(container_tester, "remote_stop_container") as stop:
            with self.assertRaises(IndexError):
                self.create(ecs)
        stop.assert_called_once_with(CLUSTER, SERVICE)

    def test_empty_tag_overrides_fall_back_to_defaults(self):
        """Empty overrides must fall back to the defaults, like ${VAR:-default}."""
        ecs = _ecs_client(TAGS)
        with mock.patch.dict(
            os.environ, {"MONGODB_OWNER_TAG": "", "MONGODB_ENV_TAG": ""}
        ):
            with mock.patch.object(container_tester, "boto3") as boto3_mock:
                boto3_mock.client.return_value = ecs
                container_tester.remote_create_container(
                    CLUSTER, "task-def", SERVICE, ["subnet"], "sg"
                )
        __, kwargs = ecs.create_service.call_args
        values = {t["key"]: t["value"] for t in kwargs["tags"]}
        self.assertEqual(
            values,
            {
                "mongodb-owner": "client-libraries-managers@mongodb.com",
                "mongodb-env": "dev",
            },
        )

    def test_verify_success_does_not_stop_service(self):
        """Tagged services are neither raised on nor stopped."""
        ecs = _ecs_client(TAGS)
        with mock.patch.object(container_tester, "remote_stop_container") as stop:
            self.create(ecs)
        stop.assert_not_called()

    def test_verify_skipped_when_unset(self):
        """No verification calls at all when the gate is off."""
        ecs = _ecs_client([])
        with mock.patch.dict(os.environ, {"VERIFY_MONGODB_TAGS": ""}):
            with mock.patch.object(container_tester, "remote_stop_container") as stop:
                self.create(ecs)
        ecs.describe_services.assert_not_called()
        stop.assert_not_called()


if __name__ == "__main__":
    unittest.main()
