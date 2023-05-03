#!/usr/bin/env bash
export ACCT=857654397073
export REPO=drivers-oidc

aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ACCT.dkr.ecr.us-east-1.amazonaws.com

docker run -p 27017:27017 -p 27018:27018  $ACCT.dkr.ecr.us-east-1.amazonaws.com/$REPO:latest