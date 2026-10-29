.PHONY: clean sleep install lint test test-connect

# ensure-uv.sh has to be sourced from bash, and make defaults to /bin/sh.
SHELL := bash

# Scopes uv's tool dir to this checkout, so installing pre-commit cannot
# disturb globally installed tools.
export DRIVERS_TOOLS ?= $(CURDIR)

# Holds the pre-commit shim, so `make lint` works without a global install.
# Stays a Unix path for PATH; the install target converts it for uv on Cygwin.
LOCAL_BIN := $(CURDIR)/.bin

all:
	@echo "Project successfully compiled"

install:
	@echo "Installing python CLIs..."
	bash .evergreen/install-cli.sh .evergreen
	bash .evergreen/install-cli.sh .evergreen/orchestration
	@echo "Installing pre-commit..."
	. .evergreen/ensure-uv.sh; ensure_uv || exit 1; \
	export PATH="$(LOCAL_BIN):$$PATH"; \
	if [ "$${OSTYPE:-}" = cygwin ]; then \
	  export UV_TOOL_BIN_DIR="$$(cygpath -aw '$(LOCAL_BIN)')"; \
	else \
	  export UV_TOOL_BIN_DIR="$(LOCAL_BIN)"; \
	fi; \
	uv tool install --force pre-commit && \
	pre-commit install

# Set HOOK to run a single hook, as in `make lint HOOK=shellcheck`.
lint:
	export PATH="$(LOCAL_BIN):$$PATH"; \
	pre-commit run --all-files $(HOOK)

clean:
	@echo "Cleaning files..."
	.evergreen/clean.sh

run-server:
	@echo "Running server..."
	.evergreen/run-mongodb.sh start

run-local-atlas:
	@echo "Running local atlas server..."
	.evergreen/run-mongodb.sh start --local-atlas

stop-server:
	@echo "Stopping server..."
	.evergreen/run-mongodb.sh stop

test:
	@echo "Running tests..."
	@echo "All done, thank you and please come again"
	@echo '{"results": [{ "status": "PASS", "test_file": "MyTest#1", "start": 860701.361040201, "end": 860701.361116371, "elapsed": 0.000076170, "log_raw": "This test did this and that"  } ]}' > test-results.json

test-connect:
	@echo "Testing server connectivity..."
	@if [ -f mo-expansion.sh ]; then set -a; . ./mo-expansion.sh; set +a; fi; \
	bash .evergreen/check-connection.sh
