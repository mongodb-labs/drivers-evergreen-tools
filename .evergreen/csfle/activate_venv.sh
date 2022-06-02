if [ "Windows_NT" = "$OS" ]; then
  PYTHON_BINARY=C:/python/Python38/python.exe
elif command -v /opt/python/3.6/bin/python3; then
  PYTHON_BINARY=/opt/python/3.6/bin/python3
elif command -v python3; then
  PYTHON_BINARY=python3
elif command -v /opt/mongodbtoolchain/v2/bin/python3; then
  PYTHON_BINARY=/opt/mongodbtoolchain/v2/bin/python3
else
  echo "error: unable to find a supported python3 executable"
fi

# Get access to createvenv.
. "$(dirname "${BASH_SOURCE[0]:-$0}")/../utils.sh"

# create venv on first run
if [ ! -d kmstlsvenv ]; then
  createvenv "$PYTHON_BINARY" kmstlsvenv
  CRYPTOGRAPHY_DONT_BUILD_RUST=1 pip install --upgrade boto3~=1.19 cryptography~=3.4.8 pykmip~=0.10.0
else
  activatevenv kmstlsvenv
fi
