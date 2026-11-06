# Secrets: Proton Pass vault "env-secrets" → Secret Service (secrets-sync) → environment.
# No values here: each Secret Service entry with service=env-secrets is exported under its label
# (= the item title in Proton Pass, e.g. GITLAB_TOKEN). After changing the vault, run: secrets-sync
# The vault also holds private non-secret config (hosts, project IDs). secrets-sync.timer refreshes it every 15 min.
command -v secret-tool >/dev/null && () {
    local line name=
    for line in "${(@f)$(secret-tool search --all --unlock service env-secrets 2>/dev/null)}"; do
        case $line in
            'label = '*)  name=${line#label = } ;;
            'secret = '*) [[ $name =~ '^[A-Z_][A-Z0-9_]*$' ]] && export "$name=${line#secret = }"; name= ;;
        esac
    done
}
