set +x

if [ "Windows_NT" = "$OS" ]; then
  PYTHON_BINARY=C:/python/Python38/python.exe
else
  PYTHON_BINARY=python3
fi

# create venv on first run
if [ ! -d authawsvenv ]; then
   FIRST_RUN=1
   virtualenv -p ${PYTHON_BINARY} authawsvenv
fi

# always activate venv
if [ "Windows_NT" = "$OS" ]; then
  . authawsvenv/Scripts/activate
else
  . authawsvenv/bin/activate
fi

# install dependencies on first run
if [ ! -z $FIRST_RUN ]; then
  pip install --upgrade boto3
fi
