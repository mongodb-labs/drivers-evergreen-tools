"""
Run mongo-orchestration and launch a deployment.

Use '--help' for more information.
"""

import argparse
import json
import logging
import os
import shlex
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

from mongodl import main as mongodl
from mongosh_dl import main as mongosh_dl

# Get global values.
HERE = Path(__file__).absolute().parent
EVG_PATH = HERE.parent
DRIVERS_TOOLS = EVG_PATH.parent
LOGGER = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(levelname)-8s %(message)s")


def get_options():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("command", choices=["run", "start", "stop"])
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Whether to log at the DEBUG level"
    )
    parser.add_argument(
        "--quiet", "-q", action="store_true", help="Whether to log at the WARNING level"
    )
    parser.add_argument(
        "--version",
        default="latest",
        help='The version to download (Required). Use "latest" to download '
        "the newest available version (including release candidates).",
    )
    parser.add_argument(
        "--topology",
        choices=["standalone", "replica_set", "sharded_cluster"],
        default="standalone",
        help="The topology of the server deployment",
    )
    parser.add_argument(
        "--auth", action="store_true", help="Whether to add authentication"
    )
    parser.add_argument(
        "--ssl", action="store_true", help="Whether to add TLS configuration"
    )
    parser.add_argument(
        "--orchestration-file", help="The name of the orchestration config file"
    )

    other_group = parser.add_argument_group("Other options")
    parser.add_argument(
        "--load-balancer", action="store_true", help="Whether to use a load balancer"
    )
    parser.add_argument(
        "--skip-crypt-shared",
        action="store_true",
        help="Whether to skip installing crypt_shared lib",
    )
    other_group.add_argument(
        "--install-legacy-shell",
        action="store_true",
        help="Whether to install the legacy shell",
    )
    other_group.add_argument(
        "--disable-test-commands",
        action="store_true",
        help="Whether to disable test commands",
    )
    other_group.add_argument(
        "--storage-engine",
        choices=["", "mmapv1", "wiredtiger", "inmemory"],
        help="The storage engine to use",
    )
    other_group.add_argument(
        "--require-api-version",
        action="store_true",
        help="Whether to set requireApiVersion",
    )
    other_group.add_argument(
        "--mongo-orchestration-home", help="The path to mongo-orchestration home"
    )
    other_group.add_argument(
        "--mongodb-binaries", help="The path to store the MongoDB binaries"
    )

    # Get the options, and then allow environment variable overrides.
    opts = parser.parse_args()
    for key in vars(opts).keys():
        env_var = key.upper()
        if env_var == "VERSION":
            env_var = "MONGODB_VERSION"
        if env_var in os.environ:
            if env_var == "AUTH":
                opts.auth = os.environ.get("AUTH") == "auth"
            elif env_var == "SSL":
                ssl_opt = os.environ.get("SSL", "")
                opts.ssl = ssl_opt and ssl_opt.lower() != "nossl"
            elif isinstance(getattr(opts, key), bool):
                if os.environ[env_var]:
                    setattr(opts, key, True)
            else:
                setattr(opts, key, os.environ[env_var])

    if opts.mongo_orchestration_home is None:
        opts.mongo_orchestration_home = DRIVERS_TOOLS / ".evergreen/orchestration"
    if opts.mongodb_binaries is None:
        opts.mongodb_binaries = DRIVERS_TOOLS / "mongodb/bin"
    if opts.topology == "standalone":
        opts.topology = "server"

    if opts.verbose:
        LOGGER.setLevel(logging.DEBUG)
    elif opts.quiet:
        LOGGER.setLevel(logging.WARNING)
    return opts


def handle_docker_config(data):
    """Modify config to when running in a docker container."""
    items = []

    # Gather all the items that have process settings.
    def traverse(root):
        if isinstance(root, list):
            [traverse(i) for i in root]
            return
        if "ipv6" in root:
            items.append(root)
            return
        for key, value in root.items():
            if key == "routers":
                continue
            if isinstance(value, (dict, list)):
                traverse(value)

    traverse(data)

    # Docker does not enable ipv6 by default.
    # https://docs.docker.com/config/daemon/ipv6/
    # We also need to use 0.0.0.0 instead of 127.0.0.1
    for item in items:
        item["ipv6"] = False
        item["bind_ip"] = "0.0.0.0,::1"
        item["dbpath"] = f"/tmp/mongo-{item['port']}"

    if "routers" in data:
        for router in data["routers"]:
            router["ipv6"] = False
            router["bind_ip"] = "0.0.0.0,::1"
            router["logpath"] = f"/tmp/mongodb-{item['port']}.log"


def run(opts):
    LOGGER.info("Running orchestration...")

    # Clean up previous files.
    mdb_binaries = Path(opts.mongodb_binaries)
    # NOTE: in general, we need to use posix strings to avoid path escapes on cygwin.
    mdb_binaries_str = mdb_binaries.as_posix()
    shutil.rmtree(mdb_binaries, ignore_errors=True)
    expansion_yaml = Path("mo-expansion.yml")
    expansion_yaml.unlink(missing_ok=True)
    expansion_sh = Path("mo-expansion.sh")
    expansion_sh.unlink(missing_ok=True)
    uri_txt = DRIVERS_TOOLS / "uri.txt"

    # The evergreen directory to path.
    os.environ["PATH"] = f"{EVG_PATH}:{os.environ['PATH']}"

    # Download the archive.
    dl_start = datetime.now()
    version = opts.version
    cache_dir = DRIVERS_TOOLS / ".local/cache"
    cache_dir_str = cache_dir.as_posix()
    default_args = f"--out {mdb_binaries_str} --cache-dir {cache_dir_str}"
    if opts.quiet:
        default_args += " -q"
    elif opts.verbose:
        default_args += " -v"
    args = f"{default_args} --version {version}"
    args += " --strip-path-components 2 --component archive"
    LOGGER.info(f"Downloading mongodb {version}...")
    mongodl(shlex.split(args))
    LOGGER.info(f"Downloading mongodb {version}... done.")

    # Download legacy shell.
    if opts.install_legacy_shell:
        args = f"{default_args} --version 5.0"
        args += " --strip-path-components 2 --component shell"
        LOGGER.INFO("Downloading legacy shell...")
        mongodl(shlex.split(args))
        LOGGER.INFO("Downloading legacy shell... done.")

    # Download crypt shared.
    if not opts.skip_crypt_shared:
        # Get the download URL for crypt_shared.
        args = f"{default_args} --version {version}"
        args += " --strip-path-components 1 --component crypt_shared"
        LOGGER.info("Downloading crypt_shared...")
        mongodl(shlex.split(args))
        LOGGER.info("Downloading crypt_shared... done.")
        crypt_shared_path = None
        expected = [f"mongo_crypt_v1.{ext}" for ext in ["dll", "so", "dylib"]]
        for fname in os.listdir(mdb_binaries_str):
            if fname in expected:
                crypt_shared_path = (mdb_binaries / fname).as_posix()
        assert crypt_shared_path is not None
        crypt_text = f'CRYPT_SHARED_LIB_PATH: "{crypt_shared_path}"'
        expansion_yaml.write_text(crypt_text)
        expansion_sh.write_text(crypt_text.replace(": ", "="))

    # Download mongosh
    args = f"--out {mdb_binaries_str} --strip-path-components 2"
    if opts.verbose:
        args += " -v"
    elif opts.quiet:
        args += " -q"
    LOGGER.info("Downloading mongosh...")
    mongosh_dl(shlex.split(args))
    LOGGER.info("Downloading mongosh... done.")

    dl_end = datetime.now()

    # Handle orchestration file - explicit or implicit.
    orchestration_file = opts.orchestration_file
    if not orchestration_file:
        fname = "basic"
        if opts.auth:
            fname = "auth"
        if opts.ssl:
            fname += "-ssl"
        if opts.load_balancer:
            fname += "-load-balancer"
        elif opts.disable_test_commands:
            fname = "disableTestCommands"
        elif opts.storage_engine:
            fname = opts.storage_engine
        orchestration_file = f"{fname}.json"

    # Get the orchestration config data.
    topology = opts.topology
    mo_home = Path(opts.mongo_orchestration_home)
    orch_path = mo_home / f"configs/{topology}s/{orchestration_file}"
    LOGGER.info(f"Using orchestration file: {orch_path}")
    text = orch_path.read_text()
    text = text.replace("ABSOLUTE_PATH_REPLACEMENT_TOKEN", DRIVERS_TOOLS.as_posix())
    data = json.loads(text)

    if opts.require_api_version:
        if opts.topology == "replica_set":
            raise ValueError(
                "requireApiVersion is not supported with replica_sets, see SERVER-97010"
            )
        data["requireApiVersion"] = "1"

    # If running on Docker, update the orchestration file to be docker-friendly.
    if os.environ.get("DOCKER_RUNNING"):
        handle_docker_config(data)

    # Write the config file.
    orch_file = Path(mo_home / "config.json")
    orch_file.write_text(json.dumps(data, indent=2))

    # Start the orchestration.
    mo_start = datetime.now()
    start(opts)

    # Configure the server.
    LOGGER.info("Starting deployment...")
    url = f"http://localhost:8889/v1/{topology}s"
    req = urllib.request.Request(
        url, data=json.dumps(data).encode("utf-8"), method="POST"
    )
    try:
        resp = urllib.request.urlopen(req)
    except urllib.error.HTTPError as e:
        stop()
        LOGGER.error("out.log: %s", (mo_home / "out.log").read_text())
        LOGGER.error("server.log: %s", (mo_home / "server.log").read_text())
        raise e
    resp = json.loads(resp.read().decode("utf-8"))
    LOGGER.debug(resp)
    LOGGER.info("Starting deployment... done.")

    # Handle the cluster uri.
    uri = resp.get("mongodb_auth_uri", resp["mongodb_uri"])
    expansion_yaml.write_text(expansion_yaml.read_text() + f"\nMONGODB_URI: {uri}")
    uri_txt.write_text(uri)
    LOGGER.info(f"Cluster URI: {uri}")

    # Write the results file.
    mo_end = datetime.now()
    data = dict(
        results=[
            dict(
                status="PASS",
                test_file="Orchestration",
                start=int(mo_start.timestamp()),
                end=int(mo_end.timestamp()),
                elapsed=(mo_end - mo_start).total_seconds(),
            ),
            dict(
                status="PASS",
                test_file="Download MongoDB",
                start=int(dl_start.timestamp()),
                end=int(dl_end.timestamp()),
                elapsed=(dl_end - dl_start).total_seconds(),
            ),
        ]
    )
    Path(DRIVERS_TOOLS / "results.json").write_text(json.dumps(data, indent=2))

    LOGGER.info("Running orchestration... done.")


def start(opts):
    # Start mongo-orchestration

    # Stop a running server.
    mo_home = Path(opts.mongo_orchestration_home)
    if (mo_home / "server.pid").exists():
        stop()

    # Clean up previous files.
    for fname in ["out.log", "server.log", "orchestration.config", "config.json"]:
        if (mo_home / fname).exists():
            (mo_home / fname).unlink()

    # Set up the mongo orchestration config.
    os.makedirs(mo_home / "lib", exist_ok=True)
    mo_config = mo_home / "orchestration.config"
    mdb_binaries = Path(opts.mongodb_binaries)
    config = dict(releases=dict(default=mdb_binaries.as_posix()))
    mo_config.write_text(json.dumps(config, indent=2))
    mo_config_str = mo_config.as_posix()
    command = f"{sys.executable} -m mongo_orchestration.server"

    # Handle Windows-specific concerns.
    if os.name == "nt":
        # Copy client certificates.
        src = DRIVERS_TOOLS / ".evergreen/x509gen/client.pem"
        dst = mo_home / "lib/client.pem"
        try:
            shutil.copy2(src, dst)
        except (shutil.SameFileError, PermissionError):
            pass

        # We need to use the CLI executable, and add it to our path.
        os.environ["PATH"] = (
            f"{Path(sys.executable).parent}{os.pathsep}{os.environ['PATH']}"
        )
        command = "mongo-orchestration -s wsgiref"

    mo_start = datetime.now()

    # Start the process.
    args = f"{command} start -e default -f {mo_config_str}"
    args += " --socket-timeout-ms=60000 --bind=127.0.0.1 --enable-majority-read-concern"

    LOGGER.info("Starting mongo-orchestration...")
    output_file = mo_home / "out.log"
    server_file = mo_home / "server.log"

    # NOTE: we need to use a separate file id for stdout and close it so Evergreen does not hang.
    output_fid = output_file.open("w")
    try:
        subprocess.run(
            shlex.split(args), check=True, stderr=subprocess.STDOUT, stdout=output_fid
        )
    except subprocess.CalledProcessError:
        LOGGER.error("Orchestration failed!")
        LOGGER.error(f"server.log:\n{server_file.read_text().strip()}")
        raise
    finally:
        output_fid.close()
        LOGGER.info(f"out.log:\n{output_file.read_text().strip()}")

    # Wait for the server to be available.
    attempt = 0
    while True:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.connect(("localhost", 8889))
                break
            except ConnectionRefusedError:
                if (datetime.now() - mo_start).seconds > 120:
                    stop()
                    LOGGER.error("Orchestration failed!")
                    LOGGER.error(f"server.log: {server_file.read_text()}")
                    raise TimeoutError("Server failed to start") from None
        attempt += 1
        time.sleep(attempt * 1000)

    LOGGER.info("Starting mongo-orchestration... done.")


def stop():
    LOGGER.info("Stopping mongo-orchestration...")
    py_exe = Path(sys.executable).as_posix()
    args = f"{py_exe} -m mongo_orchestration.server stop"
    proc = subprocess.run(
        shlex.split(args), check=True, stderr=subprocess.STDOUT, stdout=subprocess.PIPE
    )
    LOGGER.debug(proc.stdout.decode("utf-8"))
    LOGGER.info("Stopping mongo-orchestration... done.")


def main():
    opts = get_options()
    if opts.command == "run":
        run(opts)
    elif opts.command == "start":
        start(opts)
    elif opts.command == "stop":
        stop()


if __name__ == "__main__":
    main()
