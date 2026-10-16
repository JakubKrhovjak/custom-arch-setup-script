#!/usr/bin/env bash
# Sloučí datový disk: smaže rozbitou instalaci Windows (nvme0n1p2–p6)
# a roztáhne btrfs oddíl nvme0n1p1 (/mnt/data) přes celý disk.
# Linuxový systémový disk nvme1n1 se nijak nemění.
set -euo pipefail

DISK=/dev/nvme0n1
MODEL=CT1000T700SSD5

# Pojistky: správný disk, p1 je btrfs "data" na /mnt/data, oddíly Windows nejsou připojené
[[ "$(lsblk -dno MODEL "$DISK" | xargs)" == "$MODEL" ]] || { echo "Chyba: $DISK není $MODEL"; exit 1; }
[[ "$(lsblk -no FSTYPE,LABEL "${DISK}p1" | xargs)" == "btrfs data" ]] || { echo "Chyba: ${DISK}p1 není btrfs 'data'"; exit 1; }
[[ "$(findmnt -no TARGET "${DISK}p1")" == "/mnt/data" ]] || { echo "Chyba: ${DISK}p1 není na /mnt/data"; exit 1; }
for n in 2 3 4 5 6; do
  if [[ -e "${DISK}p$n" ]] && findmnt -S "${DISK}p$n" >/dev/null; then echo "Chyba: ${DISK}p$n je připojený"; exit 1; fi
done

echo "== Před =="
sudo parted -s "$DISK" unit GiB print

echo "== Mažu oddíly Windows =="
for n in 6 5 4 3 2; do
  if [[ -e "${DISK}p$n" ]]; then sudo parted -s "$DISK" rm "$n"; fi
done

echo "== Roztahuji oddíl 1 =="
echo Yes | sudo parted ---pretend-input-tty "$DISK" resizepart 1 100%

echo "== Zvětšuji btrfs =="
sudo btrfs filesystem resize max /mnt/data

echo "== Po =="
sudo parted -s "$DISK" unit GiB print
df -h /mnt/data
