#!/bin/bash

# Prints the text on the VM's first console over SSH: console.sh <work directory> [console number]

WORK=$1
CONSOLE=${2:-1}
ssh -q -i "$WORK/test-key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 tester@127.0.0.1 \
    "cols=\$(echo tester1234 | sudo -S stty -F /dev/tty$CONSOLE size 2>/dev/null | cut -d' ' -f2); echo tester1234 | sudo -S cat /dev/vcs$CONSOLE 2>/dev/null | fold -b -w \"\$cols\"" | sed 's/ *$//' | grep -a -v '^$'
