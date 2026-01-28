#!/bin/bash
# Frigate Recordings Sync Script
# Syncs recordings to git repo with 90-day retention
# Designed to run nightly via cron BEFORE Frigate deletes old recordings

set -euo pipefail

# Configuration
FRIGATE_RECORDINGS="/home/daniel/frigate-setup/storage/recordings"
STORAGE_REPO="/home/daniel/frigate-storage"
RETENTION_DAYS=90
LOG_FILE="/home/daniel/frigate-storage/sync.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== Starting Frigate Recording Sync =========="

# Ensure repo directory exists
cd "$STORAGE_REPO"

# Get yesterday's date (the day most likely to be deleted soon by Frigate's 2-day retention)
# Also sync today's recordings to be safe
YESTERDAY=$(date -d "yesterday" '+%Y-%m-%d')
TODAY=$(date '+%Y-%m-%d')

log "Syncing recordings for: $YESTERDAY and $TODAY"

# Create recordings directory in repo if it doesn't exist
mkdir -p "$STORAGE_REPO/recordings"

# Sync recordings using rsync (efficient incremental transfer)
# Only sync directories that exist
for DATE_DIR in "$YESTERDAY" "$TODAY"; do
    SOURCE_DIR="$FRIGATE_RECORDINGS/$DATE_DIR"
    if [ -d "$SOURCE_DIR" ]; then
        log "Syncing $DATE_DIR..."
        rsync -av --progress "$SOURCE_DIR" "$STORAGE_REPO/recordings/" 2>&1 | tail -5 | tee -a "$LOG_FILE"
    else
        log "No recordings found for $DATE_DIR"
    fi
done

# Generate manifest of all recordings
log "Generating recordings manifest..."
find "$STORAGE_REPO/recordings" -type f -name "*.mp4" | sort > "$STORAGE_REPO/manifest.txt"
TOTAL_FILES=$(wc -l < "$STORAGE_REPO/manifest.txt")
TOTAL_SIZE=$(du -sh "$STORAGE_REPO/recordings" 2>/dev/null | cut -f1)
log "Total recordings: $TOTAL_FILES files, $TOTAL_SIZE"

# Commit changes to git (track manifest, not the videos themselves for repo size)
log "Committing manifest to git..."
git add manifest.txt
git add -A recordings/ 2>/dev/null || true

# Check if there are changes to commit
if git diff --cached --quiet; then
    log "No new changes to commit"
else
    git commit -m "Sync recordings: $TODAY

Files: $TOTAL_FILES
Size: $TOTAL_SIZE
Synced: $YESTERDAY, $TODAY"

    log "Pushing to remote..."
    git push origin main 2>&1 | tee -a "$LOG_FILE" || {
        log "ERROR: Push failed. Will retry on next run."
    }
fi

# Cleanup: Remove recordings older than retention period
log "Checking for recordings older than $RETENTION_DAYS days..."
CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" '+%Y-%m-%d')
log "Cutoff date: $CUTOFF_DATE"

REMOVED_COUNT=0
for DATE_DIR in "$STORAGE_REPO/recordings"/*; do
    if [ -d "$DATE_DIR" ]; then
        DIR_NAME=$(basename "$DATE_DIR")
        # Check if directory name is a date and older than cutoff
        if [[ "$DIR_NAME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            if [[ "$DIR_NAME" < "$CUTOFF_DATE" ]]; then
                log "Removing old recordings: $DIR_NAME"
                rm -rf "$DATE_DIR"
                ((REMOVED_COUNT++))
            fi
        fi
    fi
done

if [ $REMOVED_COUNT -gt 0 ]; then
    log "Removed $REMOVED_COUNT old recording directories"

    # Update manifest after cleanup
    find "$STORAGE_REPO/recordings" -type f -name "*.mp4" | sort > "$STORAGE_REPO/manifest.txt"

    # Commit the removal
    git add -A
    git commit -m "Cleanup: Removed recordings older than $CUTOFF_DATE ($REMOVED_COUNT directories)"
    git push origin main 2>&1 | tee -a "$LOG_FILE" || {
        log "ERROR: Push after cleanup failed"
    }
fi

log "========== Sync Complete =========="
