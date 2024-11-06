### A test server for driver Happy Eyeballs behavior.
#
# This server will start accepting connections on a "control" port.  Driver tests can connect to
# that port to request a new pair (IPv4, IPv6) of open ephemeral ports, where one is much slower to
# complete the TCP handshake than the other.
#
# This server relies on network stack behavior present in Windows and MacOS kernels but not Linux,
# so any tests using it should only be run on those two OSen.
#
### Usage:
#
# python3 server.py [-c|--control PORT] [--wait] [--stop]
#
# Running with no arguments, or with just `-c PORT`, will start the server in the foreground.  PORT
# defaults to 10036 if not specified.
#
# Running with `--wait` will wait for a server running in another process to be ready to start
# accepting control connections.
#
# Running with `--stop` will signal a server running in another process to gracefully shutdown.
#
### Control protocol:
#
# On opening a connection to the control port, the driver test should send a single byte: 0x04 to
# request a port pair with a slow IPv4 connection, 0x06 to request one with a slow IPv6 connection.
# The server will respond with:
#   0x01  (success signal)
#   uint16 (IPv4 port, big-endian)
#   uint16 (IPv6 port, big-endian)
# Any other response should be treated as an error.  The connection will be closed after the ports
# are sent; to request another pair, open a new connection to the control port.
#
# Test connections to the two ports should be initiated immediately; the TCP handshake completion
# will be delayed on the slow port by two seconds from the time of the port being bound, not the
# ACK received.  When connected to, both ports will write out a single byte for verification (0x04
# for IPv4, 0x06 for IPv6) and then immediately close.

import argparse
import asyncio
import socket
import sys

parser = argparse.ArgumentParser(
    prog='server',
    description='Test server for happy eyeballs',
)
parser.add_argument('-c', '--control', default=10036, type=int, metavar='PORT', help='control port')
parser.add_argument('--wait', action='store_true', help='wait for a running server to be ready')
parser.add_argument('--stop', action='store_true', help='stop a running server')
args = parser.parse_args()

PREFIX='happy eyeballs server'

async def control_server():
    shutdown = asyncio.Event()
    srv = await asyncio.start_server(lambda reader, writer: on_control_connected(reader, writer, shutdown), 'localhost', args.control)
    print(f'{PREFIX}: listening for control connections on {args.control}', file=sys.stderr)
    async with srv:
        await shutdown.wait()
    print(f'{PREFIX}: all done', file=sys.stderr)

async def on_control_connected(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, shutdown: asyncio.Event):
    # Read the control request byte
    data = await reader.readexactly(1)
    if data == b'\x04':
        print(f'{PREFIX}: ========================', file=sys.stderr)
        print(f'{PREFIX}: request for delayed IPv4', file=sys.stderr)
        slow = 'IPv4'
    elif data == b'\x06':
        print(f'{PREFIX}: ========================', file=sys.stderr)
        print(f'{PREFIX}: request for delayed IPv6', file=sys.stderr)
        slow = 'IPv6'
    elif data == b'\xF0':
        writer.write(b'\x01')
        await writer.drain()
        writer.close()
        await writer.wait_closed()
        return
    elif data == b'\xFF':
        print(f'{PREFIX}: shutting down', file=sys.stderr)
        writer.close()
        await writer.wait_closed()
        shutdown.set()
        return
    else:
        print(f'Unexpected control byte: {data}', file=sys.stderr)
        exit(1)
    
    # Bind the test ports but do not yet start accepting connections
    connected = asyncio.Event()
    on_ipv4_connected = lambda reader, writer: on_test_connected('IPv4', writer, b'\x04', connected, slow)
    on_ipv6_connected = lambda reader, writer: on_test_connected('IPv6', writer, b'\x06', connected, slow)
    # port 0: pick random unused port
    srv4 = await asyncio.start_server(on_ipv4_connected, 'localhost', 0, family=socket.AF_INET, start_serving=False)
    srv6 = await asyncio.start_server(on_ipv6_connected, 'localhost', 0, family=socket.AF_INET6, start_serving=False)
    ipv4_port = srv4.sockets[0].getsockname()[1]
    ipv6_port = srv6.sockets[0].getsockname()[1]
    print(f'{PREFIX}: [slow {slow}] bound for IPv4 on {ipv4_port}', file=sys.stderr)
    print(f'{PREFIX}: [slow {slow}] bound for IPv6 on {ipv6_port}', file=sys.stderr)

    # Reply to control request with success byte and test server ports
    writer.write(b'\x01')
    writer.write(ipv4_port.to_bytes(2, 'big'))
    writer.write(ipv6_port.to_bytes(2, 'big'))
    await writer.drain()
    writer.close()
    await writer.wait_closed()

    # Start test servers listening in parallel
    # Hold a reference to the tasks so they aren't GC'd
    test_tasks = [
        asyncio.create_task(test_listen('IPv4', srv4, data == b'\x04', connected, slow)),
        asyncio.create_task(test_listen('IPv6', srv6, data == b'\x06', connected, slow)),
    ]
    await asyncio.wait(test_tasks)

    # Wait for the test servers to shut down
    srv4.close()
    srv6.close()
    close_tasks = [
        asyncio.create_task(srv4.wait_closed()),
        asyncio.create_task(srv6.wait_closed()),
    ]
    await asyncio.wait(close_tasks)
    
    print(f'{PREFIX}: [slow {slow}] connection complete, test ports closed', file=sys.stderr)
    print(f'{PREFIX}: ========================', file=sys.stderr)

async def test_listen(name: str, srv, delay: bool, connected: asyncio.Event, slow: str):
    # Both connections are delayed; the slow one is delayed by more than the fast one; this
    # ensures that the client is comparing timing and not simply choosing an immediate success
    # over a connection denied.
    if delay:
        print(f'{PREFIX}: [slow {slow}] delaying {name} connections', file=sys.stderr)
        await asyncio.sleep(2.0)
    else:
        await asyncio.sleep(1.0)
    async with srv:
        await srv.start_serving()
        print(f'{PREFIX}: [slow {slow}] accepting {name} connections', file=sys.stderr)
        # Terminate this test server when either test server has handled a request
        await connected.wait()

async def on_test_connected(name: str, writer: asyncio.StreamWriter, payload: bytes, connected: asyncio.Event, slow: str):
    print(f'{PREFIX}: [slow {slow}] connected on {name}', file=sys.stderr)
    writer.write(payload)
    await writer.drain()
    writer.close()
    await writer.wait_closed()
    connected.set()

async def stop_server():
    control_r, control_w = await asyncio.open_connection('localhost', args.control)
    control_w.write(b'\xFF')
    await control_w.drain()
    control_w.close()
    await control_w.wait_closed()

async def wait_for_server():
    while True:
        try:
            control_r, control_w = await asyncio.open_connection('localhost', args.control)
        except OSError as e:
            print(f'{PREFIX}: failed ({e}), will retry', file=sys.stderr)
            await asyncio.sleep(1)
            continue
        break
    control_w.write(b'\xF0')
    await control_w.drain()
    data = await control_r.read(1)
    if data != b'\x01':
        print(f'{PREFIX}: expected byte 1, got {data}', file=sys.stderr)
        exit(1)
    print(f'{PREFIX}: happy eyeballs server ready on port {args.control}', file=sys.stderr)


if args.stop:
    asyncio.run(stop_server())
elif args.wait:
    asyncio.run(wait_for_server())
else:
    asyncio.run(control_server())
