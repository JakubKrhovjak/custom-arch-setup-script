#!/bin/bash

# Tries an update in the VM before it goes to the real computer: update-test.sh <work directory>
# Saves a disk snapshot, runs the real desk-update, reboots and checks the login screen and the Desk session.
# Expects a finished install with passwordless sudo for the tester user, added only in the test VM.
# After a failure the VM keeps running for a look; back to the state before: qemu-img snapshot -a pre-update disk.qcow2

set -uo pipefail

WORK=$1
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SSH=(ssh -q -i "$WORK/test-key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -p 2222 tester@127.0.0.1)
SNAPSHOT=pre-update
failed=0

running() { pgrep -f '^qemu-system-x86_64 -name desk-install-test' >/dev/null; }
pause() { timeout "$1" tail -f /dev/null; }
check() { # description, command that must succeed
    if "${@:2}" >/dev/null 2>&1; then
        echo "ok    $1"
    else
        echo "FAIL  $1"
        failed=1
    fi
}

stop_vm() {
    running || return 0
    python3 -I "$HERE/hmp.py" "$WORK" system_wakeup >/dev/null 2>&1
    pause 5
    "${SSH[@]}" 'sudo systemctl poweroff' 2>/dev/null
    for _ in $(seq 1 45); do
        running || return 0
        pause 2
    done
    echo "VM did not stop" >&2
    exit 1
}

boot_vm() {
    "$HERE/vm.sh" "$WORK" disk >/dev/null
    pause 25
    python3 -I "$HERE/monitor.py" "$WORK" type disk1234
    python3 -I "$HERE/monitor.py" "$WORK" key ret
    for _ in $(seq 1 30); do
        "${SSH[@]}" true 2>/dev/null && break
        pause 3
    done
    pause 15
}

versions() {
    "${SSH[@]}" 'pacman -Q linux-zen hyprland quickshell-git caelestia-shell qt6-base localsend-bin 2>/dev/null | paste -sd" "'
}

stop_vm
qemu-img snapshot -d "$SNAPSHOT" "$WORK/disk.qcow2" 2>/dev/null
qemu-img snapshot -c "$SNAPSHOT" "$WORK/disk.qcow2" || exit 1
boot_vm

echo "before: $(versions)"
# The test server takes no pushes; without origin desk-update saves its state only locally
"${SSH[@]}" 'git -C ~/.config/quickshell/caelestia remote remove origin; git -C ~/.config remote remove origin' 2>/dev/null
"${SSH[@]}" '~/.config/desk/desk-update.sh --yes' > "$WORK/update.log" 2>&1
update_status=$?
tail -5 "$WORK/update.log" | cut -c1-140
echo "after:  $(versions)"
check "desk-update finished without errors" test "$update_status" -eq 0

"${SSH[@]}" 'sudo systemctl reboot' 2>/dev/null
pause 25
boot_vm

greeter=$("${SSH[@]}" 'pgrep -a -u greeter | grep -cE "Hyprland|qs "')
check "login screen runs (Hyprland and shell)" test "$greeter" -eq 2

"$HERE/greeter-login.sh" "$WORK" "$WORK/update" > "$WORK/update-login.log" 2>&1
pause 12

state=$("${SSH[@]}" bash -s <<'REMOTE'
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)
export WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls wayland-* | grep -v lock | head -1)
echo "session=$(pgrep -c -x Hyprland)"
echo "shell=$(pgrep -c -x qs)"
echo "panel=$(hyprctl layers -j | jq -r '.. | .namespace? // empty' | grep -c '^caelestia-desk-panel$')"
echo "config_errors=$(hyprctl configerrors | grep -cv '^\s*$')"
echo "hyprbars=$(hyprctl plugin list | grep -c hyprbars)"
echo "keyring_locked=$(busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/aliases/default org.freedesktop.Secret.Collection Locked | cut -d' ' -f2)"
echo "localsend=$(pgrep -c -x localsend)"
grim /tmp/update-desk.png
REMOTE
)
"${SSH[@]}" 'cat /tmp/update-desk.png' > "$WORK/update-desk.png"
value() { sed -n "s/^$1=//p" <<< "$state"; }

check "login works and starts Desk" test "$(value session)" -ge 1
check "shell runs" test "$(value shell)" -ge 1
check "panel is shown" test "$(value panel)" -ge 1
check "no config errors" test "$(value config_errors)" -eq 0
check "hyprbars loaded" test "$(value hyprbars)" -ge 1
check "keyring unlocked" test "$(value keyring_locked)" = false

if [ "$failed" -eq 0 ]; then
    echo "PASS: the update can go to the real computer today"
    stop_vm
else
    echo "FAIL: do not update the real computer; logs: $WORK/update.log, $WORK/update-login.log, screen: $WORK/update-desk.png"
fi
exit "$failed"
