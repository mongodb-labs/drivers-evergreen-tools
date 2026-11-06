#!/usr/bin/env bash
# Download the crypt_shared library (used by client-side encryption tests) without starting a server, and write its
# path to crypt-shared-expansion.yml (in the working directory).
#
# Inputs (environment):
#   CRYPT_SHARED_VERSION  Server version to download crypt_shared for (default: latest).
#   AWS_*                 Credentials for the private "latest" bucket (see DRIVERS-3628).

set -o errexit
set -o pipefail

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "${SCRIPT_DIR}/../handle-paths.sh"

# Ensure uv is available here.
. "${SCRIPT_DIR}/../ensure-uv.sh"
ensure_uv || exit 1

declare out_dir="${DRIVERS_TOOLS}/mongodb"
mkdir -p "${out_dir}"

uv run --project "${DRIVERS_TOOLS}/.evergreen" python "${DRIVERS_TOOLS}/.evergreen/mongodl.py" \
  --component crypt_shared \
  --version "${CRYPT_SHARED_VERSION:-latest}" \
  --out "${out_dir}" \
  --empty-is-error

declare lib
lib="$(find "${out_dir}" -type f -name 'mongo_crypt_v1.so' | head -n 1)"
if [[ -z "${lib}" ]]; then
  echo "Unable to find mongo_crypt_v1.so under ${out_dir}" 1>&2
  exit 1
fi

echo "CRYPT_SHARED_LIB_PATH: \"${lib}\"" >crypt-shared-expansion.yml
cat crypt-shared-expansion.yml
