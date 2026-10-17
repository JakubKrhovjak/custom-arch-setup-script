# BIOS update – Gigabyte X670 AORUS ELITE AX

Current: **F6** (2023-01-19). Target: newest stable for the board revision (2026-10: **F42e**, AGESA 1.3.0.1d,
for rev 1.0/1.1/1.2; rev 1.3 boards use the `FCxx` line). The update resets the firmware settings, the
Secure Boot keys and possibly the fTPM, so the disk asks for the LUKS passphrase once afterwards.

## Before

1. **Board revision**: sticker on the PCB near the bottom left (`REV: 1.x`). F-series BIOS = rev 1.0/1.1/1.2.
2. **Download** from the official page only, e.g.
   `https://www.gigabyte.com/Motherboard/X670-AORUS-ELITE-AX-rev-10-12/support` → BIOS → newest non-beta.
   Unzip; copy the BIOS file (no folder) to the root of a FAT32 USB stick. The `ARCH_202610` stick works:
   just add the file next to the installer files, nothing gets formatted.
3. **LUKS passphrase**: make sure you know it (`sudo cryptsetup luksOpen --test-passphrase /dev/nvme1n1p2`).
   A **wired keyboard** must be at hand: Bluetooth does not work at the passphrase prompt.
4. **Timeshift snapshot**: `sudo timeshift --create --comments "before BIOS update"`.
5. **Settings to restore** (they go back to defaults):
   - SVM Mode = Enabled (KVM / the `win11-tia` VM), IOMMU = Enabled
   - EXPO profile (RAM currently runs at 5000 MT/s, 2 × 16 GB)
   - fan curves, boot order (systemd-boot / UEFI disk first), CSM = Disabled
   - photograph the BIOS screens you changed before.

## Flash

BIOS (Del at boot) → Q-Flash (F8) → *Update BIOS* → pick the file on the USB stick → keep the default
"update all"/"intact" option → wait, do not power off. The board reboots several times; the first boot after
DDR5 memory training can take a few minutes with a black screen. That is normal.

## After

1. BIOS → Load Optimized Defaults → restore the settings from step 5 → Secure Boot: **Setup Mode / delete all keys**
   (custom keys were reset anyway) → Secure Boot **Disabled** for now → save, boot.
2. The disk asks for the **LUKS passphrase** (TPM changed) – type it with the wired keyboard.
3. Enroll our signing keys again (they are still on disk in `/var/lib/sbctl`):
   `sudo bash ~/projects/custom-arch-setup-script/secureboot-tpm2.sh 2` → reboot → BIOS → Secure Boot **Enabled**.
4. Re-bind the disk to the TPM:
   `sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme1n1p2`
   (the signed PCR 11 policy key `/etc/systemd/tpm2-pcr-public-key.pem` is picked up automatically), then reboot:
   no passphrase prompt any more.
5. Check: `sudo sbctl status` (Secure Boot enabled), `cat /sys/devices/system/clocksource/clocksource0/current_clocksource`
   (should be `tsc`), the VM starts (`virsh -c qemu:///system start win11-tia`).

The Windows VM is not affected: its TPM is a software TPM stored on the host disk.
