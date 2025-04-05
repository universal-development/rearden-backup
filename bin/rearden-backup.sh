#!/bin/env bash

export INIT_SCRIPT=${INIT_SCRIPT:-init.sh}

if [[ -f $INIT_SCRIPT ]]; then
    echo "Loading ${INIT_SCRIPT}"
    source "${INIT_SCRIPT}"
else
    echo "${INIT_SCRIPT} not found. Skipping."
fi

# Check if RESTIC and RCLONE are installed
if ! command -v restic &> /dev/null; then
    echo "Restic could not be found, please install it."
    exit 1
fi

if ! command -v rclone &> /dev/null; then
    echo "Rclone could not be found, please install it."
    exit 1
fi

if [[ -z "${CONFIG_DIR}" ]]; then
    echo "CONFIG_DIR is not set. Please define it via environment or in init.sh."
    exit 1
fi

# Ensure backup directories are defined
if [ -z "$BACKUP_DIRECTORIES" ]; then
    echo "No backup directories specified. Please set BACKUP_DIRECTORIES in init.sh"
    exit 1
fi

BACKUP_DIR=${BACKUP_DIR:-backup}
LOCAL_BACKUP_REPO=${LOCAL_BACKUP_REPO:-${BACKUP_DIR}/local}
RCLONE_REMOTE=${RCLONE_REMOTE:-remote:backup}

# Ensure Restic and Rclone configs are available
export RCLONE_CONFIG=${RCLONE_CONFIG:-${CONFIG_DIR}/rclone.conf}

# Steps control variables (set to 0 to disable a step)
ENABLE_BACKUP=${ENABLE_BACKUP:-1}
ENABLE_RESTORE=${ENABLE_RESTORE:-1}
ENABLE_PUSH=${ENABLE_PUSH:-1}
ENABLE_PULL=${ENABLE_PULL:-1}

# print the configuration
echo "Configuration:"
echo "  CONFIG_DIR: $CONFIG_DIR"
echo "  BACKUP_DIR: $BACKUP_DIR"
echo "  LOCAL_BACKUP_REPO: $LOCAL_BACKUP_REPO"
echo "  RCLONE_REMOTE: $RCLONE_REMOTE"
echo "  BACKUP_DIRECTORIES: $BACKUP_DIRECTORIES"
echo
echo "  ENABLE_BACKUP: $ENABLE_BACKUP"
echo "  ENABLE_RESTORE: $ENABLE_RESTORE"
echo "  ENABLE_PUSH: $ENABLE_PUSH"
echo "  ENABLE_PULL: $ENABLE_PULL"



# Function to perform backup
backup() {
    if [ "$ENABLE_BACKUP" -eq 1 ]; then
        echo "Starting backup..."

        echo "Backing up directory: $BACKUP_DIRECTORIES"
        restic -r "$LOCAL_BACKUP_REPO/restic" backup $BACKUP_DIRECTORIES --exclude '**/mount/**' --exclude '**/.cache/restic/**'

        echo "Backup completed."
    else
        echo "Backup step is disabled."
    fi
}

# Function to restore directories
restore() {
    if [ "$ENABLE_RESTORE" -eq 1 ]; then
        echo "Starting restore..."

        echo "Restoring directory: $DIR"
        restic -r "$LOCAL_BACKUP_REPO/restic" restore latest --target "/"
        echo "Restore completed."
    else
        echo "Restore step is disabled."
    fi
}

# Function to upload backup to remote storage
push() {
    if [ "$ENABLE_PUSH" -eq 1 ]; then
        echo "Uploading backup to remote storage..."
        rclone sync -P "$LOCAL_BACKUP_REPO" "$RCLONE_REMOTE"
        echo "Upload completed."
    else
        echo "Push step is disabled."
    fi
}

# Function to download backup from remote storage
pull() {
    if [ "$ENABLE_PULL" -eq 1 ]; then
        echo "Downloading backup from remote storage..."
        rclone sync -P "$RCLONE_REMOTE" "$LOCAL_BACKUP_REPO"
        echo "Download completed."
    else
        echo "Pull step is disabled."
    fi
}

# Main script logic
case "$1" in
    backup)
        backup
        ;;
    restore)
        restore
        ;;
    push)
        push
        ;;
    pull)
        pull
        ;;
    *)
        echo "Usage: $0 {backup|restore|push|pull}"
        exit 1
        ;;
esac
