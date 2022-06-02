# Usage:
# createvenv /path/to/python /output/path/for/venv
# * param1: Python binary to use for the virtualenv
# * param2: Path to the virtualenv to create
createvenv () {
    PYTHON="$1"
    VENVPATH="$2"
    if $PYTHON -m venv -h>/dev/null; then
        VENV="$PYTHON -m venv"
    elif $PYTHON -m virtualenv --version; then
        VENV="$PYTHON -m virtualenv"
    else
        echo "Cannot test without venv or virtualenv"
        exit 1
    fi
    $VENV "$VENVPATH"
    activatevenv "$VENVPATH"

    python -m pip install --upgrade pip
    python -m pip install --upgrade setuptools
}

# Usage:
# activatevenv /output/path/for/venv
# * param1: Path to the virtualenv to activate
activatevenv () {
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
