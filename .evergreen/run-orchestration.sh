#!/usr/bin/env bash
# shellcheck shell=sh
set -o errexit  # Exit the script with error if any of the commands fail
set -x
# See https://stackoverflow.com/questions/35006457/choosing-between-0-and-bash-source/35006505#35006505
# Why we need this syntax when sh is not aliased to bash (this script must be able to be called from sh)
# shellcheck disable=SC3028
SCRIPT_DIR=$(dirname ${BASH_SOURCE:-$0})
. $SCRIPT_DIR/handle-paths.sh

bash $SCRIPT_DIR/orchestration/setup.sh
$SCRIPT_DIR/orchestration/drivers-orchestration run "$@"
