-- GRAIN: one row per order_item (1 dòng fact_sales = 1 sản phẩm trong 1 đơn hàng).
-- Lý do chọn grain thấp nhất (order_item) thay vì order:
--   - Doanh thu cần cắt theo product / category / ngày -> chỉ order_item mới gắn
--     được với đúng 1 product; grain order sẽ phải "chia" order_total cho nhiều sản phẩm.
--   - Từ grain item luôn roll-up lên order (COUNT DISTINCT order_id) hoặc ngày/tháng,
--     ngược lại thì không được.
--   - Khóa nguồn: core.order_items.order_item_id (duy nhất) -> dễ đối soát 1-1 với OLTP.
-- =============================================================================
-- 04_data_mart.sql  |  Module 1 - Session 04
-- Sales Data Mart (Star Schema) cho PostgreSQL 16, schema "mart", nguồn schema "core".
--
-- Chạy:  psql -U de_user -d ecommerce -v ON_ERROR_STOP=1 -f sql/student/04_data_mart.sql
-- File chạy lại nhiều lần được: DDL dùng IF NOT EXISTS, phần LOAD là full refresh
-- (TRUNCATE ... RESTART IDENTITY rồi INSERT ... SELECT).
--
-- STAR SCHEMA
--                    dim_date
--                       |
--   dim_customer --- fact_sales --- dim_product
--                    /        \
--     dim_payment_method    dim_order_status
--
-- QUY ƯỚC
--   - Ngày nghiệp vụ tính theo giờ Việt Nam: (order_date AT TIME ZONE 'Asia/Ho_Chi_Minh')::date.
--     OLTP lưu TIMESTAMPTZ, server chạy UTC -> nếu cast thẳng ::date thì đơn 00:00-06:59
--     giờ VN bị đẩy về ngày hôm trước.
--   - Tiền: NUMERIC(12,2) (tối đa 9.999.999.999,99 / dòng, đủ cho 1 order_item).
--   - Ngày: DATE trong dim_date, fact chỉ giữ date_key INT dạng YYYYMMDD.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS mart;
SET search_path TO mart, core, public;

-- =============================================================================
-- PHẦN 1. DDL
-- =============================================================================

-- -----------------------------------------------------------------------------
-- dim_date
--   Nguồn : generate_series(MIN(order_date), MAX(order_date)) của core.orders,
--           quy đổi về ngày giờ VN.
--   Key   : date_key INT = YYYYMMDD (smart/natural key). Không dùng SERIAL vì
--           khóa ngày là bất biến, đọc được bằng mắt, và fact tự tính được
--           date_key từ order_date mà không cần lookup.
--   Map   : full_date -> day/month/quarter/year/tuần/thứ/cuối tuần.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_date (
  date_key      INTEGER PRIMARY KEY,           -- 20260115
  full_date     DATE NOT NULL UNIQUE,
  day_of_month  SMALLINT NOT NULL,
  day_of_week   SMALLINT NOT NULL,             -- ISO: 1 = Thứ 2 ... 7 = Chủ nhật
  day_name      VARCHAR(10) NOT NULL,
  week_of_year  SMALLINT NOT NULL,
  month         SMALLINT NOT NULL,
  month_name    VARCHAR(10) NOT NULL,
  year_month    CHAR(7) NOT NULL,              -- '2026-01', tiện GROUP BY + ORDER BY
  quarter       SMALLINT NOT NULL,
  year          SMALLINT NOT NULL,
  is_weekend    BOOLEAN NOT NULL
);

-- -----------------------------------------------------------------------------
-- dim_customer
--   Nguồn : core.customers (1 dòng / customer_id).
--   Key   : customer_key SERIAL (surrogate). Giữ customer_id làm natural key
--           (UNIQUE) để lookup khi load fact. Dùng surrogate để mart không phụ
--           thuộc định dạng mã nguồn và sẵn sàng cho SCD sau này.
--   Map   : full_name, city (dùng làm region), customer_segment, status giữ nguyên.
--           Bỏ email/phone (PII, không cần cho phân tích doanh thu).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_customer (
  customer_key     SERIAL PRIMARY KEY,
  customer_id      VARCHAR(12) NOT NULL UNIQUE,
  full_name        VARCHAR(150) NOT NULL,
  city             VARCHAR(100),
  customer_segment VARCHAR(30) NOT NULL,
  status           VARCHAR(20) NOT NULL
);

-- -----------------------------------------------------------------------------
-- dim_product
--   Nguồn : core.products JOIN core.categories (danh mục con)
--           LEFT JOIN core.categories (danh mục cha) -> denormalize 2 cấp danh mục
--           vào 1 dimension (đặc trưng star schema: không snowflake).
--   Key   : product_key SERIAL (surrogate) - bắt buộc nếu muốn làm SCD Type 2
--           (1 product_id có nhiều phiên bản, xem 04_bonus_scd.sql).
--   Map   : category      = tên danh mục con (Phones, Kitchen...)
--           parent_category = tên danh mục cha (Electronics, Home & Living...);
--           nếu sản phẩm gắn thẳng vào danh mục gốc thì parent_category = category.
--           list_price = products.unit_price (giá niêm yết hiện tại).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_product (
  product_key     SERIAL PRIMARY KEY,
  product_id      VARCHAR(12) NOT NULL UNIQUE,
  product_name    VARCHAR(200) NOT NULL,
  category_id     VARCHAR(10) NOT NULL,
  category        VARCHAR(120) NOT NULL,
  parent_category VARCHAR(120) NOT NULL,
  list_price      NUMERIC(12,2) NOT NULL,
  cost_price      NUMERIC(12,2) NOT NULL,
  status          VARCHAR(20) NOT NULL
);

-- -----------------------------------------------------------------------------
-- dim_payment_method
--   Nguồn : DISTINCT core.payments.payment_method + 1 dòng 'unknown'.
--   Key   : payment_method_key SMALLSERIAL (surrogate), payment_method_code UNIQUE.
--           Bảng rất nhỏ nên key 2 byte giúp fact gọn hơn VARCHAR.
--   Map   : cash -> Tiền mặt, bank_transfer -> Chuyển khoản, card -> Thẻ,
--           e_wallet -> Ví điện tử.
--           483 đơn chưa có payment -> trỏ về 'unknown' thay vì để FK NULL
--           (tránh mất dòng khi INNER JOIN trong báo cáo).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_payment_method (
  payment_method_key  SMALLSERIAL PRIMARY KEY,
  payment_method_code VARCHAR(30) NOT NULL UNIQUE,
  payment_method_name VARCHAR(50) NOT NULL
);

-- -----------------------------------------------------------------------------
-- dim_order_status
--   Nguồn : core.order_status (bảng tra cứu 5 trạng thái).
--   Key   : order_status_key SMALLSERIAL (surrogate), status_code UNIQUE.
--   Map   : giữ is_revenue (chỉ 'completed' = TRUE) để KPI doanh thu lọc
--           WHERE is_revenue mà không phải hard-code 'completed'.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_order_status (
  order_status_key SMALLSERIAL PRIMARY KEY,
  status_code      VARCHAR(20) NOT NULL UNIQUE,
  status_name      VARCHAR(50) NOT NULL,
  sort_order       SMALLINT NOT NULL,
  is_revenue       BOOLEAN NOT NULL
);

-- -----------------------------------------------------------------------------
-- fact_sales (grain: 1 dòng / order_item)
--   Nguồn : core.order_items
--           JOIN core.orders    (ngày, khách, trạng thái)
--           JOIN core.products  (qua dim_product)
--           LEFT JOIN core.payments (phương thức thanh toán; có thể chưa có)
--   Key   : sales_key BIGSERIAL; order_item_id UNIQUE để chống load trùng.
--   Degenerate dimension: order_id (không có bảng dim riêng, dùng để đếm đơn / AOV).
--   Measures:
--     quantity      = order_items.quantity
--     unit_price    = order_items.unit_price (giá snapshot lúc đặt, KHÔNG lấy products)
--     gross_amount  = quantity * unit_price
--     discount      = order_items.discount_amount
--     revenue       = gross_amount - discount   (net revenue của dòng hàng)
--   Lưu ý: fact giữ MỌI trạng thái đơn (cả cancelled/pending) để báo cáo vận hành;
--   KPI doanh thu lọc qua dim_order_status.is_revenue.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_sales (
  sales_key          BIGSERIAL PRIMARY KEY,
  order_item_id      VARCHAR(16) NOT NULL UNIQUE,
  order_id           VARCHAR(12) NOT NULL,           -- degenerate dimension
  date_key           INTEGER  NOT NULL REFERENCES dim_date(date_key),
  customer_key       INTEGER  NOT NULL REFERENCES dim_customer(customer_key),
  product_key        INTEGER  NOT NULL REFERENCES dim_product(product_key),
  payment_method_key SMALLINT NOT NULL REFERENCES dim_payment_method(payment_method_key),
  order_status_key   SMALLINT NOT NULL REFERENCES dim_order_status(order_status_key),
  quantity           INTEGER  NOT NULL CHECK (quantity > 0),
  unit_price         NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  gross_amount       NUMERIC(12,2) NOT NULL CHECK (gross_amount >= 0),
  discount           NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
  revenue            NUMERIC(12,2) NOT NULL CHECK (revenue >= 0),
  loaded_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index cho các cột FK hay JOIN / lọc trong KPI (PostgreSQL không tự tạo index cho FK).
CREATE INDEX IF NOT EXISTS idx_fact_sales_date      ON fact_sales(date_key);
CREATE INDEX IF NOT EXISTS idx_fact_sales_customer  ON fact_sales(customer_key);
CREATE INDEX IF NOT EXISTS idx_fact_sales_product   ON fact_sales(product_key);
CREATE INDEX IF NOT EXISTS idx_fact_sales_status    ON fact_sales(order_status_key);
CREATE INDEX IF NOT EXISTS idx_fact_sales_order     ON fact_sales(order_id);
CREATE INDEX IF NOT EXISTS idx_dim_product_category ON dim_product(category);
CREATE INDEX IF NOT EXISTS idx_dim_date_year_month  ON dim_date(year_month);

-- =============================================================================
-- PHẦN 2. LOAD (full refresh từ OLTP)
-- Thứ tự: dims trước, fact sau (fact cần surrogate key của dims).
-- =============================================================================

-- LOAD 0: dọn dữ liệu cũ, reset sequence để key ổn định giữa các lần chạy.
TRUNCATE fact_sales, dim_date, dim_customer, dim_product,
         dim_payment_method, dim_order_status RESTART IDENTITY;

-- LOAD 1: dim_date - dải ngày liên tục từ MIN đến MAX(order_date) theo giờ VN.
-- Dùng generate_series để có cả những ngày không phát sinh đơn (báo cáo không bị "lủng").
INSERT INTO dim_date (date_key, full_date, day_of_month, day_of_week, day_name,
                      week_of_year, month, month_name, year_month, quarter, year, is_weekend)
SELECT TO_CHAR(d, 'YYYYMMDD')::INT,
       d::DATE,
       EXTRACT(DAY     FROM d)::SMALLINT,
       EXTRACT(ISODOW  FROM d)::SMALLINT,
       TRIM(TO_CHAR(d, 'Day')),
       EXTRACT(WEEK    FROM d)::SMALLINT,
       EXTRACT(MONTH   FROM d)::SMALLINT,
       TRIM(TO_CHAR(d, 'Month')),
       TO_CHAR(d, 'YYYY-MM'),
       EXTRACT(QUARTER FROM d)::SMALLINT,
       EXTRACT(YEAR    FROM d)::SMALLINT,
       EXTRACT(ISODOW  FROM d) IN (6, 7)
FROM generate_series(
       (SELECT MIN((order_date AT TIME ZONE 'Asia/Ho_Chi_Minh')::DATE) FROM core.orders),
       (SELECT MAX((order_date AT TIME ZONE 'Asia/Ho_Chi_Minh')::DATE) FROM core.orders),
       INTERVAL '1 day') AS g(d);

-- LOAD 2: dim_customer - copy thẳng, bỏ PII.
INSERT INTO dim_customer (customer_id, full_name, city, customer_segment, status)
SELECT customer_id, full_name, city, customer_segment, status
FROM core.customers
ORDER BY customer_id;

-- LOAD 3: dim_product - denormalize danh mục con + cha.
INSERT INTO dim_product (product_id, product_name, category_id, category, parent_category,
                         list_price, cost_price, status)
SELECT p.product_id,
       p.product_name,
       c.category_id,
       c.category_name,
       COALESCE(pc.category_name, c.category_name),
       p.unit_price,
       p.cost_price,
       p.status
FROM core.products p
JOIN core.categories c       ON c.category_id  = p.category_id
LEFT JOIN core.categories pc ON pc.category_id = c.parent_category_id
ORDER BY p.product_id;

-- LOAD 4a: dim_payment_method - các phương thức có trong OLTP + 'unknown'.
INSERT INTO dim_payment_method (payment_method_code, payment_method_name)
SELECT code,
       CASE code
         WHEN 'cash'          THEN 'Tiền mặt'
         WHEN 'bank_transfer' THEN 'Chuyển khoản'
         WHEN 'card'          THEN 'Thẻ'
         WHEN 'e_wallet'      THEN 'Ví điện tử'
         ELSE 'Chưa thanh toán / không rõ'
       END
FROM (SELECT DISTINCT payment_method AS code FROM core.payments
      UNION
      SELECT 'unknown') s
ORDER BY code;

-- LOAD 4b: dim_order_status - copy từ bảng tra cứu.
INSERT INTO dim_order_status (status_code, status_name, sort_order, is_revenue)
SELECT status_code, status_name, sort_order, is_revenue
FROM core.order_status
ORDER BY sort_order;

-- LOAD 5: fact_sales - orders -> order_items -> products -> payments, lookup surrogate keys.
-- payments: mỗi đơn hiện có tối đa 1 payment; vẫn dùng DISTINCT ON để nếu sau này
-- có nhiều payment (retry/hoàn tiền) thì lấy payment mới nhất, không nhân bản dòng fact.
INSERT INTO fact_sales (order_item_id, order_id, date_key, customer_key, product_key,
                        payment_method_key, order_status_key,
                        quantity, unit_price, gross_amount, discount, revenue)
SELECT oi.order_item_id,
       o.order_id,
       TO_CHAR(o.order_date AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYYMMDD')::INT,
       dc.customer_key,
       dp.product_key,
       dpm.payment_method_key,
       dos.order_status_key,
       oi.quantity,
       oi.unit_price,
       oi.quantity * oi.unit_price,
       oi.discount_amount,
       oi.quantity * oi.unit_price - oi.discount_amount
FROM core.orders o
JOIN core.order_items oi ON oi.order_id = o.order_id
JOIN core.products    p  ON p.product_id = oi.product_id
LEFT JOIN (
       SELECT DISTINCT ON (order_id) order_id, payment_method
       FROM core.payments
       ORDER BY order_id, payment_date DESC
     ) pay ON pay.order_id = o.order_id
JOIN dim_customer       dc  ON dc.customer_id  = o.customer_id
JOIN dim_product        dp  ON dp.product_id   = p.product_id
JOIN dim_order_status   dos ON dos.status_code = o.status
JOIN dim_payment_method dpm ON dpm.payment_method_code = COALESCE(pay.payment_method, 'unknown')
ORDER BY oi.order_item_id;

ANALYZE dim_date, dim_customer, dim_product, dim_payment_method, dim_order_status, fact_sales;

-- =============================================================================
-- PHẦN 3. VERIFY - row counts + đối soát OLTP <-> Mart
-- =============================================================================

-- VERIFY 1: số dòng từng bảng mart so với nguồn.
SELECT 'dim_date'           AS table_name, COUNT(*) AS mart_rows,
       (SELECT MAX((order_date AT TIME ZONE 'Asia/Ho_Chi_Minh')::DATE)
             - MIN((order_date AT TIME ZONE 'Asia/Ho_Chi_Minh')::DATE) + 1
        FROM core.orders) AS source_rows FROM dim_date
UNION ALL
SELECT 'dim_customer',       COUNT(*), (SELECT COUNT(*) FROM core.customers)   FROM dim_customer
UNION ALL
SELECT 'dim_product',        COUNT(*), (SELECT COUNT(*) FROM core.products)    FROM dim_product
UNION ALL
SELECT 'dim_payment_method', COUNT(*), (SELECT COUNT(DISTINCT payment_method) + 1 FROM core.payments) FROM dim_payment_method
UNION ALL
SELECT 'dim_order_status',   COUNT(*), (SELECT COUNT(*) FROM core.order_status) FROM dim_order_status
UNION ALL
SELECT 'fact_sales',         COUNT(*), (SELECT COUNT(*) FROM core.order_items) FROM fact_sales;

-- VERIFY 2: đối soát doanh thu. order_total trong OLTP đã là số NET (sau discount),
-- nên SUM(fact.revenue) phải khớp SUM(orders.order_total); gross - net = tổng discount.
SELECT o.oltp_orders,
       f.mart_orders,
       o.oltp_revenue,
       f.mart_revenue,
       f.mart_revenue - o.oltp_revenue AS diff,
       f.mart_gross,
       f.mart_discount,
       f.mart_gross - f.mart_revenue   AS gross_minus_net
FROM (SELECT COUNT(*) AS oltp_orders, SUM(order_total) AS oltp_revenue FROM core.orders) o
CROSS JOIN (SELECT COUNT(DISTINCT order_id) AS mart_orders,
                   SUM(revenue)      AS mart_revenue,
                   SUM(gross_amount) AS mart_gross,
                   SUM(discount)     AS mart_discount
            FROM fact_sales) f;

-- VERIFY 3: đối soát theo trạng thái (doanh thu ghi nhận = completed).
SELECT s.status_code,
       s.is_revenue,
       COALESCE(o.oltp_revenue, 0) AS oltp_revenue,
       COALESCE(m.mart_revenue, 0) AS mart_revenue,
       COALESCE(m.mart_revenue, 0) - COALESCE(o.oltp_revenue, 0) AS diff
FROM dim_order_status s
LEFT JOIN (SELECT status, SUM(order_total) AS oltp_revenue
           FROM core.orders GROUP BY status) o ON o.status = s.status_code
LEFT JOIN (SELECT order_status_key, SUM(revenue) AS mart_revenue
           FROM fact_sales GROUP BY order_status_key) m ON m.order_status_key = s.order_status_key
ORDER BY s.sort_order;

-- VERIFY 4: đối soát từng đơn - số đơn mà tổng revenue trong mart lệch order_total (kỳ vọng 0).
SELECT COUNT(*) AS orders_mismatch
FROM core.orders o
JOIN (SELECT order_id, SUM(revenue) AS rev FROM fact_sales GROUP BY order_id) f
  ON f.order_id = o.order_id
WHERE f.rev <> o.order_total;

-- VERIFY 5: kiểm tra FK "mềm" - đơn chưa có payment được map vào 'unknown'.
SELECT pm.payment_method_code,
       COUNT(DISTINCT f.order_id) AS orders,
       COUNT(*)                   AS fact_rows
FROM fact_sales f
JOIN dim_payment_method pm ON pm.payment_method_key = f.payment_method_key
GROUP BY pm.payment_method_code
ORDER BY pm.payment_method_code;
