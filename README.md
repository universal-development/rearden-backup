### rearden-backup

Lightweight and reliable Bash script that automates the backup of local directories and securely
uploads them to a remote storage service.

This tool combines the power of `restic` for secure, incremental local backups with `rclone` for seamless remote syncing across
cloud providers, SFTP, WebDAV, or even custom remote endpoints.

#### 🔧 Features

- 📁 Backup selected local directories with `restic`
- ☁️ Upload backups to remote storage using `rclone`
- 🔒 Strong encryption with `restic` for secure backups
- 🔄 Easy restoration from any snapshot
- 📊 Backup statistics and verification
- 🕒 Supports scheduled (cron) execution for automated daily backups
- 📋 Comprehensive logging system with log rotation
- 🔃 Profile support for multiple backup configurations
- 🚫 Lock mechanism to prevent concurrent executions
- 🧪 Dry-run capability to preview actions
- 🧰 Minimal dependencies: only `bash`, `restic`, and `rclone`

#### 💼 Use Cases

- Personal or professional workstation backups
- Offsite backups for servers or VPS
- Archiving dev environments, config files, or databases
- Multi-system backup management with profiles

#### Installation

1. Check out rearden-backup into any path (here is `${HOME}/.rearden-backup`)

   ```bash
   git clone git@github.com:universal-development/rearden-backup.git ~/.rearden-backup
   ```

2. Add `~/.rearden-backup/bin` to your `$PATH` any way you like

   ```bash
   echo 'export PATH="$HOME/.rearden-backup/bin:$PATH"' >> ~/.bash_profile
   ```

#### Commands

| Command                     | Description                                                  |
|-----------------------------|--------------------------------------------------------------|
| `init`                      | Initialize the restic repository                             |
| `backup`                    | Create a new backup                                          |
| `restore [path] [snapshot]` | Restore from backup (defaults to latest snapshot and / path) |
| `push`                      | Upload entire CONFIG_DIR to remote storage                   |
| `pull`                      | Download entire CONFIG_DIR from remote storage               |
| `list`                      | List available snapshots                                     |
| `stats`                     | Show backup statistics                                       |
| `verify`                    | Verify the integrity of the backup repository                |
| `export`                    | Export backup information to a file                          |
| `template`                  | Display a template for init.sh file                          |

#### Options

| Option                  | Description                                       |
|-------------------------|---------------------------------------------------|
| `-p, --profile PROFILE` | Use specific profile configuration                |
| `-d, --dry-run`         | Show what would be done without actually doing it |
| `-v, --verbose`         | Enable basic verbosity (level 1)                  |
| `-vv`                   | Enable more detailed verbosity (level 2)          |
| `-vvv`                  | Enable maximum verbosity (level 3)                |
| `-h, --help`            | Show help message                                 |

#### Environment Variables

| Variable            | Description                                                        | Default   |
|---------------------|--------------------------------------------------------------------|-----------|
| `INIT_SCRIPT`       | Path to initialization script                                      | `init.sh` |
| `PROFILE`           | Default profile name                                               | `default` |
| `DRY_RUN`           | Set to 1 for dry-run mode                                          | `0`       |
| `VERBOSE`           | Set verbosity level: 0=none, 1=basic, 2=detailed, 3=maximum        | `1`       |
| `MAX_LOG_FILES`     | Maximum number of log files to keep                                | `10`      |
| `RESTIC_REPOSITORY` | Optional: Use a remote repository directly instead of local+rclone | ` `       |

#### Configuration Variables (in init.sh)

| Variable               | Description                                                                    | Required        |
|------------------------|--------------------------------------------------------------------------------|-----------------|
| `CONFIG_DIR`           | Directory for all configuration and backup files                               | Yes             |
| `BACKUP_DIRECTORIES`   | Space-separated list of directories to backup                                  | Yes             |
| `LOCAL_BACKUP_REPO`    | Local repository path for restic (default: `${CONFIG_DIR}/backups/${PROFILE}`) | No              |
| `RCLONE_REMOTE`        | Remote storage path for rclone                                                 | No              |
| `RETENTION_DAYS`       | Number of days to keep backups                                                 | No (default: 0) |
| `VERIFY_BACKUP`        | Verify backup after creation (1=yes, 0=no)                                     | No (default: 1) |
| `RESTIC_PASSWORD`      | Password for restic repository                                                 | No*             |
| `RESTIC_PASSWORD_FILE` | Path to file containing restic password                                        | No*             |
| `ENABLE_BACKUP`        | Enable/disable backup functionality                                            | No (default: 1) |
| `ENABLE_RESTORE`       | Enable/disable restore functionality                                           | No (default: 1) |
| `ENABLE_PUSH`          | Enable/disable push functionality                                              | No (default: 1) |
| `ENABLE_PULL`          | Enable/disable pull functionality                                              | No (default: 1) |

*Either `RESTIC_PASSWORD` or `RESTIC_PASSWORD_FILE` must be set

#### Backup Repository Modes

The script supports two modes for managing the backup repository:

1. **Local + Remote Sync mode** (default)
   - Backups are created locally in `LOCAL_BACKUP_REPO`
   - The entire `CONFIG_DIR` (including the repository) is synced to/from remote with rclone
   - Good for frequent backups with occasional remote synchronization

2. **Direct Remote Repository mode**
   - Set by defining `RESTIC_REPOSITORY` with a remote URL (s3, sftp, rest, etc.)
   - Backup operations work directly with the remote repository
   - Push/Pull operations are disabled in this mode
   - Good for direct cloud backups without local copies

#### Verbosity Levels

The script supports multiple verbosity levels to control the amount of information displayed:

- Level 0: Minimal output (only basic logs)
- Level 1 (`-v`): Basic progress and information
- Level 2 (`-vv`): Detailed progress and debug information
- Level 3 (`-vvv`): Maximum verbosity for troubleshooting

#### Profiles

Multiple backup profiles can be defined to manage different backup scenarios:

1. Create a profile file at `${CONFIG_DIR}/profiles/<profile_name>.sh`
2. Add specific configuration variables for that profile
3. Use the profile with `-p` or `--profile` option when running commands

#### Example Files

Example `init.sh`:

```bash
#!/bin/bash
# Basic configuration for backup script

# Required: Set the configuration directory
export CONFIG_DIR=$(pwd)/local

# Directories to backup (space-separated)
export BACKUP_DIRECTORIES="/projects /home/user/documents"

# Remote repository configuration
export RCLONE_REMOTE="remote:backup/projects-$(hostname)"

# Backup retention (days)
export RETENTION_DAYS=30

# Password file for restic repository
export RESTIC_PASSWORD_FILE="${CONFIG_DIR}/restic-password.txt"

# Optional: Configure verbosity (0=none, 1=basic, 2=detailed, 3=maximum)
export VERBOSE=1
```

Example profile for server backups (`local/profiles/server.sh`):

```bash
#!/bin/bash
# Server-specific backup settings

export BACKUP_DIRECTORIES="/etc /var/www /opt/application/data"
export RETENTION_DAYS=60
export VERBOSE=1
```

Example `local/rclone.conf` file for SFTP uploads:

```ini
[remote]
type = sftp
host = example.com
user = backup-user
port = 22
```

Example `local/rclone.conf` file for Hetzner storage box:

```ini
[remote]
type = sftp
host = u123456.your-storagebox.de
user = u123456
port = 23
```

Example `local/exclude.txt` for excluding specific patterns:

```
# Patterns to exclude from backup
**/.DS_Store
**/node_modules
**/.git
**/*.log
**/tmp
**/temp
**/.cache
```

#### Compatibility Notes

- The script is compatible with both newer and older versions of restic
- Some advanced features (like the `stats` command) may not be available in older restic versions
- For best results, using restic 0.12.0 or later is recommended

#### License

This code is released under the MIT License. See [LICENSE](LICENSE).
