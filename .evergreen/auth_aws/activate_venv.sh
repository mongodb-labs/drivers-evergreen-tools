set +x

if [ "Windows_NT" = "$OS" ]; then
  PYTHON_BINARY=C:/python/Python38/python.exe
else
  PYTHON_BINARY=python3
fi

# Get access to createvenv.
. "$(dirname "${BASH_SOURCE[0]}")/../utils.sh"

# create venv on first run
if [ ! -d authawsvenv ]; then
  createvenv "$PYTHON_BINARY" authawsvenv
  pip install --upgrade boto3
else
  activatevenv authawsvenv
fi
