#!/bin/bash

# GitLab Runner Registration Script
# Usage: ./register-runner.sh [runner_type]

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
    echo -e "${BLUE}GitLab Runner Registration${NC}"
    echo ""
    echo "Usage: $0 [runner_type]"
    echo ""
    echo "Runner Types:"
    echo "  docker     Register Docker executor runner (default)"
    echo "  shell      Register Shell executor runner"
    echo "  both       Register both Docker and Shell runners"
    echo "  remove     Remove all registered runners"
    echo "  list       List all registered runners"
    echo "  status     Show runner status"
    echo ""
    echo "Examples:"
    echo "  $0 docker"
    echo "  $0 both"
    echo "  $0 remove"
    echo ""
}

get_registration_token() {
    info "Getting registration token from GitLab..."
    
    # Wait for GitLab to be ready
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "http://localhost:8088/-/health" > /dev/null 2>&1; then
            log "✓ GitLab is ready"
            break
        else
            warning "Waiting for GitLab to be ready... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "GitLab is not accessible after $max_attempts attempts"
        error "Please check if GitLab is running: docker ps | grep gitlab"
        return 1
    fi
    
    echo ""
    warning "To get the registration token:"
    echo "1. Open GitLab web interface: $(grep GITLAB_URL .env | cut -d'=' -f2)"
    echo "2. Login as admin (root)"
    echo "3. Go to Admin Area > CI/CD > Runners"
    echo "4. Copy the registration token from 'Register an instance runner' section"
    echo ""
    read -p "Enter GitLab registration token: " registration_token
    
    if [ -z "$registration_token" ]; then
        error "Registration token is required!"
        return 1
    fi
    
    echo "$registration_token"
}

register_docker_runner() {
    local token="$1"
    
    log "Registering Docker executor runner..."
    
    # Get GitLab URL from .env
    local gitlab_url=$(grep GITLAB_URL .env | cut -d'=' -f2)
    
    # Register runner
    if docker exec gitlab-runner gitlab-runner register \
        --non-interactive \
        --url "http://gitlab:80/" \
        --registration-token "$token" \
        --executor "docker" \
        --docker-image "alpine:latest" \
        --docker-network "gitlab_net" \
        --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
        --docker-volumes "/cache" \
        --docker-memory "1g" \
        --docker-cpus "1.0" \
        --description "Docker Runner (On-Premise)" \
        --tag-list "docker,on-premise,linux" \
        --run-untagged="true" \
        --locked="false" \
        --access-level="not_protected" \
        --docker-privileged="false" \
        --docker-security-opt "no-new-privileges:true" \
        --limit 1; then
        
        log "✓ Docker runner registered successfully"
        return 0
    else
        error "✗ Failed to register Docker runner"
        return 1
    fi
}

register_shell_runner() {
    local token="$1"
    
    log "Registering Shell executor runner..."
    
    # Register runner
    if docker exec gitlab-runner gitlab-runner register \
        --non-interactive \
        --url "http://gitlab:80/" \
        --registration-token "$token" \
        --executor "shell" \
        --description "Shell Runner (On-Premise)" \
        --tag-list "shell,on-premise,local" \
        --run-untagged="false" \
        --locked="false" \
        --access-level="not_protected" \
        --limit 1; then
        
        log "✓ Shell runner registered successfully"
        return 0
    else
        error "✗ Failed to register Shell runner"
        return 1
    fi
}

remove_all_runners() {
    warning "Removing all registered runners..."
    
    read -p "Are you sure? This will remove ALL runners! (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled"
        return 0
    fi
    
    # Stop gitlab-runner service
    docker exec gitlab-runner gitlab-runner stop || true
    
    # Remove all runners
    if docker exec gitlab-runner rm -f /etc/gitlab-runner/config.toml; then
        log "✓ All runners removed"
        
        # Restart runner service
        docker compose restart gitlab-runner
        log "✓ Runner service restarted"
    else
        error "✗ Failed to remove runners"
        return 1
    fi
}

list_runners() {
    info "Registered runners:"
    echo ""
    
    if docker exec gitlab-runner gitlab-runner list 2>/dev/null; then
        echo ""
        log "✓ Runner list retrieved"
    else
        warning "No runners registered or runner service not accessible"
        info "To register runners, use: $0 docker"
    fi
}

show_runner_status() {
    info "GitLab Runner status:"
    echo ""
    
    # Check if runner container is running
    if docker ps | grep -q "gitlab-runner"; then
        log "✓ GitLab Runner container is running"
        
        # Check runner service status
        if docker exec gitlab-runner gitlab-runner status 2>/dev/null; then
            log "✓ Runner service is active"
        else
            warning "⚠ Runner service might have issues"
        fi
        
        echo ""
        info "Runner configuration:"
        docker exec gitlab-runner cat /etc/gitlab-runner/config.toml 2>/dev/null | head -20
        
    else
        error "✗ GitLab Runner container is not running"
        info "Start it with: docker compose up -d gitlab-runner"
    fi
}

verify_setup() {
    log "Verifying GitLab Runner setup..."
    
    # Check if containers are running
    if ! docker ps | grep -q "gitlab-runner"; then
        error "GitLab Runner container is not running"
        info "Start it with: docker compose up -d gitlab-runner"
        return 1
    fi
    
    if ! docker ps | grep -q "gitlab"; then
        error "GitLab container is not running"
        info "Start it with: docker compose up -d gitlab"
        return 1
    fi
    
    # Check if runner can access GitLab
    if docker exec gitlab-runner ping -c 1 gitlab > /dev/null 2>&1; then
        log "✓ Runner can communicate with GitLab"
    else
        warning "⚠ Runner cannot reach GitLab container"
        warning "Check network configuration"
    fi
    
    # Check if Docker socket is accessible
    if docker exec gitlab-runner docker version > /dev/null 2>&1; then
        log "✓ Runner can access Docker"
    else
        warning "⚠ Runner cannot access Docker socket"
        warning "This might affect Docker executor functionality"
    fi
    
    log "Setup verification completed"
}

# Main script logic
case "${1:-docker}" in
    "docker")
        verify_setup || exit 1
        token=$(get_registration_token) || exit 1
        register_docker_runner "$token"
        ;;
    "shell")
        verify_setup || exit 1
        token=$(get_registration_token) || exit 1
        register_shell_runner "$token"
        ;;
    "both")
        verify_setup || exit 1
        token=$(get_registration_token) || exit 1
        register_docker_runner "$token"
        register_shell_runner "$token"
        ;;
    "remove")
        remove_all_runners
        ;;
    "list")
        list_runners
        ;;
    "status")
        show_runner_status
        ;;
    "verify")
        verify_setup
        ;;
    "help"|*)
        show_help
        ;;
esac

# Show final status
echo ""
info "Current runners:"
list_runners
