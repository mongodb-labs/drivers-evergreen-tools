#!/usr/bin/env python3
"""
Script for testing MONGDOB-AWS authentication without URI credentials.
"""

import argparse

from aws_common import (
    HERE,
    LOGGER,
    setup_assume_role,
    setup_ec2,
    setup_ecs,
    setup_eks_pod_identity,
    setup_env_creds,
    setup_regular,
    setup_session_creds,
    setup_web_identity,
)


def handle_creds(creds: dict):
    with (HERE / "test-env.sh").open("w", newline="\n") as fid:
        fid.write("#!/usr/bin/env bash\n\n")
        fid.write("set +x\n")
        fid.write(
            'export MONGODB_URI="mongodb://localhost/aws?authMechanism=MONGODB-AWS"\n'
        )


def main():
    parser = argparse.ArgumentParser(description="MONGODB-AWS tester.")
    sub = parser.add_subparsers(title="Tester subcommands", help="sub-command help")

    run_assume_role_cmd = sub.add_parser("assume-role", help="Assume role test")
    run_assume_role_cmd.set_defaults(func=setup_assume_role)

    run_ec2_cmd = sub.add_parser("ec2", help="EC2 test")
    run_ec2_cmd.set_defaults(func=setup_ec2)

    run_ecs_cmd = sub.add_parser("ecs", help="ECS test")
    run_ecs_cmd.set_defaults(func=setup_ecs)

    run_regular_cmd = sub.add_parser("regular", help="Regular credentials test")
    run_regular_cmd.set_defaults(func=setup_regular)

    run_session_creds_cmd = sub.add_parser("session-creds", help="Session credentials")
    run_session_creds_cmd.set_defaults(func=setup_session_creds)

    run_env_creds_cmd = sub.add_parser("env-creds", help="Environment credentials")
    run_env_creds_cmd.set_defaults(func=setup_env_creds)

    run_web_identity_cmd = sub.add_parser("web-identity", help="Web identity test")
    run_web_identity_cmd.set_defaults(func=setup_web_identity)

    run_eks_pod_identity_cmd = sub.add_parser("eks", help="EKS pod identity test")
    run_eks_pod_identity_cmd.set_defaults(func=setup_eks_pod_identity)

    args = parser.parse_args()
    func_name = args.func.__name__.replace("setup_", "").replace("_", "-")
    LOGGER.info("Running aws_tester.py with %s...", func_name)
    creds = args.func()
    handle_creds(creds)
    LOGGER.info("Running aws_tester.py with %s... done.", func_name)


if __name__ == "__main__":
    main()
