# 🔧 Resource Management Guide

Hướng dẫn quản lý tài nguyên cho GitLab on-premise để tối ưu hiệu suất và tránh quá tải.

---

## 📊 Tổng quan Resource Limits

### **Cấu hình mặc định (Máy chủ 8GB RAM):**

| Component | Memory Limit | CPU Limit | Mô tả |
|-----------|-------------|----------|-------|
| GitLab Main | 6GB | 4 cores | Application chính |
| GitLab Runner | 1GB | 1 core | CI/CD jobs |
| Backup Service | 512MB | 0.5 core | Backup tự động |
| Database | 256MB buffer | - | PostgreSQL |
| Redis | 128MB | - | Cache |

### **Scaling theo hardware:**

#### **Máy chủ nhỏ (4GB RAM):**
```env
GITLAB_MEMORY_LIMIT=3G
GITLAB_CPU_LIMIT=2
PUMA_WORKERS=1
SIDEKIQ_CONCURRENCY=2
RUNNER_MEMORY_LIMIT=512M
```

#### **Máy chủ trung bình (8GB RAM) - Mặc định:**
```env
GITLAB_MEMORY_LIMIT=6G
GITLAB_CPU_LIMIT=4
PUMA_WORKERS=2
SIDEKIQ_CONCURRENCY=3
RUNNER_MEMORY_LIMIT=1G
```

#### **Máy chủ lớn (16GB+ RAM):**
```env
GITLAB_MEMORY_LIMIT=12G
GITLAB_CPU_LIMIT=8
PUMA_WORKERS=4
SIDEKIQ_CONCURRENCY=8
RUNNER_MEMORY_LIMIT=2G
```

---

## 🎛️ Cấu hình chi tiết

### **1. GitLab Application (.env)**

```env
# Core Application
GITLAB_MEMORY_LIMIT=6G           # RAM limit cho GitLab container
GITLAB_CPU_LIMIT=4               # CPU cores limit
GITLAB_MEMORY_RESERVATION=3G     # Reserved RAM
GITLAB_CPU_RESERVATION=2         # Reserved CPU

# Puma Web Server (handles HTTP requests)
PUMA_WORKERS=2                   # Số worker processes
PUMA_MAX_THREADS=4               # Max threads per worker
PUMA_MIN_THREADS=1               # Min threads per worker

# Sidekiq Background Jobs (CI/CD, emails, etc.)
SIDEKIQ_CONCURRENCY=3            # Concurrent background jobs

# Database Optimization
POSTGRES_MAX_CONNECTIONS=50      # Max DB connections
POSTGRES_SHARED_BUFFERS=256MB    # DB shared buffer
POSTGRES_WORK_MEM=8MB           # Memory per query
POSTGRES_MAINTENANCE_WORK_MEM=32MB # Maintenance operations

# Redis Cache
REDIS_MAX_MEMORY=128MB          # Redis memory limit

# Features Control
PROMETHEUS_ENABLE=true          # Monitoring (có thể disable để tiết kiệm RAM)
USAGE_PING_ENABLED=false       # Telemetry data
SEAT_LINK_ENABLED=false        # License validation
```

### **2. GitLab Runner (config/runner-config.toml)**

```toml
# Global Settings
concurrent = 2                   # Max concurrent jobs
check_interval = 0

[[runners]]
  name = "docker-runner"
  executor = "docker"
  
  [runners.docker]
    image = "alpine:latest"
    
    # Resource Limits per Job
    memory = "1g"                # RAM limit per job
    memory_swap = "2g"           # Swap limit per job
    memory_reservation = "512m"   # Reserved RAM per job
    cpus = "1.0"                 # CPU cores per job
    cpu_shares = 1024            # CPU priority
    
    # Storage & Network
    volumes = ["/cache"]
    shm_size = 0
    network_mode = "gitlab_net"
    
    # Security
    privileged = false
    security_opt = ["no-new-privileges:true"]
```

---

## 📈 Monitoring & Optimization

### **1. Scripts monitoring:**

```bash
# Kiểm tra resource usage hiện tại
./scripts/resource-monitor.sh check

# Monitor real-time
./scripts/resource-monitor.sh monitor

# Xem CI/CD job statistics
./scripts/resource-monitor.sh ci-stats

# Auto-optimization
./scripts/resource-monitor.sh optimize
```

### **2. Performance tuning:**

#### **Khi GitLab chậm:**
```bash
# Scale down tạm thời
./scripts/resource-monitor.sh scale-down
docker compose restart gitlab

# Cleanup resources
./scripts/resource-monitor.sh cleanup
```

#### **Khi cần performance cao:**
```bash
# Scale up
./scripts/resource-monitor.sh scale-up
docker compose restart gitlab
```

### **3. CI/CD Optimization:**

#### **Giảm concurrent jobs:**
- Sửa `concurrent = 1` trong runner config
- Restart runner: `docker compose restart gitlab-runner`

#### **Pipeline optimization:**
```yaml
# .gitlab-ci.yml mẫu
variables:
  DOCKER_DRIVER: overlay2

cache:
  paths:
    - node_modules/
    - .yarn

stages:
  - build
  - test

build:
  stage: build
  script:
    - echo "Build commands"
  only:
    - main
  timeout: 10 minutes
  
test:
  stage: test
  script:
    - echo "Test commands"
  parallel: 2
  only:
    changes:
      - "src/**/*"
```

---

## 🚨 Emergency Response

### **Khi GitLab timeout/không phản hồi:**

#### **1. Immediate response:**
```bash
# Kiểm tra tình trạng
docker ps
docker stats --no-stream

# Restart nhanh
docker compose restart gitlab

# Theo dõi logs
docker logs -f gitlab
```

#### **2. Resource emergency:**
```bash
# Giảm tải ngay lập tức
./scripts/resource-monitor.sh scale-down

# Cleanup aggressive
docker system prune -af
./scripts/resource-monitor.sh cleanup

# Restart với cấu hình thấp
docker compose up -d
```

#### **3. Database issues:**
```bash
# Restart database
docker exec gitlab gitlab-ctl stop postgresql
docker exec gitlab gitlab-ctl start postgresql

# Reconfigure nếu cần
docker exec gitlab gitlab-ctl reconfigure
```

---

## 📊 Resource Planning

### **Estimation theo team size:**

| Team Size | Projects | Daily Pipelines | Recommended RAM | Recommended CPU |
|-----------|----------|----------------|----------------|----------------|
| 1-5 | 1-10 | <10 | 4GB | 2 cores |
| 5-15 | 10-50 | 10-50 | 8GB | 4 cores |
| 15-50 | 50-200 | 50-200 | 16GB | 8 cores |
| 50+ | 200+ | 200+ | 32GB+ | 16+ cores |

### **Storage planning:**
- **OS + GitLab**: ~5GB
- **Repositories**: 1-10GB per project
- **CI Artifacts**: 100MB-1GB per project/month
- **Logs**: 1-5GB/month
- **Backups**: 2x repository size

### **Network bandwidth:**
- **Git operations**: 1-10Mbps per active user
- **CI/CD**: 10-100Mbps depending on artifacts
- **Container registry**: 100Mbps+ for large images

---

## 🔧 Maintenance Schedule

### **Daily:**
```bash
# Auto cleanup (via cron)
./scripts/resource-monitor.sh cleanup
```

### **Weekly:**
```bash
# Performance check
./scripts/resource-monitor.sh check
./scripts/resource-monitor.sh optimize

# Backup check
./scripts/backup-manager.sh status
```

### **Monthly:**
```bash
# Full optimization review
./scripts/resource-monitor.sh usage
./scripts/resource-monitor.sh ci-stats

# Cleanup old data
docker exec gitlab gitlab-rails runner "
  # Remove old job artifacts (>90 days)
  Ci::JobArtifact.where('created_at < ?', 90.days.ago).find_each(&:destroy)
  
  # Remove old job traces (>90 days)  
  Ci::Build.where('created_at < ?', 90.days.ago).update_all(trace: nil)
"
```

---

## 🎯 Best Practices

### **1. Resource allocation:**
- Luôn dành 20-30% resources cho OS
- Monitor peak usage times
- Scale based on actual usage, không phải estimation

### **2. CI/CD optimization:**
- Sử dụng cache hiệu quả
- Chia nhỏ jobs thành stages hợp lý
- Cleanup artifacts thường xuyên
- Sử dụng `only/except` rules

### **3. Database optimization:**
- Regular VACUUM
- Monitor slow queries
- Appropriate connection pool size

### **4. Monitoring:**
- Setup alerts cho high resource usage
- Regular backup verification
- Log rotation
- Health checks automation

---

## 📞 Support

Khi gặp vấn đề về performance:

1. **Thu thập thông tin:**
   ```bash
   ./scripts/resource-monitor.sh check > performance-report.txt
   ./scripts/gitlab-health.sh check >> performance-report.txt
   ```

2. **Tham khảo:**
   - [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
   - [CONFIG_GUIDE.md](CONFIG_GUIDE.md)
   - [GitLab Performance Guide](https://docs.gitlab.com/ee/administration/operations/)

---

*Cập nhật lần cuối: July 2025*
