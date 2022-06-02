# Usage:
# createvirtualenv /path/to/python /output/path/for/venv
# * param1: Python binary to use for the virtualenv
# * param2: Path to the virtualenv to create
createvirtualenv () {
    PYTHON=$1
    VENVPATH=$2
    if $PYTHON -m venv -h>/dev/null; then
        VIRTUALENV="$PYTHON -m venv"
    elif $PYTHON -m virtualenv --version; then
        VIRTUALENV="$PYTHON -m virtualenv"
    else
        echo "Cannot test without venv or virtualenv"
        exit 1
    fi
    $VIRTUALENV $VENVPATH
    if [ "Windows_NT" = "$OS" ]; then
        # Workaround https://bugs.python.org/issue32451:
        # mongovenv/Scripts/activate: line 3: $'\r': command not found
        dos2unix $VENVPATH/Scripts/activate || true
        . $VENVPATH/Scripts/activate
    else
        . $VENVPATH/bin/activate
    fi

    python -m pip install --upgrade pip
    python -m pip install --upgrade setuptools
}
