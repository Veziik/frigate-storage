#!/bin/bash
# Frigate Recordings Sync Script - LITE VERSION
# Only syncs recordings to local storage, does NOT push to GitHub
# Use this if GitHub storage is a concern
# For GitHub sync, use sync-recordings.sh instead

set -euo pipefail

# Configuration
FRIGATE_RECORDINGS="/home/daniel/frigate-setup/storage/recordings"
STORAGE_REPO="/home/daniel/frigate-storage"
RETENTION_DAYS=90
LOG_FILE="/home/daniel/frigate-storage/sync.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== Starting Frigate Recording Sync (LITE) =========="

cd "$STORAGE_REPO"

YESTERDAY=$(date -d "yesterday" '+%Y-%m-%d')
TODAY=$(date '+%Y-%m-%d')

log "Syncing recordings for: $YESTERDAY and $TODAY"

mkdir -p "$STORAGE_REPO/recordings"

# Sync recordings using rsync
for DATE_DIR in "$YESTERDAY" "$TODAY"; do
    SOURCE_DIR="$FRIGATE_RECORDINGS/$DATE_DIR"
    if [ -d "$SOURCE_DIR" ]; then
        log "Syncing $DATE_DIR..."
        rsync -av "$SOURCE_DIR" "$STORAGE_REPO/recordings/" 2>&1 | tail -3 | tee -a "$LOG_FILE"
    else
        log "No recordings found for $DATE_DIR"
    fi
done

# Generate manifest
log "Generating recordings manifest..."
find "$STORAGE_REPO/recordings" -type f -name "*.mp4" | sort > "$STORAGE_REPO/manifest.txt"
TOTAL_FILES=$(wc -l < "$STORAGE_REPO/manifest.txt")
TOTAL_SIZE=$(du -sh "$STORAGE_REPO/recordings" 2>/dev/null | cut -f1)
log "Total recordings: $TOTAL_FILES files, $TOTAL_SIZE"

# Cleanup: Remove recordings older than retention period
log "Checking for recordings older than $RETENTION_DAYS days..."
CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" '+%Y-%m-%d')

REMOVED_COUNT=0
for DATE_DIR in "$STORAGE_REPO/recordings"/*; do
    if [ -d "$DATE_DIR" ]; then
        DIR_NAME=$(basename "$DATE_DIR")
        if [[ "$DIR_NAME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            if [[ "$DIR_NAME" < "$CUTOFF_DATE" ]]; then
                log "Removing old recordings: $DIR_NAME"
                rm -rf "$DATE_DIR"
                ((REMOVED_COUNT++))
            fi
        fi
    fi
done

[ $REMOVED_COUNT -gt 0 ] && log "Removed $REMOVED_COUNT old recording directories"

log "========== Sync Complete (LOCAL ONLY) =========="
