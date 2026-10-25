#!/bin/bash
# Proton VPN look: monochrome Simpleton tray icons (disconnected / connected / error).
# The app sends the tray a file path (assets/icons/state-*.svg), not an icon name, so the icon theme
# cannot override it. The files are replaced instead, and a pacman hook replaces them again after every
# proton-vpn-gtk-app upgrade. The app icon itself comes from the theme (Simpleton proton-vpn-logo.svg).
# Safe to run again. Undo: sudo rm /etc/pacman.d/hooks/protonvpn-tray.hook && sudo pacman -S proton-vpn-gtk-app
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARE=/usr/local/share/protonvpn-tray
APPLY=/usr/local/bin/protonvpn-tray-icons

sudo install -Dm644 -t "$SHARE" "$REPO"/pc/protonvpn-tray/state-{connected,disconnected,error}.svg

sudo tee "$APPLY" > /dev/null <<EOF
#!/bin/bash
for dir in /usr/lib/python3*/site-packages/proton/vpn/app/gtk/assets/icons; do
    [ -d "\$dir" ] && install -m644 $SHARE/state-*.svg "\$dir/"
done
exit 0
EOF
sudo chmod 755 "$APPLY"

sudo install -d /etc/pacman.d/hooks
sudo tee /etc/pacman.d/hooks/protonvpn-tray.hook > /dev/null <<EOF
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = proton-vpn-gtk-app

[Action]
Description = Simpleton tray icons for Proton VPN
When = PostTransaction
Exec = $APPLY
EOF

sudo "$APPLY"
echo "==> Proton VPN tray icons replaced (restart Proton VPN to apply)"
