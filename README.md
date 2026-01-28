# Frigate Recording Storage

Long-term storage for Frigate NVR recordings with 90-day retention.

## How It Works

- **Local Frigate**: Keeps 2 days of recordings
- **This repo**: Keeps 90 days of recordings
- **Nightly sync**: Copies recordings before Frigate deletes them
- **Auto-cleanup**: Removes recordings older than 90 days

## Directory Structure

```
recordings/
├── 2026-01-25/
│   ├── 00/
│   │   ├── front_door/
│   │   │   └── MM.SS.mp4
│   │   └── back_door/
│   │       └── MM.SS.mp4
│   └── ...
└── ...
```

## Scripts

- `sync-recordings.sh` - Daily sync (run via cron at 3 AM)
- `cleanup-git-history.sh` - Monthly git maintenance
- `setup.sh` - Initial setup

## Manual Commands

```bash
# Run sync manually
./sync-recordings.sh

# Check sync logs
tail -f sync.log

# View current recordings
cat manifest.txt
```

## Storage Notes

- ~25-35 GB/day of recordings
- 90 days ≈ 2.5-3 TB total
- Individual files: 1-4 MB (motion clips)

## Important: GitHub Storage Limits

GitHub free tier has limited repository storage. For 90 days of video:

**Option 1: GitHub with Git LFS (Recommended for remote backup)**
```bash
sudo apt-get install git-lfs
cd /home/daniel/frigate-storage
git lfs install
git lfs track "*.mp4"
```
Note: Git LFS has bandwidth costs for large repos.

**Option 2: Local-only storage (No GitHub push)**
Use `sync-recordings-lite.sh` instead - syncs locally but doesn't push to GitHub.
Good for local NAS/secondary drive backup.

**Option 3: Alternative cloud storage**
Consider Backblaze B2, Google Drive, or rsync to a NAS for cost-effective large storage.

## Script Options

| Script | Description |
|--------|-------------|
| `sync-recordings.sh` | Full sync with GitHub push |
| `sync-recordings-lite.sh` | Local sync only, no push |
