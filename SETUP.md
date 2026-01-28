# Frigate Storage Setup Guide

## For Agentic Developers (Claude Code, etc.)

This document provides complete instructions for setting up the Frigate recording backup system from scratch.

---

## Overview

**Purpose**: Backup Frigate NVR recordings to GitHub with 90-day retention.

**Architecture**:
- **Frigate**: Keeps 2 days locally at `/home/daniel/frigate-setup/storage/recordings/`
- **This repo**: Stages recordings temporarily, pushes to GitHub LFS, cleans local copy
- **GitHub LFS**: Stores full 90-day archive remotely

**Storage Model**: GitHub LFS-only (minimal local footprint ~35GB during sync)

---

## Prerequisites

1. **git-lfs** installed: `sudo apt-get install git-lfs`
2. **SSH key** configured for GitHub (for `git@github.com:Veziik/frigate-storage.git`)
3. **~40GB free disk space** during sync operations
4. **GitHub LFS data pack** (free tier = 1GB storage, 1GB/month bandwidth)

---

## Fresh Setup Instructions

### Step 1: Clone Repository

```bash
mkdir -p /home/daniel/frigate-storage
cd /home/daniel/frigate-storage
git clone git@github.com:Veziik/frigate-storage.git .
```

### Step 2: Install git-lfs

```bash
sudo apt-get update
sudo apt-get install git-lfs
git lfs install
```

### Step 3: Run Setup Script

```bash
cd /home/daniel/frigate-storage
chmod +x setup.sh
sudo ./setup.sh
```

This will:
- Configure git-lfs to track `*.mp4` files
- Install systemd timer for nightly sync at 3 AM
- Enable the timer to persist across reboots

### Step 4: Verify Installation

```bash
# Check timer is active
systemctl status frigate-sync.timer

# Check when next sync will run
systemctl list-timers | grep frigate

# Run a manual test
./sync-recordings.sh
```

---

## File Structure

```
/home/daniel/frigate-storage/
├── sync-recordings.sh      # Main sync script (runs nightly)
├── cleanup-git-history.sh  # Git maintenance script
├── setup.sh                # One-time setup script
├── SETUP.md                # This file
├── README.md               # User documentation
├── manifest.txt            # Index of all recordings in repo
├── sync.log                # Sync operation logs
├── .gitattributes          # LFS tracking rules
├── recordings/             # Temporary staging (emptied after push)
└── systemd/
    ├── frigate-sync.service
    └── frigate-sync.timer
```

---

## Systemd Service Details

### Timer: `frigate-sync.timer`
- Runs daily at 3:00 AM
- `Persistent=true` - runs missed jobs after reboot
- Random delay up to 5 minutes to avoid thundering herd

### Service: `frigate-sync.service`
- Runs as user `daniel`
- 2-hour timeout for large uploads
- Logs to `/home/daniel/frigate-storage/sync.log`

### Manual Commands

```bash
# Start sync immediately
sudo systemctl start frigate-sync.service

# Check sync status
sudo systemctl status frigate-sync.service

# View timer schedule
systemctl list-timers frigate-sync.timer

# Disable timer
sudo systemctl disable frigate-sync.timer

# Re-enable timer
sudo systemctl enable frigate-sync.timer
sudo systemctl start frigate-sync.timer
```

---

## Sync Script Logic

1. **Lock**: Prevents concurrent runs
2. **Stage**: Copies yesterday's + today's recordings to staging
3. **Commit**: Adds files to git (LFS handles large files)
4. **Push**: Uploads to GitHub LFS
5. **Cleanup**: Removes local staging after successful push
6. **Prune**: Removes recordings older than 90 days from repo

---

## Troubleshooting

### "No space left on device"
The staging area needs ~35GB. Free space or check if old staging wasn't cleaned:
```bash
rm -rf /home/daniel/frigate-storage/recordings/*
```

### "Another sync is running"
Remove stale lock file:
```bash
rm /home/daniel/frigate-storage/.sync.lock
```

### Push failures
Check GitHub LFS quota:
```bash
git lfs env
```
May need GitHub LFS data pack for large storage.

### Timer not running after reboot
```bash
sudo systemctl enable frigate-sync.timer
sudo systemctl start frigate-sync.timer
```

---

## Recovery Scenarios

### Complete Re-setup
```bash
rm -rf /home/daniel/frigate-storage
git clone git@github.com:Veziik/frigate-storage.git /home/daniel/frigate-storage
cd /home/daniel/frigate-storage
sudo ./setup.sh
```

### Restore Recordings from GitHub
```bash
cd /home/daniel/frigate-storage
git lfs pull  # Downloads all LFS files
```

### View Recording History
```bash
git log --oneline recordings/
cat manifest.txt
```

---

## Configuration

Edit `sync-recordings.sh` to change:

| Variable | Default | Description |
|----------|---------|-------------|
| `FRIGATE_RECORDINGS` | `/home/daniel/frigate-setup/storage/recordings` | Source path |
| `STORAGE_REPO` | `/home/daniel/frigate-storage` | This repo |
| `RETENTION_DAYS` | `90` | Days to keep in GitHub |

Edit `systemd/frigate-sync.timer` to change schedule:
```ini
OnCalendar=*-*-* 03:00:00  # Change time here
```

After editing timer, reload:
```bash
sudo systemctl daemon-reload
sudo systemctl restart frigate-sync.timer
```

---

## GitHub LFS Costs

- **Free tier**: 1GB storage, 1GB bandwidth/month
- **Data packs**: $5/month for 50GB storage + 50GB bandwidth
- **Estimated need**: ~2.5TB storage = ~50 data packs = ~$250/month

Consider alternatives for cost-sensitive deployments:
- Self-hosted Git with LFS
- Backblaze B2 (~$5/TB/month)
- Local NAS backup

---

## Contact

Repository: `git@github.com:Veziik/frigate-storage.git`
