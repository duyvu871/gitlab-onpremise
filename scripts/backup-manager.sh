#!/bin/bash

# GitLab Backup Management Script
# Usage: ./backup-manager.sh [command] [options]

set -e

# Configuration
BACKUP_DIR="./backups"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Functions
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

show_help() {
    echo -e "${CYAN}GitLab Backup Manager${NC}"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  list                    List all available backups"
    echo "  status                  Show backup service status"
    echo "  create [name]          Create manual backup"
    echo "  restore <name>         Restore from backup"
    echo "  cleanup [days]         Remove backups older than X days (default: 7)"
    echo "  verify <name>          Verify backup integrity"
    echo "  size                   Show backup directory size"
    echo "  logs                   Show backup logs"
    echo "  test                   Test backup/restore process"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 create pre_upgrade"
    echo "  $0 restore manual_20240715_140000"
    echo "  $0 cleanup 14"
    echo ""
}

list_backups() {
    info "Available backups in $BACKUP_DIR:"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ]; then
        warning "Backup directory does not exist: $BACKUP_DIR"
        return 1
    fi
    
    # Header
    printf "%-30s %-12s %-20s %-10s\n" "BACKUP NAME" "SIZE" "DATE" "TYPE"
    printf "%-30s %-12s %-20s %-10s\n" "$(printf '%.30s' "------------------------------")" "$(printf '%.12s' "------------")" "$(printf '%.20s' "--------------------")" "$(printf '%.10s' "----------")"
    
    # List application backups
    for backup in "$BACKUP_DIR"/*_gitlab_backup.tar; do
        if [ -f "$backup" ]; then
            name=$(basename "$backup" _gitlab_backup.tar)
            size=$(du -h "$backup" 2>/dev/null | cut -f1 || echo "N/A")
            date=$(stat -c %y "$backup" 2>/dev/null | cut -d'.' -f1 || echo "Unknown")
            type="APP"
            printf "%-30s %-12s %-20s %-10s\n" "$name" "$size" "$date" "$type"
        fi
    done
    
    echo ""
    info "Total backups: $(ls -1 "$BACKUP_DIR"/*_gitlab_backup.tar 2>/dev/null | wc -l || echo 0)"
}

show_status() {
    info "GitLab Backup Service Status:"
    echo ""
    
    # Check if containers are running
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(gitlab|gitlab-backup)"; then
        echo ""
    else
        warning "GitLab containers are not running"
    fi
    
    # Check backup schedule
    if docker ps | grep -q "gitlab-backup"; then
        info "Backup schedule: $(grep BACKUP_SCHEDULE .env | cut -d'=' -f2 || echo 'Not configured')"
        info "Backup retention: $(grep BACKUP_RETENTION_DAYS .env | cut -d'=' -f2 || echo 'Not configured') days"
    else
        warning "Backup container is not running"
    fi
    
    # Check last backup
    if [ -d "$BACKUP_DIR" ]; then
        LAST_BACKUP=$(ls -t "$BACKUP_DIR"/*_gitlab_backup.tar 2>/dev/null | head -1 || echo "")
        if [ -n "$LAST_BACKUP" ]; then
            LAST_DATE=$(stat -c %y "$LAST_BACKUP" 2>/dev/null | cut -d'.' -f1 || echo "Unknown")
            info "Last backup: $(basename "$LAST_BACKUP") ($LAST_DATE)"
        else
            warning "No backups found"
        fi
    fi
}

create_backup() {
    local backup_name="$1"
    if [ -z "$backup_name" ]; then
        backup_name="manual_$(date +%Y%m%d_%H%M%S)"
    fi
    
    log "Creating backup: $backup_name"
    bash "$SCRIPT_DIR/backup.sh" "$backup_name"
}

restore_backup() {
    local backup_name="$1"
    if [ -z "$backup_name" ]; then
        error "Backup name is required for restore"
        return 1
    fi
    
    log "Restoring from backup: $backup_name"
    bash "$SCRIPT_DIR/restore.sh" "$backup_name"
}

cleanup_backups() {
    local days=${1:-7}
    
    warning "This will remove backups older than $days days"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled"
        return 0
    fi
    
    log "Cleaning up backups older than $days days..."
    
    local count=0
    for backup in "$BACKUP_DIR"/*_gitlab_backup.tar; do
        if [ -f "$backup" ] && [ "$(find "$backup" -mtime +$days)" ]; then
            log "Removing: $(basename "$backup")"
            rm -f "$backup"
            
            # Remove associated config and secrets backups
            local name=$(basename "$backup" _gitlab_backup.tar)
            rm -f "$BACKUP_DIR/${name}_config.tar.gz"
            rm -f "$BACKUP_DIR/${name}_secrets.json"
            
            ((count++))
        fi
    done
    
    log "Removed $count old backups"
}

verify_backup() {
    local backup_name="$1"
    if [ -z "$backup_name" ]; then
        error "Backup name is required for verification"
        return 1
    fi
    
    local backup_file="$BACKUP_DIR/${backup_name}_gitlab_backup.tar"
    
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi
    
    log "Verifying backup: $backup_name"
    
    # Check file integrity
    if tar -tf "$backup_file" > /dev/null 2>&1; then
        info "✓ Backup file integrity OK"
    else
        error "✗ Backup file is corrupted"
        return 1
    fi
    
    # Check backup size
    local size=$(du -h "$backup_file" | cut -f1)
    info "✓ Backup size: $size"
    
    # Check backup contents
    local contents=$(tar -tf "$backup_file" | head -5)
    info "✓ Backup contains:"
    echo "$contents" | sed 's/^/    /'
    
    log "Backup verification completed"
}

show_size() {
    if [ ! -d "$BACKUP_DIR" ]; then
        warning "Backup directory does not exist"
        return 1
    fi
    
    info "Backup directory analysis:"
    echo ""
    
    # Total size
    local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    info "Total backup size: $total_size"
    
    # Individual backup sizes
    echo ""
    printf "%-40s %s\n" "BACKUP FILE" "SIZE"
    printf "%-40s %s\n" "$(printf '%.40s' "----------------------------------------")" "--------"
    
    for backup in "$BACKUP_DIR"/*_gitlab_backup.tar; do
        if [ -f "$backup" ]; then
            local name=$(basename "$backup")
            local size=$(du -h "$backup" | cut -f1)
            printf "%-40s %s\n" "$name" "$size"
        fi
    done
}

show_logs() {
    info "Backup logs:"
    echo ""
    
    # Container logs
    if docker ps | grep -q "gitlab-backup"; then
        info "Recent backup container logs:"
        docker logs --tail 50 gitlab-backup 2>/dev/null || warning "No backup container logs available"
    fi
    
    # Backup log file (if exists)
    if [ -f "/var/log/backup.log" ]; then
        echo ""
        info "Backup log file:"
        tail -20 /var/log/backup.log
    fi
}

test_backup() {
    log "Running backup/restore test..."
    
    # Create test backup
    local test_name="test_$(date +%Y%m%d_%H%M%S)"
    log "Creating test backup: $test_name"
    
    if create_backup "$test_name"; then
        info "✓ Test backup created successfully"
        
        # Verify test backup
        if verify_backup "$test_name"; then
            info "✓ Test backup verification passed"
            
            # Cleanup test backup
            log "Cleaning up test backup..."
            rm -f "$BACKUP_DIR/${test_name}_gitlab_backup.tar"
            rm -f "$BACKUP_DIR/${test_name}_config.tar.gz"
            rm -f "$BACKUP_DIR/${test_name}_secrets.json"
            
            log "✓ Backup/restore test completed successfully"
        else
            error "✗ Test backup verification failed"
            return 1
        fi
    else
        error "✗ Test backup creation failed"
        return 1
    fi
}

# Main script logic
case "${1:-help}" in
    "list"|"ls")
        list_backups
        ;;
    "status")
        show_status
        ;;
    "create")
        create_backup "$2"
        ;;
    "restore")
        restore_backup "$2"
        ;;
    "cleanup"|"clean")
        cleanup_backups "$2"
        ;;
    "verify")
        verify_backup "$2"
        ;;
    "size")
        show_size
        ;;
    "logs")
        show_logs
        ;;
    "test")
        test_backup
        ;;
    "help"|*)
        show_help
        ;;
esac
