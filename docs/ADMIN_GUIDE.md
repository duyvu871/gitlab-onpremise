# GitLab Admin Guide 👨‍💼

Hướng dẫn quản trị GitLab on-premise với Docker Compose.

## 📋 Mục lục

- [Tài khoản Admin đầu tiên](#tài-khoản-admin-đầu-tiên)
- [Đăng nhập Admin](#đăng-nhập-admin)
- [Reset mật khẩu Admin](#reset-mật-khẩu-admin)
- [Quản lý Users](#quản-lý-users)
- [Cấu hình hệ thống](#cấu-hình-hệ-thống)
- [Monitoring & Logs](#monitoring--logs)
- [Backup & Restore](#backup--restore)
- [Command Line Tools](#command-line-tools)

---

## 🔐 Tài khoản Admin đầu tiên

### Thiết lập lần đầu

Khi GitLab khởi động lần đầu, hệ thống sẽ tự động tạo tài khoản `root` với mật khẩu ngẫu nhiên.

#### Cách 1: Sử dụng script quản lý admin
```bash
# Lấy mật khẩu hiện tại (từ .env hoặc logs)
./scripts/admin-manager.sh get-password
```

#### Cách 2: Lấy mật khẩu từ logs
```bash
# Đợi GitLab khởi động hoàn toàn (5-10 phút)
docker logs gitlab 2>&1 | grep "Password:"

# Hoặc kiểm tra file password
docker exec gitlab cat /etc/gitlab/initial_root_password
```

#### Cách 3: Đặt mật khẩu từ environment variable (Khuyến nghị)
Thêm vào file `.env`:
```bash
GITLAB_ROOT_PASSWORD=your_secure_password_here
GITLAB_ROOT_EMAIL=admin@your-domain.com
```

> ⚠️ **Đã được cấu hình sẵn** trong `docker-compose.yml` của project này!

#### Cách 4: Reset mật khẩu qua console
```bash
# Truy cập GitLab Rails console
docker exec -it gitlab gitlab-rails console

# Đặt mật khẩu mới cho root
user = User.find_by(username: 'root')
user.password = 'your_new_password'
user.password_confirmation = 'your_new_password'
user.save!

# Thoát console
exit
```

---

## 🚪 Đăng nhập Admin

### Thông tin đăng nhập
- **URL**: `https://gitlab.ssit.company` (hoặc địa chỉ bạn cấu hình)
- **Username**: `root`
- **Password**: Như đã thiết lập ở bước trên

### Truy cập Admin Area
1. Đăng nhập với tài khoản `root`
2. Click vào avatar ở góc phải
3. Chọn **Admin Area**
4. Hoặc truy cập trực tiếp: `https://gitlab.ssit.company/admin`

---

## 🔑 Reset mật khẩu Admin

### Khi quên mật khẩu root

#### Phương pháp 1: Qua Rails Console
```bash
# Truy cập container GitLab
docker exec -it gitlab gitlab-rails console

# Reset password cho user root
user = User.find_by(username: 'root')
user.password = 'new_secure_password'
user.password_confirmation = 'new_secure_password'
user.save!

# Kiểm tra kết quả
puts "Password updated successfully" if user.save!
exit
```

#### Phương pháp 2: Qua rake task
```bash
# Sử dụng rake task để reset password
docker exec -it gitlab gitlab-rake "gitlab:password:reset[root]"

# Nhập mật khẩu mới khi được yêu cầu
```

#### Phương pháp 3: Tạo user admin mới
```bash
docker exec -it gitlab gitlab-rails console

# Tạo user admin mới
user = User.new
user.email = 'admin@your-domain.com'
user.username = 'admin'
user.name = 'Administrator'
user.password = 'secure_password'
user.password_confirmation = 'secure_password'
user.admin = true
user.confirmed_at = Time.now
user.save!

exit
```

---

## 👥 Quản lý Users

### Tạo user admin qua Web UI
1. Đăng nhập với quyền admin
2. Vào **Admin Area** > **Users**
3. Click **New user**
4. Điền thông tin:
   - Name: Tên hiển thị
   - Username: Tên đăng nhập
   - Email: Địa chỉ email
   - Password: Mật khẩu
   - **☑ Admin**: Tick để cấp quyền admin
5. Click **Create user**

### Tạo user admin qua Command Line
```bash
docker exec -it gitlab gitlab-rails console

# Tạo user admin
user = User.create!(
  email: 'newadmin@company.com',
  username: 'newadmin',
  name: 'New Administrator',
  password: 'secure_password',
  password_confirmation: 'secure_password',
  admin: true,
  confirmed_at: Time.now
)

puts "Admin user created: #{user.username}"
exit
```

### Cấp quyền admin cho user hiện có
```bash
docker exec -it gitlab gitlab-rails console

# Tìm user theo username
user = User.find_by(username: 'existing_username')

# Hoặc tìm theo email
user = User.find_by(email: 'user@company.com')

# Cấp quyền admin
user.admin = true
user.save!

puts "Admin privileges granted to #{user.username}"
exit
```

### Thu hồi quyền admin
```bash
docker exec -it gitlab gitlab-rails console

user = User.find_by(username: 'username')
user.admin = false
user.save!

puts "Admin privileges revoked from #{user.username}"
exit
```

---

## ⚙️ Cấu hình hệ thống

### Các thiết lập quan trọng trong Admin Area

#### 1. General Settings
- **Admin Area** > **Settings** > **General**
- Account and limit settings
- Sign-up restrictions
- Sign-in restrictions
- Home page URL

#### 2. CI/CD Settings
- **Admin Area** > **Settings** > **CI/CD**
- Auto DevOps
- Continuous Integration
- Package Registry
- Runner registration

#### 3. Network Settings
- **Admin Area** > **Settings** > **Network**
- IP whitelist
- Outbound requests
- Protected paths

#### 4. Email Settings
- **Admin Area** > **Settings** > **Email**
- Email configuration đã setup trong docker-compose.yml

### Kiểm tra cấu hình qua command line
```bash
# Kiểm tra toàn bộ cấu hình
docker exec gitlab gitlab-rake gitlab:env:info

# Kiểm tra GitLab health
docker exec gitlab gitlab-rake gitlab:check

# Kiểm tra database
docker exec gitlab gitlab-rake gitlab:db:configure
```

---

## 📊 Monitoring & Logs

### Admin Dashboard
1. **Admin Area** > **Monitoring**
2. **System Info**: Thông tin hệ thống
3. **Health Check**: Kiểm tra sức khỏe
4. **Repository Check**: Kiểm tra repositories
5. **Background Jobs**: Sidekiq queues

### Log Files
```bash
# Application logs
docker exec gitlab tail -f /var/log/gitlab/gitlab-rails/production.log

# Nginx logs
docker exec gitlab tail -f /var/log/gitlab/nginx/gitlab_access.log
docker exec gitlab tail -f /var/log/gitlab/nginx/gitlab_error.log

# Sidekiq logs (background jobs)
docker exec gitlab tail -f /var/log/gitlab/sidekiq/current

# PostgreSQL logs
docker exec gitlab tail -f /var/log/gitlab/postgresql/current

# Redis logs
docker exec gitlab tail -f /var/log/gitlab/redis/current
```

### Performance Monitoring
```bash
# CPU và Memory usage
docker stats gitlab

# Disk usage
docker exec gitlab df -h

# GitLab specific metrics
docker exec gitlab gitlab-rake gitlab:env:info
```

---

## 💾 Backup & Restore

### Backup qua Admin Web UI
1. **Admin Area** > **Settings** > **Repository**
2. **Repository maintenance** > **Housekeeping**
3. **Export** > **GitLab export**

### Backup qua Command Line
```bash
# Backup toàn bộ GitLab
docker exec gitlab gitlab-backup create

# Backup với timestamp
docker exec gitlab gitlab-backup create BACKUP=$(date +%Y%m%d_%H%M%S)

# Liệt kê các backup có sẵn
docker exec gitlab ls -la /var/opt/gitlab/backups/
```

### Restore từ backup
```bash
# Stop services trước khi restore
docker exec gitlab gitlab-ctl stop puma
docker exec gitlab gitlab-ctl stop sidekiq

# Restore từ backup file
docker exec gitlab gitlab-backup restore BACKUP=backup_name

# Restart services
docker exec gitlab gitlab-ctl start
docker exec gitlab gitlab-rake gitlab:check SANITIZE=true
```

### Automated Backup với script
Sử dụng script có sẵn:
```bash
# Chạy backup ngay
./scripts/backup.sh

# Thiết lập backup tự động (đã cấu hình trong docker-compose.yml)
# Backup hàng ngày lúc 2:00 AM
```

---

## 🛠 Command Line Tools

### GitLab Rails Console
```bash
# Truy cập Rails console
docker exec -it gitlab gitlab-rails console

# Một số command hữu ích trong console:
# Liệt kê tất cả users
User.all.pluck(:username, :email, :admin)

# Tìm project theo tên
Project.find_by(name: 'project_name')

# Kiểm tra GitLab version
Gitlab::VERSION

# Kiểm tra database
ActiveRecord::Base.connection.execute("SELECT version();")
```

### GitLab Rake Tasks
```bash
# Kiểm tra hệ thống
docker exec gitlab gitlab-rake gitlab:check

# Import projects
docker exec gitlab gitlab-rake gitlab:import:repos['/path/to/repos']

# Reindex Elasticsearch (nếu có)
docker exec gitlab gitlab-rake gitlab:elastic:index

# Clear cache
docker exec gitlab gitlab-rake cache:clear

# Update project statistics
docker exec gitlab gitlab-rake gitlab:cleanup:project_uploads
```

### GitLab-CTL Commands
```bash
# Restart tất cả services
docker exec gitlab gitlab-ctl restart

# Status của services
docker exec gitlab gitlab-ctl status

# Restart specific service
docker exec gitlab gitlab-ctl restart nginx
docker exec gitlab gitlab-ctl restart puma

# View logs
docker exec gitlab gitlab-ctl tail
docker exec gitlab gitlab-ctl tail nginx
```

### Database Operations
```bash
# Database console
docker exec -it gitlab gitlab-psql

# Database backup
docker exec gitlab gitlab-ctl pg-dump gitlabhq_production > gitlab_db_backup.sql

# Check database size
docker exec gitlab gitlab-psql -c "SELECT pg_size_pretty(pg_database_size('gitlabhq_production'));"
```

---

## 🔒 Security Best Practices

### 1. Strong Passwords
- Sử dụng mật khẩu mạnh cho tài khoản root
- Bắt buộc users sử dụng mật khẩu mạnh
- Thiết lập password expiration

### 2. Two-Factor Authentication
```bash
# Bật 2FA cho admin
# Admin Area > Settings > General > Account and limit settings
# ☑ Require all users to set up Two-factor authentication
```

### 3. SSH Key Management
- Quản lý SSH keys của users
- **Admin Area** > **Users** > [user] > **SSH Keys**

### 4. Access Control
- Thiết lập IP whitelist
- **Admin Area** > **Settings** > **Network**

### 5. Audit Events
- Monitor admin activities
- **Admin Area** > **Monitoring** > **Audit Events**

---

## 🚨 Troubleshooting

### Common Admin Issues

#### 1. Cannot access Admin Area
```bash
# Kiểm tra user có quyền admin không
docker exec -it gitlab gitlab-rails console
user = User.find_by(username: 'your_username')
puts user.admin?
```

#### 2. GitLab web interface slow
```bash
# Kiểm tra resource usage
docker stats gitlab

# Restart Puma web server
docker exec gitlab gitlab-ctl restart puma
```

#### 3. Background jobs stuck
```bash
# Kiểm tra Sidekiq
docker exec gitlab gitlab-ctl status sidekiq

# Restart Sidekiq
docker exec gitlab gitlab-ctl restart sidekiq

# Monitor queues
docker exec gitlab gitlab-rake sidekiq:cron:list
```

#### 4. Database issues
```bash
# Database health check
docker exec gitlab gitlab-rake db:migrate:status

# Fix database
docker exec gitlab gitlab-rake db:migrate
```

---

## 📚 Tài liệu tham khảo

- [GitLab Administrator Documentation](https://docs.gitlab.com/ee/administration/)
- [GitLab Rails Console Commands](https://docs.gitlab.com/ee/administration/operations/rails_console.html)
- [GitLab Backup and Restore](https://docs.gitlab.com/ee/raketasks/backup_restore.html)
- [GitLab Troubleshooting](https://docs.gitlab.com/ee/administration/troubleshooting/)

---

## 🎯 Quick Commands Reference

```bash
# Login admin
Username: root
Password: [check initial_root_password or set via console]

# Reset root password
docker exec -it gitlab gitlab-rails console
User.find_by(username: 'root').update(password: 'new_pass', password_confirmation: 'new_pass')

# Create admin user
docker exec -it gitlab gitlab-rails console
User.create!(username: 'admin', email: 'admin@company.com', name: 'Admin', password: 'pass', password_confirmation: 'pass', admin: true, confirmed_at: Time.now)

# Check GitLab health
docker exec gitlab gitlab-rake gitlab:check

# Backup GitLab
docker exec gitlab gitlab-backup create

# View logs
docker exec gitlab gitlab-ctl tail

# Restart GitLab
docker exec gitlab gitlab-ctl restart
```

---

*💡 **Lưu ý**: Luôn backup dữ liệu trước khi thực hiện các thay đổi quan trọng!*
