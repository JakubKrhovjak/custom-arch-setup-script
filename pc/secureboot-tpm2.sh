#!/usr/bin/env bash
# Secure Boot s vlastními klíči + odemykání disku přes TPM2 (heslo zůstane jako záložní keyslot).
#
# Proč: heslo LUKS se zadává v initramfs, kde BT klávesnice ještě nefunguje. TPM2 vydá klíč sám,
# ale jen když se bootuje řetěz podepsaný našimi klíči (PCR 7 = stav Secure Bootu a použité klíče).
# Bez Secure Bootu by TPM vydal klíč komukoli, kdo podstrčí jiné UKI → TPM2 jen se Secure Bootem.
#
# Předem (hotovo 2026-10-11): LUKS2 + Argon2id, Timeshift „luks2“, záloha hlavičky
#   /mnt/data/backup/luks2/luks2-header.img. Firmware v setup módu (PK/KEK/db prázdné).
#
# 1: sudo bash pc/secureboot-tpm2.sh 1   klíče sbctl, podpis UKI a systemd-boot (bez zásahu do firmwaru)
# 2: sudo bash pc/secureboot-tpm2.sh 2   zápis klíčů do firmwaru (+ Microsoft kvůli option ROM grafiky),
#                                             pak restart → BIOS → Secure Boot Enabled
# 3: sudo bash pc/secureboot-tpm2.sh 3   po restartu: kontrola, TPM2 keyslot (ptá se na heslo → spouští uživatel),
#                                             crypttab + nové UKI; pak restart = odemčení bez hesla
#
# Záchrana: když se po zapnutí Secure Bootu nenabootuje → BIOS → Secure Boot Disabled (klíče zůstanou),
#   systém naběhne jako dřív. Když TPM klíč nevydá (update BIOSu, změna klíčů), zeptá se na heslo.
#   Live USB (Manjaro, bez shim) se Secure Bootem nenabootuje → na záchranu Secure Boot v BIOSu vypnout.

set -euo pipefail
export LANG=C

START=${1:-1}
END=${2:-$START}
LUKS_UUID=55b62d42-4184-41bc-9f97-7765ed5e7619
LUKS_DEV=/dev/disk/by-uuid/$LUKS_UUID
BACKUP=/mnt/data/backup/secureboot
ESP=/boot/efi
SDBOOT_SRC=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
UKIS=("$ESP/EFI/Linux/arch-linux.efi" "$ESP/EFI/Linux/arch-linux-lts.efi")
LOADERS=("$ESP/EFI/systemd/systemd-bootx64.efi" "$ESP/EFI/BOOT/BOOTX64.EFI")
CRYPTTABS=(/etc/crypttab.initramfs /etc/crypttab)

phase() { # číslo, název
  [[ $1 -ge $START && $1 -le $END ]] || return 1
  echo
  echo "================ Fáze $1: $2 ================"
}

confirm() {
  read -rp "Pokračovat? [a/N] " answer
  [[ $answer =~ ^([aAyY]|ano)$ ]] || { echo "Zastaveno."; exit 1; }
}

sb_state() { bootctl status 2>/dev/null | sed -n 's/^\s*Secure Boot:\s*//p'; }

[[ $EUID -eq 0 ]] || { echo "Spusť přes sudo."; exit 1; }

if phase 1 "Klíče sbctl a podpisy"; then
  [[ $(sb_state) == "disabled (setup)" ]] || { echo "Firmware není v setup módu: $(sb_state)"; exit 1; }
  mkdir -p "$BACKUP"
  # původní proměnné firmwaru (PK/KEK/db jsou prázdné, dbx je od výrobce)
  find /sys/firmware/efi/efivars -regextype egrep -regex '.*/(PK|KEK|db|dbx)-.*' -exec sh -c 'cat "$1" > "$2/${1##*/}"' _ {} "$BACKUP" \; # cp na efivarfs neumí (lseek)
  ls -l "$BACKUP"

  sbctl setup --print-state --json | grep -qE '"installed":\s*true' || sbctl create-keys
  # -s = zapsat do databáze sbctl → pacman hook a mkinitcpio post hook podepíšou i nové verze
  for f in "${UKIS[@]}" "${LOADERS[@]}"; do sbctl sign -s "$f"; done
  # podepsaný zdroj → systemd-boot-update / bootctl update kopírují na ESP rovnou podepsanou verzi
  sbctl sign -s -o "$SDBOOT_SRC.signed" "$SDBOOT_SRC"
  sbctl verify
  sbctl list-files
fi

if phase 2 "Zápis klíčů do firmwaru"; then
  [[ $(sb_state) == "disabled (setup)" ]] || { echo "Firmware není v setup módu: $(sb_state)"; exit 1; }
  sbctl verify
  echo "Zapíšu PK/KEK/db: naše klíče + Microsoft (option ROM grafiky RX 6700 XT je podepsaná Microsoftem;"
  echo "bez nich hrozí černá obrazovka). Firmware tím opustí setup mód."
  confirm
  sbctl enroll-keys --microsoft
  sbctl status
  echo
  echo "Teď restart → BIOS (Del) → Boot → Secure Boot → Enabled (Secure Boot Mode: Custom, NEOBNOVOVAT"
  echo "výchozí klíče) → Save & Exit. Pak: sudo bash pc/secureboot-tpm2.sh 3"
fi

if phase 3 "TPM2 keyslot (PCR 7) a nové UKI"; then
  [[ $(sb_state) == enabled* ]] || { echo "Secure Boot není zapnutý: $(sb_state)"; exit 1; }
  sbctl status
  if ! cryptsetup luksDump "$LUKS_DEV" | grep -q systemd-tpm2; then
    systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "$LUKS_DEV"
  fi
  cryptsetup luksDump "$LUKS_DEV" | grep -E '^  [0-9]+: |systemd-tpm2|tpm2-pcrs'
  for t in "${CRYPTTABS[@]}"; do
    [[ -f $t ]] || continue
    cp -a "$t" "$BACKUP/$(basename "$t").pred-tpm2"
    grep -q 'tpm2-device=' "$t" || sed -i -E "/^luks-$LUKS_UUID /s/\s*$/,tpm2-device=auto/" "$t"
    echo "-- $t:"; cat "$t"
  done
  mkinitcpio -P # post hook sbctl podepíše nová UKI
  sbctl verify
  echo
  echo "Restart: disk se má odemknout bez hesla. Když se zeptá na heslo, TPM klíč nevydal (napiš mi)."
fi

echo
echo "Hotovo (fáze $START–$END)."
