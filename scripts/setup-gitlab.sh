#!/bin/bash

# GitLab Complete Setup Script
# Usage: ./setup-gitlab.sh

set -e

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
step() { echo -e "${PURPLE}[STEP]${NC} $1"; }
success() { echo -e "${CYAN}[SUCCESS]${NC} $1"; }

show_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   GitLab On-Premise Setup                   ║"
    echo "║              Complete Docker-based Solution                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

check_requirements() {
    step "Checking system requirements..."
    
    # Check Docker
    if command -v docker &> /dev/null; then
        log "✓ Docker is installed"
        docker --version
    else
        error "✗ Docker is not installed"
        error "Please install Docker first: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker Compose
    if command -v docker compose &> /dev/null || command -v docker-compose &> /dev/null; then
        log "✓ Docker Compose is available"
        docker compose version 2>/dev/null || docker-compose version
    else
        error "✗ Docker Compose is not available"
        error "Please install Docker Compose"
        exit 1
    fi
    
    # Check available memory
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$mem_gb" -ge 4 ]; then
        log "✓ System memory: ${mem_gb}GB (sufficient)"
    else
        warning "⚠ System memory: ${mem_gb}GB (recommended: 8GB+)"
        warning "GitLab may run slowly with limited memory"
    fi
    
    # Check available disk space
    local disk_gb=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$disk_gb" -ge 20 ]; then
        log "✓ Available disk space: ${disk_gb}GB (sufficient)"
    else
        warning "⚠ Available disk space: ${disk_gb}GB (recommended: 50GB+)"
    fi
    
    echo ""
}

setup_environment() {
    step "Setting up environment configuration..."
    
    # Check if .env exists
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            log "Creating .env from .env.example"
            cp .env.example .env
        else
            warning ".env file not found, using default configuration"
        fi
    else
        log "✓ .env file already exists"
    fi
    
    # Display current configuration
    info "Current configuration:"
    echo "  GitLab URL: $(grep GITLAB_URL .env | cut -d'=' -f2 || echo 'Not set')"
    echo "  HTTP Port: $(grep GITLAB_HTTP_PORT .env | cut -d'=' -f2 || echo 'Not set')"
    echo "  SSH Port: $(grep GITLAB_SSH_PORT .env | cut -d'=' -f2 || echo 'Not set')"
    echo ""
    
    # Ask if user wants to modify configuration
    read -p "Do you want to modify the configuration? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Edit .env file and run this script again"
        exit 0
    fi
    
    echo ""
}

start_gitlab() {
    step "Starting GitLab services..."
    
    # Create necessary directories
    log "Creating data directories..."
    mkdir -p data/config data/logs data/data backups config
    
    # Start services
    log "Starting Docker containers..."
    if docker compose up -d; then
        success "✓ GitLab containers started successfully"
    else
        error "✗ Failed to start GitLab containers"
        exit 1
    fi
    
    # Wait for GitLab to initialize
    log "Waiting for GitLab to initialize (this may take 3-5 minutes)..."
    
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "http://localhost:$(grep GITLAB_HTTP_PORT .env | cut -d'=' -f2)/-/health" > /dev/null 2>&1; then
            success "✓ GitLab is ready!"
            break
        else
            echo -n "."
            sleep 5
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        warning "⚠ GitLab initialization is taking longer than expected"
        warning "You can check the progress with: docker logs -f gitlab"
    fi
    
    echo ""
}

setup_runner() {
    step "Setting up GitLab Runner..."
    
    # Check if runner container is running
    if docker ps | grep -q "gitlab-runner"; then
        log "✓ GitLab Runner container is running"
        
        # Ask if user wants to register runner
        read -p "Do you want to register GitLab Runner now? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            info "Starting runner registration process..."
            echo ""
            warning "You will need the registration token from GitLab Admin Area"
            warning "Go to: Admin Area > CI/CD > Runners"
            echo ""
            
            if bash scripts/register-runner.sh docker; then
                success "✓ GitLab Runner registered successfully"
            else
                warning "⚠ Runner registration skipped or failed"
                info "You can register later with: ./scripts/register-runner.sh docker"
            fi
        else
            info "Runner registration skipped"
            info "You can register later with: ./scripts/register-runner.sh docker"
        fi
    else
        warning "⚠ GitLab Runner container is not running"
        info "Start it with: docker compose up -d gitlab-runner"
    fi
    
    echo ""
}

show_access_info() {
    step "Setup completed! Access information:"
    echo ""
    
    local gitlab_url=$(grep GITLAB_URL .env | cut -d'=' -f2)
    local gitlab_port=$(grep GITLAB_HTTP_PORT .env | cut -d'=' -f2)
    
    success "🌐 GitLab Web Interface:"
    echo "   URL: $gitlab_url"
    echo "   Alternative: http://localhost:$gitlab_port"
    echo ""
    
    success "🔑 Initial Login:"
    echo "   Username: root"
    echo "   Password: Check with command below:"
    echo "   docker logs gitlab 2>&1 | grep -A2 -B2 'Password:'"
    echo ""
    
    success "🏃‍♂️ GitLab Runner:"
    echo "   Status: ./scripts/register-runner.sh status"
    echo "   Register: ./scripts/register-runner.sh docker"
    echo ""
    
    success "📊 Management Commands:"
    echo "   Health check: ./scripts/gitlab-health.sh check"
    echo "   Resource monitor: ./scripts/resource-monitor.sh check"
    echo "   Backup: ./scripts/backup.sh"
    echo "   View logs: docker logs -f gitlab"
    echo ""
}

show_next_steps() {
    step "Next steps:"
    echo ""
    
    info "1. 🔐 Change default root password"
    echo "   - Login to GitLab web interface"
    echo "   - Go to Profile > Password"
    echo ""
    
    info "2. 🏃‍♂️ Register GitLab Runner (if not done)"
    echo "   - Get registration token from Admin Area > CI/CD > Runners"
    echo "   - Run: ./scripts/register-runner.sh docker"
    echo ""
    
    info "3. 📧 Configure SMTP (optional)"
    echo "   - Edit SMTP settings in .env file"
    echo "   - Restart: docker compose restart gitlab"
    echo ""
    
    info "4. 🔒 Setup SSL/HTTPS (recommended for production)"
    echo "   - Configure SSL certificates"
    echo "   - Update nginx configuration"
    echo ""
    
    info "5. 📚 Read documentation"
    echo "   - GitLab Runner: docs/GITLAB_RUNNER_GUIDE.md"
    echo "   - Configuration: docs/CONFIG_GUIDE.md"
    echo "   - Troubleshooting: docs/TROUBLESHOOTING.md"
    echo ""
}

verify_setup() {
    step "Verifying setup..."
    
    # Check containers
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(gitlab|gitlab-runner|gitlab-backup)"; then
        log "✓ All containers are running"
    else
        warning "⚠ Some containers may not be running"
    fi
    
    echo ""
    
    # Check health
    if [ -f "scripts/gitlab-health.sh" ]; then
        log "Running health check..."
        bash scripts/gitlab-health.sh check || true
    fi
    
    echo ""
}

main() {
    show_banner
    
    check_requirements
    setup_environment
    start_gitlab
    setup_runner
    verify_setup
    show_access_info
    show_next_steps
    
    echo ""
    success "🎉 GitLab setup completed successfully!"
    echo ""
    warning "📝 Important: Save your root password and registration tokens!"
    echo ""
}

# Run main function
main "$@"
