#!/usr/bin/env bash
# Optional T-Mobile CZ (GPC) work setup; not part of first-login.sh. Run as your user after setup-script.sh
# and `pass-cli login`. Each step is its own script and can run alone; all are safe to repeat.
#
#   bash tmobile/setup.sh                    host side: tunnel units, Firefox, app environment
#   bash tmobile/setup.sh --vm-iso Win11.iso also create the VPN VM (unattended Windows install)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

ISO=""
[ "${1:-}" = "--vm-iso" ] && ISO="${2:-}"

[ "$(id -u)" -ne 0 ] || tm_die "run as your user, not root"
pass-cli info >/dev/null 2>&1 || tm_die "Proton Pass not logged in: pass-cli login (vault $TM_PASS_VAULT holds the certificates)"

for step in tunnel.sh firefox.sh apps.sh; do
    echo; echo "════════ tmobile/$step ════════"
    bash "$TM_REPO/$step"
done

if [ -n "$ISO" ]; then
    echo; echo "════════ tmobile/vm.sh create ════════"
    bash "$TM_REPO/vm.sh" create --iso "$ISO"
fi

echo
tm_ok "host side done. Remaining (see tmobile/README.md):"
[ -n "$ISO" ] || echo "  1. bash $TM_REPO/vm.sh create --iso ~/Downloads/Win11.iso"
echo "  2. bash $TM_REPO/vm.sh provision            # certificates, BitLocker; again after FortiClient for the MTU"
echo "  3. in the VM: FortiClient from https://vpnclientcz.tcko.net/, restart, connect (certificate Identita / vpn-fed)"
echo "  4. bash $TM_REPO/apps.sh --clone            # repos, once the tunnel is up"
