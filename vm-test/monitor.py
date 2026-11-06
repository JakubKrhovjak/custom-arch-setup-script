#!/usr/bin/python3
"""QEMU monitor for the VM test: monitor.py <work directory> type <text> | key <qemu key> | shot <png>"""
import socket
import subprocess
import sys
import time
from pathlib import Path

work = Path(sys.argv[1])
action = sys.argv[2]
value = sys.argv[3]

SPECIAL = {" ": "spc", "-": "minus", ".": "dot", "/": "slash", "_": "shift-minus", ":": "shift-semicolon", "\n": "ret"}

sock = socket.socket(socket.AF_UNIX)
sock.connect(str(work / "monitor.sock"))
sock.settimeout(5)


def read_until_prompt():
    data = b""
    while not data.endswith(b"(qemu) "):
        data += sock.recv(4096)
    return data


def command(line):
    sock.sendall(line.encode() + b"\n")
    return read_until_prompt()


read_until_prompt()
if action == "key":
    command(f"sendkey {value}")
elif action == "type":
    for char in value:
        key = SPECIAL.get(char, f"shift-{char.lower()}" if char.isupper() else char)
        command(f"sendkey {key}")
        time.sleep(0.06)
elif action == "shot":
    raw = work / "screen.ppm"
    command(f"screendump {raw}")
    time.sleep(0.5)
    subprocess.run(["magick", str(raw), value], check=True)
else:
    raise SystemExit("type|key|shot")
