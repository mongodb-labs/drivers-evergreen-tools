# Drivers Orchestration

Scripts to manage MongoDB server deployments for driver testing, used by
[run-orchestration.sh](../run-orchestration.sh). See the repository
[README](../../README.md) for general usage.

## OpenTelemetry trace export (MongoDB 9.0+)

For the trace-context propagation prose tests
([DRIVERS-3454](https://jira.mongodb.org/browse/DRIVERS-3454)), orchestration
can start every `mongod`/`mongos` defined in the orchestration config
(config servers that mongo-orchestration synthesizes itself are not covered)
with the server's OpenTelemetry file exporter enabled:

```bash
OTEL=1 MONGODB_VERSION=latest TOPOLOGY=server \
  bash .evergreen/run-orchestration.sh
```

This requires MongoDB 9.0+ (the setParameters do not exist on older servers)
and a locally orchestrated cluster: the file exporter has no wire protocol,
so the test runner must share a filesystem with the server processes.
Orchestration fails fast if `OTEL` is combined with an older version,
`DOCKER_RUNNING`, `--local-atlas`, or `--mongodb-runner`.

Span export additionally requires a mongod binary compiled with OpenTelemetry support (the server's span-export tests are tagged `requires_otel_build`). On builds without it, the parameters are accepted but no span files are written — orchestration cannot detect this, so run the prose tests against an OTel-enabled 9.0+ build.

Each cluster member writes OTLP JSON span batches (one batch per line,
NDJSON) into its own per-port directory:

```
$DRIVERS_TOOLS/otel/          <- exported as OTEL_TRACE_DIR
├── 27017/
├── 27018/
└── 27019/
```

`OTEL_TRACE_DIR` is written to `mo-expansion.sh` / `mo-expansion.yml`
alongside `MONGODB_URI`. Driver test suites should:

- Skip the prose test when `OTEL_TRACE_DIR` is unset or empty (this covers
  every environment that did not opt in — no same-host detection needed).
- Enable `OTEL` only in a dedicated task or variant pinned to
  `VERSION: latest`, never in a shared orchestration function — the version
  fail-fast will break every variant pinned below 9.0 otherwise.
- Poll for span files with a generous timeout (e.g. 30 s) rather than a
  single sleep: the exporter flushes every
  `openTelemetryTracingBatchExportIntervalMillis` (default 1000 ms).
- Read files recursively under `OTEL_TRACE_DIR`; match server spans to
  client spans by hex `traceId` / `parentSpanId`.

The directory is wiped at the start of each orchestration run. To upload the
traces as task artifacts on failure, add to the driver project's Evergreen
config:

```yaml
- command: archive.targz_pack
  params:
    target: "otel-traces.tar.gz"
    source_dir: "${DRIVERS_TOOLS}/otel"
    include: ["./**"]
- command: s3.put
  params:
    aws_key: ${aws_key}
    aws_secret: ${aws_secret}
    local_file: otel-traces.tar.gz
    remote_file: ${UPLOAD_BUCKET}/${build_variant}/${revision}/${version_id}/${build_id}/otel/${task_id}-${execution}-otel-traces.tar.gz
    bucket: ${bucket_name}
    permissions: public-read
    content_type: ${content_type|application/x-gzip}
    display_name: "otel-traces.tar.gz"
```
