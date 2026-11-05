#!/usr/bin/env bash
# T-Mobile files that are not shell variables (CA certificates, kubeconfigs, AWS, Maven settings, VPN client
# certificate) live in the Proton Pass vault $TM_PASS_VAULT, one note per file, so a new machine needs only
# `pass-cli login`. Base64 because notes are text and the .p12 is binary.
#
#   files.sh push [--force]   this machine -> Proton Pass (existing items are kept unless --force)
#   files.sh restore          Proton Pass -> $HOME (existing files are kept)
#   files.sh get TITLE FILE   one item into FILE (used by vm.sh for the vm/ items)
#   files.sh status           which items are in the vault, which files are on disk
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

LIST="$TM_REPO/files.list"
P12_PASSWORD_ITEM="vm/client-cert-password"

command -v pass-cli >/dev/null || tm_die "pass-cli missing (setup-script.sh installs it)"
pass-cli info >/dev/null 2>&1 || tm_die "Proton Pass not logged in: pass-cli login"

entries() { grep -v -E '^\s*(#|$)' "$LIST"; }

vault_titles() {
    { pass-cli item list "$TM_PASS_VAULT" --output json 2>/dev/null || echo '{}'; } | jq -r '.. | .title? // empty'
}

ensure_vault() {
    pass-cli vault list | grep -q "]: $TM_PASS_VAULT\$" || {
        pass-cli vault create --name "$TM_PASS_VAULT" >/dev/null
        tm_ok "vault $TM_PASS_VAULT created"
    }
}

note_of() {
    pass-cli item view --vault-name "$TM_PASS_VAULT" --item-title "$1" --output json | jq -er '.item.content.note'
}

get() {
    local title="$1" out="$2"
    ( umask 077 && note_of "$title" | base64 -d > "$out" )
}

push() {
    local force="${1:-}" titles
    ensure_vault
    titles="$(vault_titles)"
    entries | while read -r title src _; do
        local path="$HOME/$src"
        [ -f "$path" ] || { tm_info "skip $title: no ~/$src"; continue; }
        if grep -qxF "$title" <<<"$titles"; then
            [ "$force" = "--force" ] || { tm_info "keep $title (already in the vault, --force replaces it)"; continue; }
            pass-cli item update --vault-name "$TM_PASS_VAULT" --item-title "$title" --field "note=$(base64 -w0 "$path")" >/dev/null
            tm_ok "updated $title"
        else
            jq -n --arg t "$title" --rawfile n <(base64 -w0 "$path") '{title: $t, note: $n}' \
                | pass-cli item create note --vault-name "$TM_PASS_VAULT" --from-template - >/dev/null
            tm_ok "stored $title"
        fi
    done
    grep -qxF "$P12_PASSWORD_ITEM" <<<"$titles" \
        || tm_info "add a Login item '$P12_PASSWORD_ITEM' to the vault $TM_PASS_VAULT in the Proton Pass app (password = .p12 protection password)"
}

restore() {
    local titles
    titles="$(vault_titles)"
    entries | grep -v '^vm/' | while read -r title target mode; do
        local path="$HOME/$target"
        [ -e "$path" ] && { tm_info "keep ~/$target (exists)"; continue; }
        grep -qxF "$title" <<<"$titles" || { tm_info "skip $title: not in the vault"; continue; }
        mkdir -p "$(dirname "$path")"
        get "$title" "$path"
        chmod "$mode" "$path"
        tm_ok "restored ~/$target"
    done
    # The SK GitLab chain ends in Slovak Telekom Root CA 2, which the system store lacks; the bundle is derived, not stored
    local root="$HOME/.config/tmobile/slovak-telekom-root-ca2.pem"
    [ -f "$root" ] && cat /etc/ssl/certs/ca-certificates.crt "$root" > "$HOME/.config/tmobile/ca-bundle-itc.pem" \
        && tm_ok "built ~/.config/tmobile/ca-bundle-itc.pem"
}

status() {
    local titles
    titles="$(vault_titles)"
    entries | while read -r title target _; do
        local in_vault="-" on_disk="-"
        grep -qxF "$title" <<<"$titles" && in_vault="vault"
        [ -f "$HOME/$target" ] && on_disk="disk"
        printf '%-6s %-5s %s\n' "$in_vault" "$on_disk" "$title"
    done
    grep -qxF "$P12_PASSWORD_ITEM" <<<"$titles" && echo "vault  -     $P12_PASSWORD_ITEM" || echo "-      -     $P12_PASSWORD_ITEM (missing)"
}

case "${1:-}" in
    push) push "${2:-}" ;;
    restore) restore ;;
    get) [ $# -eq 3 ] || tm_die "usage: $0 get TITLE FILE"; get "$2" "$3" ;;
    status) status ;;
    *) echo "usage: $0 push [--force] | restore | get TITLE FILE | status"; exit 2 ;;
esac
