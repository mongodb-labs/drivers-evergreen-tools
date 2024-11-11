### A test client for server.py
#
# This can be used to check that server.py is functioning properly.  When run, it
# will connect to the control port on that server, request a pair of ports, open a connection to
# both ports in parallel, and assert that the byte read is the expected one for that port.

import argparse
import asyncio
import socket

parser = argparse.ArgumentParser(
    prog='client',
    description='client for testing the happy eyeballs test server',
)
parser.add_argument('-c', '--control', default=10036, type=int, metavar='PORT', help='control port')
parser.add_argument('-d', '--delay', default=4, choices=[4,6], type=int, help="ip protocol to request server delay")
args = parser.parse_args()

async def main():
    print('connecting to control')
    control_r, control_w = await asyncio.open_connection('localhost', args.control)
    control_w.write(args.delay.to_bytes(1, 'big'))
    await control_w.drain()
    data = await control_r.read(1)
    if data != b'\x01':
        raise Exception(f'Expected byte 1, got {data}')
    ipv4_port = int.from_bytes(await control_r.read(2), 'big')
    ipv6_port = int.from_bytes(await control_r.read(2), 'big')
    connect_tasks = [
        asyncio.create_task(connect('IPv4', ipv4_port, socket.AF_INET, b'\x04')),
        asyncio.create_task(connect('IPv6', ipv6_port, socket.AF_INET6, b'\x06')),
    ]
    await asyncio.wait(connect_tasks)

async def connect(name: str, port: int, family: socket.AddressFamily, payload: bytes):
    print(f'{name}: connecting')
    try:
        reader, writer = await asyncio.open_connection('localhost', port, family=family)
    except Exception as e:
        print(f'{name}: failed ({e})')
        return
    print(f'{name}: connected')
    data = await reader.readexactly(1)
    if data != payload:
        raise Exception(f'Expected {payload}, got {data}')
    writer.close()
    await writer.wait_closed()
    print(f'{name}: done')

asyncio.run(main())
