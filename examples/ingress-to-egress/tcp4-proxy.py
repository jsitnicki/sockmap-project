#!/usr/bin/env python3
#
# Single-threaded asynchronous TCP4 proxy
#

import asyncio, errno, logging, sys
from socket import *


logging.basicConfig(
    format="{asctime} - {levelname} - {message}",
    style="{",
    datefmt="%Y-%m-%d %H:%M:%S",
    level=logging.INFO,
)

info = logging.info
warn = logging.warning


async def proxy_stream(id, source, target):
    BUF_SIZE = 64 * 1024

    try:
        info(f"proxy stream {id}")

        loop = asyncio.get_running_loop()
        while True:
            buf = await loop.sock_recv(source, BUF_SIZE)
            if not buf:
                break
            await loop.sock_sendall(target, buf)

        source.shutdown(SHUT_RDWR)
        target.shutdown(SHUT_RDWR)

    except OSError as e:
        if (
            e.errno == errno.ENOTCONN  # other coro called shutdown
            or e.errno == errno.ECONNRESET  # peer gone
        ):
            pass
        else:
            raise e

    finally:
        source.close()
        target.close()
        info(f"close stream {id}")


async def run(listen_addr, connect_addr):
    ln = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK)
    ln.setsockopt(SOL_SOCKET, SO_REUSEADDR, 1)
    ln.bind(listen_addr)
    ln.listen(SOMAXCONN)

    tasks = set()
    loop = asyncio.get_running_loop()
    while True:
        info(f"waiting for conn at {ln.getsockname()}...")

        p, _ = await loop.sock_accept(ln)
        info(f"incoming conn {p.getpeername()} ↱ {p.getsockname()}")

        try:
            c = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK)
            await loop.sock_connect(c, connect_addr)
            info(f"outgoing conn {c.getsockname()} ↳ {c.getpeername()}")

            id1 = f"{p.getpeername()} ↱ {p.getsockname()} ↷ {c.getsockname()} ↳ {c.getpeername()}"
            id2 = f"{c.getpeername()} ↱ {c.getsockname()} ↷ {p.getsockname()} ↳ {p.getpeername()}"

            t1 = loop.create_task(proxy_stream(id1, p.dup(), c.dup()))
            t2 = loop.create_task(proxy_stream(id2, c.dup(), p.dup()))

            # TODO: clean up finished tasks
            tasks |= {t1, t2}  # keep tasks alive

        except ConnectionRefusedError:
            warn(f"failed to connect to {connect_addr}")

        finally:
            p.close()
            c.close()


if __name__ == "__main__":
    from argparse import ArgumentParser

    p = ArgumentParser()
    p.add_argument("listen_host")
    p.add_argument("listen_port", type=int)
    p.add_argument("connect_host")
    p.add_argument("connect_port", type=int)

    args = p.parse_args()
    listen_addr = (args.listen_host, args.listen_port)
    connect_addr = (args.connect_host, args.connect_port)

    try:
        asyncio.run(run(listen_addr, connect_addr))
    except KeyboardInterrupt:
        info("exit on signal...")
