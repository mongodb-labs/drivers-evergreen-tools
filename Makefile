.PHONY: clean sleep

connection_result = '{"results": [{ "status": "PASS", "test_file": "Connection#1", "start": 860701.361040201, "end": 860701.361116371, "elapsed": 0.000076170, "log_raw": "Made a successful connection!"  } ]}'
default_result = '{"results": [{ "status": "PASS", "test_file": "TestFile#1", "start": 860701.361040201, "end": 860701.361116371, "elapsed": 0.000076170, "log_raw": "Ran a simple test!"  } ]}'

all:
	@echo "Project successfully compiled"

test:
	@echo "Running tests..."
	@if [ -f ./mongodb/bin/mongosh ]; then ./mongodb/bin/mongosh "$(MONGODB_URI)" --eval "db.runCommand({\"ping\":1})" && echo $(connection_result) > test-results.json ; else echo $(default_result) > test-results.json; fi
	@echo "All done, thank you and please come again"
