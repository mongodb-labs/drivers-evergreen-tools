#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="bin"
mkdir -p $BIN_DIR
go build -o $BIN_DIR/perfcomp ./cmd/perfcomp/
