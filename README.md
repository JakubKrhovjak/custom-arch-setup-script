# Minimal Arch Linux setup

Scripts that build a minimal, encrypted Arch Linux desktop with [Desk](https://github.com/JakubKrhovjak/desk)
(Hyprland with a custom shell), Ghostty + zsh + Starship, and a backend dev toolchain.
The earlier version with a choice of KDE Plasma in the Simpleton look is kept in the `plasma` branch.

| Script | Run | What it does |
|---|---|---|
| `arch-install.sh` | Arch ISO, as root | LUKS2 (Argon2id) + btrfs (`@ @home @cache @log`), systemd-boot + UKI (`linux-zen` default, `linux-lts` fallback), greetd, zram + earlyoom, Timeshift, yay; Secure Boot + TPM2 when the firmware is in setup mode |
| `first-login.sh` | automatically at first login | runs the scripts below on the console with progress on screen (log `~/arch-setup/first-login.log`); on failure runs again at next login |
| `desk-install.sh` | (first login) | dotfiles (`dotfiles-install.sh`), the desk repository in `~/.config` and its `install.sh`: Hyprland, shell, keyd, graphical login screen |
| `setup-script.sh` | (first login) | dev tools (below) |
| `secureboot-tpm2.sh` | `sudo`, 3 phases | Secure Boot + TPM2 later (installed without setup mode) or again after a BIOS update |
| `tmobile/setup.sh` | optional, by hand | T-Mobile CZ work: FortiClient VPN VM, SSH tunnel, Firefox PAC + Windows UA, app environment; secrets from Proton Pass — see [`tmobile/README.md`](tmobile/README.md) |

## Installation

1. BIOS: Secure Boot **disabled** (the Arch ISO does not boot with it) and, for Secure Boot + TPM2,
   keys deleted (**setup mode**). Boot the Arch ISO (UEFI), connect to the internet (`iwctl` for Wi-Fi).
2. Get the scripts and install:
   ```bash
   pacman -Sy git && git clone https://github.com/JakubKrhovjak/custom-arch-setup-script && cd custom-arch-setup-script && bash arch-install.sh
   ```
   Asks for the disk, hostname, user, password and disk passphrase. Root stays locked (use `sudo`).
3. `umount -R /mnt && cryptsetup close root && reboot`. With Secure Boot: BIOS → Secure Boot → **Enabled**
   (mode Custom, do not restore default keys). The first boot asks for the disk passphrase once and
   enrolls TPM2 (`tpm2-enroll.service`); from then on the disk unlocks without it.
4. Log in on the text login screen: the setup runs on the console (asks for the sudo password once), then Enter starts the desktop.
   The graphical login screen appears after the next reboot.

Keep a wired keyboard: Bluetooth does not work at the passphrase prompt (first boot, BIOS updates).

### After the setup (needs your logins, so not automated)

1. Proton Pass CLI: `pass-cli login` (opens nothing, copy the printed URL to a browser). Shell secrets arrive
   within a minute via `secrets-sync.timer`; open a new terminal.
2. Notesnook: sign in (login in Proton Pass), the notes come down with the sync.
3. GitHub: `gh auth login` (SSH key), needed for the private repos below.
4. Mindmap (private repo): `git clone git@github.com:JakubKrhovjak/mindmap.git ~/projects/mindmap && ~/projects/mindmap/mindmap install`
   (links `~/.local/bin/mindmap`, adds the app to the menu; Node + pnpm come from `setup-script.sh`).

## What gets installed

**Desktop (minimal):** Desk with greetd and gnome-keyring, Ghostty, Firefox, VLC, Flatpak (Flathub), printing (CUPS),
Thunderbolt/USB4 dock authorization (`bolt`, `boltctl`),
KDE Connect (iPhone/Android; ufw opens 1714–1764).

**Firefox (default browser):** hardened by `/etc/firefox/policies/policies.json` (from `dotfiles/firefox/`):
uBlock Origin + Proton Pass installed, no saving of logins (Proton Pass), no telemetry/studies/Pocket/sponsored content,
strict tracking protection, HTTPS-Only, DNS over HTTPS (Cloudflare, with fallback), new notification/location
requests blocked. Nothing is locked except telemetry; check with `about:policies`. Chromium (Arch repo) is the second browser
(Chrome DevTools incl. Lighthouse).
Fonts: Noto (+ emoji), DejaVu, Liberation, Hack Nerd Font, Terminus (TTY). AMD GPU (Mesa, Vulkan).

**Dev tools (`setup-script.sh`):** git, GitHub CLI, jq, Podman (rootless) + Compose, Go, Terraform,
kubectl, Helm, k9s, kind, trivy, k3s, SDKMAN (Java 21 + 25 Temurin, Maven, Gradle), NVM (Node.js LTS),
Python, static analysis for the Claude `/cr` skill (semgrep, lizard, PMD), Google Cloud CLI + GKE auth plugin, QEMU/KVM + virt-manager (UEFI + TPM guests),
JetBrains Toolbox, VS Code, Claude Code, Chromium, Postman (Flatpak), Notesnook (Flatpak), Proton VPN, Proton Pass + rclone.

**System health (`setup-script.sh`):** ufw, monthly `btrfs scrub` on every btrfs filesystem, `smartd` (SSD self-tests,
warnings as desktop notifications via `/usr/local/bin/smartd-notify`), `informant` (unread Arch news blocks `pacman -Syu`;
read it with `informant read`), `arch-audit` (installed packages with known CVEs).

**CPU scheduler (`setup-script.sh`):** `scx_bpfland` loaded through sched_ext by the `scx_loader` service
(`/etc/scx_loader.toml`) — interactive apps stay smooth while all cores are busy. Check with `scxctl get`;
back to the kernel's EEVDF with `scxctl stop` (until reboot) or `sudo systemctl disable --now scx_loader`.

**rclone config in the repo, encrypted:** `secrets/rclone.conf.age` is `~/.config/rclone/rclone.conf` (Proton Drive,
Google Drive remotes with their tokens) encrypted with [age](https://age-encryption.org) and a passphrase.
`setup-script.sh` asks for the passphrase once and restores the file; after a token refresh or a new remote run
`pc/rclone-conf.sh encrypt` and commit. The plain file is never committed.

**Notes:** Notesnook (end-to-end encrypted notes) syncs across all devices by itself; sign in after the setup. Joplin and its Proton Drive backup were dropped (the old backup stays in `proton:backup/joplin`,
the restore script `pc/joplin-proton.sh` is in the git history).

## Layout

```
dotfiles/   zshrc, zsh/base.zsh, zsh/secrets.zsh, zsh/tab-colors.zsh + tab-colors, bin/secrets-sync,
            systemd/secrets-sync.{service,timer},
            starship.toml, ghostty/config
vm-test/    clean install and login screen test in a QEMU VM
```

**Shell env (API tokens, DB passwords, private hosts and project IDs):** the source of truth is the Proton Pass vault `env-secrets`
(one login item per variable: title = variable name, password = value). `secrets-sync` copies the vault into
the Secret Service (gnome-keyring); `~/.config/zsh/secrets.zsh` (from this repo, holds no values) exports them at shell start (~10 ms,
works offline). The user timer `secrets-sync.timer` syncs 1 min after login and every 15 min, so a secret added
to the vault reaches new terminals by itself; run `secrets-sync` for an immediate sync.
New machine: `pass-cli login` once (the timer does the rest). Log: `journalctl --user -u secrets-sync`.
Optional per-machine overrides go to `~/.config/zsh/local.zsh` (sourced if present), never to this repo.

## Notes

- AUR builds use all cores via `~/.makepkg.conf` (`MAKEFLAGS="-j$(nproc)"`, written by `desk-install.sh`).
- Timeshift snapshots only `@`; UKIs live on the ESP. After restoring a snapshot with another kernel,
  rebuild them: `sudo mkinitcpio -P`.
