# RUNBOOK — Chạy lab Module 1 trên Windows

Ghi chú riêng cho máy này (Windows 11, Docker Desktop, Git Bash, Anaconda Python 3.12).
Thư mục gốc của pack:

```
C:\Users\ASUS\Desktop\DE_BK\AI_Native_DE_Module1_Student_Pack_v3_Speaker_Notes\AI_Native_DE_Module1_Student_Pack_v3_Speaker_Notes
```

Mọi lệnh PowerShell bên dưới đều giả định bạn đã `cd` vào thư mục này:

```powershell
cd "C:\Users\ASUS\Desktop\DE_BK\AI_Native_DE_Module1_Student_Pack_v3_Speaker_Notes\AI_Native_DE_Module1_Student_Pack_v3_Speaker_Notes"
```

---

## 0. Setup 1 lần duy nhất (đã làm xong ngày 16/09/2026)

Máy có sẵn PostgreSQL 17 cài native, chiếm cổng 5432 và làm DBeaver báo
`FATAL: password authentication failed for user "de_user"`. Đã tắt nó đi:

```powershell
# PowerShell chạy bằng quyền Administrator
Stop-Service postgresql-x64-17
Set-Service postgresql-x64-17 -StartupType Manual
```

Tạo file `.env` từ mẫu:

```powershell
Copy-Item .env.example .env -Force
```

> Muốn dùng lại Postgres 17 native sau này: `Start-Service postgresql-x64-17`
> (nhớ `docker compose down` trước để hai bên không tranh cổng 5432).

---

## 1. Mỗi buổi học — khởi động

1. Mở **Docker Desktop**, đợi tới khi góc dưới trái báo *Engine running*.
2. Bật database:

```powershell
docker compose up -d postgres
```

3. Kiểm tra container đã `healthy`:

```powershell
docker ps --filter name=ecommerce-postgres
```

Kết quả mong đợi: `Up ... (healthy)` và `0.0.0.0:5432->5432/tcp`.

4. Test đăng nhập DB (không cần cài psql trên Windows, dùng psql trong container):

```powershell
docker exec ecommerce-postgres psql -U de_user -d ecommerce -c "\dn"
```

---

## 2. Thông số kết nối DBeaver

| Trường | Giá trị |
|---|---|
| Connect by | Host |
| Host | `localhost` |
| Port | `5432` |
| Database | `ecommerce` |
| Authentication | Username/password |
| Username | `de_user` |
| Password | `de_password` |
| Save password | tick |

Nếu DBeaver vẫn giữ lỗi cũ: chuột phải connection → **Invalidate/Reconnect**.

Nguồn của các giá trị này: `docker-compose.yml` và `.env.example`.

---

## 3. Buổi 1 — thiết kế ERD rồi tạo bảng

Database `ecommerce` lúc mới lên là **rỗng** (chưa có schema `core`) — đúng thiết kế
của khóa học, xem `database/README.md`.

Thứ tự làm:

1. Tự thiết kế ERD, export ra `database/ecommerce_oltp.dbml`.
2. Viết DDL vào `sql/student/01_create_oltp.sql` (script bootstrap sẽ chạy đúng file này).
3. Chạy bootstrap để tạo schema + nạp seed data.

### Cách chạy bootstrap trên Windows

Script là `.sh` nên chạy bằng **Git Bash** (đã có sẵn tại `C:\Program Files\Git\bin\bash.exe`):

```powershell
& "C:\Program Files\Git\bin\bash.exe" ./scripts/bootstrap.sh
```

Script sẽ: bật postgres → `DROP SCHEMA core, mart` → chạy SQL của bạn → `docker cp` 6 file
CSV trong `data/seed/` vào container → `\copy` vào các bảng `core.*`.

Nếu script dừng ở bước `[3/4]` nghĩa là DDL của bạn còn lỗi — sửa
`sql/student/01_create_oltp.sql` rồi chạy lại. Chạy lại bao nhiêu lần cũng được vì
script tự drop schema trước.

Kiểm tra sau khi bootstrap xong:

```powershell
docker exec ecommerce-postgres psql -U de_user -d ecommerce -c "\dt core.*"
docker exec ecommerce-postgres psql -U de_user -d ecommerce -c "select count(*) from core.orders;"
```

---

## 4. Từ Buổi 5 — Python

Máy đang có Anaconda Python 3.12 (pack gợi ý 3.11, 3.12 thường vẫn chạy được).

```powershell
if (-not (Test-Path src)) { Copy-Item -Recurse starter/src src }
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Lần sau chỉ cần activate lại:

```powershell
.\.venv\Scripts\Activate.ps1
```

> Nếu PowerShell chặn script activate:
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

---

## 5. Từ Buổi 6 — Mock REST API

```powershell
docker compose up -d mock-api
```

Kiểm tra:

```powershell
curl http://localhost:8000/health
```

API key dùng trong `.env`: `training-key` (biến `MOCK_API_KEY`).

---

## 6. Tắt / dọn dẹp

```powershell
# Tắt container, GIỮ nguyên dữ liệu
docker compose stop

# Tắt và xóa container, vẫn GIỮ dữ liệu (nằm trong volume)
docker compose down

# XÓA SẠCH dữ liệu database (volume) — chỉ dùng khi muốn làm lại từ đầu
docker compose down -v
```

Sau `down -v` thì phải chạy lại bootstrap ở mục 3 để có bảng và data.

---

## 7. Sự cố hay gặp

**`FATAL: password authentication failed for user "de_user"`**
Bạn đang nối vào một PostgreSQL khác chứ không phải container. Kiểm tra ai đang giữ cổng 5432:

```powershell
$p = (Get-NetTCPConnection -LocalPort 5432 -State Listen | Select-Object -First 1).OwningProcess
Get-Process -Id $p | Select-Object Id, ProcessName
```

- `wslrelay` hoặc `com.docker.backend` → đúng, là Docker.
- `postgres` → là Postgres native đang chạy, tắt bằng `Stop-Service postgresql-x64-17` (quyền Admin).

**`Connection refused` / `could not connect`**
Docker Desktop chưa chạy, hoặc container chưa lên. Chạy lại mục 1.

**`docker: failed to connect to the docker API`**
Docker Desktop chưa khởi động xong. Đợi *Engine running* rồi thử lại.

**`port is already allocated` khi `docker compose up`**
Có process khác đang giữ 5432 — xem lại phần kiểm tra cổng ở trên.

**Xem log database**

```powershell
docker logs --tail 50 ecommerce-postgres
```
