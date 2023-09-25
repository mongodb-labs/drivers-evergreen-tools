#!/usr/bin/env bash
set -eu

cd $DRIVERS_TOOLS/.evergreen
bash run-orchestration.sh
echo "Success!"
echo '{"results": [{ "status": "SUCCESS", "test_file": "Run", "log_raw": "run-orchestration.sh succeeded!"  } ]}' >|${PROJECT_DIRECTORY}/test-results.json
