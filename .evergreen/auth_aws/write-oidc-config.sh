#!/usr/bin/env bash
#
# start-oidc-enabled-server.sh
#
# Usage:
#   . ./start-oidc-enabled-server.sh
#
# Use mongo-orchestration to start a server that is configured to
# use a single identity provider.

# Inputs: VERSION (optional), USE_MULTIPLE_PRINCIPALS (optional),
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_TOKEN_FOLDER - where to store
# token files.  The name of the file is the principal name (test1, test2).
. ./activate_venv.sh

# Handle the orchestration file and the token files
python lib/aws_oidc_management.py get-config

# Run mongo-orchestration
sudo yum install -y lsof
MONGODB_VERSION=${VERSION:=latest} \
  TOPOLOGY=server \
  MONGODB_DOWNLOAD_URL=https://mciuploads.s3.amazonaws.com/mongodb-mongo-master/linux-x86-dynamic-compile-required/d2bb64fbd29269667d665c1f09066be0725b1d78/dist/mongo-mongodb_mongo_master_linux_x86_dynamic_compile_required_d2bb64fbd29269667d665c1f09066be0725b1d78_23_01_03_16_35_49.tgz \
  ORCHESTRATION_FILE=auth-oidc.json \
  bash $(dirname "${BASH_SOURCE:-$0}")/run-orchestration.sh

# Set up the server with the appropriate roles
mongo ./aws_setup_oidc.js