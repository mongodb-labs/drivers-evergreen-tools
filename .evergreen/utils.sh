# Usage:
# venvcreate /path/to/python /output/path/for/venv
# * param1: Python binary to use for the virtualenv
# * param2: Path to the virtualenv to create
venvcreate () {
    PYTHON="$1"
    VENVPATH="$2"
    if $PYTHON -m virtualenv --version; then
        # The system-installed virtualenv on Debian 10 is buggy and will default
        # to creating a python2 environment even when invoked from python3; the
        # '-p' parameter ensures that we always use the desired interpreter
        VENV="$PYTHON -m virtualenv -p $PYTHON"
    elif $PYTHON -m venv -h>/dev/null; then
        VENV="$PYTHON -m venv"
    else
        echo "Cannot test without venv or virtualenv"
        exit 1
    fi
    $VENV "$VENVPATH"
    venvactivate "$VENVPATH"

    python -m pip install --upgrade pip
    python -m pip install --upgrade setuptools
}

# Usage:
# venvactivate /output/path/for/venv
# * param1: Path to the virtualenv to activate
venvactivate () {
    VENVPATH="$1"
    if [ "Windows_NT" = "$OS" ]; then
        # Workaround https://bugs.python.org/issue32451:
        # mongovenv/Scripts/activate: line 3: $'\r': command not found
        dos2unix "$VENVPATH/Scripts/activate" || true
        . $VENVPATH/Scripts/activate
    else
        . $VENVPATH/bin/activate
    fi
}
