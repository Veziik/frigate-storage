# Frigate Storage Setup Guide

## For Agentic Developers (Claude Code, etc.)

Complete instructions for setting up the Frigate recording backup system.

---

## Overview

**Purpose**: Backup Frigate NVR recordings to Google Drive with 90-day retention.

**Architecture**:
- **Frigate**: Keeps 2 days locally at `/home/daniel/frigate-setup/storage/recordings/`
- **rclone**: Syncs recordings to Google Drive nightly
- **Google Drive**: Stores full 90-day archive (~2.5TB)

---

## Prerequisites

1. **rclone** installed
2. **Google Drive** with sufficient storage (~3TB recommended)
3. **Frigate NVR** running with recordings enabled

---

## Fresh Setup Instructions

### Step 1: Install rclone

```bash
# Option A: Via apt
sudo apt install rclone

# Option B: Latest version (recommended)
curl https://rclone.org/install.sh | sudo bash
```

### Step 2: Configure Google Drive Remote

```bash
rclone config
```

Follow prompts:
1. `n` - New remote
2. Name: `gdrive`
3. Storage: `drive` (Google Drive)
4. Client ID/Secret: Leave blank
5. Scope: `1` (Full access)
6. Auto config: `y` (opens browser)
7. Team drive: `n`
8. Confirm: `y`

Verify:
```bash
rclone lsd Drive:
```

### Step 3: Clone Repository

```bash
mkdir -p /home/daniel/frigate-storage
cd /home/daniel/frigate-storage
git clone git@github.com:Veziik/frigate-storage.git .
chmod +x *.sh
```

### Step 4: Install Systemd Timer

```bash
sudo cp systemd/frigate-sync.service /etc/systemd/system/
sudo cp systemd/frigate-sync.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable frigate-sync.timer
sudo systemctl start frigate-sync.timer
```

### Step 5: Verify

```bash
# Check timer
systemctl status frigate-sync.timer
systemctl list-timers | grep frigate

# Manual test
./sync-recordings.sh
```

---

## File Structure

```
/home/daniel/frigate-storage/
├── sync-recordings.sh      # Main sync script (rclone)
├── SETUP.md                # This file
├── manifest.txt            # Remote file index
├── sync.log                # Logs
└── systemd/
    ├── frigate-sync.service
    └── frigate-sync.timer
```

---

## Configuration

Edit `sync-recordings.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `FRIGATE_RECORDINGS` | `/home/daniel/frigate-setup/storage/recordings` | Source |
| `RCLONE_REMOTE` | `Drive:Frigate Recordings` | Destination |
| `RETENTION_DAYS` | `90` | Cloud retention |

---

## Commands

```bash
# Manual sync
./sync-recordings.sh

# View logs
tail -f sync.log

# Check Drive usage
rclone about gdrive:
rclone size gdrive:frigate-recordings

# Download specific day
rclone copy gdrive:frigate-recordings/2026-01-26 ./local/

# List remote recordings
rclone lsf gdrive:frigate-recordings --dirs-only
```

---

## Troubleshooting

### "rclone not installed"
```bash
curl https://rclone.org/install.sh | sudo bash
```

### "gdrive remote not configured"
```bash
rclone config
```

### "Another sync running"
```bash
rm /home/daniel/frigate-storage/.sync.lock
```

### Timer not running after reboot
```bash
sudo systemctl enable frigate-sync.timer
sudo systemctl start frigate-sync.timer
```

---

## Recovery

### Full restore from Drive
```bash
mkdir -p /restore
rclone sync gdrive:frigate-recordings /restore --progress
```

### Re-setup from scratch
```bash
rm -rf /home/daniel/frigate-storage
git clone git@github.com:Veziik/frigate-storage.git /home/daniel/frigate-storage
cd /home/daniel/frigate-storage
chmod +x *.sh
# Then run Step 4 above
```
