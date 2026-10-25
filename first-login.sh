#!/bin/bash

# Runs once after the first login (autostart in Ghostty, set up by arch-install.sh):
# post-install.sh (look & feel) and setup-script.sh (dev tools), with progress on screen and in a log.
# On failure the autostart stays → it runs again at next login (both scripts are safe to repeat).

set -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOSTART="$HOME/.config/autostart/arch-setup.desktop"
LOG="$REPO/first-login.log"

finish() { # message
    echo ""
    echo "$1"
    read -rp "Press Enter to close..."
    exit 0
}

echo "First login setup — log: $LOG"
echo "sudo asks for your password once; it stays valid until the setup ends."
sudo -v || finish "sudo failed, setup will run again at next login."

# keep sudo alive (yay, pacman, podman…) until this script ends
while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 50; done 2>/dev/null &

sleep 5 # let Plasma finish starting (post-install changes the running session)

for STEP in post-install.sh setup-script.sh; do
    echo ""
    echo "════════════════ $STEP ════════════════"
    if ! bash "$REPO/$STEP" 2>&1 | tee -a "$LOG"; then
        finish "$STEP FAILED — see $LOG. Setup will run again at next login."
    fi
done

rm -f "$AUTOSTART"
finish "All done. Log out and back in (theme on the login screen, libvirt group)."
