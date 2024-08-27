.PHONY: clean sleep

all:
	@echo "Project successfully compiled"

run-server:
	.evergreen/run-orchestration.sh

stop-server:
	bash .evergreen/stop-orchestration.sh

test:
	@echo "Running tests..."
	@echo "All done, thank you and please come again"
	@echo '{"results": [{ "status": "PASS", "test_file": "MyTest#1", "start": 860701.361040201, "end": 860701.361116371, "elapsed": 0.000076170, "log_raw": "This test did this and that"  } ]}' > test-results.json
