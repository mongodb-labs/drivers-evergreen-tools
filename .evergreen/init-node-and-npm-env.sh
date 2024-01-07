#! /usr/bin/env bash
##
## This script add the location of `npm` and `node` to the path.
## This is necessary because evergreen uses separate bash scripts for
## different functions in a given CI run but doesn't persist the environment
## across them.  So we manually invoke this script everywhere we need
## access to `npm`, `node`, or need to install something globally from
## npm.

DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
. $DIR/handle-paths.sh
NODE_ARTIFACTS_PATH="$DIR/node-artifacts"
if [[ "$OS" == "Windows_NT" ]]; then
  NODE_ARTIFACTS_PATH=$(cygpath --unix "$NODE_ARTIFACTS_PATH")
fi

export NODE_ARTIFACTS_PATH
# npm uses this environment variable to determine where to install global packages
export npm_global_prefix=$NODE_ARTIFACTS_PATH/npm_global
export PATH="$npm_global_prefix/bin:$NODE_ARTIFACTS_PATH/nodejs/bin:$PATH"
hash -r

export NODE_OPTIONS="--trace-deprecation --trace-warnings"
