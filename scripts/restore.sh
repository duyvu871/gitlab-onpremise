#!/bin/bash

# GitLab Restore Script
# Usage: ./restore.sh <backup_name>
# Example: ./restore.sh manual_20240715_140000

set -e

# Configuration
BACKUP_DIR="./backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if backup name is provided
if [ -z "$1" ]; then
    error "Backup name is required!"
    echo ""
    echo "Usage: $0 <backup_name>"
    echo ""
    echo "Available backups:"
    if [ -d "$BACKUP_DIR" ]; then
        ls -1 "$BACKUP_DIR"/ | grep "_gitlab_backup.tar$" | sed 's/_gitlab_backup.tar$//' | sort -r | head -10
    else
        echo "No backup directory found"
    fi
    exit 1
fi

BACKUP_NAME="$1"
APP_BACKUP="$BACKUP_DIR/${BACKUP_NAME}_gitlab_backup.tar"
CONFIG_BACKUP="$BACKUP_DIR/${BACKUP_NAME}_config.tar.gz"
SECRETS_BACKUP="$BACKUP_DIR/${BACKUP_NAME}_secrets.json"

# Check if backup files exist
if [ ! -f "$APP_BACKUP" ]; then
    error "Application backup file not found: $APP_BACKUP"
    exit 1
fi

log "Starting GitLab restore process..."
log "Backup name: $BACKUP_NAME"
log "Application backup: $APP_BACKUP"

# Show backup information
if [ -f "$APP_BACKUP" ]; then
    APP_SIZE=$(du -h "$APP_BACKUP" | cut -f1)
    APP_DATE=$(stat -c %y "$APP_BACKUP" 2>/dev/null || stat -f %Sm "$APP_BACKUP" 2>/dev/null || echo "Unknown")
    info "Application backup size: $APP_SIZE"
    info "Backup date: $APP_DATE"
fi

# Confirmation prompt
warning "This will REPLACE all current GitLab data!"
warning "Make sure you have a recent backup of current data."
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Restore cancelled by user"
    exit 0
fi

# Check if GitLab container is running
if ! docker ps | grep -q "gitlab"; then
    error "GitLab container is not running!"
    error "Please start GitLab first: docker compose up -d gitlab"
    exit 1
fi

# Stop GitLab services
log "Stopping GitLab services..."
docker exec gitlab gitlab-ctl stop unicorn
docker exec gitlab gitlab-ctl stop puma
docker exec gitlab gitlab-ctl stop sidekiq

# Copy application backup to GitLab container
log "Copying application backup to GitLab container..."
docker cp "$APP_BACKUP" gitlab:/var/opt/gitlab/backups/

# Extract backup name from filename
BACKUP_TIMESTAMP=$(basename "$APP_BACKUP" _gitlab_backup.tar)

# Restore GitLab application
log "Restoring GitLab application data..."
if docker exec gitlab gitlab-backup restore BACKUP=$BACKUP_TIMESTAMP; then
    log "GitLab application restored successfully"
else
    error "Failed to restore GitLab application"
    exit 1
fi

# Restore configuration if available
if [ -f "$CONFIG_BACKUP" ]; then
    log "Restoring configuration..."
    
    # Backup current config
    log "Backing up current configuration..."
    docker exec gitlab tar -czf /tmp/config_backup_$(date +%s).tar.gz -C /etc/gitlab .
    
    # Extract and restore config
    docker cp "$CONFIG_BACKUP" gitlab:/tmp/restore_config.tar.gz
    docker exec gitlab sh -c "cd /etc/gitlab && tar -xzf /tmp/restore_config.tar.gz"
    docker exec gitlab rm /tmp/restore_config.tar.gz
    
    log "Configuration restored successfully"
else
    warning "Configuration backup not found: $CONFIG_BACKUP"
fi

# Restore secrets if available
if [ -f "$SECRETS_BACKUP" ]; then
    log "Restoring secrets..."
    docker cp "$SECRETS_BACKUP" gitlab:/etc/gitlab/gitlab-secrets.json
    log "Secrets restored successfully"
else
    warning "Secrets backup not found: $SECRETS_BACKUP"
fi

# Reconfigure and restart GitLab
log "Reconfiguring GitLab..."
docker exec gitlab gitlab-ctl reconfigure

log "Starting GitLab services..."
docker exec gitlab gitlab-ctl start

# Wait for GitLab to be ready
log "Waiting for GitLab to be ready..."
for i in {1..30}; do
    if docker exec gitlab gitlab-ctl status | grep -q "run:"; then
        log "GitLab services are running"
        break
    fi
    echo -n "."
    sleep 10
done

# Verify restore
log "Verifying restore..."
if docker exec gitlab gitlab-rake gitlab:check SANITIZE=true; then
    log "GitLab restore verification passed"
else
    warning "GitLab restore verification had some issues"
    info "Check the output above and run 'docker exec gitlab gitlab-rake gitlab:check' for details"
fi

# Check GitLab version
GITLAB_VERSION=$(docker exec gitlab cat /opt/gitlab/embedded/service/gitlab-rails/VERSION 2>/dev/null || echo "Unknown")
info "GitLab version: $GITLAB_VERSION"

log "Restore completed successfully!"
log ""
log "Next steps:"
log "1. Check GitLab health: docker exec gitlab gitlab-ctl status"
log "2. Verify web interface: http://$(grep GITLAB_URL .env | cut -d'=' -f2 | tr -d \"\')"
log "3. Test SSH access if configured"
log "4. Verify user access and repositories"