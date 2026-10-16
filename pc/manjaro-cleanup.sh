#!/usr/bin/env bash
# Úklid zbytků Manjara po převodu na Arch + systemd-boot / UKI.
#
# Vzhled zůstává z vlastních souborů (připravené předem, bez sudo):
#   ~/.zshrc → ~/.config/zsh/base.zsh (dřív manjaro-zsh-config) + Starship (~/.config/starship.toml)
#   Konsole: ~/.local/share/konsole/redo.profile + Silverfox.colorscheme (dřív Breath.profile / BreathSilverfox)
#   Ghostty: ~/.config/ghostty/config (stejné barvy a font)
#   KWin: [Plugins] v ~/.config/kwinrc (dřív výchozí hodnoty z manjaro-kde-settings)
#   zálohy: ~/.zshrc.pred-cleanup, redo.profile.pred-cleanup, kwinrc.pred-cleanup
#
# Fáze 4–5 (GRUB, keyslot s keyfile) spouštět až po vyzkoušení záchrany z live USB.
#
# Spuštění:    sudo bash pc/manjaro-cleanup.sh        (fáze 1–3)
# Pokračování: sudo bash pc/manjaro-cleanup.sh 2      (od fáze 2 do 3)
# GRUB a LUKS: sudo bash pc/manjaro-cleanup.sh 4 5
set -euo pipefail
export LANG=C

START=${1:-1}
END=${2:-3}
BACKUP=/mnt/data/backup/manjaro-cleanup
LUKS_UUID=55b62d42-4184-41bc-9f97-7765ed5e7619
ESP=/boot/efi
USER_NAME=${SUDO_USER:-redo}
ZSH_PLUGINS="zsh-autosuggestions zsh-syntax-highlighting zsh-completions zsh-history-substring-search"
MANJARO_PKGS="manjaro-zsh-config zsh-theme-powerlevel10k ttf-meslo-nerd-font-powerlevel10k manjaro-kde-settings manjaro-base-skel manjaro-icons plasma6-themes-breath plasma6-themes-breath-migration sddm-breath-theme plymouth-theme-manjaro"
GRUB_PKGS="grub grub-btrfs os-prober grub-theme-manjaro"

phase() { # číslo, název
  [[ $1 -ge $START && $1 -le $END ]] || return 1
  echo
  echo "================ Fáze $1: $2 ================"
}

confirm() {
  read -rp "Pokračovat? [a/N] " answer
  [[ $answer =~ ^([aAyY]|ano)$ ]] || { echo "Zastaveno. Pokračovat: sudo bash $0 ${CURRENT:-$START}"; exit 1; }
}

installed() { # vypíše jen nainstalované balíčky ze seznamu
  for p in "$@"; do pacman -Q "$p" &>/dev/null && echo "$p"; done
}

[[ $EUID -eq 0 ]] || { echo "Spusť přes sudo."; exit 1; }

CURRENT=1
if phase 1 "Snapshot, zálohy, Starship + Ghostty"; then
  timeshift --create --comments "pred-cleanup" --tags O
  mkdir -p "$BACKUP"
  cp --update=none /etc/pacman.conf /etc/mkinitcpio.d/linux.preset /etc/mkinitcpio.d/linux-lts.preset "$BACKUP/"
  [[ -f /etc/default/grub ]] && cp --update=none /etc/default/grub "$BACKUP/"
  cp -r --update=none /etc/sddm.conf.d "$BACKUP/"
  efibootmgr >"$BACKUP/efibootmgr.txt"
  pacman -Qqe >"$BACKUP/pkglist-explicit.txt"
  pacman -S --needed --noconfirm starship ghostty $ZSH_PLUGINS ttf-hack-nerd
  # pluginy a font byly závislosti manjaro-zsh-config / Breath.profile → jako explicitní, ať je -Rns nesmaže
  pacman -D --asexplicit $ZSH_PLUGINS ttf-hack-nerd
  echo "-- test nové konfigurace zsh ($USER_NAME):"
  sudo -iu "$USER_NAME" zsh -i -c 'echo "zsh OK"; starship --version | head -1; echo "prompt: ${PROMPT:0:40}"' 2>&1
  ls -la "$BACKUP"
  confirm
fi

CURRENT=2
if phase 2 "Kontrola, že vzhled nic z Manjara nepoužívá"; then
  echo "-- soubory uživatele, které odkazují na balíky Manjara (mělo by být prázdné):"
  home=$(getent passwd "$USER_NAME" | cut -d: -f6)
  grep -l -E "manjaro-zsh|p10k|powerlevel10k|Breath\.profile|BreathSilverfox" \
    "$home/.zshrc" "$home/.config/zsh/"*.zsh "$home/.local/share/konsole/"*.profile "$home/.config/konsolerc" 2>/dev/null || echo "   nic"
  echo "-- SDDM (vyhrává poslední soubor):"; grep -H '^Current' /etc/sddm.conf.d/*.conf
  echo "-- Plymouth:"; plymouth-set-default-theme
  confirm
fi

CURRENT=3
if phase 3 "Odebrání vzhledových balíčků Manjara"; then
  pkgs=$(installed $MANJARO_PKGS)
  [[ -n $pkgs ]] || { echo "Nic k odebrání."; }
  if [[ -n $pkgs ]]; then
    echo "-- odebere se (včetně nepotřebných závislostí):"
    pacman -Rs --print-format '   %n %v' $pkgs # -n (nosave) nejde s --print
    confirm
    pacman -Rns --noconfirm $pkgs
  fi
  echo "-- zbylé balíky s manjaro / breath v názvu:"; pacman -Qq | grep -i -E "manjaro|breath" || echo "   žádné"
  echo "Teď otevři novou Konsoli a Ghostty a zkontroluj vzhled a našeptávání."
fi

CURRENT=4
if phase 4 "Odebrání GRUBu (jen po testu záchrany z USB)"; then
  echo "Záchrana z live USB vyzkoušená (nabootovat, odemknout LUKS, připojit btrfs)?"
  confirm
  efibootmgr
  entry=$(efibootmgr | sed -n 's/^Boot\([0-9A-F]\{4\}\)\*\? manjaro\s.*/\1/p')
  [[ -n $entry ]] && efibootmgr -b "$entry" -B
  [[ -d $ESP/EFI/Manjaro ]] && mv "$ESP/EFI/Manjaro" "$BACKUP/esp-EFI-Manjaro"
  pkgs=$(installed $GRUB_PKGS)
  [[ -n $pkgs ]] && pacman -Rns --noconfirm $pkgs
  sed -i '/^IgnorePkg = grub$/d' /etc/pacman.conf
  [[ -d /boot/grub ]] && mv /boot/grub "$BACKUP/boot-grub"
  # initramfs v /boot potřeboval jen GRUB; dál se staví jen UKI
  for k in linux linux-lts; do
    sed -i -e '/^default_image=/d' -e "s|^# mkinitcpio preset pro '$k':.*|# mkinitcpio preset pro '$k': UKI pro systemd-boot|" /etc/mkinitcpio.d/$k.preset
  done
  mkinitcpio -P
  for f in /boot/initramfs-linux.img /boot/initramfs-linux-lts.img; do [[ -f $f ]] && mv "$f" "$BACKUP/"; done
  echo "-- efibootmgr:"; efibootmgr
  echo "-- ESP:"; ls -R "$ESP/EFI"
  echo "-- /boot:"; ls /boot
  confirm
fi

CURRENT=5
if phase 5 "LUKS: odebrání keyslotu s keyfile"; then
  dev=/dev/disk/by-uuid/$LUKS_UUID
  if grep -q crypto_keyfile /etc/crypttab /etc/crypttab.initramfs; then
    echo "crypttab pořád odkazuje na keyfile, končím."; exit 1
  fi
  cryptsetup luksDump "$dev" | grep -E "^Version|Key Slot [0-9]+: ENABLED"
  if [[ -f /crypto_keyfile.bin ]]; then
    cryptsetup luksRemoveKey "$dev" /crypto_keyfile.bin
    shred -u /crypto_keyfile.bin
  fi
  echo "-- zbylé keysloty (musí zůstat ten s heslem):"
  cryptsetup luksDump "$dev" | grep -E "Key Slot [0-9]+: ENABLED"
fi

echo
echo "Hotovo (fáze $START–$END)."
