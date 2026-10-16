#!/usr/bin/env bash
# Úklid po převodu Manjaro → Arch (2026-10-11): jméno stroje, .pacnew / .pacsave.
# Spouštět: sudo bash pc/arch-post-cleanup.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Spusť přes sudo."; exit 1; }

echo "== 1. Jméno stroje redo (převod smazal /etc/hostname, k3s založil uzel rag.local)"
hostnamectl set-hostname redo
cat /etc/hostname
rm -f /etc/hostname.pacsave

echo "== 2. pacman.conf: doplnit DownloadUser = alpm (zbytek nechat: Color, IgnorePkg = grub, multilib)"
grep -q '^DownloadUser' /etc/pacman.conf || sed -i 's/^ParallelDownloads = 5$/ParallelDownloads = 5\nDownloadUser = alpm/' /etc/pacman.conf
grep -nE '^(ParallelDownloads|DownloadUser|IgnorePkg|Color)' /etc/pacman.conf
rm -f /etc/pacman.conf.pacnew

echo "== 3. Převzít nové verze (makepkg fortran, tpm2-tss profily v novém formátu)"
mv /etc/makepkg.conf.d/fortran.conf.pacnew /etc/makepkg.conf.d/fortran.conf
mv /etc/tpm2-tss/fapi-profiles/P_ECCP384SHA384.json.pacnew /etc/tpm2-tss/fapi-profiles/P_ECCP384SHA384.json
mv /etc/tpm2-tss/fapi-profiles/P_RSA3072SHA384.json.pacnew /etc/tpm2-tss/fapi-profiles/P_RSA3072SHA384.json

echo "== 4. Nechat naše, .pacnew zahodit (locale.gen, mkinitcpio.conf s keyfile, plymouthd.conf, mirrorlist)"
rm -f /etc/locale.gen.pacnew /etc/mkinitcpio.conf.pacnew /etc/plymouth/plymouthd.conf.pacnew /etc/pacman.d/mirrorlist.pacnew

echo "== 5. Zbytky Manjara (.pacsave)"
rm -f /etc/pamac.conf.pacsave /etc/pacman-mirrors.conf.pacsave /etc/mkinitcpio.d/linux612.preset.pacsave /etc/mkinitcpio.d/linux71.preset.pacsave

echo "== 6. Restart k3s pod jménem redo"
systemctl restart k3s
sleep 40
k3s kubectl get nodes

echo "== Zbylé .pacnew / .pacsave:"
find /etc \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null || true
