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

# Fail-fast checks: incompatible combinations must error before any download.
if OTEL=1 ./orchestration/drivers-orchestration run --version 8.0 2>/dev/null; then
  echo "ERROR: OTEL=1 with server 8.0 should have failed"
  exit 1
fi
if OTEL=1 ./orchestration/drivers-orchestration run --version latest --local-atlas 2>/dev/null; then
  echo "ERROR: OTEL=1 with --local-atlas should have failed"
  exit 1
fi
if OTEL=1 DOCKER_RUNNING=true ./orchestration/drivers-orchestration run --version latest 2>/dev/null; then
  echo "ERROR: OTEL=1 with DOCKER_RUNNING should have failed"
  exit 1
fi

# Live run: the OTel parameters must be applied and the trace dir exported.
OTEL=1 ./orchestration/drivers-orchestration run --version latest

grep -q '^OTEL_TRACE_DIR=' mo-expansion.sh
# shellcheck disable=SC1091
. ./mo-expansion.sh
test -d "${OTEL_TRACE_DIR}/27017"

$MONGODB_BINARIES/mongosh "mongodb://localhost:27017/?directConnection=true" --eval '
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
    throw new Error("unexpected OTel parameters: " + JSON.stringify(p));
  }
  print("OTEL_PARAMS_OK");
' | grep -q OTEL_PARAMS_OK

./orchestration/drivers-orchestration stop

# Opt-in regression: without OTEL, no trace dir and no expansion entry.
./orchestration/drivers-orchestration run --version latest
if grep -q OTEL_TRACE_DIR mo-expansion.sh; then
  echo "ERROR: OTEL_TRACE_DIR exported without OTEL=1"
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
