#!/bin/bash

# Opens the launcher, then Files and Ghostty in the VM's Desk and saves screenshots: desk-try.sh <work directory> <prefix of local pngs>

WORK=$1
PREFIX=$2
SSH=(ssh -q -i "$WORK/test-key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p 2222 tester@127.0.0.1)

"${SSH[@]}" bash -s <<'REMOTE'
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)
export WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls wayland-* | grep -v lock | head -1)
touch ~/sample.pdf ~/sample.png ~/sample.txt ~/sample.zip ~/sample.mp3
qs -c desk ipc call launcher toggle
timeout 2 tail -f /dev/null
grim /tmp/try-launcher.png
qs -c desk ipc call launcher toggle
timeout 1 tail -f /dev/null
qs -c desk ipc call files open
timeout 3 tail -f /dev/null
hyprctl eval 'hl.dispatch(hl.dsp.exec_cmd("ghostty"))' >/dev/null
timeout 4 tail -f /dev/null
grim /tmp/try-windows.png
hyprctl clients -j | jq -c '.[] | {class, title, at, size}' | cut -c1-120
echo "--- layout"; hyprctl devices -j | jq -r '.keyboards[] | select(.main) | .layout + " " + .active_keymap'
echo "--- secret service"; busctl --user --list 2>/dev/null | grep -c org.freedesktop.secrets
echo "--- portals"; pgrep -a 'xdg-desktop-portal' | cut -c1-70
REMOTE
"${SSH[@]}" 'cat /tmp/try-launcher.png' > "${PREFIX}-launcher.png"
"${SSH[@]}" 'cat /tmp/try-windows.png' > "${PREFIX}-windows.png"
