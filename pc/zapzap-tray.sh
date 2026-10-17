#!/bin/bash
# ZapZap (WhatsApp, Flatpak) look: monochrome light tray icon, and the white outline WhatsApp icon of the
# Simpleton theme instead of ZapZap's built-in one (via a sitecustomize hook loaded through PYTHONPATH,
# set with `flatpak override`; the Flatpak itself is not modified and updates keep working).
# Safe to run again. Undo: flatpak override --user --unset-env=PYTHONPATH com.rtosta.zapzap
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=com.rtosta.zapzap
DATA="$HOME/.var/app/$APP/data/tray-override"
CONF="$HOME/.var/app/$APP/config/ZapZap/ZapZap.conf"

mkdir -p "$DATA" "$(dirname "$CONF")"
cp "$REPO/pc/zapzap-tray/sitecustomize.py" "$DATA/sitecustomize.py"
flatpak override --user --env=PYTHONPATH="$DATA" "$APP"

# ZapZap's own setting: symbolic light tray icon (QSettings ini, [system] tray_theme)
touch "$CONF"
if grep -q '^tray_theme=' "$CONF"; then
    sed -i 's/^tray_theme=.*/tray_theme=symbolic_light/' "$CONF"
elif grep -q '^\[system\]' "$CONF"; then
    sed -i '/^\[system\]/a tray_theme=symbolic_light' "$CONF"
else
    printf '\n[system]\ntray_theme=symbolic_light\n' >> "$CONF"
fi
echo "==> ZapZap tray icon configured (restart ZapZap to apply)"
