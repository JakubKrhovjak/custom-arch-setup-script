#!/usr/bin/env bash
# rclone.conf (Proton Drive, Google Drive remotes) kept in the repo encrypted with age (passphrase).
#
#   rclone-conf.sh encrypt   ~/.config/rclone/rclone.conf  -> secrets/rclone.conf.age  (asks for a passphrase twice)
#   rclone-conf.sh decrypt   secrets/rclone.conf.age       -> ~/.config/rclone/rclone.conf (asks for the passphrase)
#
# Re-run "encrypt" after rclone refreshes tokens or you add a remote; commit the .age file, never the plain one.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAIN="$HOME/.config/rclone/rclone.conf"
ENC="$REPO/secrets/rclone.conf.age"

case "${1:-}" in
    encrypt)
        [ -f "$PLAIN" ] || { echo "no $PLAIN"; exit 1; }
        mkdir -p "$(dirname "$ENC")"
        age -p -o "$ENC" "$PLAIN"
        echo "encrypted -> $ENC ($(stat -c %s "$ENC") B); commit it"
        ;;
    decrypt)
        [ -f "$ENC" ] || { echo "no $ENC in the repo"; exit 1; }
        if [ -f "$PLAIN" ]; then
            echo "$PLAIN already exists, leaving it alone"; exit 0
        fi
        mkdir -p "$(dirname "$PLAIN")"
        ( umask 077 && age -d -o "$PLAIN" "$ENC" )
        echo "restored $PLAIN: $(rclone listremotes | tr '\n' ' ')"
        ;;
    *) echo "usage: $0 encrypt|decrypt"; exit 2 ;;
esac
