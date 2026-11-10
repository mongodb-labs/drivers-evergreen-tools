"""Regression tests for the DRIVERS-3712 tag-verification gates (Atlas).

The live red/green Evergreen runs prove the gates' behavior; the live runs
cannot catch a missing or disarmed gate, so these tests pin gate
completeness and wiring structurally.
"""

import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


class AtlasGatePresenceTest(unittest.TestCase):
    """The Atlas-consuming scripts must gate on VERIFY_MONGODB_TAGS."""

    GATED_SCRIPTS = (
        ".evergreen/atlas/setup-atlas-cluster.sh",
        ".evergreen/auth_oidc/setup.sh",
        ".evergreen/auth_oidc/gcp/setup.sh",
        ".evergreen/auth_oidc/k8s/setup.sh",
        ".evergreen/auth_oidc/azure_func/setup.sh",
    )

    def test_gates_present(self):
        for relpath in self.GATED_SCRIPTS:
            text = (REPO / relpath).read_text()
            with self.subTest(script=relpath):
                self.assertIn("VERIFY_MONGODB_TAGS", text)
                self.assertIn("verify_atlas_tags", text)

    def test_endpoints_use_deployment_type(self):
        # These two also serve serverless instances; the rest only create
        # clusters.
        for relpath in (
            ".evergreen/atlas/setup-atlas-cluster.sh",
            ".evergreen/auth_oidc/azure_func/setup.sh",
        ):
            text = (REPO / relpath).read_text()
            with self.subTest(script=relpath):
                self.assertIn("${DEPLOYMENT_TYPE", text)

    def test_create_deployment_injects_tags(self):
        text = (REPO / ".evergreen/atlas/atlas-utils.sh").read_text()
        self.assertIn('data["tags"]', text)
        self.assertIn("mongodb-owner", text)
        self.assertIn("mongodb-env", text)


if __name__ == "__main__":
    unittest.main()
