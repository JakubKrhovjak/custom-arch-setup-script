#!/bin/bash

# Tries the login screen in the VM: wrong password first, then the right one: greeter-login.sh <work directory> <prefix of local pngs>

WORK=$1
PREFIX=$2
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SSH=(ssh -q -i "$WORK/test-key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -p 2222 tester@127.0.0.1)
keys() { python3 -I "$HERE/monitor.py" "$WORK" type "$1"; python3 -I "$HERE/monitor.py" "$WORK" key ret; }

keys wrongpassword
timeout 6 tail -f /dev/null
"${SSH[@]}" 'sudo -u greeter env XDG_RUNTIME_DIR=/run/user/964 WAYLAND_DISPLAY=wayland-1 grim /tmp/greeter-wrong.png; sudo cat /tmp/greeter-wrong.png' > "$PREFIX-wrong.png"
keys tester1234
timeout 25 tail -f /dev/null
"${SSH[@]}" bash -s <<'REMOTE'
echo "--- greeter processes"; pgrep -a -u greeter | grep -E 'Hyprland|qs |start.sh' | cut -c1-80
echo "--- user session"; pgrep -a -u tester -f 'Hyprland|qs -c desk|desk-session|first-login' | grep -v pgrep | cut -c1-90
loginctl list-sessions --no-legend
echo "--- keyring"; busctl --user call org.freedesktop.secrets /org/freedesktop/secrets/aliases/default org.freedesktop.DBus.Properties Get ss org.freedesktop.Secret.Collection Locked 2>&1 | cut -c1-100
echo "--- greetd"; sudo journalctl -u greetd -b --since "-60s" --no-pager | grep -v 'config:' | tail -6 | cut -c1-140
REMOTE
