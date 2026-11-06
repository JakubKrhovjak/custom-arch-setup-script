#!/usr/bin/python3
"""Sends one command to the QEMU monitor and prints the answer: hmp.py <work directory> <command>"""
import socket
import sys
from pathlib import Path

sock = socket.socket(socket.AF_UNIX)
sock.connect(str(Path(sys.argv[1]) / "monitor.sock"))
sock.settimeout(5)


def read_until_prompt():
    data = b""
    while not data.endswith(b"(qemu) "):
        data += sock.recv(4096)
    return data.decode(errors="ignore")


read_until_prompt()
sock.sendall(sys.argv[2].encode() + b"\n")
print(read_until_prompt())
