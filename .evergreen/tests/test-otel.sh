#!/usr/bin/env bash

# Test the OTel span-export orchestration configuration (DRIVERS-3454).
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
. $SCRIPT_DIR/../ensure-uv.sh

pushd $SCRIPT_DIR/.. > /dev/null

ensure_uv || exit 1

# Unit tests for the injection and gating helpers.
pushd orchestration > /dev/null
uv run python -m unittest test_drivers_orchestration -v
popd > /dev/null

bash install-cli.sh "$(pwd)/orchestration"

# Fail-fast checks: incompatible combinations must error with the expected
# message -- a bare non-zero exit could also be an unrelated crash (e.g. an
# ImportError) masquerading as a working gate.
assert_gate_rejects() {
  local expected="$1"
  shift
  local output
  if output=$("$@" 2>&1); then
    echo "ERROR: '$*' should have failed"
    exit 1
  fi
  if ! echo "$output" | grep -q "$expected"; then
    echo "ERROR: '$*' failed for the wrong reason (expected '$expected'):"
    echo "$output"
    exit 1
  fi
}

assert_gate_rejects "requires MongoDB 9.0" \
  env OTEL=1 ./orchestration/drivers-orchestration run --version 8.0
assert_gate_rejects "local-atlas" \
  env OTEL=1 ./orchestration/drivers-orchestration run --version latest --local-atlas
assert_gate_rejects "DOCKER_RUNNING" \
  env OTEL=1 DOCKER_RUNNING=true ./orchestration/drivers-orchestration run --version latest

# The authoritative version gate probes the binary that will actually run: a
# real 8.0 binary via --existing-binaries-dir must be rejected before the
# remaining downloads and the deployment.
EXISTING_BIN_80=mongodl_otel_test_80
rm -rf ${EXISTING_BIN_80}
uv run python mongodl.py --edition enterprise --version 8.0 --component archive --out ${EXISTING_BIN_80} --strip-path-components 2 --cache-dir "${DRIVERS_TOOLS}/.local/cache" --retries 5
assert_gate_rejects "mongod binary reports db version v8.0" \
  env OTEL=1 ./orchestration/drivers-orchestration run --existing-binaries-dir=${EXISTING_BIN_80}
rm -rf ${EXISTING_BIN_80}

# Live sharded cluster through --existing-binaries-dir, in one leg:
# - mongos must accept the injected setParameters (router entries hold proc
#   params directly, without a procParams wrapper);
# - per-port trace directories for routers and shard members;
# - --version 8.0 is deliberate: the probed binary is authoritative and a
#   stale requested version must not veto a compatible 9.0+ build
#   (--skip-crypt-shared avoids downloading the only 8.0 artifact the
#   version would otherwise select).
EXISTING_BIN_LATEST=otel_existing_bin_test
rm -rf ${EXISTING_BIN_LATEST}
uv run python mongodl.py --edition enterprise --version latest --component archive --out ${EXISTING_BIN_LATEST} --strip-path-components 2 --cache-dir "${DRIVERS_TOOLS}/.local/cache" --retries 5
OTEL=1 ./orchestration/drivers-orchestration run --topology sharded_cluster --existing-binaries-dir=${EXISTING_BIN_LATEST} --version 8.0 --skip-crypt-shared
grep -q '^OTEL_TRACE_DIR=' mo-expansion.sh
# shellcheck disable=SC1091
. ./mo-expansion.sh
test -n "${OTEL_TRACE_DIR}"
# Per-port directories for the mongos (27017) and a shard member (27217).
test -d "${OTEL_TRACE_DIR}/27017"
test -d "${OTEL_TRACE_DIR}/27217"
# getParameter against the mongos itself: the router's own parameters.
$MONGODB_BINARIES/mongosh "mongodb://localhost:27017" --eval '
  const p = db.adminCommand({
    getParameter: 1,
    opentelemetryTraceDirectory: 1,
    openTelemetryExternalTracing: 1,
    openTelemetryTracingSampling: 1,
    openTelemetryTracingFileFlushCount: 1,
  });
  if (!p.opentelemetryTraceDirectory.endsWith("27017") ||
      p.openTelemetryExternalTracing.tokenBucketRateLimit.maxTokens !== 1000 ||
      p.openTelemetryTracingSampling.defaultSampling.samplingFactor !== 1.0 ||
      p.openTelemetryTracingFileFlushCount !== 1) {
    throw new Error("unexpected OTel parameters on mongos: " + JSON.stringify(p));
  }
  print("OTEL_MONGOS_PARAMS_OK");
' | grep -q OTEL_MONGOS_PARAMS_OK
./orchestration/drivers-orchestration stop
rm -rf ${EXISTING_BIN_LATEST}

# Same flow through the preferred mongodb-runner entry point (run-mongodb.sh):
# the runner translates procParams.setParameter into --setParameter args, so
# the injected OTel parameters must be applied there too.
OTEL=1 MONGODB_VERSION=latest bash ./run-mongodb.sh start
# run() silently falls back to mongo-orchestration when mongodb-runner is
# unsupported on the host, which would make the assertions below meaningless
MO_HOME=${MONGO_ORCHESTRATION_HOME:-${DRIVERS_TOOLS}/.evergreen/orchestration}
if ! uv run python -c "import json; json.load(open('${MO_HOME}/out.log'))" 2>/dev/null; then
  echo "ERROR: mongodb-runner path fell back to mongo-orchestration"
  exit 1
fi
# shellcheck disable=SC1091
. ./mo-expansion.sh
test -n "${OTEL_TRACE_DIR}"
test -d "${OTEL_TRACE_DIR}/27017"
$MONGODB_BINARIES/mongosh "mongodb://localhost:27017/?directConnection=true" --eval '
  const p = db.adminCommand({
    getParameter: 1,
    opentelemetryTraceDirectory: 1,
    openTelemetryExternalTracing: 1,
    openTelemetryTracingFileFlushCount: 1,
  });
  if (!p.opentelemetryTraceDirectory.endsWith("27017") ||
      p.openTelemetryExternalTracing.tokenBucketRateLimit.maxTokens !== 1000 ||
      p.openTelemetryTracingFileFlushCount !== 1) {
    throw new Error("unexpected OTel parameters via mongodb-runner: " + JSON.stringify(p));
  }
  print("OTEL_RUNNER_PARAMS_OK");
' | grep -q OTEL_RUNNER_PARAMS_OK
bash ./run-mongodb.sh stop

# Opt-in regression: without OTEL, no trace dir and no expansion entry.
./orchestration/drivers-orchestration run --version latest
if ! grep -q '^OTEL_TRACE_DIR=""$' mo-expansion.sh; then
  echo "ERROR: OTEL_TRACE_DIR should be exported as empty without OTEL=1 (to clear stale values)"
  exit 1
fi
if [ -d "${DRIVERS_TOOLS}/otel" ]; then
  echo "ERROR: otel directory created without OTEL=1"
  exit 1
fi
./orchestration/drivers-orchestration stop

popd > /dev/null
# Overwrite the placeholder FAIL result seeded by setup.sh with a PASS entry.
make -C ${DRIVERS_TOOLS} test
echo "OTel orchestration test... done."
