#!/usr/bin/env bash

# Enhanced backup script that relies entirely on CONFIG_DIR from init.sh
# Features:
# - Self-contained within CONFIG_DIR
# - Improved error reporting and handling
# - Backup retention policy
# - Dry-run capability
# - Backup verification
# - Lock mechanism to prevent concurrent runs
# - Comprehensive logging
# - Support for configuration profiles
# - Push/Pull of entire CONFIG_DIR, not just restic repo
# - Support for predefined remote RESTIC_REPOSITORY

set -euo pipefail

# Colors for nicer output
readonly RESET="\033[0m"
readonly INFO="\033[1;34m[INFO]\033[0m"
readonly WARN="\033[1;33m[WARN]\033[0m"
readonly ERROR="\033[1;31m[ERROR]\033[0m"
readonly SUCCESS="\033[1;32m[SUCCESS]\033[0m"

# Script variables
readonly SCRIPT_NAME=$(basename "$0")

# First, we need to load init.sh to get CONFIG_DIR
# Default location is in the same directory as the script
export INIT_SCRIPT="${INIT_SCRIPT:-init.sh}"

# Basic logging functions before we set up proper logging
echo_log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $INFO $1"
}

echo_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $ERROR $1" >&2
}

# Load init.sh first to get CONFIG_DIR
pre_load_init() {
    if [[ ! -f "$INIT_SCRIPT" ]]; then
        echo_error "${INIT_SCRIPT} not found. This file is required."
        echo_error "Please create init.sh with your backup configuration."
        exit 1
    fi

    echo_log "Pre-loading ${INIT_SCRIPT} to get CONFIG_DIR"
    source "$INIT_SCRIPT"

    # Ensure CONFIG_DIR is set
    if [[ -z "${CONFIG_DIR:-}" ]]; then
        echo_error "CONFIG_DIR is not defined in ${INIT_SCRIPT}."
        echo_error "Please define CONFIG_DIR in your init.sh file."
        exit 1
    fi

    echo_log "Using CONFIG_DIR: ${CONFIG_DIR}"
}

# Load init.sh to get CONFIG_DIR
pre_load_init

# Now we can define all paths based on CONFIG_DIR
readonly LOCK_FILE="${CONFIG_DIR}/locks/${SCRIPT_NAME}.lock"
readonly LOG_DIR="${CONFIG_DIR}/logs"
readonly LOG_FILE="${LOG_DIR}/backup-$(date +%Y%m%d-%H%M%S).log"
readonly BACKUP_DIR="${CONFIG_DIR}/backups"
readonly MAX_LOG_FILES="${MAX_LOG_FILES:-10}"

# Default variables - will be overridden by init.sh when fully loaded
PROFILE="${PROFILE:-default}"
LOCAL_BACKUP_REPO=""
RCLONE_REMOTE=""
BACKUP_DIRECTORIES=""
DRY_RUN="${DRY_RUN:-0}"
RETENTION_DAYS="${RETENTION_DAYS:-0}"
VERIFY_BACKUP="${VERIFY_BACKUP:-1}"
ENABLE_BACKUP="1"
ENABLE_RESTORE="1"
ENABLE_PUSH="1"
ENABLE_PULL="1"
VERBOSE="${VERBOSE:-0}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
USE_REMOTE_REPO="0"

# Handle script exit
cleanup() {
    # Remove lock file when script exits
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log "Removed lock file"
    fi
}

trap cleanup EXIT

# Create config directory structure
create_config_structure() {
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${CONFIG_DIR}/locks"
    mkdir -p "${CONFIG_DIR}/logs"
    mkdir -p "${CONFIG_DIR}/backups"
    mkdir -p "${CONFIG_DIR}/profiles"

    log "Created config directory structure in ${CONFIG_DIR}"

    # Create a sample exclude file if it doesn't exist
    if [[ ! -f "${CONFIG_DIR}/exclude.txt" ]]; then
        cat > "${CONFIG_DIR}/exclude.txt" <<EOF
# Patterns to exclude from backup
**/.DS_Store
**/node_modules
**/.git
**/*.log
**/tmp
**/temp
**/.cache
EOF
        log "Created sample exclude.txt file in ${CONFIG_DIR}/exclude.txt"
    fi
}

# Check if another instance is running
check_lock() {
    # Ensure lock directory exists
    mkdir -p "$(dirname "$LOCK_FILE")"

    if [[ -f "$LOCK_FILE" ]]; then
        pid=$(cat "$LOCK_FILE")
        if ps -p "$pid" > /dev/null; then
            log_error "Another instance is already running with PID $pid"
            exit 1
        else
            log_warn "Found stale lock file. Previous process may have crashed."
            rm -f "$LOCK_FILE"
        fi
    fi

    # Create lock file
    echo $$ > "$LOCK_FILE"
    log "Created lock file with PID $$"
}

# Logging functions
setup_logging() {
    # Create log directory if it doesn't exist
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
    fi

    # Rotate logs if there are more than MAX_LOG_FILES
    local log_count=$(ls -1 "${LOG_DIR}"/*.log 2>/dev/null | wc -l || echo "0")
    if [[ "$log_count" -gt "$MAX_LOG_FILES" ]]; then
        log_warn "Rotating logs, removing oldest files"
        ls -1t "${LOG_DIR}"/*.log | tail -n +$((MAX_LOG_FILES+1)) | xargs rm -f
    fi

    # Start logging
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "Started logging to $LOG_FILE"
}

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $INFO $1"
}

log_warn() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $WARN $1"
}

log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $ERROR $1"
}

log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $SUCCESS $1"
}

load_init_script() {
    log "Fully loading ${INIT_SCRIPT}"
    source "$INIT_SCRIPT"

    # Load profile-specific config if it exists
    local profile_config="${CONFIG_DIR}/profiles/${PROFILE}.sh"
    if [[ -f "$profile_config" ]]; then
        log "Loading profile: $PROFILE from $profile_config"
        source "$profile_config"
    fi
}

check_requirements() {
    local missing_tools=0

    for cmd in restic rclone; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is not installed. Please install it."
            missing_tools=1
        else
            local version
            if [[ "$cmd" == "restic" ]]; then
                version=$(restic version | head -n1)
            else
                version=$(rclone --version | head -n1)
            fi
            log "Found $version"
        fi
    done

    if [[ "$missing_tools" -eq 1 ]]; then
        exit 1
    fi
}

validate_config() {
    # Configuration validation
    if [[ -z "${BACKUP_DIRECTORIES:-}" ]]; then
        log_error "BACKUP_DIRECTORIES is not set. Define it in init.sh or profile config."
        exit 1
    fi

    # Make sure the directories to back up exist
    local missing_dirs=0
    for dir in $BACKUP_DIRECTORIES; do
        if [[ ! -d "$dir" ]]; then
            log_error "Backup directory does not exist: $dir"
            missing_dirs=1
        fi
    done

    if [[ "$missing_dirs" -eq 1 ]]; then
        exit 1
    fi

    # Set rclone config
    export RCLONE_CONFIG="${RCLONE_CONFIG:-${CONFIG_DIR}/rclone.conf}"
    if [[ ! -f "$RCLONE_CONFIG" && "$ENABLE_PUSH" -eq 1 ]]; then
        log_warn "Rclone config not found at $RCLONE_CONFIG. Remote operations may fail."
    fi

    # Check RESTIC_REPOSITORY configuration
    if [[ -n "$RESTIC_REPOSITORY" ]]; then
        USE_REMOTE_REPO="1"
        log "Using direct remote repository: $RESTIC_REPOSITORY"

        # Check if additional environment variables are needed for the repository type
        if [[ "$RESTIC_REPOSITORY" == *"s3:"* && -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
            log_warn "S3 repository detected but AWS_ACCESS_KEY_ID is not set"
        elif [[ "$RESTIC_REPOSITORY" == *"sftp:"* && -z "${RESTIC_SFTP_COMMAND:-}" ]]; then
            log_warn "SFTP repository detected but RESTIC_SFTP_COMMAND might be needed"
        elif [[ "$RESTIC_REPOSITORY" == *"rest:"* && -z "${RESTIC_REST_USERNAME:-}" ]]; then
            log_warn "REST repository detected but RESTIC_REST_USERNAME might be needed"
        fi
    else
        USE_REMOTE_REPO="0"
    fi

    # Validate restic environment variables
    if [[ -z "${RESTIC_PASSWORD:-}" && -z "${RESTIC_PASSWORD_FILE:-}" ]]; then
        # Try to find a password file in the config directory
        if [[ -f "${CONFIG_DIR}/restic-password.txt" ]]; then
            export RESTIC_PASSWORD_FILE="${CONFIG_DIR}/restic-password.txt"
            log "Using password file: $RESTIC_PASSWORD_FILE"
        else
            log_error "RESTIC_PASSWORD or RESTIC_PASSWORD_FILE must be set for restic to work."
            exit 1
        fi
    fi
}

set_defaults() {
    # All paths are derived from CONFIG_DIR now
    LOCAL_BACKUP_REPO="${LOCAL_BACKUP_REPO:-${BACKUP_DIR}/${PROFILE}}"
    RCLONE_REMOTE="${RCLONE_REMOTE:-remote:backup}"

    # Create local backup repo if it doesn't exist and we're not using a remote repo
    if [[ "$USE_REMOTE_REPO" -eq 0 && ! -d "$LOCAL_BACKUP_REPO/restic" ]]; then
        mkdir -p "$LOCAL_BACKUP_REPO/restic"
        log "Created local backup repository: $LOCAL_BACKUP_REPO/restic"
    fi

    ENABLE_BACKUP="${ENABLE_BACKUP:-1}"
    ENABLE_RESTORE="${ENABLE_RESTORE:-1}"
    ENABLE_PUSH="${ENABLE_PUSH:-1}"
    ENABLE_PULL="${ENABLE_PULL:-1}"

    # Disable push/pull if using a remote repository directly
    if [[ "$USE_REMOTE_REPO" -eq 1 ]]; then
        # Only warn if they were explicitly enabled
        if [[ "$ENABLE_PUSH" -eq 1 || "$ENABLE_PULL" -eq 1 ]]; then
            log_warn "Push/Pull operations are disabled when using a direct remote repository."
        fi
        ENABLE_PUSH=0
        ENABLE_PULL=0
    fi
}

print_config() {
    log "Current Configuration:"
    cat <<EOF
  CONFIG_DIR:         $CONFIG_DIR
  PROFILE:            $PROFILE
EOF

    if [[ "$USE_REMOTE_REPO" -eq 1 ]]; then
        cat <<EOF
  RESTIC_REPOSITORY:  $RESTIC_REPOSITORY
  USE_REMOTE_REPO:    Yes
EOF
    else
        cat <<EOF
  LOCAL_BACKUP_REPO:  $LOCAL_BACKUP_REPO
  RCLONE_REMOTE:      $RCLONE_REMOTE
  USE_REMOTE_REPO:    No
EOF
    fi

    cat <<EOF
  BACKUP_DIRECTORIES: $BACKUP_DIRECTORIES
  DRY_RUN:            $DRY_RUN
  RETENTION_DAYS:     $RETENTION_DAYS
  VERIFY_BACKUP:      $VERIFY_BACKUP

  ENABLE_BACKUP:      $ENABLE_BACKUP
  ENABLE_RESTORE:     $ENABLE_RESTORE
  ENABLE_PUSH:        $ENABLE_PUSH
  ENABLE_PULL:        $ENABLE_PULL

  LOG_FILE:           $LOG_FILE
  RCLONE_CONFIG:      $RCLONE_CONFIG
EOF
}

# Helper function to get the repository path for restic commands
get_repo_path() {
    if [[ "$USE_REMOTE_REPO" -eq 1 ]]; then
        echo "$RESTIC_REPOSITORY"
    else
        echo "$LOCAL_BACKUP_REPO/restic"
    fi
}

# Helper function to build restic command with proper repository flag
# FIX: Removed the quotes within the command string
build_restic_command() {
    local base_cmd="restic"

    # Add repository flag if using local repository
    if [[ "$USE_REMOTE_REPO" -eq 0 ]]; then
        local repo_path=$(get_repo_path)
        base_cmd+=" -r $repo_path"  # Removed the quotes that were causing the issue
    fi

    echo "$base_cmd"
}

restic_init() {
    local repo_path=$(get_repo_path)
    log "Checking if Restic repository is initialized at $repo_path..."

    local restic_cmd=$(build_restic_command)

    if $restic_cmd snapshots &>/dev/null; then
        log "Restic repository already initialized."
    else
        log "Initializing Restic repository at $repo_path"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "DRY-RUN: Would initialize repository"
        else
            $restic_cmd init
            if [[ "$?" -eq 0 ]]; then
                log_success "Repository initialized successfully."
            else
                log_error "Repository initialization failed!"
                return 1
            fi
        fi
    fi
}

backup() {
    if [[ "$ENABLE_BACKUP" -eq 1 ]]; then
        local repo_path=$(get_repo_path)
        log "Starting backup to repository: $repo_path"

        # Build our exclude list
        local exclude_opts="--exclude '**/mount/**' --exclude '**/.cache/restic/**'"

        # Check for additional exclude file
        if [[ -f "${CONFIG_DIR}/exclude.txt" ]]; then
            exclude_opts+=" --exclude-file=${CONFIG_DIR}/exclude.txt"
            log "Using exclude file: ${CONFIG_DIR}/exclude.txt"
        fi

        # Build the base restic command with repo flag
        local restic_cmd=$(build_restic_command)

        # Build the complete backup command
        local cmd="$restic_cmd backup $BACKUP_DIRECTORIES $exclude_opts"

        if [[ "$VERBOSE" -eq 1 ]]; then
            cmd+=" -v"
        fi

        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "DRY-RUN: Would execute: $cmd"
        else
            log "Executing: $cmd"
            eval "$cmd"

            if [[ "$?" -eq 0 ]]; then
                log_success "Backup completed successfully."

                # Apply retention policy
                apply_retention_policy

                # Verify backup if enabled
                if [[ "$VERIFY_BACKUP" -eq 1 ]]; then
                    verify_backup
                fi
            else
                log_error "Backup failed!"
                return 1
            fi
        fi
    else
        log_warn "Backup step is disabled."
    fi
}

apply_retention_policy() {
    if [[ "$RETENTION_DAYS" -gt 0 ]]; then
        local restic_cmd=$(build_restic_command)
        log "Applying retention policy: keeping backups for $RETENTION_DAYS days"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "DRY-RUN: Would remove snapshots older than $RETENTION_DAYS days"
        else
            $restic_cmd forget --keep-within "${RETENTION_DAYS}d" --prune
            if [[ "$?" -eq 0 ]]; then
                log_success "Retention policy applied successfully."
            else
                log_error "Failed to apply retention policy!"
                return 1
            fi
        fi
    else
        log "Retention policy disabled (RETENTION_DAYS=$RETENTION_DAYS)"
    fi
}

verify_backup() {
    local restic_cmd=$(build_restic_command)
    log "Verifying backup integrity..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "DRY-RUN: Would verify the backup"
    else
        $restic_cmd check
        if [[ "$?" -eq 0 ]]; then
            log_success "Backup verification completed successfully."
        else
            log_error "Backup verification failed! The repository may be corrupted."
            return 1
        fi
    fi
}

restore() {
    if [[ "$ENABLE_RESTORE" -eq 1 ]]; then
        local target="${1:-/}"
        local snapshot="${2:-latest}"
        local repo_path=$(get_repo_path)
        local restic_cmd=$(build_restic_command)

        log "Starting restore of snapshot $snapshot from $repo_path to target $target..."

        # Confirm with the user if not a dry run
        if [[ "$DRY_RUN" -ne 1 ]]; then
            read -p "This will restore files to $target. Are you sure? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_warn "Restore cancelled by user."
                return 1
            fi
        fi

        local cmd="$restic_cmd restore $snapshot --target \"$target\""

        if [[ "$VERBOSE" -eq 1 ]]; then
            cmd+=" -v"
        fi

        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "DRY-RUN: Would execute: $cmd"
        else
            log "Executing: $cmd"
            eval "$cmd"

            if [[ "$?" -eq 0 ]]; then
                log_success "Restore completed successfully to $target."
            else
                log_error "Restore failed!"
                return 1
            fi
        fi
    else
        log_warn "Restore step is disabled."
    fi
}

push() {
    if [[ "$ENABLE_PUSH" -eq 1 ]]; then
        log "Uploading entire CONFIG_DIR to remote: $RCLONE_REMOTE"

        local cmd="rclone sync"

        if [[ "$VERBOSE" -eq 1 ]]; then
            cmd+=" -v"
        else
            cmd+=" -P"  # Progress but not verbose
        fi

        # Exclude the current log file to avoid syncing issues
        local log_file_basename
        log_file_basename=$(basename "$LOG_FILE")
        cmd+=" --exclude logs/$log_file_basename"

        # Sync the entire CONFIG_DIR except the current log
        cmd+=" \"$CONFIG_DIR\" \"$RCLONE_REMOTE/${PROFILE}\""

        if [[ "$DRY_RUN" -eq 1 ]]; then
            cmd+=" --dry-run"
            log "DRY-RUN: $cmd"
        fi

        log "Executing: $cmd"
        eval "$cmd"

        if [[ "$?" -eq 0 && "$DRY_RUN" -ne 1 ]]; then
            log_success "Upload of CONFIG_DIR to remote completed successfully."
        elif [[ "$DRY_RUN" -ne 1 ]]; then
            log_error "Upload to remote failed!"
            return 1
        fi
    else
        log_warn "Push step is disabled."
    fi
}

pull() {
    if [[ "$ENABLE_PULL" -eq 1 ]]; then
        log "Downloading entire CONFIG_DIR from remote: $RCLONE_REMOTE"

        local cmd="rclone sync"

        if [[ "$VERBOSE" -eq 1 ]]; then
            cmd+=" -v"
        else
            cmd+=" -P"  # Progress but not verbose
        fi

        # Sync from the remote to the entire CONFIG_DIR
        cmd+=" \"$RCLONE_REMOTE/${PROFILE}\" \"$CONFIG_DIR\""

        if [[ "$DRY_RUN" -eq 1 ]]; then
            cmd+=" --dry-run"
            log "DRY-RUN: $cmd"
        fi

        log "Executing: $cmd"
        eval "$cmd"

        if [[ "$?" -eq 0 && "$DRY_RUN" -ne 1 ]]; then
            log_success "Download of CONFIG_DIR from remote completed successfully."
        elif [[ "$DRY_RUN" -ne 1 ]]; then
            log_error "Download from remote failed!"
            return 1
        fi
    else
        log_warn "Pull step is disabled."
    fi
}

list_snapshots() {
    local restic_cmd=$(build_restic_command)
    log "Listing snapshots in repository:"
    $restic_cmd snapshots
}

# Show backup stats and summary
show_stats() {
    local restic_cmd=$(build_restic_command)
    log "Generating backup statistics:"
    $restic_cmd stats

    log "Summary of latest snapshots:"
    $restic_cmd snapshots --latest 5
}

# Export backup info to a file
export_info() {
    local export_file="${CONFIG_DIR}/backup-info.txt"
    local repo_path=$(get_repo_path)
    local restic_cmd=$(build_restic_command)

    log "Exporting backup information to $export_file"

    {
        echo "===== Backup Information ====="
        echo "Date: $(date)"
        echo "Profile: $PROFILE"
        echo "Repository: $repo_path"
        echo ""
        echo "===== Snapshots ====="
        $restic_cmd snapshots
        echo ""
        echo "===== Statistics ====="
        $restic_cmd stats
    } > "$export_file"

    log_success "Exported backup information to $export_file"
}

# Display a template for init.sh file
print_init_template() {
    cat <<EOF
#!/bin/bash
# Configuration for backup script

# Required: Set the configuration directory
CONFIG_DIR="/path/to/config/directory"

# Directories to backup (space-separated)
BACKUP_DIRECTORIES="/home/user/documents /etc"

# Remote repository configuration - two options:

# Option 1: Use a local repo with rclone for remote sync
LOCAL_BACKUP_REPO="\${CONFIG_DIR}/backups/default"
RCLONE_REMOTE="remote:backup"

# Option 2: Use a remote repository directly
# RESTIC_REPOSITORY="s3:s3.amazonaws.com/my-bucket/restic"
# AWS_ACCESS_KEY_ID="your-access-key"
# AWS_SECRET_ACCESS_KEY="your-secret-key"

# Backup retention (days)
RETENTION_DAYS=30

# Optional: Password for restic repository
# RESTIC_PASSWORD="your-secure-password"
# Or use a password file (recommended)
# RESTIC_PASSWORD_FILE="\${CONFIG_DIR}/restic-password.txt"

# Enable/disable features (1=enabled, 0=disabled)
ENABLE_BACKUP=1
ENABLE_RESTORE=1
ENABLE_PUSH=1
ENABLE_PULL=1
EOF
}

# Usage information
print_usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options] [command]

Backup script with restic and rclone integration.
All files are stored within CONFIG_DIR defined in init.sh.

Commands:
  init           Initialize restic repository
  backup         Create a new backup
  restore [path] [snapshot]
                 Restore from backup (defaults to latest snapshot and / path)
  push           Upload entire CONFIG_DIR to remote storage
  pull           Download entire CONFIG_DIR from remote storage
  list           List available snapshots
  stats          Show backup statistics
  verify         Verify the integrity of the backup repository
  export         Export backup information to a file
  template       Display a template for init.sh file

Options:
  -p, --profile PROFILE   Use specific profile configuration
  -d, --dry-run           Show what would be done without actually doing it
  -v, --verbose           Increase verbosity
  -h, --help              Show this help message

Environment variables:
  INIT_SCRIPT          Path to initialization script (default: init.sh)
  PROFILE              Default profile name (default: default)
  DRY_RUN              Set to 1 for dry-run mode
  VERBOSE              Set to 1 for verbose output
  MAX_LOG_FILES        Maximum number of log files to keep (default: 10)
  RESTIC_REPOSITORY    Optional: Use a remote repository directly instead of local+rclone

Required configuration in init.sh:
  CONFIG_DIR           Directory for all configuration and backup files
  BACKUP_DIRECTORIES   Space-separated list of directories to backup

Examples:
  $SCRIPT_NAME init                 # Initialize the repository
  $SCRIPT_NAME backup               # Create a backup
  $SCRIPT_NAME -p server backup     # Create a backup using the 'server' profile
  $SCRIPT_NAME --dry-run backup     # Show what would be backed up
  $SCRIPT_NAME restore /tmp latest  # Restore latest snapshot to /tmp
  $SCRIPT_NAME list                 # List all snapshots
  $SCRIPT_NAME template             # Show template for init.sh

  # Run with a specific init script
  INIT_SCRIPT=/path/to/init.sh $SCRIPT_NAME backup

  # Run with a direct remote repository
  RESTIC_REPOSITORY=s3:s3.amazonaws.com/my-bucket/restic $SCRIPT_NAME backup
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--profile)
                PROFILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            init|backup|restore|push|pull|list|verify|stats|export|template)
                COMMAND="$1"
                shift
                COMMAND_ARGS=("$@")
                return
                ;;
            *)
                echo_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    echo_error "No command specified"
    print_usage
    exit 1
}

main() {
    # Parse command line arguments first
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 1
    fi

    parse_args "$@"

    # Special case for template command - doesn't need CONFIG_DIR
    if [[ "$COMMAND" == "template" ]]; then
        print_init_template
        exit 0
    fi

    # Everything else requires init.sh with CONFIG_DIR already loaded
    # At this point, CONFIG_DIR should be set from pre_load_init

    # Create config directory structure
    create_config_structure

    # Setup logging
    setup_logging

    # Check for concurrent runs
    check_lock

    log "Starting $SCRIPT_NAME with command: $COMMAND"

    # Fully load configuration
    load_init_script
    check_requirements
    validate_config
    set_defaults
    print_config

    # Execute the requested command
    case "$COMMAND" in
        init)
            restic_init
            ;;
        backup)
            backup
            ;;
        restore)
            restore "${COMMAND_ARGS[0]:-/}" "${COMMAND_ARGS[1]:-latest}"
            ;;
        push)
            push
            ;;
        pull)
            pull
            ;;
        list)
            list_snapshots
            ;;
        verify)
            verify_backup
            ;;
        stats)
            show_stats
            ;;
        export)
            export_info
            ;;
        *)
            log_error "Invalid command: $COMMAND"
            print_usage
            exit 1
            ;;
    esac

    log_success "Command $COMMAND completed successfully"
}

main "$@"