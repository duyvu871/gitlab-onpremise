# 📋 Hướng dẫn cấu hình GitLab On-Premise

Tài liệu này hướng dẫn chi tiết cách cấu hình và tùy chỉnh GitLab CE trên Docker cho môi trường on-premise.

> 👨‍💼 **Cần hướng dẫn về tài khoản admin?** Xem [Admin Guide](ADMIN_GUIDE.md)

---

## 🔧 Cấu hình biến môi trường (.env)

### Các biến môi trường cơ bản

```env
# Domain chính của GitLab
GITLAB_HOST=gitlab.ssit.company.com

# URL truy cập GitLab
GITLAB_URL=http://gitlab.ssit.company.com:8088

# Domain SSH riêng (khuyến nghị)
GITLAB_SSH_HOST=ssh.gitlab.ssit.company.com

# Port HTTP cho GitLab
GITLAB_HTTP_PORT=8088

# Port SSH cho GitLab
GITLAB_SSH_PORT=2222

# Cấu hình Admin
GITLAB_ROOT_PASSWORD=YourSecurePassword123!  # Mật khẩu root (thay đổi ngay!)
GITLAB_ROOT_EMAIL=admin@ssit.company.com      # Email của admin

# Cấu hình backup
BACKUP_SCHEDULE=0 2 * * *  # Backup hàng ngày lúc 2:00 AM
BACKUP_RETENTION_DAYS=7    # Giữ backup trong 7 ngày
BACKUP_PATH=./backups      # Thư mục lưu backup
```

> ⚠️ **Bảo mật**: Thay đổi `GITLAB_ROOT_PASSWORD` ngay lập tức sau khi cài đặt!

### Cấu hình SMTP (Email)

Thêm các biến sau vào `.env` để cấu hình email:

```env
# SMTP Configuration
SMTP_ENABLE=true
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USER_NAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_DOMAIN=gmail.com
SMTP_AUTHENTICATION=login
SMTP_ENABLE_STARTTLS_AUTO=true
SMTP_TLS=false
```

### Cấu hình LDAP/Active Directory

```env
# LDAP Configuration
LDAP_ENABLED=false
LDAP_HOST=ldap.company.com
LDAP_PORT=389
LDAP_UID=sAMAccountName
LDAP_METHOD=plain
LDAP_BASE=dc=company,dc=com
LDAP_USER_FILTER=
LDAP_BIND_DN=cn=gitlab,cn=users,dc=company,dc=com
LDAP_PASSWORD=ldap-password
```

---

## 🐳 Cấu hình Docker Compose

### Giải thích các service

#### 1. GitLab Service
- **Image**: `gitlab/gitlab-ce:16.3.4-ce.0`
- **Volumes**: 
  - `./data/config:/etc/gitlab` - Cấu hình GitLab
  - `./data/logs:/var/log/gitlab` - Log files
  - `./data/data:/var/opt/gitlab` - Data và repositories
- **Ports**:
  - `${GITLAB_HTTP_PORT}:80` - HTTP access
  - `${GITLAB_SSH_PORT}:22` - SSH access

#### 2. Backup Service
- **Image**: `gitlab/gitlab-ce:16.3.4-ce.0`
- **Purpose**: Tự động backup định kỳ
- **Schedule**: Chạy theo cron job

### Cấu hình nâng cao trong gitlab.rb

Tạo file `config/gitlab.rb` để override cấu hình:

```ruby
# External URL
external_url ENV['GITLAB_URL']

# SSH settings
gitlab_rails['gitlab_ssh_host'] = ENV['GITLAB_SSH_HOST']
gitlab_rails['gitlab_shell_ssh_port'] = ENV['GITLAB_SSH_PORT'].to_i

# Backup settings
gitlab_rails['backup_keep_time'] = 604800  # 7 days
gitlab_rails['backup_path'] = "/var/opt/gitlab/backups"

# Performance tuning
unicorn['worker_processes'] = 2
unicorn['worker_timeout'] = 60

# Memory settings (cho server nhỏ)
postgresql['shared_buffers'] = "256MB"
postgresql['max_worker_processes'] = 8

# Email settings (nếu dùng SMTP)
gitlab_rails['smtp_enable'] = ENV['SMTP_ENABLE'] == 'true'
gitlab_rails['smtp_address'] = ENV['SMTP_ADDRESS']
gitlab_rails['smtp_port'] = ENV['SMTP_PORT'].to_i
gitlab_rails['smtp_user_name'] = ENV['SMTP_USER_NAME']
gitlab_rails['smtp_password'] = ENV['SMTP_PASSWORD']
gitlab_rails['smtp_domain'] = ENV['SMTP_DOMAIN']
gitlab_rails['smtp_authentication'] = ENV['SMTP_AUTHENTICATION']
gitlab_rails['smtp_enable_starttls_auto'] = ENV['SMTP_ENABLE_STARTTLS_AUTO'] == 'true'
gitlab_rails['smtp_tls'] = ENV['SMTP_TLS'] == 'true'

gitlab_rails['gitlab_email_from'] = ENV['SMTP_USER_NAME']
gitlab_rails['gitlab_email_reply_to'] = ENV['SMTP_USER_NAME']

# LDAP settings (nếu dùng)
gitlab_rails['ldap_enabled'] = ENV['LDAP_ENABLED'] == 'true'
gitlab_rails['ldap_servers'] = YAML.load <<-'EOS'
  main:
    label: 'LDAP'
    host: ENV['LDAP_HOST']
    port: ENV['LDAP_PORT'].to_i
    uid: ENV['LDAP_UID']
    method: ENV['LDAP_METHOD']
    bind_dn: ENV['LDAP_BIND_DN']
    password: ENV['LDAP_PASSWORD']
    encryption: 'plain'
    verify_certificates: true
    active_directory: true
    allow_username_or_email_login: false
    block_auto_created_users: false
    base: ENV['LDAP_BASE']
    user_filter: ENV['LDAP_USER_FILTER']
EOS

# Monitoring
prometheus_monitoring['enable'] = true
grafana['enable'] = false

# Security
nginx['ssl_prefer_server_ciphers'] = "on"
nginx['ssl_protocols'] = "TLSv1.2 TLSv1.3"
```

---

## 🛡️ Cấu hình bảo mật

### 1. Firewall Rules

```bash
# Chỉ cho phép SSH từ các IP cụ thể
sudo ufw allow from YOUR_IP to any port 22

# Cho phép HTTP/HTTPS
sudo ufw allow 80
sudo ufw allow 443

# Cho phép GitLab ports
sudo ufw allow ${GITLAB_HTTP_PORT}
sudo ufw allow ${GITLAB_SSH_PORT}

# Enable firewall
sudo ufw enable
```

### 2. Fail2Ban cho GitLab

Tạo file `/etc/fail2ban/jail.local`:

```ini
[gitlab]
enabled = true
port = http,https,${GITLAB_SSH_PORT}
filter = gitlab
logpath = /path/to/gitlab/logs/gitlab-rails/production.log
maxretry = 5
bantime = 600
```

### 3. SSL/TLS Hardening

Cập nhật Nginx config với các header bảo mật:

```nginx
server {
    listen 443 ssl http2;
    server_name gitlab.ssit.company.com;

    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/gitlab.ssit.company.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gitlab.ssit.company.com/privkey.pem;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    # GitLab specific
    client_max_body_size 512m;
    
    location / {
        proxy_pass http://localhost:${GITLAB_HTTP_PORT};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Ssl on;
    }
}
```

---

## 📊 Monitoring và Logging

### 1. Prometheus Metrics

GitLab tích hợp sẵn Prometheus metrics tại:
- `http://gitlab.ssit.company.com:8088/-/metrics`

### 2. Log Analysis

Các log quan trọng:
- `./data/logs/gitlab-rails/production.log` - Application logs
- `./data/logs/nginx/gitlab_access.log` - Access logs
- `./data/logs/nginx/gitlab_error.log` - Error logs

### 3. Health Checks

```bash
# Kiểm tra trạng thái GitLab
docker exec gitlab gitlab-ctl status

# Kiểm tra health endpoint
curl -f http://gitlab.ssit.company.com:8088/-/health

# Kiểm tra readiness
curl -f http://gitlab.ssit.company.com:8088/-/readiness
```

---

## 🔄 Backup và Restore Strategy

### 1. Backup Strategy

- **Frequency**: Hàng ngày lúc 2:00 AM
- **Retention**: 7 ngày
- **Location**: Local và remote storage
- **Components**: 
  - GitLab database
  - Git repositories  
  - User uploads
  - Configuration files

### 2. Restore Process

```bash
# 1. Stop GitLab
docker compose stop gitlab

# 2. Restore từ backup
./scripts/restore.sh backup_timestamp.tar

# 3. Restart GitLab
docker compose start gitlab

# 4. Reconfigure
docker exec gitlab gitlab-ctl reconfigure
```

### 3. Disaster Recovery

- Regular backup verification
- Offsite backup storage
- Documentation update
- Recovery time objective (RTO): < 4 hours
- Recovery point objective (RPO): < 24 hours

---

## ⚡ Performance Tuning

### 1. Server Requirements

**Minimum**:
- CPU: 4 cores
- RAM: 8GB
- Storage: 100GB SSD

**Recommended**:
- CPU: 8 cores
- RAM: 16GB
- Storage: 500GB SSD

### 2. Docker Resource Limits

```yaml
services:
  gitlab:
    deploy:
      resources:
        limits:
          memory: 8G
          cpus: '4'
        reservations:
          memory: 4G
          cpus: '2'
```

### 3. Database Optimization

Trong `gitlab.rb`:

```ruby
# PostgreSQL tuning
postgresql['max_connections'] = 200
postgresql['shared_buffers'] = "512MB"
postgresql['effective_cache_size'] = "2GB"
postgresql['work_mem'] = "16MB"
postgresql['maintenance_work_mem'] = "256MB"
```

---

## 🔍 Troubleshooting

### Các lỗi thường gặp

1. **GitLab không khởi động được**
   ```bash
   docker logs gitlab
   docker exec gitlab gitlab-ctl tail
   ```

2. **SSH không hoạt động**
   - Kiểm tra port mapping
   - Kiểm tra firewall
   - Kiểm tra SSH host config

3. **Email không gửi được**
   - Kiểm tra SMTP config
   - Test SMTP connection
   - Kiểm tra logs

4. **Performance issues**
   - Kiểm tra resource usage
   - Analyze slow queries
   - Review Prometheus metrics

### Commands hữu ích

```bash
# Reconfigure GitLab
docker exec gitlab gitlab-ctl reconfigure

# Restart all services
docker exec gitlab gitlab-ctl restart

# Check configuration
docker exec gitlab gitlab-rake gitlab:check

# Reset root password
docker exec -it gitlab gitlab-rails console
# User.find_by(username: 'root').update(password: 'newpassword', password_confirmation: 'newpassword')
```

---

## 📞 Support

Để được hỗ trợ:
1. Kiểm tra logs trong `./data/logs/`
2. Chạy `gitlab-rake gitlab:check`
3. Tham khảo [GitLab Documentation](https://docs.gitlab.com/)
4. Mở issue trên repository này

---

*Cập nhật lần cuối: July 2025*
