#!/bin/bash
# Frigate Recordings Sync Script - GitHub LFS Mode
# Stages recordings temporarily, pushes to GitHub LFS, then cleans local copy
# Requires: git-lfs, ~35GB temporary disk space
#
# Storage model:
# - Local: Only temporary staging (~1 day at a time)
# - GitHub LFS: Full 90-day archive
# - Frigate: 2-day rolling window

set -euo pipefail

# Configuration
FRIGATE_RECORDINGS="/home/daniel/frigate-setup/storage/recordings"
STORAGE_REPO="/home/daniel/frigate-storage"
STAGING_DIR="$STORAGE_REPO/recordings"
RETENTION_DAYS=90
LOG_FILE="$STORAGE_REPO/sync.log"
LOCK_FILE="$STORAGE_REPO/.sync.lock"

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
    log "ERROR: Another sync is running (lock file exists). Exiting."
    exit 1
fi
echo $$ > "$LOCK_FILE"

log "========== Starting Frigate Recording Sync (LFS Mode) =========="

cd "$STORAGE_REPO"

# Check available disk space (need at least 40GB for staging)
AVAILABLE_GB=$(df -BG "$STORAGE_REPO" | awk 'NR==2 {print $4}' | tr -d 'G')
if [ "$AVAILABLE_GB" -lt 40 ]; then
    log "WARNING: Only ${AVAILABLE_GB}GB available. Need 40GB for safe staging."
fi

# Get dates to sync (yesterday and today - before Frigate's 2-day cleanup)
YESTERDAY=$(date -d "yesterday" '+%Y-%m-%d')
TODAY=$(date '+%Y-%m-%d')

log "Processing dates: $YESTERDAY, $TODAY"
log "Available disk space: ${AVAILABLE_GB}GB"

# Ensure staging directory exists
mkdir -p "$STAGING_DIR"

# Process each date one at a time to minimize disk usage
for DATE_DIR in "$YESTERDAY" "$TODAY"; do
    SOURCE_DIR="$FRIGATE_RECORDINGS/$DATE_DIR"
    DEST_DIR="$STAGING_DIR/$DATE_DIR"

    if [ ! -d "$SOURCE_DIR" ]; then
        log "No recordings found for $DATE_DIR, skipping"
        continue
    fi

    # Check if already synced (directory exists in git)
    if git ls-tree -d HEAD --name-only 2>/dev/null | grep -q "recordings/$DATE_DIR"; then
        log "$DATE_DIR already in repo, checking for new files..."
    fi

    log "Staging $DATE_DIR..."

    # Copy recordings to staging (rsync for efficiency)
    rsync -av --info=progress2 "$SOURCE_DIR/" "$DEST_DIR/" 2>&1 | tail -5 | tee -a "$LOG_FILE"

    if [ $? -ne 0 ]; then
        log "ERROR: rsync failed for $DATE_DIR"
        continue
    fi

    # Count files staged
    FILE_COUNT=$(find "$DEST_DIR" -type f -name "*.mp4" 2>/dev/null | wc -l)
    DIR_SIZE=$(du -sh "$DEST_DIR" 2>/dev/null | cut -f1)
    log "Staged $FILE_COUNT files ($DIR_SIZE) for $DATE_DIR"

    # Add to git (LFS will handle large files)
    log "Adding to git..."
    git add "$DEST_DIR"

    # Commit this date
    if ! git diff --cached --quiet; then
        git commit -m "Add recordings: $DATE_DIR

Files: $FILE_COUNT
Size: $DIR_SIZE
Cameras: $(ls "$DEST_DIR"/*/ 2>/dev/null | head -5 | xargs -I{} basename {} | tr '\n' ', ' || echo 'various')"

        log "Pushing $DATE_DIR to GitHub LFS..."
        if git push origin main 2>&1 | tee -a "$LOG_FILE"; then
            log "Successfully pushed $DATE_DIR"

            # Clean up local staging after successful push
            log "Cleaning local staging for $DATE_DIR..."
            rm -rf "$DEST_DIR"
            git rm -rf --cached "$DEST_DIR" 2>/dev/null || true
        else
            log "ERROR: Push failed for $DATE_DIR. Keeping local copy for retry."
        fi
    else
        log "No new files to commit for $DATE_DIR"
    fi
done

# Update manifest (list of all recordings in repo)
log "Updating remote manifest..."
git ls-tree -r HEAD --name-only | grep "\.mp4$" | sort > "$STORAGE_REPO/manifest.txt" 2>/dev/null || true
TOTAL_FILES=$(wc -l < "$STORAGE_REPO/manifest.txt" 2>/dev/null || echo "0")
log "Total recordings in repo: $TOTAL_FILES files"

# Commit manifest update
git add manifest.txt 2>/dev/null || true
if ! git diff --cached --quiet; then
    git commit -m "Update manifest: $TOTAL_FILES files"
    git push origin main 2>&1 | tee -a "$LOG_FILE" || true
fi

# Remote cleanup: Remove recordings older than retention period
log "Checking for recordings older than $RETENTION_DAYS days to remove from repo..."
CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" '+%Y-%m-%d')
log "Cutoff date: $CUTOFF_DATE"

# Find old directories in the repo
OLD_DIRS=$(git ls-tree -d HEAD --name-only recordings/ 2>/dev/null | while read dir; do
    DIR_NAME=$(basename "$dir")
    if [[ "$DIR_NAME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "$DIR_NAME" < "$CUTOFF_DATE" ]]; then
        echo "$dir"
    fi
done)

if [ -n "$OLD_DIRS" ]; then
    log "Removing old recordings from repo..."
    for OLD_DIR in $OLD_DIRS; do
        log "Removing: $OLD_DIR"
        git rm -rf "$OLD_DIR" 2>/dev/null || true
    done

    if ! git diff --cached --quiet; then
        git commit -m "Cleanup: Remove recordings before $CUTOFF_DATE"
        git push origin main 2>&1 | tee -a "$LOG_FILE" || log "ERROR: Cleanup push failed"
    fi
fi

# Final disk space check
FINAL_SPACE=$(df -h "$STORAGE_REPO" | awk 'NR==2 {print $4}')
log "Disk space after sync: $FINAL_SPACE available"

log "========== Sync Complete =========="
