# Linux Log Triage Toolkit

A Linux support toolkit for collecting log evidence and repairing selected journal-service, rotation and retention problems.

## Diagnostic script

```bash
chmod +x src/linux_log_triage.sh
sudo ./src/linux_log_triage.sh --hours 24
```

The diagnostic script summarises journal, authentication, kernel, boot and recurring application errors in text, CSV and JSON formats.

## Repair script

Restart the journal service:

```bash
chmod +x src/linux_log_repair.sh
sudo ./src/linux_log_repair.sh --restart-journald
```

Rotate journal and configured log files:

```bash
sudo ./src/linux_log_repair.sh --rotate
```

Apply a journal retention limit:

```bash
sudo ./src/linux_log_repair.sh --vacuum-days 30
sudo ./src/linux_log_repair.sh --vacuum-size 500M
```

Preview any operation with `--dry-run`.

## What the repair does

- Restarts systemd-journald.
- Requests journal rotation and runs logrotate when configured.
- Can remove archived journal data older than a selected age.
- Can reduce archived journal storage to a selected size.
- Records journal disk usage and service state before and after repair.
- Supports confirmation prompts, dry-run, logs and clear exit codes.

## Safety and privacy

Vacuum operations affect archived journal history and require confirmation. Current active journal files are managed through supported journalctl operations. Logs can contain sensitive infrastructure and user information and should be reviewed before sharing.

## Author

Dewald Pretorius — L2 IT Support Engineer
