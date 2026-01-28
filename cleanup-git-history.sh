#!/bin/bash
# Git History Cleanup Script
# Removes deleted recordings from git history to prevent repo bloat
# Run monthly via cron

set -euo pipefail

STORAGE_REPO="/home/daniel/frigate-storage"
LOG_FILE="/home/daniel/frigate-storage/cleanup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== Starting Git History Cleanup =========="

cd "$STORAGE_REPO"

# Get current repo size
BEFORE_SIZE=$(du -sh .git 2>/dev/null | cut -f1)
log "Git repo size before cleanup: $BEFORE_SIZE"

# Method 1: git gc with aggressive pruning (safe, non-destructive)
log "Running git garbage collection..."
git reflog expire --expire=now --all
git gc --prune=now --aggressive

AFTER_SIZE=$(du -sh .git 2>/dev/null | cut -f1)
log "Git repo size after gc: $AFTER_SIZE"

# Note: For more aggressive cleanup (rewriting history), use git-filter-repo
# This requires all collaborators to re-clone, so only run manually when needed
# Example: git filter-repo --invert-paths --path-glob 'recordings/2024-*'

log "========== Cleanup Complete =========="
log "Before: $BEFORE_SIZE, After: $AFTER_SIZE"
