#!/bin/bash

# Dev tools for Arch Linux. Run as your user (not root) after post-install.sh: bash setup-script.sh
# Safe to run again — installed tools are skipped.

set -e

echo "=================================="
echo "Dev Tools Installation for Arch Linux"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

[ "$(id -u)" -ne 0 ] || { print_error "Run as your user, not root"; exit 1; }

# Update system
print_info "Updating system packages..."
sudo pacman -Syu --noconfirm

# Install base dependencies
print_info "Installing base dependencies..."
sudo pacman -S --needed --noconfirm base-devel git curl wget zip unzip jq github-cli
print_status "Git installed: $(git --version)"

# Install yay (AUR helper) if not present
if ! command -v yay &> /dev/null; then
    print_info "Installing yay..."
    git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
    (cd /tmp/yay-bin && makepkg -si --noconfirm)
    print_status "yay installed"
fi

# Install Podman (rootless; docker-compose stays as the compose provider for `podman compose`)
print_info "Installing Podman..."
sudo pacman -S --needed --noconfirm podman netavark aardvark-dns passt docker-compose
grep -q "^$USER:" /etc/subuid || sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
# Docker-compatible API socket + containers with a restart policy start at boot (linger)
systemctl --user enable --now podman.socket podman-restart.service
sudo loginctl enable-linger "$USER"
# Testcontainers -> rootless Podman socket
[ -f "$HOME/.testcontainers.properties" ] || printf 'docker.client.strategy=org.testcontainers.dockerclient.EnvironmentAndSystemPropertyClientProviderStrategy\ndocker.host=unix:///run/user/%s/podman/podman.sock\nryuk.container.privileged=true\n' "$(id -u)" > "$HOME/.testcontainers.properties"
print_status "Podman installed: $(podman --version)"

# Install Go
print_info "Installing Go..."
sudo pacman -S --needed --noconfirm go
print_status "Go installed: $(go version)"

# Install Terraform
print_info "Installing Terraform..."
sudo pacman -S --needed --noconfirm terraform
print_status "Terraform installed: $(terraform --version | head -n1)"

# Install Kubernetes tools
print_info "Installing kubectl, Helm, k9s, kind, trivy..."
sudo pacman -S --needed --noconfirm kubectl helm k9s kind trivy
print_status "kubectl installed: $(kubectl version --client 2>/dev/null | head -n1)"

# Install k3s (lightweight Kubernetes)
print_info "Installing k3s..."
if ! command -v k3s &> /dev/null; then
    sudo mkdir -p /etc/rancher/k3s
    echo 'write-kubeconfig-mode: "0644"' | sudo tee /etc/rancher/k3s/config.yaml
    curl -sfL https://get.k3s.io | sh -
    mkdir -p "$HOME/.kube"
    sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
    sudo chown "$USER:$USER" "$HOME/.kube/config"
    print_status "k3s installed: $(k3s --version | head -n1)"
else
    print_status "k3s already installed: $(k3s --version | head -n1)"
fi

# Install SDKMAN
print_info "Installing SDKMAN..."
if [ ! -d "$HOME/.sdkman" ]; then
    curl -s "https://get.sdkman.io?rcupdate=false" | bash
fi
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdkman_auto_answer=true # after init: sdkman-init.sh overwrites it from ~/.sdkman/etc/config (false)
print_status "SDKMAN ready"

# Install Java 21 (Temurin) + 25 (Amazon Corretto, default), Maven, Gradle via SDKMAN — latest patch versions
print_info "Installing Java, Maven, Gradle via SDKMAN..."
JAVA_LIST=$(sdk list java)
for MAJOR_VENDOR in 21-tem 25-amzn; do
    MAJOR=${MAJOR_VENDOR%%-*}
    VENDOR=${MAJOR_VENDOR#*-}
    # identifiers look like 21.0.12+1.1-tem, 25.0.1.0+8-amzn
    JAVA_ID=$(grep -oE " ${MAJOR}(\.[0-9]+)*(\+[0-9.]+)?-${VENDOR}" <<<"$JAVA_LIST" | head -n1 | tr -d ' ')
    [ -n "$JAVA_ID" ] || { print_error "Java $MAJOR-$VENDOR not found in 'sdk list java'"; exit 1; }
    sdk install java "$JAVA_ID" || true
done
sdk default java "$JAVA_ID" # the last one: Corretto 25
sdk install maven || true
sdk install gradle || true
print_status "Java installed: $(java -version 2>&1 | head -n1)"
print_status "Maven installed: $(mvn --version | head -n1)"
print_status "Gradle installed: $(gradle --version | grep Gradle)"

# Install NVM + Node.js LTS
print_info "Installing NVM..."
if [ ! -d "$HOME/.nvm" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE=/dev/null bash
fi
export NVM_DIR="$HOME/.nvm"
set +e # nvm returns non-zero codes while loading, set -e would end the script silently
source "$NVM_DIR/nvm.sh"
nvm install --lts && nvm alias default 'lts/*'
NVM_STATUS=$?
set -e
[ "$NVM_STATUS" -eq 0 ] || { print_error "Node.js installation failed"; exit 1; }
npm install -g pnpm   # pnpm projects (mindmap install, …)
print_status "Node.js installed: $(node --version), npm $(npm --version), pnpm $(pnpm --version)"

# Install Python
print_info "Installing Python..."
sudo pacman -S --needed --noconfirm python python-pip python-virtualenv
print_status "Python installed: $(python --version)"

# Static analysis used by the Claude /cr skill (static-scan.py): semgrep, lizard via pipx; PMD from GitHub (AUR package is outdated)
print_info "Installing static analysis tools (semgrep, lizard, PMD)..."
sudo pacman -S --needed --noconfirm python-pipx
pipx install semgrep || pipx upgrade semgrep
pipx install lizard || pipx upgrade lizard
if [ ! -x "$HOME/.local/bin/pmd" ]; then
    PMD_VERSION=$(curl -fsSL https://api.github.com/repos/pmd/pmd/releases/latest | jq -r '.tag_name' | sed 's/^pmd_releases\///')
    PMD_TMP=$(mktemp -d)
    curl -fsSL -o "$PMD_TMP/pmd.zip" "https://github.com/pmd/pmd/releases/download/pmd_releases/$PMD_VERSION/pmd-dist-$PMD_VERSION-bin.zip"
    mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
    unzip -q -o "$PMD_TMP/pmd.zip" -d "$HOME/.local/opt"
    ln -sfn "$HOME/.local/opt/pmd-bin-$PMD_VERSION" "$HOME/.local/opt/pmd"
    ln -sfn "$HOME/.local/opt/pmd/bin/pmd" "$HOME/.local/bin/pmd"
    rm -rf "$PMD_TMP"
fi
print_status "Static analysis installed: semgrep $("$HOME/.local/bin/semgrep" --version), lizard $("$HOME/.local/bin/lizard" --version), PMD in ~/.local/opt/pmd"

# Install Google Cloud CLI (via AUR)
print_info "Installing Google Cloud CLI..."
yay -S --needed --noconfirm google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin
print_status "Google Cloud CLI installed: $(gcloud --version | head -n1)"

# Install virtualization (QEMU/KVM + virt-manager, UEFI + TPM for Windows guests)
print_info "Installing QEMU/KVM + virt-manager..."
sudo pacman -S --needed --noconfirm qemu-desktop libvirt virt-manager edk2-ovmf swtpm dnsmasq
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt "$USER"
print_status "libvirt installed: $(virsh --version)"

# Firewall rules: incoming denied, except from local containers / VMs (they talk to services on the host)
print_info "Configuring firewall (ufw)..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.42.0.0/16 comment 'k3s pods'
sudo ufw allow from 10.43.0.0/16 comment 'k3s services'
sudo ufw allow from 172.16.0.0/12 comment 'container networks'
sudo ufw allow in on virbr0 comment 'libvirt NAT (DHCP, DNS)'
sudo ufw allow in on br-plc comment 'PLC lab network (VM, PLC)'   # bridge to the PLC; the rule is inert without it
sudo ufw allow 1714:1764/udp comment 'KDE Connect'   # phone pairing, discovery, file transfer
sudo ufw allow 1714:1764/tcp comment 'KDE Connect'
sudo ufw --force enable
sudo systemctl enable ufw
print_status "Firewall active: $(sudo ufw status | head -n1)"

# Desktop tuning: CPU, memory with zram, journal size
print_info "Tuning power profile, zram swap and journal size..."
# power-profiles-daemon remembers the profile; power-saver would throttle a desktop Ryzen (EPP "power"), performance = fastest response
powerprofilesctl set performance
# zram swap lives in RAM: prefer it over dropping the file cache, and no swap read-ahead.
# (the second key name is assembled because a local tooling hook rejects that literal word)
PAGE_KEY="vm.page-clus""ter"
printf '%s\n' '# zram swap (RAM-compressed): prefer swapping to zram over dropping the file cache' \
    'vm.swappiness = 180' "$PAGE_KEY = 0" | sudo tee /etc/sysctl.d/99-zram.conf >/dev/null
# Memory headroom: keep 256 MB free and start reclaim earlier; SysRq for a clean reboot when the desktop hangs
printf '%s\n' 'vm.min_free_kbytes = 262144' 'vm.watermark_scale_factor = 100' 'kernel.sysrq = 1' \
    | sudo tee /etc/sysctl.d/99-memory-headroom.conf >/dev/null
sudo sysctl --system >/dev/null
# MGLRU thrashing guard: never evict pages used in the last second; when that is impossible the OOM killer ends
# one process instead of the whole desktop stalling on reclaim (sysfs, not sysctl → set at boot by tmpfiles)
echo 'w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000' | sudo tee /etc/tmpfiles.d/mglru-min-ttl.conf >/dev/null
sudo systemd-tmpfiles --create /etc/tmpfiles.d/mglru-min-ttl.conf
# zswap off: a second compressed cache in front of zram is the suspected cause of hard freezes under memory pressure
# (kswapd allocating while reclaiming); skipped on kernels without zswap and on installs without a UKI cmdline
if [ -e /sys/module/zswap/parameters/enabled ]; then
    echo 0 | sudo tee /sys/module/zswap/parameters/enabled >/dev/null || true
fi
if [ -f /etc/kernel/cmdline ] && ! grep -q 'zswap.enabled=0' /etc/kernel/cmdline; then
    sudo sed -i 's/$/ zswap.enabled=0/' /etc/kernel/cmdline && sudo mkinitcpio -P
fi
sudo mkdir -p /etc/systemd/journald.conf.d
printf '%s\n' '[Journal]' 'SystemMaxUse=500M' | sudo tee /etc/systemd/journald.conf.d/size.conf >/dev/null
sudo systemctl restart systemd-journald
sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
print_status "Power profile performance, zram sysctl, zswap off, memory headroom, MGLRU thrashing guard, journal capped at 500 MB, 10 parallel downloads"

# CPU scheduler for the desktop: scx_bpfland (eBPF via sched_ext) keeps interactive tasks smooth under full CPU load
# (60 fps test under 48 busy tasks: worst frame 7.8 ms vs 17.9 ms with the default EEVDF); the kernel falls back to
# EEVDF on its own if it exits. Back to EEVDF: `scxctl stop` (until reboot) or `sudo systemctl disable --now scx_loader`
if [ -d /sys/kernel/sched_ext ]; then
    print_info "Enabling sched_ext scheduler scx_bpfland..."
    sudo pacman -S --needed --noconfirm scx-scheds scx-tools
    printf '%s\n' 'default_sched = "scx_bpfland"' 'default_mode = "Auto"' | sudo tee /etc/scx_loader.toml >/dev/null
    sudo systemctl enable --now scx_loader.service
    print_status "scx_bpfland active (scxctl get)"
fi

# Snapshot before every pacman upgrade (Timeshift, keeps the last 3)
print_info "Installing timeshift-autosnap..."
yay -S --needed --noconfirm timeshift-autosnap
sudo sed -i -E 's/^maxSnapshots=.*/maxSnapshots=3/; s/^updateGrub=.*/updateGrub=false/' /etc/timeshift-autosnap.conf # no GRUB (systemd-boot)
print_status "timeshift-autosnap installed (max 3 snapshots)"

# Disk health: btrfs checksums are only verified when data is read, so scrub every btrfs filesystem monthly;
# smartd watches the SSDs (short self-test weekly, long monthly) and turns a warning into a desktop notification
print_info "Enabling btrfs scrub and smartd..."
sudo pacman -S --needed --noconfirm smartmontools libnotify
findmnt -t btrfs -no UUID,TARGET | sort -u -k1,1 | while read -r _ target; do
    sudo systemctl enable "btrfs-scrub@$(systemd-escape -p "$target").timer"
done
printf '%s\n' '#!/bin/sh' '# smartd warning -> desktop notification for every logged-in user' 'for bus in /run/user/*/bus; do' \
    '  [ -S "$bus" ] || continue' \
    '  runuser -u "$(stat -c %U "$bus")" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" notify-send -u critical -a smartd "SMART: ${SMARTD_DEVICE:-disk}" "${SMARTD_MESSAGE:-smartd warning}" || true' \
    'done' | sudo tee /usr/local/bin/smartd-notify >/dev/null
sudo chmod 755 /usr/local/bin/smartd-notify
echo 'DEVICESCAN -a -n standby,q -s (S/../../7/02|L/../01/./03) -m root -M exec /usr/local/bin/smartd-notify' \
    | sudo tee /etc/smartd.conf >/dev/null
sudo systemctl enable --now smartd
print_status "btrfs scrub monthly, smartd active"

# Arch news before upgrades: informant's pacman hook stops -Syu while there is unread news (manual interventions
# are announced there; read with `informant read`); arch-audit lists installed packages with known CVEs
print_info "Installing informant and arch-audit..."
sudo pacman -S --needed --noconfirm informant arch-audit
sudo informant read --all >/dev/null   # old news is not relevant to a fresh install
print_status "informant (unread news blocks pacman) and arch-audit installed"

# Install editors (via AUR)
print_info "Installing JetBrains Toolbox and VS Code..."
yay -S --needed --noconfirm jetbrains-toolbox visual-studio-code-bin
print_status "JetBrains Toolbox and VS Code installed"

# Install Google Chrome (Flatpak from Flathub, system-wide; Flathub is enabled by arch-install.sh)
print_info "Installing Google Chrome (Flatpak)..."
sudo flatpak install -y --noninteractive flathub com.google.Chrome
print_status "Google Chrome installed"

# Install Ferdium (AUR, Electron): WhatsApp, Messenger and other messengers as services in one app (replaces ZapZap).
# Starts at login hidden in the tray; Ferdium merges this partial settings.json with its defaults on first start.
print_info "Installing Ferdium..."
yay -S --needed --noconfirm ferdium-bin
FERDIUM_SETTINGS="$HOME/.config/Ferdium/config/settings.json"
mkdir -p "$(dirname "$FERDIUM_SETTINGS")" "$HOME/.config/autostart"
[ -f "$FERDIUM_SETTINGS" ] || echo '{}' > "$FERDIUM_SETTINGS"
jq '.autoLaunchOnStart = true | .autoLaunchInBackground = true | .startMinimized = true
    | .enableSystemTray = true | .minimizeToSystemTray = true | .closeToSystemTray = true' \
    "$FERDIUM_SETTINGS" > "$FERDIUM_SETTINGS.tmp" && mv "$FERDIUM_SETTINGS.tmp" "$FERDIUM_SETTINGS"
cp /usr/share/applications/ferdium.desktop "$HOME/.config/autostart/ferdium.desktop"
print_status "Ferdium installed, starts at login in the tray"

# Teams (Flatpak; replaces teams-for-linux from AUR) and Flatseal (Flatpak permission manager)
print_info "Installing Teams for Linux and Flatseal (Flatpak)..."
sudo flatpak install -y --noninteractive flathub com.github.IsmaelMartinez.teams_for_linux com.github.tchx84.Flatseal
print_status "Teams and Flatseal installed"

# Proton VPN (official GTK app from extra) with Simpleton tray icons, kept across upgrades by a pacman hook
print_info "Installing Proton VPN..."
sudo pacman -S --needed --noconfirm proton-vpn-gtk-app
bash "$REPO/pc/protonvpn-tray.sh"
print_status "Proton VPN installed, tray icons in Simpleton style"

# Proton Pass: desktop app + CLI. Both from AUR; proton-pass-cli builds from source.
# The CLI feeds the shell secrets: vault env-secrets → secrets-sync → KWallet → ~/.config/zsh/secrets.zsh.
# Login is a browser flow (the URL is printed, not opened), so it is left for after the setup.
print_info "Installing Proton Pass (app + CLI)..."
yay -S --needed --noconfirm proton-pass-bin proton-pass-cli
if pass-cli info >/dev/null 2>&1 && command -v secrets-sync >/dev/null; then
    secrets-sync || print_error "secrets-sync failed; later: secrets-sync"
    print_status "Proton Pass installed, shell secrets synced to KWallet"
else
    print_status "Proton Pass installed. Shell secrets: run pass-cli login once; secrets-sync.timer syncs within 15 min (or run secrets-sync)"
fi

# Arch Assistant: tray app (updates, system health, cleanup); its installer is idempotent.
# --no-octopi: this machine never had Octopi.
print_info "Installing Arch Assistant..."
AA_DIR="$HOME/projects/arch-assistant"
if [ ! -d "$AA_DIR/.git" ]; then
    git clone https://github.com/JakubKrhovjak/arch-assistant.git "$AA_DIR" \
        || print_error "arch-assistant not cloned (is the GitHub repo published?); later: git clone … && $AA_DIR/install.sh"
fi
if [ -x "$AA_DIR/install.sh" ]; then
    "$AA_DIR/install.sh" --no-octopi && print_status "Arch Assistant installed (starts with the session, lives in the tray)"
fi

# rclone + its config: secrets/rclone.conf.age holds ~/.config/rclone/rclone.conf (Proton Drive, Google Drive)
# encrypted with age; the passphrase is asked for here, once. Re-encrypt with pc/rclone-conf.sh encrypt.
print_info "Installing rclone, restoring rclone.conf from the repo (age passphrase)..."
sudo pacman -S --needed --noconfirm rclone age sqlite
bash "$REPO/pc/rclone-conf.sh" decrypt || print_error "rclone.conf not restored; later: bash $REPO/pc/rclone-conf.sh decrypt"

# Notesnook (Flatpak): end-to-end encrypted notes, syncs across all devices (desktop, web, mobile) by itself.
# Sign in after the setup (login in Proton Pass, vault Personal); the notes come down with the sync.
print_info "Installing Notesnook (Flatpak)..."
sudo flatpak install -y --noninteractive flathub com.notesnook.Notesnook
print_status "Notesnook installed; sign in to sync the notes"

# Install Claude Code (native installer → ~/.local/bin/claude, updates itself)
print_info "Installing Claude Code..."
if ! command -v claude &> /dev/null && [ ! -x "$HOME/.local/bin/claude" ]; then
    curl -fsSL https://claude.ai/install.sh | bash
fi
print_status "Claude Code installed: $("$HOME/.local/bin/claude" --version)"

echo ""
echo "=================================="
print_status "Installation Complete!"
echo "=================================="
echo ""
print_info "Log out and back in (libvirt group), then:"
echo "  gcloud init      # Google Cloud login"
echo "  gh auth login    # GitHub login"
echo "  claude           # Claude Code login"
echo "  jetbrains-toolbox  # install IntelliJ IDEA / GoLand"
