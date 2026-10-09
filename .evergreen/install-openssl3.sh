#!/usr/bin/env bash
set -eu

# install-openssl3.sh
#
# Builds OpenSSL 3 into a local prefix and exports the environment needed to
# compile and run Python sdists that link against OpenSSL (e.g. cryptography).
#
# cryptography 47.0+ refuses to link against OpenSSL 1.1.x, and some hosts
# (RHEL 8 zSeries) only ship OpenSSL 1.1.1 with no 3.x package available, so
# this script compiles OpenSSL 3 from source.
#
# Must be sourced. Exports OPENSSL_DIR (used by openssl-sys to find the
# headers and libraries during the build) and LD_LIBRARY_PATH (so the
# compiled extension module can find libssl.so.3/libcrypto.so.3 at runtime).
# Idempotent: the build is skipped if the prefix already has an openssl
# binary. Invoked by ensure-build-deps.sh when the system OpenSSL is older
# than 3.0.

# Preserve the caller's SCRIPT_DIR: this script is sourced (by
# ensure-build-deps.sh), whose own save/restore of SCRIPT_DIR runs after this
# script returns.
_saved_script_dir=${SCRIPT_DIR:-}

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

OPENSSL_VERSION="3.5.4"
# The release tag's commit (the annotated tag's peeled head), pinned so that
# a moved or compromised tag cannot change the code the CI build executes.
OPENSSL_COMMIT="c1eeb9406b6142148f267594197d853403d10208"
OPENSSL_PREFIX="${OPENSSL_PREFIX:-"${DRIVERS_TOOLS}/.openssl3"}"

if [ ! -x "${OPENSSL_PREFIX}/bin/openssl" ]; then
  # One work directory for both the shim and the clone: git clone refuses a
  # target that is not an empty directory, so the shim must live outside the
  # clone target.
  work_dir=$(mktemp -d)
  build_dir="${work_dir}/openssl"
  shim_dir="${work_dir}/perl-shim"

  # OpenSSL's Makefile template requires the perl core module Time::Piece
  # (it parses the release tag's VERSION.dat RELEASE_DATE when generating the
  # Makefile), and the minimal perl on these hosts does not ship it — nor can
  # we install packages. Provide the small shim the template needs via
  # PERL5LIB. Contract for the pinned version: strptime($date, "%d %b %Y")
  # followed by strftime("%Y-%m-%d") on the result.
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

  # Shallow clone of the release tag rather than a tarball download: the CI
  # hosts' git transport to github.com is the same one used to fetch this
  # repository, and a clone avoids depending on the release-asset endpoint.
  git clone --depth 1 --branch "openssl-${OPENSSL_VERSION}" \
    -c advice.detachedHead=false \
    https://github.com/openssl/openssl.git "${build_dir}"

  # The shallow clone fetched the tag's head commit; verify it is the pinned
  # one. Returning out of this sourced script skips the exports, so a
  # mismatched tag cannot leave a broken (or unverified) prefix behind.
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
  # libdir=lib (rather than the lib64 that ./config picks on 64-bit hosts)
  # keeps the libraries at the path openssl-sys expects below OPENSSL_DIR.
  #
  # no-asm: OpenSSL's perlasm assembly generators need more core perl than
  # the minimal hosts ship (s390x.pm alone requires bigint), and the driver
  # tests don't need the assembly's performance. With no-asm the only perl
  # the build runs is the Makefile generation, which the shim above covers.
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

# Verify the binary works. This is the script's last command so that a failed
# build fails the script even when errexit is suppressed while sourcing it.
"${OPENSSL_PREFIX}/bin/openssl" version
