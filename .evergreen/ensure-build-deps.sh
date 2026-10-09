#!/usr/bin/env bash
#
# ensure-build-deps.sh
#
# Ensures the toolchain needed to build Python sdists that compile native
# extensions against OpenSSL (e.g. cryptography) on hosts where no prebuilt
# wheels exist.
#
# Must be sourced; safe to source repeatedly. Restores the caller's
# SCRIPT_DIR and shell options before returning, and its final status
# reflects whether the dependencies could be ensured.
#
# Nothing is done on platforms with prebuilt wheels. For each arch in
# KNOWN_NO_WHEEL_ARCHES it:
#   - installs a Rust toolchain (via install-rust.sh) if cargo is missing or
#     older than cryptography's MSRV, and
#   - builds OpenSSL 3 into a local prefix (via install-openssl3.sh,
#     exporting OPENSSL_DIR and LD_LIBRARY_PATH for the build) if the system
#     OpenSSL is older than 3.0.

# Arches where cryptography publishes no wheels, so uv builds the sdist from
# source. Extend this list as new arches need support.
KNOWN_NO_WHEEL_ARCHES="s390x"

# cryptography's minimum supported Rust version (its Cargo.toml
# rust-version). A system toolchain older than this cannot build the sdist.
MIN_RUST_VERSION="1.83.0"

# Returns 0 if dot-separated version $1 is at least $2.
version_at_least() {
    local version=${1%%[!0-9.]*}
    local -a lhs rhs
    IFS='.' read -r -a lhs <<< "$version"
    IFS='.' read -r -a rhs <<< "$2"
    local i
    for i in 0 1 2; do
        [ "${lhs[i]:-0}" -gt "${rhs[i]:-0}" ] && return 0
        [ "${lhs[i]:-0}" -lt "${rhs[i]:-0}" ] && return 1
    done
    return 0
}

# The save variables use names unique to this script: its helpers
# (install-rust.sh) save SCRIPT_DIR in `_saved_script_dir` and unset it
# before returning, which would destroy this script's own saved value and
# leak `.evergreen` as SCRIPT_DIR into the caller.
_ebd_saved_script_dir=${SCRIPT_DIR:-}
_ebd_saved_opts=$-
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

_status=0
for _arch in $KNOWN_NO_WHEEL_ARCHES; do
    [ "$(uname -m)" = "$_arch" ] || continue

    # Rust: install if there is no usable toolchain. install-rust.sh installs
    # a current rustup-managed toolchain and puts it first on PATH.
    _rustc_version=$(rustc --version 2>/dev/null | awk '{print $2}')
    if ! command -v cargo >/dev/null 2>&1 \
       || [ -z "$_rustc_version" ] \
       || ! version_at_least "$_rustc_version" "$MIN_RUST_VERSION"; then
        echo "Installing Rust toolchain for $_arch (no cargo >= $MIN_RUST_VERSION found)"
        . "$SCRIPT_DIR/install-rust.sh" || _status=1
        # Re-validate whatever toolchain is first on PATH now: a failed
        # install leaves an older system rustc resolvable (install-rust.sh's
        # final cargo --version accepts any binary), and the cryptography
        # build would only reject it much later, and cryptically.
        _rustc_version=$(rustc --version 2>/dev/null | awk '{print $2}')
        if ! version_at_least "${_rustc_version:-}" "$MIN_RUST_VERSION"; then
            echo "ERROR: no rustc >= $MIN_RUST_VERSION available (found: ${_rustc_version:-none})" >&2
            _status=1
        fi
    fi

    # OpenSSL 3: build locally if the system library is older. cryptography
    # 47.0+ refuses to link against OpenSSL 1.1.x.
    if [ "$(openssl version 2>/dev/null | awk 'END { print int($2) }')" -lt 3 ]; then
        echo "No system OpenSSL >= 3.0: building OpenSSL into a local prefix"
        . "$SCRIPT_DIR/install-openssl3.sh" || _status=1
    fi
done

# Restore what this script clobbered while sourcing its helpers. A caller
# without SCRIPT_DIR gets it unset again (rather than left pointing here), so
# later sourced scripts fail loudly on it under nounset instead of silently
# resolving against this directory.
if [ -n "${_ebd_saved_script_dir:-}" ]; then
    SCRIPT_DIR=$_ebd_saved_script_dir
else
    unset SCRIPT_DIR
fi
unset _ebd_saved_script_dir _arch _rustc_version
# handle-paths.sh re-enables allexport for its .env handling and leaves it on;
# the caller did not necessarily have it set.
[[ "$_ebd_saved_opts" == *a* ]] || set +a
[[ "$_ebd_saved_opts" == *e* ]] || set +e
[[ "$_ebd_saved_opts" == *u* ]] || set +u

# Final status: propagates any failure to the sourcing shell (whose
# `. ensure-build-deps.sh || return` catches it), since the individual
# scripts' failures are otherwise absorbed by the suppression of errexit
# while sourcing.
[ "$_status" -eq 0 ]
