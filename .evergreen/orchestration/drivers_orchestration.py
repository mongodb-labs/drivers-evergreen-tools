"""
Run mongo-orchestration and launch a deployment.

Use '--help' for more information.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
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

# Get global values.
HERE = Path(__file__).absolute().parent
EVG_PATH = HERE.parent
DRIVERS_TOOLS = EVG_PATH.parent
LOGGER = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(levelname)-8s %(message)s")
PLATFORM = sys.platform.lower()
CRYPT_NAME_MAP = {
    "win32": "mongo_crypt_v1.dll",
    "darwin": "mongo_crypt_v1.dylib",
    "linux": "mongo_crypt_v1.so",
}

# Top level files
URI_TXT = DRIVERS_TOOLS / "uri.txt"
MO_EXPANSION_SH = Path("mo-expansion.sh")
MO_EXPANSION_YML = Path("mo-expansion.yml")


def get_options():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("command", choices=["run", "start", "stop", "clean"])
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Whether to log at the DEBUG level"
    )
    parser.add_argument(
        "--quiet", "-q", action="store_true", help="Whether to log at the WARNING level"
    )
    parser.add_argument(
        "--version",
        default="latest",
        help='The version to download. Use "latest" to download '
        "the newest available version (including release candidates).",
    )
    parser.add_argument(
        "--topology",
        choices=["standalone", "replica_set", "sharded_cluster"],
        help="The topology of the server deployment (defaults to standalone unless another flag like load_balancer is set)",
    )
    parser.add_argument(
        "--auth", action="store_true", help="Whether to add authentication"
    )
    parser.add_argument(
        "--ssl", action="store_true", help="Whether to add TLS configuration"
    )
    parser.add_argument(
        "--local-atlas",
        action="store_true",
        help="Whether to use mongodb-atlas-local to start the server",
    )
    parser.add_argument(
        "--orchestration-file", help="The name of the orchestration config file"
    )

    other_group = parser.add_argument_group("Other options")
    other_group.add_argument(
        "--load-balancer", action="store_true", help="Whether to use a load balancer"
    )
    other_group.add_argument(
        "--auth-aws", action="store_true", help="Whether to use MONGODB-AWS auth"
    )
    other_group.add_argument(
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
    other_group.add_argument(
        "--existing-binaries-dir",
        help="A directory containing existing mongodb binaries to use instead of downloading new ones",
    )
    other_group.add_argument(
        "--tls-cert-key-file",
        help="A .pem to be used as the tlsCertificateKeyFile option in mongo-orchestration",
    )
    other_group.add_argument(
        "--tls-pem-key-file",
        help="A .pem file that contains the TLS certificate and key for the server",
    )
    other_group.add_argument(
        "--tls-ca-file",
        help="A .pem file that contains the root certificate chain for the server",
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
    if not opts.topology and opts.load_balancer:
        opts.topology = "sharded_cluster"
    if opts.auth_aws:
        opts.auth = True
        opts.orchestration_file = "auth-aws.json"
    if opts.topology == "standalone" or not opts.topology:
        opts.topology = "server"
    if not opts.version:
        opts.version = "latest"

    if opts.verbose:
        LOGGER.setLevel(logging.DEBUG)
    elif opts.quiet:
        LOGGER.setLevel(logging.WARNING)
    return opts


def get_docker_cmd():
    """Get the appropriate docker command."""
    docker = shutil.which("docker") or shutil.which("podman")
    if not docker:
        return None
    if "podman" in docker:
        docker = f"sudo {docker}"
    return docker


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


def normalize_path(path: Path | str) -> str:
    if PLATFORM != "win32":
        return str(path)
    path = Path(path).as_posix()
    return re.sub("/cygdrive/(.*?)(/)", r"\1://", path, count=1)


def run_command(cmd: str, **kwargs):
    LOGGER.debug(f"Running command {cmd}...")
    try:
        proc = subprocess.run(
            shlex.split(cmd),
            check=True,
            encoding="utf-8",
            stderr=subprocess.STDOUT,
            stdout=subprocess.PIPE,
            **kwargs,
        )
        LOGGER.info(proc.stdout)
    except subprocess.CalledProcessError as e:
        LOGGER.error(e.output)
        LOGGER.error(str(e))
        sys.exit(e.returncode)
    LOGGER.debug(f"Running command {cmd}... done.")


def start_atlas(opts):
    mo_home = Path(opts.mongo_orchestration_home)
    image = f"docker.io/mongodb/mongodb-atlas-local:{opts.version}"
    docker = get_docker_cmd()
    stop(opts)
    cmd = f"{docker} run --rm -d --name mongodb_atlas_local -p 27017:27017"
    if opts.auth:
        cmd += " -e MONGODB_INITDB_ROOT_USERNAME=bob"
        cmd += " -e MONGODB_INITDB_ROOT_PASSWORD=pwd123"
    if "podman" in docker:
        cmd += " --health-cmd '/usr/local/bin/runner healthcheck'"
    cmd += f" -P {image}"
    LOGGER.info("Starting local atlas...")
    LOGGER.debug("Using command: '%s'", cmd)
    container_id = subprocess.check_output(cmd, shell=True, encoding="utf-8").strip()
    (mo_home / "container_id.txt").write_text(container_id)
    # Wait for container to become healthy.
    LOGGER.info("Waiting for container to be healthy...")
    if "podman" in docker:
        run_command(f"{docker} healthcheck run {container_id}")
    cmd = f"{docker} inspect -f '{{{{.State.Health.Status}}}}' {container_id}"
    tries = 0
    while 1:
        resp = subprocess.check_output(shlex.split(cmd), encoding="utf-8").strip()
        if resp == "healthy":
            break
        if tries >= 60:
            LOGGER.error("Timed out waiting for container to become healthy")
            sys.exit(1)
        time.sleep(1)
        tries += 1

    LOGGER.info("Waiting for container to be healthy... done.")
    uri = "mongodb://127.0.0.1:27017?directConnection=true"
    if opts.auth:
        uri = "mongodb://bob:pwd123@127.0.0.1:27017?directConnection=true"
    mongosh = Path(opts.mongodb_binaries) / "mongosh"
    run_command(f"{mongosh} {uri} --eval 'db.runCommand({{ping:1}})'")
    LOGGER.info("Starting local atlas... done.")
    return uri


def get_orchestration_data(opts):
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

    # Handle overriding the tls configuration in the file.
    if opts.tls_pem_key_file or opts.tls_ca_file:
        if not (opts.tls_pem_key_file and opts.tls_ca_file):
            raise ValueError("You must supply both tls-pem-key-file and tls-ca-file")
        base = "ABSOLUTE_PATH_REPLACEMENT_TOKEN/.evergreen/x509gen"
        text = text.replace(f"{base}/server.pem", normalize_path(opts.tls_pem_key_file))
        text = text.replace(f"{base}/ca.pem", normalize_path(opts.tls_ca_file))
    text = text.replace(
        "ABSOLUTE_PATH_REPLACEMENT_TOKEN", normalize_path(DRIVERS_TOOLS)
    )
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

    return data


def clean_run(opts):
    mdb_binaries = Path(opts.mongodb_binaries)
    mdb_binaries_str = normalize_path(mdb_binaries)
    shutil.rmtree(mdb_binaries_str, ignore_errors=True)

    mongodb_dir = DRIVERS_TOOLS / "mongodb"
    if mongodb_dir.exists():
        shutil.rmtree(normalize_path(mongodb_dir), ignore_errors=True)

    for path in [URI_TXT, MO_EXPANSION_SH, MO_EXPANSION_YML]:
        path.unlink(missing_ok=True)

    crypt_path = DRIVERS_TOOLS / CRYPT_NAME_MAP[PLATFORM]
    crypt_path.unlink(missing_ok=True)


def run(opts):
    # Deferred import so we can run as a script without the cli installed.
    from mongodl import main as mongodl
    from mongosh_dl import main as mongosh_dl

    LOGGER.info("Running orchestration...")
    clean_run(opts)

    # NOTE: in general, we need to normalize paths to account for cygwin/Windows.
    mdb_binaries = Path(opts.mongodb_binaries)
    mdb_binaries_str = normalize_path(mdb_binaries)

    # The evergreen directory to path.
    os.environ["PATH"] = f"{EVG_PATH}:{os.environ['PATH']}"

    dl_start = datetime.now()

    version = opts.version
    cache_dir = DRIVERS_TOOLS / ".local/cache"
    cache_dir_str = normalize_path(cache_dir)
    default_args = f"--out {mdb_binaries_str} --cache-dir {cache_dir_str} --retries 5"
    if opts.quiet:
        default_args += " -q"
    elif opts.verbose:
        default_args += " -v"

    if not opts.local_atlas:
        # Download the archive.
        args = f"{default_args} --version {version}"
        args += " --strip-path-components 2 --component archive"
        if not opts.existing_binaries_dir:
            LOGGER.info(f"Downloading mongodb {version}...")
            mongodl(shlex.split(args))
            LOGGER.info(f"Downloading mongodb {version}... done.")
        else:
            LOGGER.info(
                f"Using existing mongod binaries dir: {opts.existing_binaries_dir}"
            )
            shutil.copytree(opts.existing_binaries_dir, mdb_binaries)

        run_command(f"{mdb_binaries_str}/mongod --version")

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
        # We download crypt_shared to DRIVERS_TOOLS so that it is on a different
        # path location than the other binaries, which is required for
        # https://github.com/mongodb/specifications/blob/master/source/client-side-encryption/tests/README.md#via-bypassautoencryption
        args = default_args + (
            f" --version {version} --strip-path-components 1 --component crypt_shared"
        )
        LOGGER.info("Downloading crypt_shared...")
        mongodl(shlex.split(args))
        LOGGER.info("Downloading crypt_shared... done.")
        crypt_shared_path = mdb_binaries / CRYPT_NAME_MAP[PLATFORM]
        if crypt_shared_path.exists():
            shutil.move(crypt_shared_path, DRIVERS_TOOLS)
            crypt_shared_path = DRIVERS_TOOLS / crypt_shared_path.name
        else:
            raise RuntimeError(
                f"Could not find expected crypt_shared_path: {crypt_shared_path}"
            )
        crypt_text = f'CRYPT_SHARED_LIB_PATH: "{normalize_path(crypt_shared_path)}"'
        MO_EXPANSION_YML.write_text(crypt_text)
        MO_EXPANSION_SH.write_text(crypt_text.replace(": ", "="))

    # Download mongosh
    args = f"--out {mdb_binaries_str} --strip-path-components 2 --retries 5"
    if opts.verbose:
        args += " -v"
    elif opts.quiet:
        args += " -q"
    LOGGER.info("Downloading mongosh...")
    mongosh_dl(shlex.split(args))
    LOGGER.info("Downloading mongosh... done.")

    dl_end = datetime.now()
    mo_start = datetime.now()

    if opts.local_atlas:
        uri = start_atlas(opts)
    else:
        mo_home = Path(opts.mongo_orchestration_home)
        data = get_orchestration_data(opts)

        # Write the config file.
        orch_file = Path(mo_home / "config.json")
        orch_file.write_text(json.dumps(data, indent=2))

        # Start the orchestration.
        start(opts)

        # Configure the server.
        LOGGER.info("Starting deployment...")
        url = f"http://localhost:8889/v1/{opts.topology}s"
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
        uri = resp.get("mongodb_auth_uri", resp["mongodb_uri"])

    # Handle the cluster uri.
    MO_EXPANSION_YML.touch()
    MO_EXPANSION_YML.write_text(
        MO_EXPANSION_YML.read_text() + f'\nMONGODB_URI: "{uri}"'
    )
    MO_EXPANSION_SH.touch()
    MO_EXPANSION_SH.write_text(MO_EXPANSION_SH.read_text() + f'\nMONGODB_URI="{uri}"')
    URI_TXT.write_text(uri)
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


def clean_start(opts):
    mo_home = Path(opts.mongo_orchestration_home)
    for fname in [
        "out.log",
        "server.log",
        "orchestration.config",
        "config.json",
        "server.pid",
    ]:
        if (mo_home / fname).exists():
            (mo_home / fname).unlink()


def start(opts):
    # Start mongo-orchestration

    # Stop a running server.
    mo_home = Path(opts.mongo_orchestration_home)
    if (mo_home / "server.pid").exists():
        stop()

    # Clean up previous files.
    clean_start(opts)

    # Set up the mongo orchestration config.
    os.makedirs(mo_home / "lib", exist_ok=True)
    mo_config = mo_home / "orchestration.config"
    mdb_binaries = Path(opts.mongodb_binaries)
    config = dict(releases=dict(default=normalize_path(mdb_binaries)))
    mo_config.write_text(json.dumps(config, indent=2))
    mo_config_str = normalize_path(mo_config)
    sys_executable = normalize_path(sys.executable)
    command = f"{sys_executable} -m mongo_orchestration.server"

    # Handle Windows-specific concerns.
    if PLATFORM == "win32":
        # Copy default client certificate.
        src = DRIVERS_TOOLS / ".evergreen/x509gen/client.pem"
        dst = mo_home / "lib/client.pem"
        try:
            shutil.copy2(src, dst)
        except (shutil.SameFileError, PermissionError):
            pass

        # We need to use the CLI executable, and add it to our path.
        os.environ["PATH"] = (
            f"{Path(sys_executable).parent}{os.pathsep}{os.environ['PATH']}"
        )
        command = "mongo-orchestration -s wsgiref"

    # Override the client cert file if applicable.
    env = os.environ.copy()
    if opts.tls_cert_key_file:
        env["MONGO_ORCHESTRATION_CLIENT_CERT"] = normalize_path(opts.tls_cert_key_file)

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
            shlex.split(args),
            check=True,
            stderr=subprocess.STDOUT,
            stdout=output_fid,
            env=env,
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


def stop(opts):
    mo_home = Path(opts.mongo_orchestration_home)
    pid_file = mo_home / "server.pid"
    container_file = mo_home / "container_id.txt"
    docker = get_docker_cmd()
    if pid_file.exists():
        LOGGER.info("Stopping mongo-orchestration...")
        py_exe = normalize_path(sys.executable)
        run_command(f"{py_exe} -m mongo_orchestration.server stop")
        pid_file.unlink(missing_ok=True)
        LOGGER.info("Stopping mongo-orchestration... done.")
    if container_file.exists():
        LOGGER.info("Stopping mongodb_atlas_local...")
        container_id = container_file.read_text()
        run_command(f"{docker} kill {container_id}")
        container_file.unlink()
        LOGGER.info("Stopping mongodb_atlas_local... done.")
    elif docker:
        cmd = f"{docker} ps -a -q -f name=mongodb_atlas_local"
        try:
            result = subprocess.check_output(shlex.split(cmd), encoding="utf-8").strip()
        except Exception:
            result = None
        if result:
            LOGGER.info("Stopping mongodb_atlas_local...")
            if "podman" in docker:
                run_command(f"{docker} rm -f {result}")
            else:
                run_command(f"{docker} kill {result}")
            LOGGER.info("Stopping mongodb_atlas_local... done.")


def main():
    opts = get_options()
    if opts.command == "run":
        run(opts)
    elif opts.command == "start":
        start(opts)
    elif opts.command == "stop":
        stop(opts)
    elif opts.command == "clean":
        clean_run(opts)
        clean_start(opts)


if __name__ == "__main__":
    main()
