#!/usr/bin/env python3
#
# TODO:
# - accept alos second and subsequent connection
#

"""\
Usage: proxy.py <LISTEN-HOST> <LISTEN-PORT> <CONNECT-HOST> <CONNECT-PORT>
"""

import asyncio
import sys
from socket import *


BUF_SIZE = 64 * 1024


async def proxy(source, target):
    loop = asyncio.get_event_loop()

    print(f"proxy {source.getsockname()} → {target.getsockname()}")
    while True:
        buf = await loop.sock_recv(source, BUF_SIZE)
        await loop.sock_sendall(target, buf)


async def run(listen_addr, connect_addr):
    loop = asyncio.get_event_loop()

    ln = socket(AF_INET, SOCK_STREAM)
    ln.setsockopt(SOL_SOCKET, SO_REUSEADDR, 1)
    ln.bind(listen_addr)
    ln.listen(SOMAXCONN)  # can't await for it with asyncio?
    ln.setblocking(False)

    tasks = set()
    while True:
        print("waiting for conn...")

        p, _ = await loop.sock_accept(ln)
        print(f"incoming conn {p.getpeername()} → {p.getsockname()}")

        c = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK)
        await loop.sock_connect(c, connect_addr)
        print(f"outgoing conn {c.getsockname()} → {c.getpeername()}")

        t1 = loop.create_task(proxy(p, c))
        t2 = loop.create_task(proxy(c, p))

        # keep tasks alive
        tasks |= {t1, t2}


def main():
    args = sys.argv[1:]

    if len(args) != 4:
        print(__doc__, end="", file=sys.stderr)
        sys.exit(1)

    listen_host, listen_port, connect_host, connect_port = args
    listen_addr = (listen_host, int(listen_port))
    connect_addr = (connect_host, int(connect_port))

    asyncio.run(run(listen_addr, connect_addr))


main()
