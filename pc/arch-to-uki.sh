#!/usr/bin/env bash
# Přechod z GRUBu (šifrovaný /boot, heslo v textovém GRUBu) na systemd-boot + UKI:
# jádro + initramfs jako jeden soubor .efi na nešifrovaném ESP, heslo k LUKS se ptá Plymouth v grafice.
# Initramfs přechází na systemd hooky (sd-encrypt), z initramfs mizí crypto_keyfile.bin
# (UKI leží na nešifrovaném ESP, keyfile by tam byl čitelný).
#
# GRUB zůstává jako záloha: položka „manjaro“ v boot menu firmwaru (F12). Bootuje dál
# /boot/vmlinuz-* + /boot/initramfs-*.img, jen se heslo zeptá dvakrát (GRUB, pak Plymouth).
# Odebrání GRUBu a keyslotu s keyfile = samostatný krok až po ověření.
#
# Spuštění:    sudo bash pc/arch-to-uki.sh        (od fáze 1)
# Pokračování: sudo bash pc/arch-to-uki.sh 3      (od fáze 3)
# Jen jedna fáze: sudo bash pc/arch-to-uki.sh 2 2
set -euo pipefail
export LANG=C

START=${1:-1}
END=${2:-5}
BACKUP=/mnt/data/backup/arch-to-uki
LUKS_UUID=55b62d42-4184-41bc-9f97-7765ed5e7619
LUKS_NAME=luks-$LUKS_UUID
ESP=/boot/efi
CMDLINE="root=/dev/mapper/$LUKS_NAME rootflags=subvol=@ rw quiet splash udev.log_priority=3"
HOOKS="base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems"

phase() { # číslo, název
  [[ $1 -ge $START && $1 -le $END ]] || return 1
  echo
  echo "================ Fáze $1: $2 ================"
}

confirm() {
  read -rp "Pokračovat? [a/N] " answer
  [[ $answer =~ ^([aAyY]|ano)$ ]] || { echo "Zastaveno. Pokračovat: sudo bash $0 ${CURRENT:-$START}"; exit 1; }
}

[[ $EUID -eq 0 ]] || { echo "Spusť přes sudo."; exit 1; }

CURRENT=1
if phase 1 "Kontroly, snapshot, zálohy"; then
  [[ -d /sys/firmware/efi ]] || { echo "Systém nebootuje v UEFI."; exit 1; }
  mountpoint -q "$ESP" || { echo "$ESP není připojený."; exit 1; }
  df -h "$ESP"
  pacman -Q systemd plymouth mkinitcpio
  timeshift --create --comments "pred-uki" --tags O
  mkdir -p "$BACKUP"
  cp --update=none /etc/mkinitcpio.conf /etc/mkinitcpio.d/linux.preset /etc/mkinitcpio.d/linux-lts.preset /etc/crypttab "$BACKUP/"
  [[ -f $BACKUP/esp.tar.gz ]] || tar -czf "$BACKUP/esp.tar.gz" -C "$ESP" .
  efibootmgr >"$BACKUP/efibootmgr.txt"
  ls -la "$BACKUP"
  confirm
fi

CURRENT=2
if phase 2 "Konfigurace initramfs, cmdline, Plymouth"; then
  # sd-encrypt čte /etc/crypttab.initramfs (platí pro UKI i pro záložní GRUB); bez keyfile → heslo v Plymouthu
  echo "$LUKS_NAME UUID=$LUKS_UUID none luks" >/etc/crypttab.initramfs
  echo "$CMDLINE" >/etc/kernel/cmdline
  sed -i -e "s|^HOOKS=.*|HOOKS=($HOOKS)|" -e 's|^FILES=.*|FILES=()|' /etc/mkinitcpio.conf
  for k in linux linux-lts; do
    cat >/etc/mkinitcpio.d/$k.preset <<EOF
# mkinitcpio preset pro '$k': initramfs pro záložní GRUB + UKI pro systemd-boot
ALL_kver="/boot/vmlinuz-$k"
PRESETS=('default')
default_image="/boot/initramfs-$k.img"
default_uki="$ESP/EFI/Linux/arch-$k.efi"
EOF
  done
  plymouth-set-default-theme bgrt
  echo "-- crypttab.initramfs:"; cat /etc/crypttab.initramfs
  echo "-- kernel/cmdline:"; cat /etc/kernel/cmdline
  echo "-- mkinitcpio.conf:"; grep -E '^(HOOKS|FILES)=' /etc/mkinitcpio.conf
  echo "-- Plymouth:"; plymouth-set-default-theme
  confirm
fi

CURRENT=3
if phase 3 "Sestavení UKI a initramfs"; then
  mkdir -p "$ESP/EFI/Linux"
  mkinitcpio -P
  ls -la "$ESP/EFI/Linux" /boot/initramfs-*.img
  df -h "$ESP"
  for k in linux linux-lts; do
    echo "-- kontrola /boot/initramfs-$k.img"
    content=$(lsinitcpio "/boot/initramfs-$k.img")
    grep -q 'crypto_keyfile.bin' <<<"$content" && { echo "CHYBA: keyfile je pořád v initramfs"; exit 1; }
    grep -E '^etc/crypttab$|systemd-cryptsetup$|plymouthd$' <<<"$content"
  done
  confirm
fi

CURRENT=4
if phase 4 "Instalace systemd-boot"; then
  bootctl --esp-path="$ESP" install
  cat >"$ESP/loader/loader.conf" <<EOF
default arch-linux.efi
timeout 3
console-mode keep
editor no
EOF
  systemctl enable systemd-boot-update.service
  bootctl --esp-path="$ESP" list
  efibootmgr
  confirm
fi

CURRENT=5
if phase 5 "Kontrola"; then
  bootctl --esp-path="$ESP" status | head -25
  echo
  echo "Hotovo. Restartuj: systemd-boot → Arch Linux → heslo v grafice (Plymouth)."
  echo "Když UKI nenastartuje: F12 → položka 'manjaro' (GRUB) → heslo 2× (GRUB, Plymouth)."
  echo "Úplný návrat: Timeshift snapshot pred-uki, zálohy v $BACKUP."
fi
