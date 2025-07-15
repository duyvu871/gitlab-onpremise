# 🏃‍♂️ GitLab Runner Configuration Guide

Hướng dẫn chi tiết cấu hình GitLab Runner cho GitLab on-premise với Docker để chạy CI/CD pipelines.

---

## 📋 Tổng quan

GitLab Runner là service chịu trách nhiệm chạy CI/CD jobs từ GitLab. Project này đã được cấu hình sẵn:

- **Docker Executor**: Chạy jobs trong Docker containers (khuyến nghị)
- **Shell Executor**: Chạy jobs trực tiếp trên host
- **Resource Limits**: Giới hạn tài nguyên cho mỗi job
- **Network Integration**: Kết nối với GitLab qua internal network

---

## 🚀 Quick Start

### **1. Khởi động GitLab và Runner:**

```bash
# Start tất cả services
docker compose up -d

# Kiểm tra status
docker ps | grep -E "(gitlab|runner)"
```

### **2. Register Runner tự động:**

```bash
# Register Docker runner (khuyến nghị)
./scripts/register-runner.sh docker

# Hoặc register cả Docker và Shell
./scripts/register-runner.sh both
```

### **3. Verify setup:**

```bash
# Kiểm tra runner status
./scripts/register-runner.sh status

# List registered runners
./scripts/register-runner.sh list
```

---

## 🔧 Cấu hình chi tiết

### **1. Docker Compose Configuration**

Trong `docker-compose.yml`:

```yaml
gitlab-runner:
  image: gitlab/gitlab-runner:latest
  container_name: gitlab-runner
  restart: unless-stopped
  volumes:
    - ./config/runner-config.toml:/etc/gitlab-runner/config.toml
    - /var/run/docker.sock:/var/run/docker.sock  # Để chạy Docker-in-Docker
    - gitlab-runner-cache:/cache
  networks:
    - gitlab_net  # Internal network với GitLab
  environment:
    - DOCKER_TLS_CERTDIR=""
    - DOCKER_DRIVER=overlay2
    - GITLAB_URL=${GITLAB_URL}
  privileged: true  # Cần thiết cho Docker-in-Docker
  deploy:
    resources:
      limits:
        memory: 2G    # Giới hạn RAM cho Runner container
        cpus: '2'     # Giới hạn CPU
```

### **2. Runner Configuration File**

File `config/runner-config.toml`:

```toml
concurrent = 2  # Số jobs chạy đồng thời tối đa
check_interval = 0
log_level = "info"

# Docker Executor Runner
[[runners]]
  name = "docker-runner"
  url = "http://gitlab:80/"  # Internal URL
  executor = "docker"
  
  [runners.docker]
    image = "alpine:latest"  # Default image
    privileged = false       # Bảo mật
    
    # Resource limits per job
    memory = "1g"            # RAM limit per job
    cpus = "1.0"            # CPU limit per job
    memory_swap = "2g"       # Swap limit
    
    # Volumes
    volumes = [
      "/cache",
      "/var/run/docker.sock:/var/run/docker.sock"
    ]
    
    # Network
    network_mode = "gitlab_net"
    
    # Security
    security_opt = ["no-new-privileges:true"]
    cap_drop = ["ALL"]
    cap_add = ["CHOWN", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
```

### **3. Environment Variables (.env)**

```env
# Runner Resource Limits
RUNNER_MEMORY_LIMIT=2G        # Memory limit cho runner container
RUNNER_CPU_LIMIT=2            # CPU limit cho runner container
RUNNER_MEMORY_RESERVATION=512M # Reserved memory
RUNNER_CPU_RESERVATION=0.5    # Reserved CPU
```

---

## 📝 Registration Process

### **1. Lấy Registration Token**

#### **Cách 1: Web Interface (Khuyến nghị)**
1. Truy cập GitLab: `http://gitlab.ssit.company.com:8088`
2. Login as admin (root)
3. Vào **Admin Area** > **CI/CD** > **Runners**
4. Copy token từ section **"Register an instance runner"**

#### **Cách 2: Command Line**
```bash
# Lấy token từ GitLab database (nếu có quyền admin)
docker exec gitlab gitlab-rails runner "puts Gitlab::CurrentSettings.runners_registration_token"
```

### **2. Register Runners**

#### **Docker Runner (Khuyến nghị cho hầu hết use cases):**
```bash
./scripts/register-runner.sh docker
```

#### **Shell Runner (cho builds cần local tools):**
```bash
./scripts/register-runner.sh shell
```

#### **Register manual:**
```bash
docker exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "http://gitlab:80/" \
  --registration-token "YOUR_TOKEN" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --docker-network "gitlab_net" \
  --description "My Docker Runner" \
  --tag-list "docker,linux" \
  --run-untagged="true"
```

### **3. Verify Registration**

```bash
# List runners
./scripts/register-runner.sh list

# Check status
./scripts/register-runner.sh status

# Test runner với simple job
```

---

## 🎛️ Resource Management

### **1. Container Level Limits**

Trong `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      memory: 2G      # Total memory cho runner container
      cpus: '2'       # Total CPU cores
    reservations:
      memory: 512M    # Reserved memory
      cpus: '0.5'     # Reserved CPU
```

### **2. Job Level Limits**

Trong `config/runner-config.toml`:

```toml
[runners.docker]
  memory = "1g"           # RAM per job
  memory_swap = "2g"      # Swap per job  
  memory_reservation = "512m"  # Reserved RAM per job
  cpus = "1.0"           # CPU cores per job
  cpu_shares = 1024      # CPU priority weight
```

### **3. Concurrent Job Limits**

```toml
concurrent = 2          # Global: max 2 jobs across all runners

[[runners]]
  limit = 1             # Per runner: max 1 job per runner
```

### **4. Cache Management**

```toml
[runners.cache]
  Type = "local"
  Path = "/cache"
  
  [runners.cache.local]
    MaxCacheSize = "1G"  # Giới hạn cache size
```

---

## 🐳 Executor Types

### **1. Docker Executor (Khuyến nghị)**

**Ưu điểm:**
- Isolation tốt
- Clean environment cho mỗi job
- Hỗ trợ nhiều ngôn ngữ/tools
- Easy scaling

**Cấu hình:**
```toml
[[runners]]
  executor = "docker"
  
  [runners.docker]
    image = "alpine:latest"
    privileged = false
    volumes = ["/cache", "/var/run/docker.sock:/var/run/docker.sock"]
    network_mode = "gitlab_net"
```

**Use cases:**
- Web applications (Node.js, Python, PHP)
- Containerized applications
- Multi-language projects
- Testing với multiple environments

### **2. Shell Executor**

**Ưu điểm:**
- Direct access to host
- Faster execution (no container overhead)
- Access to host tools/services

**Cấu hình:**
```toml
[[runners]]
  executor = "shell"
  
  [runners.shell]
    # Chạy trực tiếp trên host
```

**Use cases:**
- Native builds (C/C++, Go)
- System administration tasks
- Legacy applications
- Performance-critical builds

### **3. Docker-in-Docker (DinD)**

**Cấu hình đặc biệt cho Docker builds:**
```toml
[runners.docker]
  image = "docker:latest"
  privileged = true
  volumes = ["/certs/client"]
  
  environment = [
    "DOCKER_TLS_CERTDIR=/certs",
    "DOCKER_TLS_VERIFY=1",
    "DOCKER_CERT_PATH=/certs/client"
  ]
  
  services = ["docker:dind"]
```

---

## 🔒 Security Configuration

### **1. Privileged Mode**

```toml
# Không khuyến nghị trừ khi cần thiết
[runners.docker]
  privileged = false  # Mặc định
  
# Chỉ enable khi cần Docker-in-Docker
[runners.docker]
  privileged = true   # Chỉ cho DinD builds
```

### **2. Security Options**

```toml
[runners.docker]
  security_opt = ["no-new-privileges:true"]
  cap_drop = ["ALL"]
  cap_add = ["CHOWN", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
```

### **3. Network Isolation**

```toml
[runners.docker]
  network_mode = "gitlab_net"  # Isolated network
  # Hoặc
  network_mode = "none"        # No network access
```

### **4. Volume Restrictions**

```toml
[runners.docker]
  volumes = [
    "/cache",                    # Cache only
    "/var/run/docker.sock:/var/run/docker.sock"  # Docker access
  ]
  # Tránh mount sensitive directories như /etc, /var, /home
```

---

## 📊 Monitoring & Troubleshooting

### **1. Runner Status**

```bash
# Check runner status
./scripts/register-runner.sh status

# Check logs
docker logs gitlab-runner

# Check runner processes
docker exec gitlab-runner ps aux
```

### **2. Job Debugging**

```bash
# Enable debug mode
docker exec gitlab-runner gitlab-runner --debug run

# Check job logs in GitLab UI
# Hoặc check local logs
docker exec gitlab-runner find /var/log -name "*gitlab-runner*"
```

### **3. Resource Monitoring**

```bash
# Monitor runner resources
./scripts/resource-monitor.sh monitor

# Check running jobs
./scripts/resource-monitor.sh ci-stats

# Container stats
docker stats gitlab-runner
```

### **4. Common Issues**

#### **Runner không kết nối được GitLab:**
```bash
# Check network
docker exec gitlab-runner ping gitlab

# Check GitLab URL
docker exec gitlab-runner curl http://gitlab:80/-/health
```

#### **Jobs fail với "permission denied":**
```bash
# Check volume permissions
docker exec gitlab-runner ls -la /var/run/docker.sock

# Restart runner
docker compose restart gitlab-runner
```

#### **Out of memory errors:**
```bash
# Reduce job memory limit
# Edit config/runner-config.toml
memory = "512m"  # Giảm từ 1g

# Hoặc increase runner container limit
RUNNER_MEMORY_LIMIT=4G  # Trong .env
```

---

## 🎯 Best Practices

### **1. Resource Planning**

- **Small teams (1-5 devs)**: 1-2 concurrent jobs, 1G RAM per job
- **Medium teams (5-15 devs)**: 2-4 concurrent jobs, 1-2G RAM per job  
- **Large teams (15+ devs)**: 4-8 concurrent jobs, 2-4G RAM per job

### **2. Runner Configuration**

```toml
# Optimized cho most use cases
concurrent = 2

[[runners]]
  limit = 1
  
  [runners.docker]
    memory = "1g"
    cpus = "1.0"
    pull_policy = "if-not-present"  # Faster builds
```

### **3. Cache Strategy**

```yaml
# .gitlab-ci.yml
cache:
  key: ${CI_COMMIT_REF_SLUG}
  paths:
    - node_modules/
    - vendor/
    - .yarn
  policy: pull-push
```

### **4. Image Selection**

```yaml
# Fast, lightweight base images
image: alpine:latest       # Minimal Linux
image: node:16-alpine     # Node.js on Alpine
image: python:3.9-slim    # Python slim
```

### **5. Pipeline Optimization**

```yaml
stages:
  - build
  - test
  - deploy

variables:
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_CERTDIR: ""

build:
  stage: build
  script:
    - echo "Building..."
  only:
    - main
  timeout: 30 minutes
  
test:
  stage: test
  script:
    - echo "Testing..."
  parallel: 2
  coverage: '/Coverage: \d+\.\d+%/'
```

---

## 🛠️ Management Commands

### **Registration Management**

```bash
# Register new runner
./scripts/register-runner.sh docker

# Remove all runners
./scripts/register-runner.sh remove

# List current runners
./scripts/register-runner.sh list
```

### **Runner Control**

```bash
# Restart runner service
docker compose restart gitlab-runner

# Update runner
docker compose pull gitlab-runner
docker compose up -d gitlab-runner

# Stop runner gracefully
docker exec gitlab-runner gitlab-runner stop
```

### **Configuration Updates**

```bash
# Edit runner config
nano config/runner-config.toml

# Restart để apply changes
docker compose restart gitlab-runner

# Verify new config
./scripts/register-runner.sh status
```

### **Cleanup**

```bash
# Clean runner cache
docker exec gitlab-runner rm -rf /cache/*

# Clean old job logs
docker exec gitlab-runner find /var/log -name "*.log" -mtime +7 -delete

# Docker cleanup
docker system prune -f
```

---

## 📞 Support & Documentation

### **Tham khảo thêm:**
- [GitLab Runner Documentation](https://docs.gitlab.com/runner/)
- [Docker Executor](https://docs.gitlab.com/runner/executors/docker.html)
- [Resource Management Guide](RESOURCE_MANAGEMENT.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)

### **Log locations:**
- **Runner logs**: `docker logs gitlab-runner`
- **Job logs**: GitLab Web UI > CI/CD > Jobs
- **Configuration**: `config/runner-config.toml`

### **Emergency commands:**
```bash
# Quick restart everything
docker compose restart

# Reset runner completely
./scripts/register-runner.sh remove
./scripts/register-runner.sh docker

# Emergency resource cleanup
./scripts/resource-monitor.sh cleanup
```

---

*Cập nhật lần cuối: July 2025*
