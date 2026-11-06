#!/bin/bash

# Reinstalls the greeter in the VM, ends the Desk session and captures the login screen: greeter-check.sh <work directory> <local png>
# Expects passwordless sudo for the tester user, added only in the test VM.

WORK=$1
OUT=$2
SSH_OPTS=(-q -i "$WORK/test-key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -p 2222)
SSH=(ssh "${SSH_OPTS[@]}" tester@127.0.0.1)

rsync -a -e "ssh ${SSH_OPTS[*]}" "$HOME/.config/desk/greeter/" tester@127.0.0.1:.config/desk/greeter/
"${SSH[@]}" bash -s <<'REMOTE'
~/.config/desk/greeter/install.sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
if [ -d "$XDG_RUNTIME_DIR/hypr" ]; then
    export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)
    hyprctl eval 'hl.dispatch(hl.dsp.exit())' >/dev/null 2>&1
fi
sudo systemctl restart greetd
sleep 12
as_greeter() { sudo -u greeter env XDG_RUNTIME_DIR=/run/user/964 WAYLAND_DISPLAY=wayland-1 "$@"; }
echo "--- processes"; pgrep -a -u greeter | cut -c1-90
echo "--- greetd log"; sudo journalctl -u greetd -b --since "-40s" --no-pager | tail -12 | cut -c1-170
echo "--- shell log"; sudo find /run/user/964 -name '*.log' 2>/dev/null | tail -1 | xargs -r sudo tail -12 | cut -c1-170
as_greeter grim /tmp/greeter.png
REMOTE
"${SSH[@]}" 'sudo cat /tmp/greeter.png' > "$OUT"
