### rearden-backup

Lightweight and reliable Bash script that automates the backup of local directories and securely
uploads them to a remote storage service.

Tool combines the power of `rsync` for fast, incremental local backups with `rclone` for seamless remote syncing across
cloud providers, SFTP, WebDAV, or even custom remote endpoints.

#### 🔧 Features

- 📁 Backup selected local directories with `rsync`
- ☁️ Upload archives or snapshots to remote storage using `rclone`
- 🕒 Supports scheduled (cron) execution for automated daily backups
- 🔐 Optional encryption via `rclone`'s crypt backend
- 🧾 Log-friendly output for easy monitoring
- 🧰 Minimal dependencies: only `bash`, `rsync`, and `rclone`

#### 💼 Use Cases

- Personal or professional workstation backups
- Offsite backups for servers or VPS
- Archiving dev environments, config files, or databases

#### Installation

1. Check out rearden-backup into any path (here is `${HOME}/.rearden-backup`)

   ```bash
   git clone git@github.com:universal-development/rearden-backup.git ~/.rearden-backup
   ```

2. Add `~/.rearden-backup/bin` to your `$PATH` any way you like

   ```bash
   echo 'export PATH="$HOME/.rearden-backup/bin:$PATH"' >> ~/.bash_profile

#### Commands

| Command                     | Description                                                  |
|-----------------------------|--------------------------------------------------------------|
| `init`                      | Initialize the restic repository                             |
| `backup`                    | Create a new backup                                          |
| `restore [path] [snapshot]` | Restore from backup (defaults to latest snapshot and / path) |
| `push`                      | Upload backup to remote storage                              |
| `pull`                      | Download backup from remote storage                          |
| `list`                      | List available snapshots                                     |
| `stats`                     | Show backup statistics                                       |
| `verify`                    | Verify the integrity of the backup repository                |
| `export`                    | Export backup information to a file                          |
| `template`                  | Display a template for init.sh file                          |

## Options

| Option                  | Description                                       |
|-------------------------|---------------------------------------------------|
| `-p, --profile PROFILE` | Use specific profile configuration                |
| `-d, --dry-run`         | Show what would be done without actually doing it |
| `-v, --verbose`         | Increase verbosity                                |
| `-h, --help`            | Show help message                                 |

## Environment Variables

| Variable        | Description                         | Default   |
|-----------------|-------------------------------------|-----------|
| `INIT_SCRIPT`   | Path to initialization script       | `init.sh` |
| `PROFILE`       | Default profile name                | `default` |
| `DRY_RUN`       | Set to 1 for dry-run mode           | `0`       |
| `VERBOSE`       | Set to 1 for verbose output         | `0`       |
| `MAX_LOG_FILES` | Maximum number of log files to keep | `10`      |

## Configuration Variables (in init.sh)

| Variable               | Description                                      | Required         |
|------------------------|--------------------------------------------------|------------------|
| `CONFIG_DIR`           | Directory for all configuration and backup files | Yes              |
| `BACKUP_DIRECTORIES`   | Space-separated list of directories to backup    | Yes              |
| `RCLONE_REMOTE`        | Remote storage path for rclone                   | No               |
| `RETENTION_DAYS`       | Number of days to keep backups                   | No (default: 30) |
| `RESTIC_PASSWORD`      | Password for restic repository                   | No*              |
| `RESTIC_PASSWORD_FILE` | Path to file containing restic password          | No*              |
| `ENABLE_BACKUP`        | Enable/disable backup functionality              | No (default: 1)  |
| `ENABLE_RESTORE`       | Enable/disable restore functionality             | No (default: 1)  |
| `ENABLE_PUSH`          | Enable/disable push functionality                | No (default: 1)  |
| `ENABLE_PULL`          | Enable/disable pull functionality                | No (default: 1)  |

*Either `RESTIC_PASSWORD` or `RESTIC_PASSWORD_FILE` must be set

## Example files

Example `init.sh`

```
export CONFIG_DIR=$(pwd)/local
export BACKUP_DIRECTORIES=/projects
export RESTIC_PASSWORD_FILE=$(pwd)/creds.txt
export RCLONE_REMOTE="remote:backup/projects-$(hostname)"
```

Example `local/rclone.conf` file for sftp uploads:

```
[remote]
type = sftp
host = xyz
user = abc
port = 22
```

Example `local/rclone.conf` file for Hetzner storage box:
```
[remote]
type = sftp
host = xyz.your-storagebox.de
user = abc
port = 23
```

## License

This code is released under the MIT License. See [LICENSE](LICENSE).

