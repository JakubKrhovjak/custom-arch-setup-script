#!/bin/bash

# Desk after the first login: dotfiles, the desk repository in ~/.config and its own install.sh.
# Runs from the text console, there is no desktop yet. Safe to run again.
# DESK_GIT_BASE points the clones elsewhere (a test server in the VM test, see vm-test/).

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "${CYAN}[>]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }

[ "$(id -u)" -ne 0 ] || { echo "Run as your user, not root"; exit 1; }
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_BASE="${DESK_GIT_BASE:-https://github.com/JakubKrhovjak/}"
GIT_DIR_DESK="$HOME/.local/share/desk.git"

# Parallel AUR builds: /etc/makepkg.conf leaves MAKEFLAGS commented out, so make runs on one core
[ -f "$HOME/.makepkg.conf" ] || printf '%s\n' '# Parallel builds for makepkg / yay (AUR): use all CPU cores' 'MAKEFLAGS="-j$(nproc)"' > "$HOME/.makepkg.conf"

bash "$REPO/dotfiles-install.sh"

# The repository's work tree is ~/.config, so it is cloned in place (same steps as the README in the desk repository).
# The submodule URL is SSH for pushing; both repositories are public, so the first clone goes over HTTPS without a login.
if [ ! -d "$GIT_DIR_DESK" ]; then
    info "Cloning desk into ~/.config..."
    mkdir -p "$HOME/.config" "$(dirname "$GIT_DIR_DESK")"
    git init -q -b main --separate-git-dir="$GIT_DIR_DESK" "$HOME/.config"
    git -C "$HOME/.config" remote add origin "${GIT_BASE}desk.git"
fi
git -C "$HOME/.config" fetch -q origin
# Files the dotfiles step placed in ~/.config and the repository also has (Ghostty) are replaced by the repository's
git -C "$HOME/.config" checkout -q -f -B main --track origin/main
git -C "$HOME/.config" -c "url.${GIT_BASE}.insteadOf=git@github.com:JakubKrhovjak/" submodule update --init
ok "Desk repository in ~/.config"

"$HOME/.config/desk/install.sh"
ok "Desk installed"
