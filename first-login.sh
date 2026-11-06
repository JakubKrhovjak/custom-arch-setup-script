#!/bin/bash

# Runs once after the first login, with progress on screen and in a log: look & feel, then setup-script.sh (dev tools).
# Plasma: post-install.sh, started in Ghostty by an autostart entry. Desk: desk-install.sh, started on the console by desk-session.sh.
# On failure it runs again at next login (all the scripts are safe to repeat).

set -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOSTART="$HOME/.config/autostart/arch-setup.desktop"
LOG="$REPO/first-login.log"
DESKTOP=$(cat "$REPO/desktop" 2>/dev/null || echo plasma)
# local.env exists only in the VM test (vm-test/): where to clone from, which steps to skip
[ -f "$REPO/local.env" ] && . "$REPO/local.env"
if [ "$DESKTOP" = desk ]; then
    STEPS=(desk-install.sh setup-script.sh)
else
    STEPS=(post-install.sh setup-script.sh)
fi
[ "${SKIP_DEV_TOOLS:-}" = 1 ] && unset 'STEPS[1]'

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

[ "$DESKTOP" = desk ] || sleep 5 # let Plasma finish starting (post-install changes the running session)

for STEP in "${STEPS[@]}"; do
    echo ""
    echo "════════════════ $STEP ════════════════"
    if ! bash "$REPO/$STEP" 2>&1 | tee -a "$LOG"; then
        finish "$STEP FAILED — see $LOG. Setup will run again at next login."
    fi
done

rm -f "$AUTOSTART"
touch "$REPO/.first-login-done"
[ "$DESKTOP" = desk ] && finish "All done. Press Enter to start the desktop."
finish "All done. Log out and back in (theme on the login screen, libvirt group)."
