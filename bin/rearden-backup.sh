#!/usr/bin/env bash

set -euo pipefail

# Optional: Colors for nicer output
INFO="\033[1;34m[INFO]\033[0m"
WARN="\033[1;33m[WARN]\033[0m"
ERROR="\033[1;31m[ERROR]\033[0m"

export INIT_SCRIPT="${INIT_SCRIPT:-init.sh}"

load_init_script() {
    if [[ -f "$INIT_SCRIPT" ]]; then
        echo -e "$INFO Loading ${INIT_SCRIPT}"
        source "$INIT_SCRIPT"
    else
        echo -e "$WARN ${INIT_SCRIPT} not found. Skipping."
    fi
}

check_requirements() {
    for cmd in restic rclone; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "$ERROR $cmd is not installed. Please install it."
            exit 1
        fi
    done
}

validate_config() {
    if [[ -z "${CONFIG_DIR:-}" ]]; then
        echo -e "$ERROR CONFIG_DIR is not set. Please define it in the environment or in init.sh."
        exit 1
    fi

    if [[ -z "${BACKUP_DIRECTORIES:-}" ]]; then
        echo -e "$ERROR BACKUP_DIRECTORIES is not set. Define it in init.sh."
        exit 1
    fi

    export RCLONE_CONFIG="${RCLONE_CONFIG:-${CONFIG_DIR}/rclone.conf}"
}

set_defaults() {
    BACKUP_DIR="${BACKUP_DIR:-backup}"
    LOCAL_BACKUP_REPO="${LOCAL_BACKUP_REPO:-${BACKUP_DIR}/local}"
    RCLONE_REMOTE="${RCLONE_REMOTE:-remote:backup}"

    ENABLE_BACKUP="${ENABLE_BACKUP:-1}"
    ENABLE_RESTORE="${ENABLE_RESTORE:-1}"
    ENABLE_PUSH="${ENABLE_PUSH:-1}"
    ENABLE_PULL="${ENABLE_PULL:-1}"
}

print_config() {
    echo -e "$INFO Current Configuration:"
    cat <<EOF
  CONFIG_DIR:         $CONFIG_DIR
  BACKUP_DIR:         $BACKUP_DIR
  LOCAL_BACKUP_REPO:  $LOCAL_BACKUP_REPO
  RCLONE_REMOTE:      $RCLONE_REMOTE
  BACKUP_DIRECTORIES: $BACKUP_DIRECTORIES

  ENABLE_BACKUP:      $ENABLE_BACKUP
  ENABLE_RESTORE:     $ENABLE_RESTORE
  ENABLE_PUSH:        $ENABLE_PUSH
  ENABLE_PULL:        $ENABLE_PULL
EOF
}

initialize_repo() {
    if ! restic -r "$LOCAL_BACKUP_REPO/restic" snapshots &>/dev/null; then
        echo -e "$INFO Initializing restic repository at $LOCAL_BACKUP_REPO/restic"
        restic -r "$LOCAL_BACKUP_REPO/restic" init
    fi
}

backup() {
    if [[ "$ENABLE_BACKUP" -eq 1 ]]; then
        echo -e "$INFO Starting backup..."
        initialize_repo
        restic -r "$LOCAL_BACKUP_REPO/restic" backup $BACKUP_DIRECTORIES \
            --exclude '**/mount/**' --exclude '**/.cache/restic/**'
        echo -e "$INFO Backup completed."
    else
        echo -e "$WARN Backup step is disabled."
    fi
}

restore() {
    if [[ "$ENABLE_RESTORE" -eq 1 ]]; then
        echo -e "$INFO Starting restore..."
        restic -r "$LOCAL_BACKUP_REPO/restic" restore latest --target "/"
        echo -e "$INFO Restore completed."
    else
        echo -e "$WARN Restore step is disabled."
    fi
}

push() {
    if [[ "$ENABLE_PUSH" -eq 1 ]]; then
        echo -e "$INFO Uploading backup to remote..."
        rclone sync -P "$LOCAL_BACKUP_REPO" "$RCLONE_REMOTE"
        echo -e "$INFO Upload completed."
    else
        echo -e "$WARN Push step is disabled."
    fi
}

pull() {
    if [[ "$ENABLE_PULL" -eq 1 ]]; then
        echo -e "$INFO Downloading backup from remote..."
        rclone sync -P "$RCLONE_REMOTE" "$LOCAL_BACKUP_REPO"
        echo -e "$INFO Download completed."
    else
        echo -e "$WARN Pull step is disabled."
    fi
}

main() {
    load_init_script
    check_requirements
    validate_config
    set_defaults
    print_config

    case "${1:-}" in
        backup) backup ;;
        restore) restore ;;
        push) push ;;
        pull) pull ;;
        *)
            echo -e "$ERROR Invalid command."
            echo "Usage: $0 {backup|restore|push|pull}"
            exit 1
            ;;
    esac
}

main "$@"
