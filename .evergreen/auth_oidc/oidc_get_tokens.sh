#!/usr/bin/env bash
#
# Get the set of OIDC tokens in the OIDC_TOKEN_DIR.
#
set -ex
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

if [ -z "${OIDC_TOKEN_DIR:-}" ]; then
    export OIDC_TOKEN_DIR=/tmp/tokens
fi
if [ "Windows_NT" = "${OS:-}" ]; then
    export OIDC_TOKEN_DIR=$(cygpath -m $OIDC_TOKEN_DIR)
fi
mkdir -p $OIDC_TOKEN_DIR

pushd $SCRIPT_DIR
if [ ! -f "./secrets-export.sh" ]; then
    . ./setup-secrets.sh
else
    source ./secrets-export.sh
fi

. ./activate-authoidcvenv.sh
python ./oidc_get_tokens.py

cat <<EOF >> "secrets-export.sh"
export OIDC_TOKEN_DIR=$OIDC_TOKEN_DIR
export OIDC_TOKEN_FILE=$OIDC_TOKEN_DIR/test_machine
EOF

popd
