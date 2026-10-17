#!/usr/bin/env bash
# Joplin (Flatpak) profile <-> Proton Drive: backup, restore, scheduled backup.
#
#   joplin-proton.sh backup    copy the profile to proton:backup/joplin (safe while Joplin runs)
#   joplin-proton.sh restore   new machine: pull the profile from Proton Drive before the first start
#   joplin-proton.sh enable    install the backup script + daily user timer (what setup-script.sh calls)
#
# Needs the rclone remote "proton" (Proton Drive): rclone config → protondrive, name "proton".
# Credentials are never in this repo; without the remote the script only prints what to do.
set -euo pipefail

PROFILE="$HOME/.config/joplin-desktop"           # the Flatpak writes its profile here, not under ~/.var
JEX_DIR="$HOME/Documents/JoplinBackup"           # Joplin's bundled Backup plugin (JEX), optional
STAGE="$HOME/.local/share/joplin-backup/profile"
REMOTE="proton:backup/joplin"
BIN="$HOME/.local/bin/joplin-proton-backup.sh"
UNIT_DIR="$HOME/.config/systemd/user"

have_remote() { rclone listremotes 2>/dev/null | grep -qx 'proton:'; }
need_remote() {
    have_remote && return 0
    echo "rclone remote 'proton' is missing. Run: rclone config  (type protondrive, name proton), then re-run: $0 $1"
    return 1
}

backup() {
    need_remote backup
    mkdir -p "$STAGE"
    # the profile without caches, locks, logs and Electron internals (--delete-excluded also removes
    # excluded files from the stage, so the database copy below has to come AFTER this step)
    rsync -a --delete --delete-excluded \
        --exclude 'cache/' --exclude 'lock' --exclude 'log*.txt' \
        --exclude 'database.sqlite' --exclude 'database.sqlite-*' \
        --exclude 'JoplinBackup/' --exclude 'internal/' --exclude 'tmp/' \
        "$PROFILE/" "$STAGE/"
    # consistent copy of the database even while Joplin is running
    sqlite3 "$PROFILE/database.sqlite" ".backup '$STAGE/database.sqlite'"
    rclone sync "$STAGE" "$REMOTE/profile" --stats-one-line -v
    [ -d "$JEX_DIR" ] && rclone copy "$JEX_DIR" "$REMOTE/jex" --stats-one-line -v
    echo "joplin backup OK: $(date -Is) -> $REMOTE"
}

restore() {
    need_remote restore
    if [ -f "$PROFILE/database.sqlite" ]; then
        echo "Profile already exists ($PROFILE). Restore only into a fresh profile: close Joplin, move the folder away, re-run."
        return 1
    fi
    pgrep -f joplin-desktop >/dev/null && { echo "Close Joplin first."; return 1; }
    mkdir -p "$PROFILE"
    rclone copy "$REMOTE/profile" "$PROFILE" --stats-one-line -v
    echo "Joplin profile restored from $REMOTE/profile (notes, attachments, settings, plugins). Start Joplin."
    echo "Fallback (JEX): rclone copy $REMOTE/jex $JEX_DIR, then File → Import → JEX."
}

enable() {
    mkdir -p "$(dirname "$BIN")" "$UNIT_DIR"
    # the backup script is this file in 'backup' mode, so there is one copy of the logic
    cp "${BASH_SOURCE[0]}" "$BIN" && chmod +x "$BIN"
    cat > "$UNIT_DIR/joplin-proton-backup.service" <<EOF
[Unit]
Description=Backup Joplin profile to Proton Drive ($REMOTE)
After=network-online.target

[Service]
Type=oneshot
ExecStart=$BIN backup
EOF
    cat > "$UNIT_DIR/joplin-proton-backup.timer" <<'EOF'
[Unit]
Description=Daily Joplin backup to Proton Drive

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now joplin-proton-backup.timer
    echo "Daily Joplin backup enabled: systemctl --user list-timers joplin-proton-backup.timer"
}

case "${1:-}" in
    backup)  backup ;;
    restore) restore ;;
    enable)  enable ;;
    *) echo "usage: $0 backup|restore|enable"; exit 2 ;;
esac
