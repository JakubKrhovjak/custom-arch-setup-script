#!/usr/bin/env bash
# Environment for the GPC apps (pci-be, epc-management-service, api-gateway, product-catalog, pci-fe, PCS/PCU):
# work folder from Proton Drive + its hourly sync, files from Proton Pass (CA, kubeconfigs, AWS, Maven),
# merged kubeconfig, Python 3.12 for PCS, the Keystone wrapper for Claude Code. Java 21/25, Node, Podman
# and Testcontainers come from setup-script.sh. Safe to run again.
#
#   apps.sh            everything that works without the VPN
#   apps.sh --clone    also clone the repos (needs the VPN tunnel and GITLAB/ITC tokens in the shell)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

CLONE="${1:-}"
UNIT_DIR="$HOME/.config/systemd/user"

sudo pacman -S --needed --noconfirm uv rclone jq
yay -S --needed --noconfirm kubelogin-bin
# PCS pins Python 3.12, which is older than Arch's python
uv python install 3.12
tm_ok "kubelogin, uv + Python 3.12"

bash "$TM_REPO/files.sh" restore

# Merge rather than replace: ~/.kube/config may already hold other clusters (k3s, kind)
configs=("$HOME"/.kube/configs/tmobile*.yaml)
if [ -f "${configs[0]}" ]; then
    first_context="$(kubectl config get-contexts -o name --kubeconfig "${configs[0]}" | head -n1)"
    if ! kubectl config get-contexts -o name 2>/dev/null | grep -qxF "$first_context"; then
        [ -f "$HOME/.kube/config" ] && cp "$HOME/.kube/config" "$HOME/.kube/config.bak.$(date +%Y%m%d%H%M)"
        merged="$(KUBECONFIG="$HOME/.kube/config:$(IFS=:; echo "${configs[*]}")" kubectl config view --flatten)"
        ( umask 077 && printf '%s\n' "$merged" > "$HOME/.kube/config" )
        tm_ok "T-Mobile contexts merged into ~/.kube/config (they use proxy-url socks5://127.0.0.1:$TM_SOCKS_PORT)"
    else
        tm_ok "~/.kube/config already has the T-Mobile contexts"
    fi
fi

mkdir -p "$HOME/.config/zsh"
cat > "$HOME/.config/zsh/claude-keystone-linux.zsh" <<EOF
# The Keystone gateway is reachable only through the VPN; Claude Code ignores PAC files and needs an HTTP proxy
functions -c claude-keystone _claude-keystone-base

claude-keystone() {
  (
    export HTTPS_PROXY='http://127.0.0.1:$TM_HTTP_PROXY_PORT'
    export NO_PROXY='localhost,127.0.0.1'
    export NODE_EXTRA_CA_CERTS="\$HOME/.config/tmobile/tmcz-ca.pem"
    _claude-keystone-base "\$@"
  )
}
EOF
tm_ok "claude-keystone via the HTTP proxy (~/.config/zsh/claude-keystone-linux.zsh)"

# The Linux remote is called proton:, the work scripts use the Mac's name hudba-zaloha:
rclone listremotes | grep -qx 'hudba-zaloha:' \
    || { rclone listremotes | grep -qx 'proton:' && rclone config create hudba-zaloha alias remote=proton: >/dev/null && tm_ok "rclone alias hudba-zaloha: -> proton:"; }
if rclone listremotes | grep -qx 'hudba-zaloha:'; then
    if [ ! -f "$TM_PROJECT/scripts/linux-proton-sync.sh" ]; then
        tm_info "pulling the work folder from Proton Drive into $TM_PROJECT..."
        mkdir -p "$TM_PROJECT"
        rclone copy hudba-zaloha:tmobile "$TM_PROJECT" --filter-from <(rclone cat hudba-zaloha:tmobile/.rclone-filter) --update --transfers 4
    fi
    mkdir -p "$UNIT_DIR"
    printf '%s\n' '[Unit]' 'Description=Sync ~/projects/tmobile with Proton Drive (push to tmobile-linux, pull Mac copy)' \
        'After=network-online.target' '' '[Service]' 'Type=oneshot' "ExecStart=$TM_PROJECT/scripts/linux-proton-sync.sh" \
        > "$UNIT_DIR/tmobile-proton-sync.service"
    printf '%s\n' '[Unit]' 'Description=Hourly tmobile <-> Proton Drive sync' '' '[Timer]' 'OnCalendar=hourly' \
        'Persistent=true' 'RandomizedDelaySec=120' '' '[Install]' 'WantedBy=timers.target' \
        > "$UNIT_DIR/tmobile-proton-sync.timer"
    systemctl --user daemon-reload
    systemctl --user enable --now tmobile-proton-sync.timer >/dev/null
    tm_ok "work folder $TM_PROJECT, hourly Proton sync (journalctl --user -u tmobile-proton-sync)"
else
    tm_err "no rclone remote proton: (setup-script.sh restores rclone.conf); skipped the work folder and its sync"
fi

if [ "$CLONE" = "--clone" ]; then
    [ -x "$TM_PROJECT/scripts/clone-repos.sh" ] || tm_die "no $TM_PROJECT/scripts/clone-repos.sh (work folder missing)"
    systemctl --user is-active --quiet tmobile-socks.service || tm_die "VPN tunnel down: start the VM and connect FortiClient first"
    ( cd "$TM_PROJECT" && scripts/clone-repos.sh )
fi

[ -f "$HOME/.m2/settings.xml" ] || tm_info "no ~/.m2/settings.xml: Maven gets 401 from Artifactory until it is in Proton Pass (files.sh push on a machine that has it)"
tm_ok "app environment ready. Next: databases (scripts/db-restore.sh in $TM_PROJECT), then the /sylius-fresh skill or dev-up.sh"
