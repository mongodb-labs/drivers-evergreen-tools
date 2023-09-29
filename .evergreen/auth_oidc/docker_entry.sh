#!/usr/bin/env bash
#
# Entry point for Dockerfile for launching an oidc-enabled server.
#
set -eux

bash /root/docker_entry_base.sh
tail -f $MONGO_ORCHESTRATION_HOME/server.log
