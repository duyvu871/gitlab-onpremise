#!/bin/bash

# GitLab Health Check and Troubleshooting Script
# Usage: ./gitlab-health.sh [command]

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

show_help() {
    echo -e "${BLUE}GitLab Health Check & Troubleshooting${NC}"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  check          Complete health check"
    echo "  status         Show container status"
    echo "  logs           Show recent logs"
    echo "  metrics        Check Prometheus metrics issues"
    echo "  memory         Check memory usage"
    echo "  fix-shm        Fix shared memory issues"
    echo "  reconfigure    Reconfigure GitLab"
    echo "  restart        Restart GitLab services"
    echo "  cleanup        Clean up unused resources"
    echo ""
}

check_containers() {
    info "Checking container status..."
    echo ""
    
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(gitlab|gitlab-backup)"; then
        log "✓ Containers are running"
    else
        error "✗ GitLab containers are not running"
        return 1
    fi
    echo ""
}

check_gitlab_health() {
    info "Checking GitLab application health..."
    
    # Wait for GitLab to be ready
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec gitlab gitlab-ctl status > /dev/null 2>&1; then
            log "✓ GitLab services are running"
            break
        else
            warning "Attempt $attempt/$max_attempts: GitLab services not ready..."
            sleep 10
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "✗ GitLab services failed to start properly"
        return 1
    fi
    
    # Check specific services
    info "Checking individual services..."
    docker exec gitlab gitlab-ctl status | while read line; do
        if echo "$line" | grep -q "run:"; then
            service=$(echo "$line" | awk '{print $2}' | cut -d':' -f1)
            log "✓ $service is running"
        elif echo "$line" | grep -q "down:"; then
            service=$(echo "$line" | awk '{print $2}' | cut -d':' -f1)
            error "✗ $service is down"
        fi
    done
    
    echo ""
}

check_connectivity() {
    info "Checking network connectivity..."
    
    # Get GitLab URL from .env
    local gitlab_url=$(grep GITLAB_URL .env | cut -d'=' -f2)
    local gitlab_port=$(grep GITLAB_HTTP_PORT .env | cut -d'=' -f2)
    
    # Check if GitLab responds
    if curl -s -f "http://localhost:$gitlab_port/-/health" > /dev/null; then
        log "✓ GitLab health endpoint is accessible"
    else
        warning "⚠ GitLab health endpoint is not accessible"
        warning "This might be normal during startup"
    fi
    
    # Check if web interface is accessible
    if curl -s -f "http://localhost:$gitlab_port" > /dev/null; then
        log "✓ GitLab web interface is accessible"
    else
        warning "⚠ GitLab web interface is not accessible"
    fi
    
    echo ""
}

show_recent_logs() {
    info "Recent GitLab logs (last 50 lines):"
    echo ""
    docker logs --tail 50 gitlab 2>&1 | tail -20
    echo ""
    
    info "Recent backup container logs:"
    echo ""
    if docker ps | grep -q "gitlab-backup"; then
        docker logs --tail 20 gitlab-backup 2>&1 || warning "No backup container logs available"
    else
        warning "Backup container is not running"
    fi
    echo ""
}

check_metrics_issues() {
    info "Checking Prometheus metrics issues..."
    echo ""
    
    # Check for shared memory errors in logs
    local shm_errors=$(docker logs gitlab 2>&1 | grep -c "writing value to /dev/shm" || echo "0")
    if [ "$shm_errors" -gt 0 ]; then
        warning "Found $shm_errors shared memory errors in logs"
        warning "This can be fixed with: $0 fix-shm"
    else
        log "✓ No shared memory errors found"
    fi
    
    # Check Prometheus configuration
    if docker exec gitlab grep -q "prometheus\['enable'\] = true" /opt/gitlab/embedded/cookbooks/gitlab/recipes/prometheus.rb 2>/dev/null; then
        info "Prometheus is enabled"
        
        # Check if metrics endpoint is accessible
        if docker exec gitlab curl -s -f "http://localhost:9090/-/healthy" > /dev/null 2>&1; then
            log "✓ Prometheus is healthy"
        else
            warning "⚠ Prometheus might have issues"
        fi
    else
        info "Prometheus monitoring status unclear"
    fi
    
    echo ""
}

check_memory_usage() {
    info "Memory usage analysis..."
    echo ""
    
    # Container memory usage
    info "Container memory usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep -E "(gitlab|NAME)"
    echo ""
    
    # System memory
    info "System memory:"
    free -h
    echo ""
    
    # Shared memory usage
    info "Shared memory usage:"
    if docker exec gitlab df -h /dev/shm 2>/dev/null; then
        log "✓ Shared memory information available"
    else
        warning "⚠ Cannot access shared memory information"
    fi
    
    echo ""
}

fix_shared_memory() {
    warning "Attempting to fix shared memory issues..."
    
    # Stop GitLab
    log "Stopping GitLab container..."
    docker compose stop gitlab
    
    # Clean up shared memory
    log "Cleaning up shared memory..."
    docker system prune -f
    
    # Restart with new configuration
    log "Starting GitLab with updated configuration..."
    docker compose up -d gitlab
    
    # Wait and check
    log "Waiting for GitLab to start..."
    sleep 30
    
    if check_containers && check_gitlab_health; then
        log "✓ Shared memory fix appears successful"
    else
        error "✗ Shared memory fix may not have worked"
        warning "You may need to manually reconfigure: $0 reconfigure"
    fi
}

reconfigure_gitlab() {
    log "Reconfiguring GitLab..."
    
    if docker exec gitlab gitlab-ctl reconfigure; then
        log "✓ GitLab reconfigured successfully"
        
        log "Restarting GitLab services..."
        docker exec gitlab gitlab-ctl restart
        
        sleep 30
        check_gitlab_health
    else
        error "✗ GitLab reconfiguration failed"
        return 1
    fi
}

restart_services() {
    log "Restarting GitLab services..."
    
    docker compose restart gitlab
    
    sleep 30
    
    if check_containers && check_gitlab_health; then
        log "✓ Services restarted successfully"
    else
        error "✗ Service restart may have issues"
    fi
}

cleanup_resources() {
    log "Cleaning up unused Docker resources..."
    
    # Clean up unused containers, networks, images
    docker system prune -f
    
    # Clean up old GitLab logs (keep last 7 days)
    log "Cleaning up old GitLab logs..."
    docker exec gitlab find /var/log/gitlab -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    # Clean up old backup files
    log "Cleaning up old backups..."
    find ./backups -name "*_gitlab_backup.tar" -mtime +7 -delete 2>/dev/null || true
    
    log "✓ Cleanup completed"
}

run_complete_check() {
    log "Running complete GitLab health check..."
    echo ""
    
    check_containers || return 1
    check_gitlab_health || return 1
    check_connectivity
    check_metrics_issues
    check_memory_usage
    
    log "Health check completed!"
    echo ""
    info "If you found issues, try:"
    info "  - $0 fix-shm     (for shared memory issues)"
    info "  - $0 reconfigure (for configuration issues)"  
    info "  - $0 restart     (for service issues)"
    info "  - $0 cleanup     (for resource issues)"
}

# Main script logic
case "${1:-check}" in
    "check")
        run_complete_check
        ;;
    "status")
        check_containers
        ;;
    "logs")
        show_recent_logs
        ;;
    "metrics")
        check_metrics_issues
        ;;
    "memory")
        check_memory_usage
        ;;
    "fix-shm")
        fix_shared_memory
        ;;
    "reconfigure")
        reconfigure_gitlab
        ;;
    "restart")
        restart_services
        ;;
    "cleanup")
        cleanup_resources
        ;;
    "help"|*)
        show_help
        ;;
esac
