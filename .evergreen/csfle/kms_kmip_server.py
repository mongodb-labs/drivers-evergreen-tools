#! /usr/bin/env python3
"""
KMS KMIP test server.
"""

from kmip.services.server import KmipServer
import os
import logging

HOSTNAME = "localhost"
PORT = 5698


def main():
    dir_path = os.path.dirname(os.path.realpath(__file__))
    drivers_evergreen_tools = os.path.join(dir_path, "..", "..")
    server = KmipServer(
        hostname=HOSTNAME,
        port=PORT,
        certificate_path=os.path.join(
            drivers_evergreen_tools, ".evergreen", "x509gen", "server.pem"),
        ca_path=os.path.join(drivers_evergreen_tools,
                             ".evergreen", "x509gen", "ca.pem"),
        config_path=None,
        auth_suite="TLS1.2",
        log_path=os.path.join(drivers_evergreen_tools,
                              ".evergreen", "csfle", "pykmip.log"),
        database_path=os.path.join(
            drivers_evergreen_tools, ".evergreen", "csfle", "pykmip.db"),
        logging_level=logging.DEBUG,
    )
    with server:
        print("Starting KMS KMIP server")
        server.serve()


if __name__ == "__main__":
    main()
