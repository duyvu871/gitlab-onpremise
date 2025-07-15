#!/bin/bash

# Nginx Configuration Setup Script
# Usage: ./setup-nginx.sh [command]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Configuration
NGINX_CONFIG_FILE="./nginx/gitlab.ssit.company.conf"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
SITE_NAME="gitlab.ssit.company"

show_help() {
    echo -e "${BLUE}Nginx Configuration Setup${NC}"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install     Setup nginx configuration (symlink + reload)"
    echo "  enable      Enable GitLab site (create symlink)"
    echo "  disable     Disable GitLab site (remove symlink)"
    echo "  reload      Reload nginx configuration"
    echo "  test        Test nginx configuration"
    echo "  status      Show nginx and site status"
    echo "  remove      Remove GitLab site configuration"
    echo "  backup      Backup current nginx configuration"
    echo ""
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 test"
    echo "  $0 status"
    echo ""
}

check_nginx() {
    if ! command -v nginx &> /dev/null; then
        error "Nginx is not installed"
        info "Install nginx first:"
        info "  Ubuntu/Debian: sudo apt install nginx"
        info "  CentOS/RHEL: sudo yum install nginx"
        info "  macOS: brew install nginx"
        return 1
    fi
    
    if ! systemctl is-active --quiet nginx 2>/dev/null && ! service nginx status &>/dev/null; then
        warning "Nginx is not running"
        info "Start nginx with: sudo systemctl start nginx"
    fi
    
    return 0
}

check_permissions() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root or with sudo"
        info "Try: sudo $0 $1"
        return 1
    fi
    return 0
}

backup_nginx_config() {
    local backup_dir="/etc/nginx/backup-$(date +%Y%m%d-%H%M%S)"
    
    log "Creating backup of nginx configuration..."
    
    if mkdir -p "$backup_dir"; then
        cp -r /etc/nginx/sites-available "$backup_dir/" 2>/dev/null || true
        cp -r /etc/nginx/sites-enabled "$backup_dir/" 2>/dev/null || true
        cp /etc/nginx/nginx.conf "$backup_dir/" 2>/dev/null || true
        
        log "✓ Backup created at: $backup_dir"
    else
        warning "Could not create backup directory"
    fi
}

install_config() {
    log "Installing GitLab nginx configuration..."
    
    # Check if config file exists
    if [ ! -f "$NGINX_CONFIG_FILE" ]; then
        error "Nginx config file not found: $NGINX_CONFIG_FILE"
        return 1
    fi
    
    # Create sites-available and sites-enabled directories if they don't exist
    mkdir -p "$NGINX_SITES_AVAILABLE"
    mkdir -p "$NGINX_SITES_ENABLED"
    
    # Copy config to sites-available
    log "Copying config to sites-available..."
    if cp "$NGINX_CONFIG_FILE" "$NGINX_SITES_AVAILABLE/$SITE_NAME"; then
        log "✓ Config copied to $NGINX_SITES_AVAILABLE/$SITE_NAME"
    else
        error "Failed to copy config file"
        return 1
    fi
    
    # Create symlink to sites-enabled
    enable_site
    
    # Test configuration
    test_config
    
    # Reload nginx
    reload_nginx
    
    log "✓ GitLab nginx configuration installed successfully"
}

enable_site() {
    log "Enabling GitLab site..."
    
    # Check if config exists in sites-available
    if [ ! -f "$NGINX_SITES_AVAILABLE/$SITE_NAME" ]; then
        error "Configuration not found in sites-available"
        info "Run: $0 install"
        return 1
    fi
    
    # Remove existing symlink if it exists
    if [ -L "$NGINX_SITES_ENABLED/$SITE_NAME" ]; then
        log "Removing existing symlink..."
        rm "$NGINX_SITES_ENABLED/$SITE_NAME"
    fi
    
    # Create symlink
    if ln -s "$NGINX_SITES_AVAILABLE/$SITE_NAME" "$NGINX_SITES_ENABLED/$SITE_NAME"; then
        log "✓ Symlink created: $NGINX_SITES_ENABLED/$SITE_NAME -> $NGINX_SITES_AVAILABLE/$SITE_NAME"
    else
        error "Failed to create symlink"
        return 1
    fi
}

disable_site() {
    log "Disabling GitLab site..."
    
    if [ -L "$NGINX_SITES_ENABLED/$SITE_NAME" ]; then
        if rm "$NGINX_SITES_ENABLED/$SITE_NAME"; then
            log "✓ GitLab site disabled"
            reload_nginx
        else
            error "Failed to remove symlink"
            return 1
        fi
    else
        warning "GitLab site is not enabled or symlink not found"
    fi
}

test_config() {
    log "Testing nginx configuration..."
    
    if nginx -t; then
        log "✓ Nginx configuration test passed"
        return 0
    else
        error "✗ Nginx configuration test failed"
        return 1
    fi
}

reload_nginx() {
    log "Reloading nginx..."
    
    if systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null; then
        log "✓ Nginx reloaded successfully"
    else
        error "Failed to reload nginx"
        info "Try manually: sudo systemctl reload nginx"
        return 1
    fi
}

show_status() {
    info "Nginx and GitLab site status:"
    echo ""
    
    # Nginx service status
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log "✓ Nginx service is running"
    else
        warning "⚠ Nginx service is not running"
    fi
    
    # Configuration file status
    if [ -f "$NGINX_SITES_AVAILABLE/$SITE_NAME" ]; then
        log "✓ Configuration exists in sites-available"
    else
        warning "⚠ Configuration not found in sites-available"
    fi
    
    # Symlink status
    if [ -L "$NGINX_SITES_ENABLED/$SITE_NAME" ]; then
        log "✓ GitLab site is enabled (symlinked)"
        info "   Target: $(readlink $NGINX_SITES_ENABLED/$SITE_NAME)"
    else
        warning "⚠ GitLab site is not enabled"
    fi
    
    # Test configuration
    echo ""
    if nginx -t 2>/dev/null; then
        log "✓ Nginx configuration is valid"
    else
        error "✗ Nginx configuration has errors"
    fi
    
    # Show listening ports
    echo ""
    info "Nginx listening ports:"
    netstat -tlnp 2>/dev/null | grep nginx || ss -tlnp | grep nginx || echo "Could not determine listening ports"
    
    # Show enabled sites
    echo ""
    info "Enabled sites:"
    ls -la "$NGINX_SITES_ENABLED/" 2>/dev/null | grep -v "^total" || echo "No sites enabled"
}

remove_config() {
    warning "Removing GitLab nginx configuration..."
    
    read -p "Are you sure you want to remove GitLab nginx configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled"
        return 0
    fi
    
    # Disable site first
    disable_site
    
    # Remove from sites-available
    if [ -f "$NGINX_SITES_AVAILABLE/$SITE_NAME" ]; then
        if rm "$NGINX_SITES_AVAILABLE/$SITE_NAME"; then
            log "✓ Configuration removed from sites-available"
        else
            error "Failed to remove configuration"
        fi
    fi
    
    log "✓ GitLab nginx configuration removed"
}

# Check if running as root for most operations
case "${1:-help}" in
    "install"|"enable"|"disable"|"reload"|"remove")
        check_permissions "$1" || exit 1
        check_nginx || exit 1
        ;;
    "test"|"status")
        check_nginx || exit 1
        ;;
esac

# Main script logic
case "${1:-help}" in
    "install")
        backup_nginx_config
        install_config
        ;;
    "enable")
        enable_site
        test_config && reload_nginx
        ;;
    "disable")
        disable_site
        ;;
    "reload")
        test_config && reload_nginx
        ;;
    "test")
        test_config
        ;;
    "status")
        show_status
        ;;
    "remove")
        remove_config
        ;;
    "backup")
        check_permissions "$1" || exit 1
        backup_nginx_config
        ;;
    "help"|*)
        show_help
        ;;
esac
