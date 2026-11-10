"""Regression tests for the DRIVERS-3712 tag-verification gates (Atlas).

The live red/green Evergreen runs prove the gates' behavior; the live runs
cannot catch a missing or disarmed gate, so these tests pin gate
completeness and wiring structurally: every Atlas-consuming setup gates on
VERIFY_MONGODB_TAGS, the cluster-and-serverless endpoints fetch with
${DEPLOYMENT_TYPE}, create_deployment injects the tags, and this PR's
touched scripts parse.
"""

import subprocess
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
        # These two serve clusters and serverless instances alike; the other
        # gated scripts only create cluster-type deployments, so they hardcode
        # "clusters" in the endpoint.
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

    def test_touched_scripts_parse(self):
        for relpath in (
            ".evergreen/verify-tags.sh",
            ".evergreen/atlas/atlas-utils.sh",
            ".evergreen/atlas/setup-atlas-cluster.sh",
            ".evergreen/auth_oidc/setup.sh",
            ".evergreen/auth_oidc/gcp/setup.sh",
            ".evergreen/auth_oidc/k8s/setup.sh",
            ".evergreen/auth_oidc/azure_func/setup.sh",
        ):
            with self.subTest(script=relpath):
                subprocess.run(
                    ["bash", "-n", str(REPO / relpath)], check=True, timeout=30
                )


if __name__ == "__main__":
    unittest.main()
