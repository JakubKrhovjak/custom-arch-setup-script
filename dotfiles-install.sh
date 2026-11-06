#!/bin/bash

# Shared by both desktops: zsh, Starship, Ghostty, Firefox policy, secrets-sync timer, user dirs, Timeshift schedule. Safe to run again.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'
info() { echo -e "${CYAN}[>]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Dotfiles (existing files are kept as *.bak) ───────────────────────────────
info "Dotfiles (zsh, Starship, Ghostty, Dolphin)..."
install_dotfile() { # source in repo, target
    mkdir -p "$(dirname "$2")"
    if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
        cp "$2" "$2.bak"
    fi
    cp "$1" "$2"
}
install_dotfile "$REPO/dotfiles/zshrc" "$HOME/.zshrc"
install_dotfile "$REPO/dotfiles/zsh/base.zsh" "$HOME/.config/zsh/base.zsh"
install_dotfile "$REPO/dotfiles/zsh/secrets.zsh" "$HOME/.config/zsh/secrets.zsh"   # KWallet loader, no values
install_dotfile "$REPO/dotfiles/zsh/tab-colors.zsh" "$HOME/.config/zsh/tab-colors.zsh"
install_dotfile "$REPO/dotfiles/tab-colors" "$HOME/.config/tab-colors"
install -Dm755 "$REPO/dotfiles/bin/secrets-sync" "$HOME/.local/bin/secrets-sync"     # Proton Pass → KWallet
# Firefox hardening for every profile: uBlock Origin + Proton Pass, no saved logins, no telemetry/sponsored
# content, strict tracking protection, HTTPS-Only, DNS over HTTPS (check in about:policies)
sudo install -Dm644 "$REPO/dotfiles/firefox/policies.json" /etc/firefox/policies/policies.json
# Firefox is the default browser (links from every app, KDE included); Chromium is the second browser
xdg-settings set default-web-browser firefox.desktop
xdg-mime default firefox.desktop text/html x-scheme-handler/http x-scheme-handler/https application/xhtml+xml
command -v kwriteconfig6 >/dev/null && kwriteconfig6 --file kdeglobals --group General --key BrowserApplication firefox.desktop
install -Dm644 -t "$HOME/.config/systemd/user" "$REPO/dotfiles/systemd/secrets-sync.service" "$REPO/dotfiles/systemd/secrets-sync.timer"
systemctl --user daemon-reload
systemctl --user enable secrets-sync.timer   # every 15 min; fails quietly until pass-cli login
install_dotfile "$REPO/dotfiles/starship.toml" "$HOME/.config/starship.toml"
install_dotfile "$REPO/dotfiles/ghostty/config" "$HOME/.config/ghostty/config"
command -v dolphin >/dev/null && install_dotfile "$REPO/dotfiles/dolphin/dolphinrc" "$HOME/.config/dolphinrc"
[ "$(getent passwd "$USER" | cut -d: -f7)" = /usr/bin/zsh ] || chsh -s /usr/bin/zsh
ok "Dotfiles installed"

xdg-user-dirs-update

# ── Timeshift: creates the cron jobs (daily, at boot) from timeshift.json + the first snapshot ──
if command -v timeshift >/dev/null; then
    info "Timeshift schedule + first snapshot..."
    sudo timeshift --check --scripted
    ls /etc/cron.d/ | grep timeshift
else
    info "Timeshift not installed, schedule skipped"
fi

