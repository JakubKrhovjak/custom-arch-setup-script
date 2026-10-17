#!/bin/bash

# Look & feel after the first login: Simpleton theme (also on the login screen), Ghostty, zsh + Starship.
# Run as your user inside Plasma: bash post-install.sh   (safe to run again)

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'
info() { echo -e "${CYAN}[>]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }

[ "$(id -u)" -ne 0 ] || { echo "Run as your user, not root"; exit 1; }
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARE=/usr/share

# ── Simpleton theme (system-wide, so the login screen sees it too) ────────────
info "Installing Simpleton theme to $SHARE..."
sudo cp -rT "$REPO/theme/icons/Simpleton" "$SHARE/icons/Simpleton"
sudo cp -rT "$REPO/theme/plasma/desktoptheme/simpleton" "$SHARE/plasma/desktoptheme/simpleton"
sudo cp -rT "$REPO/theme/plasma/look-and-feel/org.simpleton.dark.desktop" "$SHARE/plasma/look-and-feel/org.simpleton.dark.desktop"
sudo cp -rT "$REPO/theme/wallpapers/Simpleton" "$SHARE/wallpapers/Simpleton"
sudo install -Dm644 "$REPO/theme/color-schemes/BreathSlate.colors" "$SHARE/color-schemes/BreathSlate.colors"
sudo gtk-update-icon-cache -f -q "$SHARE/icons/Simpleton" || true

# Parallel AUR builds: /etc/makepkg.conf leaves MAKEFLAGS commented out, so make runs on one core
[ -f "$HOME/.makepkg.conf" ] || printf '%s\n' '# Parallel builds for makepkg / yay (AUR): use all CPU cores' 'MAKEFLAGS="-j$(nproc)"' > "$HOME/.makepkg.conf"

# Klassy application style: rounded buttons and frames (Simpleton's widgetStyle). Built from AUR against
# the installed Plasma/Qt — the -bin package breaks on newer Qt. Takes a few minutes.
info "Installing Klassy application style (AUR build)..."
yay -S --needed --noconfirm --removemake klassy-git
mkdir -p "$HOME/.config/klassy"
cp "$REPO/dotfiles/klassy/klassyrc" "$HOME/.config/klassy/klassyrc"

info "Applying Simpleton look-and-feel..."
plasma-apply-lookandfeel -a org.simpleton.dark.desktop
# Simpleton for both light and dark mode: the "Dark Mode" toggle in Brightness & Color would otherwise
# switch the whole desktop to Breeze / Breeze Dark (icons included)
kwriteconfig6 --file kdeglobals --group KDE --key DefaultLightLookAndFeel org.simpleton.dark.desktop
kwriteconfig6 --file kdeglobals --group KDE --key DefaultDarkLookAndFeel org.simpleton.dark.desktop
WALLPAPER=$(ls "$SHARE"/wallpapers/Simpleton/contents/images/* | head -n1)
plasma-apply-wallpaperimage "$WALLPAPER"
# panel at the top edge (Plasma default is bottom)
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'panels().forEach(function (p) { p.location = "top"; })'
# weather widget, no Show Desktop, Bluetooth/Volume/Clipboard in the tray's hidden section, ZapZap launcher
bash "$REPO/pc/panel-setup.sh" || info "panel layout not applied; later: bash $REPO/pc/panel-setup.sh"
ok "Simpleton applied, panel at the top"

# Baloo (file indexer): since Plasma 6.8 baloo_file_extractor starts before WAYLAND_DISPLAY is set and
# crashes in a loop ("no Qt platform plugin"), hundreds of core dumps per boot. It needs no GUI.
mkdir -p "$HOME/.config/systemd/user/kde-baloo.service.d"
printf '%s\n' '[Service]' 'Environment=QT_QPA_PLATFORM=offscreen' > "$HOME/.config/systemd/user/kde-baloo.service.d/offscreen.conf"
systemctl --user daemon-reload

# ── Plasma settings ────────────────────────────────────────────────────────────
info "Plasma settings (Ghostty, keyboard, Num Lock, formats, effects)..."
kwriteconfig6 --file kdeglobals --group General --key TerminalApplication ghostty
kwriteconfig6 --file kdeglobals --group General --key TerminalService com.mitchellh.ghostty.desktop
kwriteconfig6 --file kxkbrc --group Layout --key Use true
kwriteconfig6 --file kxkbrc --group Layout --key LayoutList us,cz
kwriteconfig6 --file kxkbrc --group Layout --key VariantList ,qwerty
kwriteconfig6 --file kcminputrc --group Keyboard --key NumLock 0   # 0 = on at Plasma start
kwriteconfig6 --file plasma-localerc --group Formats --key LANG en_US.UTF-8
kwriteconfig6 --file plasma-localerc --group Formats --key LC_TIME cs_CZ.UTF-8
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key contrastEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key glideEnabled true
# Toolbox JetBrains: okno jen v tray, ne v liste uloh (pravidlo KWin).
# Plasma 6.8 drzi seznam pravidel v klici "Order"; existujici polozky se nesmi prepsat.
kwin_rules=$(kreadconfig6 --file kwinrulesrc --group General --key Order 2>/dev/null || true)
if [[ ",$kwin_rules," != *",toolbox-tray,"* ]]; then
    kwriteconfig6 --file kwinrulesrc --group General --key Order "${kwin_rules:+$kwin_rules,}toolbox-tray"
fi
kwriteconfig6 --file kwinrulesrc --group toolbox-tray --key Description "Toolbox jen v tray"
kwriteconfig6 --file kwinrulesrc --group toolbox-tray --key wmclass jetbrains-toolbox
kwriteconfig6 --file kwinrulesrc --group toolbox-tray --key wmclassmatch 1
kwriteconfig6 --file kwinrulesrc --group toolbox-tray --key skiptaskbar true
kwriteconfig6 --file kwinrulesrc --group toolbox-tray --key skiptaskbarrule 2

# ── Login screen (SDDM Breeze greeter in Simpleton colors + wallpaper) ────────
info "Login screen..."
printf '[General]\nbackground=%s\nshowClock=true\ntype=image\n' "$WALLPAPER" \
    | sudo tee "$SHARE/sddm/themes/breeze/theme.conf.user" >/dev/null
SDDM_CFG=/var/lib/sddm/.config
sudo install -d -o sddm -g sddm "$SDDM_CFG"
if [ -f "$HOME/.config/kdeglobals" ]; then
    sudo install -o sddm -g sddm -m644 "$HOME/.config/kdeglobals" "$SDDM_CFG/kdeglobals"
fi
# Plasma 6 does not store values equal to the look-and-feel defaults → write them explicitly
sudo kwriteconfig6 --file "$SDDM_CFG/kdeglobals" --group Icons --key Theme Simpleton
sudo kwriteconfig6 --file "$SDDM_CFG/kdeglobals" --group General --key ColorScheme BreathSlate
printf '[Theme]\nname=simpleton\n' | sudo tee "$SDDM_CFG/plasmarc" >/dev/null
printf '[Keyboard]\nNumLock=0\n\n[Mouse]\ncursorTheme=breeze_cursors\n' | sudo tee "$SDDM_CFG/kcminputrc" >/dev/null
sudo chown -R sddm:sddm "$SDDM_CFG" # no glob: /var/lib/sddm is not readable for the user, "$SDDM_CFG"/* would stay unexpanded
ok "Login screen uses Simpleton"

# ── Dotfiles (existing files are kept as *.bak) ───────────────────────────────
info "Dotfiles (zsh, Starship, Ghostty)..."
install_dotfile() { # source in repo, target
    mkdir -p "$(dirname "$2")"
    if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
        cp "$2" "$2.bak"
    fi
    cp "$1" "$2"
}
install_dotfile "$REPO/dotfiles/zshrc" "$HOME/.zshrc"
install_dotfile "$REPO/dotfiles/zsh/base.zsh" "$HOME/.config/zsh/base.zsh"
install_dotfile "$REPO/dotfiles/starship.toml" "$HOME/.config/starship.toml"
install_dotfile "$REPO/dotfiles/ghostty/config" "$HOME/.config/ghostty/config"
[ "$(getent passwd "$USER" | cut -d: -f7)" = /usr/bin/zsh ] || chsh -s /usr/bin/zsh
ok "Dotfiles installed"

xdg-user-dirs-update

# ── Timeshift: creates the cron jobs (daily, at boot) from timeshift.json + the first snapshot ──
info "Timeshift schedule + first snapshot..."
sudo timeshift --check --scripted
ls /etc/cron.d/ | grep timeshift

echo ""
ok "Done. Log out and back in to see everything (login screen included)."
echo "  Next: bash $REPO/setup-script.sh"
