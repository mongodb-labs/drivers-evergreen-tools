# Determine whether the current Python executable is usable for Drivers Evergreen Tools.
# Exit status will determine compatibility.

import sys

REQUIRED_PYTHON_VERSION_MAJOR = 3
REQUIRED_PYTHON_VERSION_MINOR = 9

# For diagnostic purposes.
print(f"  Version: {sys.version.split()[0]}")


def error_out(message):
    print(f"   INVALID: {message}")
    sys.exit(1)


try:
    import pip  # noqa: F401
except ImportError:
    try:
        import ensurepip  # noqa: F401
    except ImportError:
        error_out("Does not support pip")

try:
    import venv  # noqa: F401
except ImportError:
    try:
        import virtualenv  # noqa: F401
    except ImportError:
        error_out("Does not support venv or virtualenv")


if "free-threading" in sys.version:
    error_out("Free threaded python not supported")


if not (
    sys.version_info[0] == REQUIRED_PYTHON_VERSION_MAJOR
    and sys.version_info[1] >= REQUIRED_PYTHON_VERSION_MINOR
):
    error_out(
        f"Unsupported version of python, requires {REQUIRED_PYTHON_VERSION_MAJOR}.{REQUIRED_PYTHON_VERSION_MINOR}+"
    )

if sys.version_info.releaselevel != "final":
    error_out("Prerelease version of python")

print("   VALID!")
