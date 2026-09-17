# 2.2 — Documentation

Đề bài yêu cầu 2 artifact, cả hai đều phải nằm đúng vị trí quy định nên không
copy vào đây:

1. **Hướng dẫn chạy scripts theo thứ tự** (tạo DB → chạy `01_create_oltp.sql`
   → verify) → [../../../sql/README.md](../../../sql/README.md)

2. **Comment ghi chú quan hệ cha–con và ý nghĩa FK ngay trong file SQL** →
   [../../../sql/student/01_create_oltp.sql](../../../sql/student/01_create_oltp.sql)

   Phần sơ đồ quan hệ nằm ở block comment đầu file; mỗi `CREATE TABLE` có
   comment nói rõ bảng đó là cha hay con của bảng nào và ứng với business rule
   số mấy trong `docs/business_requirements.md`.
