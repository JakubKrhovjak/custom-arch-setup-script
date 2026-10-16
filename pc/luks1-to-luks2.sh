#!/usr/bin/env bash
# Převod šifrování systémového disku LUKS1 → LUKS2 bez live USB (příprava na odemykání přes TPM2).
#
# Převod mění jen hlavičku (data se nepřešifrovávají, heslo zůstává). Jde jen se zamčeným diskem,
# proto ho udělá služba v jednorázovém UKI ještě před odemčením. Když převod selže, služba vrátí
# hlavičku ze zálohy přibalené v UKI a disk se odemkne jako LUKS1.
#
# Předem (hotovo 2026-10-11): záloha hlavičky + zkušební převod kopie s jiným UUID
#   /mnt/data/backup/luks2/luks1-header.img, test-luks2.img (heslo ověřit:
#   sudo cryptsetup open --test-passphrase /mnt/data/backup/luks2/test-luks2.img)
#
# 1: sudo bash pc/luks1-to-luks2.sh 1   příprava UKI + jednorázový start, pak restart (jen heslo)
# 2: sudo bash pc/luks1-to-luks2.sh 2   po restartu: kontrola a úklid
# 3: sudo bash pc/luks1-to-luks2.sh 3   heslo na Argon2id (ptá se na heslo → spouští uživatel v terminálu)
set -euo pipefail
export LANG=C

START=${1:-1}
END=${2:-$START}
LUKS_UUID=55b62d42-4184-41bc-9f97-7765ed5e7619
LUKS_DEV=/dev/disk/by-uuid/$LUKS_UUID
BACKUP=/mnt/data/backup/luks2
ESP=/boot/efi
UKI_DIR=$ESP/EFI/luks2
ENTRY=luks2-convert.conf
HOOK=/etc/initcpio/install/luks2-convert
LIB=/usr/local/lib/luks2-convert
CONF=/etc/mkinitcpio-luks2.conf

phase() { # číslo, název
  [[ $1 -ge $START && $1 -le $END ]] || return 1
  echo
  echo "================ Fáze $1: $2 ================"
}

confirm() {
  read -rp "Pokračovat? [a/N] " answer
  [[ $answer =~ ^([aAyY]|ano)$ ]] || { echo "Zastaveno."; exit 1; }
}

luks_version() { cryptsetup luksDump "$1" | sed -n 's/^Version:\s*//p'; }
mk_digest() { cryptsetup luksDump "$1" | sed -n 's/^MK digest:\s*//p'; } # otisk hlavního klíče (LUKS1)

[[ $EUID -eq 0 ]] || { echo "Spusť přes sudo."; exit 1; }

if phase 0 "Test hesla na převedené kopii hlavičky"; then
  cryptsetup open --test-passphrase "$BACKUP/test-luks2.img" && echo "Heslo na kopii LUKS2 funguje."
fi

if phase 1 "Jednorázové UKI s převodem"; then
  [[ $(luks_version "$LUKS_DEV") == 1 ]] || { echo "Disk není LUKS1, není co převádět."; exit 1; }
  [[ $(cryptsetup luksUUID "$BACKUP/luks1-header.img") == "$LUKS_UUID" ]] || { echo "Chybí záloha hlavičky."; exit 1; }
  [[ $(luks_version "$BACKUP/test-luks2.img") == 2 ]] || { echo "Chybí zkušební převod kopie."; exit 1; }
  [[ $(mk_digest "$LUKS_DEV") == "$(mk_digest "$BACKUP/luks1-header.img")" ]] || { echo "Záloha hlavičky nesedí k disku."; exit 1; }

  mkdir -p "$LIB"
  # skript, který poběží v initramfs (busybox sh)
  cat >"$LIB/luks2-convert" <<EOF
#!/bin/sh
dev=$LUKS_DEV
if cryptsetup isLuks --type luks2 "\$dev"; then echo "luks2-convert: už je LUKS2"; exit 0; fi
cryptsetup isLuks --type luks1 "\$dev" || { echo "luks2-convert: není LUKS1, nic nedělám"; exit 1; }
if cryptsetup convert --type luks2 -q "\$dev" && cryptsetup isLuks --type luks2 "\$dev"; then
  echo "luks2-convert: převod hotový"
  exit 0
fi
echo "luks2-convert: převod selhal, vracím hlavičku LUKS1 ze zálohy"
cryptsetup luksHeaderRestore -q "\$dev" --header-backup-file /etc/luks1-header.img
exit 1
EOF
  cat >"$LIB/luks2-convert.service" <<EOF
[Unit]
Description=Převod LUKS1 na LUKS2 (jednorázově)
DefaultDependencies=no
After=$(systemd-escape -p --suffix=device "$LUKS_DEV")
Wants=$(systemd-escape -p --suffix=device "$LUKS_DEV") cryptsetup-pre.target
Before=cryptsetup-pre.target systemd-cryptsetup@$(systemd-escape "luks-$LUKS_UUID").service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh /usr/local/bin/luks2-convert
EOF
  cat >"$HOOK" <<EOF
#!/bin/bash
build() {
  add_binary cryptsetup
  add_file $LIB/luks2-convert /usr/local/bin/luks2-convert 0755
  add_file $BACKUP/luks1-header.img /etc/luks1-header.img 0400
  add_file $LIB/luks2-convert.service /usr/lib/systemd/system/luks2-convert.service
  add_symlink /usr/lib/systemd/system/sysinit.target.wants/luks2-convert.service /usr/lib/systemd/system/luks2-convert.service
}
help() { echo "Jednorázový převod LUKS1 → LUKS2 před odemčením disku."; }
EOF
  sed 's/^HOOKS=(\(.*\))/HOOKS=(\1 luks2-convert)/' /etc/mkinitcpio.conf >"$CONF"
  echo "-- HOOKS: $(grep '^HOOKS' "$CONF")"
  echo "-- služba v initramfs:"; cat "$LIB/luks2-convert.service"

  mkdir -p "$UKI_DIR"
  mkinitcpio -c "$CONF" -k /boot/vmlinuz-linux -U "$UKI_DIR/convert.efi"
  printf 'title   Převod na LUKS2 (jednorázově)\nefi     /EFI/luks2/convert.efi\n' >"$ESP/loader/entries/$ENTRY"
  echo "-- obsah UKI:"; lsinitcpio "$UKI_DIR/convert.efi" | grep -E 'luks2|luks1-header'
  bootctl list --no-pager | grep -E 'title|id:' || true
  echo "Nastavit jako příští start (jen jednou)?"
  confirm
  bootctl set-oneshot "$ENTRY"
  bootctl status --no-pager 2>/dev/null | grep -iE 'oneshot|Current Entry|Default Entry' || true
  echo "Hotovo. Restartuj (bez aktualizace systému mezi tím), zadej heslo jako vždy."
fi

if phase 2 "Po restartu: kontrola a úklid"; then
  echo "-- verze hlavičky: $(luks_version "$LUKS_DEV")"
  journalctl -b -o cat --no-pager | grep -E 'luks2-convert|Převod LUKS1' || true
  [[ $(luks_version "$LUKS_DEV") == 2 ]] || { echo "Disk není LUKS2, nic neuklízím."; exit 1; }
  cryptsetup luksDump "$LUKS_DEV" | grep -E '^Version|^  [0-9]: luks2|PBKDF'
  rm -f "$ESP/loader/entries/$ENTRY" "$UKI_DIR/convert.efi" "$HOOK" "$CONF" "$LIB/luks2-convert" "$LIB/luks2-convert.service" "$BACKUP/test-luks2.img"
  rmdir "$UKI_DIR" "$LIB"
  echo "-- ESP:"; ls -R "$ESP/EFI" "$ESP/loader/entries"
  echo "Další: fáze 3 (Argon2id) spusť sám v terminálu, ptá se na heslo."
fi

if phase 3 "Heslo na Argon2id + nová záloha hlavičky"; then
  [[ $(luks_version "$LUKS_DEV") == 2 ]] || { echo "Disk není LUKS2."; exit 1; }
  cryptsetup luksConvertKey --pbkdf argon2id "$LUKS_DEV"
  cryptsetup luksDump "$LUKS_DEV" | grep -E '^  [0-9]: luks2|PBKDF'
  cryptsetup luksHeaderBackup "$LUKS_DEV" --header-backup-file "$BACKUP/luks2-header.img"
  # záloha LUKS1 obsahuje slot s PBKDF2 (slabší proti hádání hesla) a už se nehodí
  shred -u "$BACKUP/luks1-header.img"
  ls -l "$BACKUP"
fi

echo
echo "Hotovo (fáze $START–$END)."
