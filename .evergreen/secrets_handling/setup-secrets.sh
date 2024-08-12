#!/usr/bin/env bash
# Secrets setup script.  It will write the secrets into the calling
# directory as `secrets-export.sh`.
#
# Run with a . to add environment variables to the current shell:
#
# . ../secrets_handling/setup-secrets.sh drivers/<vault_name>
#
# More than one vault can be provided as extra arguments.
# All of the variables will be written to the same file.
set -eu

ORIG_SCRIPT_DIR=${SCRIPT_DIR:-}
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR/../auth_aws > /dev/null
. ./activate-authawsvenv.sh
popd > /dev/null

ALL_ARGS="$@"
echo "Getting secrets: ${ALL_ARGS}..."
python $SCRIPT_DIR/setup_secrets.py $ALL_ARGS
source $(pwd)/secrets-export.sh
echo "Getting secrets: $ALL_ARGS... done."

# Restore the script dir if we've overridden it.
if [ -n "${ORIG_SCRIPT_DIR}" ]; then
    SCRIPT_DIR=$ORIG_SCRIPT_DIR
fi
