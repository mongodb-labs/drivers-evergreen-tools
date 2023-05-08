#!/usr/bin/env bash
#
# Run an AWS ECS container test end to end
#
rm -rf authawsvenv
. ./activate-authawsvenv.sh
python aws_e2e_ecs.py