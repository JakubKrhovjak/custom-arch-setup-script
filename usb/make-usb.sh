#!/bin/bash

# Makes a USB stick that boots the Arch ISO (UEFI) and starts the installation by itself:
# this repo + usb/autoinstall.sh on the stick, boot parameter script=, optionally the current Wi-Fi.
# Usage: sudo bash usb/make-usb.sh /dev/sdX [archlinux-x86_64.iso]   (without ISO: downloads the latest)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
info() { echo -e "${CYAN}[>]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
die()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run with sudo"
[ $# -ge 1 ] || die "Usage: sudo bash $0 /dev/sdX [archlinux-x86_64.iso]"
DEV=$1
ISO=${2:-}
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIRROR=https://geo.mirror.pkgbuild.com/iso/latest

[ -b "$DEV" ] || die "$DEV is not a block device"
[ "$(lsblk -dn -o TRAN "$DEV")" = usb ] || die "$DEV is not a USB disk (lsblk TRAN != usb)"

WORK=$(mktemp -d)
MNT="$WORK/usb"
cleanup() { mountpoint -q "$MNT" && umount "$MNT"; rm -rf "$WORK"; }
trap cleanup EXIT

if [ -z "$ISO" ]; then
    info "Downloading the latest Arch ISO..."
    ISO="$WORK/archlinux-x86_64.iso"
    curl -fL --progress-bar -o "$ISO" "$MIRROR/archlinux-x86_64.iso"
    curl -fsSL -o "$WORK/sha256sums.txt" "$MIRROR/sha256sums.txt"
    (cd "$WORK" && sha256sum -c --ignore-missing sha256sums.txt) || die "ISO checksum does not match"
fi
[ -f "$ISO" ] || die "ISO $ISO not found"

# the live system finds its files by the FAT volume label (archisolabel=), max 11 characters
LABEL=$(blkid -o value -s LABEL "$ISO")
[ -n "$LABEL" ] || die "Cannot read the ISO volume label"

lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$DEV"
warn "This will ERASE everything on $DEV. Type 'yes' to continue:"
read -r CONFIRM
[ "$CONFIRM" = yes ] || die "Aborted."

info "Partitioning $DEV (GPT, one FAT32 partition $LABEL)..."
lsblk -lnp -o NAME,MOUNTPOINTS "$DEV" | awk 'NF > 1 {print $1}' | xargs -r umount
wipefs -aq "$DEV"
parted -s "$DEV" mklabel gpt mkpart ARCHISO fat32 1MiB 100% set 1 esp on
udevadm settle
PART=$(lsblk -lnp -o NAME,TYPE "$DEV" | awk '$2 == "part" {print $1; exit}')
mkfs.fat -F32 -n "$LABEL" "$PART" >/dev/null

info "Copying the ISO contents..."
mkdir -p "$MNT"
mount "$PART" "$MNT"
bsdtar -x -f "$ISO" -C "$MNT"

info "Boot menu: install (default), restore Timeshift snapshot, rescue shell..."
ENTRIES="$MNT/loader/entries"
SCRIPTS=/run/archiso/bootmnt/arch-setup/usb
# copied files are found by the FAT label, not by the ISO UUID;
# copytoram=n: with the root image in RAM the live system unmounts the stick and script= would not find the scripts
sed -i -E "s|archisosearchuuid=\S+|archisolabel=$LABEL copytoram=n|" "$ENTRIES"/*.conf
INSTALL=$(ls "$ENTRIES"/01-archiso-*.conf)
# script= is run by the live system on tty1 (archiso automated script)
sed -E "s|^title.*|title    Restore Timeshift snapshot|; s|^sort-key.*|sort-key 04|; s|^(options.*)\$|\1 script=$SCRIPTS/restore-snapshot.sh|" \
    "$INSTALL" > "$ENTRIES/04-restore-snapshot.conf"
sed -E "s|^title.*|title    Rescue shell (live system, no script)|; s|^sort-key.*|sort-key 05|" \
    "$INSTALL" > "$ENTRIES/05-rescue-shell.conf"
sed -i -E "s|^title.*|title    Install Arch Linux (automatic)|; s|^(options.*)\$|\1 script=$SCRIPTS/autoinstall.sh|" "$INSTALL"
sed -i 's/^timeout.*/timeout 5/' "$MNT/loader/loader.conf"
grep -H -E '^(title|options)' "$ENTRIES"/*.conf | sed "s|$ENTRIES/||"

info "Copying setup scripts (working tree, without .git)..."
# FAT has no symlinks / permissions → copy the targets, no owners
rsync -rL --exclude=.git --exclude=/pc "$REPO/" "$MNT/arch-setup/"

# Wi-Fi of this PC (NetworkManager) → the installer connects by itself; the password is then on the stick
# by UUID: several profiles may share one name (nmcli then prints the value of each)
WIFI_CONN=$(nmcli -t -f UUID,TYPE connection show --active 2>/dev/null | awk -F: '$2 == "802-11-wireless" {print $1; exit}')
if [ -n "$WIFI_CONN" ]; then
    WIFI_SSID=$(nmcli -s -g 802-11-wireless.ssid connection show uuid "$WIFI_CONN")
    WIFI_PASS=$(nmcli -s -g 802-11-wireless-security.psk connection show uuid "$WIFI_CONN")
    printf 'WIFI_SSID=%q\nWIFI_PASS=%q\n' "$WIFI_SSID" "$WIFI_PASS" > "$MNT/wifi.conf"
    ok "Wi-Fi \"$WIFI_SSID\" saved to the stick (wifi.conf, password in plain text)"
else
    warn "No active Wi-Fi here → the installer uses a cable or asks for a Wi-Fi network"
fi

sync
ok "USB stick ready: boot it (UEFI, Secure Boot off + setup mode) and the installation starts by itself"
