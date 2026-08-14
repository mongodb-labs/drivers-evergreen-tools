#!/usr/bin/env bash
#
# The stub interpreter behind make_python in test-ensure-uv.sh. Each stub is a
# small wrapper that exports the variables below and execs this script, so the
# behavior lives in one place instead of a heredoc.
#
# It answers only what ensure_uv asks of an interpreter:
#
#   STUB_VERSION    version to report, e.g. 3.9.2
#   STUB_CAPS       comma-separated capabilities: pip, venv
#   STUB_USER_BASE  directory to report as `-m site --user-base`
#   STUB_ORIGIN     the interpreter this stub stands for, carried into any uv it
#                   installs so a case can assert which candidate was chosen
set -u

version="${STUB_VERSION:?}"
caps="${STUB_CAPS:?}"
user_base="${STUB_USER_BASE:?}"
origin="${STUB_ORIGIN:?}"
major_minor="${version%.*}"

# uv publishes no distribution below Python 3.8, so an older interpreter fails
# here the way it does on a real host: pip and venv both find nothing.
supports_uv() {
  [ "$(printf '%s\n' 3.8 "$major_minor" | sort -V | head -n1)" = "3.8" ]
}

has() { case ",$caps," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

no_distribution() {
  echo "ERROR: Could not find a version that satisfies the requirement uv (from versions: none)" >&2
  echo "ERROR: No matching distribution found for uv" >&2
  exit 1
}

# Drop a working uv into $1, the way a successful install would.
install_uv_into() {
  mkdir -p "$1"
  {
    printf '#!/bin/sh\n'
    printf 'echo "uv 0.12.3 (from %s)"\n' "$origin"
  } >"$1/uv"
  chmod +x "$1/uv"
}

# Seed $1 with an interpreter that installs into the venv's own bin. It always
# has pip, even when the base one did not: seeding pip through ensurepip is why
# a host with venv but no pip can still get uv. $origin carries through, so the
# uv a venv installs still names the interpreter the venv was built from.
make_venv_python() {
  declare venv_dir="$1"
  mkdir -p "$venv_dir/bin"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'export STUB_VERSION=%q STUB_CAPS=%q STUB_USER_BASE=%q STUB_ORIGIN=%q\n' \
      "$version" "pip,venv" "$venv_dir" "$origin"
    printf 'exec %q "$@"\n' "$0"
  } >"$venv_dir/bin/python"
  chmod +x "$venv_dir/bin/python"
}

case "${1:-}" in
--version)
  echo "Python $version"
  ;;
-m)
  case "${2:-}" in
  site)
    echo "$user_base"
    ;;
  pip)
    has pip || exit 1
    if [ "${3:-}" = "--version" ]; then
      echo "pip 24.0 from $user_base (python $version)"
      exit 0
    fi
    # Anything other than an install of uv, e.g. upgrading pip, is a no-op.
    for arg in "$@"; do
      if [ "$arg" = "uv" ]; then
        supports_uv || no_distribution
        install_uv_into "$user_base/bin"
        exit 0
      fi
    done
    ;;
  venv)
    has venv || exit 1
    supports_uv || no_distribution
    # The venv directory is the last argument.
    make_venv_python "${*: -1}"
    ;;
  *)
    exit 1
    ;;
  esac
  ;;
*)
  exit 1
  ;;
esac
