# 🚨 GitLab Troubleshooting Guide

Hướng dẫn khắc phục các lỗi thường gặp khi chạy GitLab on-premise với Docker.

---

## 🔧 Script kiểm tra nhanh

```bash
# Chạy health check tổng thể
./scripts/gitlab-health.sh check

# Khắc phục lỗi shared memory
./scripts/gitlab-health.sh fix-shm

# Reconfigure GitLab
./scripts/gitlab-health.sh reconfigure
```

---

## ⚠️ Lỗi Shared Memory (Prometheus)

### **Lỗi:**
```
writing value to /dev/shm/gitlab/puma/gauge_all_puma_16-0.db failed with unmapped file
```

### **Nguyên nhân:**
- Container không có đủ shared memory
- Prometheus metrics không thể ghi vào `/dev/shm`

### **Giải pháp:**

#### 1. **Tự động (khuyến nghị):**
```bash
./scripts/gitlab-health.sh fix-shm
```

#### 2. **Thủ công:**
```bash
# Stop containers
docker compose down

# Update docker-compose.yml (đã được cập nhật)
# Start lại với cấu hình mới
docker compose up -d

# Reconfigure GitLab
docker exec gitlab gitlab-ctl reconfigure
```

#### 3. **Disable Prometheus (nếu không cần monitoring):**
Sửa `.env`:
```env
PROMETHEUS_ENABLE=false
```

---

## 🐌 GitLab chậm khởi động

### **Triệu chứng:**
- Container chạy nhưng web interface không truy cập được
- `docker logs gitlab` hiển thị quá trình khởi tạo

### **Giải pháp:**

#### 1. **Kiểm tra trạng thái:**
```bash
./scripts/gitlab-health.sh status
docker exec gitlab gitlab-ctl status
```

#### 2. **Đợi GitLab khởi tạo hoàn tất:**
```bash
# GitLab lần đầu cần 3-5 phút
# Theo dõi logs
docker logs -f gitlab
```

#### 3. **Kiểm tra resource:**
```bash
./scripts/gitlab-health.sh memory
```

---

## 💾 Lỗi Database/Storage

### **Lỗi:**
```
PG::ConnectionBad: could not connect to server
FATAL: database "gitlabhq_production" does not exist
```

### **Giải pháp:**

#### 1. **Reset database:**
```bash
docker exec gitlab gitlab-ctl stop postgresql
docker exec gitlab gitlab-ctl reconfigure
docker exec gitlab gitlab-ctl start
```

#### 2. **Kiểm tra volumes:**
```bash
# Kiểm tra volume mounts
docker inspect gitlab | grep -A 10 "Mounts"

# Kiểm tra dung lượng
df -h ./data/
```

#### 3. **Restore từ backup (nếu có):**
```bash
./scripts/restore.sh <backup_name>
```

---

## 🌐 Lỗi Network/Port

### **Lỗi:**
- Không truy cập được web interface
- SSH clone không hoạt động

### **Giải pháp:**

#### 1. **Kiểm tra ports:**
```bash
# Kiểm tra port bindings
docker port gitlab

# Kiểm tra port conflicts
netstat -tulpn | grep :8088
netstat -tulpn | grep :2222
```

#### 2. **Kiểm tra firewall:**
```bash
# Windows
Get-NetFirewallRule | Where-Object {$_.DisplayName -like "*8088*"}

# Linux
sudo ufw status
```

#### 3. **Kiểm tra DNS/hosts:**
```bash
# Ping domain
ping gitlab.ssit.company.com

# Kiểm tra /etc/hosts (Linux) hoặc C:\Windows\System32\drivers\etc\hosts (Windows)
```

---

## 📧 Lỗi SMTP/Email

### **Lỗi:**
- GitLab không gửi được email
- SMTP authentication failed

### **Giải pháp:**

#### 1. **Kiểm tra cấu hình SMTP trong `.env`:**
```env
SMTP_ENABLE=true
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USER_NAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password  # App Password, không phải password thường
```

#### 2. **Test SMTP:**
```bash
docker exec gitlab gitlab-rails console
# Trong console:
# Notify.test_email('test@example.com', 'Test Subject', 'Test Body').deliver_now
```

#### 3. **Kiểm tra logs:**
```bash
docker exec gitlab tail -f /var/log/gitlab/gitlab-rails/production.log | grep -i smtp
```

---

## 🔐 Lỗi SSL/HTTPS

### **Lỗi:**
- Certificate issues
- Mixed content warnings

### **Giải pháp:**

#### 1. **Kiểm tra certificate:**
```bash
# Kiểm tra cert files
ls -la /etc/nginx/ssl/ssit.company/

# Test SSL
openssl s_client -connect gitlab.ssit.company.com:443
```

#### 2. **Cập nhật nginx config:**
```bash
# Reload nginx (nếu chạy reverse proxy riêng)
sudo nginx -t
sudo systemctl reload nginx
```

---

## ⏱️ Lỗi Timeout "GitLab is taking too much time to respond"

### **Lỗi:**
```
We're sorry. GitLab is taking too much time to respond.
Try refreshing the page, or going back and attempting the action again.
Please contact your GitLab administrator if this problem persists.
```

### **Nguyên nhân:**
- GitLab đang quá tải về CPU/Memory
- Quá nhiều CI/CD jobs chạy đồng thời
- Database queries chậm
- Insufficient resources

### **Giải pháp:**

#### 1. **Kiểm tra tài nguyên (khuyến nghị):**
```bash
./scripts/resource-monitor.sh check
./scripts/resource-monitor.sh ci-stats
```

#### 2. **Optimization tự động:**
```bash
./scripts/resource-monitor.sh optimize
```

#### 3. **Giảm tải ngay lập tức:**
```bash
# Giảm resource usage
./scripts/resource-monitor.sh scale-down

# Restart GitLab
docker compose restart gitlab

# Dọn dẹp tài nguyên
./scripts/resource-monitor.sh cleanup
```

#### 4. **Cấu hình resource limits:**
Sửa `.env` để giới hạn tài nguyên:
```env
# Giảm workers
PUMA_WORKERS=1
SIDEKIQ_CONCURRENCY=2

# Giảm database connections
POSTGRES_MAX_CONNECTIONS=30

# Giảm memory cho container
GITLAB_MEMORY_LIMIT=4G
GITLAB_CPU_LIMIT=2
```

#### 5. **Disable các tính năng không cần thiết:**
```env
PROMETHEUS_ENABLE=false
USAGE_PING_ENABLED=false
SEAT_LINK_ENABLED=false
```

#### 6. **Tăng timeout trong nginx (nếu dùng reverse proxy):**
```nginx
# Trong nginx config
proxy_connect_timeout 300s;
proxy_send_timeout 300s;
proxy_read_timeout 300s;
client_max_body_size 1G;
```

---

## 🚀 CI/CD Resource Management

### **Vấn đề:**
- CI/CD jobs chiếm quá nhiều tài nguyên
- Server bị chậm khi có nhiều pipeline chạy

### **Giải pháp:**

#### 1. **Giới hạn concurrent jobs:**
Sửa runner config (`config/runner-config.toml`):
```toml
concurrent = 2  # Chỉ cho phép 2 job chạy đồng thời
```

#### 2. **Resource limits cho mỗi job:**
```toml
[runners.docker]
  memory = "1g"        # Giới hạn RAM cho mỗi job
  cpus = "1.0"         # Giới hạn CPU cores
  memory_swap = "2g"   # Giới hạn swap
```

#### 3. **Monitoring CI/CD load:**
```bash
# Xem jobs đang chạy
./scripts/resource-monitor.sh ci-stats

# Monitor real-time
./scripts/resource-monitor.sh monitor
```

#### 4. **Cleanup CI/CD data:**
```bash
# Dọn dẹp artifacts và logs cũ
./scripts/resource-monitor.sh cleanup
```

#### 5. **Pipeline optimization:**
- Sử dụng cache hiệu quả
- Chia nhỏ jobs thành stages
- Sử dụng `only/except` rules để giảm số jobs
- Parallel jobs hợp lý

### **Cấu hình mẫu .gitlab-ci.yml:**
```yaml
# Giới hạn resources trong pipeline
variables:
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_CERTDIR: ""

stages:
  - build
  - test
  - deploy

# Cache để giảm tải
cache:
  paths:
    - node_modules/
    - vendor/

build:
  stage: build
  script:
    - echo "Building..."
  # Chỉ chạy khi cần thiết
  only:
    - main
    - develop
  # Timeout cho job
  timeout: 30 minutes

test:
  stage: test
  script:
    - echo "Testing..."
  # Chạy parallel để nhanh hơn nhưng giới hạn số lượng
  parallel: 2
  only:
    changes:
      - "src/**/*"
      - "tests/**/*"
```

---

## 🔄 Lỗi Backup/Restore

### **Lỗi:**
- Backup script fails
- Restore incomplete

### **Giải pháp:**

#### 1. **Kiểm tra backup process:**
```bash
./scripts/backup-manager.sh status
./scripts/backup-manager.sh test
```

#### 2. **Kiểm tra permissions:**
```bash
ls -la backups/
ls -la scripts/
```

#### 3. **Manual backup:**
```bash
docker exec gitlab gitlab-backup create
docker cp gitlab:/var/opt/gitlab/backups/ ./backups/
```

---

## 🧹 Cleaning & Maintenance

### **Định kỳ thực hiện:**

#### 1. **Cleanup resources:**
```bash
./scripts/gitlab-health.sh cleanup
```

#### 2. **Update GitLab:**
```bash
# Backup trước khi update
./scripts/backup.sh pre_update_$(date +%Y%m%d)

# Update image version trong docker-compose.yml
# Restart
docker compose pull
docker compose up -d
```

#### 3. **Monitor logs:**
```bash
./scripts/gitlab-health.sh logs
```

---

## 📊 Performance Issues

### **Triệu chứng:**
- GitLab chạy chậm
- High memory usage
- Timeout errors

### **Giải pháp:**

#### 1. **Giảm resource usage:**
Sửa `.env`:
```env
PROMETHEUS_SCRAPE_INTERVAL=60  # Tăng interval
```

#### 2. **Optimize trong `gitlab.rb`:**
```ruby
# Trong GITLAB_OMNIBUS_CONFIG
puma['worker_processes'] = 2
sidekiq['max_concurrency'] = 5
postgresql['shared_buffers'] = "256MB"
```

#### 3. **Tăng hardware:**
- Minimum: 8GB RAM, 4 CPU cores
- Recommended: 16GB RAM, 8 CPU cores

---

## 🆘 Emergency Recovery

### **Khi GitLab hoàn toàn không hoạt động:**

#### 1. **Complete restart:**
```bash
docker compose down
docker system prune -f
docker compose up -d
```

#### 2. **Factory reset (mất data):**
```bash
docker compose down -v
rm -rf ./data/
docker compose up -d
```

#### 3. **Restore từ backup:**
```bash
./scripts/restore.sh <latest_backup>
```

---

## 📞 Getting Help

1. **Kiểm tra logs đầy đủ:**
   ```bash
   ./scripts/gitlab-health.sh logs > gitlab-logs.txt
   ```

2. **Thu thập system info:**
   ```bash
   docker version > system-info.txt
   docker compose version >> system-info.txt
   ./scripts/gitlab-health.sh check >> system-info.txt
   ```

3. **Tham khảo:**
   - [GitLab Documentation](https://docs.gitlab.com/)
   - [Docker Troubleshooting](https://docs.docker.com/engine/troubleshooting/)
   - Project [CONFIG_GUIDE.md](CONFIG_GUIDE.md)

---

*Cập nhật lần cuối: July 2025*
