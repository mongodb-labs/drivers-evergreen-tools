# Happy Eyeballs test scripts

This folder contains a test server ([`server.py`](server.py)) for driver Happy Eyeballs TCP connection behavior.  It also has has [`client.py`](client.py), a simple client for that server that can be useful for debugging but won't be needed in most cases.

**NOTE**: This server relies on network stack behavior present in Windows and MacOS but not Linux, so any tests using it must only be run on those two OSes.

## Command-line Usage

`python3 server.py [-c|--control PORT] [--wait] [--stop]`

Run with:
* no arguments, or with just `-c PORT`, to start the server in the foreground.  `PORT` defaults to 10036 if not specified.
* `--wait` to wait for a server running in another process to be ready to start accepting control connections.
* `--stop` to signal a server running in another process to gracefully shutdown.

For convenience, you can run `setup.sh` to start the server in the background and wait for it to stop, and
`teardown.sh` to stop the server.  If you use a different port, pass the port argument to both scripts.

## Integration with Evergreen

The server can be incorporated into an evergreen test run via these functions:
```yaml
functions:
  "start happy eyeballs server":
    - command: subprocess.exec
      params:
        working_dir: src
        binary: bash
        args:
          - ${DRIVERS_TOOLS}/.evergreen/happy_eyeballs/setup.sh
  "stop happy eyeballs server":
    - command: subprocess.exec
      params:
        working_dir: src
        binary: bash
        args:
          - ${DRIVERS_TOOLS}/.evergreen/happy_eyeballs/teardown.sh
```
The `"stop happy eyeballs server"` function should be included in the `post` configuration or a `teardown_task` section to ensure that the server isn't left running after the test finishes.

## Test Usage

On opening a connection to the control port, the driver test should send a single byte: `0x04` to request a port pair with a slow IPv4 connection, or `0x06` to request one with a slow IPv6 connection. The server will respond with:
1. `0x01`  (success signal), followed by
2. `uint16` (IPv4 port, big-endian), followed by
3. `uint16` (IPv6 port, big-endian)

Any other response should be treated as an error.  The connection will be closed after the ports are sent; to request another pair, open a new connection to the control port.

Test connections to the two ports should be initiated immediately; the TCP handshake completion will be delayed on the slow port by two seconds from the time of the port _being bound_, not the ACK received. Only one port is expected to successfully connect. Once connected, the port will write out a single byte for verification (`0x04`
for IPv4, `0x06` for IPv6) and then immediately close both ports.
