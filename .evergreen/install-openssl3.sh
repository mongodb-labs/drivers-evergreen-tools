#!/usr/bin/env bash
set -eu

# Builds OpenSSL 3 into a local prefix and exports OPENSSL_DIR and
# LD_LIBRARY_PATH for building and running packages that link against it:
# cryptography 47.0+ refuses OpenSSL 1.1.x, and RHEL 8 zSeries ships only
# 1.1.1 with no 3.x package available.
#
# Must be sourced; the build is skipped when the prefix already has an
# openssl binary. Invoked by ensure-cryptography-build.sh.

# Preserve the caller's SCRIPT_DIR: this script is sourced.
_saved_script_dir=${SCRIPT_DIR:-}

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

OPENSSL_VERSION="3.5.4"
# The annotated tag's peeled head, so a moved tag cannot change what CI builds.
OPENSSL_COMMIT="c1eeb9406b6142148f267594197d853403d10208"
OPENSSL_PREFIX="${OPENSSL_PREFIX:-"${DRIVERS_TOOLS}/.openssl3"}"

if [ ! -x "${OPENSSL_PREFIX}/bin/openssl" ]; then
  # git clone refuses a non-empty target, so the shim lives outside the clone.
  work_dir=$(mktemp -d)
  build_dir="${work_dir}/openssl"
  shim_dir="${work_dir}/perl-shim"

  # The Makefile template needs Time::Piece (core perl, absent from the
  # minimal hosts, not installable); shim its strptime/strftime usage.
  mkdir -p "${shim_dir}/Time"
  cat > "${shim_dir}/Time/Piece.pm" <<'EOF'
package Time::Piece;
use strict;
use warnings;

my @Months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my %MonthNumber = map { $Months[$_] => $_ + 1 } 0 .. 11;

sub new { my ($class, %fields) = @_; return bless \%fields, $class }

sub strptime {
    my ($class, $date, $format) = @_;
    die "Time::Piece shim: unsupported format '$format'"
        unless $format eq '%d %b %Y';
    my ($mday, $month, $year) =
        $date =~ /^\s*(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s*$/
        or die "Time::Piece shim: cannot parse date '$date'";
    my $mon = $MonthNumber{$month}
        or die "Time::Piece shim: unknown month '$month'";
    return $class->new(year => $year, mon => $mon, mday => $mday);
}

sub strftime {
    my ($self, $format) = @_;
    die "Time::Piece shim: unsupported format '$format'"
        unless $format eq '%Y-%m-%d';
    return sprintf '%04d-%02d-%02d', @$self{qw(year mon mday)};
}

1;
EOF
  PERL5LIB="${shim_dir}${PERL5LIB:+:${PERL5LIB}}"
  export PERL5LIB

  # Shallow clone: same git transport as this repository, no release assets.
  git clone --depth 1 --branch "openssl-${OPENSSL_VERSION}" \
    -c advice.detachedHead=false \
    https://github.com/openssl/openssl.git "${build_dir}"

  # Enforce the pin; the return skips the exports, leaving no prefix behind.
  _pinned_head=$(git -C "${build_dir}" rev-parse HEAD)
  if [ "${_pinned_head}" != "${OPENSSL_COMMIT}" ]; then
    echo "ERROR: openssl-${OPENSSL_VERSION} resolved to ${_pinned_head}, expected ${OPENSSL_COMMIT}" >&2
    rm -rf "${work_dir}"
    # The restore at the script's end is skipped by this early return.
    if [ -n "${_saved_script_dir:-}" ]; then
      SCRIPT_DIR=$_saved_script_dir
    else
      unset SCRIPT_DIR
    fi
    unset _saved_script_dir
    return 1
  fi
  unset _pinned_head

  pushd "${build_dir}"
  # libdir=lib keeps the libraries where openssl-sys expects them.
  # no-asm: the perlasm generators need more perl core than these hosts ship;
  # this leaves the Makefile generation as the only perl the build runs.
  ./config no-asm --prefix="${OPENSSL_PREFIX}" --openssldir="${OPENSSL_PREFIX}/ssl" --libdir=lib
  make -j"$(nproc)" build_sw
  make install_sw
  popd

  rm -rf "${work_dir}"
fi

echo "openssl location: ${OPENSSL_PREFIX}/bin/openssl"

export OPENSSL_DIR="${OPENSSL_PREFIX}"
export LD_LIBRARY_PATH="${OPENSSL_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Restore the caller's SCRIPT_DIR (clobbered above and by handle-paths.sh).
if [ -n "${_saved_script_dir:-}" ]; then
  SCRIPT_DIR=$_saved_script_dir
fi
unset _saved_script_dir

# Last command: a failed build must fail the script despite the sourcing's
# suppressed errexit.
"${OPENSSL_PREFIX}/bin/openssl" version
