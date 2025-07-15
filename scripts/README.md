# 🔧 GitLab Scripts

Thư mục này chứa các script để quản lý GitLab on-premise.

## 📋 Danh sách Scripts

### 🔄 Backup & Restore

| Script | Mô tả | Sử dụng |
|--------|-------|---------|
| `backup.sh` | Tạo backup thủ công | `./backup.sh [tên_backup]` |
| `restore.sh` | Khôi phục từ backup | `./restore.sh <tên_backup>` |
| `backup-cron.sh` | Script backup tự động (chạy trong container) | Tự động theo lịch |
| `backup-manager.sh` | Quản lý backup tổng hợp | `./backup-manager.sh [command]` |

### 🚀 Sử dụng nhanh

```bash
# Tạo backup thủ công
./scripts/backup.sh

# Tạo backup với tên cụ thể
./scripts/backup.sh pre_upgrade_v16_4

# Xem danh sách backup
./scripts/backup-manager.sh list

# Khôi phục từ backup
./scripts/restore.sh manual_20240715_140000

# Kiểm tra trạng thái backup
./scripts/backup-manager.sh status

# Dọn dẹp backup cũ
./scripts/backup-manager.sh cleanup 14
```

## 🔐 Permissions

Đảm bảo các script có quyền thực thi:

```bash
chmod +x scripts/*.sh
```

## 📊 Backup Manager Commands

```bash
# Hiển thị help
./scripts/backup-manager.sh help

# Liệt kê tất cả backup
./scripts/backup-manager.sh list

# Kiểm tra trạng thái dịch vụ backup
./scripts/backup-manager.sh status

# Tạo backup thủ công
./scripts/backup-manager.sh create [tên]

# Khôi phục từ backup
./scripts/backup-manager.sh restore <tên>

# Dọn dẹp backup cũ (>7 ngày)
./scripts/backup-manager.sh cleanup [số_ngày]

# Kiểm tra tính toàn vẹn backup
./scripts/backup-manager.sh verify <tên>

# Xem kích thước backup
./scripts/backup-manager.sh size

# Xem logs backup
./scripts/backup-manager.sh logs

# Test backup/restore
./scripts/backup-manager.sh test
```

## 🕐 Backup Schedule

Backup tự động được cấu hình trong `.env`:

```env
BACKUP_SCHEDULE=0 2 * * *  # Hàng ngày lúc 2:00 AM
BACKUP_RETENTION_DAYS=7    # Giữ backup 7 ngày
```

## 📁 Backup Structure

```
backups/
├── manual_20240715_140000_gitlab_backup.tar     # Application data
├── manual_20240715_140000_config.tar.gz         # Configuration
├── manual_20240715_140000_secrets.json          # Secrets
├── auto_20240716_020000_gitlab_backup.tar       # Auto backup
└── ...
```

## 🔍 Troubleshooting

### Script không chạy được

```bash
# Kiểm tra permissions
ls -la scripts/

# Cấp quyền thực thi
chmod +x scripts/*.sh

# Kiểm tra shell
head -1 scripts/backup.sh
```

### Backup thất bại

```bash
# Kiểm tra container GitLab
docker ps | grep gitlab

# Kiểm tra logs
docker logs gitlab

# Kiểm tra dung lượng disk
df -h

# Kiểm tra quyền ghi thư mục backup
ls -la backups/
```

### Restore thất bại

```bash
# Kiểm tra file backup có tồn tại
ls -la backups/

# Kiểm tra tính toàn vẹn file backup
./scripts/backup-manager.sh verify <tên_backup>

# Kiểm tra GitLab container
docker exec gitlab gitlab-ctl status
```

## 📝 Logs

Logs của backup được lưu tại:

- **Container logs**: `docker logs gitlab-backup`
- **Application logs**: `./data/logs/gitlab-rails/production.log`
- **Backup logs**: Trong container backup hoặc sử dụng `backup-manager.sh logs`

## 🔗 Liên quan

- [CONFIG_GUIDE.md](../docs/CONFIG_GUIDE.md) - Hướng dẫn cấu hình chi tiết
- [README.md](../README.md) - Hướng dẫn triển khai tổng quát
