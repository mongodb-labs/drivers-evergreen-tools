"""Regression tests for the DRIVERS-3712 tag-verification gates (Azure assets).

The live red/green Evergreen runs and the smoke test prove the gates'
behavior; the live runs cannot catch a missing or disarmed gate, so these
tests pin gate completeness and wiring structurally, plus the janitor's
orphan-vnet logic (no CI run exercises it, and it deletes real resources)
and the IP-echo retry flags against a local HTTP server.
"""

import datetime
import importlib.util
import os
import subprocess
import sys
import threading
import time
import types
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]


class JanitorTest(unittest.TestCase):
    """The janitor's orphaned-vnet logic, with the Azure SDK stubbed.

    Both clients are mocked, so the scan runs without touching Azure.
    """

    SCRIPT = REPO / ".evergreen/csfle/azurekms/delete_old_azure_resources.py"

    def setUp(self):
        for name, attrs in {
            "azure": {},
            "azure.identity": {"DefaultAzureCredential": mock.MagicMock()},
            "azure.mgmt": {},
            "azure.mgmt.compute": {"ComputeManagementClient": mock.MagicMock()},
            "azure.mgmt.network": {"NetworkManagementClient": mock.MagicMock()},
        }.items():
            if name not in sys.modules:
                module = types.ModuleType(name)
                for attr, value in attrs.items():
                    setattr(module, attr, value)
                sys.modules[name] = module

        spec = importlib.util.spec_from_file_location(
            "delete_old_azure_resources_under_test", self.SCRIPT
        )
        self.janitor = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.janitor)

        self.now = datetime.datetime.now(tz=datetime.timezone.utc)
        self.old_vm = types.SimpleNamespace(
            name="vmname-old-123", time_created=self.now - datetime.timedelta(hours=3)
        )
        self.cm = mock.MagicMock(name="compute_client")
        self.cm.virtual_machines.list.return_value = [self.old_vm]
        self.nm = mock.MagicMock(name="network_client")
        self.nm.network_security_groups.list.return_value = []
        self.nm.public_ip_addresses.list.return_value = []
        self.nm.virtual_networks.list.return_value = [
            types.SimpleNamespace(
                name="vmname-old-123-VNET",
                tags={
                    "created-at": str(
                        int((self.now - datetime.timedelta(hours=3)).timestamp())
                    )
                },
            ),
            types.SimpleNamespace(
                name="vmname-gone-456-VNET",
                tags={
                    "created-at": str(
                        int((self.now - datetime.timedelta(hours=3)).timestamp())
                    )
                },
            ),
        ]

    def run_main(self, dry_run=False):
        argv = ["delete_old_azure_resources.py"] + (["--dry-run"] if dry_run else [])
        with (
            mock.patch("sys.argv", argv),
            mock.patch.dict(
                os.environ,
                {"AZURE_RESOURCE_GROUP": "rg", "AZURE_SUBSCRIPTION_ID": "sub"},
            ),
            mock.patch.object(
                self.janitor, "ComputeManagementClient", return_value=self.cm
            ),
            mock.patch.object(
                self.janitor, "NetworkManagementClient", return_value=self.nm
            ),
        ):
            self.janitor.main()

    def test_orphaned_vnets_are_deleted(self):
        """VNets whose VM is gone are deleted; live VMs' vnets are kept."""
        self.run_main()
        deleted = [
            call.args for call in self.nm.virtual_networks.begin_delete.call_args_list
        ]
        self.assertIn(("rg", "vmname-gone-456-VNET"), deleted)
        self.assertNotIn(("rg", "vmname-old-123-VNET"), deleted)

    def test_dry_run_keeps_orphaned_vnets(self):
        self.run_main(dry_run=True)
        self.nm.virtual_networks.begin_delete.assert_not_called()

    def test_fresh_vnets_are_skipped(self):
        """A vnet younger than the grace period is never deleted.

        The vnet is created before its VM, so a just-created vnet looks
        orphaned mid-provisioning.
        """
        self.nm.virtual_networks.list.return_value = [
            types.SimpleNamespace(
                name="vmname-gone-456-VNET",
                tags={"created-at": str(int(self.now.timestamp()))},
            ),
        ]
        self.run_main()
        self.nm.virtual_networks.begin_delete.assert_not_called()

    def test_vnet_reclaims_its_vm_before_delete(self):
        """A fresh VM listing runs before deletion: a vnet whose VM appeared
        since the snapshot is skipped."""
        self.nm.virtual_networks.list.return_value = [
            types.SimpleNamespace(
                name="vmname-new-789-VNET",
                tags={
                    "created-at": str(
                        int((self.now - datetime.timedelta(hours=3)).timestamp())
                    )
                },
            ),
        ]
        # list() call order: old-VM scan, VM-name snapshot, fresh re-check.
        self.cm.virtual_machines.list.side_effect = [
            [self.old_vm],
            [self.old_vm],
            [self.old_vm, types.SimpleNamespace(name="vmname-new-789")],
        ]
        self.run_main()
        self.nm.virtual_networks.begin_delete.assert_not_called()

    def test_non_vm_vnets_are_never_deleted(self):
        """Only per-VM vnets (<vmname>-VNET) are deletion candidates.

        create-vm.sh owns that naming convention; any other vnet in the
        resource group, such as shared infrastructure, must be ignored even
        with no created-at tag.
        """
        self.nm.virtual_networks.list.return_value = [
            types.SimpleNamespace(name="shared-infrastructure", tags=None),
        ]
        self.run_main()
        self.nm.virtual_networks.begin_delete.assert_not_called()


class AzureParseTest(unittest.TestCase):
    """This PR's files must parse, gate on VERIFY_MONGODB_TAGS, and verify
    every resource they create."""

    SHELL_SCRIPTS = (
        ".evergreen/verify-tags.sh",
        ".evergreen/csfle/azurekms/create-vm.sh",
        ".evergreen/csfle/azurekms/delete-vm.sh",
        ".evergreen/k8s/aks/setup-cluster.sh",
        ".evergreen/k8s/aks/verify-aks-setup.sh",
        ".evergreen/k8s/aks/smoke-test.sh",
    )

    def test_scripts_parse(self):
        for relpath in self.SHELL_SCRIPTS:
            with self.subTest(script=relpath):
                subprocess.run(
                    ["bash", "-n", str(REPO / relpath)], check=True, timeout=30
                )

    def test_gates_present(self):
        # Teardown (delete-vm.sh) creates nothing to verify; only the create
        # paths carry gates.
        for relpath in (
            ".evergreen/csfle/azurekms/create-vm.sh",
            ".evergreen/k8s/aks/setup-cluster.sh",
        ):
            text = (REPO / relpath).read_text()
            with self.subTest(script=relpath):
                self.assertIn("VERIFY_MONGODB_TAGS", text)

    def test_create_vm_verifies_every_created_resource(self):
        """The VM, OS disk, NIC, public IP, NSG, and vnet are all verified,
        and a verification failure cleans the VM up."""
        text = (REPO / ".evergreen/csfle/azurekms/create-vm.sh").read_text()
        self.assertEqual(text.count('verify_cloud_tags "'), 6)
        self.assertIn("Tag verification failed", text)

    def test_verify_aks_setup_checks_every_resource(self):
        """The resource group, cluster, node resource group, node pools, and
        identity are all verified; the identity name is required."""
        text = (REPO / ".evergreen/k8s/aks/verify-aks-setup.sh").read_text()
        self.assertEqual(text.count("verify_cloud_tags"), 5)
        self.assertIn("AKS_USER_ASSIGNED_IDENTITY_NAME:?", text)

    def test_setup_cluster_tags_and_verifies(self):
        """The create path must keep its tag writes, the group-list check,
        and the end-of-setup gate."""
        text = (REPO / ".evergreen/k8s/aks/setup-cluster.sh").read_text()
        self.assertEqual(text.count('--tags "mongodb-owner='), 5)
        self.assertIn("az tag update", text)
        self.assertIn("verify_aks_tags", text)
        self.assertIn("az group list", text)

    def test_pod_flow_and_config_arm_the_gate(self):
        """The pod flow runs the gate when VERIFY_MONGODB_TAGS is set, and
        config.yml sets the flag."""
        setup = (REPO / ".evergreen/k8s/aks/setup.sh").read_text()
        self.assertIn("VERIFY_MONGODB_TAGS", setup)
        self.assertIn("verify_aks_tags", setup)
        config = (REPO / ".evergreen/config.yml").read_text()
        self.assertIn("export VERIFY_MONGODB_TAGS=1", config)

    def test_ip_echo_curl_fails_fast(self):
        """The IP-echo curl calls must fail on HTTP errors and hung
        connections, so retry_with_backoff retries them: bare `curl -s`
        exits 0 on an HTTP error page and hangs forever without a time
        limit, feeding garbage into the NSG source prefix."""
        for relpath in (
            ".evergreen/csfle/azurekms/create-vm.sh",
            ".evergreen/csfle/azurekms/set-ssh-ip.sh",
        ):
            text = (REPO / relpath).read_text()
            with self.subTest(script=relpath):
                lines = [
                    line
                    for line in text.splitlines()
                    if "whatismyip.akamai.com" in line
                ]
                self.assertEqual(len(lines), 1, text)
                for flag in ("--fail", "--max-time"):
                    self.assertIn(flag, lines[0])

    def test_mc_group_tagging_merges(self):
        """The AKS-managed MC_ group is tagged with a merge, not a replace:
        `az tag create` rewrites the resource's whole tag set and would drop
        any tags AKS puts on the group itself."""
        readme = (REPO / ".evergreen/k8s/aks/README.md").read_text()
        setup = (REPO / ".evergreen/k8s/aks/setup-cluster.sh").read_text()
        for text in (readme, setup):
            self.assertIn("az tag update", text)
            self.assertIn("--operation Merge", text)
        self.assertNotIn("az tag create --resource-id", setup)


class RetryCurlTest(unittest.TestCase):
    """The retry helper's curl flags behave as the IP-echo callers need.

    Runs curl against a local HTTP server, so it needs no network access.
    """

    SCRIPT = REPO / ".evergreen/retry-with-backoff.sh"

    def setUp(self):
        server = self
        self.hits = 0

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                server.hits += 1
                if server.hang:
                    time.sleep(server.hang)
                if server.hits <= server.fail_times:
                    self.send_response(500)
                    self.end_headers()
                    self.wfile.write(b"Service Unavailable")
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"192.0.2.1")

            def log_message(self, *args):  # keep the test output clean
                pass

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.fail_times = 0
        self.hang = 0

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    def run_retry(self, attempts, max_time):
        return subprocess.run(
            [
                "bash",
                str(self.SCRIPT),
                "curl",
                "-sS",
                "--fail",
                "--max-time",
                str(max_time),
                f"http://127.0.0.1:{self.httpd.server_address[1]}/",
            ],
            capture_output=True,
            text=True,
            timeout=120,
            env={**os.environ, "ATTEMPTS": str(attempts), "TIMEOUT": "0"},
            check=False,
        )

    def test_http_error_is_retried_and_body_returned(self):
        """A 500 fails the attempt; a later 200 returns the IP body."""
        self.fail_times = 2
        result = self.run_retry(attempts=3, max_time=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "192.0.2.1")
        self.assertEqual(self.hits, 3)

    def test_persistent_http_error_fails(self):
        """A server that only 500s fails the whole command instead of
        returning the error page as a successful IP."""
        self.fail_times = 999
        result = self.run_retry(attempts=3, max_time=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.hits, 3)

    def test_hung_connection_times_out_and_retries(self):
        """A connection that never responds is cut off by --max-time and
        retried, rather than hanging the task until Evergreen kills it."""
        self.hang = 30  # each curl attempt is cut off at max_time
        result = self.run_retry(attempts=2, max_time=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.hits, 2)


if __name__ == "__main__":
    unittest.main()
