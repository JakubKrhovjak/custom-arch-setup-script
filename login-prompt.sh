#!/bin/bash

# Offers the logins that need a browser, once, in the first terminal on the desktop: the setup itself runs on the
# console, where no browser exists. Started from ~/.zshrc while the marker from first-login.sh exists.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -f "$REPO/.login-prompt-pending"

ask() { # question
    local answer
    read -rp "$1 [y/N] " answer
    [[ $answer == [yY]* ]]
}

if command -v pass-cli >/dev/null && ! pass-cli info >/dev/null 2>&1 && ask "Log in to Proton Pass (shell secrets)?"; then
    pass-cli login && secrets-sync
fi

if command -v gh >/dev/null && ! gh auth status >/dev/null 2>&1 && ask "Log in to GitHub?"; then
    gh auth login
fi

exit 0
