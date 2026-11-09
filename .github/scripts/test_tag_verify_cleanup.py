"""Regression tests for the DRIVERS-3712 tag-verification gates (AWS and Azure assets).

verify-tags.sh exits the sourcing shell on failure, so the create paths must
tolerate the S3 races and keep the verify gates armed. These tests drive the
real scripts through mocked `aws`/`eksctl`/`kubectl` binaries.
"""

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# Mock `aws`: models the CLI subset the eks scripts and
# run-deployed-lambda-aws-tests.sh use. Knobs: CREATE_CONFLICT=1 simulates a
# concurrent deploy winning the bucket race, READ_ERROR=1 a tag-read failure
# other than NoSuchTagSet, DROP_LT_TAGS=1 an untagged launch template.
AWS_MOCK = r"""#!/usr/bin/env bash
set -u
STATE_DIR=${STATE_DIR:?}
# jq output spans lines; collapse them so each call is one log line.
echo "aws $*" | tr '\n' ' ' >> "$STATE_DIR/calls.log"
echo >> "$STATE_DIR/calls.log"

case "$1 $2" in
  "sts get-caller-identity") echo "123456789012" ;;
  "s3api head-bucket")
    if [ -f "$STATE_DIR/bucket_created" ]; then
      exit 0
    fi
    exit 1
    ;;
  "s3api create-bucket")
    if [ -n "${FAIL_CREATE:-}" ]; then
      echo "An error occurred (AccessDenied) when calling the CreateBucket operation: Access Denied" 1>&2
      exit 254
    fi
    if [ -n "${CREATE_CONFLICT:-}" ] && [ ! -f "$STATE_DIR/bucket_created" ]; then
      # A concurrent deployment won the race: the bucket now exists, but this
      # create fails outside us-east-1.
      touch "$STATE_DIR/bucket_created"
      echo "An error occurred (BucketAlreadyOwnedByYou) when calling the CreateBucket operation: The bucket already exists" 1>&2
      exit 254
    fi
    touch "$STATE_DIR/bucket_created"
    ;;
  "s3api get-bucket-tagging")
    if [ -n "${READ_ERROR:-}" ]; then
      echo "An error occurred (AccessDenied) when calling the GetBucketTagging operation: Access Denied" 1>&2
      exit 254
    fi
    if [ -f "$STATE_DIR/existing_tags.json" ]; then
      cat "$STATE_DIR/existing_tags.json"
    else
      echo "An error occurred (NoSuchTagSet) when calling the GetBucketTagging operation: The TagSet does not exist" 1>&2
      exit 254
    fi
    ;;
  "s3api put-bucket-tagging") : ;;
  "iam tag-role")
    if [ -n "${DROP_IAM_TAGS:-}" ]; then
      echo '[{"Key": "aws:eks:unrelated", "Value": "x"}]' > "$STATE_DIR/role_tags.json"
    else
      echo '[{"Key": "mongodb-owner", "Value": "o"}, {"Key": "mongodb-env", "Value": "dev"}]' > "$STATE_DIR/role_tags.json"
    fi
    ;;
  "iam get-role")
    # Returns the post-query shape: the real CLI applies --query client-side.
    # Without a prior tag-role (standalone verification), the role is tagged.
    if [ -f "$STATE_DIR/role_tags.json" ]; then
      cat "$STATE_DIR/role_tags.json"
    else
      echo '[{"Key": "mongodb-owner", "Value": "o"}, {"Key": "mongodb-env", "Value": "dev"}]'
    fi
    ;;
  "eks list-nodegroups") echo '{"nodegroups": ["ng-1"]}' ;;
  "eks describe-cluster")
    if [ -n "${DROP_EKS_TAGS:-}" ]; then
      echo '{}'
    else
      echo '{"mongodb-owner": "o", "mongodb-env": "dev"}'
    fi
    ;;
  "ec2 describe-launch-templates")
    if [ -n "${FAIL_LT_DESCRIBE:-}" ]; then
      echo "An error occurred when calling the DescribeLaunchTemplates operation: simulated failure" 1>&2
      exit 254
    fi
    # A wildcard name filter simulates the API's glob matching, which also
    # returns starter templates of clusters sharing the name prefix.
    if [[ "$*" == *launch-template-name* ]]; then
      if [[ "$*" == *\** ]]; then
        echo '{"LaunchTemplates": [{"LaunchTemplateId": "lt-starter"}, {"LaunchTemplateId": "lt-other-cluster"}]}'
      else
        echo '{"LaunchTemplates": [{"LaunchTemplateId": "lt-starter"}]}'
      fi
    elif [[ "$*" == *eks:cluster-name* ]]; then
      echo '{"LaunchTemplates": [{"LaunchTemplateId": "lt-generated"}]}'
    elif [ -n "${DROP_LT_TAGS:-}" ]; then
      echo '[{"Key": "eks:cluster-name", "Value": "cluster"}]'
    else
      echo '[{"Key": "eks:cluster-name", "Value": "cluster"}, {"Key": "mongodb-owner", "Value": "o"}, {"Key": "mongodb-env", "Value": "dev"}]'
    fi
    ;;
  "ec2 create-tags") : ;;
  *) echo '{}' ;;
esac
"""

# Mock `eksctl`: logs every invocation; enough for setup-cluster.sh.
EKSCTL_MOCK = """#!/usr/bin/env bash
set -u
STATE_DIR=${STATE_DIR:?}
echo "eksctl $*" | tr '\\n' ' ' >> "$STATE_DIR/calls.log"
echo >> "$STATE_DIR/calls.log"
"""

# Mock `kubectl`: no-op.
KUBECTL_MOCK = """#!/usr/bin/env bash
exit 0
"""


class ArtifactBucketTest(unittest.TestCase):
    """Tests for ensure_artifact_bucket in run-deployed-lambda-aws-tests.sh.

    The script's function definitions are extracted (everything before its
    trap line) and sourced with a mocked `aws`, so the real bucket logic runs
    without touching S3.
    """

    SCRIPT = REPO / ".evergreen/aws_lambda/run-deployed-lambda-aws-tests.sh"

    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)
        self.bin = self.state_path / "bin"
        self.bin.mkdir()
        self.write_executable("aws", AWS_MOCK)
        # Everything before the trap line: function definitions only.
        extraction = subprocess.run(
            ["awk", "/^trap cleanup EXIT/{exit} {print}", str(self.SCRIPT)],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        # The extracted file lives outside the repo, so handle-paths.sh's
        # relative source cannot resolve; DRIVERS_TOOLS is already set.
        functions_text = extraction.stdout.replace(
            ". $SCRIPT_DIR/../handle-paths.sh",
            ": # handle-paths.sh skipped by the test harness; DRIVERS_TOOLS is set",
        )
        self.functions = self.state_path / "functions.sh"
        self.functions.write_text(functions_text)

    def tearDown(self):
        self.state.cleanup()

    def write_executable(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def run_ensure_artifact_bucket(self, extra_env):
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["STATE_DIR"] = str(self.state_path)
        env["DRIVERS_TOOLS"] = str(REPO)
        env["TEST_LAMBDA_DIRECTORY"] = str(self.state_path)
        env["DRIVERS_ATLAS_PUBLIC_API_KEY"] = "k"
        env["DRIVERS_ATLAS_PRIVATE_API_KEY"] = "s"
        env["DRIVERS_ATLAS_LAMBDA_USER"] = "u"
        env["DRIVERS_ATLAS_LAMBDA_PASSWORD"] = "p"
        env["DRIVERS_ATLAS_GROUP_ID"] = "g"
        env["LAMBDA_STACK_NAME"] = "stack"
        env["AWS_REGION"] = "us-west-2"
        env["FUNCTIONS"] = str(self.functions)
        env.update(extra_env)
        return subprocess.run(
            ["bash", "-c", "set -o errexit; source $FUNCTIONS; ensure_artifact_bucket"],
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )

    def calls(self):
        log = self.state_path / "calls.log"
        return log.read_text() if log.exists() else ""

    def test_concurrent_bucket_creation_is_tolerated(self):
        """A BucketAlreadyOwnedByYou from a concurrent deploy must not abort.

        The winner created the bucket, which is then perfectly usable.
        """
        proc = self.run_ensure_artifact_bucket({"CREATE_CONFLICT": "1"})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("put-bucket-tagging", self.calls())

    def test_existing_bucket_tags_are_merged(self):
        """put-bucket-tagging must not wipe tags unrelated to the policy."""
        (self.state_path / "bucket_created").touch()
        (self.state_path / "existing_tags.json").write_text(
            '[{"Key": "CostCenter", "Value": "42"}]'
        )
        proc = self.run_ensure_artifact_bucket({})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        tagging_line = next(
            (ln for ln in self.calls().splitlines() if "put-bucket-tagging" in ln), ""
        )
        for expected in ("CostCenter", "mongodb-owner", "mongodb-env"):
            self.assertIn(expected, tagging_line)

    def test_bucket_tag_read_error_aborts(self):
        """A tag-read error other than NoSuchTagSet must abort before the write.

        Writing the policy tags after a failed read would wipe the tags the
        script never saw.
        """
        proc = self.run_ensure_artifact_bucket({"READ_ERROR": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertNotIn("put-bucket-tagging", self.calls())

    def test_bucket_create_error_is_reported(self):
        """A create failure that head-bucket cannot rescue must report the AWS error.

        Swallowing the create's stderr leaves only 'Could not create artifact
        bucket', hiding the real cause.
        """
        proc = self.run_ensure_artifact_bucket({"FAIL_CREATE": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("AccessDenied", proc.stderr)


class EksSetupTest(unittest.TestCase):
    """Tests for the EKS service account tagging in k8s/eks/setup-cluster.sh.

    eksctl's --tags on create iamserviceaccount reaches the CloudFormation
    stack but not the IAM role, so the script must tag and verify the role
    itself. Runs the real script from a stub checkout with mocked CLIs.
    """

    SCRIPT = REPO / ".evergreen/k8s/eks/setup-cluster.sh"

    SECRETS = (
        "export EKS_CLUSTER_NAME=cluster\n"
        "export EKS_REGION=us-west-2\n"
        "export EKS_SERVICE_ACCOUNT_NAME=sa\n"
        "export EKS_IAM_ROLE_NAME=role\n"
        "export EKS_POLICY_ARN=arn:policy\n"
    )

    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)
        self.bin = self.state_path / "bin"
        self.bin.mkdir()
        self.write_executable("aws", AWS_MOCK)
        self.write_executable("eksctl", EKSCTL_MOCK)
        self.write_executable("kubectl", KUBECTL_MOCK)
        # The script sources ./secrets-export.sh from its working directory;
        # the stub keeps the vault-based setup-secrets.sh out of the run.
        (self.state_path / "secrets-export.sh").write_text(self.SECRETS)

    def tearDown(self):
        self.state.cleanup()

    def write_executable(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def run_setup_cluster(self, extra_env):
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["STATE_DIR"] = str(self.state_path)
        env["VERIFY_MONGODB_TAGS"] = "1"
        env["DRIVERS_TOOLS"] = str(REPO)
        env.update(extra_env)
        return subprocess.run(
            ["bash", str(self.SCRIPT)],
            cwd=self.state_path,
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )

    def calls(self):
        log = self.state_path / "calls.log"
        return log.read_text() if log.exists() else ""

    def test_eks_service_account_and_role_tagged(self):
        """The iamserviceaccount gets the tags and the IAM role is tagged too."""
        proc = self.run_setup_cluster({})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        sa_line = next(
            (ln for ln in self.calls().splitlines() if "iamserviceaccount" in ln), ""
        )
        self.assertIn("--tags", sa_line)
        self.assertIn("mongodb-owner", sa_line)
        self.assertIn("tag-role", self.calls())
        self.assertIn("mongodb-owner", self.calls())

    def test_eks_fails_when_role_tags_missing(self):
        """An untagged IAM role must fail verification."""
        proc = self.run_setup_cluster({"DROP_IAM_TAGS": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)

    def test_eks_launch_templates_are_tagged(self):
        """Both launch template families must get the policy tags, and
        discovery must stay inside the cluster: a name-prefix match would
        reach starters of other clusters sharing the prefix."""
        proc = self.run_setup_cluster({})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        create_calls = [ln for ln in self.calls().splitlines() if "create-tags" in ln]
        self.assertEqual(1, len(create_calls), self.calls())
        for lt_id in ("lt-starter", "lt-generated"):
            self.assertIn(lt_id, create_calls[0])
        self.assertNotIn("lt-other-cluster", create_calls[0])
        self.assertIn("mongodb-owner", create_calls[0])
        self.assertIn("mongodb-env", create_calls[0])

    def test_eks_fails_when_launch_template_untagged(self):
        """An untagged launch template must fail verification."""
        proc = self.run_setup_cluster({"DROP_LT_TAGS": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("verify-tags FAILED", proc.stdout + proc.stderr)

    def test_eks_fails_when_launch_template_discovery_fails(self):
        """A failed describe-launch-templates must abort, not skip tagging."""
        proc = self.run_setup_cluster({"FAIL_LT_DESCRIBE": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn(
            "describe-launch-templates (ng-1) failed", proc.stdout + proc.stderr
        )

    def test_eks_fails_when_launch_template_parsing_fails(self):
        """A failed launch-template parse must abort, not skip tagging."""
        self.write_executable("jq", "#!/usr/bin/env bash\nexit 1\n")
        proc = self.run_setup_cluster({"VERIFY_MONGODB_TAGS": ""})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn(
            "parsing list-nodegroups output failed", proc.stdout + proc.stderr
        )

    def test_verify_eks_setup_standalone(self):
        """verify-eks-setup.sh re-checks every tag on an existing cluster."""
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["STATE_DIR"] = str(self.state_path)
        env["DRIVERS_TOOLS"] = str(REPO)
        proc = subprocess.run(
            ["bash", str(REPO / ".evergreen/k8s/eks/verify-eks-setup.sh")],
            cwd=self.state_path,
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("verify-tags OK", proc.stdout + proc.stderr)


class EksPodSetupTest(unittest.TestCase):
    """Tests for the cluster-tag gate in k8s/eks/setup.sh, the pod flow the
    eks task runs."""

    SCRIPT = REPO / ".evergreen/k8s/eks/setup.sh"

    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)
        self.bin = self.state_path / "bin"
        self.bin.mkdir()
        self.write_executable("aws", AWS_MOCK)
        self.write_executable("kubectl", KUBECTL_MOCK)
        self.write_executable("eksctl", EKSCTL_MOCK)

    def tearDown(self):
        self.state.cleanup()

    def write_executable(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def run_pod_setup(self, extra_env):
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["STATE_DIR"] = str(self.state_path)
        env["VERIFY_MONGODB_TAGS"] = "1"
        env["DRIVERS_TOOLS"] = str(REPO)
        env["EKS_CLUSTER_NAME"] = "cluster"
        env["EKS_REGION"] = "us-west-2"
        env["EKS_SERVICE_ACCOUNT_NAME"] = "sa"
        env.update(extra_env)
        return subprocess.run(
            ["bash", str(self.SCRIPT)],
            cwd=self.state_path,
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )

    def test_pod_setup_fails_when_cluster_untagged(self):
        """An untagged cluster must fail the pod setup."""
        proc = self.run_pod_setup({"DROP_EKS_TAGS": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("verify-tags FAILED", proc.stdout + proc.stderr)

    def test_pod_setup_passes_when_cluster_tagged(self):
        proc = self.run_pod_setup({})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


class AwsParseTest(unittest.TestCase):
    """This PR's shell files must parse and gate on VERIFY_MONGODB_TAGS."""

    SCRIPTS = (
        ".evergreen/verify-tags.sh",
        ".evergreen/aws_lambda/run-deployed-lambda-aws-tests.sh",
        ".evergreen/k8s/eks/setup-cluster.sh",
        ".evergreen/k8s/eks/verify-eks-setup.sh",
    )

    # verify-eks-setup.sh verifies unconditionally and carries no gate.
    GATES = (
        ".evergreen/aws_lambda/run-deployed-lambda-aws-tests.sh",
        ".evergreen/k8s/eks/setup-cluster.sh",
    )

    def test_scripts_parse(self):
        for relpath in self.SCRIPTS:
            with self.subTest(script=relpath):
                subprocess.run(
                    ["bash", "-n", str(REPO / relpath)], check=True, timeout=30
                )

    def test_gates_present(self):
        for relpath in self.GATES:
            text = (REPO / relpath).read_text()
            with self.subTest(script=relpath):
                self.assertIn("VERIFY_MONGODB_TAGS", text)


import datetime
import importlib.util
import sys
import types
from unittest import mock

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
        self.assertEqual(text.count('verify_cloud_tags "'), 6)
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
