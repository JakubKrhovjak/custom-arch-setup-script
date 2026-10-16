#!/bin/bash

# Runs by itself on the Arch ISO from the USB stick made by make-usb.sh (boot parameter script=, tty1):
# network (cable, Wi-Fi from wifi.conf, or pick a Wi-Fi network) → arch-install.sh → reboot.

set -uo pipefail

USB=/run/archiso/bootmnt
WIFI_CONF="$USB/wifi.conf"

CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
info() { echo -e "${CYAN}[>]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

online() { ping -c1 -W2 archlinux.org &>/dev/null; }

wait_online() { # seconds
    for _ in $(seq "$1"); do
        online && return 0
        sleep 1
    done
    return 1
}

wifi_connect() { # ssid, passphrase
    local dev
    dev=$(ls /sys/class/net | grep -m1 '^wl') || { warn "No Wi-Fi adapter"; return 1; }
    info "Connecting $dev to Wi-Fi \"$1\"..."
    iwctl station "$dev" scan &>/dev/null
    sleep 3
    iwctl --passphrase "$2" station "$dev" connect "$1" && wait_online 30
}

wifi_pick() { # interactive fallback: list networks, ask for name + password
    local dev ssid pass
    dev=$(ls /sys/class/net | grep -m1 '^wl') || return 1
    iwctl station "$dev" scan &>/dev/null
    sleep 3
    iwctl station "$dev" get-networks
    read -rp "Wi-Fi name: " ssid
    read -rsp "Wi-Fi password: " pass; echo
    wifi_connect "$ssid" "$pass"
}

clear
echo -e "${CYAN}══════════ Arch Linux automatic install ══════════${NC}"

info "Waiting for network..."
if ! wait_online 15 && [ -f "$WIFI_CONF" ]; then
    # shellcheck source=/dev/null
    source "$WIFI_CONF" # WIFI_SSID, WIFI_PASS (written by make-usb.sh)
    wifi_connect "$WIFI_SSID" "$WIFI_PASS" || warn "Wi-Fi from the USB stick did not connect"
fi
until online; do
    warn "No internet. Plug in a cable, or pick a Wi-Fi network:"
    wifi_pick || sleep 5
done
info "Online"

# copy off the FAT stick: arch-install.sh copies its own directory into the new system
info "Copying setup scripts from the USB stick (may take a few minutes)..."
rm -rf /root/arch-setup
cp -r "$USB/arch-setup" /root/arch-setup

if ! bash /root/arch-setup/arch-install.sh; then
    echo -e "${RED}[✗]${NC} Installation failed — see the output above. You are in a shell (re-run: bash /root/arch-setup/arch-install.sh)."
    exit 1
fi

umount -R /mnt
cryptsetup close root
echo ""
# the live system runs from the stick (copytoram=n) → pull it out only when the PC is off
echo "Press Enter to power off. Then remove the USB stick, enable Secure Boot in BIOS and boot."
read -r
poweroff
