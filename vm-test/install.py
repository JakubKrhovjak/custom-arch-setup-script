#!/usr/bin/python3
"""Runs arch-install.sh on the ISO's serial console and answers its questions.

Usage: install.py <work directory>
Before the reboot it adds what the test needs and a real install does not have: sshd with a test key.
"""
import re
import socket
import sys
import time
from pathlib import Path

work = Path(sys.argv[1])
USER = "tester"
PASSWORD = "tester1234"
PASSPHRASE = "disk1234"

sock = socket.socket(socket.AF_UNIX)
sock.connect(str(work / "serial.sock"))
sock.settimeout(1)
log = (work / "install-serial.log").open("ab", buffering=0)
seen = ""


def pump():
    global seen
    try:
        data = sock.recv(65536)
    except TimeoutError:
        return
    log.write(data)
    seen += re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", data.decode(errors="replace"))
    seen = seen[-200000:]


def expect(pattern, timeout=120):
    global seen
    end = time.time() + timeout
    while time.time() < end:
        pump()
        match = re.search(pattern, seen)
        if match:
            seen = seen[match.end():]
            return match
    raise SystemExit(f"timeout waiting for {pattern!r}; end of the log:\n{seen[-1500:]}")


def send(line):
    sock.sendall(line.encode() + b"\r")


def run(command, timeout=300):
    """Runs a command at the root prompt and fails on a non-zero exit code."""
    send(f"{command}; echo RC=$?")
    match = expect(r"RC=(\d+)", timeout)
    expect(r"# ", 30)
    if match.group(1) != "0":
        raise SystemExit(f"failed: {command}")


time.sleep(2)
send("")
match = expect(r"(login: |root@archiso.*# )", 240)
if "login" in match.group(1):
    send("root")
    expect(r"# ", 60)
run("stty cols 200 rows 50; export TERM=dumb")
run("until ping -c1 -W2 10.0.2.2 >/dev/null 2>&1 || curl -s -o /dev/null https://archlinux.org; do sleep 2; done", 120)
run("pacman -Sy --noconfirm git", 300)
run("git clone -q git://10.0.2.2/custom-arch-setup-script /root/setup", 120)

send("bash /root/setup/arch-install.sh; echo INSTALL_RC=$?")
expect(r"Hostname \[lucky\]: ")
send("desktest")
expect(r"Username \[lucky\]: ")
send(USER)
expect(r"User password: ")
send(PASSWORD)
expect(r"User password \(again\): ")
send(PASSWORD)
expect(r"Disk encryption passphrase: ")
send(PASSPHRASE)
expect(r"Disk encryption passphrase \(again\): ")
send(PASSPHRASE)
expect(r"Type 'yes' to continue:")
send("yes")
match = expect(r"INSTALL_RC=(\d+)", 3000)
expect(r"# ", 30)
if match.group(1) != "0":
    raise SystemExit(f"arch-install.sh failed, see {work}/install-serial.log")

key = (work / "test-key.pub").read_text().strip()
run(f"arch-chroot /mnt systemctl enable sshd")
run(f"install -d -m700 /mnt/home/{USER}/.ssh")
run(f"echo '{key}' > /mnt/home/{USER}/.ssh/authorized_keys")
run(f"arch-chroot /mnt chown -R {USER}:{USER} /home/{USER}/.ssh")
run("arch-chroot /mnt ufw allow 22/tcp || true")
run("umount -R /mnt; cryptsetup close root; sync")
send("poweroff")
print("install finished")
