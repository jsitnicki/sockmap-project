#!/usr/bin/env python3

from signal import pause
from socket import *
import sys

args = sys.argv[1:]

if len(args) != 4:
    print("Usage: proxy.py <LISTEN-HOST> <LISTEN-PORT> <CONNECT-HOST> <CONNECT-PORT>")
    sys.exit(1)

listen_host, listen_port, connect_host, connect_port = args
listen_addr = (listen_host, int(listen_port))
connect_addr = (connect_host, int(connect_port))

ln = socket(AF_INET, SOCK_STREAM)
ln.bind(listen_addr)
ln.listen(1)

p, _ = ln.accept()
print(f"Accepted {p.getsockname()} → {p.getpeername()}")

c = socket(AF_INET, SOCK_STREAM)
c.connect(connect_addr)
print(f"Connected {c.getsockname()} → {c.getpeername()}")

print("Waiting for signal...")
pause()
