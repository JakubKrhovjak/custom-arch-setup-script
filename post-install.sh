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

info "Applying Simpleton look-and-feel..."
plasma-apply-lookandfeel -a org.simpleton.dark.desktop
plasma-apply-wallpaperimage "$SHARE/wallpapers/Simpleton" || true
ok "Simpleton applied"

# ── Plasma settings ────────────────────────────────────────────────────────────
info "Plasma settings (Ghostty, keyboard, formats, effects)..."
kwriteconfig6 --file kdeglobals --group General --key TerminalApplication ghostty
kwriteconfig6 --file kdeglobals --group General --key TerminalService com.mitchellh.ghostty.desktop
kwriteconfig6 --file kxkbrc --group Layout --key Use true
kwriteconfig6 --file kxkbrc --group Layout --key LayoutList us,cz
kwriteconfig6 --file kxkbrc --group Layout --key VariantList ,qwerty
kwriteconfig6 --file plasma-localerc --group Formats --key LANG en_US.UTF-8
kwriteconfig6 --file plasma-localerc --group Formats --key LC_TIME cs_CZ.UTF-8
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key contrastEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key glideEnabled true

# ── Login screen (SDDM Breeze greeter in Simpleton colors + wallpaper) ────────
info "Login screen..."
WALLPAPER=$(ls "$SHARE"/wallpapers/Simpleton/contents/images/* | head -n1)
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
printf '[Mouse]\ncursorTheme=breeze_cursors\n' | sudo tee "$SDDM_CFG/kcminputrc" >/dev/null
sudo chown sddm:sddm "$SDDM_CFG"/*
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

echo ""
ok "Done. Log out and back in to see everything (login screen included)."
echo "  Next: bash $REPO/setup-script.sh"
