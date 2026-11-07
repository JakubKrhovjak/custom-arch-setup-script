#!/bin/bash

# QEMU for the install test. Usage: vm.sh <work directory> iso|disk|window
# iso:    boots the Arch ISO with its kernel on the serial console (serial.sock), disk is created when missing
# disk:   boots the installed system with a virtual GPU and no window; keyboard through the monitor (monitor.sock),
#         SSH for logs on host port 2222. No Secure Boot firmware: arch-install.sh must not enter its setup-mode path.
# window: the same system in a QEMU window on your desktop; Ctrl + Alt + G releases the mouse and keyboard

set -euo pipefail

WORK=$1
MODE=$2
cd "$WORK"

# A second start would fail, but only after removing the monitor socket of the running VM
if [ -e qemu.pid ] && kill -0 "$(cat qemu.pid)" 2>/dev/null; then
    echo "VM already running, pid $(cat qemu.pid)" >&2
    exit 1
fi

[ -f disk.qcow2 ] || qemu-img create -q -f qcow2 disk.qcow2 60G
[ -f vars.fd ] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd vars.fd

args=(
    -name desk-install-test -enable-kvm -machine q35 -cpu host -smp 8 -m 12G
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd
    -drive if=pflash,format=raw,file=vars.fd
    -drive if=virtio,format=qcow2,file=disk.qcow2
    -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22
    -monitor unix:monitor.sock,server=on,wait=off
    -serial unix:serial.sock,server=on,wait=off
    -pidfile qemu.pid
)
# A QEMU window stays attached to the terminal it started from, the other modes run in the background
[ "$MODE" = window ] || args+=(-daemonize)

if [ "$MODE" = iso ]; then
    mkdir -p iso-boot
    if [ ! -f iso-boot/vmlinuz-linux ]; then
        bsdtar -xf archlinux-x86_64.iso -C iso-boot --strip-components=3 arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img
        chmod u+rw iso-boot/*
    fi
    uuid=$(blkid -p -s UUID -o value archlinux-x86_64.iso)
    args+=(
        -display none -vga none
        -cdrom archlinux-x86_64.iso
        -kernel iso-boot/vmlinuz-linux -initrd iso-boot/initramfs-linux.img
        -append "archisobasedir=arch archisosearchuuid=$uuid console=ttyS0,115200"
    )
elif [ "$MODE" = window ]; then
    args+=(
        -device virtio-vga-gl,xres=1920,yres=1080
        -display gtk,gl=on,zoom-to-fit=on
    )
else
    args+=(
        -device virtio-vga-gl,xres=1920,yres=1080
        -display egl-headless
    )
fi

rm -f monitor.sock serial.sock
qemu-system-x86_64 "${args[@]}"
echo "started, pid $(cat qemu.pid)"
