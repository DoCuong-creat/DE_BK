-- =============================================================================
-- 04_kpi_from_mart.sql  |  Module 1 - Session 04
-- 5 KPI chỉ đọc từ schema mart (fact_sales JOIN dims), KHÔNG JOIN bảng core.*.
--
-- Chạy:  psql -U de_user -d ecommerce -f sql/student/04_kpi_from_mart.sql
-- Quy ước doanh thu: chỉ tính đơn có dim_order_status.is_revenue = TRUE
-- (= 'completed', business rule #5). revenue trong fact là net (đã trừ discount).
-- =============================================================================

SET search_path TO mart;

-- KPI1: Total revenue by month
SELECT d.year_month,
       COUNT(DISTINCT f.order_id) AS orders,
       SUM(f.revenue)             AS revenue
FROM fact_sales f
JOIN dim_date d         ON d.date_key = f.date_key
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY d.year_month
ORDER BY d.year_month;

-- KPI2: Revenue by category (danh mục cha + tỷ trọng)
SELECT p.parent_category                                      AS category,
       SUM(f.revenue)                                         AS revenue,
       ROUND(100.0 * SUM(f.revenue) / SUM(SUM(f.revenue)) OVER (), 2) AS pct_of_total
FROM fact_sales f
JOIN dim_product p      ON p.product_key = f.product_key
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY p.parent_category
ORDER BY revenue DESC;

-- KPI3: Top 10 products theo revenue
SELECT p.product_id,
       p.product_name,
       p.category,
       SUM(f.quantity) AS units_sold,
       SUM(f.revenue)  AS revenue
FROM fact_sales f
JOIN dim_product p      ON p.product_key = f.product_key
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY p.product_id, p.product_name, p.category
ORDER BY revenue DESC, p.product_id
LIMIT 10;

-- KPI4: AOV = SUM(revenue) / COUNT(DISTINCT order_id)
SELECT SUM(f.revenue)                                           AS revenue,
       COUNT(DISTINCT f.order_id)                               AS orders,
       ROUND(SUM(f.revenue) / COUNT(DISTINCT f.order_id), 2)    AS aov
FROM fact_sales f
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue;

-- KPI5: Customer count by segment / region (city)
-- 5a. Theo segment: số khách có đơn completed + doanh thu
SELECT c.customer_segment,
       COUNT(DISTINCT f.customer_key)                                  AS customers,
       SUM(f.revenue)                                                  AS revenue,
       ROUND(SUM(f.revenue) / COUNT(DISTINCT f.customer_key), 2)       AS revenue_per_customer
FROM fact_sales f
JOIN dim_customer c     ON c.customer_key = f.customer_key
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY c.customer_segment
ORDER BY revenue DESC;

-- 5b. Theo region (city của khách hàng)
SELECT c.city                         AS region,
       COUNT(DISTINCT f.customer_key) AS customers,
       SUM(f.revenue)                 AS revenue
FROM fact_sales f
JOIN dim_customer c     ON c.customer_key = f.customer_key
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY c.city
ORDER BY customers DESC, region;
