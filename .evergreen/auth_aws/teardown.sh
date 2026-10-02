#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

echo "Tearing down auth_aws..."
pushd $SCRIPT_DIR >/dev/null

# If we've gotten credentials, ensure the instance profile is set.
if [ -f secrets-export.sh ]; then
  . $SCRIPT_DIR/../ensure-uv.sh
  ensure_uv || exit 1
  source secrets-export.sh
  # The auth_aws group is defined in the root pyproject.toml, so run from the
  # root project context. DRIVERS_TOOLS is set absolutely by handle-paths.sh.
  uv run --project "$DRIVERS_TOOLS" --group auth_aws python ./lib/aws_assign_instance_profile.py || true
fi

popd >/dev/null

echo "Tearing down auth_aws.. done."
