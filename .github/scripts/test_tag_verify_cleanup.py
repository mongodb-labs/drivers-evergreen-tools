"""Regression tests for the DRIVERS-3712 tag gates (AWS and Azure assets).

verify-tags.sh exits the sourcing shell on failure, so the create paths must
tolerate the S3 races and keep the verify gates armed, and the create scripts
must clean up what they created when verification or tagging fails. The
janitor must not delete fresh vnets mid-provisioning. These tests drive the
real scripts through mocked `aws`/`eksctl`/`kubectl`/`az`/`curl` binaries.
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


AZ_MOCK = r"""#!/usr/bin/env bash
set -u
STATE_DIR=${STATE_DIR:?}
echo "az $*" >> "$STATE_DIR/calls.log"

flag_values () {
  local flag=$1; shift
  local collecting=0 out=()
  for a in "$@"; do
    if [ "$a" = "$flag" ]; then collecting=1; continue; fi
    # A single-dash flag (-otsv) ends collection just like --output tsv.
    if [[ "$a" == -* ]]; then collecting=0; fi
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
        elif [[ "$*" == *publicIps* ]]; then
          echo "20.51.134.22"
        else
          cat "$STATE_DIR/vm_tags.json"
        fi
        ;;
      delete) echo "vm-delete" >> "$STATE_DIR/cleanup.log" ;;
      auto-shutdown) : ;;
      resize)
        if [ -n "${FAIL_RESIZE:-}" ]; then
          echo "az vm resize: simulated failure" 1>&2
          exit 1
        fi
        ;;
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
          if [ -n "${FAIL_NSG_RULE:-}" ]; then
            echo "az network nsg rule create: simulated failure" 1>&2
            exit 1
          fi
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
  group)
    # az group list/create/show/delete. Tags are stored by resource id in
    # resource_tags.txt, so tag-create-on-id (the MC_ node resource group)
    # and create-time --tags land in the same store.
    sub=$1; shift
    group_id="/subscriptions/sub/resourceGroups/${AKS_RESOURCE_GROUP:-RG}"
    case "$sub" in
      list)
        # Empty: the simulated subscription has no pre-existing groups, so
        # setup-cluster.sh's exists-check passes.
        echo "[]"
        ;;
      create)
        group_name=""; prev=""
        for a in "$@"; do
          if [ "$prev" = "--name" ] || [ "$prev" = "-n" ]; then group_name=$a; fi
          prev=$a
        done
        store_resource_tags "/subscriptions/sub/resourceGroups/${group_name}" \
          "$(tags_json "$(flag_values --tags "$@")")"
        ;;
      show)
        group_name=""; query=""; prev=""
        for a in "$@"; do
          case "$prev" in
            --name|-n|--resource-group) group_name=$a ;;
            --query) query=$a ;;
          esac
          prev=$a
        done
        group_id="/subscriptions/sub/resourceGroups/${group_name}"
        if [ "$query" = "id" ]; then
          echo "${group_id}"
        elif [ "$query" = "tags" ]; then
          # Unstored groups model the migrated pre-provisioned cluster: the
          # node resource group carries the tags unless DROP_MC_TAGS drops
          # them.
          stored=$(show_resource_tags "${group_id}")
          if [ -n "${stored}" ]; then
            echo "${stored}"
          elif [ -n "${DROP_MC_TAGS:-}" ]; then
            echo '{}'
          else
            echo '{"mongodb-owner": "o", "mongodb-env": "dev"}'
          fi
        fi
        ;;
      delete)
        echo "group-delete" >> "$STATE_DIR/cleanup.log"
        ;;
    esac
    ;;
  identity)
    sub=$1; shift
    identity_name=""; query=""; prev=""
    for a in "$@"; do
      case "$prev" in
        --name) identity_name=$a ;;
        --query) query=$a ;;
      esac
      prev=$a
    done
    identity_id="/subscriptions/sub/resourceGroups/${AKS_RESOURCE_GROUP:-RG}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${identity_name}"
    case "$sub" in
      create)
        store_resource_tags "${identity_id}" "$(tags_json "$(flag_values --tags "$@")")"
        ;;
      show)
        if [ "$query" = "clientId" ]; then
          echo "client-id"
        elif [ "$query" = "tags" ]; then
          stored=$(show_resource_tags "${identity_id}")
          if [ -n "${stored}" ]; then
            echo "${stored}"
          elif [ -n "${DROP_IDENTITY_TAGS:-}" ]; then
            echo '{}'
          else
            echo '{"mongodb-owner": "o", "mongodb-env": "dev"}'
          fi
        fi
        ;;
    esac
    ;;
  aks)
    # az aks show -n NAME -g RG --query tags (the pod-flow cluster gate);
    # the mock returns the post-query tags map.
    sub=${1:-}
    shift || true
    case "$sub" in
      show)
        query=$(flag_values --query "$@")
        if [ "$query" = "nodeResourceGroup" ]; then
          echo "MC-TEST-NODES"
        elif [ "$query" = "oidcIssuerProfile.issuerUrl" ]; then
          echo "https://oidc.example"
        elif [ "$query" = "tags" ]; then
          stored=$(show_resource_tags "/subscriptions/sub/resourceGroups/${AKS_RESOURCE_GROUP:-RG}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME:-cluster}")
          if [ -n "${stored}" ]; then
            echo "${stored}"
          elif [ -n "${DROP_AKS_TAGS:-}" ]; then
            echo '{}'
          else
            echo '{"mongodb-owner": "o", "mongodb-env": "dev"}'
          fi
        fi
        ;;
      create)
        if [ -n "${FAIL_AKS_CREATE:-}" ]; then
          echo "az aks create: simulated failure" 1>&2
          exit 1
        fi
        store_resource_tags "/subscriptions/sub/resourceGroups/${AKS_RESOURCE_GROUP:-RG}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME:-cluster}" \
          "$(tags_json "$(flag_values --tags "$@")")"
        ;;
      nodepool)
        np_sub=${1:-}
        case "$np_sub" in
          list)
            if [ -n "${FAIL_POOL_LIST:-}" ]; then
              echo "az aks nodepool list: simulated failure" 1>&2
              exit 1
            fi
            if [ -n "${DROP_POOL_TAGS:-}" ]; then
              echo '[{"name": "nodepool1", "tags": {}}]'
            else
              echo '[{"name": "nodepool1", "tags": {"mongodb-owner": "o", "mongodb-env": "dev"}}]'
            fi
            ;;
          update)
            if [ -n "${FAIL_POOL_UPDATE:-}" ]; then
              echo "az aks nodepool update: simulated failure" 1>&2
              exit 1
            fi
            pool_name=""; prev=""
            for a in "$@"; do
              if [ "$prev" = "-n" ] || [ "$prev" = "--name" ]; then pool_name=$a; fi
              prev=$a
            done
            if [ -n "${DROP_POOL_TAGS:-}" ]; then
              store_resource_tags "/subscriptions/sub/resourceGroups/${AKS_RESOURCE_GROUP:-RG}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME:-cluster}/agentPools/${pool_name}" '{}'
            else
              store_resource_tags "/subscriptions/sub/resourceGroups/${AKS_RESOURCE_GROUP:-RG}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME:-cluster}/agentPools/${pool_name}" \
                "$(tags_json "$(flag_values --tags "$@")")"
            fi
            ;;
        esac
        ;;
      *) : ;;
    esac
    ;;
  *) echo '{}' ;;
esac
"""

CURL_MOCK = r"""#!/usr/bin/env bash
# Mock `curl` for whatismyip.akamai.com. CURL_FAIL_FIRST=1 fails the first
# invocation (exit 56, curl's network-receive error); CURL_FAIL_ALWAYS=1
# fails every invocation. CURL_PARTIAL_FIRST=1 writes a partial IP to stdout
# before failing the first invocation, the way a connection cut mid-transfer
# does. Otherwise echoes an IP.
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

CREATE_VM_ENV = {
    "AZUREKMS_VMNAME_PREFIX": "PREFIX",
    "AZUREKMS_RESOURCEGROUP": "RG",
    "AZUREKMS_IMAGE": "IMG",
    "AZUREKMS_PUBLICKEYPATH": "/dev/null",
}


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

    def test_azure_vm_deleted_when_resize_fails(self):
        """A failed resize after tagging must still clean up the VM.

        Resize has no explicit guard; callers persist teardown metadata only
        after create-vm.sh returns.
        """
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh",
            {**CREATE_VM_ENV, "AZUREKMS_MACHINESIZE": "SIZE", "FAIL_RESIZE": "1"},
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("vm-delete", self.cleanup_calls())
        self.assertIn("nic-delete", self.cleanup_calls())
        self.assertIn("public-ip-delete", self.cleanup_calls())
        self.assertIn("nsg-delete", self.cleanup_calls())
        self.assertIn("vnet-delete", self.cleanup_calls())

    def test_azure_vm_deleted_when_nsg_rule_fails(self):
        """A failed SSH-rule create must still clean up the VM."""
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh",
            {**CREATE_VM_ENV, "FAIL_NSG_RULE": "1"},
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("vm-delete", self.cleanup_calls())
        self.assertIn("nic-delete", self.cleanup_calls())
        self.assertIn("public-ip-delete", self.cleanup_calls())
        self.assertIn("nsg-delete", self.cleanup_calls())
        self.assertIn("vnet-delete", self.cleanup_calls())

    def test_azure_vm_deleted_when_ip_lookup_fails(self):
        """Exhausting the IP-lookup retries must still clean up the VM.

        The lookup runs after the VM is up but before callers save teardown
        metadata.
        """
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh",
            {**CREATE_VM_ENV, "CURL_FAIL_ALWAYS": "1"},
        )
        self.assertEqual(proc.returncode, 56, proc.stdout + proc.stderr)
        self.assertIn("vm-delete", self.cleanup_calls())
        self.assertIn("nic-delete", self.cleanup_calls())
        self.assertIn("public-ip-delete", self.cleanup_calls())
        self.assertIn("nsg-delete", self.cleanup_calls())
        self.assertIn("vnet-delete", self.cleanup_calls())

    def test_azure_nsg_rule_gets_one_ip_after_partial_response(self):
        """A partial response from a failed lookup must not reach the rule.

        The retried curl concatenates a failed attempt's partial stdout with
        the next attempt's response; the NSG rule would get an invalid IP.
        """
        proc = self.run_create_script(
            ".evergreen/csfle/azurekms/create-vm.sh",
            {**CREATE_VM_ENV, "CURL_PARTIAL_FIRST": "1"},
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("attempt n. 2", proc.stderr)
        self.assertIn("--source-address-prefixes 1.2.3.4", self.calls())
        self.assertNotIn("1.2.3.1.2.3.4", self.calls())


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


class AksPodSetupTest(unittest.TestCase):
    """Tests for the cluster-tag gate in k8s/aks/setup.sh, the pod flow the
    aks task runs."""

    SCRIPT = REPO / ".evergreen/k8s/aks/setup.sh"

    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)
        self.bin = self.state_path / "bin"
        self.bin.mkdir()
        self.write_executable("az", AZ_MOCK)
        self.write_executable("kubectl", KUBECTL_MOCK)

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
        # Exported so the script skips the vault-based setup-secrets.sh and
        # azurekms/login.sh's service-principal login; the script pushd's
        # into the repo, so a cwd stub file would be ignored.
        env["AZUREKMS_TENANTID"] = "t"
        env["AZUREKMS_CLIENTID"] = "c"
        env["AZUREKMS_SECRET"] = "s"
        env["AKS_CLUSTER_NAME"] = "cluster"
        env["AKS_RESOURCE_GROUP"] = "rg"
        env["AKS_SERVICE_ACCOUNT_NAME"] = "sa"
        env["AKS_SERVICE_ACCOUNT_NAMESPACE"] = "default"
        env["AKS_USER_ASSIGNED_IDENTITY_NAME"] = "identity"
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
        proc = self.run_pod_setup({"DROP_AKS_TAGS": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("verify-tags FAILED", proc.stdout + proc.stderr)

    def test_pod_setup_fails_when_node_resource_group_untagged(self):
        """An untagged node resource group must fail the pod setup.

        The pre-provisioned cluster's own tags pass, but until the README
        migration snippet tags its AKS-created node resource group, the gate
        must still reject it: that group holds the billable nodes.
        """
        proc = self.run_pod_setup({"DROP_MC_TAGS": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("verify-tags OK: AKS cluster", proc.stdout + proc.stderr)
        self.assertIn(
            "verify-tags FAILED: AKS node resource group MC-TEST-NODES lacks "
            "mongodb-owner/mongodb-env tags",
            proc.stdout + proc.stderr,
        )

    def test_pod_setup_passes_when_cluster_tagged(self):
        proc = self.run_pod_setup({})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


AKS_SETUP_ENV = {
    "AKS_RESOURCE_GROUP": "RG",
    "AKS_CLUSTER_NAME": "CLUSTER",
    "AKS_LOCATION": "eastus",
    "AKS_SERVICE_ACCOUNT_NAME": "sa",
    "AKS_SERVICE_ACCOUNT_NAMESPACE": "default",
    "AKS_FEDERATED_IDENTITY_CREDENTIAL_NAME": "fed",
    "AKS_USER_ASSIGNED_IDENTITY_NAME": "identity",
    "AKS_APPLICATION_ID": "app-id",
    # Exported so the script skips the vault-based setup-secrets.sh.
    "AZUREKMS_TENANTID": "t",
}


class AksClusterSetupTest(unittest.TestCase):
    """Tests for the DRIVERS-3712 tagging flow in k8s/aks/setup-cluster.sh.

    az aks create --tags reaches only the cluster resource: the AKS-created
    node resource group (the billable nodes, load balancer IP, and networks)
    and the node pools backing the VMSS need explicit tagging. A failure
    before setup completes must delete the partially created resource group
    (a leftover one blocks re-runs and leaks billable resources); a
    verification failure must leave the long-lived cluster for manual repair.
    """

    SCRIPT = REPO / ".evergreen/k8s/aks/setup-cluster.sh"

    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)
        self.bin = self.state_path / "bin"
        self.bin.mkdir()
        self.write_executable("az", AZ_MOCK)
        self.write_executable("kubectl", KUBECTL_MOCK)

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
        env.update(AKS_SETUP_ENV)
        env.update(extra_env)
        return subprocess.run(
            ["bash", str(self.SCRIPT)],
            cwd=self.state_path,
            env=env,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )

    def cleanup_calls(self):
        path = self.state_path / "cleanup.log"
        if not path.exists():
            return []
        return path.read_text().split()

    def resource_tags(self, resource):
        """Return the stored tag line for a resource-id substring."""
        path = self.state_path / "resource_tags.txt"
        if not path.exists():
            return ""
        lines = path.read_text().splitlines()
        return next((ln for ln in lines if resource in ln), "")

    def test_node_resource_group_pools_and_identity_are_tagged(self):
        """The AKS-created node resource group, node pools, and identity
        carry the tags; az aks create --tags reaches none of them."""
        proc = self.run_setup_cluster({})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        for resource in (
            "resourceGroups/MC-TEST-NODES",
            "agentPools/nodepool1",
            "userAssignedIdentities/identity",
        ):
            line = self.resource_tags(resource)
            self.assertIn("mongodb-owner", line, resource)
            self.assertIn("mongodb-env", line, resource)
        self.assertEqual([], self.cleanup_calls())

    def test_group_deleted_when_cluster_create_fails(self):
        """A failed az aks create must delete the created resource group."""
        proc = self.run_setup_cluster({"FAIL_AKS_CREATE": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("group-delete", self.cleanup_calls())

    def test_group_deleted_when_nodepool_tagging_fails(self):
        """A failed node pool tag write must delete the resource group."""
        proc = self.run_setup_cluster({"FAIL_POOL_UPDATE": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("group-delete", self.cleanup_calls())

    def test_group_kept_when_verification_fails(self):
        """A tag verification failure leaves the cluster for manual repair.

        Deleting it would be destructive; the trap must be disarmed before
        verification runs.
        """
        proc = self.run_setup_cluster({"DROP_POOL_TAGS": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("verify-tags FAILED", proc.stdout + proc.stderr)
        self.assertNotIn("group-delete", self.cleanup_calls())


class AksVerifyTest(unittest.TestCase):
    """Tests for verify-aks-setup.sh run standalone against a live cluster.

    The pod flow's gate and the one-time setup share the module: the cluster,
    its node resource group, every node pool, and the identity must carry
    mongodb-owner/mongodb-env.
    """

    SCRIPT = REPO / ".evergreen/k8s/aks/verify-aks-setup.sh"

    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)
        self.bin = self.state_path / "bin"
        self.bin.mkdir()
        self.write_executable("az", AZ_MOCK)

    def tearDown(self):
        self.state.cleanup()

    def write_executable(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def run_verify(self, extra_env):
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["STATE_DIR"] = str(self.state_path)
        env["DRIVERS_TOOLS"] = str(REPO)
        # Exported so the script skips the vault-based setup-secrets.sh.
        env["AZUREKMS_TENANTID"] = "t"
        env["AKS_RESOURCE_GROUP"] = "RG"
        env["AKS_CLUSTER_NAME"] = "CLUSTER"
        env["AKS_USER_ASSIGNED_IDENTITY_NAME"] = "identity"
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

    def test_standalone_verification_passes_when_tagged(self):
        proc = self.run_verify({})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        output = proc.stdout + proc.stderr
        for resource in (
            "AKS cluster",
            "AKS node resource group",
            "AKS node pool",
            "AKS identity",
        ):
            self.assertIn(f"verify-tags OK: {resource}", output, resource)

    def test_fails_when_node_pool_untagged(self):
        proc = self.run_verify({"DROP_POOL_TAGS": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("verify-tags FAILED", proc.stdout + proc.stderr)

    def test_fails_when_node_resource_group_untagged(self):
        proc = self.run_verify({"DROP_MC_TAGS": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("verify-tags FAILED", proc.stdout + proc.stderr)

    def test_fails_when_node_pool_discovery_fails(self):
        proc = self.run_verify({"FAIL_POOL_LIST": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)


class SshIpTest(unittest.TestCase):
    """Tests for set-ssh-ip.sh's external-IP lookup.

    The whatismyip curl is an external dependency on the provisioning path;
    it must survive a transient failure (retry) instead of aborting the task
    with curl's exit 56.
    """

    SCRIPT = REPO / ".evergreen/csfle/azurekms/set-ssh-ip.sh"

    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.state_path = Path(self.state.name)
        self.bin = self.state_path / "bin"
        self.bin.mkdir()
        self.write_executable("az", AZ_MOCK)
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
        # The retry progress goes to stderr; stdout must carry only the IP
        # pipeline's own output.
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
    """The retry helper's stdout contract.

    retry-with-backoff.sh runs inside command substitutions, where a failed
    attempt's partial stdout would concatenate with the next attempt's
    response: the whatismyip lookups would get an invalid IP.
    """

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


class AzureParseTest(unittest.TestCase):
    """This PR's files must parse and the shell gates must be present."""

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


if __name__ == "__main__":
    unittest.main()
