#!/bin/bash

# Copies the current working trees, uncommitted changes included, into bare repositories for the VM test.
# The real repositories keep their branches, index and working tree; only unreferenced objects get added.
# Usage: snapshot.sh <directory with the bare repositories> [extra local.env line...]

set -euo pipefail

BASE=$1
shift
SETUP_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAELESTIA="$HOME/.config/quickshell/caelestia"
mkdir -p "$BASE"

bare() { # name
    [ -d "$BASE/$1.git" ] || env -u GIT_DIR -u GIT_WORK_TREE git init -q --bare "$BASE/$1.git"
    echo "$BASE/$1.git"
}

snapshot() { # git command prefix as a string is avoided: uses GIT_DIR and GIT_WORK_TREE from the caller
    local index
    index=$(mktemp -u)
    GIT_INDEX_FILE=$index git read-tree HEAD
    GIT_INDEX_FILE=$index git add -A
    for entry in "$@"; do
        GIT_INDEX_FILE=$index git update-index --add --cacheinfo "$entry"
    done
    local tree
    tree=$(GIT_INDEX_FILE=$index git write-tree)
    rm -f "$index"
    git commit-tree "$tree" -p HEAD -m "VM test snapshot"
}

# Caelestia first: the desk snapshot points to its commit
export GIT_DIR GIT_WORK_TREE
GIT_DIR=$(git -C "$CAELESTIA" rev-parse --absolute-git-dir)
GIT_WORK_TREE=$CAELESTIA
caelestia_commit=$(snapshot)
target=$(bare caelestia-shell)
git push -q -f "$target" "$caelestia_commit:refs/heads/master" refs/heads/upstream:refs/heads/upstream

GIT_DIR=$HOME/.local/share/desk.git
GIT_WORK_TREE=$HOME/.config
desk_commit=$(snapshot "160000,$caelestia_commit,quickshell/caelestia")
target=$(bare desk)
git push -q -f "$target" "$desk_commit:refs/heads/main"

GIT_DIR=$SETUP_REPO/.git
GIT_WORK_TREE=$SETUP_REPO
env_blob=$(printf 'export %s\n' "$@" | git hash-object -w --stdin)
setup_commit=$(snapshot "100644,$env_blob,local.env")
target=$(bare custom-arch-setup-script)
git push -q -f "$target" "$setup_commit:refs/heads/main"
git --git-dir="$target" symbolic-ref HEAD refs/heads/main
git --git-dir="$BASE/desk.git" symbolic-ref HEAD refs/heads/main
git --git-dir="$BASE/caelestia-shell.git" symbolic-ref HEAD refs/heads/master

echo "snapshots: caelestia $caelestia_commit, desk $desk_commit, setup $setup_commit"
