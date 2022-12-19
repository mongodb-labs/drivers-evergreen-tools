# This script is deprecated. Use activate-authawsvenv.sh for a hygienic alternative.

set +x

if [ "Windows_NT" = "$OS" ]; then
  PYTHON_BINARY=C:/python/Python38/python.exe
else
  PYTHON_BINARY=python3
fi

# Get access to venvcreate.
. "$(dirname "${BASH_SOURCE:-$0}")/../utils.sh"

# create venv on first run
if [ ! -d authawsvenv ]; then
  venvcreate "$PYTHON_BINARY" authawsvenv
  pip install --upgrade boto3 pyop
else
  venvactivate authawsvenv
fi
