#!/usr/bin/env bash
# Small Windows 11 Pro VM that only runs the T-Mobile FortiClient VPN (2 vCPU, 6 GB RAM by default, see env.sh).
# Arch is not in the VPN's posture rules and the special FortiClient build is Windows only, hence the VM;
# the host reaches the internal network through an SSH SOCKS tunnel into it (tunnel.sh).
#
#   vm.sh create --iso Win11.iso [--lang en-US]   define the VM, unattended install (no Microsoft account)
#   vm.sh provision [--no-updates] [--forticlient FILE]
#                                                 certificates, BitLocker, MTU, optional FortiClient installer
#   vm.sh status | console | ssh [CMD]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
VIRTIO_ISO="$TM_VM_DIR/virtio-win.iso"
UNATTEND_ISO="$TM_VM_DIR/$TM_VM_NAME-unattend.iso"
DISK="$TM_VM_DIR/$TM_VM_NAME.qcow2"
REMOTE_DIR='C:\ProgramData\tmobile-provision'

virsh_() { virsh -c "$TM_LIBVIRT" "$@"; }

xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; s="${s//\'/&apos;}"
    printf '%s' "$s"
}

qemu_can_read() {
    sudo -u libvirt-qemu test -r "$1" 2>/dev/null
}

ensure_network() {
    virsh_ net-info default >/dev/null 2>&1 || tm_die "libvirt network 'default' missing"
    virsh_ net-autostart default >/dev/null
    virsh_ net-info default | grep -q '^Active:.*yes' || virsh_ net-start default >/dev/null
    if ! virsh_ net-dumpxml default | grep -q "mac='$TM_VM_MAC'"; then
        virsh_ net-update default add ip-dhcp-host "<host mac='$TM_VM_MAC' name='$TM_VM_NAME' ip='$TM_VM_IP'/>" --live --config >/dev/null
        tm_ok "DHCP reservation $TM_VM_MAC -> $TM_VM_IP"
    fi
}

build_unattend_iso() {
    local lang="$1" password="$2" work
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' RETURN
    shopt -u patsub_replacement 2>/dev/null || true
    local xml
    xml="$(<"$TM_REPO/vm/autounattend.xml")"
    xml="${xml//@LANG@/$lang}"
    xml="${xml//@COMPUTER@/$TM_VM_NAME}"
    xml="${xml//@USER@/$(xml_escape "$TM_VM_USER")}"
    xml="${xml//@PASSWORD@/$(xml_escape "$password")}"
    ( umask 077 && printf '%s\n' "$xml" > "$work/autounattend.xml" )
    xmllint --noout "$work/autounattend.xml"
    cp "$TM_REPO/vm/firstlogon.ps1" "$work/"
    cp "$HOME/.ssh/id_ed25519.pub" "$work/authorized_keys"
    printf '%s\n' "$TM_HOST_IP" > "$work/host-ip.txt"
    xorriso -as mkisofs -quiet -J -r -V UNATTEND -o "$work/unattend.iso" "$work" 2>/dev/null
    sudo install -m 600 -o libvirt-qemu -g libvirt-qemu "$work/unattend.iso" "$UNATTEND_ISO"
}

create() {
    local iso="" lang="en-US"
    while [ $# -gt 0 ]; do
        case "$1" in
            --iso) iso="$2"; shift 2 ;;
            --lang) lang="$2"; shift 2 ;;
            *) tm_die "unknown option $1" ;;
        esac
    done
    [ -f "$iso" ] || tm_die "usage: vm.sh create --iso Win11.iso (download: https://www.microsoft.com/software-download/windows11)"
    virsh_ dominfo "$TM_VM_NAME" >/dev/null 2>&1 && tm_die "VM $TM_VM_NAME already exists"
    [ -f "$HOME/.ssh/id_ed25519.pub" ] || ssh-keygen -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519" -q

    sudo pacman -S --needed --noconfirm qemu-desktop libvirt virt-manager edk2-ovmf swtpm dnsmasq libisoburn libxml2
    sudo mkdir -p "$TM_VM_DIR"
    [ -f "$VIRTIO_ISO" ] || { tm_info "downloading virtio-win drivers..."; sudo curl -fL -o "$VIRTIO_ISO" "$VIRTIO_URL"; }
    if ! qemu_can_read "$iso"; then
        # libvirt-qemu cannot traverse a 700 home directory
        tm_info "copying the ISO to $TM_VM_DIR (qemu cannot read $iso)"
        sudo install -m 644 "$iso" "$TM_VM_DIR/$(basename "$iso")"
        iso="$TM_VM_DIR/$(basename "$iso")"
    fi

    local password confirm
    read -rsp "Password for the Windows user $TM_VM_USER (save it in Proton Pass): " password; echo
    read -rsp "Again: " confirm; echo
    [ -n "$password" ] && [ "$password" = "$confirm" ] || tm_die "passwords empty or different"
    build_unattend_iso "$lang" "$password"
    ensure_network

    # Empty disk first, Windows ISO second: UEFI falls through to the ISO once, then always boots the installed disk.
    # SATA, not virtio, for the disk: Windows Setup has no virtio storage driver and the install stays hands-off.
    virt-install --connect "$TM_LIBVIRT" --name "$TM_VM_NAME" --osinfo win11 \
        --vcpus "$TM_VM_VCPUS" --memory "$TM_VM_MEMORY_MB" --cpu host-passthrough \
        --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=yes \
        --tpm emulator,model=tpm-crb,version=2.0 \
        --disk "path=$DISK,size=$TM_VM_DISK_GB,format=qcow2,bus=sata,discard=unmap,boot.order=1" \
        --disk "path=$iso,device=cdrom,bus=sata,boot.order=2" \
        --disk "path=$VIRTIO_ISO,device=cdrom,bus=sata" \
        --disk "path=$UNATTEND_ISO,device=cdrom,bus=sata" \
        --network "network=default,model=virtio,mac=$TM_VM_MAC" \
        --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
        --graphics spice --video qxl --sound none \
        --import --noautoconsole
    tm_ok "VM $TM_VM_NAME defined and started"
    tm_info "In the console press a key at 'Press any key to boot from CD or DVD' (it waits 5 s, else reboot the VM)."
    tm_info "The install runs by itself (~20-40 min, two reboots). Then: bash $TM_REPO/vm.sh provision"
    virt-manager --connect "$TM_LIBVIRT" --show-domain-console "$TM_VM_NAME" >/dev/null 2>&1 &
}

wait_for_firstlogon() {
    tm_info "waiting for SSH on $TM_VM_IP (first logon finished)..."
    until tm_vm_reachable && tm_ssh 'Test-Path C:\ProgramData\tmobile-firstlogon.done' 2>/dev/null | grep -q True; do
        sleep 15
    done
    tm_ok "SSH into $TM_VM_USER@$TM_VM_IP works"
}

detach_install_media() {
    virsh_ domblklist "$TM_VM_NAME" --details | awk '$2 == "cdrom" && $4 != "-" {print $3, $4}' |
        while read -r target source; do
            [ "$source" = "$VIRTIO_ISO" ] && continue
            virsh_ change-media "$TM_VM_NAME" "$target" --eject --live --config >/dev/null && tm_ok "ejected $source"
        done
    # It holds the Windows password in plain text, so it must not outlive the install
    [ -f "$UNATTEND_ISO" ] && sudo rm -f "$UNATTEND_ISO" && tm_ok "removed $UNATTEND_ISO"
}

store_recovery() {
    local key="$1" title="vm/bitlocker-recovery-$TM_VM_NAME"
    if pass-cli item view --vault-name "$TM_PASS_VAULT" --item-title "$title" >/dev/null 2>&1; then
        pass-cli item update --vault-name "$TM_PASS_VAULT" --item-title "$title" --field "note=$key" >/dev/null
    else
        jq -n --arg t "$title" --arg n "$key" '{title: $t, note: $n}' \
            | pass-cli item create note --vault-name "$TM_PASS_VAULT" --from-template - >/dev/null
    fi
    tm_ok "BitLocker recovery key stored in Proton Pass ($TM_PASS_VAULT / $title)"
}

provision() {
    local args=() forti=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-updates) args+=(-NoUpdates); shift ;;
            --forticlient) forti="$2"; shift 2 ;;
            *) tm_die "unknown option $1" ;;
        esac
    done
    [ -z "$forti" ] || [ -f "$forti" ] || tm_die "no installer $forti"
    pass-cli info >/dev/null 2>&1 || tm_die "Proton Pass not logged in: pass-cli login"

    virsh_ domstate "$TM_VM_NAME" | grep -q running || virsh_ start "$TM_VM_NAME" >/dev/null
    wait_for_firstlogon
    detach_install_media

    local work
    work="$(mktemp -d)"
    trap 'rm -rf "$work"; tm_ssh "Remove-Item -Recurse -Force $REMOTE_DIR -ErrorAction SilentlyContinue" >/dev/null 2>&1 || true' EXIT
    bash "$TM_REPO/files.sh" get vm/client-cert.p12 "$work/client-cert.p12"
    bash "$TM_REPO/files.sh" get vm/vpn-fed.pem "$work/vpn-fed.pem"
    cp "$TM_REPO/vm/provision.ps1" "$work/"
    [ -z "$forti" ] || { cp "$forti" "$work/"; args+=(-FortiInstaller "$(basename "$forti")"); }

    tm_ssh "New-Item -ItemType Directory -Force $REMOTE_DIR | Out-Null"
    scp -q -o BatchMode=yes "$work"/* "$TM_VM_USER@$TM_VM_IP:C:/ProgramData/tmobile-provision/"

    local output
    output="$(pass-cli item view --vault-name "$TM_PASS_VAULT" --item-title vm/client-cert-password --field password \
        | tm_ssh "powershell -NoProfile -ExecutionPolicy Bypass -File $REMOTE_DIR\\provision.ps1 ${args[*]}")"
    grep -v '^RECOVERY-PASSWORD ' <<<"$output"
    local recovery
    recovery="$(grep '^RECOVERY-PASSWORD ' <<<"$output" | cut -d' ' -f2- || true)"
    [ -z "$recovery" ] || store_recovery "$recovery"
    tm_ok "provisioned. Next, in the VM: FortiClient from https://vpnclientcz.tcko.net/ (unless --forticlient), restart, connect with certificate Identita / vpn-fed"
}

status() {
    echo "VM:      $(virsh_ domstate "$TM_VM_NAME" 2>/dev/null | head -n1 | grep . || echo "not defined")"
    tm_vm_reachable && echo "SSH:     $TM_VM_IP:22 open" || echo "SSH:     $TM_VM_IP:22 closed"
    systemctl --user is-active --quiet tmobile-socks.service && echo "tunnel:  up (socks5://127.0.0.1:$TM_SOCKS_PORT)" || echo "tunnel:  down"
}

case "${1:-}" in
    create) shift; create "$@" ;;
    provision) shift; provision "$@" ;;
    status) status ;;
    console) virt-manager --connect "$TM_LIBVIRT" --show-domain-console "$TM_VM_NAME" ;;
    ssh) shift; tm_ssh "$@" ;;
    *) sed -n '2,10p' "$0"; exit 2 ;;
esac
