"""
Run mongo-orchestration.

Use '--help' for more information.
"""

import argparse
import json
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


def get_options():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("command", choices=["run", "start", "stop"])
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
            if key == "auth":
                opts.auth = os.environ.get("auth") == "auth"
            elif key == "ssl":
                opts.ssl = os.environ.get("ssl") == "ssl"
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
    print("Running orchestration...")

    # Clean up previous files.
    mdb_binaries = Path(opts.mongodb_binaries)
    mdb_binaries_str = mdb_binaries.as_posix()
    shutil.rmtree(mdb_binaries, ignore_errors=True)
    expansion_yaml = Path("mo-expansion.yml")
    expansion_yaml.unlink(missing_ok=True)
    expansion_sh = Path("mo-expansion.sh")
    expansion_sh.unlink(missing_ok=True)

    # The evergreen directory to path.
    os.environ["PATH"] = f"{EVG_PATH}:{os.environ['PATH']}"

    # Download the archive.
    dl_start = datetime.now()
    version = opts.version
    cache_dir = DRIVERS_TOOLS / ".local/cache"
    cache_dir_str = cache_dir.as_posix()
    args = f"--out {mdb_binaries_str} --cache-dir {cache_dir_str} --version {version}"
    args += " --strip-path-components 2 --component archive"
    print(f"Downloading mongodb {version}...")
    mongodl(shlex.split(args))
    print(f"Downloading mongodb {version}... done.")

    # Download legacy shell
    if opts.install_legacy_shell:
        args = f"--out {mdb_binaries_str} --cache-dir {cache_dir_str} --version 5.0"
        args += " --strip-path-components 2 --component shell"
        print("Downloading legacy shell...")
        mongodl(shlex.split(args))
        print("Downloading legacy shell... done.")

    # Download crypt shared.
    if not opts.skip_crypt_shared:
        # Get the download URL for crypt_shared.
        # The crypt_shared package is available on server 6.0 and newer.
        # Try to download a version of crypt_shared matching the server version.
        # If no matching version is available, try to download the latest Major release of crypt_shared.
        if version in ["3.6", "4.0", "4.2", "4.4", "5.0"]:
            crypt_shared_version = "latest"
        else:
            crypt_shared_version = version
        args = f"--out {mdb_binaries_str} --cache-dir {cache_dir_str}"
        args += f" --version {crypt_shared_version}"
        args += " --strip-path-components 1 --component crypt_shared"
        print("Downloading crypt_shared...")
        mongodl(shlex.split(args))
        print("Downloading crypt_shared... done.")
        crypt_shared_path = None
        for fname in os.listdir(mdb_binaries_str):
            if fname.startswith("mongo_crypt_v1"):
                crypt_shared_path = (mdb_binaries / fname).as_posix()
        assert crypt_shared_path is not None
        crypt_text = f'CRYPT_SHARED_LIB_PATH: "{crypt_shared_path}"'
        expansion_yaml.write_text(crypt_text)
        expansion_sh.write_text(crypt_text.replace(": ", "="))

    # Download mongosh
    args = f"--out {mdb_binaries_str} --strip-path-components 2"
    print("Downloading mongosh...")
    mongosh_dl(shlex.split(args))
    print("Downloading mongosh... done.")

    dl_end = datetime.now()

    # Handle orchestration file - explicit or implicit.
    orchestration_file = opts.orchestration_file
    if not orchestration_file:
        prefix = "basic"
        if opts.auth:
            prefix = "auth"
        if opts.ssl:
            prefix += "-ssl"
        if opts.load_balancer:
            prefix += "-load-balancer"
        elif opts.disable_test_commands:
            prefix = "disableTestCommands"
        elif opts.storage_engine:
            prefix = opts.storage_engine

        orchestration_file = f"{prefix}.json"

    # Get the orchestration config data.
    topology = opts.topology
    mo_home = Path(opts.mongo_orchestration_home)
    orch_path = mo_home / f"configs/{topology}s/{orchestration_file}"
    print("Using orchestration file:", orch_path)
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
    print("Starting deployment...")
    url = f"http://localhost:8889/v1/{topology}s"
    req = urllib.request.Request(
        url, data=json.dumps(data).encode("utf-8"), method="POST"
    )
    try:
        resp = urllib.request.urlopen(req)
    except urllib.error.HTTPError as e:
        stop()
        raise e
    resp = json.loads(resp.read().decode("utf-8"))
    print(resp)
    print("Starting deployment... done.")

    # Handle the cluster uri.
    uri = resp.get("mongodb_auth_uri", resp["mongodb_uri"])
    expansion_yaml.write_text(expansion_yaml.read_text() + f"\nMONGODB_URI: {uri}")
    print(f"\nCluster URI: {uri}")

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

    print("Running orchestration... done.")


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
    config = dict(releases=dict(default=str(mdb_binaries)))
    mo_config.write_text(json.dumps(config, indent=2))
    mo_config_str = mo_config.as_posix()

    # Copy client certificates on Windows.
    if os.name == "nt":
        src = DRIVERS_TOOLS / ".evergreen/x509gen/client.pem"
        dst = mo_home / "lib/client.pem"
        shutil.copy2(src, dst)

    mo_start = datetime.now()

    # Start the process.
    args = f"{sys.executable} -m mongo_orchestration.server run -e default -f {mo_config_str}"
    args += "--socket-timeout-ms=60000 --bind=127.0.0.1 --enable-majority-read-concern"
    if os.name == "nt":
        args = +"-s wsgiref"
    args += " start"

    print("Starting mongo-orchestration...")
    try:
        subprocess.check_call(shlex.split(args))
    except subprocess.CalledProcessError as e:
        print(e.stderr.decode("utf-8"))
        raise e

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
                    raise TimeoutError(
                        "Failed to start cluster, see out.log and server.log"
                    ) from None
        attempt += 1
        time.sleep(attempt * 1000)

    print("Starting mongo-orchestration... done.")


def stop(_):
    print("Stopping mongo-orchestration...")
    args = f"{sys.executable} -m mongo_orchestration.server stop"
    try:
        subprocess.check_call(shlex.split(args))
    except subprocess.CalledProcessError as e:
        print(e.stderr.decode("utf-8"))
        raise e
    print("Stopping mongo-orchestration... done.")


def main():
    opts = get_options()
    if opts.command == "run":
        run(opts)
    elif opts.command == "start":
        start(opts)
    elif opts.command == "stop":
        stop(opts)


if __name__ == "__main__":
    main()
