#!/bin/bash

# Checks the running Desk session in the VM and saves a screenshot: desk-check.sh <work directory> <local png>

WORK=$1
OUT=$2
SSH=(ssh -q -i "$WORK/test-key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p 2222 tester@127.0.0.1)

"${SSH[@]}" bash -s <<'REMOTE'
export XDG_RUNTIME_DIR=/run/user/$(id -u)
signature=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
export HYPRLAND_INSTANCE_SIGNATURE=$signature
wayland=$(cd "$XDG_RUNTIME_DIR" && ls wayland-* 2>/dev/null | grep -v lock | head -1)
export WAYLAND_DISPLAY=$wayland
echo "instance=$signature wayland=$wayland"
echo "--- processes"; pgrep -a 'Hyprland|start-hyprland|^qs$|gnome-keyring|kdeconnect' | cut -c1-90
echo "--- monitors"; hyprctl monitors -j 2>/dev/null | jq -c '.[] | {name, width, height}'
echo "--- layers"; hyprctl layers -j 2>/dev/null | jq -r '.. | .namespace? // empty' | sort -u | paste -sd' '
echo "--- config errors"; hyprctl configerrors 2>&1 | head -10 | cut -c1-160
echo "--- plugin"; hyprctl plugin list 2>&1 | head -3 | cut -c1-80
echo "--- icon theme"; grep -m1 Inherits ~/.local/share/icons/Simpleton/index.theme; grep -h iconTheme ~/.config/qtengine/config.json
echo "--- scheme"; jq -r '.name' ~/.local/state/caelestia/scheme.json 2>&1
echo "--- shell log"; qs -c desk log 2>/dev/null | grep -i -E ' (error|warn|critical)|fatal' | cut -c1-170 | tail -15
grim /tmp/desk-check.png 2>&1 | head -2
REMOTE
"${SSH[@]}" 'cat /tmp/desk-check.png' > "$OUT"
