#!/usr/bin/env python3
"""
Script for testing MONGDOB-AWS authentication.
"""

from urllib.parse import quote_plus

from aws_common import HERE, main


def handle_creds(creds: dict):
    if "USER" in creds:
        USER = quote_plus(creds["USER"])
        if "PASS" in creds:
            PASS = quote_plus(creds["PASS"])
            MONGODB_URI = f"mongodb://{USER}:{PASS}@localhost"
        else:
            MONGODB_URI = f"mongodb://{USER}@localhost"
    elif "MONGODB_URI" in creds:
        MONGODB_URI = creds.pop("MONGODB_URI")
    else:
        MONGODB_URI = "mongodb://localhost"
    MONGODB_URI = f"{MONGODB_URI}/aws?authMechanism=MONGODB-AWS"
    if "SESSION_TOKEN" in creds:
        SESSION_TOKEN = quote_plus(creds["SESSION_TOKEN"])
        MONGODB_URI = (
            f"{MONGODB_URI}&authMechanismProperties=AWS_SESSION_TOKEN:{SESSION_TOKEN}"
        )
    with (HERE / "test-env.sh").open("w", newline="\n") as fid:
        fid.write("#!/usr/bin/env bash\n\n")
        fid.write("set +x\n")
        for key, value in creds.items():
            if key in ["USER", "PASS", "SESSION_TOKEN"]:
                value = quote_plus(value)  # noqa: PLW2901
            fid.write(f"export {key}={value}\n")
        fid.write(f'export MONGODB_URI="{MONGODB_URI}"\n')


if __name__ == "__main__":
    main()
