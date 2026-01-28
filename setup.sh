#!/bin/bash
# Frigate Storage Setup Script
# Installs systemd timer for persistent nightly sync
# Run with sudo for systemd installation

set -euo pipefail

STORAGE_REPO="/home/daniel/frigate-storage"
SYSTEMD_DIR="/etc/systemd/system"

echo "========== Frigate Storage Setup =========="

# Check if running as root for systemd installation
if [ "$EUID" -ne 0 ]; then
    echo "Note: Run with sudo to install systemd services"
    echo "      sudo ./setup.sh"
    echo ""
    echo "Continuing with non-root setup..."
    SKIP_SYSTEMD=true
else
    SKIP_SYSTEMD=false
fi

# Verify git-lfs is installed
if ! command -v git-lfs &> /dev/null; then
    echo "ERROR: git-lfs is not installed."
    echo "Install with: sudo apt-get install git-lfs"
    exit 1
fi
echo "✓ git-lfs is installed"

# Initialize git-lfs in repo
cd "$STORAGE_REPO"
git lfs install
git lfs track "*.mp4"
git add .gitattributes 2>/dev/null || true
echo "✓ git-lfs configured to track *.mp4 files"

# Make scripts executable
chmod +x "$STORAGE_REPO/sync-recordings.sh"
chmod +x "$STORAGE_REPO/cleanup-git-history.sh" 2>/dev/null || true
echo "✓ Scripts made executable"

# Configure git for the repo
git config user.email "frigate-sync@localhost"
git config user.name "Frigate Sync"
echo "✓ Git configured"

# Create recordings staging directory
mkdir -p "$STORAGE_REPO/recordings"
echo "✓ Staging directory created"

# Install systemd services if running as root
if [ "$SKIP_SYSTEMD" = false ]; then
    echo ""
    echo "Installing systemd services..."

    # Copy service files
    cp "$STORAGE_REPO/systemd/frigate-sync.service" "$SYSTEMD_DIR/"
    cp "$STORAGE_REPO/systemd/frigate-sync.timer" "$SYSTEMD_DIR/"

    # Reload systemd
    systemctl daemon-reload

    # Enable and start timer
    systemctl enable frigate-sync.timer
    systemctl start frigate-sync.timer

    echo "✓ Systemd timer installed and enabled"
    echo ""
    echo "Timer status:"
    systemctl status frigate-sync.timer --no-pager || true
else
    echo ""
    echo "========== Manual Systemd Installation =========="
    echo "Run these commands to install the timer:"
    echo ""
    echo "  sudo cp $STORAGE_REPO/systemd/frigate-sync.service /etc/systemd/system/"
    echo "  sudo cp $STORAGE_REPO/systemd/frigate-sync.timer /etc/systemd/system/"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable frigate-sync.timer"
    echo "  sudo systemctl start frigate-sync.timer"
fi

# Commit any setup changes
git add -A
if ! git diff --cached --quiet; then
    git commit -m "Setup: Configure git-lfs and systemd services"
    git push origin main 2>/dev/null || echo "Push pending - run manually if needed"
fi

echo ""
echo "========== Setup Complete =========="
echo ""
echo "Commands:"
echo "  Manual sync:     $STORAGE_REPO/sync-recordings.sh"
echo "  View logs:       tail -f $STORAGE_REPO/sync.log"
echo "  Timer status:    systemctl status frigate-sync.timer"
echo "  Run now:         sudo systemctl start frigate-sync.service"
echo ""
