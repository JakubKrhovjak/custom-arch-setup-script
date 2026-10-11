# Minimal Arch Linux setup

Scripts that build a minimal, encrypted Arch Linux desktop with KDE Plasma in the **Simpleton** look
(monochrome icons, dark BreathSlate colors, rounded Klassy widgets), Ghostty + zsh + Starship, and a backend dev toolchain.

| Script | Run | What it does |
|---|---|---|
| `arch-install.sh` | Arch ISO, as root | LUKS2 (Argon2id) + btrfs (`@ @home @cache @log`), systemd-boot + UKI (`linux`, `linux-lts`), minimal Plasma, zram + earlyoom, Timeshift, yay; Secure Boot + TPM2 when the firmware is in setup mode |
| `first-login.sh` | automatically at first login | opens Ghostty and runs the two scripts below with progress on screen (log `~/arch-setup/first-login.log`); on failure runs again at next login |
| `post-install.sh` | (first login) | Simpleton theme (desktop + login screen), Ghostty as default terminal, dotfiles, `us,cz` keyboard |
| `setup-script.sh` | (first login) | dev tools (below) |
| `secureboot-tpm2.sh` | `sudo`, 3 phases | Secure Boot + TPM2 later (installed without setup mode) or again after a BIOS update |

## Installation

1. BIOS: Secure Boot **disabled** (the Arch ISO does not boot with it) and, for Secure Boot + TPM2,
   keys deleted (**setup mode**). Boot the Arch ISO (UEFI), connect to the internet (`iwctl` for Wi-Fi).
2. Get the scripts and install:
   ```bash
   pacman -Sy git && git clone https://github.com/JakubKrhovjak/manjaro-setup-script && cd manjaro-setup-script && bash arch-install.sh
   ```
   Asks for the disk, hostname, user, password and disk passphrase. Root stays locked (use `sudo`).
3. `umount -R /mnt && cryptsetup close root && reboot`. With Secure Boot: BIOS → Secure Boot → **Enabled**
   (mode Custom, do not restore default keys). The first boot asks for the disk passphrase once and
   enrolls TPM2 (`tpm2-enroll.service`); from then on the disk unlocks without it.
4. Log in to Plasma: Ghostty opens and runs the setup (asks for the sudo password once). Then log out and in.

Keep a wired keyboard: Bluetooth does not work at the passphrase prompt (first boot, BIOS updates).

## What gets installed

**Desktop (minimal):** Plasma without `kde-applications-meta` — Dolphin, Kate, Okular, Gwenview, Spectacle,
Ark, Filelight, KCalc, Ghostty (no Konsole), Firefox, VLC, Flatpak (Flathub), printing (CUPS).
Fonts: Noto (+ emoji), DejaVu, Liberation, Hack Nerd Font, Terminus (TTY). AMD GPU (Mesa, Vulkan).

**Dev tools (`setup-script.sh`):** git, GitHub CLI, jq, Docker + Compose + Buildx, Go, Terraform,
kubectl, Helm, k9s, kind, trivy, k3s, SDKMAN (Java 21 + 25 Temurin, Maven, Gradle), NVM (Node.js LTS),
Python, Google Cloud CLI + GKE auth plugin, QEMU/KVM + virt-manager (UEFI + TPM guests),
JetBrains Toolbox, VS Code, Claude Code.

## Layout

```
dotfiles/   zshrc, zsh/base.zsh, starship.toml, ghostty/config, klassy/klassyrc (14 px corners)
theme/      icons/Simpleton, plasma/desktoptheme/simpleton, plasma/look-and-feel/org.simpleton.dark.desktop,
            wallpapers/Simpleton, color-schemes/BreathSlate.colors
```

Secrets (API tokens) go to `~/.config/zsh/secrets.zsh` (`chmod 600`), never to this repo.

## Notes

- The theme is installed to `/usr/share` so the SDDM login screen (user `sddm`) can read it.
  After changing the theme, run `post-install.sh` again.
- Timeshift snapshots only `@`; UKIs live on the ESP. After restoring a snapshot with another kernel,
  rebuild them: `sudo mkinitcpio -P`.
- `theme/plasma/desktoptheme/simpleton` contains unmodified SVGs from Manjaro's Breath theme (CC BY-ND);
  the wallpaper is Ant-Dark by EliverLara (GPL-3.0).
