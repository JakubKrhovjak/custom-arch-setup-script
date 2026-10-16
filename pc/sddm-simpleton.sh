#!/usr/bin/env bash
# Přihlašovací obrazovka SDDM (téma breeze) ve vzhledu Simpleton.
# SDDM běží jako uživatel sddm a do /home/redo (700) nevidí → téma, ikony,
# barvy a tapetu kopíruje do /usr/share a nastavení do /var/lib/sddm/.config.
# Spouštět: sudo bash pc/sddm-simpleton.sh   (znovu po změně vzhledu)
set -euo pipefail

src=/home/redo/.local/share
cfg=/home/redo/.config
sddmCfg=/var/lib/sddm/.config
breeze=/usr/share/sddm/themes/breeze
backup=/mnt/data/backup/sddm-simpleton

install -d "$backup"
[[ -e $backup/theme.conf.user ]] || cp -a "$breeze/theme.conf.user" "$backup/"
[[ -e $backup/kdeglobals ]] || cp -a "$sddmCfg/kdeglobals" "$backup/"

echo "== kopie vzhledu do /usr/share"
install -d /usr/share/wallpapers /usr/share/plasma/desktoptheme /usr/share/icons /usr/share/color-schemes
cp -rT "$src/wallpapers/Simpleton" /usr/share/wallpapers/Simpleton
cp -rT "$src/plasma/desktoptheme/simpleton" /usr/share/plasma/desktoptheme/simpleton
cp -rT "$src/icons/Simpleton" /usr/share/icons/Simpleton
cp -rT "$src/plasma/look-and-feel/org.simpleton.dark.desktop" /usr/share/plasma/look-and-feel/org.simpleton.dark.desktop
cp "$src/color-schemes/BreathSlate.colors" /usr/share/color-schemes/
chmod -R a+rX /usr/share/wallpapers/Simpleton /usr/share/plasma/desktoptheme/simpleton /usr/share/icons/Simpleton /usr/share/plasma/look-and-feel/org.simpleton.dark.desktop /usr/share/color-schemes/BreathSlate.colors

echo "== tapeta v $breeze/theme.conf.user"
wallpaper=$(ls /usr/share/wallpapers/Simpleton/contents/images/* | head -1)
printf '[General]\nbackground=%s\nshowClock=true\ntype=image\n' "$wallpaper" > "$breeze/theme.conf.user"
cat "$breeze/theme.conf.user"

echo "== nastavení uživatele sddm ($sddmCfg)"
cp "$cfg/kdeglobals" "$sddmCfg/kdeglobals"
# Plasma 6 neukládá hodnoty shodné s balíčkem vzhledu → zapsat natvrdo
kwriteconfig6 --file "$sddmCfg/kdeglobals" --group Icons --key Theme Simpleton
kwriteconfig6 --file "$sddmCfg/kdeglobals" --group General --key ColorScheme BreathSlate
printf '[Theme]\nname=simpleton\n' > "$sddmCfg/plasmarc"
printf '[Mouse]\ncursorTheme=breeze_cursors\n' > "$sddmCfg/kcminputrc"
chown sddm:sddm "$sddmCfg/kdeglobals" "$sddmCfg/plasmarc" "$sddmCfg/kcminputrc"
grep -A1 '^\[Icons\]' "$sddmCfg/kdeglobals"
grep -m1 '^ColorScheme=' "$sddmCfg/kdeglobals"

echo "Hotovo. Ověření: odhlásit se (Start → Odhlásit). Zálohy: $backup"
