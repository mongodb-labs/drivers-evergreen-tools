.PHONY: clean sleep install lint test test-connect

# ensure-uv.sh has to be sourced from bash, and make defaults to /bin/sh.
SHELL := bash

# Let ensure_uv scope uv's tool dir to this checkout, as it does for the other
# scripts, so installing pre-commit cannot disturb globally installed tools.
export DRIVERS_TOOLS ?= $(CURDIR)

# Install the pre-commit shim into a repo-local bin dir rather than uv's default,
# so `make lint` can find it without pre-commit being installed globally and
# without writing to the developer's own tool bin dir.
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
	export UV_TOOL_BIN_DIR="$(LOCAL_BIN)"; \
	uv tool install pre-commit && \
	pre-commit install

lint:
	export PATH="$(LOCAL_BIN):$$PATH"; \
	pre-commit run --all-files

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
