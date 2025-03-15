# Determine whether the current Python executable is usable for Drivers Evergreen Tools.
# Exit status will determine compatibility.

import sys

MIN_PYTHON = "3.9"

# For diagnostic purposes.
print(f" - {sys.executable} - {sys.version.split()[0]}")


def error_out(message):
    print(f"   INVALID: {message}")
    sys.exit(1)


try:
    import pip  # noqa: F401
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


minor_version = int(MIN_PYTHON.split(".")[-1])
if not (sys.version_info[0] == 3 and sys.version_info[1] >= minor_version):  # noqa: YTT201
    error_out("Unsupported version of python")

if sys.version_info.releaselevel != "final":
    error_out("Prerelease version of python")

print("   VALID!")
