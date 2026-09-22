-- Buổi 3
-- TODO 1: Refactor business report bằng CTE nhiều bước.
-- TODO 2: Running revenue theo ngày.
-- TODO 3: DENSE_RANK product trong từng category.
-- TODO 4: first_purchase, recency, frequency, monetary.
-- TODO 5: cohort_month × activity_month.


-- =============================================================================
-- Bonus 2.1 (Buổi 2) — Advanced Analytics
-- Database: ecommerce | Schema: core
-- =============================================================================

SET search_path TO core, public;

-- Bonus 2.1 - Query 1: Cumulative revenue theo thời gian.
-- Window function SUM(...) OVER (ORDER BY thang) cộng dồn doanh thu các tháng
-- trước đó, dùng để vẽ đường doanh thu lũy kế trên dashboard.
WITH revenue_thang AS (
    SELECT DATE_TRUNC('month', order_date)::date AS thang,
           SUM(order_total) AS doanh_thu
    FROM orders
    WHERE status = 'completed'
    GROUP BY 1
)
SELECT thang,
       doanh_thu,
       SUM(doanh_thu) OVER (ORDER BY thang) AS doanh_thu_luy_ke
FROM revenue_thang
ORDER BY thang;

-- Bonus 2.1 - Query 2: Tỷ trọng doanh thu từng category.
-- SUM(...) OVER () không có PARTITION -> tính tổng toàn bộ, lấy doanh thu từng
-- category chia cho tổng đó để ra phần trăm đóng góp.
WITH revenue_category AS (
    SELECT cat.category_id, cat.category_name,
           SUM(oi.quantity * oi.unit_price - oi.discount_amount) AS doanh_thu
    FROM order_items oi
    JOIN orders o     ON o.order_id = oi.order_id
    JOIN products p   ON p.product_id = oi.product_id
    JOIN categories cat ON cat.category_id = p.category_id
    WHERE o.status = 'completed'
    GROUP BY cat.category_id, cat.category_name
)
SELECT category_id, category_name, doanh_thu,
       ROUND(100.0 * doanh_thu / SUM(doanh_thu) OVER (), 2) AS ty_trong_pct,
       ROUND(100.0 * SUM(doanh_thu) OVER (ORDER BY doanh_thu DESC)
                   / SUM(doanh_thu) OVER (), 2) AS ty_trong_luy_ke_pct
FROM revenue_category
ORDER BY doanh_thu DESC;

-- Bonus 2.1 - Query 3: Customers "churn".
-- Định nghĩa: khách không phát sinh đơn nào trong 30 ngày gần nhất, mốc thời
-- gian lấy theo MAX(order_date) của toàn hệ thống (không dùng NOW() vì dữ liệu
-- seed dừng ở 2026-06-29, dùng NOW() sẽ coi 100% khách là churn).
WITH moc_thoi_gian AS (
    SELECT MAX(order_date) AS ngay_cuoi FROM orders
),
lan_mua_cuoi AS (
    SELECT o.customer_id,
           MAX(o.order_date) AS lan_mua_cuoi,
           COUNT(*) AS so_don,
           SUM(o.order_total) AS tong_chi_tieu
    FROM orders o
    GROUP BY o.customer_id
)
SELECT c.customer_id, c.full_name, c.customer_segment,
       l.lan_mua_cuoi::date AS lan_mua_cuoi,
       (SELECT ngay_cuoi FROM moc_thoi_gian)::date AS moc_doi_chieu,
       EXTRACT(DAY FROM (SELECT ngay_cuoi FROM moc_thoi_gian) - l.lan_mua_cuoi)::int AS so_ngay_khong_mua,
       l.so_don, l.tong_chi_tieu
FROM lan_mua_cuoi l
JOIN customers c ON c.customer_id = l.customer_id
WHERE l.lan_mua_cuoi < (SELECT ngay_cuoi FROM moc_thoi_gian) - INTERVAL '30 days'
ORDER BY so_ngay_khong_mua DESC;
