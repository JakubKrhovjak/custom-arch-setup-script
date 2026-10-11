#!/usr/bin/env bash
# Optional: Secure Boot with own keys + unlocking the disk via TPM2 (the passphrase stays as a fallback keyslot).
#
# Why: TPM2 releases the disk key on its own, but only when the chain signed by our keys boots
# (PCR 7 = Secure Boot state and keys). Without Secure Boot TPM2 would release it to any UKI → only together.
#
# Before: BIOS → Secure Boot → reset to Setup Mode (delete keys), so PK/KEK/db are empty.
#
# 1: sudo bash secureboot-tpm2.sh 1   sbctl keys, sign UKIs and systemd-boot (firmware untouched)
# 2: sudo bash secureboot-tpm2.sh 2   enroll keys to firmware (+ Microsoft for GPU option ROMs),
#                                     then reboot → BIOS → Secure Boot Enabled
# 3: sudo bash secureboot-tpm2.sh 3   after reboot: TPM2 keyslot (asks for the passphrase), crypttab, new UKIs;
#                                     next reboot unlocks the disk without a passphrase
#
# Recovery: no boot with Secure Boot → BIOS → Secure Boot Disabled (keys stay), boots as before.
#   TPM2 does not release the key (BIOS update, key change) → asks for the passphrase; then re-run phase 3
#   after: systemd-cryptenroll --wipe-slot=tpm2 <luks device>.
#   Keep a wired keyboard around — Bluetooth does not work at the passphrase prompt.

set -euo pipefail
export LANG=C

START=${1:-1}
END=${2:-$START}
CRYPTTAB=/etc/crypttab.initramfs
LUKS_UUID=$(sed -nE 's/^\S+\s+UUID=(\S+).*/\1/p' "$CRYPTTAB" | head -n1)
LUKS_DEV=/dev/disk/by-uuid/$LUKS_UUID
BACKUP=/root/secureboot-backup
ESP=/boot/efi
SDBOOT_SRC=/usr/lib/systemd/boot/efi/systemd-bootx64.efi

phase() { # number, name
  [[ $1 -ge $START && $1 -le $END ]] || return 1
  echo
  echo "================ Phase $1: $2 ================"
}

confirm() {
  read -rp "Continue? [y/N] " answer
  [[ $answer =~ ^[yY]$ ]] || { echo "Stopped."; exit 1; }
}

sb_state() { bootctl status 2>/dev/null | sed -n 's/^\s*Secure Boot:\s*//p'; }

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
[[ -b $LUKS_DEV ]] || { echo "LUKS device from $CRYPTTAB not found: $LUKS_DEV"; exit 1; }

if phase 1 "sbctl keys and signatures"; then
  [[ $(sb_state) == "disabled (setup)" ]] || { echo "Firmware is not in setup mode: $(sb_state)"; exit 1; }
  mkdir -p "$BACKUP"
  # original firmware variables (dbx comes from the vendor); cp cannot read efivarfs (lseek)
  find /sys/firmware/efi/efivars -regextype egrep -regex '.*/(PK|KEK|db|dbx)-.*' -exec sh -c 'cat "$1" > "$2/${1##*/}"' _ {} "$BACKUP" \;
  ls -l "$BACKUP"

  sbctl setup --print-state --json | grep -qE '"installed":\s*true' || sbctl create-keys
  # -s = save to the sbctl database → pacman / mkinitcpio hooks sign new versions too
  for f in "$ESP"/EFI/Linux/*.efi "$ESP/EFI/systemd/systemd-bootx64.efi" "$ESP/EFI/BOOT/BOOTX64.EFI"; do
    sbctl sign -s "$f"
  done
  # signed source → bootctl update / systemd-boot-update copy an already signed loader to the ESP
  sbctl sign -s -o "$SDBOOT_SRC.signed" "$SDBOOT_SRC"
  # fwupd (BIOS updates): signed EFI binary booted without shim
  FWUPD_EFI=/usr/lib/fwupd/efi/fwupdx64.efi
  if [[ -f $FWUPD_EFI ]]; then
    sbctl sign -s -o "$FWUPD_EFI.signed" "$FWUPD_EFI"
    grep -q '^\[uefi_capsule\]' /etc/fwupd/fwupd.conf 2>/dev/null \
      || printf '\n[uefi_capsule]\nDisableShimForSecureBoot=true\n' >> /etc/fwupd/fwupd.conf
  fi
  sbctl verify
fi

if phase 2 "Enroll keys to firmware"; then
  [[ $(sb_state) == "disabled (setup)" ]] || { echo "Firmware is not in setup mode: $(sb_state)"; exit 1; }
  sbctl verify
  echo "Enrolling PK/KEK/db: our keys + Microsoft (GPU option ROMs are signed by Microsoft;"
  echo "without them the screen may stay black). The firmware leaves setup mode."
  confirm
  sbctl enroll-keys --microsoft
  sbctl status
  echo
  echo "Now reboot → BIOS → Secure Boot → Enabled (mode Custom, do NOT restore default keys)"
  echo "→ Save & Exit. Then: sudo bash secureboot-tpm2.sh 3"
fi

if phase 3 "TPM2 keyslot (PCR 7) and new UKIs"; then
  [[ $(sb_state) == enabled* ]] || { echo "Secure Boot is not enabled: $(sb_state)"; exit 1; }
  sbctl status
  if ! cryptsetup luksDump "$LUKS_DEV" | grep -q systemd-tpm2; then
    systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "$LUKS_DEV"
  fi
  cryptsetup luksDump "$LUKS_DEV" | grep -E '^  [0-9]+: |systemd-tpm2|tpm2-pcrs'
  grep -q 'tpm2-device=' "$CRYPTTAB" || sed -i -E "/UUID=$LUKS_UUID/s/\s*$/,tpm2-device=auto/" "$CRYPTTAB"
  cat "$CRYPTTAB"
  mkinitcpio -P # sbctl post hook signs the new UKIs
  sbctl verify
  echo
  echo "Reboot: the disk should unlock without a passphrase."
fi

echo
echo "Done (phase $START–$END)."
