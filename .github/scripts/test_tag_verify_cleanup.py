"""Regression tests for the DRIVERS-3712 tag-verification gates (AWS assets).

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
    # Filter calls return the full response shape; the per-template call
    # returns the post-query tag array, policy-less under DROP_LT_TAGS.
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
        """Both launch template families must get the policy tags: eksctl's
        starter is created untagged and EKS's generated copy carries service
        tags only, so setup-cluster.sh must tag both itself. Discovery must
        also stay inside the cluster: a name-prefix match would reach
        starters of other clusters sharing the prefix."""
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
        """A failed describe-launch-templates must abort, not skip tagging.

        Masking the discovery failure would leave templates untagged and let
        the gate pass without checking them.
        """
        proc = self.run_setup_cluster({"FAIL_LT_DESCRIBE": "1"})
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn(
            "describe-launch-templates (ng-1) failed", proc.stdout + proc.stderr
        )

    def test_eks_fails_when_launch_template_parsing_fails(self):
        """A failed launch-template parse must abort, not skip tagging.

        With verification disabled nothing else would catch the skipped
        tagging, so the parse failure has to propagate from discovery.
        """
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


if __name__ == "__main__":
    unittest.main()
