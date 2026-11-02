"""Regression tests for the DRIVERS-3712 tag-verification gates in the shell
provisioning scripts.

The tagged resources are created before verification, and verify-tags.sh
exits the sourcing shell on failure, so each create script must clean up what
it created when verification fails (callers persist teardown metadata only
after these scripts return). These tests drive the real scripts through
mocked `az`/`gcloud`/`curl` binaries and assert the cleanup and the
boot-disk labeling behavior.
"""

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# Mock `az`: models the subset of the CLI that azurekms/create-vm.sh uses.
# DROP_TAGS=1 simulates the CLI losing tags so verification fails. Every
# invocation is logged; deletions are logged to cleanup.log.
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

cmd=$1; shift
case "$cmd" in
  vm)
    sub=$1; shift
    case "$sub" in
      create)
        persist_tags "$STATE_DIR/vm_tags.json" "$@"
        echo '{"id": "vm-id"}'
        ;;
      show)
        if [[ "$*" == *storageProfile* ]]; then
          echo "/subscriptions/sub/disks/osdisk"
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
    if [ -n "${FAIL_DISK_TAG:-}" ]; then
      echo "az tag create: simulated failure" >> "$STATE_DIR/calls.log"
      exit 1
    fi
    persist_tags "$STATE_DIR/disk_tags.json" "$@"
    echo '{}'
    ;;
  disk)
    if [ "${1:-}" = "show" ]; then
      cat "$STATE_DIR/disk_tags.json"
    fi
    ;;
  public-ip)
    # `public-ip` is not a top-level Azure CLI command group; model the real
    # CLI by failing so the production script cannot rely on it.
    echo "az: 'public-ip' is not a command group; use 'az network public-ip'" 1>&2
    exit 1
    ;;
  network)
    if [ "${1:-}" = "nsg" ] && [ "${2:-}" = "rule" ] && [ "${3:-}" = "create" ]; then
      echo '{}'
    elif [ "${1:-}" = "nsg" ] && [ "${2:-}" = "delete" ]; then
      echo "nsg-delete" >> "$STATE_DIR/cleanup.log"
    elif [ "${1:-}" = "public-ip" ] && [ "${2:-}" = "delete" ]; then
      echo "public-ip-delete" >> "$STATE_DIR/cleanup.log"
    fi
    ;;
  *) echo '{}' ;;
esac
"""

# Mock `gcloud`: models the subset of the CLI that gcpkms/create-instance.sh
# uses. DROP_INSTANCE_LABELS / DROP_DISK_LABELS simulate lost labels.
GCLOUD_MOCK = r"""#!/usr/bin/env bash
set -u
STATE_DIR=${STATE_DIR:?}
echo "gcloud $*" >> "$STATE_DIR/calls.log"

flag_value () {
  local flag=$1; shift
  local collecting=0 out=""
  for a in "$@"; do
    if [ "$a" = "$flag" ]; then collecting=1; continue; fi
    if [[ "$a" == --* ]]; then collecting=0; fi
    if [ $collecting = 1 ]; then out=$a; fi
  done
  echo "$out"
}

labels_json () {
  local csv out="{" first=1 pair key val
  csv=$(flag_value "$@" | tr ',' ' ')
  for pair in $csv; do
    key=${pair%%=*}; val=${pair#*=}
    if [ $first = 1 ]; then first=0; else out="$out,"; fi
    out="$out\"$key\": \"$val\""
  done
  echo "$out}"
}

case "$1 $2 $3" in
  "compute instances create")
    if [ -n "${DROP_INSTANCE_LABELS:-}" ]; then
      echo '{}' > "$STATE_DIR/instance_labels.json"
    else
      labels_json --labels "${@:4}" > "$STATE_DIR/instance_labels.json"
    fi
    echo '{}'
    ;;
  "compute instances describe")
    echo "{\"labels\": $(cat "$STATE_DIR/instance_labels.json")}"
    ;;
  "compute instances delete")
    echo "instance-delete" >> "$STATE_DIR/cleanup.log"
    ;;
  "compute disks update")
    if [ -n "${FAIL_DISK_UPDATE:-}" ]; then
      echo "gcloud compute disks update: simulated failure" >> "$STATE_DIR/calls.log"
      exit 1
    fi
    if [ -n "${DROP_DISK_LABELS:-}" ]; then
      echo '{}' > "$STATE_DIR/disk_labels.json"
    else
      labels_json --update-labels "${@:4}" > "$STATE_DIR/disk_labels.json"
    fi
    echo '{}'
    ;;
  "compute disks describe")
    echo "{\"labels\": $(cat "$STATE_DIR/disk_labels.json")}"
    ;;
  *) echo '{}' ;;
esac
"""

CURL_MOCK = "#!/usr/bin/env bash\necho 1.2.3.4\n"

CREATE_VM_ENV = {
    "AZUREKMS_VMNAME_PREFIX": "PREFIX",
    "AZUREKMS_RESOURCEGROUP": "RG",
    "AZUREKMS_IMAGE": "IMG",
    "AZUREKMS_PUBLICKEYPATH": "/dev/null",
}

CREATE_INSTANCE_ENV = {
    "GCPKMS_GCLOUD": "",  # filled in per-case with the mock path
    "GCPKMS_PROJECT": "proj",
    "GCPKMS_ZONE": "zone",
    "GCPKMS_SERVICEACCOUNT": "sa",
    "GCPKMS_IMAGEPROJECT": "ip",
    "GCPKMS_IMAGEFAMILY": "if",
    "GCPKMS_MACHINETYPE": "e2-micro",
    "GCPKMS_DISKSIZE": "20gb",
}


class TagVerifyCleanupTest(unittest.TestCase):
    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)
        self.bin = self.state_path / "bin"
        self.bin.mkdir()
        self.write_executable("az", AZ_MOCK)
        self.write_executable("gcloud", GCLOUD_MOCK)
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

    def test_azure_vm_deleted_when_verification_fails(self):
        """A failed tag check must delete the VM, public IP, and NSG (F4)."""
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh",
            {**CREATE_VM_ENV, "DROP_TAGS": "1"},
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("vm-delete", self.cleanup_calls())
        self.assertIn("public-ip-delete", self.cleanup_calls())
        self.assertIn("nsg-delete", self.cleanup_calls())

    def test_azure_vm_deleted_nothing_when_tagged(self):
        """A tagged VM and OS disk pass verification and are left running."""
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh", CREATE_VM_ENV
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertEqual([], self.cleanup_calls())

    def test_azure_vm_deleted_when_os_disk_tagging_fails(self):
        """A failed OS-disk tag write must delete the VM, public IP, and NSG.

        The tagging runs before auto-shutdown is configured and before callers
        persist teardown metadata, so it must clean up itself (N4).
        """
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh",
            {**CREATE_VM_ENV, "FAIL_DISK_TAG": "1"},
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("vm-delete", self.cleanup_calls())
        self.assertIn("public-ip-delete", self.cleanup_calls())
        self.assertIn("nsg-delete", self.cleanup_calls())

    def test_gcp_instance_deleted_when_instance_labels_lost(self):
        """A failed instance-label check must delete the instance (F5)."""
        proc = self.run_create_script(
            ".evergreen/csfle/gcpkms/create-instance.sh",
            {
                **CREATE_INSTANCE_ENV,
                "GCPKMS_GCLOUD": str(self.bin / "gcloud"),
                "DROP_INSTANCE_LABELS": "1",
            },
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("instance-delete", self.cleanup_calls())

    def test_gcp_instance_deleted_when_disk_labels_lost(self):
        """An unlabelled boot disk must fail verification and delete the instance (F6)."""
        proc = self.run_create_script(
            ".evergreen/csfle/gcpkms/create-instance.sh",
            {
                **CREATE_INSTANCE_ENV,
                "GCPKMS_GCLOUD": str(self.bin / "gcloud"),
                "DROP_DISK_LABELS": "1",
            },
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("instance-delete", self.cleanup_calls())

    def test_gcp_instance_deleted_when_disk_labeling_fails(self):
        """A failed boot-disk label update must delete the instance.

        The update runs under errexit before callers persist teardown
        metadata, so it must clean up itself (N2).
        """
        proc = self.run_create_script(
            ".evergreen/csfle/gcpkms/create-instance.sh",
            {
                **CREATE_INSTANCE_ENV,
                "GCPKMS_GCLOUD": str(self.bin / "gcloud"),
                "FAIL_DISK_UPDATE": "1",
            },
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("instance-delete", self.cleanup_calls())

    def test_gcp_boot_disk_labelled_when_tagged(self):
        """The boot disk is labelled and verification passes end to end (F6)."""
        proc = self.run_create_script(
            ".evergreen/csfle/gcpkms/create-instance.sh",
            {**CREATE_INSTANCE_ENV, "GCPKMS_GCLOUD": str(self.bin / "gcloud")},
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertEqual([], self.cleanup_calls())
        disk_tags = (self.state_path / "disk_labels.json").read_text()
        self.assertIn("mongodb-owner", disk_tags)
        self.assertIn("mongodb-env", disk_tags)


class AtlasGatePresenceTest(unittest.TestCase):
    """The Atlas-consuming scripts must gate on VERIFY_MONGODB_TAGS (F1)."""

    GATED_SCRIPTS = (
        ".evergreen/atlas/setup-atlas-cluster.sh",
        ".evergreen/serverless/create-instance.sh",
        ".evergreen/auth_oidc/azure_func/setup.sh",
    )

    def test_gates_present_and_use_deployment_type(self):
        for relpath in self.GATED_SCRIPTS:
            text = (REPO / relpath).read_text()
            with self.subTest(script=relpath):
                self.assertIn("VERIFY_MONGODB_TAGS", text)
                self.assertIn("verify_atlas_tags", text)
                self.assertIn("${DEPLOYMENT_TYPE", text)

    def test_touched_scripts_parse(self):
        for relpath in (
            *self.GATED_SCRIPTS,
            ".evergreen/csfle/azurekms/create-vm.sh",
            ".evergreen/csfle/gcpkms/create-instance.sh",
        ):
            with self.subTest(script=relpath):
                subprocess.run(
                    ["bash", "-n", str(REPO / relpath)], check=True, timeout=30
                )


if __name__ == "__main__":
    unittest.main()
