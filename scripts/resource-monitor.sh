#!/bin/bash

# GitLab Resource Monitor & Auto-scaling Script
# Usage: ./resource-monitor.sh [command]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MEMORY_THRESHOLD=80  # Ngưỡng RAM cảnh báo (%)
CPU_THRESHOLD=80     # Ngưỡng CPU cảnh báo (%)
DISK_THRESHOLD=85    # Ngưỡng disk cảnh báo (%)

# Functions
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

show_help() {
    echo -e "${BLUE}GitLab Resource Monitor${NC}"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  monitor        Real-time resource monitoring"
    echo "  check          One-time resource check"
    echo "  optimize       Auto-optimize based on current usage"
    echo "  scale-down     Reduce resource allocation"
    echo "  scale-up       Increase resource allocation"
    echo "  limits         Show current resource limits"
    echo "  usage          Show current resource usage"
    echo "  ci-stats       Show CI/CD job statistics"
    echo "  cleanup        Clean up resources"
    echo ""
}

get_container_stats() {
    local container=$1
    if docker ps | grep -q "$container"; then
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" | grep "$container"
    else
        echo "Container $container is not running"
    fi
}

check_resource_usage() {
    info "Current resource usage:"
    echo ""
    
    # Container stats
    info "Container resource usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep -E "(gitlab|NAME)"
    echo ""
    
    # System resources
    info "System resource usage:"
    
    # Memory
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    echo "Memory: ${mem_usage}%"
    if (( $(echo "$mem_usage > $MEMORY_THRESHOLD" | bc -l) )); then
        warning "Memory usage is high: ${mem_usage}%"
    fi
    
    # CPU (using top)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo "CPU: ${cpu_usage}%"
    if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) 2>/dev/null )); then
        warning "CPU usage is high: ${cpu_usage}%"
    fi
    
    # Disk
    local disk_usage=$(df -h . | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    echo "Disk: ${disk_usage}%"
    if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
        warning "Disk usage is high: ${disk_usage}%"
    fi
    
    echo ""
}

show_current_limits() {
    info "Current resource limits from .env:"
    echo ""
    
    grep -E "(MEMORY_LIMIT|CPU_LIMIT|WORKERS|CONCURRENCY)" .env | while read line; do
        echo "  $line"
    done
    
    echo ""
    info "Docker container limits:"
    
    # GitLab container limits
    if docker ps | grep -q "gitlab"; then
        echo "GitLab container:"
        docker inspect gitlab | jq -r '.[] | .HostConfig | "  Memory: \(.Memory // "unlimited"), CPUs: \(.CpuQuota // "unlimited")"' 2>/dev/null || echo "  Could not retrieve limits"
    fi
    
    # Runner container limits  
    if docker ps | grep -q "gitlab-runner"; then
        echo "GitLab Runner container:"
        docker inspect gitlab-runner | jq -r '.[] | .HostConfig | "  Memory: \(.Memory // "unlimited"), CPUs: \(.CpuQuota // "unlimited")"' 2>/dev/null || echo "  Could not retrieve limits"
    fi
    
    echo ""
}

get_ci_stats() {
    info "CI/CD Job Statistics:"
    echo ""
    
    if docker exec gitlab gitlab-rails runner "puts Job.where('created_at > ?', 24.hours.ago).group(:status).count" 2>/dev/null; then
        log "✓ Retrieved job stats from last 24 hours"
    else
        warning "Could not retrieve CI/CD job statistics"
        warning "Make sure GitLab is running and accessible"
    fi
    
    echo ""
    info "Running jobs:"
    if docker exec gitlab gitlab-rails runner "Job.running.find_each { |job| puts \"Project: #{job.project.name}, Job: #{job.name}, Duration: #{Time.current - job.started_at}s\" }" 2>/dev/null; then
        log "✓ Listed running jobs"
    else
        info "No running jobs or could not access job data"
    fi
    
    echo ""
}

auto_optimize() {
    info "Analyzing current usage for optimization..."
    
    # Get current memory usage
    local mem_usage=$(docker stats --no-stream --format "{{.MemPerc}}" gitlab | cut -d'.' -f1 2>/dev/null || echo "0")
    local cpu_usage=$(docker stats --no-stream --format "{{.CPUPerc}}" gitlab | cut -d'.' -f1 2>/dev/null || echo "0")
    
    info "Current GitLab usage: Memory ${mem_usage}%, CPU ${cpu_usage}%"
    
    # Suggest optimizations
    if [ "$mem_usage" -gt "70" ]; then
        warning "High memory usage detected. Suggestions:"
        echo "  - Reduce PUMA_WORKERS (current: $(grep PUMA_WORKERS .env | cut -d'=' -f2))"
        echo "  - Reduce SIDEKIQ_CONCURRENCY (current: $(grep SIDEKIQ_CONCURRENCY .env | cut -d'=' -f2))"
        echo "  - Increase GITLAB_MEMORY_LIMIT if needed"
    elif [ "$mem_usage" -lt "30" ]; then
        info "Low memory usage detected. Consider:"
        echo "  - Increasing PUMA_WORKERS for better performance"
        echo "  - Reducing GITLAB_MEMORY_LIMIT to free up system resources"
    fi
    
    if [ "$cpu_usage" -gt "70" ]; then
        warning "High CPU usage detected. Suggestions:"
        echo "  - Reduce concurrent CI/CD jobs"
        echo "  - Increase PROMETHEUS_SCRAPE_INTERVAL"
        echo "  - Check for resource-intensive jobs"
    fi
    
    # Check CI/CD load
    local running_jobs=$(docker exec gitlab gitlab-rails runner "puts Job.running.count" 2>/dev/null || echo "0")
    if [ "$running_jobs" -gt "3" ]; then
        warning "High CI/CD load: $running_jobs running jobs"
        echo "  - Consider increasing runner resources"
        echo "  - Or limiting concurrent jobs in runner config"
    fi
}

scale_down() {
    warning "Scaling down GitLab resources..."
    
    # Create backup of current .env
    cp .env .env.backup.$(date +%s)
    
    # Reduce resources
    sed -i 's/PUMA_WORKERS=.*/PUMA_WORKERS=1/' .env
    sed -i 's/SIDEKIQ_CONCURRENCY=.*/SIDEKIQ_CONCURRENCY=2/' .env
    sed -i 's/POSTGRES_MAX_CONNECTIONS=.*/POSTGRES_MAX_CONNECTIONS=30/' .env
    sed -i 's/GITLAB_MEMORY_LIMIT=.*/GITLAB_MEMORY_LIMIT=4G/' .env
    sed -i 's/GITLAB_CPU_LIMIT=.*/GITLAB_CPU_LIMIT=2/' .env
    
    log "Resources scaled down. Restart GitLab to apply changes:"
    echo "  docker compose restart gitlab"
}

scale_up() {
    info "Scaling up GitLab resources..."
    
    # Create backup of current .env
    cp .env .env.backup.$(date +%s)
    
    # Increase resources
    sed -i 's/PUMA_WORKERS=.*/PUMA_WORKERS=4/' .env
    sed -i 's/SIDEKIQ_CONCURRENCY=.*/SIDEKIQ_CONCURRENCY=8/' .env
    sed -i 's/POSTGRES_MAX_CONNECTIONS=.*/POSTGRES_MAX_CONNECTIONS=100/' .env
    sed -i 's/GITLAB_MEMORY_LIMIT=.*/GITLAB_MEMORY_LIMIT=8G/' .env
    sed -i 's/GITLAB_CPU_LIMIT=.*/GITLAB_CPU_LIMIT=6/' .env
    
    log "Resources scaled up. Restart GitLab to apply changes:"
    echo "  docker compose restart gitlab"
}

cleanup_resources() {
    log "Cleaning up GitLab resources..."
    
    # Clean up old logs
    info "Cleaning old logs..."
    docker exec gitlab find /var/log/gitlab -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    # Clean up old CI artifacts
    info "Cleaning old CI artifacts..."
    docker exec gitlab gitlab-rails runner "Ci::JobArtifact.where('created_at < ?', 30.days.ago).find_each(&:destroy)" 2>/dev/null || warning "Could not clean old artifacts"
    
    # Clean up docker resources
    info "Cleaning Docker resources..."
    docker system prune -f
    
    # Clean up GitLab traces
    info "Cleaning old job traces..."
    docker exec gitlab gitlab-rails runner "Ci::Build.where('created_at < ?', 30.days.ago).update_all(trace: nil)" 2>/dev/null || warning "Could not clean old traces"
    
    log "Resource cleanup completed"
}

monitor_resources() {
    log "Starting real-time resource monitoring (Press Ctrl+C to stop)..."
    echo ""
    
    while true; do
        clear
        echo -e "${BLUE}=== GitLab Resource Monitor - $(date) ===${NC}"
        echo ""
        
        check_resource_usage
        
        echo ""
        info "Container details:"
        get_container_stats "gitlab"
        get_container_stats "gitlab-runner"
        
        echo ""
        info "Press Ctrl+C to stop monitoring..."
        
        sleep 5
    done
}

# Main script logic
case "${1:-check}" in
    "monitor")
        monitor_resources
        ;;
    "check")
        check_resource_usage
        ;;
    "optimize")
        auto_optimize
        ;;
    "scale-down")
        scale_down
        ;;
    "scale-up")
        scale_up
        ;;
    "limits")
        show_current_limits
        ;;
    "usage")
        check_resource_usage
        ;;
    "ci-stats")
        get_ci_stats
        ;;
    "cleanup")
        cleanup_resources
        ;;
    "help"|*)
        show_help
        ;;
esac
