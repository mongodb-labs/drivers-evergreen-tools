# AGENTS.md

Instructions for coding agents working in this repository. Read [README.md](./README.md)
(what this repo is, how drivers consume it) and [CONTRIBUTING.md](./CONTRIBUTING.md)
(server-version and Python support policy, new-feature process) first; this file assumes
both and adds only what an agent needs to act.

## What this repo is

Drivers bootstrap their Evergreen CI configuration from this repo. It contains scripts for
downloading MongoDB, launching topologies, and other tasks most drivers need. See
[README.md](./README.md) for how drivers consume it, and
[https://evergreen.mongodb.com/waterfall/drivers-tools](https://evergreen.mongodb.com/waterfall/drivers-tools)
for the CI that runs it.

## Repo layout

- Root: `Makefile`, `CONTRIBUTING.md`, `README.md`, `ruff.toml`, `.pre-commit-config.yaml`.
- `.evergreen/pyproject.toml` packages `mongodl`, `mongosh-dl`, and `socks5srv`.
- `.evergreen/<feature>/`: one subfolder per feature (e.g. `csfle`, `atlas`, `auth_oidc`,
  `k8s`), each with its own README and scripts. New features follow this layout; see
  [CONTRIBUTING.md#new-features](./CONTRIBUTING.md#new-features).
- `.evergreen/orchestration/`: the MongoDB server/topology launcher. Has its own
  `pyproject.toml` and its own dependency lockfile (`uv.lock`), independent of
  `.evergreen/pyproject.toml`.
- `.evergreen/tests/`: `test-<feature>.sh` scripts. These are the test suite (see Testing
  below), run as Evergreen tasks, not a pytest suite.

## Prerequisites

- `DRIVERS_TOOLS`: expected to point at the repo root. Several scripts read it.
- `.evergreen/find-python3.sh`: sourced by scripts that need a Python interpreter. A
  handful of older scripts still use its `find_python3`/`venvcreate` path instead of `uv`.
- `.evergreen/ensure-uv.sh` (`ensure_uv`): installs or locates `uv`. In CI it scopes uv's
  cache, tool, and Python install dirs under the task's temp directory; outside CI it
  only redirects the tool dir, so a local `uv tool install --force` can't overwrite
  globally installed tools, and the cache stays shared to avoid re-downloading.
- `uv` runs most Python scripts (`uv run`) and manages CLI installs, but not all: some
  scripts (`.evergreen/clean.sh`) call `python3` directly, and some features (`auth_aws`)
  still use the legacy `find-python3.sh`/`venvcreate` virtual environments. Check the
  script before assuming uv isolation.

## Running things

- `make run-server` or `make run-local-atlas` starts a MongoDB deployment.
- `make stop-server` stops it.
- `make test-connect` checks connectivity to a running deployment
  (`.evergreen/check-connection.sh`).
- `make clean` removes generated files (`.evergreen/clean.sh`).
- `make test` is a legacy stub: it prints a canned pass and writes a placeholder
  `test-results.json`. `.evergreen/tests/test-cli.sh` calls it directly as live CI
  behavior, so it can't be changed. It proves nothing about a change.

## Python CLIs

Two independently packaged CLI projects, both installed with
`bash .evergreen/install-cli.sh <dir>` (uv-managed, isolated):

- `.evergreen/pyproject.toml` packages `mongodl`, `mongosh-dl`, `socks5srv`.
- `.evergreen/orchestration/pyproject.toml` packages `drivers-orchestration`.

Everything else under `.evergreen/` is an unpackaged script. Check the script and its
feature directory for a setup wrapper (e.g. `auth_aws/activate-authawsvenv.sh`) before
running it: some import dependencies (`pymongo`) that only exist in a feature-specific
virtual environment, so a direct `python3 <path>.py --help` fails on import first.

Not everything under `.evergreen/` is Python: `.evergreen/github_app/` is an npm project
(its own `package.json`, linted separately), and `.evergreen/mongoproxy/` and
`.evergreen/perfcomp/` are Go modules (their own `go.mod`, tested with `go test ./...`).

## Testing

There is no pytest suite. Validation is:

- `.evergreen/tests/test-*.sh`: one script per feature area, run as Evergreen tasks.
- `.github/workflows/tests.yml`: GitHub Actions test workflow.
- `.github/workflows/markdown.yml`: checks for broken relative links in Markdown files.

Outside that, `.evergreen/mongoproxy/` and `.evergreen/perfcomp/` have their own Go tests
(`go test ./...`, per each folder's README), and `.github/scripts/test_*.py` has its own
unittest suite, run by the `bump-version` job in `tests.yml`.

## Pre-commit and linting

`make lint` is the validation entry point. There is no `just`, no `justfile`, and no mypy
step in this repo; conventions from other repos don't carry over.

- Run `make install` once to set up `pre-commit`. It installs `pre-commit` into `.bin/`
  under this checkout using `uv`, not globally. The `PATH` change lives only inside the
  Make recipe, so a bare `pre-commit` command never resolves in your shell; use
  `make lint` instead.
- `make lint` runs `pre-commit run --all-files`. Many hooks auto-fix in place, so a run
  that modifies files exits non-zero even though it fixed the problem; re-run `make lint`
  to confirm clean. There is no separate fix mode.
- `make lint HOOK=<hook-id>` runs a single hook, e.g. `make lint HOOK=shellcheck`.

Run `make lint` before opening a PR.

## Adding a new feature

Per [CONTRIBUTING.md#new-features](./CONTRIBUTING.md#new-features): add a folder under
`.evergreen/<feature>/` with a `README.md` (usage instructions, example Evergreen config
where relevant) and a test file at `.evergreen/tests/test-<feature>.sh`, wired up as a
dedicated Evergreen task. Tag it `pr` if it's self-contained enough to run on every PR.

## PR requirements

- Title references a JIRA ticket; see `.github/pull_request_template.md`.
- Body fills in Summary, Changes in this PR, and Test Plan.
- Run `make lint` first. CI checks the same things in its own `pre-commit` job, but also
  runs a deployment test matrix, `eslint` on `.evergreen/github_app/`, and the
  `.github/scripts/test_*.py` unittest suite; `make lint` doesn't cover those.

## Gotchas

- Gitignored build artifacts (venvs, `uv` caches, downloaded binaries) aren't source.
  Their presence or absence isn't a signal about what changed.
- Shell scripts need a shebang and the executable bit; Evergreen invokes them directly.
- The CI matrix includes Windows. Don't assume Unix-only behavior for path separators,
  `cygpath`, or case sensitivity.
