#!/bin/bash

# Minimal Arch Linux installer: LUKS2 + btrfs + systemd-boot with UKI, minimal KDE Plasma.
# Run from the Arch ISO live environment: bash arch-install.sh
# After first login: bash ~/arch-setup/post-install.sh (look & feel), then setup-script.sh (dev tools),
# optionally secureboot-tpm2.sh (Secure Boot + unlocking the disk via TPM2).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[>]${NC} $1"; }
ok()      { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
die()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }

read_secret() { # prompt, variable name
    local first second
    while true; do
        read -rsp "$1: " first; echo
        read -rsp "$1 (again): " second; echo
        [ -n "$first" ] && [ "$first" = "$second" ] && break
        warn "Empty or not matching, try again"
    done
    printf -v "$2" '%s' "$first"
}

# ── Sanity checks ──────────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || die "Run as root (from Arch ISO)"
[ -d /sys/firmware/efi ] || die "UEFI boot required (systemd-boot + UKI)"
ping -c1 archlinux.org &>/dev/null || die "No internet connection"

# ── Config ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════${NC}"
echo -e "${CYAN}   Minimal Arch Linux Installer       ${NC}"
echo -e "${CYAN}══════════════════════════════════════${NC}"
echo ""

# Target disk: internal disks only (no USB stick with the installer, no zram / loop / CD); TRAN last, may be empty
mapfile -t DISKS < <(lsblk -dn -o NAME,TYPE,RO,TRAN | awk '$2 == "disk" && $3 == "0" && $4 != "usb" && $1 !~ /^zram/ {print $1}')
describe_disk() { lsblk -dn -o SIZE,MODEL "/dev/$1" | xargs; }
case ${#DISKS[@]} in
    0) die "No internal disk found" ;;
    1) DISK="${DISKS[0]}"
       info "Only one disk: $DISK ($(describe_disk "$DISK"))" ;;
    *) echo "Disks:"
       for i in "${!DISKS[@]}"; do
           echo "  $((i + 1))) ${DISKS[$i]}  $(describe_disk "${DISKS[$i]}")"
       done
       while true; do
           read -rp "Install to disk number [1-${#DISKS[@]}]: " CHOICE
           [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#DISKS[@]} )) && break
           warn "Enter a number from the list"
       done
       DISK="${DISKS[$((CHOICE - 1))]}" ;;
esac
DISK="/dev/${DISK}"
[ -b "$DISK" ] || die "Disk $DISK not found"

read -rp "Hostname [lucky]: " HOSTNAME
HOSTNAME="${HOSTNAME:-lucky}"
read -rp "Username [lucky]: " USERNAME
USERNAME="${USERNAME:-lucky}"
read_secret "User password" USER_PASS
read_secret "Disk encryption passphrase" LUKS_PASS

# Secure Boot: keys can be enrolled only when the firmware is in setup mode (BIOS → Secure Boot → delete keys)
SB_STATE=$(bootctl status 2>/dev/null | sed -n 's/^\s*Secure Boot:\s*//p')
if [[ "$SB_STATE" == *setup* ]]; then
    SECURE_BOOT=yes
    info "Firmware in setup mode → Secure Boot keys + TPM2 unlock will be set up"
else
    SECURE_BOOT=no
    warn "Firmware not in setup mode ($SB_STATE) → no Secure Boot (later: secureboot-tpm2.sh)"
fi

TIMEZONE="Europe/Prague"
KEYMAP="us"
ESP_SIZE="1GiB" # UKI ~75 MB each (linux + linux-lts)

warn "This will ERASE all data on $DISK. Type 'yes' to continue:"
read -r CONFIRM
[ "$CONFIRM" = "yes" ] || die "Aborted."

# ── Partitioning ───────────────────────────────────────────────────────────────
info "Partitioning $DISK..."
parted -s "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB "$ESP_SIZE" \
    set 1 esp on \
    mkpart root "$ESP_SIZE" 100%

# Partition naming: nvme uses p1/p2, sda uses 1/2
if [[ "$DISK" == *"nvme"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi
udevadm settle

info "Formatting EFI partition..."
mkfs.fat -F32 "$EFI_PART"

info "Encrypting root partition (LUKS2, Argon2id)..."
printf '%s' "$LUKS_PASS" | cryptsetup luksFormat --type luks2 --pbkdf argon2id --batch-mode "$ROOT_PART" -
printf '%s' "$LUKS_PASS" | cryptsetup open --key-file=- "$ROOT_PART" root
LUKS_UUID=$(blkid -s UUID -o value "$ROOT_PART")

# ── btrfs subvolumes (Timeshift layout: @ and @home) ──────────────────────────
info "Creating btrfs subvolumes..."
mkfs.btrfs -f /dev/mapper/root
mount /dev/mapper/root /mnt
for SUBVOL in @ @home @cache @log; do
    btrfs subvolume create "/mnt/$SUBVOL"
done
umount /mnt

BTRFS_OPTS="noatime,compress=zstd:1"
mount -o "subvol=@,$BTRFS_OPTS" /dev/mapper/root /mnt
mkdir -p /mnt/home /mnt/var/cache /mnt/var/log /mnt/boot/efi
mount -o "subvol=@home,$BTRFS_OPTS" /dev/mapper/root /mnt/home
mount -o "subvol=@cache,$BTRFS_OPTS" /dev/mapper/root /mnt/var/cache
mount -o "subvol=@log,$BTRFS_OPTS" /dev/mapper/root /mnt/var/log
mount -o umask=0077 "$EFI_PART" /mnt/boot/efi

# ── Base install ───────────────────────────────────────────────────────────────
info "Installing base system (this may take a while)..."
pacstrap -K /mnt \
    base \
    base-devel \
    linux \
    linux-lts \
    linux-firmware \
    amd-ucode \
    btrfs-progs \
    cryptsetup \
    dosfstools \
    systemd-ukify \
    sbctl \
    plymouth \
    \
    networkmanager \
    sudo \
    git \
    openssh \
    man-db \
    man-pages \
    micro \
    htop \
    wget \
    curl \
    zip \
    unzip \
    rsync \
    jq \
    tree \
    usbutils \
    ntfs-3g \
    exfatprogs \
    wl-clipboard \
    \
    zram-generator \
    earlyoom \
    timeshift \
    cronie \
    ufw \
    pacman-contrib \
    reflector \
    fwupd \
    fwupd-efi \
    \
    mesa \
    vulkan-radeon \
    \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    bluez \
    bluez-utils \
    \
    plasma-desktop \
    plasma-nm \
    plasma-pa \
    bluedevil \
    powerdevil \
    power-profiles-daemon \
    kscreen \
    kwallet-pam \
    ksshaskpass \
    kde-gtk-config \
    breeze-gtk \
    xdg-desktop-portal-kde \
    plasma-systemmonitor \
    kinfocenter \
    sddm \
    sddm-kcm \
    plymouth-kcm \
    xdg-user-dirs \
    \
    ghostty \
    dolphin \
    kio-extras \
    ffmpegthumbs \
    kdegraphics-thumbnailers \
    kate \
    okular \
    gwenview \
    spectacle \
    ark \
    7zip \
    filelight \
    kcalc \
    firefox \
    vlc \
    flatpak \
    \
    cups \
    print-manager \
    \
    zsh \
    zsh-completions \
    zsh-autosuggestions \
    zsh-syntax-highlighting \
    zsh-history-substring-search \
    starship \
    \
    terminus-font \
    noto-fonts \
    noto-fonts-emoji \
    ttf-dejavu \
    ttf-liberation \
    ttf-hack-nerd

# ── fstab ──────────────────────────────────────────────────────────────────────
info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
# no subvolid: after a Timeshift restore @ has another id and the system would not boot
sed -i -E 's/,?subvolid=[0-9]+//' /mnt/etc/fstab
echo "tmpfs /tmp tmpfs noatime,mode=1777 0 0" >> /mnt/etc/fstab

# ── Initramfs + UKI ────────────────────────────────────────────────────────────
info "Configuring initramfs and unified kernel images..."
# systemd-based initramfs: sd-encrypt reads /etc/crypttab.initramfs (TPM2 unlock is added by secureboot-tpm2.sh)
sed -i 's/^HOOKS=.*/HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems)/' /mnt/etc/mkinitcpio.conf
echo "root UUID=${LUKS_UUID} none luks" > /mnt/etc/crypttab.initramfs
mkdir -p /mnt/etc/kernel
echo "root=/dev/mapper/root rootflags=subvol=@ rw quiet splash udev.log_priority=3" > /mnt/etc/kernel/cmdline

for KERNEL in linux linux-lts; do
    cat > "/mnt/etc/mkinitcpio.d/${KERNEL}.preset" <<EOF
# mkinitcpio preset for '${KERNEL}': UKI for systemd-boot
ALL_kver="/boot/vmlinuz-${KERNEL}"
PRESETS=('default')
default_uki="/boot/efi/EFI/Linux/arch-${KERNEL}.efi"
EOF
done
mkdir -p /mnt/boot/efi/EFI/Linux

# ── Timeshift: btrfs snapshots of @ (only changed blocks take space) ─────────
# daily 3 + at boot 5 (+ before each upgrade 3, timeshift-autosnap in setup-script.sh); no weekly / monthly
BTRFS_UUID=$(blkid -s UUID -o value /dev/mapper/root)
mkdir -p /mnt/etc/timeshift
cat > /mnt/etc/timeshift/timeshift.json <<EOF
{
  "backup_device_uuid" : "${BTRFS_UUID}",
  "parent_device_uuid" : "${LUKS_UUID}",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "false",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "true",
  "count_monthly" : "0",
  "count_weekly" : "0",
  "count_daily" : "3",
  "count_hourly" : "0",
  "count_boot" : "5",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude" : [],
  "exclude-apps" : []
}
EOF

# ── After a snapshot restore: rebuild UKIs when the ESP kernel has no modules in the system ──
# Timeshift snapshots only @, the UKIs on the ESP stay newer → without this the restored system
# boots without modules (no graphics, no network).
cat > /mnt/usr/local/bin/uki-match-kernel <<'UKIMATCH'
#!/usr/bin/env bash
# Rebuilds the UKIs when the running kernel (from the ESP) has no modules in the system — typically after a snapshot restore.
set -euo pipefail
kver=$(uname -r)
marker=/var/lib/uki-match-kernel/$kver

[[ -d /usr/lib/modules/$kver ]] && { echo "Modules for $kver present, UKI matches."; exit 0; }
[[ -e $marker ]] && { echo "Rebuild for $kver already tried ($marker), not again."; exit 1; }

echo "Running kernel $kver has no modules → UKI on the ESP does not match the system (restored snapshot?)."
echo "Kernels in the system: $(ls /usr/lib/modules | tr '\n' ' ')"
mkdir -p "${marker%/*}"
touch "$marker"
mkinitcpio -P # sbctl post hook signs the new UKIs
echo "UKIs rebuilt, rebooting."
systemctl --no-block reboot
UKIMATCH
chmod 755 /mnt/usr/local/bin/uki-match-kernel

cat > /mnt/etc/systemd/system/uki-match-kernel.service <<'UNIT'
[Unit]
Description=Rebuild UKIs when the ESP kernel does not match the system (after a snapshot restore)
ConditionPathExists=!/usr/lib/modules/%v
RequiresMountsFor=/boot /boot/efi /var/lib
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/uki-match-kernel

[Install]
WantedBy=multi-user.target
UNIT

# ── Chroot configuration ───────────────────────────────────────────────────────
info "Configuring system inside chroot..."

arch-chroot /mnt /bin/bash <<CHROOT
set -euo pipefail

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Locale — English system, Czech formats are set per user in Plasma
sed -i -E 's/^#(en_US.UTF-8 UTF-8|cs_CZ.UTF-8 UTF-8)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Console keymap and font
printf 'KEYMAP=${KEYMAP}\nFONT=ter-132b\n' > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat >> /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# User with zsh; root stays locked (sudo via wheel)
useradd -m -G wheel -s /usr/bin/zsh "${USERNAME}"
passwd -l root
# emergency / rescue shell even with root locked (otherwise "root account is locked" → only a live USB helps)
for UNIT in emergency rescue; do
    mkdir -p /etc/systemd/system/\${UNIT}.service.d
    printf '[Service]\\nEnvironment=SYSTEMD_SULOGIN_FORCE=1\\n' > /etc/systemd/system/\${UNIT}.service.d/sulogin-force.conf
done
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Pacman maintenance
# fastest HTTPS mirrors, refreshed weekly by reflector.timer; old package versions cleaned by paccache.timer (keeps 3)
cat > /etc/xdg/reflector/reflector.conf <<'EOF'
--save /etc/pacman.d/mirrorlist
--protocol https
--country Czechia,Germany,Austria,Poland
--latest 10
--sort rate
EOF

mkdir -p /etc/systemd/system/paccache.service.d
printf '[Service]\\nExecStart=\\nExecStart=/usr/bin/paccache -rk3\\nExecStart=/usr/bin/paccache -ruk0\\n' > /etc/systemd/system/paccache.service.d/uninstalled.conf

# Firewall: incoming denied (except replies), outgoing allowed; rules for docker / k3s / libvirt in setup-script.sh
sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf

# fwupd with Secure Boot: boot the fwupd EFI binary signed by sbctl directly, without shim
mkdir -p /etc/fwupd
printf '[uefi_capsule]\nDisableShimForSecureBoot=true\n' >> /etc/fwupd/fwupd.conf

# Pacman tuning
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
# no -debug packages from makepkg (yay, AUR builds)
sed -i -E '/^OPTIONS=/s/([( ])debug/\\1!debug/' /etc/makepkg.conf

# zram swap (8 GB, zstd) — earlyoom kills the biggest process before the system freezes
printf '[zram0]\nzram-size = 8192\ncompression-algorithm = zstd\nswap-priority = 100\n' > /etc/systemd/zram-generator.conf

# Boot splash: firmware logo
plymouth-set-default-theme bgrt

# SDDM: Breeze greeter on KWin Wayland (no Xorg installed), no autologin;
# post-install.sh gives it the Simpleton look
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-wayland.conf <<'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
EOF
printf '[Theme]\nCurrent=breeze\nCursorTheme=breeze_cursors\n' > /etc/sddm.conf.d/kde_settings.conf

# UKIs + systemd-boot (finds UKIs in EFI/Linux on its own)
mkinitcpio -P
bootctl install --esp-path=/boot/efi
printf 'default arch-linux.efi\ntimeout 3\nconsole-mode max\neditor no\n' > /boot/efi/loader/loader.conf
# initramfs images from the default presets (pacstrap) — not used with UKIs
rm -f /boot/initramfs-*.img

# Flatpak — enable Flathub
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Services
systemctl enable NetworkManager bluetooth sddm cups earlyoom fstrim.timer systemd-boot-update systemd-timesyncd power-profiles-daemon cronie ufw paccache.timer reflector.timer uki-match-kernel
CHROOT

printf '%s:%s\n' "$USERNAME" "$USER_PASS" | arch-chroot /mnt chpasswd

# ── Secure Boot (own keys + Microsoft) and TPM2 unlock on first boot ──────────
if [ "$SECURE_BOOT" = yes ]; then
    info "Secure Boot: creating keys, signing, enrolling to firmware..."
    arch-chroot /mnt /bin/bash <<'SECUREBOOT'
set -euo pipefail
sbctl create-keys
# -s = save to the sbctl database → pacman / mkinitcpio hooks sign new versions too
for f in /boot/efi/EFI/Linux/*.efi /boot/efi/EFI/systemd/systemd-bootx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI; do
    sbctl sign -s "$f"
done
# signed source → systemd-boot-update copies an already signed loader to the ESP
sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi
sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi # BIOS updates via fwupd
sbctl verify
# Microsoft keys: GPU option ROMs are signed by Microsoft (without them the screen may stay black)
sbctl enroll-keys --microsoft
SECUREBOOT

    # TPM2 can be enrolled only in the booted system with Secure Boot on (PCR 7 = Secure Boot state).
    # Temporary key on the encrypted root → first boot with Secure Boot enrolls TPM2 without asking
    # for the passphrase, then removes this key from the LUKS header and the disk.
    info "Preparing TPM2 enrollment for the first boot with Secure Boot..."
    ENROLL_KEY=/mnt/etc/tpm2-enroll.key
    (umask 077 && head -c 64 /dev/urandom > "$ENROLL_KEY")
    printf '%s' "$LUKS_PASS" | cryptsetup luksAddKey --key-file=- "$ROOT_PART" "$ENROLL_KEY"

    cat > /mnt/usr/local/bin/tpm2-enroll <<'ENROLL'
#!/bin/bash
# One-shot: enroll TPM2 (PCR 7) to LUKS once Secure Boot is on, then remove the temporary key.
set -euo pipefail
KEY=/etc/tpm2-enroll.key
CRYPTTAB=/etc/crypttab.initramfs
UUID=$(sed -nE 's/^\S+\s+UUID=(\S+).*/\1/p' "$CRYPTTAB" | head -n1)
DEV=/dev/disk/by-uuid/$UUID

if ! bootctl status 2>/dev/null | grep -qE 'Secure Boot:\s*enabled'; then
    echo "Secure Boot not enabled yet → enable it in BIOS; trying again at next boot"
    exit 0
fi
systemd-cryptenroll --unlock-key-file="$KEY" --tpm2-device=auto --tpm2-pcrs=7 "$DEV"
grep -q 'tpm2-device=' "$CRYPTTAB" || sed -i -E "/UUID=$UUID/s/\s*$/,tpm2-device=auto/" "$CRYPTTAB"
mkinitcpio -P # sbctl post hook signs the new UKIs
sbctl verify
cryptsetup luksRemoveKey "$DEV" "$KEY"
shred -u "$KEY"
systemctl disable tpm2-enroll.service
echo "TPM2 enrolled — next boot unlocks the disk without a passphrase"
ENROLL
    chmod 755 /mnt/usr/local/bin/tpm2-enroll

    cat > /mnt/etc/systemd/system/tpm2-enroll.service <<'UNIT'
[Unit]
Description=Enroll TPM2 for LUKS unlock (once, after Secure Boot is enabled)
ConditionPathExists=/etc/tpm2-enroll.key
After=local-fs.target tpm2.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tpm2-enroll

[Install]
WantedBy=multi-user.target
UNIT
    arch-chroot /mnt systemctl enable tpm2-enroll.service
    ok "Secure Boot keys enrolled, TPM2 enrollment waits for the first boot with Secure Boot on"
fi

# ── yay (AUR helper) — built as the user, installed as root (no sudo prompt in chroot) ──
info "Building yay..."
arch-chroot /mnt sudo -u "$USERNAME" bash -c 'cd ~ && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg --noconfirm'
arch-chroot /mnt bash -c "pacman -U --noconfirm /home/${USERNAME}/yay-bin/yay-bin-[0-9]*.pkg.tar.zst"

# ── Copy this repo to the new system ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
info "Copying setup scripts to /home/${USERNAME}/arch-setup..."
cp -r "$SCRIPT_DIR" "/mnt/home/${USERNAME}/arch-setup"

# First login: Ghostty opens and runs post-install.sh + setup-script.sh (first-login.sh removes this when done)
mkdir -p "/mnt/home/${USERNAME}/.config/autostart"
cat > "/mnt/home/${USERNAME}/.config/autostart/arch-setup.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Arch setup (first login)
Exec=ghostty --title="Arch setup" -e bash /home/${USERNAME}/arch-setup/first-login.sh
Terminal=false
EOF
arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/arch-setup" "/home/${USERNAME}/.config"

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════${NC}"
ok "Installation complete!"
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo ""
echo "  Disk:     $DISK (ESP $EFI_PART, LUKS2 $ROOT_PART → btrfs @ @home @cache @log)"
echo "  Boot:     systemd-boot + UKI (linux, linux-lts)"
echo "  Hostname: $HOSTNAME"
echo "  User:     $USERNAME (root locked, use sudo)"
echo ""
warn "Unmount and reboot:"
echo "  umount -R /mnt && cryptsetup close root && reboot"
echo ""
if [ "$SECURE_BOOT" = yes ]; then
    warn "On reboot: BIOS → Secure Boot → Enabled (mode Custom, do NOT restore default keys)."
    echo "  First boot asks for the disk passphrase once, then TPM2 unlocks it."
    echo "  No boot with Secure Boot → disable it in BIOS (keys stay), boots as before."
fi
warn "After first login Ghostty opens and runs the setup (look & feel + dev tools)."
echo "  Log: ~/arch-setup/first-login.log"
