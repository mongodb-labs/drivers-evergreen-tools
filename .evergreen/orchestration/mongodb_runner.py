import argparse
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
from typing import Any, Dict, List, Literal, Union
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


_MR_VERSION = "6.7.1"


def _install_mongodb_runner() -> Path:
    """Install mongodb-runner via npm with overrides to pin @mongodb-js/oidc-mock-provider.

    npx does not support npm overrides, so we manage the install manually.
    @mongodb-js/oidc-mock-provider 0.13.8+ switched to yargs@18 (ESM-only), which
    cannot be require()'d on Node 16. Pinning to 0.13.7 keeps it on yargs@17.
    """
    install_dir = TMPDIR / f"mongodb-runner-{_MR_VERSION}"
    ext = ".cmd" if PLATFORM == "win32" else ""
    runner_bin = install_dir / "node_modules" / ".bin" / f"mongodb-runner{ext}"
    if not runner_bin.exists():
        pkg = {
            "name": "mongodb-runner-wrapper",
            "version": "1.0.0",
            "dependencies": {"mongodb-runner": _MR_VERSION},
            "overrides": {"@mongodb-js/oidc-mock-provider": "0.13.7"},
        }
        install_dir.mkdir(parents=True, exist_ok=True)
        (install_dir / "package.json").write_text(json.dumps(pkg, indent=2))
        npm = shutil.which("npm")
        if npm is None:
            raise RuntimeError(
                "npm not found. Source init-node-and-npm-env.sh or install Node before running this script."
            )
        if PLATFORM == "win32":
            # .cmd files require shell=True on Windows; pass as string to avoid quoting issues.
            subprocess.run(
                f'"{npm}" install --silent',
                cwd=str(install_dir),
                check=True,
                shell=True,
            )
        else:
            subprocess.run(
                [npm, "install", "--silent"], cwd=str(install_dir), check=True
            )
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
        binary = _normalize_path(_install_mongodb_runner())
        cmd = f"{binary} start --debug --config {config_file}"
    LOGGER.info(f"Running mongodb-runner using {binary}...")
    env = os.environ.copy()
    node_bin = shutil.which("node")
    if node_bin:
        try:
            node_ver = subprocess.check_output(
                [node_bin, "--version"], encoding="utf-8"
            ).strip()
            node_major = int(node_ver.lstrip("v").split(".")[0])
            # Node < 19 doesn't expose WebCrypto as a global; mongodb driver needs it.
            # The flag was removed in Node 22, so only add it for Node 16-18.
            if node_major < 19:
                existing = env.get("NODE_OPTIONS", "")
                env["NODE_OPTIONS"] = (
                    f"{existing} --experimental-global-webcrypto".strip()
                )
        except (subprocess.CalledProcessError, ValueError):
            pass
    try:
        with server_log.open("w") as fid:
            # Capture output while still streaming it to the file
            proc = subprocess.Popen(
                cmd if PLATFORM == "win32" else shlex.split(cmd),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                env=env,
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
            if key == "sslCAFile":
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
