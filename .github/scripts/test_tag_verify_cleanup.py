"""Regression tests for the DRIVERS-3712 tag-verification gates (Azure assets).

verify-tags.sh exits the sourcing shell on failure, and callers persist
teardown metadata only after the create scripts return, so the create scripts
must clean up what they created when verification or tagging fails. The
janitor must not delete fresh vnets mid-provisioning. These tests drive the
real scripts through mocked `az`/`curl` binaries.
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

AZ_MOCK = r"""#!/usr/bin/env bash
set -u
STATE_DIR=${STATE_DIR:?}
echo "az $*" >> "$STATE_DIR/calls.log"

flag_values () {
  local flag=$1; shift
  local collecting=0 out=()
  for a in "$@"; do
    if [ "$a" = "$flag" ]; then collecting=1; continue; fi
    if [[ "$a" == --* ]]; then collecting=0; fi
    if [ $collecting = 1 ]; then out+=("$a"); fi
  done
  echo "${out[*]}"
}

tags_json () {
  local out="{" first=1 pair key val
  for pair in $*; do
    key=${pair%%=*}; val=${pair#*=}
    if [ $first = 1 ]; then first=0; else out="$out,"; fi
    out="$out\"$key\": \"$val\""
  done
  echo "$out}"
}

persist_tags () {
  local dest=$1; shift
  if [ -n "${DROP_TAGS:-}" ]; then
    echo '{}' > "$dest"
  else
    tags_json "$(flag_values --tags "$@")" > "$dest"
  fi
}

# Record tags for a resource id in $STATE_DIR/resource_tags.txt, one
# "id|json" line per resource, replacing any line for the same id.
store_resource_tags () {
  local rid=$1 json=$2
  touch "$STATE_DIR/resource_tags.txt"
  grep -v "^${rid}|" "$STATE_DIR/resource_tags.txt" > "$STATE_DIR/resource_tags.tmp" || true
  mv "$STATE_DIR/resource_tags.tmp" "$STATE_DIR/resource_tags.txt"
  echo "${rid}|${json}" >> "$STATE_DIR/resource_tags.txt"
}

show_resource_tags () {
  local rid=$1
  grep "^${rid}|" "$STATE_DIR/resource_tags.txt" | cut -d'|' -f2-
}

VNET_ID="/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"

cmd=$1; shift
case "$cmd" in
  vm)
    sub=$1; shift
    case "$sub" in
      create)
        if [ -n "${FAIL_VM_CREATE:-}" ]; then
          echo "az vm create: simulated failure" 1>&2
          exit 1
        fi
        persist_tags "$STATE_DIR/vm_tags.json" "$@"
        echo '{"id": "vm-id"}'
        ;;
      show)
        if [[ "$*" == *storageProfile* ]]; then
          echo "/subscriptions/sub/disks/osdisk"
        elif [[ "$*" == *networkProfile* ]]; then
          echo "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/nic"
        else
          cat "$STATE_DIR/vm_tags.json"
        fi
        ;;
      delete) echo "vm-delete" >> "$STATE_DIR/cleanup.log" ;;
      auto-shutdown) : ;;
      resize) : ;;
      *) : ;;
    esac
    ;;
  tag)
    # az tag create --resource-id X --tags "k=v" "k=v"
    local_rid=""
    prev=""
    for a in "$@"; do
      if [ "$prev" = "--resource-id" ]; then local_rid=$a; fi
      prev=$a
    done
    if [ -n "${FAIL_DISK_TAG:-}" ] && [[ "$local_rid" == *disks* ]]; then
      echo "az tag create: simulated failure" 1>&2
      exit 1
    fi
    if [ -n "${FAIL_TAG_TARGET:-}" ] && [[ "$local_rid" == *"${FAIL_TAG_TARGET}"* ]]; then
      echo "az tag create: simulated failure for ${local_rid}" 1>&2
      exit 1
    fi
    persist_tags "$STATE_DIR/disk_tags.json" "$@"
    store_resource_tags "$local_rid" "$(tags_json "$(flag_values --tags "$@")")"
    echo '{}'
    ;;
  disk)
    if [ "${1:-}" = "show" ]; then
      cat "$STATE_DIR/disk_tags.json"
    fi
    ;;
  resource)
    # az resource show --ids X --query tags
    if [ "${1:-}" = "show" ]; then
      rid=""; prev=""
      for a in "$@"; do
        if [ "$prev" = "--ids" ]; then rid=$a; fi
        prev=$a
      done
      show_resource_tags "$rid"
    fi
    ;;
  public-ip)
    # `public-ip` is not a top-level Azure CLI command group; model the real
    # CLI by failing so the production script cannot rely on it.
    echo "az: 'public-ip' is not a command group; use 'az network public-ip'" 1>&2
    exit 1
    ;;
  network)
    sub=$1; shift
    case "$sub" in
      vnet)
        if [ "${1:-}" = "create" ]; then
          echo "vnet-create" >> "$STATE_DIR/calls.log"
          if [ -n "${DROP_TAGS:-}" ]; then
            store_resource_tags "$VNET_ID" "{}"
          else
            store_resource_tags "$VNET_ID" "$(tags_json "$(flag_values --tags "$@")")"
          fi
          echo '{}'
        elif [ "${1:-}" = "show" ]; then
          show_resource_tags "$VNET_ID"
        elif [ "${1:-}" = "delete" ]; then
          echo "vnet-delete" >> "$STATE_DIR/cleanup.log"
        fi
        ;;
      nsg)
        if [ "${1:-}" = "rule" ] && [ "${2:-}" = "create" ]; then
          echo '{}'
        elif [ "${1:-}" = "delete" ]; then
          echo "nsg-delete" >> "$STATE_DIR/cleanup.log"
        elif [ "${1:-}" = "show" ]; then
          echo "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg"
        fi
        ;;
  public-ip)
    if [ "${1:-}" = "delete" ]; then
      echo "public-ip-delete" >> "$STATE_DIR/cleanup.log"
    elif [ "${1:-}" = "show" ]; then
      echo "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/ip"
    fi
    ;;
  nic)
    if [ "${1:-}" = "delete" ]; then
      # The CLI's default NIC name is <vmname>VMNic; model the 404 any other
      # name gets (swallowed by || true) so the test catches a wrong name.
      nic_name=""; prev=""
      for a in "$@"; do
        if [ "$prev" = "--name" ]; then nic_name=$a; fi
        prev=$a
      done
      if [[ "$nic_name" == *VMNic ]]; then
        echo "nic-delete" >> "$STATE_DIR/cleanup.log"
      else
        echo "az network nic delete: ResourceNotFound: ${nic_name}" 1>&2
        exit 3
      fi
    fi
    ;;
      *) echo '{}' ;;
    esac
    ;;
  *) echo '{}' ;;
esac
"""

# Mock `gcloud`: models the subset of the CLI that gcpkms/create-instance.sh
# uses. DROP_INSTANCE_LABELS / DROP_DISK_LABELS simulate lost labels.

CURL_MOCK = "#!/usr/bin/env bash\necho 1.2.3.4\n"

CREATE_VM_ENV = {
    "AZUREKMS_VMNAME_PREFIX": "PREFIX",
    "AZUREKMS_RESOURCEGROUP": "RG",
    "AZUREKMS_IMAGE": "IMG",
    "AZUREKMS_PUBLICKEYPATH": "/dev/null",
}


class TagVerifyCleanupTest(unittest.TestCase):
    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)
        self.bin = self.state_path / "bin"
        self.bin.mkdir()
        self.write_executable("az", AZ_MOCK)
        self.write_executable("curl", CURL_MOCK)
        self.cleanup_log = self.state_path / "cleanup.log"

    def tearDown(self):
        self.state.cleanup()

    def write_executable(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def run_create_script(self, relpath, extra_env):
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["STATE_DIR"] = str(self.state_path)
        env["VERIFY_MONGODB_TAGS"] = "1"
        env["DRIVERS_TOOLS"] = str(REPO)
        env.update(extra_env)
        return subprocess.run(
            ["bash", str(REPO / relpath)],
            env=env,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )

    def cleanup_calls(self):
        if not self.cleanup_log.exists():
            return []
        return self.cleanup_log.read_text().split()

    def resource_tags(self, resource):
        """Return the stored tag line for a resource-type substring."""
        path = self.state_path / "resource_tags.txt"
        if not path.exists():
            return ""
        lines = path.read_text().splitlines()
        return next((ln for ln in lines if resource in ln), "")

    def calls(self):
        log = self.state_path / "calls.log"
        return log.read_text() if log.exists() else ""

    def test_azure_vm_deleted_when_verification_fails(self):
        """A failed tag check must delete the VM, public IP, NSG, and vnet."""
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh",
            {**CREATE_VM_ENV, "DROP_TAGS": "1"},
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("vm-delete", self.cleanup_calls())
        self.assertIn("public-ip-delete", self.cleanup_calls())
        self.assertIn("nsg-delete", self.cleanup_calls())
        self.assertIn("vnet-delete", self.cleanup_calls())

    def test_azure_vnet_created_and_tagged_when_tagged(self):
        """The VM must use an explicitly created, tagged vnet.

        az vm create with no existing network implicitly creates an untagged
        one.
        """
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh", CREATE_VM_ENV
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        vnet_lines = [ln for ln in self.calls().splitlines() if "vnet create" in ln]
        self.assertTrue(vnet_lines, "no vnet create call")
        self.assertIn("--tags", vnet_lines[0])
        vm_lines = [ln for ln in self.calls().splitlines() if "vm create" in ln]
        self.assertIn("--vnet-name", vm_lines[0])
        self.assertIn("mongodb-owner", self.resource_tags("virtualNetworks"))

    def test_azure_vnet_deleted_when_vm_create_fails(self):
        """A failed az vm create must delete the already-created vnet and NIC."""
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh",
            {**CREATE_VM_ENV, "FAIL_VM_CREATE": "1"},
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        calls = self.cleanup_calls()
        self.assertIn("vm-delete", calls)
        self.assertIn("nic-delete", calls)
        # The NIC must go before the public IP, NSG, and vnet: while it is
        # attached, those deletes fail.
        self.assertLess(calls.index("nic-delete"), calls.index("public-ip-delete"))
        self.assertLess(calls.index("nic-delete"), calls.index("nsg-delete"))
        self.assertLess(calls.index("nic-delete"), calls.index("vnet-delete"))

    def test_azure_teardown_deletes_vnet(self):
        """Normal teardown must delete the VM's vnet.

        The OIDC teardown path funnels through the same delete-vm.sh.
        """
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/delete-vm.sh",
            {
                "AZUREKMS_VMNAME": "vmname-test-1",
                "AZUREKMS_RESOURCEGROUP": "RG",
            },
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("vm-delete", self.cleanup_calls())
        self.assertIn("vnet-delete", self.cleanup_calls())

    def test_azure_vm_deleted_nothing_when_tagged(self):
        """A tagged VM and OS disk pass verification and are left running."""
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh", CREATE_VM_ENV
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertEqual([], self.cleanup_calls())

    def test_azure_supporting_resources_tagged_when_tagged(self):
        """The NIC, public IP, and NSG created alongside the VM carry the tags.

        az vm create --tags reaches none of them.
        """
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh", CREATE_VM_ENV
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        resource_tags = (self.state_path / "resource_tags.txt").read_text()
        for resource in (
            "networkInterfaces",
            "publicIPAddresses",
            "networkSecurityGroups",
        ):
            line = next((ln for ln in resource_tags.splitlines() if resource in ln), "")
            self.assertIn("mongodb-owner", line, resource)
            self.assertIn("mongodb-env", line, resource)

    def test_azure_vm_deleted_when_supporting_resource_tagging_fails(self):
        """A failed supporting-resource tag write must clean up the VM."""
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh",
            {**CREATE_VM_ENV, "FAIL_TAG_TARGET": "networkInterfaces"},
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("vm-delete", self.cleanup_calls())
        self.assertIn("public-ip-delete", self.cleanup_calls())
        self.assertIn("nsg-delete", self.cleanup_calls())

    def test_azure_vm_deleted_when_os_disk_tagging_fails(self):
        """A failed OS-disk tag write must delete the VM, public IP, and NSG."""
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh",
            {**CREATE_VM_ENV, "FAIL_DISK_TAG": "1"},
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("vm-delete", self.cleanup_calls())
        self.assertIn("public-ip-delete", self.cleanup_calls())
        self.assertIn("nsg-delete", self.cleanup_calls())


class JanitorTest(unittest.TestCase):
    """Tests for the orphaned-vnet cleanup in delete_old_azure_resources.py.

    The Azure SDK is stubbed and both clients mocked, so the janitor's
    orphan-detection logic runs without touching Azure.
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


class AzureParseTest(unittest.TestCase):
    """This PR's files must parse and the shell gates must be present."""

    SHELL_SCRIPTS = (
        ".evergreen/verify-tags.sh",
        ".evergreen/csfle/azurekms/create-vm.sh",
        ".evergreen/csfle/azurekms/delete-vm.sh",
        ".evergreen/k8s/aks/setup-cluster.sh",
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


if __name__ == "__main__":
    unittest.main()
