#!/bin/bash
# Frigate Recordings Sync Script - Google Drive via rclone
# Syncs recordings to Google Drive with 90-day retention
# Requires: rclone configured with 'gdrive' remote
#
# Storage model:
# - Local Frigate: 2-day rolling window
# - Google Drive: Full 90-day archive
# - This script: Syncs before Frigate deletes, manages retention

set -euo pipefail

# Configuration
FRIGATE_RECORDINGS="/home/daniel/frigate-setup/storage/recordings"
RCLONE_REMOTE="gdrive:frigate-recordings"  # Adjust remote name if different
RETENTION_DAYS=90
LOG_FILE="/home/daniel/frigate-storage/sync.log"
LOCK_FILE="/home/daniel/frigate-storage/.sync.lock"
LOCAL_MANIFEST="/home/daniel/frigate-storage/manifest.txt"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Cleanup function
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
    if [ "$LOCK_PID" != "unknown" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
        log "ERROR: Another sync is running (PID $LOCK_PID). Exiting."
        exit 1
    else
        log "WARNING: Stale lock file found. Removing."
        rm -f "$LOCK_FILE"
    fi
fi
echo $$ > "$LOCK_FILE"

log "========== Starting Frigate Recording Sync (Google Drive) =========="

# Check rclone is available
if ! command -v rclone &> /dev/null; then
    log "ERROR: rclone is not installed. Install with: sudo apt install rclone"
    exit 1
fi

# Check remote is configured
if ! rclone listremotes | grep -q "^gdrive:"; then
    log "ERROR: rclone remote 'gdrive' not configured. Run: rclone config"
    exit 1
fi

# Get dates to sync (yesterday and today)
YESTERDAY=$(date -d "yesterday" '+%Y-%m-%d')
TODAY=$(date '+%Y-%m-%d')

log "Processing dates: $YESTERDAY, $TODAY"

# Track sync stats
SYNCED_FILES=0
SYNCED_SIZE="0"

# Sync each date directory
for DATE_DIR in "$YESTERDAY" "$TODAY"; do
    SOURCE_DIR="$FRIGATE_RECORDINGS/$DATE_DIR"

    if [ ! -d "$SOURCE_DIR" ]; then
        log "No recordings found for $DATE_DIR, skipping"
        continue
    fi

    # Count source files
    FILE_COUNT=$(find "$SOURCE_DIR" -type f -name "*.mp4" 2>/dev/null | wc -l)
    DIR_SIZE=$(du -sh "$SOURCE_DIR" 2>/dev/null | cut -f1)

    log "Syncing $DATE_DIR: $FILE_COUNT files ($DIR_SIZE)..."

    # Sync to Google Drive using rclone
    # --checksum: Use checksum for comparison (more accurate than modtime)
    # --transfers 4: 4 parallel transfers
    if rclone sync "$SOURCE_DIR" "$RCLONE_REMOTE/$DATE_DIR" \
        --checksum \
        --transfers 4 \
        --stats-one-line \
        --stats 30s \
        --log-file="$LOG_FILE" \
        --log-level INFO 2>&1 | tee -a "$LOG_FILE"; then
        log "✓ Successfully synced $DATE_DIR"
        ((SYNCED_FILES+=FILE_COUNT))
        SYNCED_SIZE="$DIR_SIZE"
    else
        log "ERROR: Failed to sync $DATE_DIR"
    fi
done

# Cleanup: Remove recordings older than retention period from Google Drive
log "Checking for old recordings to remove from Google Drive..."
CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" '+%Y-%m-%d')
log "Cutoff date: $CUTOFF_DATE"

# List remote directories and remove old ones
for REMOTE_DIR in $(rclone lsf "$RCLONE_REMOTE" --dirs-only 2>/dev/null || true); do
    # Remove trailing slash
    DIR_NAME="${REMOTE_DIR%/}"
    if [[ "$DIR_NAME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "$DIR_NAME" < "$CUTOFF_DATE" ]]; then
        log "Removing old recordings from Drive: $DIR_NAME"
        if rclone purge "$RCLONE_REMOTE/$DIR_NAME" 2>&1 | tee -a "$LOG_FILE"; then
            log "✓ Removed $DIR_NAME"
        else
            log "ERROR: Failed to remove $DIR_NAME"
        fi
    fi
done

# Generate manifest of remote files
log "Generating remote manifest..."
rclone ls "$RCLONE_REMOTE" 2>/dev/null | grep ".mp4$" | sort > "$LOCAL_MANIFEST" || true
TOTAL_FILES=$(wc -l < "$LOCAL_MANIFEST" 2>/dev/null || echo "0")
TOTAL_SIZE=$(rclone size "$RCLONE_REMOTE" --json 2>/dev/null | grep -o '"bytes":[0-9]*' | cut -d: -f2 || echo "unknown")

# Convert bytes to human readable
if [ "$TOTAL_SIZE" != "unknown" ] && [ -n "$TOTAL_SIZE" ]; then
    TOTAL_SIZE_HR=$(numfmt --to=iec-i --suffix=B "$TOTAL_SIZE" 2>/dev/null || echo "${TOTAL_SIZE} bytes")
else
    TOTAL_SIZE_HR="unknown"
fi

log "========== Sync Complete =========="
log "Synced: $SYNCED_FILES files today"
log "Total in Google Drive: $TOTAL_FILES files ($TOTAL_SIZE_HR)"
