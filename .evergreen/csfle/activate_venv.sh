if [ "Windows_NT" = "$OS" ]; then
  PYTHON_BINARY=C:/python/Python38/python.exe
elif command -v /opt/python/3.6/bin/python3; then
  PYTHON_BINARY=/opt/python/3.6/bin/python3
else
  PYTHON_BINARY=python3
fi

# create venv on first run
if [ ! -d kmstlsvenv ]; then
   FIRST_RUN=1
   virtualenv -p ${PYTHON_BINARY} kmstlsvenv
fi

# always activate venv
if [ "Windows_NT" = "$OS" ]; then
  . kmstlsvenv/Scripts/activate
else
  . kmstlsvenv/bin/activate
fi

# install dependencies on first run
if [ ! -z $FIRST_RUN ]; then
  pip install --upgrade boto3~=1.19 pykmip~=0.10.0
fi