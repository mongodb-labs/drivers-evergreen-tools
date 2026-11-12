"""Regression tests for the DRIVERS-3712 tag-verification gates (Atlas).

The live red/green Evergreen runs prove the gates' behavior; the live runs
cannot catch a missing or disarmed gate, so these tests pin gate
completeness and wiring structurally.
"""

import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

ATLAS_UTILS = ".evergreen/atlas/atlas-utils.sh"


class AtlasGatePresenceTest(unittest.TestCase):
    """The Atlas-consuming scripts must verify tags through the shared
    verify_deployment_tags helper, which carries the gate itself."""

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
                self.assertIn("verify_deployment_tags", text)

    def test_shared_helper_gates_and_verifies(self):
        # The gate lives once, in the shared helper: it arms on
        # VERIFY_MONGODB_TAGS, sources verify-tags.sh from this checkout, and
        # checks the deployment's tags array with verify_atlas_tags.
        text = (REPO / ATLAS_UTILS).read_text()
        self.assertIn("VERIFY_MONGODB_TAGS", text)
        self.assertIn("verify-tags.sh", text)
        self.assertIn("verify_atlas_tags", text)

    def test_endpoints_use_deployment_type(self):
        # The shared helper serves serverless instances too; hardcoding
        # "clusters" would 404 the check for a serverless deployment.
        text = (REPO / ATLAS_UTILS).read_text()
        self.assertIn("${DEPLOYMENT_TYPE", text)

    def test_create_deployment_injects_tags(self):
        text = (REPO / ATLAS_UTILS).read_text()
        self.assertIn('data["tags"]', text)
        self.assertIn("mongodb-owner", text)
        self.assertIn("mongodb-env", text)


if __name__ == "__main__":
    unittest.main()
