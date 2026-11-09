"""Regression tests for the DRIVERS-3712 tag-verification gates (Azure assets).

The Azure create paths tag every resource they create and verify with
`VERIFY_MONGODB_TAGS` set; the janitor reaps orphaned per-VM vnets only.
Behavioral coverage of the gates lives in the red/green Evergreen runs;
these tests are structural plus the janitor's orphan logic.
"""

import datetime
import importlib.util
import os
import stat
import subprocess
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]

# Mock `curl` for whatismyip.akamai.com: CURL_FAIL_FIRST=1 fails the first
# call, CURL_FAIL_ALWAYS=1 every call, CURL_PARTIAL_FIRST=1 writes a partial
# IP before failing the first call.
CURL_MOCK = r"""#!/usr/bin/env bash
set -u
STATE_DIR=${STATE_DIR:-/tmp}
if [ -n "${CURL_FAIL_ALWAYS:-}" ]; then
  echo "curl: (56) Recv failure" 1>&2
  exit 56
fi
touch "$STATE_DIR/curl_calls"
calls=$(wc -l < "$STATE_DIR/curl_calls")
echo x >> "$STATE_DIR/curl_calls"
if [ "$calls" = 0 ]; then
  if [ -n "${CURL_PARTIAL_FIRST:-}" ]; then
    printf '1.2.3.'
    echo "curl: (56) Recv failure" 1>&2
    exit 56
  fi
  if [ -n "${CURL_FAIL_FIRST:-}" ]; then
    echo "curl: (56) Recv failure" 1>&2
    exit 56
  fi
fi
echo 1.2.3.4
"""

# Mock `az` for set-ssh-ip.sh: log every call, answer the public-IP lookup.
AZ_SSH_MOCK = r"""#!/usr/bin/env bash
echo "az $*" >> "${STATE_DIR:?}/calls.log"
if [[ "$*" == *publicIps* ]]; then echo "1.2.3.4"; fi
"""


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


class SshIpTest(unittest.TestCase):
    """set-ssh-ip.sh's external-IP lookup must survive a transient failure
    instead of aborting the task with curl's exit 56."""

    SCRIPT = REPO / ".evergreen/csfle/azurekms/set-ssh-ip.sh"

    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)
        self.bin = self.state_path / "bin"
        self.bin.mkdir()
        self.write_executable("az", AZ_SSH_MOCK)
        self.write_executable("curl", CURL_MOCK)
        self.write_executable("ssh", "#!/usr/bin/env bash\nexit 0\n")

    def tearDown(self):
        self.state.cleanup()

    def write_executable(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def run_set_ssh_ip(self, extra_env):
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["STATE_DIR"] = str(self.state_path)
        env["DRIVERS_TOOLS"] = str(REPO)
        env["AZUREKMS_RESOURCEGROUP"] = "RG"
        env["AZUREKMS_VMNAME"] = "vmname-test-1"
        env["AZUREKMS_PRIVATEKEYPATH"] = "/dev/null"
        env.update(extra_env)
        return subprocess.run(
            ["bash", str(self.SCRIPT)],
            env=env,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )

    def calls(self):
        log = self.state_path / "calls.log"
        return log.read_text() if log.exists() else ""

    def test_transient_ip_lookup_failure_is_retried(self):
        """A failed whatismyip call is retried; the IP stays clean."""
        proc = self.run_set_ssh_ip({"CURL_FAIL_FIRST": "1"})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("attempt n. 2", proc.stderr)
        self.assertNotIn("retry_with_backoff:", proc.stdout)

    def test_partial_response_is_discarded(self):
        """A partial response from a failed lookup must not reach the rule."""
        proc = self.run_set_ssh_ip({"CURL_PARTIAL_FIRST": "1"})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("attempt n. 2", proc.stderr)
        self.assertIn("--source-address-prefixes 1.2.3.4", self.calls())
        self.assertNotIn("1.2.3.1.2.3.4", self.calls())

    def test_persistent_ip_lookup_failure_fails_the_script(self):
        proc = self.run_set_ssh_ip({"CURL_FAIL_ALWAYS": "1"})
        self.assertEqual(proc.returncode, 56, proc.stdout + proc.stderr)


class RetryHelperTest(unittest.TestCase):
    """retry-with-backoff.sh runs inside command substitutions: a failed
    attempt's partial stdout would corrupt the next attempt's response."""

    SCRIPT = REPO / ".evergreen/retry-with-backoff.sh"

    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)

    def tearDown(self):
        self.state.cleanup()

    def run_helper(self, command, extra_env=None):
        env = dict(os.environ)
        env["STATE_DIR"] = str(self.state_path)
        env.update(extra_env or {})
        return subprocess.run(
            ["bash", str(self.SCRIPT), "bash", "-c", command],
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )

    def test_partial_stdout_of_failed_attempt_is_discarded(self):
        """Only the successful attempt's output reaches stdout."""
        proc = self.run_helper(
            'if [ -f "$STATE_DIR/marker" ]; then echo "1.2.3.4"; '
            'else touch "$STATE_DIR/marker"; printf "1.2.3."; exit 56; fi'
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("attempt n. 2", proc.stderr)
        self.assertEqual(proc.stdout, "1.2.3.4")

    def test_success_after_partial_failure_keeps_full_response(self):
        """The successful attempt's output is emitted exactly once."""
        proc = self.run_helper('touch "$STATE_DIR/marker"; echo "1.2.3.4"')
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertEqual(proc.stdout, "1.2.3.4")

    def test_exhaustion_returns_the_command_status(self):
        proc = self.run_helper("exit 7", {"ATTEMPTS": "2"})
        self.assertEqual(proc.returncode, 7)


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
        self.assertEqual(text.count("verify_cloud_tags"), 6)
        self.assertIn("Tag verification failed", text)

    def test_verify_aks_setup_checks_every_resource(self):
        """The resource group, cluster, node resource group, node pools, and
        identity are all verified; the identity name is required."""
        text = (REPO / ".evergreen/k8s/aks/verify-aks-setup.sh").read_text()
        self.assertEqual(text.count("verify_cloud_tags"), 5)
        self.assertIn("AKS_USER_ASSIGNED_IDENTITY_NAME:?", text)

    def test_setup_cluster_tags_and_verifies(self):
        """The group, cluster, and identity get --tags; the node resources
        get az tag create/nodepool update; the gate runs at the end."""
        text = (REPO / ".evergreen/k8s/aks/setup-cluster.sh").read_text()
        self.assertEqual(text.count('--tags "mongodb-owner='), 5)
        self.assertIn("az tag create", text)
        self.assertIn("az aks nodepool update", text)
        self.assertIn("verify_aks_tags", text)
        self.assertIn("az group list", text)

    def test_delete_vm_deletes_the_vnet(self):
        text = (REPO / ".evergreen/csfle/azurekms/delete-vm.sh").read_text()
        self.assertIn("vnet delete", text)

    def test_pod_flow_and_config_arm_the_gate(self):
        """The pod flow runs the gate when VERIFY_MONGODB_TAGS is set, and
        config.yml sets the flag."""
        setup = (REPO / ".evergreen/k8s/aks/setup.sh").read_text()
        self.assertIn("VERIFY_MONGODB_TAGS", setup)
        self.assertIn("verify_aks_tags", setup)
        config = (REPO / ".evergreen/config.yml").read_text()
        self.assertIn("export VERIFY_MONGODB_TAGS=1", config)

    def test_ip_lookups_retry(self):
        for relpath in (
            ".evergreen/csfle/azurekms/create-vm.sh",
            ".evergreen/csfle/azurekms/set-ssh-ip.sh",
        ):
            text = (REPO / relpath).read_text()
            with self.subTest(script=relpath):
                self.assertIn("retry-with-backoff.sh", text)

    def test_smoke_test_harvests_quoted_env(self):
        text = (REPO / ".evergreen/k8s/aks/smoke-test.sh").read_text()
        self.assertIn("export -p", text)
        self.assertIn("VERIFY_MONGODB_TAGS=1", text)


if __name__ == "__main__":
    unittest.main()
