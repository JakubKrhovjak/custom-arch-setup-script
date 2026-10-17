#!/bin/bash
# Enable TRIM through LUKS on an already installed system (fresh installs get it from arch-install.sh).
# Adds the `discard` option to the root entry in /etc/crypttab.initramfs or /etc/crypttab (whichever the
# sd-encrypt initramfs uses), rebuilds the UKIs (the sbctl post hook signs them, ukify re-signs the PCR 11
# policy) and verifies them. No passphrase needed; takes effect after the next reboot.
# Trade-off: someone holding the disk can see which blocks are in use (not their content).
set -euo pipefail

[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

for f in /etc/crypttab.initramfs /etc/crypttab; do
    if [[ -f "$f" ]] && grep -qE '^\S+\s+UUID=\S+\s+\S+\s+\S*luks' "$f"; then
        CRYPTTAB=$f
        break
    fi
done
[[ -n "${CRYPTTAB:-}" ]] || { echo "No LUKS entry in /etc/crypttab(.initramfs)"; exit 1; }

if grep -E '^\S+\s+UUID=' "$CRYPTTAB" | grep -q 'discard'; then
    echo "discard already set in $CRYPTTAB"
else
    cp -a "$CRYPTTAB" "$CRYPTTAB.bak-$(date +%Y%m%d)"
    sed -i -E '/^\S+\s+UUID=\S+\s+\S+\s+\S*luks/s/\s*$/,discard/' "$CRYPTTAB"
    echo "discard added to $CRYPTTAB (backup next to it)"
    mkinitcpio -P
    sbctl verify
fi
grep -E '^\S+\s+UUID=' "$CRYPTTAB"
echo "Reboot, then check: sudo fstrim -v /   (should report trimmed bytes)"
