#!/usr/bin/env bash
set -eu

# install-openssl3.sh
#
# Builds OpenSSL 3 into a local prefix and exports the environment needed to
# compile and run Python sdists that link against OpenSSL (e.g. cryptography).
#
# cryptography publishes no wheels for s390x, so the activate scripts build
# its sdist from source. cryptography 47.0+ refuses to link against OpenSSL
# 1.1.x, and the RHEL 8 zSeries hosts only ship OpenSSL 1.1.1 (with no 3.x
# package available for s390x), so this script compiles OpenSSL 3 from source.
#
# Must be sourced. Exports OPENSSL_DIR (used by openssl-sys to find the
# headers and libraries during the build) and LD_LIBRARY_PATH (so the
# compiled extension module can find libssl.so.3/libcrypto.so.3 at runtime).
# Idempotent: the build is skipped if the prefix already has an openssl
# binary. Only call it where the system OpenSSL is older than 3.0 (currently
# the s390x/zSeries hosts).

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

OPENSSL_VERSION="3.5.4"
OPENSSL_PREFIX="${OPENSSL_PREFIX:-"${DRIVERS_TOOLS}/.openssl3"}"

if [ ! -x "${OPENSSL_PREFIX}/bin/openssl" ]; then
  # OpenSSL's build system requires perl.
  if ! command -v perl >/dev/null 2>&1; then
    sudo yum install -y perl-core < /dev/null > /dev/null
  fi

  build_dir=$(mktemp -d)
  curl --retry 8 -sSf -o "${build_dir}/openssl.tar.gz" \
    "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
  tar -xzf "${build_dir}/openssl.tar.gz" -C "${build_dir}" --strip-components=1

  pushd "${build_dir}"
  # libdir=lib (rather than the lib64 that ./config picks on 64-bit hosts)
  # keeps the libraries at the path openssl-sys expects below OPENSSL_DIR.
  ./config --prefix="${OPENSSL_PREFIX}" --openssldir="${OPENSSL_PREFIX}/ssl" --libdir=lib
  make -j"$(nproc)" build_sw
  make install_sw
  popd

  rm -rf "${build_dir}"
fi

echo "openssl location: ${OPENSSL_PREFIX}/bin/openssl"

export OPENSSL_DIR="${OPENSSL_PREFIX}"
export LD_LIBRARY_PATH="${OPENSSL_PREFIX}/lib:${LD_LIBRARY_PATH:-}"

# Verify the binary works. This is the script's last command so that a failed
# build fails the script even when errexit is suppressed while sourcing it.
"${OPENSSL_PREFIX}/bin/openssl" version
