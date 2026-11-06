#!/bin/bash

# The session greetd starts for Desk: finishes the setup at the first login, then starts the desktop.
# When the setup fails, the login screen comes back and the next login tries again.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DONE="$REPO/.first-login-done"

if [ ! -e "$DONE" ]; then
    bash "$REPO/first-login.sh"
    [ -e "$DONE" ] || exit 1
fi

exec "$HOME/.config/desk/start.sh"
