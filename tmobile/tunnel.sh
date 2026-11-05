#!/usr/bin/env bash
# Host side of the VPN: user units for the SOCKS tunnel into the VM (socks5://127.0.0.1:1080), a watcher that
# starts it whenever the VM comes up, an HTTP proxy in front of it (127.0.0.1:3128) and on-demand DB forwards.
# Safe to run again; re-renders the units from tmobile/systemd/ with the values from env.sh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

UNIT_DIR="$HOME/.config/systemd/user"

sudo pacman -S --needed --noconfirm openssh uv
command -v pproxy >/dev/null || [ -x "$HOME/.local/bin/pproxy" ] || uv tool install pproxy
tm_ok "pproxy: $HOME/.local/bin/pproxy"

mkdir -p "$UNIT_DIR"
for template in "$TM_REPO"/systemd/*; do
    sed -e "s|@VM_NAME@|$TM_VM_NAME|g" -e "s|@VM_IP@|$TM_VM_IP|g" -e "s|@VM_USER@|$TM_VM_USER|g" \
        -e "s|@SOCKS_PORT@|$TM_SOCKS_PORT|g" -e "s|@HTTP_PROXY_PORT@|$TM_HTTP_PROXY_PORT|g" \
        "$template" > "$UNIT_DIR/$(basename "$template")"
done
# An older hand-made drop-in (ExecCondition, Restart) is now part of the unit itself
[ -f "$UNIT_DIR/tmobile-socks.service.d/override.conf" ] \
    && tm_info "remove $UNIT_DIR/tmobile-socks.service.d/override.conf: its settings are in the unit now"

systemctl --user daemon-reload
systemctl --user enable tmobile-socks.service tmobile-http-proxy.service >/dev/null
systemctl --user enable --now tmobile-socks-watch.timer >/dev/null
tm_vm_reachable && systemctl --user restart tmobile-socks.service tmobile-http-proxy.service
tm_ok "tunnel units installed (VM $TM_VM_USER@$TM_VM_IP); DB forwards: systemctl --user start tmobile-dev1-pg tmobile-test2-pg"
