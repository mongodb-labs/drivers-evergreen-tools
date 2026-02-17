#! /usr/bin/env bash
# shellcheck shell=sh
##
## This script add the location of `npm` and `node` to the path.
## This is necessary because evergreen uses separate bash scripts for
## different functions in a given CI run but doesn't persist the environment
## across them.  So we manually invoke this script everywhere we need
## access to `npm`, `node`, or need to install something globally from
## npm.

# See https://stackoverflow.com/questions/35006457/choosing-between-0-and-bash-source/35006505#35006505
# Why we need this syntax when sh is not aliased to bash (this script must be able to be called from sh)
# shellcheck disable=SC3028
ORIG_SCRIPT_DIR=${SCRIPT_DIR:-}
SCRIPT_DIR=$(dirname ${BASH_SOURCE:-$0})
# Make sure paths are set up for node driver tests.
. $SCRIPT_DIR/handle-paths.sh

NODE_ARTIFACTS_PATH="$SCRIPT_DIR/node-artifacts"
if [ "${OS:-}" = "Windows_NT" ]; then
  NODE_ARTIFACTS_PATH=$(cygpath --unix "$NODE_ARTIFACTS_PATH")
fi

export NODE_ARTIFACTS_PATH
# npm uses this environment variable to determine where to install global packages
export npm_global_prefix=$NODE_ARTIFACTS_PATH/npm_global
export PATH="$npm_global_prefix/bin:$NODE_ARTIFACTS_PATH/nodejs/bin:$PATH"
hash -r

export NODE_OPTIONS="--trace-deprecation --trace-warnings"

# Restore the script dir.
export SCRIPT_DIR=$ORIG_SCRIPT_DIR
