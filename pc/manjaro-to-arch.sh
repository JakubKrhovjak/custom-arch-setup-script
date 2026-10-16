#!/usr/bin/env bash
# Převede Manjaro na čistý Arch na místě: repozitáře Archu, pryč systémové balíčky Manjara
# (pamac, mhwd, settings manager, jádra linuxNN), jádro linux + linux-lts z Archu, GRUB, initramfs.
# Zůstává: /home, /etc (síť br-plc, libvirt, VM), Plasma, Konsole, Bluetooth.
# Balíčky vzhledu Manjara (zsh prompt, Breath Dark, SDDM, GRUB a Plymouth téma) zůstanou
# nainstalované jako cizí — fungují dál, jen se přestanou aktualizovat.
#
# Spuštění:   sudo bash pc/manjaro-to-arch.sh        (od fáze 1)
# Pokračování: sudo bash pc/manjaro-to-arch.sh 5     (od fáze 5, když se něco zastavilo)
# Jen jedna fáze: sudo bash pc/manjaro-to-arch.sh 3 3
set -euo pipefail
export LANG=C

START=${1:-1}
END=${2:-9}
BACKUP=/mnt/data/backup/manjaro-to-arch
LUKS_UUID=55b62d42-4184-41bc-9f97-7765ed5e7619

# Systémové balíčky Manjara k odebrání (z nich se odeberou jen nainstalované)
REMOVE=(
  pamac-cli pamac-gtk pamac-gtk3 pamac-tray-icon-plasma libpamac libpamac-flatpak-plugin libpamac-snap-plugin libpamac-aur-plugin
  manjaro-application-utility manjaro-settings-manager manjaro-settings-manager-knotifier
  mhwd mhwd-db mhwd-amdgpu mhwd-ati mhwd-nvidia mhwd-nvidia-390xx mhwd-nvidia-470xx mhwd-nvidia-580xx
  manjaro-alsa manjaro-gstreamer manjaro-modem manjaro-pipewire manjaro-printer
  manjaro-browser-settings timeshift-autosnap-manjaro
)
# Metabalíčky, jejichž závislosti (zvuk, multimédia, tisk, modem, ovladače AMD) mají zůstat
KEEP_DEPS_OF=(manjaro-alsa manjaro-gstreamer manjaro-modem manjaro-pipewire manjaro-printer mhwd-amdgpu mhwd-ati)
# Nahradí je balíčky Archu při synchronizaci, proto se odebírají bez kontroly závislostí
REMOVE_REPLACED=(manjaro-system manjaro-release pacman-mirrors manjaro-keyring)
OLD_KERNELS=(linux-meta linux-headers-meta linux612 linux612-headers linux71 linux71-headers)
NEW_KERNELS=(linux linux-headers linux-lts linux-lts-headers linux-firmware)

phase() { # číslo, název
  [[ $1 -ge $START && $1 -le $END ]] || return 1
  echo
  echo "================ Fáze $1: $2 ================"
}

confirm() {
  read -rp "Pokračovat? [a/N] " answer
  [[ $answer =~ ^([aAyY]|ano)$ ]] || { echo "Zastaveno. Pokračovat: sudo bash $0 ${CURRENT:-$START}"; exit 1; }
}

installed() { # vypíše z argumentů jen nainstalované balíčky
  printf '%s\n' "$@" | grep -Fxf <(pacman -Qq) || true
}

deps_of() { # přímé závislosti balíčků (bez verzí); bez argumentů nic (pacman -Qi by vypsal vše)
  [[ $# -gt 0 ]] || return 0
  pacman -Qi "$@" | sed -n 's/^Depends On *: //p' | tr -s ' ' '\n' | sed 's/[<>=].*//' | grep -vx -e None -e '' | sort -u
}

[[ $EUID -eq 0 ]] || { echo "Spusť přes sudo."; exit 1; }

CURRENT=1
if phase 1 "Kontroly"; then
  running=$(virsh -c qemu:///system list --state-running --name | grep -v '^$' || true)
  [[ -z $running ]] || { echo "Běží VM: $running — nejdřív ji vypni (virsh shutdown win11-tia --mode agent)."; exit 1; }
  echo "VM: žádná neběží"
  df -h / | tail -1
  echo "-- LUKS (GRUB musí umět odemknout) --"
  cryptsetup luksDump "/dev/disk/by-uuid/$LUKS_UUID" | grep -E '^Version|PBKDF|Hash spec' | sort -u
  pacman -Q grub
  echo "Když je PBKDF argon2id/argon2i, fáze 3 nechá GRUB z Manjara (IgnorePkg = grub)."
  echo "Doporučení: mít po ruce USB s ISO Archu (záchrana přes arch-chroot)."
  confirm
fi

CURRENT=2
if phase 2 "Snapshot Timeshift a záloha"; then
  timeshift --create --comments "pred-arch" --tags O
  timeshift --list | tail -5
  # /home Timeshift nezálohuje → vlastní snapshot @home jen pro čtení (okamžitý, místo nezabírá)
  mkdir -p /mnt/btrfs-root
  mount -o subvolid=5 "/dev/mapper/luks-$LUKS_UUID" /mnt/btrfs-root
  [[ -e /mnt/btrfs-root/@home-pred-arch ]] || btrfs subvolume snapshot -r /mnt/btrfs-root/@home /mnt/btrfs-root/@home-pred-arch
  ls /mnt/btrfs-root
  umount /mnt/btrfs-root
  mkdir -p "$BACKUP"
  tar -C / -czf "$BACKUP/etc.tar.gz" etc
  pacman -Qqe >"$BACKUP/pkg-explicit.txt"
  pacman -Qqm >"$BACKUP/pkg-foreign.txt"
  pacman -Q >"$BACKUP/pkg-all.txt"
  ls -lh "$BACKUP"
  confirm
fi

CURRENT=3
if phase 3 "Repozitáře Archu"; then
  cp -n /etc/pacman.conf "$BACKUP/pacman.conf.manjaro"
  cp -n /etc/pacman.d/mirrorlist "$BACKUP/mirrorlist.manjaro"
  # GRUB volitelně: výchozí = ponechat GRUB z Manjara beze změny (IgnorePkg, žádný zápis do EFI)
  ignore="IgnorePkg = grub"
  if cryptsetup luksDump "/dev/disk/by-uuid/$LUKS_UUID" | grep -q 'PBKDF:.*argon2'; then
    echo "LUKS používá Argon2 → GRUB z Manjara zůstává."
  else
    read -rp "Vyměnit GRUB za verzi z Archu (grub-install do EFI)? [a/N] " answer
    [[ $answer != a ]] || ignore=""
  fi
  cat >/etc/pacman.conf <<EOF
[options]
HoldPkg = pacman glibc
Architecture = auto
Color
CheckSpace
ParallelDownloads = 5
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
$ignore

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
  cat >/etc/pacman.d/mirrorlist <<'EOF'
## Arch Linux — později lze vygenerovat rychlejší: reflector --country CZ,DE --protocol https --sort rate
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
EOF
  grep -vE '^\s*(#|$)' /etc/pacman.conf
  pacman -Syy
  pacman -S --needed --noconfirm archlinux-keyring
  pacman-key --populate archlinux
  confirm
fi

CURRENT=4
if phase 4 "Odebrání systémových balíčků Manjara"; then
  mapfile -t targets < <(installed "${REMOVE[@]}")
  mapfile -t replaced < <(installed "${REMOVE_REPLACED[@]}")
  # Závislosti metabalíčků (pipewire, cups, ovladače z mhwd…) označit jako explicitní, ať nezůstanou sirotci;
  # závislosti pamacu a settings manageru zůstanou jako sirotci (pacman -Qdt) k pozdějšímu úklidu
  mapfile -t keep < <(deps_of $(installed "${KEEP_DEPS_OF[@]}") | grep -Fxvf <(printf '%s\n' "${targets[@]}" "${replaced[@]}") | grep -Fxf <(pacman -Qq) || true)
  echo "Odeberu: ${targets[*]} ${replaced[*]}"
  echo "Ponechám jako explicitní: ${keep[*]}"
  confirm
  [[ ${#keep[@]} -eq 0 ]] || pacman -D --asexplicit "${keep[@]}"
  [[ ${#targets[@]} -eq 0 ]] || pacman -R "${targets[@]}"
  [[ ${#replaced[@]} -eq 0 ]] || pacman -Rdd --noconfirm "${replaced[@]}"
fi

CURRENT=5
if phase 5 "Synchronizace na Arch (pacman -Syyuu) a jádra z Archu"; then
  echo "Potrvá to (stáhne se většina systému). Dotazy pacmanu na náhradu balíčků potvrzuj Y."
  confirm
  pacman -Syyuu --needed "${NEW_KERNELS[@]}" lsb-release filesystem
  mapfile -t meta < <(installed linux-firmware-meta)
  [[ ${#meta[@]} -eq 0 ]] || pacman -R --noconfirm "${meta[@]}"
  # Balíčky se stejnou verzí jako v Archu -Syyuu nevymění (filesystem, pacman, plymouth…) → přeinstalovat;
  # v cache leží stejně pojmenované buildy Manjara, pacman je při chybném podpisu smaže → druhý pokus
  mapfile -t same < <(pacman -Qi | awk '/^Name/{n=$3} /^Packager.*manjaro/{print n}' | grep -vx grub | grep -vxFf <(pacman -Qqm) || true)
  if [[ ${#same[@]} -gt 0 ]]; then
    pacman -S --noconfirm "${same[@]}" || pacman -S --noconfirm "${same[@]}"
  fi
  chmod 700 /etc/ssl/private
  cat /etc/os-release | head -3
fi

CURRENT=6
if phase 6 "Odebrání jader Manjara"; then
  ls /boot/vmlinuz-linux /boot/vmlinuz-linux-lts
  mapfile -t old < <(installed "${OLD_KERNELS[@]}")
  echo "Odeberu: ${old[*]}"
  confirm
  [[ ${#old[@]} -eq 0 ]] || pacman -R "${old[@]}"
fi

CURRENT=7
if phase 7 "Initramfs"; then
  [[ ! -e /etc/mkinitcpio.conf.pacnew ]] || echo "Pozor: /etc/mkinitcpio.conf.pacnew existuje — platí původní mkinitcpio.conf (HOOKS s encrypt)."
  mkinitcpio -P
  for img in /boot/initramfs-linux.img /boot/initramfs-linux-lts.img; do
    echo "-- $img --"
    lsinitcpio "$img" | grep -E '^crypto_keyfile.bin$|hooks/encrypt$|hooks/plymouth$'
  done
  echo "Musí být vidět crypto_keyfile.bin a hooks/encrypt u obou obrazů."
  confirm
fi

CURRENT=8
if phase 8 "GRUB"; then
  cp -n /etc/default/grub "$BACKUP/grub.manjaro"
  sed -i "s/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR='Arch'/" /etc/default/grub
  # grub-mkconfig řadí podle názvu → výchozí by bylo linux-lts; hlavní jádro nahoru
  grep -q '^GRUB_TOP_LEVEL=' /etc/default/grub || echo 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux"' >>/etc/default/grub
  # Zavaděč v EFI musí odpovídat modulům v /boot/grub; ID 'manjaro' = stávající položka Boot0000
  grep -q '^IgnorePkg = grub' /etc/pacman.conf \
    && echo "GRUB z Manjara ponechán, grub-install přeskočen." \
    || grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=manjaro --recheck
  grub-mkconfig -o /boot/grub/grub.cfg
  grep -E "^menuentry|^submenu" /boot/grub/grub.cfg
  efibootmgr | head -4
  confirm
fi

CURRENT=9
if phase 9 "Kontrola"; then
  echo "-- Cizí balíčky (AUR + ponechané vzhledové Manjara) --"
  pacman -Qqm
  echo "-- Soubory .pacnew (projdeme spolu, nic se nepřepisuje samo) --"
  find /etc -name '*.pacnew' 2>/dev/null
  ls /boot
  echo
  echo "Hotovo. Restartuj. V GRUBu je i položka se snapshoty (grub-btrfs) — návrat: snapshot pred-arch."
  echo "Po startu zkontrolovat: Plasma, Konsole, myš, br-plc (ping 192.168.10.1), virsh start win11-tia."
fi
