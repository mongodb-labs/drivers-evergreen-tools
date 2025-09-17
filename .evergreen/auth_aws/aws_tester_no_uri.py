#!/usr/bin/env python3
"""
Script for testing MONGDOB-AWS authentication without URI credentials.
"""

from aws_common import HERE, main


def handle_creds(creds: dict):
    with (HERE / "test-env.sh").open("w", newline="\n") as fid:
        fid.write("#!/usr/bin/env bash\n\n")
        fid.write("set +x\n")
        fid.write(
            'export MONGODB_URI="mongodb://localhost/aws?authMechanism=MONGODB-AWS"\n'
        )


if __name__ == "__main__":
    main()
