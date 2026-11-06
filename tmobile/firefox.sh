#!/usr/bin/env bash
# Firefox for T-Mobile, on top of the base hardening from dotfiles-install.sh:
#  - proxy.pac: internal hosts through the VPN tunnel, the rest direct (policy, so every profile gets it)
#  - User-Agent String Switcher reports Windows on T-Mobile/Telekom sites, whose access checks reject Linux
# Merged into /etc/firefox/policies/policies.json; dotfiles-install.sh overwrites that file, so run this again after it.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

PAC="$HOME/.config/tmobile/proxy.pac"
POLICIES=/etc/firefox/policies/policies.json

mkdir -p "$(dirname "$PAC")"
sed "s|@SOCKS_PORT@|$TM_SOCKS_PORT|g" "$TM_REPO/firefox/proxy.pac" > "$PAC"
tm_ok "PAC file $PAC"

[ -f "$POLICIES" ] || tm_die "$POLICIES missing: run dotfiles-install.sh first"
merged="$(jq -s '.[0] * .[1]' "$POLICIES" <(sed "s|@PAC@|$PAC|g" "$TM_REPO/firefox/policies-tmobile.json"))"
printf '%s\n' "$merged" | sudo tee "$POLICIES" >/dev/null
tm_ok "Firefox policies: PAC proxy + Windows User-Agent for T-Mobile sites (restart Firefox, check about:policies)"

# A user.js from the hand-made setup would keep overriding the policy; it set the same proxy, so it can go
find "$HOME/.mozilla/firefox" -maxdepth 2 -name user.js -exec grep -l 'tmobile/proxy.pac' {} + 2>/dev/null \
    | while read -r js; do tm_info "the proxy lines in $js are now redundant (policy), remove them when convenient"; done
