#!/bin/bash

# Live USB rescue: roll the system (@) back to a Timeshift snapshot, the same way Timeshift does it.
# The broken @ is kept as @broken-<date> (delete it later from the running system).
# Runs by itself from the "Restore Timeshift snapshot" boot entry of the USB stick (make-usb.sh).

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

pick() { # prompt, options… → prints the chosen option
    local prompt=$1; shift
    local options=("$@") choice
    if [ ${#options[@]} -eq 1 ]; then
        echo "${options[0]}"
        return
    fi
    for i in "${!options[@]}"; do echo "  $((i + 1))) ${options[$i]}" >&2; done
    while true; do
        read -rp "$prompt [1-${#options[@]}]: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )) && break
        warn "Enter a number from the list" >&2
    done
    echo "${options[$((choice - 1))]}"
}

clear
echo -e "${CYAN}══════════ Restore a Timeshift snapshot ══════════${NC}"

mapfile -t PARTS < <(lsblk -lnp -o NAME,FSTYPE | awk '$2 == "crypto_LUKS" {print $1}')
[ ${#PARTS[@]} -gt 0 ] || die "No encrypted (LUKS) partition found"
PART=$(pick "Encrypted system partition" "${PARTS[@]}")
info "System partition: $PART"

[ -e /dev/mapper/root ] || cryptsetup open "$PART" root
mount -o subvolid=5 /dev/mapper/root /mnt
trap 'umount /mnt 2>/dev/null; cryptsetup close root 2>/dev/null' EXIT

SNAPDIR=/mnt/timeshift-btrfs/snapshots
mapfile -t SNAPS < <(find "$SNAPDIR" -mindepth 2 -maxdepth 2 -name @ -printf '%h\n' 2>/dev/null | xargs -rn1 basename | sort -r)
[ ${#SNAPS[@]} -gt 0 ] || die "No Timeshift snapshots in $SNAPDIR"
echo "Snapshots (newest first):"
SNAP=$(pick "Restore snapshot" "${SNAPS[@]}")

BROKEN="@broken-$(date +%Y-%m-%d_%H-%M)"
warn "The system (@) will be replaced by snapshot $SNAP; the current one is kept as $BROKEN. Type 'yes':"
read -r CONFIRM
[ "$CONFIRM" = yes ] || die "Aborted."

mv /mnt/@ "/mnt/$BROKEN"
btrfs subvolume snapshot "$SNAPDIR/$SNAP/@" /mnt/@
ok "System restored to $SNAP (old one: $BROKEN)"
echo "  After reboot the UKIs are rebuilt by uki-match-kernel if the kernel changed (one extra reboot)."
echo "  When all works: sudo mount -o subvolid=5 /dev/mapper/root /mnt && sudo btrfs subvolume delete /mnt/$BROKEN"

umount /mnt
cryptsetup close root
trap - EXIT
# the live system runs from the stick (copytoram=n) → pull it out only when the PC is off
echo "Press Enter to power off. Then remove the USB stick, enable Secure Boot in BIOS again and boot."
read -r
poweroff
