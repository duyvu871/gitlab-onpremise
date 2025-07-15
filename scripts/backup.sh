#!/bin/bash

# GitLab Manual Backup Script
# Usage: ./backup.sh [backup_name]

set -e

# Configuration
BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME=${1:-"manual_${TIMESTAMP}"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

log "Starting manual GitLab backup process..."
log "Backup name: $BACKUP_NAME"

# Check if GitLab container is running
if ! docker ps | grep -q "gitlab"; then
    error "GitLab container is not running!"
    error "Please start GitLab first: docker compose up -d gitlab"
    exit 1
fi

# Check GitLab health before backup
log "Checking GitLab health..."
if ! docker exec gitlab gitlab-ctl status > /dev/null 2>&1; then
    warning "GitLab services may not be fully ready"
    read -p "Continue with backup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Backup cancelled by user"
        exit 0
    fi
fi

# Create GitLab application backup
log "Creating GitLab application backup..."
if docker exec gitlab gitlab-backup create BACKUP=$BACKUP_NAME; then
    log "GitLab application backup created successfully"
else
    error "Failed to create GitLab application backup"
    exit 1
fi

# Copy backup from GitLab container
log "Copying backup files from GitLab container..."
if docker cp gitlab:/var/opt/gitlab/backups/${BACKUP_NAME}_gitlab_backup.tar "$BACKUP_DIR/"; then
    log "Backup files copied successfully"
else
    error "Failed to copy backup files"
    exit 1
fi

# Create configuration backup
log "Creating configuration backup..."
if [ -d "./data/config" ]; then
    tar -czf "$BACKUP_DIR/${BACKUP_NAME}_config.tar.gz" -C ./data/config .
    log "Configuration backup created: ${BACKUP_NAME}_config.tar.gz"
else
    warning "Configuration directory not found, skipping config backup"
fi

# Create secrets backup
log "Creating secrets backup..."
if docker exec gitlab test -f /etc/gitlab/gitlab-secrets.json; then
    docker cp gitlab:/etc/gitlab/gitlab-secrets.json "$BACKUP_DIR/${BACKUP_NAME}_secrets.json"
    log "Secrets backup created: ${BACKUP_NAME}_secrets.json"
else
    warning "GitLab secrets file not found"
fi

# Calculate backup sizes
APP_BACKUP="$BACKUP_DIR/${BACKUP_NAME}_gitlab_backup.tar"
CONFIG_BACKUP="$BACKUP_DIR/${BACKUP_NAME}_config.tar.gz"
SECRETS_BACKUP="$BACKUP_DIR/${BACKUP_NAME}_secrets.json"

if [ -f "$APP_BACKUP" ]; then
    APP_SIZE=$(du -h "$APP_BACKUP" | cut -f1)
    log "Application backup: ${BACKUP_NAME}_gitlab_backup.tar ($APP_SIZE)"
fi

if [ -f "$CONFIG_BACKUP" ]; then
    CONFIG_SIZE=$(du -h "$CONFIG_BACKUP" | cut -f1)
    log "Configuration backup: ${BACKUP_NAME}_config.tar.gz ($CONFIG_SIZE)"
fi

if [ -f "$SECRETS_BACKUP" ]; then
    SECRETS_SIZE=$(du -h "$SECRETS_BACKUP" | cut -f1)
    log "Secrets backup: ${BACKUP_NAME}_secrets.json ($SECRETS_SIZE)"
fi

# List all backups
log "All available backups:"
ls -lht "$BACKUP_DIR"/ | head -10

log "Manual backup completed successfully!"
log "Backup location: $BACKUP_DIR"
log ""
log "To restore this backup, use:"
log "  ./scripts/restore.sh $BACKUP_NAME"
