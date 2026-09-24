-- =============================================================================
-- 03_cte_window_cohort.sql | Module 1 - Session 03
-- SQL nâng cao - Customer Analytics & Cohort
--
-- Database: ecommerce | Schema: core | PostgreSQL 16
-- Chay:  docker exec -i ecommerce-postgres psql -U de_user -d ecommerce -f <file>
--
-- ÁNH XẠ TÊN CỘT (giống buổi 2):
--   đề: orders.total_amount  -> thực tế: orders.order_total
--   đề: orders.id            -> thực tế: orders.order_id
--
-- PHẠM VI DỮ LIỆU:
--   * Hành vi khách hàng (CTE, W1-W4, RFM, Cohort): đơn "hợp lệ" = mọi đơn trừ
--     'cancelled'. Đơn pending/confirmed/shipped vẫn là một lần khách quay lại
--     mua, nên được tính vào frequency/retention.
--   * Doanh thu (W5, Bonus timeseries): chỉ đơn 'completed', đúng định nghĩa
--     KPI Total Revenue trong docs/business_requirements.md.
--   * Dữ liệu seed: 2026-01-01 -> 2026-06-29, đơn vị VND.
-- =============================================================================

SET search_path TO core, public;

-- #############################################################################
-- 1.1 CTE REFACTORING (CTE1 - CTE5)
-- #############################################################################

-- CTE1: Top 10 customers theo total spending.
-- CTE customer_spending gom tổng chi tiêu mỗi khách, SELECT bên ngoài chỉ việc
-- JOIN lấy thông tin khách rồi lọc top 10.
WITH customer_spending AS (
    SELECT customer_id,
           COUNT(*)         AS order_count,
           SUM(order_total) AS total_spending
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
)
SELECT cs.customer_id, c.full_name, c.customer_segment,
       cs.order_count, cs.total_spending
FROM customer_spending cs
JOIN customers c ON c.customer_id = cs.customer_id
ORDER BY cs.total_spending DESC
LIMIT 10;

-- CTE2: Phân tầng khách Low / Medium / High bằng CASE WHEN trên CTE.
-- Ngưỡng đề bài (500 / 2000) viết cho dữ liệu USD; dữ liệu ở đây là VND với
-- trung vị chi tiêu ~55 triệu/khách, nên quy đổi sang TRIỆU VND:
--   Low < 50 triệu | Medium 50 - 100 triệu | High > 100 triệu.
WITH customer_spending AS (
    SELECT customer_id,
           SUM(order_total) AS total_spending
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
),
customer_tier AS (
    SELECT customer_id,
           total_spending,
           CASE
               WHEN total_spending < 50000000   THEN 'Low'
               WHEN total_spending <= 100000000 THEN 'Medium'
               ELSE 'High'
           END AS spending_tier
    FROM customer_spending
)
SELECT spending_tier,
       COUNT(*)                                          AS customer_count,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_pct,
       MIN(total_spending)                               AS min_spending,
       ROUND(AVG(total_spending), 0)                     AS avg_spending,
       MAX(total_spending)                               AS max_spending
FROM customer_tier
GROUP BY spending_tier
ORDER BY MIN(total_spending);

-- CTE3: Nested CTEs - orders_per_customer -> customer_stats.
-- customer_stats đọc lại từ orders_per_customer (CTE sau dùng CTE trước) để lấy
-- MAX/AVG/MIN số đơn, rồi so sánh từng khách với mức trung bình.
WITH orders_per_customer AS (
    SELECT customer_id,
           COUNT(*) AS order_count
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
),
customer_stats AS (
    SELECT COUNT(*)                   AS customer_count,
           MAX(order_count)           AS max_orders,
           ROUND(AVG(order_count), 2) AS avg_orders,
           MIN(order_count)           AS min_orders
    FROM orders_per_customer
)
SELECT opc.customer_id,
       opc.order_count,
       cs.max_orders,
       cs.avg_orders,
       cs.min_orders,
       ROUND(opc.order_count - cs.avg_orders, 2) AS diff_vs_avg
FROM orders_per_customer opc
CROSS JOIN customer_stats cs
ORDER BY opc.order_count DESC, opc.customer_id;

-- CTE4: AOV mỗi customer = total_spending / order_count.
WITH customer_spending AS (
    SELECT customer_id,
           COUNT(*)         AS order_count,
           SUM(order_total) AS total_spending
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
)
SELECT customer_id,
       order_count,
       total_spending,
       ROUND(total_spending / order_count, 0) AS aov
FROM customer_spending
ORDER BY aov DESC;

-- CTE5: Retention đơn giản - % khách của mỗi cohort quay lại mua ở tháng kế tiếp.
-- cohort: tháng đơn đầu tiên của từng khách.
-- next_month_buyers: khách có ít nhất 1 đơn đúng vào tháng cohort + 1.
-- Cohort 2026-06 chưa có tháng 07 trong dữ liệu nên retention để NULL.
WITH cohort AS (
    SELECT customer_id,
           DATE_TRUNC('month', MIN(order_date))::date AS cohort_month
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
),
next_month_buyers AS (
    SELECT DISTINCT c.customer_id, c.cohort_month
    FROM cohort c
    JOIN orders o ON o.customer_id = c.customer_id
    WHERE o.status <> 'cancelled'
      AND DATE_TRUNC('month', o.order_date)::date = (c.cohort_month + INTERVAL '1 month')::date
),
data_range AS (
    SELECT DATE_TRUNC('month', MAX(order_date))::date AS last_month FROM orders
)
SELECT c.cohort_month,
       COUNT(*)              AS cohort_size,
       COUNT(n.customer_id)  AS returned_next_month,
       CASE WHEN c.cohort_month < d.last_month
            THEN ROUND(100.0 * COUNT(n.customer_id) / COUNT(*), 2)
       END                   AS retention_m1_pct
FROM cohort c
LEFT JOIN next_month_buyers n ON n.customer_id = c.customer_id
CROSS JOIN data_range d
GROUP BY c.cohort_month, d.last_month
ORDER BY c.cohort_month;


-- #############################################################################
-- 1.2 WINDOW FUNCTIONS (W1 - W5)
-- #############################################################################

-- W1: ROW_NUMBER() OVER (ORDER BY total_spending DESC) - xếp hạng customers.
-- ROW_NUMBER luôn cho số liên tiếp 1,2,3... kể cả khi đồng giá trị.
WITH customer_spending AS (
    SELECT customer_id,
           COUNT(*)         AS order_count,
           SUM(order_total) AS total_spending
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
)
SELECT ROW_NUMBER() OVER (ORDER BY total_spending DESC) AS spending_rank,
       customer_id,
       order_count,
       total_spending
FROM customer_spending
ORDER BY spending_rank;

-- W2: RANK() vs DENSE_RANK() - top 3 customers theo số đơn hàng.
-- Xếp theo order_count (thay vì total_spending) vì số đơn có nhiều khách đồng
-- hạng, nhờ đó thấy rõ khác biệt:
--   * RANK(): các dòng đồng hạng nhận cùng số, dòng kế tiếp NHẢY SỐ (có gap).
--     Ví dụ 3 khách cùng 15 đơn đều hạng 1 -> khách kế tiếp là hạng 4.
--   * DENSE_RANK(): đồng hạng cùng số nhưng KHÔNG nhảy số (không gap).
--     Cùng ví dụ trên -> khách kế tiếp là hạng 2.
--   * ROW_NUMBER() để đối chiếu: luôn 1,2,3... bất kể đồng hạng.
-- Kết quả thực tế: 1 khách 15 đơn (hạng 1), 3 khách cùng 13 đơn (đều hạng 2),
-- khách 12 đơn kế tiếp: RANK = 5 (nhảy qua 3, 4) còn DENSE_RANK = 3.
-- "Top 3" lấy theo DENSE_RANK <= 3 = 3 mức số đơn cao nhất (gồm mọi khách
-- đồng hạng). Nếu lọc RANK <= 3 sẽ mất khách 12 đơn vì gap.
WITH orders_per_customer AS (
    SELECT customer_id,
           COUNT(*)         AS order_count,
           SUM(order_total) AS total_spending
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
),
ranked AS (
    SELECT customer_id,
           order_count,
           total_spending,
           ROW_NUMBER() OVER (ORDER BY order_count DESC, total_spending DESC) AS row_num,
           RANK()       OVER (ORDER BY order_count DESC) AS rnk,
           DENSE_RANK() OVER (ORDER BY order_count DESC) AS dense_rnk
    FROM orders_per_customer
)
SELECT customer_id, order_count, total_spending, row_num, rnk, dense_rnk
FROM ranked
WHERE dense_rnk <= 3
ORDER BY row_num;

-- W3: ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date)
-- Số thứ tự đơn hàng của mỗi customer (1 = đơn đầu tiên). order_id làm
-- tie-breaker để kết quả ổn định khi 2 đơn trùng thời điểm.
SELECT customer_id,
       order_id,
       order_date,
       order_total,
       ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS order_seq
FROM orders
WHERE status <> 'cancelled'
ORDER BY customer_id, order_seq;

-- W4: LAG() / LEAD() - so sánh order_total với đơn trước / sau của cùng customer.
-- Đơn đầu tiên không có prev (NULL), đơn cuối không có next (NULL).
SELECT customer_id,
       order_id,
       order_date,
       order_total,
       LAG(order_total)  OVER w                  AS prev_order_total,
       order_total - LAG(order_total) OVER w     AS diff_vs_prev,
       LEAD(order_total) OVER w                  AS next_order_total,
       LEAD(order_total) OVER w - order_total    AS diff_to_next
FROM orders
WHERE status <> 'cancelled'
WINDOW w AS (PARTITION BY customer_id ORDER BY order_date, order_id)
ORDER BY customer_id, order_date, order_id;

-- W5: SUM(order_total) OVER (ORDER BY order_date) - running total doanh thu.
-- Chỉ đơn completed (định nghĩa Revenue). Dùng ROWS BETWEEN UNBOUNDED PRECEDING
-- AND CURRENT ROW + order_id tie-breaker: frame mặc định là RANGE nên các đơn
-- trùng order_date sẽ cộng "cả cụm" một lúc, số lũy kế nhảy bậc khó đối soát.
SELECT order_id,
       order_date,
       order_total,
       SUM(order_total) OVER (
           ORDER BY order_date, order_id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS cumulative_revenue
FROM orders
WHERE status = 'completed'
ORDER BY order_date, order_id;


-- #############################################################################
-- 1.3 CUSTOMER ANALYTICS - RFM
-- #############################################################################

-- RFM: customer_id, recency_days, frequency, monetary.
-- Cách chọn: dùng 1 GROUP BY duy nhất thay vì 3 CTE rồi JOIN. Cả 3 metric đều
-- là aggregate trên cùng bảng orders, cùng khóa customer_id, cùng bộ lọc, nên
-- một lần quét + một GROUP BY cho kết quả y hệt mà không tốn 3 lần quét và 2
-- phép JOIN; cũng không có rủi ro JOIN lệch làm sinh NULL.
--   Recency  = số ngày từ đơn cuối tới hôm nay: NOW()::date - MAX(order_date)::date
--   Frequency= COUNT(order_id)
--   Monetary = SUM(order_total)
-- Chỉ lấy khách có ít nhất 1 đơn hợp lệ -> frequency/monetary không thể NULL,
-- recency_days luôn >= 0 vì không có order_date ở tương lai.
-- Lưu ý: dùng NOW() theo đề nên recency thay đổi theo ngày chạy (dữ liệu dừng ở
-- 2026-06-29). Bảng RFM xuất ra docs/customer_rfm.csv ngày 2026-09-24.
SELECT customer_id,
       (NOW()::date - MAX(order_date)::date) AS recency_days,
       COUNT(order_id)                       AS frequency,
       SUM(order_total)                      AS monetary
FROM orders
WHERE status <> 'cancelled'
GROUP BY customer_id
ORDER BY customer_id;


-- #############################################################################
-- 1.4 COHORT ANALYSIS - RETENTION THEO THÁNG
-- #############################################################################

-- Cohort: retention theo tháng, hàng = cohort_month, cột = M0..M5, giá trị = %.
-- 1) first_order: cohort = DATE_TRUNC('month', MIN(order_date)) mỗi khách.
-- 2) activity: các tháng khách có đơn, month_offset = số tháng kể từ cohort.
-- 3) Pivot bằng COUNT(DISTINCT ...) FILTER cho từng offset, chia cohort_size.
-- Ô chưa quan sát được (cohort_month + k vượt quá tháng cuối của dữ liệu) để
-- NULL thay vì 0%, tránh hiểu nhầm là khách đã rời bỏ.
WITH first_order AS (
    SELECT customer_id,
           DATE_TRUNC('month', MIN(order_date))::date AS cohort_month
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT
           f.customer_id,
           f.cohort_month,
           (EXTRACT(YEAR  FROM o.order_date) * 12 + EXTRACT(MONTH FROM o.order_date))
         - (EXTRACT(YEAR  FROM f.cohort_month) * 12 + EXTRACT(MONTH FROM f.cohort_month))
             AS month_offset
    FROM first_order f
    JOIN orders o ON o.customer_id = f.customer_id
    WHERE o.status <> 'cancelled'
),
cohort_counts AS (
    SELECT cohort_month,
           COUNT(DISTINCT customer_id)                                  AS cohort_size,
           COUNT(DISTINCT customer_id) FILTER (WHERE month_offset = 1) AS c1,
           COUNT(DISTINCT customer_id) FILTER (WHERE month_offset = 2) AS c2,
           COUNT(DISTINCT customer_id) FILTER (WHERE month_offset = 3) AS c3,
           COUNT(DISTINCT customer_id) FILTER (WHERE month_offset = 4) AS c4,
           COUNT(DISTINCT customer_id) FILTER (WHERE month_offset = 5) AS c5
    FROM activity
    GROUP BY cohort_month
),
data_range AS (
    SELECT DATE_TRUNC('month', MAX(order_date))::date AS last_month
    FROM orders
    WHERE status <> 'cancelled'
)
SELECT TO_CHAR(cc.cohort_month, 'YYYY-MM') AS cohort_month,
       100.00 AS m0,
       CASE WHEN cc.cohort_month + INTERVAL '1 month' <= d.last_month
            THEN ROUND(100.0 * cc.c1 / cc.cohort_size, 2) END AS m1,
       CASE WHEN cc.cohort_month + INTERVAL '2 month' <= d.last_month
            THEN ROUND(100.0 * cc.c2 / cc.cohort_size, 2) END AS m2,
       CASE WHEN cc.cohort_month + INTERVAL '3 month' <= d.last_month
            THEN ROUND(100.0 * cc.c3 / cc.cohort_size, 2) END AS m3,
       CASE WHEN cc.cohort_month + INTERVAL '4 month' <= d.last_month
            THEN ROUND(100.0 * cc.c4 / cc.cohort_size, 2) END AS m4,
       CASE WHEN cc.cohort_month + INTERVAL '5 month' <= d.last_month
            THEN ROUND(100.0 * cc.c5 / cc.cohort_size, 2) END AS m5,
       cc.cohort_size
FROM cohort_counts cc
CROSS JOIN data_range d
ORDER BY cc.cohort_month;


-- #############################################################################
-- 2.1 BONUS - ADVANCED CUSTOMER SEGMENTATION
-- #############################################################################

-- Bonus RFM: chấm điểm 1-5 cho R, F, M bằng NTILE(5) -> rfm_segment 111..555.
--   R: recency càng nhỏ càng tốt -> ORDER BY recency_days DESC để khách mua gần
--      nhất rơi vào nhóm 5.
--   F, M: càng lớn càng tốt -> ORDER BY ASC để nhóm cao nhất là 5.
-- LTV đơn giản = AOV x frequency (về số học bằng monetary; tách ra để thấy rõ
-- 2 thành phần giá trị đơn và tần suất mua).
-- segment_label gom 125 mã thành vài nhóm hành động bằng CASE WHEN.
WITH rfm AS (
    SELECT customer_id,
           (NOW()::date - MAX(order_date)::date) AS recency_days,
           COUNT(order_id)                       AS frequency,
           SUM(order_total)                      AS monetary
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
),
scored AS (
    SELECT customer_id, recency_days, frequency, monetary,
           NTILE(5) OVER (ORDER BY recency_days DESC, customer_id) AS r_score,
           NTILE(5) OVER (ORDER BY frequency ASC,  customer_id)    AS f_score,
           NTILE(5) OVER (ORDER BY monetary ASC,   customer_id)    AS m_score
    FROM rfm
)
SELECT customer_id,
       recency_days,
       frequency,
       monetary,
       r_score, f_score, m_score,
       CONCAT(r_score, f_score, m_score)             AS rfm_segment,
       ROUND(monetary / frequency, 0)                AS aov,
       ROUND(monetary / frequency * frequency, 0)    AS ltv,
       CASE
           WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
           WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal'
           WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
           WHEN r_score <= 2 AND f_score >= 3                  THEN 'At Risk'
           WHEN r_score <= 2 AND f_score <= 2                  THEN 'Hibernating'
           ELSE 'Need Attention'
       END                                           AS segment_label
FROM scored
ORDER BY customer_id;


-- #############################################################################
-- 2.2 BONUS - TIME SERIES
-- #############################################################################

-- Bonus timeseries 1: doanh thu tháng + MoM growth = (this - prev) / prev.
-- Tháng đầu tiên không có tháng trước -> mom_growth_pct NULL.
WITH monthly AS (
    SELECT DATE_TRUNC('month', order_date)::date AS month,
           COUNT(*)                              AS orders,
           SUM(order_total)                      AS revenue
    FROM orders
    WHERE status = 'completed'
    GROUP BY 1
)
SELECT TO_CHAR(month, 'YYYY-MM')                           AS month,
       orders,
       revenue,
       LAG(revenue) OVER (ORDER BY month)                  AS prev_revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
                   / LAG(revenue) OVER (ORDER BY month), 2) AS mom_growth_pct
FROM monthly
ORDER BY month;

-- Bonus timeseries 2: doanh thu ngày + moving average 7-day / 30-day.
-- generate_series tạo đủ mọi ngày (ngày không có đơn = 0) để ROWS 6/29
-- PRECEDING thật sự là 7/30 ngày lịch, không phải 7/30 "ngày có đơn".
-- 6/29 ngày đầu tiên cửa sổ chưa đủ độ dài -> ma vẫn tính trên số ngày hiện có,
-- cột days_in_window_30 cho biết cửa sổ đã đủ 30 ngày hay chưa.
WITH bounds AS (
    SELECT MIN(order_date)::date AS d_start, MAX(order_date)::date AS d_end
    FROM orders
    WHERE status = 'completed'
),
calendar AS (
    SELECT gs::date AS day
    FROM bounds, generate_series(d_start, d_end, INTERVAL '1 day') AS gs
),
daily AS (
    SELECT order_date::date AS day, SUM(order_total) AS revenue
    FROM orders
    WHERE status = 'completed'
    GROUP BY 1
)
SELECT c.day,
       COALESCE(d.revenue, 0) AS revenue,
       ROUND(AVG(COALESCE(d.revenue, 0)) OVER (ORDER BY c.day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0)  AS ma_7d,
       ROUND(AVG(COALESCE(d.revenue, 0)) OVER (ORDER BY c.day ROWS BETWEEN 29 PRECEDING AND CURRENT ROW), 0) AS ma_30d,
       COUNT(*) OVER (ORDER BY c.day ROWS BETWEEN 29 PRECEDING AND CURRENT ROW)                               AS days_in_window_30
FROM calendar c
LEFT JOIN daily d ON d.day = c.day
ORDER BY c.day;
