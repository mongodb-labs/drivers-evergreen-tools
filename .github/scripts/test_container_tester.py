"""Regression tests for the DRIVERS-3712 ECS tag work in container_tester.py.

These run under the bump-version unittest discovery (tests.yml), which has no
boto3 dependency, so boto3 is stubbed before the module under test is imported
by path. The mocked ECS client models the calls remote_create_container makes.
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
        """The service must pass its tags down to the Fargate tasks (DRIVERS-3712)."""
        ecs = self.create(_ecs_client(TAGS))
        __, kwargs = ecs.create_service.call_args
        self.assertEqual(kwargs["propagateTags"], "SERVICE")

    def test_verify_failure_stops_service_and_raises(self):
        """A failed tag check must stop the service before exiting.

        _run_e2e_test's cleanup try/finally only starts after
        remote_create_container returns, so remote_create_container itself has
        to clean up.
        """
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
