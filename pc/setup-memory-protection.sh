#!/usr/bin/env bash
# Ochrana proti zamrznutí při vyčerpání RAM (2026-10-10: VM + k3s + Teams sežraly 31 GB, bez swapu → zátěž 160, tvrdý reset).
# 1) zram swap 8 GB (komprimovaný swap v RAM) — systém při nedostatku paměti zpomalí místo zamrznutí.
# 2) earlyoom — při < 5 % volné RAM i swapu ukončí největší proces; přednostně Teams / prohlížeče / VS Code,
#    nikdy VM (qemu), desktop (kwin, plasmashell) ani k3s.
set -euo pipefail

echo "== Balíčky =="
sudo pacman -S --needed --noconfirm zram-generator earlyoom

echo "== zram swap 8 GB =="
printf '[zram0]\nzram-size = 8192\ncompression-algorithm = zstd\nswap-priority = 100\n' | sudo tee /etc/systemd/zram-generator.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service
swapon --show

echo "== earlyoom =="
printf '%s\n' 'EARLYOOM_ARGS="-m 5 -s 5 -r 3600 -n --prefer (^|/)(teams-for-linux|chrome|chromium|firefox|electron|code)$ --avoid (^|/)(qemu-system-x86_64|kwin_wayland|plasmashell|sddm|Xwayland|k3s-server|systemd|sshd)$"' | sudo tee /etc/default/earlyoom >/dev/null
sudo systemctl enable --now earlyoom.service
systemctl --no-pager status earlyoom.service | head -5

echo
echo "Hotovo."
free -h
