# Shared settings of the tmobile/ scripts. Override any of them in the environment or in ~/.config/tmobile/env.
# shellcheck shell=bash

TM_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HOME/.config/tmobile/env" ] && . "$HOME/.config/tmobile/env"

TM_VM_NAME="${TM_VM_NAME:-tmobile-vpn}"
# A fixed MAC + DHCP reservation keeps the VM on one address, which the tunnel units and the guest firewall rely on
TM_VM_MAC="${TM_VM_MAC:-52:54:00:7e:a0:01}"
TM_VM_IP="${TM_VM_IP:-192.168.122.239}"
TM_VM_USER="${TM_VM_USER:-tmobile}"
TM_VM_VCPUS="${TM_VM_VCPUS:-2}"
TM_VM_MEMORY_MB="${TM_VM_MEMORY_MB:-6144}"
TM_VM_DISK_GB="${TM_VM_DISK_GB:-64}"
TM_VM_DIR="${TM_VM_DIR:-/var/lib/libvirt/images}"
TM_HOST_IP="${TM_HOST_IP:-192.168.122.1}"
TM_LIBVIRT="qemu:///system"

TM_SOCKS_PORT="${TM_SOCKS_PORT:-1080}"
TM_HTTP_PROXY_PORT="${TM_HTTP_PROXY_PORT:-3128}"
TM_PASS_VAULT="${TM_PASS_VAULT:-tmobile-files}"
TM_PROJECT="${TM_PROJECT:-$HOME/projects/tmobile}"

tm_ok()   { echo -e "\033[0;32m[✓]\033[0m $1"; }
tm_info() { echo -e "\033[1;33m[i]\033[0m $1"; }
tm_err()  { echo -e "\033[0;31m[✗]\033[0m $1" >&2; }
tm_die()  { tm_err "$1"; exit 1; }

tm_vm_reachable() {
    timeout 2 bash -c "exec 3<>/dev/tcp/$TM_VM_IP/22" 2>/dev/null
}

tm_ssh() {
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$TM_VM_USER@$TM_VM_IP" "$@"
}
