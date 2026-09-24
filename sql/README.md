# Hướng dẫn chạy SQL scripts

Thư mục này chứa toàn bộ script SQL của Module 1. Các file được đánh số theo
thứ tự phải chạy — **không được đảo thứ tự** vì script sau phụ thuộc bảng do
script trước tạo ra.

| Thứ tự | File | Buổi | Mục đích |
|---|---|---|---|
| 1 | `student/01_create_oltp.sql` | 01 | Tạo schema `core` (OLTP normalized) + seed bảng tra cứu `order_status` |
| 2 | `student/02_exercises_basic.sql` | 02 | Truy vấn SQL cơ bản |
| 3 | `student/03_exercises_advanced.sql` | 03 | Truy vấn nâng cao cho KPI |
| 3 | `student/03_cte_window_cohort.sql` | 03 | CTE, window functions, RFM, cohort retention |
| 4 | `student/04_data_mart.sql` | 04 | Star schema cho `mart` |

## Bước 1 — Khởi động database

```powershell
docker compose up -d postgres
docker compose ps        # phải thấy ecommerce-postgres ... Up (healthy)
```

Thông số kết nối (khớp `docker-compose.yml` và `.env.example`):

| Host | Port | Database | User | Password |
|---|---|---|---|---|
| localhost | 5432 | ecommerce | de_user | de_password |

## Bước 2 — Chạy DDL tạo bảng

Cách A — dùng script bootstrap (khuyến nghị, tạo bảng **và** nạp luôn seed data):

```powershell
& "C:\Program Files\Git\bin\bash.exe" ./scripts/bootstrap.sh
```

Script này drop `core`/`mart`, chạy `student/01_create_oltp.sql`, rồi `\copy`
6 file CSV trong `data/seed/` vào các bảng tương ứng. Chạy lại nhiều lần được.

Cách B — chỉ chạy DDL, không nạp data:

```powershell
Get-Content sql/student/01_create_oltp.sql | docker exec -i ecommerce-postgres psql -U de_user -d ecommerce -v ON_ERROR_STOP=1
```

Cách C — chạy trong DBeaver: mở file, chọn toàn bộ, Execute script (Alt+X).

## Bước 3 — Verify

```powershell
docker exec ecommerce-postgres psql -U de_user -d ecommerce -c "\dt core.*"
```

Kết quả đúng: **7 bảng** — `order_status`, `categories`, `customers`,
`products`, `orders`, `order_items`, `payments`.

Kiểm tra số dòng sau khi nạp seed:

```powershell
docker exec ecommerce-postgres psql -U de_user -d ecommerce -c "SELECT 'orders' t, count(*) FROM core.orders UNION ALL SELECT 'order_items', count(*) FROM core.order_items UNION ALL SELECT 'payments', count(*) FROM core.payments;"
```

Số dòng mong đợi: categories 20, customers 1000, products 500, orders 5000,
order_items 12717, payments 4517, order_status 5.

Output đầy đủ của bước verify được lưu tại `docs/evidence/1.1/01-verify-db-full.txt`.

## Thứ tự phụ thuộc giữa các bảng

Phải tạo bảng cha trước bảng con, vì FK không tham chiếu được tới bảng chưa tồn tại:

```
order_status ──┐
               ├──> orders ──┬──> order_items
customers ─────┘             └──> payments
categories ──> products ─────────> order_items
categories ──> categories (tự tham chiếu)
```

Thứ tự tạo trong `01_create_oltp.sql`: `order_status` → `categories` →
`customers` → `products` → `orders` → `order_items` → `payments`.

## Reset toàn bộ

```powershell
& "C:\Program Files\Git\bin\bash.exe" ./scripts/reset.sh
```

Lệnh này chạy `docker compose down -v` (**xóa sạch volume, mất hết dữ liệu**)
rồi bootstrap lại từ đầu.

## Lỗi thường gặp

| Lỗi | Nguyên nhân | Xử lý |
|---|---|---|
| `password authentication failed for user "de_user"` | Đang nối vào PostgreSQL khác đang chiếm cổng 5432 | Xem `RUNBOOK_WINDOWS.md`, tắt service Postgres native |
| `relation "core.customers" does not exist` | Chưa chạy `01_create_oltp.sql` | Chạy Bước 2 |
| `violates foreign key constraint` khi nạp CSV | Nạp bảng con trước bảng cha | Dùng `scripts/bootstrap.sh`, đã đúng thứ tự |
| `constraint ... already exists` | Chạy lại phần Bonus trên DB cũ | File đã viết `DROP CONSTRAINT IF EXISTS` trước mỗi `ADD`, chạy lại được |
