import argparse
import hashlib
import json
import logging
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, Tuple, Union
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

TMPDIR = Path(tempfile.gettempdir()) / "drivers_orchestration"
TMPDIR.mkdir(exist_ok=True)
HERE = Path(__file__).absolute().parent
DRIVERS_TOOLS = HERE.parent.parent
S_IRUSR = stat.S_IRUSR  # Unix owner read
LOGGER = logging.getLogger("drivers_orchestration")
PLATFORM = sys.platform.lower()


def _format_value(value):
    value = str(value)
    if value in ["True", "False"]:
        value = value.lower()
    return value


def _append_arg(args, key, value):
    if value is True:
        args.append(f"--{key}")
    elif value is not False:
        args.append(f"--{key}")
        args.append(_format_value(value))


def _handle_proc_params(params: dict, args: List[str]):
    found_enable_test_commands = False
    for key, value in params.items():
        if isinstance(value, dict):
            for subkey, subvalue in value.items():
                args.append(f"--{key}")
                args.append(f"{subkey}={_format_value(subvalue)}")
                if subkey == "enableTestCommands":
                    found_enable_test_commands = True
        else:
            _append_arg(args, key, value)
    if not found_enable_test_commands:
        args.append("--setParameter")
        args.append("enableTestCommands=true")


def _normalize_path(path: Union[Path, str]) -> str:
    if PLATFORM != "win32":
        return str(path)
    path = Path(path).absolute().as_posix()
    return re.sub("/cygdrive/(.*?)(/)", r"\1://", path, count=1)


_MR_PIN_DIR = HERE / "mongodb-runner"
_MR_DEFAULT_PIN = "default"


def _pin_dir(version: str) -> Path:
    """The committed pin set for a server version.

    A directory named for the version wins over the default, which is how a server
    whose wire version the current driver dropped keeps working.
    """
    # MONGODB_VERSION is untrusted input: only the captured X.Y group becomes a
    # path component, and fullmatch stops a "../" from riding along with it.
    match = re.fullmatch(r"v?(\d+\.\d+)(?:[.-][\w.-]*)?", version or "")
    if match:
        candidate = _MR_PIN_DIR / match.group(1)
        if candidate.is_dir():
            return candidate
    return _MR_PIN_DIR / _MR_DEFAULT_PIN


def _pinned_versions(pin_dir: Path) -> Tuple[str, str]:
    """The mongodb-runner and mongodb versions a pin set resolves to."""
    try:
        packages = json.loads((pin_dir / "package-lock.json").read_text())["packages"]
        return (
            packages["node_modules/mongodb-runner"]["version"],
            packages["node_modules/mongodb"]["version"],
        )
    except (OSError, ValueError, KeyError) as exc:
        raise RuntimeError(
            f"could not read {pin_dir / 'package-lock.json'}: {exc}"
        ) from exc


def _pin_digest(pin_dir: Path) -> str:
    """A short digest of a pin set's committed bytes."""
    digest = hashlib.sha256()
    for name in ("package.json", "package-lock.json"):
        try:
            digest.update((pin_dir / name).read_bytes())
        except OSError as exc:
            raise RuntimeError(f"could not read {pin_dir / name}: {exc}") from exc
    return digest.hexdigest()[:8]


def _npm_ci(install_dir: Path) -> Optional[str]:
    """Install a pin set's lockfile in install_dir.

    Returns None on success, or npm's error output on failure.

    ci rather than install so a lockfile that disagrees with its package.json fails
    instead of quietly re-resolving. --engine-strict turns the dependency tree's
    engines ranges into errors instead of warnings, so npm decides whether the Node on
    PATH will do. Output is captured, not silenced, so that reason reaches the caller.
    """
    npm = shutil.which("npm")
    if npm is None:
        return "npm was not found on PATH"
    args = ["ci", "--loglevel=error", "--engine-strict"]
    try:
        if PLATFORM == "win32":
            # .cmd files require shell=True on Windows; pass as string to avoid quoting issues.
            subprocess.run(
                f'"{npm}" {" ".join(args)}',
                cwd=str(install_dir),
                check=True,
                shell=True,
                capture_output=True,
                text=True,
            )
        else:
            subprocess.run(
                [npm, *args],
                cwd=str(install_dir),
                check=True,
                capture_output=True,
                text=True,
            )
    except subprocess.CalledProcessError as exc:
        return (exc.stderr or exc.stdout or str(exc)).strip()
    return None


def _install_node() -> bool:
    """Install Node into node-artifacts and put it first on PATH."""
    install_node_script = DRIVERS_TOOLS / ".evergreen" / "install-node.sh"
    LOGGER.info(f"Installing Node using {install_node_script}...")
    try:
        subprocess.run(["bash", str(install_node_script)], check=True)
    except subprocess.CalledProcessError as exc:
        LOGGER.warning(f"Failed to install Node using {install_node_script}: {exc}")
        return False
    node_bin_dir = DRIVERS_TOOLS / ".evergreen" / "node-artifacts" / "nodejs" / "bin"
    os.environ["PATH"] = f"{node_bin_dir}{os.pathsep}{os.environ.get('PATH', '')}"
    return True


def _host_lacks_mongodb_runner_support(message: str) -> bool:
    """Whether an install failure means the host, not the pin, can't do this.

    npm's own EBADENGINE is the host's Node/npm not meeting a package's declared
    engines range -- exactly the old-glibc-caps-Node-at-16 case from DRIVERS-3558.
    A missing npm is the same story. Anything else -- a bad package reference, a
    failed integrity check -- points at the pin's content, not the host, and must
    not be swallowed here.
    """
    return (
        "npm was not found on PATH" in message or "npm ERR! code EBADENGINE" in message
    )


def _mongodb_runner_supported(version: str) -> bool:
    """Whether mongodb-runner can run on this host.

    Installing it is the check: npm enforces the Node its dependencies need, so
    a host that cannot get a new enough Node fails the install and falls back to
    mongo-orchestration. It installs the same pin set the run will use, so a pin
    that cannot be installed would be caught here too, except that only a
    host-capability failure is treated as unsupported; anything else propagates,
    because it means the committed pin itself is broken.
    """
    if os.environ.get("USE_DEV_MONGODB_RUNNER"):
        # start_mongodb_runner runs the compiled dev runner directly, so the
        # pinned package is never installed and only node has to be present.
        return shutil.which("node") is not None
    try:
        _install_mongodb_runner(version)
    except RuntimeError as exc:
        if not _host_lacks_mongodb_runner_support(str(exc)):
            raise
        LOGGER.warning(f"mongodb-runner is unavailable here: {exc}")
        return False
    return True


def _install_mongodb_runner(version: str) -> Path:
    """Install the pin set for a server version, caching the install for reuse."""
    pin_dir = _pin_dir(version)
    runner_version, driver_version = _pinned_versions(pin_dir)
    # The versions make the directory legible; the digest is what makes it correct.
    # A transitive-only lockfile bump leaves both versions untouched, so without it
    # a warm host would reuse the previous tree and ignore the committed update.
    install_dir = TMPDIR / (
        f"mongodb-runner-{runner_version}-mongodb-{driver_version}"
        f"-{_pin_digest(pin_dir)}"
    )
    LOGGER.info(f"Using the {pin_dir.name!r} mongodb-runner pin set: {install_dir}")
    ext = ".cmd" if PLATFORM == "win32" else ""
    runner_bin = install_dir / "node_modules" / ".bin" / f"mongodb-runner{ext}"
    # A cached shim still needs a node to run it, and the docker entrypoints
    # delete node-artifacts while the cache under TMPDIR survives.
    if not runner_bin.exists() or shutil.which("node") is None:
        install_dir.mkdir(parents=True, exist_ok=True)
        try:
            for name in ("package.json", "package-lock.json"):
                shutil.copyfile(pin_dir / name, install_dir / name)
        except OSError as exc:
            raise RuntimeError(f"could not copy pin set from {pin_dir}: {exc}") from exc
        # Try the Node already on PATH first, then install our own and retry.
        error = _npm_ci(install_dir)
        if error is not None:
            LOGGER.info(f"Installing mongodb-runner failed, installing Node: {error}")
            if _install_node():
                error = _npm_ci(install_dir)
        if error is not None:
            raise RuntimeError(f"could not install mongodb-runner: {error}")
    return runner_bin


def start_mongodb_runner(opts, data):
    mo_home = Path(opts.mongo_orchestration_home)
    server_log = mo_home / "server.log"
    out_log = mo_home / "out.log"
    if out_log.exists():
        out_log.unlink()
    config = _get_cluster_options(data, opts)
    config["runnerDir"] = config["tmpDir"]
    config["host"] = "localhost"
    # Write the config file.
    config_file = mo_home / "config.json"
    config_file.write_text(json.dumps(config, indent=2))
    config_file = _normalize_path(config_file)
    # Start the runner using node.
    # Use npx unless dev version of mongodb runner is being used.
    if os.environ.get("USE_DEV_MONGODB_RUNNER"):
        binary = shutil.which("node")
        target = HERE / "devtools-shared/packages/mongodb-runner/bin/runner.js"
        target = _normalize_path(target)
        binary = _normalize_path(binary)
        cmd = f"{binary} {target} start --debug --config {config_file}"
    else:
        binary = _normalize_path(_install_mongodb_runner(opts.version))
        cmd = f"{binary} start --debug --config {config_file}"
    LOGGER.info(f"Running mongodb-runner using {binary}...")
    try:
        with server_log.open("w") as fid:
            # Capture output while still streaming it to the file
            proc = subprocess.Popen(
                cmd if PLATFORM == "win32" else shlex.split(cmd),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                shell=(PLATFORM == "win32"),
            )
            output_lines = []
            for line in proc.stdout:
                print(line, end="")  # to stdout
                fid.write(line)  # to file
                output_lines.append(line)
            proc.wait()
            if proc.returncode != 0:
                raise subprocess.CalledProcessError(
                    proc.returncode, cmd, "".join(output_lines)
                )
    except subprocess.CalledProcessError as e:
        LOGGER.error("server.log: %s", server_log.read_text())
        LOGGER.error(str(e))
        raise e
    LOGGER.info(f"Running mongodb-runner using {binary}... done.")
    cluster_file = Path(config["runnerDir"]) / f"m-{config['id']}.json"
    server_info = json.loads(cluster_file.read_text())
    cluster_file.unlink()
    out_log.write_text(json.dumps(server_info, indent=2))

    # Get the connection string, keeping only the replicaSet and authSource query params.
    conn_string = server_info["connectionString"]
    parsed = urlparse(conn_string)
    query_params = dict(parse_qsl(parsed.query))
    new_query = {
        k: v for k, v in query_params.items() if k in ["replicaSet", "authSource"]
    }
    if opts.auth and "authSource" not in new_query:
        new_query["authSource"] = config.get("authSource", "admin")
    return urlunparse(parsed._replace(query=urlencode(new_query)))


def _get_cluster_options(input: dict, opts: Any, static=False) -> Dict[str, Any]:
    id_ = uuid.uuid4().hex
    rs_members = []
    users = []
    shard_args = []
    mongos_args = []
    tmp_dir = TMPDIR
    args: List[str] = []
    roles = [
        {"role": "userAdminAnyDatabase", "db": "admin"},
        {"role": "clusterAdmin", "db": "admin"},
        {"role": "dbAdminAnyDatabase", "db": "admin"},
        {"role": "readWriteAnyDatabase", "db": "admin"},
        {"role": "restore", "db": "admin"},
        {"role": "backup", "db": "admin"},
    ]

    topology: Literal["standalone", "replset", "sharded"] = "standalone"
    if opts.topology == "replica_set":
        topology = "replset"
    elif opts.topology == "sharded_cluster":
        topology = "sharded"

    # Top level options
    skip_keys = [
        "shards",
        "requireApiVersion",
        "sslParams",
        "routers",
        "members",
        "login",
        "password",
        "id",
        "name",
        "procParams",
    ]
    for key, value in input.items():
        if key in skip_keys:
            continue
        if key == "auth_key":
            if static:
                key_file = "KEY_FILE_PATH"
            else:
                Path(tmp_dir).mkdir(parents=True, exist_ok=True)
                key_file = os.path.join(tmp_dir, f"key-file-{id_}.txt")
                with open(key_file, "w") as f:
                    f.write(input["auth_key"])
                os.chmod(key_file, S_IRUSR)
            args.extend(["--keyFile", _normalize_path(key_file)])
        else:
            _append_arg(args, key, value)

    if topology == "standalone":
        if "procParams" in input:
            _handle_proc_params(input["procParams"], args)

    if topology == "replset":
        args.append("--replSet")
        args.append(str(input["id"]))
        for member in input["members"]:
            member_rs_options = {
                "args": [],
                "tags": {},
                "priority": 1,
            }
            rs_params = member.get("rsParams")
            if rs_params:
                if "tags" in rs_params:
                    member_rs_options["tags"] = rs_params["tags"]
                if rs_params.get("arbiterOnly"):
                    member_rs_options["priority"] = 0
                    member_rs_options["arbiterOnly"] = True
                if "priority" in rs_params:
                    member_rs_options["priority"] = rs_params["priority"]
            if "procParams" in member:
                _handle_proc_params(member["procParams"], member_rs_options["args"])
            rs_members.append(member_rs_options)

    # Sharded/topology code
    if topology == "sharded":
        # Add a blank config srv to start, it must be the first shard.
        shard_args = [{"args": [], "rsMembers": [{}]}]
        for shard in input["shards"]:
            is_config_srv = False
            this_shard_options = {"args": [], "rsMembers": []}
            for member in shard["shardParams"]["members"]:
                member_args = []
                _handle_proc_params(member["procParams"], member_args)
                if "--shardsvr" in member_args:
                    member_args.remove("--shardsvr")
                elif "--configsvr" in member_args:
                    is_config_srv = True
                    member_args.remove("--configsvr")
                this_shard_options["rsMembers"].append({"args": member_args})
            if is_config_srv:
                shard_args[0] = this_shard_options
            else:
                shard_args.append(this_shard_options)
        for router in input["routers"]:
            this_router_args = []
            _handle_proc_params(router, this_router_args)
            mongos_args.append(this_router_args)

    # TLS/SSL options
    if "sslParams" in input:
        for key, value in input["sslParams"].items():
            if key == "sslPEMKeyFile":
                key = "tlsCertificateKeyFile"  # noqa: PLW2901
            elif key == "sslCAFile":
                key = "tlsCAFile"  # noqa: PLW2901
            _append_arg(args, key, value)
    if input.get("login"):
        users.append(
            {
                "username": input["login"],
                "password": input["password"],
                "roles": roles,
            }
        )

    output = {"topology": topology, "args": args}
    if users:
        output["users"] = users
    if topology == "replset":
        output["rsMembers"] = rs_members
    elif topology == "sharded":
        output["mongosArgs"] = mongos_args
        output["shards"] = shard_args
    if "requireApiVersion" in input:
        output["requireApiVersion"] = input["requireApiVersion"]

    if not static:
        output["id"] = uuid.uuid4().hex
        output["tmpDir"] = str(tmp_dir)
        output["binDir"] = str(opts.mongodb_binaries)
        if sys.platform != "win32":
            args.extend(["--unixSocketPrefix", "/tmp"])

    return output


def main():
    parser = argparse.ArgumentParser(description="MongoDB Runner Config Migrator")

    parser.add_argument(
        "--input-file", type=str, required=True, help="Path to the input file"
    )
    parser.add_argument(
        "--output-file", type=str, required=True, help="Path to the output file"
    )
    parser.add_argument(
        "--mongo-orchestration-home",
        type=str,
        required=False,
        help="Path to mongo-orchestration home",
    )
    parser.add_argument(
        "--topology",
        type=str,
        required=True,
        choices=["standalone", "replica_set", "sharded_cluster"],
        help="Server deployment topology (standalone, replica_set, sharded_cluster)",
    )

    opts = parser.parse_args()
    with open(opts.input_file) as fid:
        data = json.load(fid)

    new_data = _get_cluster_options(data, opts, static=True)
    with open(opts.output_file, "w") as fid:
        json.dump(new_data, fid, indent=2)


if __name__ == "__main__":
    main()
