#!/bin/bash

# GitLab Admin Management Script
# Usage: ./admin-manager.sh [command] [options]

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
    echo -e "${BLUE}GitLab Admin Management${NC}"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  get-password        Get initial root password"
    echo "  reset-password      Reset root password"
    echo "  create-admin        Create new admin user"
    echo "  list-admins         List all admin users"
    echo "  grant-admin         Grant admin privileges to user"
    echo "  revoke-admin        Revoke admin privileges from user"
    echo "  user-info          Show user information"
    echo "  console            Open GitLab Rails console"
    echo ""
    echo "Examples:"
    echo "  $0 get-password"
    echo "  $0 reset-password"
    echo "  $0 create-admin newadmin admin@company.com"
    echo "  $0 grant-admin username"
    echo "  $0 user-info username"
    echo ""
}

check_gitlab() {
    if ! docker ps | grep -q "gitlab.*Up"; then
        error "GitLab container is not running"
        info "Start GitLab with: docker compose up -d"
        return 1
    fi
    return 0
}

wait_for_gitlab() {
    log "Waiting for GitLab to be ready..."
    local timeout=300
    local counter=0
    
    while [ $counter -lt $timeout ]; do
        if docker exec gitlab gitlab-rails runner "puts 'GitLab is ready'" 2>/dev/null | grep -q "GitLab is ready"; then
            log "✓ GitLab is ready"
            return 0
        fi
        
        echo -n "."
        sleep 5
        counter=$((counter + 5))
    done
    
    error "GitLab is not ready after $timeout seconds"
    return 1
}

get_initial_password() {
    log "Getting initial root password..."
    
    # Method 1: Check from environment variable
    if [ -f ".env" ] && grep -q "GITLAB_ROOT_PASSWORD" .env; then
        local env_password=$(grep "GITLAB_ROOT_PASSWORD" .env | cut -d'=' -f2 | tr -d '"'"'"' ')
        if [ -n "$env_password" ] && [ "$env_password" != "YourSecurePassword123!" ]; then
            echo -e "${GREEN}Root password from .env:${NC} $env_password"
            warning "Remember to change this password for security!"
            return 0
        fi
    fi
    
    # Method 2: Check from logs
    local password=$(docker logs gitlab 2>&1 | grep -A1 "Password:" | tail -1 | tr -d '\r\n ')
    
    if [ -n "$password" ] && [ "$password" != "Password:" ]; then
        echo -e "${GREEN}Initial root password:${NC} $password"
        return 0
    fi
    
    # Method 3: Check from file
    if docker exec gitlab test -f /etc/gitlab/initial_root_password; then
        password=$(docker exec gitlab cat /etc/gitlab/initial_root_password | grep -v "^#" | tr -d '\r\n ')
        if [ -n "$password" ]; then
            echo -e "${GREEN}Initial root password:${NC} $password"
            return 0
        fi
    fi
    
    warning "Could not find initial root password"
    info "You may need to reset the password using: $0 reset-password"
}

reset_root_password() {
    log "Resetting root password..."
    
    read -s -p "Enter new password for root: " new_password
    echo
    read -s -p "Confirm password: " confirm_password
    echo
    
    if [ "$new_password" != "$confirm_password" ]; then
        error "Passwords do not match"
        return 1
    fi
    
    if [ ${#new_password} -lt 8 ]; then
        error "Password must be at least 8 characters long"
        return 1
    fi
    
    log "Updating root password..."
    
    local result=$(docker exec -i gitlab gitlab-rails console << EOF
user = User.find_by(username: 'root')
if user
  user.password = '$new_password'
  user.password_confirmation = '$new_password'
  if user.save!
    puts 'SUCCESS: Root password updated'
  else
    puts 'ERROR: Failed to update password'
  end
else
  puts 'ERROR: Root user not found'
end
EOF
)
    
    if echo "$result" | grep -q "SUCCESS"; then
        log "✓ Root password updated successfully"
    else
        error "Failed to update root password"
        echo "$result"
        return 1
    fi
}

create_admin_user() {
    local username="$1"
    local email="$2"
    local name="$3"
    
    if [ -z "$username" ] || [ -z "$email" ]; then
        error "Usage: $0 create-admin <username> <email> [name]"
        return 1
    fi
    
    if [ -z "$name" ]; then
        name="$username"
    fi
    
    read -s -p "Enter password for $username: " password
    echo
    read -s -p "Confirm password: " confirm_password
    echo
    
    if [ "$password" != "$confirm_password" ]; then
        error "Passwords do not match"
        return 1
    fi
    
    log "Creating admin user: $username"
    
    local result=$(docker exec -i gitlab gitlab-rails console << EOF
if User.find_by(username: '$username')
  puts 'ERROR: User already exists'
else
  user = User.create!(
    username: '$username',
    email: '$email',
    name: '$name',
    password: '$password',
    password_confirmation: '$password',
    admin: true,
    confirmed_at: Time.now,
    state: 'active'
  )
  puts "SUCCESS: Admin user created - #{user.username} (#{user.email})"
end
EOF
)
    
    if echo "$result" | grep -q "SUCCESS"; then
        log "✓ Admin user created successfully"
        echo "$result" | grep "SUCCESS"
    else
        error "Failed to create admin user"
        echo "$result"
        return 1
    fi
}

list_admin_users() {
    log "Listing all admin users..."
    
    docker exec -i gitlab gitlab-rails console << 'EOF'
puts "Admin Users:"
puts "-" * 80
puts "Username".ljust(20) + "Email".ljust(30) + "Name".ljust(25) + "State"
puts "-" * 80

User.where(admin: true).each do |user|
  puts user.username.ljust(20) + user.email.ljust(30) + user.name.ljust(25) + user.state
end
EOF
}

grant_admin_privileges() {
    local username="$1"
    
    if [ -z "$username" ]; then
        error "Usage: $0 grant-admin <username>"
        return 1
    fi
    
    log "Granting admin privileges to: $username"
    
    local result=$(docker exec -i gitlab gitlab-rails console << EOF
user = User.find_by(username: '$username')
if user
  user.admin = true
  if user.save!
    puts "SUCCESS: Admin privileges granted to #{user.username}"
  else
    puts "ERROR: Failed to grant admin privileges"
  end
else
  puts 'ERROR: User not found'
end
EOF
)
    
    if echo "$result" | grep -q "SUCCESS"; then
        log "✓ Admin privileges granted successfully"
    else
        error "Failed to grant admin privileges"
        echo "$result"
        return 1
    fi
}

revoke_admin_privileges() {
    local username="$1"
    
    if [ -z "$username" ]; then
        error "Usage: $0 revoke-admin <username>"
        return 1
    fi
    
    if [ "$username" = "root" ]; then
        warning "Are you sure you want to revoke admin privileges from root user?"
        read -p "Type 'yes' to confirm: " confirm
        if [ "$confirm" != "yes" ]; then
            log "Operation cancelled"
            return 0
        fi
    fi
    
    log "Revoking admin privileges from: $username"
    
    local result=$(docker exec -i gitlab gitlab-rails console << EOF
user = User.find_by(username: '$username')
if user
  user.admin = false
  if user.save!
    puts "SUCCESS: Admin privileges revoked from #{user.username}"
  else
    puts "ERROR: Failed to revoke admin privileges"
  end
else
  puts 'ERROR: User not found'
end
EOF
)
    
    if echo "$result" | grep -q "SUCCESS"; then
        log "✓ Admin privileges revoked successfully"
    else
        error "Failed to revoke admin privileges"
        echo "$result"
        return 1
    fi
}

show_user_info() {
    local username="$1"
    
    if [ -z "$username" ]; then
        error "Usage: $0 user-info <username>"
        return 1
    fi
    
    log "Getting user information for: $username"
    
    docker exec -i gitlab gitlab-rails console << EOF
user = User.find_by(username: '$username')
if user
  puts "User Information:"
  puts "-" * 50
  puts "Username: #{user.username}"
  puts "Email: #{user.email}"
  puts "Name: #{user.name}"
  puts "Admin: #{user.admin? ? 'Yes' : 'No'}"
  puts "State: #{user.state}"
  puts "Created: #{user.created_at}"
  puts "Last Sign-in: #{user.last_sign_in_at || 'Never'}"
  puts "Confirmed: #{user.confirmed? ? 'Yes' : 'No'}"
  puts "Two-factor: #{user.two_factor_enabled? ? 'Enabled' : 'Disabled'}"
else
  puts 'ERROR: User not found'
end
EOF
}

open_console() {
    log "Opening GitLab Rails console..."
    info "Type 'exit' to quit the console"
    echo
    docker exec -it gitlab gitlab-rails console
}

# Check if GitLab is running
if ! check_gitlab; then
    exit 1
fi

# Main script logic
case "${1:-help}" in
    "get-password")
        get_initial_password
        ;;
    "reset-password")
        wait_for_gitlab && reset_root_password
        ;;
    "create-admin")
        wait_for_gitlab && create_admin_user "$2" "$3" "$4"
        ;;
    "list-admins")
        wait_for_gitlab && list_admin_users
        ;;
    "grant-admin")
        wait_for_gitlab && grant_admin_privileges "$2"
        ;;
    "revoke-admin")
        wait_for_gitlab && revoke_admin_privileges "$2"
        ;;
    "user-info")
        wait_for_gitlab && show_user_info "$2"
        ;;
    "console")
        wait_for_gitlab && open_console
        ;;
    "help"|*)
        show_help
        ;;
esac
