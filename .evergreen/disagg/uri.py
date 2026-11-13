"""Describe the deployment started by setup.sh, from the newest ports.json under the slslocal state directory.

Usage:
  uri.py <slslocal-state-dir>                  Print an Evergreen expansion line with MONGODB_URI.
  uri.py <slslocal-state-dir> --member-names   Print the replica set member host names, one per line.

The members advertise names like `shard1-node0-mongod:<published port>` that only resolve inside the containers.
setup.sh maps them to 127.0.0.1 in /etc/hosts (the ports are published on the host), so the URI can use normal
replica set discovery, seeded with those same names. ports.json does not include the replica set name, so it is read
from a `hello` reply.
"""

import glob
import json
import os
import sys

from pymongo import MongoClient


def main():
    state_dir = sys.argv[1]
    paths = glob.glob(os.path.join(state_dir, "**", "ports.json"), recursive=True)
    if not paths:
        sys.exit(f"no ports.json found under {state_dir}")
    with open(max(paths, key=os.path.getmtime)) as f:
        ports = json.load(f)
    shards = ports.get("shards_by_log_id") or {}
    nodes = {
        name: addr for members in shards.values() for name, addr in members.items()
    }
    if not nodes:
        sys.exit("ports.json has no mongod shards: " + json.dumps(ports)[:500])

    if "--member-names" in sys.argv[2:]:
        for name in nodes:
            print(f"{name}-mongod")
        return

    # Ask one member directly: discovery would need the advertised names, which may not resolve yet.
    with MongoClient(
        f"mongodb://{next(iter(nodes.values()))}/?directConnection=true",
        serverSelectionTimeoutMS=30000,
    ) as client:
        set_name = client.admin.command("hello").get("setName")
    if not set_name:
        sys.exit("hello reply has no setName; is the deployment a replica set?")

    # Seed with the names the members advertise (resolved by /etc/hosts), not the published addresses: otherwise
    # discovery replaces the seeds with differently named servers and tests that rely on server ids from the seed
    # list (e.g. serverId: 1) no longer find them.
    seeds = [f"{name}-mongod:{addr.rsplit(':', 1)[1]}" for name, addr in nodes.items()]
    print(f'MONGODB_URI: "mongodb://{",".join(seeds)}/?replicaSet={set_name}"')


main()
