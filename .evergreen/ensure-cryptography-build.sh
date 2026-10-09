#!/usr/bin/env bash
#
# Ensures the toolchain for building cryptography's sdist, which uv needs on
# s390x (no published wheels): a Rust toolchain, and OpenSSL 3 where the
# system library is older than 3.0.
#
# Must be sourced; safe to source repeatedly. Restores the caller's SCRIPT_DIR
# and shell options, and its final status reflects whether the toolchain could
# be ensured.

# cryptography's minimum supported Rust version (its Cargo.toml rust-version).
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

# The save variable names are unique to this script: install-rust.sh saves
# SCRIPT_DIR in `_saved_script_dir` and unsets it before it returns.
_saved_cryptography_script_dir=${SCRIPT_DIR:-}
_saved_cryptography_opts=$-
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

_status=0
if [ "$(uname -m)" = "s390x" ]; then
    # Install Rust when no toolchain at least cryptography's MSRV is on PATH.
    _rustc_version=$(rustc --version 2>/dev/null | awk '{print $2}')
    if ! command -v cargo >/dev/null 2>&1 \
       || [ -z "$_rustc_version" ] \
       || ! version_at_least "$_rustc_version" "$MIN_RUST_VERSION"; then
        echo "Installing Rust toolchain (no cargo >= $MIN_RUST_VERSION found)"
        . "$SCRIPT_DIR/install-rust.sh" || _status=1
        # Re-validate: a failed install leaves an older system rustc first on
        # PATH, which the cryptography build would reject much later.
        _rustc_version=$(rustc --version 2>/dev/null | awk '{print $2}')
        if ! version_at_least "${_rustc_version:-}" "$MIN_RUST_VERSION"; then
            echo "ERROR: no rustc >= $MIN_RUST_VERSION available (found: ${_rustc_version:-none})" >&2
            _status=1
        fi
    fi

    # cryptography 47.0+ refuses to link against OpenSSL 1.1.x.
    if [ "$(openssl version 2>/dev/null | awk 'END { print int($2) }')" -lt 3 ]; then
        echo "No system OpenSSL >= 3.0: building OpenSSL into a local prefix"
        . "$SCRIPT_DIR/install-openssl3.sh" || _status=1
    fi
fi

# Restore what this script clobbered while sourcing its helpers. A caller
# without SCRIPT_DIR gets it unset again, so later sourced scripts fail
# loudly under nounset instead of resolving against this directory.
if [ -n "${_saved_cryptography_script_dir:-}" ]; then
    SCRIPT_DIR=$_saved_cryptography_script_dir
else
    unset SCRIPT_DIR
fi
unset _rustc_version
[[ "$_saved_cryptography_opts" == *a* ]] || set +a
[[ "$_saved_cryptography_opts" == *e* ]] || set +e
[[ "$_saved_cryptography_opts" == *u* ]] || set +u

[ "$_status" -eq 0 ]
