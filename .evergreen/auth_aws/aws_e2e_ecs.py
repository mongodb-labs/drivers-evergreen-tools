import os
import json
import sys
import subprocess

HERE = os.path.abspath(os.path.dirname(__file__))
mongo_binaries = os.environ['MONGO_BINARIES']
project_dir = os.environ['PROJECT_DIR']

with open(os.path.join(HERE, 'aws_e2e_setup.json')) as fid:
   config = json.load(fid)


base_command = f"{sys.executable} -u  lib/container_tester.py"
run_prune_command = f"{base_command} -v remote_gc_services --cluster {config['iam_auth_ecs_cluster']}"
run_test_command = f"{base_command} -d -v run_e2e_test --cluster {config['iam_auth_ecs_cluster']} --task_definition {config['iam_auth_ecs_task_definition']} --subnets {config['iam_auth_ecs_subnet_a']} --subnets {config['iam_auth_ecs_subnet_b']} --security_group {config['iam_auth_ecs_security_group']} --files {mongo_binaries}/mongod:/root/mongod ${mongo_binaries}/mongo:/root/mongo lib/ecs_hosted_test.js:/root/ecs_hosted_test.js {project_dir}:/root --script lib/ecs_hosted_test.sh"

# Pass in the AWS credentials as environment variables
# AWS_SHARED_CREDENTIALS_FILE does not work in evergreen for an unknown
#  reason
env = dict(AWS_ACCESS_KEY_ID=config['iam_auth_ecs_account'],
           AWS_SECRET_ACCESS_KEY=config['iam_auth_ecs_secret_access_key'])

# Prune other containers
subprocess.run(['/bin/sh', '-c', run_prune_command], env=env)

# Run the test in a container
subprocess.run(['/bin/sh', '-c', run_test_command], env=env)
