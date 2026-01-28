#!/bin/bash
# Frigate Storage Setup Script
# Run once to configure the sync system

set -euo pipefail

STORAGE_REPO="/home/daniel/frigate-storage"

echo "========== Frigate Storage Setup =========="

# Check for git-lfs (optional but recommended)
if ! command -v git-lfs &> /dev/null; then
    echo "WARNING: git-lfs is not installed."
    echo "For large video files, install with: sudo apt-get install git-lfs"
    echo "Continuing without LFS (videos will be stored directly in git)..."
else
    echo "git-lfs is installed"
    cd "$STORAGE_REPO"
    git lfs install
    git lfs track "*.mp4"
    git add .gitattributes 2>/dev/null || true
fi

# Make scripts executable
chmod +x "$STORAGE_REPO/sync-recordings.sh"
chmod +x "$STORAGE_REPO/cleanup-git-history.sh"

# Create recordings directory
mkdir -p "$STORAGE_REPO/recordings"

# Initialize git config for the repo
cd "$STORAGE_REPO"
git config user.email "frigate-sync@localhost"
git config user.name "Frigate Sync"

# Initial commit if needed
if [ ! -f "$STORAGE_REPO/.gitignore" ]; then
    cat > "$STORAGE_REPO/.gitignore" << 'EOF'
# Logs
*.log

# Temporary files
*.tmp
*.swp
EOF
    git add .gitignore
fi

# Commit setup files
git add -A
git commit -m "Initial setup: sync scripts and configuration" 2>/dev/null || echo "No new files to commit"

echo ""
echo "========== Setting up Cron Jobs =========="
echo ""
echo "Add these lines to your crontab (crontab -e):"
echo ""
echo "# Sync Frigate recordings nightly at 3 AM"
echo "0 3 * * * $STORAGE_REPO/sync-recordings.sh >> $STORAGE_REPO/cron.log 2>&1"
echo ""
echo "# Clean up git history monthly on the 1st at 4 AM"
echo "0 4 1 * * $STORAGE_REPO/cleanup-git-history.sh >> $STORAGE_REPO/cron.log 2>&1"
echo ""

# Offer to install cron jobs automatically
read -p "Install cron jobs automatically? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Check if cron jobs already exist
    if crontab -l 2>/dev/null | grep -q "sync-recordings.sh"; then
        echo "Cron job for sync already exists, skipping..."
    else
        (crontab -l 2>/dev/null; echo "# Sync Frigate recordings nightly at 3 AM") | crontab -
        (crontab -l 2>/dev/null; echo "0 3 * * * $STORAGE_REPO/sync-recordings.sh >> $STORAGE_REPO/cron.log 2>&1") | crontab -
    fi

    if crontab -l 2>/dev/null | grep -q "cleanup-git-history.sh"; then
        echo "Cron job for cleanup already exists, skipping..."
    else
        (crontab -l 2>/dev/null; echo "# Clean up git history monthly") | crontab -
        (crontab -l 2>/dev/null; echo "0 4 1 * * $STORAGE_REPO/cleanup-git-history.sh >> $STORAGE_REPO/cron.log 2>&1") | crontab -
    fi

    echo "Cron jobs installed. Current crontab:"
    crontab -l
fi

echo ""
echo "========== Setup Complete =========="
echo ""
echo "To run the sync manually: $STORAGE_REPO/sync-recordings.sh"
echo "To view logs: tail -f $STORAGE_REPO/sync.log"
