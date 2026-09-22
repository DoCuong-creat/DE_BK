# Buổi 02 — Trả lời 5 Business Questions

Database: `ecommerce` / schema `core` (đã nạp `ecommerce_lab2_ready_database_v2.sql`).
Phạm vi dữ liệu: **2026-01-01 → 2026-06-29**, 5000 orders / 1000 customers / 12717 order_items / 4517 payments.

Định nghĩa doanh thu dùng xuyên suốt: đơn có `status = 'completed'`, theo
`docs/business_requirements.md`. Output chạy lại: `docs/evidence/buoi-02/1.4/02-business-results.txt`.

---

## B1. Total revenue tháng 7/2026 là bao nhiêu?

```sql
SELECT COALESCE(SUM(order_total), 0) AS revenue_thang_07_2026,
       COUNT(*) AS so_don
FROM core.orders
WHERE status = 'completed'
  AND order_date >= DATE '2026-07-01'
  AND order_date <  DATE '2026-08-01';
```

**Đáp án: 0 VND (0 đơn).**

Nhận xét: không phải doanh thu sụt về 0 mà là **dữ liệu chưa có tháng 7** — `MAX(order_date)` của bảng `orders` là 2026-06-29. Batch tháng 7 nằm ở `data/incremental/day_2026-07-01/` (600 đơn) và chỉ được nạp từ Buổi 5–6. Để có số đối chiếu, doanh thu **tháng 6/2026 là 7.756.301.000 VND / 626 đơn**.

---

## B2. Customer nào có tổng chi tiêu cao nhất?

```sql
SELECT c.customer_id, c.full_name, c.customer_segment,
       COUNT(o.order_id) AS so_don,
       SUM(o.order_total) AS tong_chi_tieu
FROM core.customers c
JOIN core.orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.full_name, c.customer_segment
ORDER BY tong_chi_tieu DESC
LIMIT 1;
```

**Đáp án: `CUS000575` — Jessica Marquez (Gold) — 209.701.000 VND / 15 đơn.**

Nhận xét: đây là khách có số đơn nhiều nhất toàn tập (15 đơn) chứ không phải khách có đơn giá trị lớn nhất — tổng chi tiêu cao đến từ tần suất mua. Nếu chỉ tính đơn `completed` thì ngôi đầu đổi thành `CUS000736` — Gordon Rogers — 173.654.000 VND, cho thấy một phần đơn của Jessica Marquez chưa ở trạng thái hoàn tất.

---

## B3. Category nào có số lượng orders cao nhất?

```sql
SELECT cat.category_id, cat.category_name,
       COUNT(DISTINCT o.order_id) AS so_don
FROM core.order_items oi
JOIN core.orders o      ON o.order_id = oi.order_id
JOIN core.products p    ON p.product_id = oi.product_id
JOIN core.categories cat ON cat.category_id = p.category_id
GROUP BY cat.category_id, cat.category_name
ORDER BY so_don DESC
LIMIT 1;
```

**Đáp án: `CAT009` — Kitchen — 1.046 đơn.**

Nhận xét: xếp theo **số đơn** thì Kitchen dẫn đầu (1.046 đơn), nhưng xếp theo **doanh thu** thì Skincare mới đứng nhất (4.776.238.500 VND, 9,93% tổng). Nghĩa là Kitchen bán nhiều đơn giá trị nhỏ, Skincare ít đơn hơn nhưng giá trị mỗi đơn cao hơn.

---

## B4. Average Order Value (AOV) là bao nhiêu?

```sql
SELECT ROUND(AVG(order_total), 2) AS aov,
       COUNT(*) AS so_don,
       SUM(order_total) AS tong_doanh_thu
FROM core.orders
WHERE status = 'completed';
```

**Đáp án: 12.391.222,68 VND** (3.880 đơn completed, tổng 48.077.944.000 VND).

Nhận xét: con số này khớp đúng với giá trị kỳ vọng ghi ở cuối file `ecommerce_lab2_ready_database_v2.sql` (`AOV=12391222.68`) → phép tính đã đối soát được. Nếu tính trên toàn bộ 5000 đơn (mọi trạng thái) thì AOV là 12.341.286,40 VND, thấp hơn không đáng kể.

---

## B5. Có bao nhiêu customers có hơn 3 orders?

```sql
SELECT COUNT(*) AS so_customer_tren_3_don
FROM (
    SELECT customer_id
    FROM core.orders
    GROUP BY customer_id
    HAVING COUNT(*) > 3
) t;
```

**Đáp án: 719 khách hàng.**

Nhận xét: 719/994 khách có phát sinh đơn, tức **72,3% khách mua trên 3 lần** — tỷ lệ quay lại rất cao. Phân bố đỉnh ở mức 5 đơn/khách (176 khách), khách nhiều đơn nhất có 15 đơn, và chỉ 6 khách trong tổng 1000 chưa từng mua lần nào.
