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

# Install Docker
print_info "Installing Docker..."
sudo pacman -S --needed --noconfirm docker docker-compose docker-buildx
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
print_status "Docker installed: $(docker --version)"

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
print_status "Node.js installed: $(node --version), npm $(npm --version)"

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
sudo ufw allow from 172.16.0.0/12 comment 'docker networks'
sudo ufw allow in on virbr0 comment 'libvirt NAT (DHCP, DNS)'
sudo ufw --force enable
sudo systemctl enable ufw
print_status "Firewall active: $(sudo ufw status | head -n1)"

# Snapshot before every pacman upgrade (Timeshift, keeps the last 3)
print_info "Installing timeshift-autosnap..."
yay -S --needed --noconfirm timeshift-autosnap
sudo sed -i -E 's/^maxSnapshots=.*/maxSnapshots=3/; s/^updateGrub=.*/updateGrub=false/' /etc/timeshift-autosnap.conf # no GRUB (systemd-boot)
print_status "timeshift-autosnap installed (max 3 snapshots)"

# Install editors (via AUR)
print_info "Installing JetBrains Toolbox and VS Code..."
yay -S --needed --noconfirm jetbrains-toolbox visual-studio-code-bin
print_status "JetBrains Toolbox and VS Code installed"

# Install Google Chrome (Flatpak from Flathub, system-wide; Flathub is enabled by arch-install.sh)
print_info "Installing Google Chrome (Flatpak)..."
sudo flatpak install -y --noninteractive flathub com.google.Chrome
print_status "Google Chrome installed"

# Install WhatsApp client ZapZap (Flatpak, Qt WebEngine; WasIstLos from AUR needs webkit2gtk, which no longer builds)
print_info "Installing WhatsApp (ZapZap, Flatpak)..."
sudo flatpak install -y --noninteractive flathub com.rtosta.zapzap
print_status "WhatsApp (ZapZap) installed"

# rclone + its config: secrets/rclone.conf.age holds ~/.config/rclone/rclone.conf (Proton Drive, Google Drive)
# encrypted with age; the passphrase is asked for here, once. Re-encrypt with pc/rclone-conf.sh encrypt.
print_info "Installing rclone, restoring rclone.conf from the repo (age passphrase)..."
sudo pacman -S --needed --noconfirm rclone age sqlite
bash "$REPO/pc/rclone-conf.sh" decrypt || print_error "rclone.conf not restored; later: bash $REPO/pc/rclone-conf.sh decrypt"

# Joplin notes (Flatpak). The notes live on Proton Drive (proton:backup/joplin), not in Joplin Cloud:
# the profile is restored before Joplin's first start and a daily backup timer is enabled.
print_info "Installing Joplin (Flatpak), restoring notes from Proton Drive..."
sudo flatpak install -y --noninteractive flathub net.cozic.joplin_desktop
if [ ! -f "$HOME/.config/joplin-desktop/database.sqlite" ]; then
    bash "$REPO/pc/joplin-proton.sh" restore || print_error "Joplin not restored; later: bash $REPO/pc/joplin-proton.sh restore"
fi
bash "$REPO/pc/joplin-proton.sh" enable
print_status "Joplin installed, backup timer enabled"

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
print_info "Log out and back in (docker + libvirt groups), then:"
echo "  gcloud init      # Google Cloud login"
echo "  gh auth login    # GitHub login"
echo "  claude           # Claude Code login"
echo "  jetbrains-toolbox  # install IntelliJ IDEA / GoLand"
