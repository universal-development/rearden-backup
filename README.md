### rearden-backup

**rearden-backup** is a lightweight and reliable Bash script that automates the backup of local directories and securely
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

## License

This code is released under the MIT License. See [LICENSE](LICENSE).

