#!/bin/bash

# GitLab Backup Cron Script
# This script runs inside the backup container

set -e

# Configuration
BACKUP_DIR="/backups"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="gitlab_backup_${TIMESTAMP}.tar"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

log "Starting GitLab backup process..."

# Check if GitLab container is running
if ! docker ps | grep -q "gitlab"; then
    log "ERROR: GitLab container is not running!"
    exit 1
fi

# Create GitLab backup
log "Creating GitLab application backup..."
if docker exec gitlab gitlab-backup create BACKUP=${TIMESTAMP}; then
    log "GitLab application backup created successfully"
else
    log "ERROR: Failed to create GitLab application backup"
    exit 1
fi

# Copy backup from GitLab container
log "Copying backup files from GitLab container..."
if docker cp gitlab:/var/opt/gitlab/backups/${TIMESTAMP}_gitlab_backup.tar "$BACKUP_DIR/"; then
    log "Backup files copied successfully"
else
    log "ERROR: Failed to copy backup files"
    exit 1
fi

# Rename backup file
mv "$BACKUP_DIR/${TIMESTAMP}_gitlab_backup.tar" "$BACKUP_DIR/$BACKUP_FILE"

# Create configuration backup
log "Creating configuration backup..."
tar -czf "$BACKUP_DIR/gitlab_config_${TIMESTAMP}.tar.gz" -C /etc/gitlab .

# Calculate backup size
BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
CONFIG_SIZE=$(du -h "$BACKUP_DIR/gitlab_config_${TIMESTAMP}.tar.gz" | cut -f1)

log "Backup completed:"
log "  - Application backup: $BACKUP_FILE ($BACKUP_SIZE)"
log "  - Configuration backup: gitlab_config_${TIMESTAMP}.tar.gz ($CONFIG_SIZE)"

# Cleanup old backups
log "Cleaning up old backups (keeping last $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "gitlab_backup_*.tar" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "gitlab_config_*.tar.gz" -mtime +$RETENTION_DAYS -delete

# List current backups
log "Current backups:"
ls -lh "$BACKUP_DIR"/ | grep -E "(gitlab_backup_|gitlab_config_)"

# Send notification (if configured)
if [ -n "$WEBHOOK_URL" ]; then
    curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"GitLab backup completed successfully: $BACKUP_FILE ($BACKUP_SIZE)\"}" \
        2>/dev/null || log "Failed to send webhook notification"
fi

log "Backup process completed successfully!"
