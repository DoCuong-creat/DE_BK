-- =============================================================================
-- 02_exercises_basic.sql | Module 1 - Session 02
-- SQL Fundamentals & Business Analytics
--
-- Database: ecommerce | Schema: core | PostgreSQL 16
-- Chay:  docker exec -i ecommerce-postgres psql -U de_user -d ecommerce -f <file>
--
-- ÁNH XẠ TÊN CỘT: đề bài viết theo tên "generic", schema thực tế khác một chút
--   đề: orders.total_amount   -> thực tế: orders.order_total
--   đề: orders.id             -> thực tế: orders.order_id
--   đề: customers.id          -> thực tế: customers.customer_id
--   đề: order_items.id        -> thực tế: order_items.order_item_id
--   đề: products.price        -> thực tế: products.unit_price
--   đề: order_status          -> thực tế: orders.status
--
-- ĐỊNH NGHĨA DOANH THU (theo docs/business_requirements.md):
--   Revenue net = SUM(quantity * unit_price - discount_amount) của đơn completed.
--   Khi đề yêu cầu dùng total_amount thì dùng orders.order_total, có ghi chú rõ.
-- =============================================================================

SET search_path TO core, public;

-- #############################################################################
-- 1.1 BASIC QUERIES (Q1 - Q5)
-- #############################################################################

-- Q1: SELECT with filtering - tất cả orders có total_amount > 100.
-- Lưu ý: dữ liệu tính bằng VND nên mọi đơn đều lớn hơn 100 -> điều kiện này
-- không lọc được gì (trả về đủ 5000 dòng). Xem Q1b cho ngưỡng thực tế.
SELECT order_id, customer_id, order_date, status, order_total
FROM orders
WHERE order_total > 100
ORDER BY order_total DESC;

-- Q1b: cùng ý tưởng nhưng dùng ngưỡng có nghĩa với đơn vị VND (> 20 triệu).
SELECT order_id, customer_id, order_date, status, order_total
FROM orders
WHERE order_total > 20000000
ORDER BY order_total DESC;

-- Q2: NULL handling - customers chưa phát sinh đơn hàng nào.
SELECT c.customer_id, c.full_name, c.email, c.city, c.customer_segment
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL
ORDER BY c.customer_id;

-- Q3: ORDER BY - top 10 customers theo tổng chi tiêu (tính trên orders).
SELECT c.customer_id, c.full_name, c.customer_segment,
       COUNT(o.order_id) AS so_don,
       SUM(o.order_total) AS tong_chi_tieu
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.full_name, c.customer_segment
ORDER BY tong_chi_tieu DESC
LIMIT 10;

-- Q4: COUNT/DISTINCT - số customers khác nhau đã từng có đơn hàng.
SELECT COUNT(DISTINCT customer_id) AS so_customer_co_don,
       (SELECT COUNT(*) FROM customers) AS tong_so_customer
FROM orders;

-- Q5: LIMIT - 5 orders mới nhất theo order_date.
SELECT order_id, customer_id, order_date, status, channel, order_total
FROM orders
ORDER BY order_date DESC
LIMIT 5;

-- #############################################################################
-- 1.2 AGGREGATE & GROUPING (Q6 - Q10)
-- #############################################################################

-- Q6: Tổng doanh thu theo từng tháng (chỉ tính đơn completed).
SELECT DATE_TRUNC('month', order_date)::date AS thang,
       COUNT(*) AS so_don,
       SUM(order_total) AS doanh_thu
FROM orders
WHERE status = 'completed'
GROUP BY 1
ORDER BY 1;

-- Q7: Trung bình giá trị đơn hàng theo từng customer (top 20 theo AOV).
SELECT customer_id,
       COUNT(*) AS so_don,
       ROUND(AVG(order_total), 2) AS aov_khach
FROM orders
GROUP BY customer_id
ORDER BY aov_khach DESC
LIMIT 20;

-- Q8: Số lượng đơn hàng theo từng order_status.
SELECT status,
       COUNT(*) AS so_don,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS ty_trong_pct
FROM orders
GROUP BY status
ORDER BY so_don DESC;

-- Q9: Tổng doanh thu theo category (order_items -> products -> categories).
-- Revenue net = quantity * unit_price - discount_amount, chỉ đơn completed.
SELECT cat.category_id, cat.category_name,
       COUNT(DISTINCT o.order_id) AS so_don,
       SUM(oi.quantity) AS so_luong_ban,
       SUM(oi.quantity * oi.unit_price - oi.discount_amount) AS doanh_thu
FROM order_items oi
JOIN orders o     ON o.order_id = oi.order_id
JOIN products p   ON p.product_id = oi.product_id
JOIN categories cat ON cat.category_id = p.category_id
WHERE o.status = 'completed'
GROUP BY cat.category_id, cat.category_name
ORDER BY doanh_thu DESC;

-- Q10: HAVING - categories có tổng doanh thu > 1000.
-- Với đơn vị VND thì mọi category có bán hàng đều vượt ngưỡng 1000 -> HAVING
-- không lọc được gì, trả về đủ 15 dòng. (Chỉ 15/20 category xuất hiện vì
-- CAT001-CAT005 là category gốc, không gắn sản phẩm nào.)
-- Q10b bên dưới dùng ngưỡng 1 tỷ VND để HAVING thực sự có tác dụng.
SELECT cat.category_name,
       SUM(oi.quantity * oi.unit_price - oi.discount_amount) AS doanh_thu
FROM order_items oi
JOIN orders o     ON o.order_id = oi.order_id
JOIN products p   ON p.product_id = oi.product_id
JOIN categories cat ON cat.category_id = p.category_id
WHERE o.status = 'completed'
GROUP BY cat.category_name
HAVING SUM(oi.quantity * oi.unit_price - oi.discount_amount) > 1000
ORDER BY doanh_thu DESC;

-- Q10b: HAVING với ngưỡng thực tế 1 tỷ VND.
SELECT cat.category_name,
       SUM(oi.quantity * oi.unit_price - oi.discount_amount) AS doanh_thu
FROM order_items oi
JOIN orders o     ON o.order_id = oi.order_id
JOIN products p   ON p.product_id = oi.product_id
JOIN categories cat ON cat.category_id = p.category_id
WHERE o.status = 'completed'
GROUP BY cat.category_name
HAVING SUM(oi.quantity * oi.unit_price - oi.discount_amount) > 1000000000
ORDER BY doanh_thu DESC;

-- #############################################################################
-- 1.3 JOIN OPERATIONS (Q11 - Q15)
-- #############################################################################

-- Q11: Orders kèm customer_name, customer_email (INNER JOIN).
SELECT o.order_id, o.order_date, o.status, o.order_total,
       c.full_name AS customer_name, c.email AS customer_email
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
ORDER BY o.order_date DESC
LIMIT 20;

-- Q12: Chi tiết order_items kèm product_name, price.
SELECT oi.order_item_id, oi.order_id,
       p.product_name, oi.quantity, oi.unit_price, oi.discount_amount,
       (oi.quantity * oi.unit_price - oi.discount_amount) AS thanh_tien
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
ORDER BY oi.order_id, oi.order_item_id
LIMIT 20;

-- Q13: LEFT JOIN + IS NULL - orders có payment nhưng KHÔNG có order_item nào.
SELECT DISTINCT o.order_id, o.order_date, o.status, o.order_total
FROM orders o
JOIN payments pay ON pay.order_id = o.order_id
LEFT JOIN order_items oi ON oi.order_id = o.order_id
WHERE oi.order_item_id IS NULL
ORDER BY o.order_id;

-- Q14: Products chưa từng được bán.
SELECT p.product_id, p.product_name, p.unit_price, p.status
FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.product_id
WHERE oi.order_item_id IS NULL
ORDER BY p.product_id;

-- Q15: ĐỐI SOÁT - orders.order_total so với SUM(quantity*unit_price - discount).
SELECT o.order_id,
       o.order_total                                               AS tong_tren_don,
       SUM(oi.quantity * oi.unit_price - oi.discount_amount)       AS tong_tu_dong_hang,
       o.order_total - SUM(oi.quantity * oi.unit_price - oi.discount_amount) AS chenh_lech
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.order_total
ORDER BY ABS(o.order_total - SUM(oi.quantity * oi.unit_price - oi.discount_amount)) DESC,
         o.order_id
LIMIT 10;

-- Q15b: Đếm tổng số đơn bị lệch (0 = toàn bộ khớp).
SELECT COUNT(*) AS so_don_lech
FROM (
    SELECT o.order_id
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY o.order_id, o.order_total
    HAVING ABS(o.order_total - SUM(oi.quantity * oi.unit_price - oi.discount_amount)) > 0.01
) t;
