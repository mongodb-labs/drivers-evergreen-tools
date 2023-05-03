#!/usr/bin/env bash
export ACCT=857654397073
export REPO=drivers-oidc

aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ACCT.dkr.ecr.us-east-1.amazonaws.com

cd ../..
docker build -t $REPO --build-arg AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" --build-arg AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" --build-arg AWS_ROLE_ARN=$AWS_ROLE_ARN --build-arg NO_IPV6=true -f .evergreen/auth_oidc/Dockerfile .

docker tag oidc-test:latest $ACCT.dkr.ecr.us-east-1.amazonaws.com/$REPO

docker push $ACCT.dkr.ecr.us-east-1.amazonaws.com/$REPO
