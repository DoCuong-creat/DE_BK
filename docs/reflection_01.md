# Reflection — Buổi 01: Thiết kế Database & Khởi động hệ thống

**1. Khó khăn khi cài Docker/DBeaver.**
DBeaver báo `FATAL: password authentication failed for user "de_user"` dù
thông số đã đúng. Kiểm chứng bằng `Get-NetTCPConnection -LocalPort 5432`: cổng
do process `postgres` giữ chứ không phải `wslrelay` của Docker — máy đã cài sẵn
PostgreSQL 17 native, DBeaver nối nhầm vào đó. Xử lý: `Stop-Service
postgresql-x64-17` rồi `docker compose up -d postgres`.

**2. Vì sao chọn data type như vậy.**
Tiền dùng `NUMERIC(14,2)` chứ không dùng FLOAT, vì FLOAT lưu nhị phân nên sai
số tích lũy khi `SUM(order_total)` trên 5000 đơn sẽ làm lệch doanh thu. Thời
gian dùng `TIMESTAMPTZ` vì dữ liệu nguồn có offset `+07:00`. ID giữ mã nghiệp
vụ VARCHAR (`CUS000001`) thay vì SERIAL, để không mất khóa của hệ thống nguồn
và để pipeline `ON CONFLICT DO UPDATE` chạy lại không sinh trùng.

**3. Quan hệ 1:N giữa customers và orders.**
Một khách có nhiều đơn, mỗi đơn chỉ thuộc một khách, thể hiện bằng FK
`orders.customer_id`. Ví dụ `CUS000575` có 15 đơn: `ORD003920`, `ORD000008`,
`ORD004703`...

**4. Nếu schema cần sửa sau này.**
Ưu tiên `ALTER TABLE` và lưu thành migration script đánh số, chạy tuần tự để
không mất dữ liệu. Chỉ tạo lại bảng khi ở môi trường dev và chưa có dữ liệu thật.
