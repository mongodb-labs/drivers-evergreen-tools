#!/bin/bash
# A shell script to run in an ECS hosted task
set -ex

# The environment variable is always set during interactive logins
# But for non-interactive logs, ~/.bashrc does not appear to be read on Ubuntu but it works on Fedora
[[ -z "${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}" ]] && export $(strings /proc/1/environ | grep AWS_CONTAINER_CREDENTIALS_RELATIVE_URI)

env

mkdir -p /data/db || true

/root/mongod --fork --setParameter authenticationMechanisms="MONGODB-AWS,SCRAM-SHA-256"
PID=$!
sleep 1
/root/mongosh --verbose ecs_hosted_test.js
export MONGODB_URI="mongodb://127.0.0.1:20000/aws?authMechanism=MONGODB-AWS"
bash /root/src/.evergreen/run-mongodb-aws-ecs-test.sh
kill $PID
