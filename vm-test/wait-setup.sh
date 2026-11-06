#!/bin/bash

# Waits until first-login.sh in the VM finishes or fails, then prints the end of its log: wait-setup.sh <work directory>

WORK=$1
SSH=(ssh -q -i "$WORK/test-key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p 2222 tester@127.0.0.1)

for _ in $(seq 1 360); do
    timeout 30 tail -f /dev/null
    state=$("${SSH[@]}" 'test -e ~/arch-setup/.first-login-done && echo done; pgrep -f first-login.sh >/dev/null || echo gone')
    case "$state" in
        *done*|*gone*) break ;;
    esac
done

echo "state: $state"
"${SSH[@]}" 'tail -40 ~/arch-setup/first-login.log | cut -c1-160'
