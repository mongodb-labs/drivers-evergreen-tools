.PHONY: clean sleep install lint test test-results

all:
	@echo "Project successfully compiled"

install:
	@echo "Installing python CLIs..."
	bash .evergreen/install-cli.sh .evergreen
	bash .evergreen/install-cli.sh .evergreen/orchestration
	@echo "Installing pre-commit..."
	command -v uv >/dev/null 2>&1 || export PATH="$$PWD/.bin:$$PATH"; \
	uv tool install pre-commit
	pre-commit install

lint:
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
	@echo "Testing server connectivity..."
	@if [ -f mo-expansion.sh ]; then set -a; . ./mo-expansion.sh; set +a; fi; \
	bash .evergreen/check-connection.sh

test-results:
	@echo "Running tests..."
	@echo "All done, thank you and please come again"
	@echo '{"results": [{ "status": "PASS", "test_file": "MyTest#1", "start": 860701.361040201, "end": 860701.361116371, "elapsed": 0.000076170, "log_raw": "This test did this and that"  } ]}' > test-results.json
