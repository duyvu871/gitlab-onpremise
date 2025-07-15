# 🐙 GitLab On-Premise - Docker Setup

Triển k## 🚀 Triển khai nhanh

### Quick Setup (Recommended)

```bash
git clone https://github.com/duyvu871/gitlab-onpremise.git
cd gitlab-onpremise

# One-command setup
./scripts/setup-gitlab.sh
`## 📚 Tài liệu chi tiết

- **[Admin Guide](docs/ADMIN_GUIDE.md)** - 👨‍💼 Hướng dẫn quản trị GitLab (tài khoản admin, user management)
- **[GitLab Runner Guide](docs/GITLAB_RUNNER_GUIDE.md)** - Hướng dẫn cấu hình CI/CD Runner
- **[Config Guide](docs/CONFIG_GUIDE.md)** - Hướng dẫn cấu hình chi tiết
- **[Resource Management](docs/RESOURCE_MANAGEMENT.md)** - Quản lý tài nguyên và performance
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Khắc phục sự cố thường gặp
- **[Scripts README](scripts/README.md)** - Hướng dẫn sử dụng scripts## Manual Setup

### 1. Clone repo & cấu hình biến môi trường

```bash
git clone https://github.com/duyvu871/gitlab-onpremise.git
cd gitlab-onpremise
cp .env.example .env
# Sửa file .env theo tên miền, port của bạn
```

### 2. Khởi động GitLab

```bash
docker compose up -d
```

Đợi 3–5 phút để GitLab khởi tạo lần đầu.

### 3. Cấu hình GitLab Runner (CI/CD)

```bash
# Register runner tự động
./scripts/register-runner.sh docker

# Hoặc register cả Docker và Shell runner
./scripts/register-runner.sh both
```

### 4. Truy cập GitLab

Truy cập: `http://gitlab.example.com:8088`

**Login đầu tiên:**
- Username: `root`
- Password: 
  - **Nếu đã cấu hình trong .env**: Sử dụng `GITLAB_ROOT_PASSWORD`
  - **Nếu chưa cấu hình**: Xem trong logs `docker logs gitlab | grep "Password:"`
  - **Hoặc sử dụng script**: `./scripts/admin-manager.sh get-password` Edition (CE) trên máy chủ riêng bằng Docker Compose, với reverse proxy qua Nginx, domain tách biệt cho SSH, hỗ trợ backup/restore.

---

## 📦 Tính năng

- Triển khai GitLab CE `16.3.4` bằng Docker
- **GitLab Runner** tích hợp với Docker executor
- **Backup tự động** theo lịch với retention policy
- **Resource management** để tối ưu hiệu suất
- Tách riêng domain SSH (`ssh.gitlab.example.com`)
- Reverse proxy qua Nginx (có SSL)
- Custom port để tránh xung đột hệ thống
- Hỗ trợ backup/restore dễ dàng
- Cấu trúc thư mục rõ ràng, dễ maintain

---

## 🗂️ Cấu trúc dự án

```

gitlab-onpremise/
├── docker-compose.yml         # Cấu hình dịch vụ GitLab
├── .env                       # Biến môi trường
├── config/
│   └── gitlab.rb              # Cấu hình GitLab (nếu dùng trực tiếp)
├── data/                      # Volume bind cho GitLab
│   ├── config/                # /etc/gitlab
│   ├── logs/                  # /var/log/gitlab
│   └── data/                  # /var/opt/gitlab
├── nginx/
│   └── gitlab.conf            # Reverse proxy Nginx
├── scripts/
│   ├── backup.sh              # Script backup GitLab
│   └── restore.sh             # Script restore GitLab
├── certs/                     # Thư mục chứa SSL cert (nếu dùng thủ công)
├── docs/                      # Hướng dẫn bổ sung
│   ├── README.md
│   └── CONFIG\_GUIDE.md
└── .gitignore

````

---

## 🚀 Triển khai nhanh

### 1. Clone repo & cấu hình biến môi trường

```bash
git clone https://github.com/duyvu871/gitlab-onpremise.git
cd gitlab-onpremise
cp .env.example .env
# Sửa file .env theo tên miền, port của bạn
````

### 2. Khởi động GitLab

```bash
docker compose up -d
```

Đợi 3–5 phút để GitLab khởi tạo lần đầu.

Truy cập: `http://gitlab.example.com:8088`

---

## 🌐 Reverse proxy bằng Nginx

### Cấu hình Nginx host (nginx/gitlab.conf)

```nginx
server {
    listen 80;
    server_name gitlab.example.com;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name gitlab.example.com;

    ssl_certificate /etc/letsencrypt/live/gitlab.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gitlab.example.com/privkey.pem;

    location / {
        proxy_pass http://localhost:8088;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 512m;
    }
}
```

### Cài SSL (nếu cần)

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d gitlab.example.com
```

---

## 🔐 Tách domain SSH riêng

### Trỏ DNS

* A record: `ssh.gitlab.example.com → your-server-ip`
* ⚠️ KHÔNG bật proxy (Cloudflare) cho SSH

### Sửa `.env`

```dotenv
GITLAB_SSH_HOST=ssh.gitlab.example.com
GITLAB_SSH_PORT=2222
```

### Cấu hình clone SSH

```bash
git clone ssh://git@ssh.gitlab.example.com:2222/group/project.git
```

---

## 💾 Backup & Restore

### Backup

```bash
./scripts/backup.sh
```

### Restore

```bash
./scripts/restore.sh <backup-file>
```

> Thư mục `backup/` sẽ chứa các bản `.tar` tự động tạo.

---

## ✅ Câu lệnh hữu ích

### GitLab Management
```bash
# Reconfigure GitLab (sau khi sửa config)
docker exec -it gitlab gitlab-ctl reconfigure

# Xem logs
docker logs -f gitlab

# Reset root password (nếu cần)
docker exec -it gitlab bash
gitlab-rails console
user = User.find_by(username: 'root')
user.password = 'newpassword'
user.password_confirmation = 'newpassword'
user.save!
```

### GitLab Runner Management
```bash
# Kiểm tra runner status
./scripts/register-runner.sh status

# List registered runners
./scripts/register-runner.sh list

# Register new runner
./scripts/register-runner.sh docker

# Remove all runners
./scripts/register-runner.sh remove
```

### Backup & Resource Management
```bash
# Tạo backup thủ công
./scripts/backup.sh

# Kiểm tra resource usage
./scripts/resource-monitor.sh check

# Optimize performance
./scripts/resource-monitor.sh optimize

# Health check tổng thể
./scripts/gitlab-health.sh check
```

---

## � Tài liệu chi tiết

- **[GitLab Runner Guide](docs/GITLAB_RUNNER_GUIDE.md)** - Hướng dẫn cấu hình CI/CD Runner
- **[Config Guide](docs/CONFIG_GUIDE.md)** - Hướng dẫn cấu hình chi tiết
- **[Resource Management](docs/RESOURCE_MANAGEMENT.md)** - Quản lý tài nguyên và performance
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Khắc phục sự cố thường gặp
- **[Scripts README](scripts/README.md)** - Hướng dẫn sử dụng scripts

---

## �📄 Giấy phép

MIT License

---

## 👤 Tác giả

> Nếu bạn thấy hữu ích, hãy ⭐️ repo này hoặc fork lại để tùy chỉnh theo hệ thống của bạn!
