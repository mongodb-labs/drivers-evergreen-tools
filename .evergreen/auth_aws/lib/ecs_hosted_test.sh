#!/usr/bin/env bash
# A shell script to run in an ECS hosted task
set -eux

echo "Running ECS hosted test..."

# The environment variable is always set during interactive logins
# But for non-interactive logs, ~/.bashrc does not appear to be read on Ubuntu but it works on Fedora
[[ -z "${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI:-}" ]] && export "$(strings /proc/1/environ | grep AWS_CONTAINER_CREDENTIALS_RELATIVE_URI)"

curl -L --verbose http://169.254.170.2/$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
TOKEN=`curl -L -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 30"`
ROLE_NAME=`curl -L http://169.254.169.254/latest/meta-data/iam/security-credentials/ -H "X-aws-ec2-metadata-token: $TOKEN"`
echo "ROLE_NAME=$ROLE_NAME"
env
exit 1
mkdir -p /data/db || true
/root/mongod --fork --logpath server.log --setParameter authenticationMechanisms="MONGODB-AWS,SCRAM-SHA-256"
sleep 1
/root/mongosh --verbose ecs_hosted_test.js

bash /root/src/.evergreen/run-mongodb-aws-ecs-test.sh "mongodb://localhost/aws?authMechanism=MONGODB-AWS"

echo "Running ECS hosted test... done."
