-- =============================================================================
-- 04_bonus_scd.sql  |  Module 1 - Session 04 - Bonus 2.1 (a)
-- SCD Type 2 cho mart.dim_product: lưu lịch sử thay đổi giá niêm yết (list_price).
--
-- Chạy SAU 04_data_mart.sql:
--   psql -U de_user -d ecommerce -v ON_ERROR_STOP=1 -f sql/student/04_bonus_scd.sql
--
-- Ý tưởng:
--   - Mỗi lần list_price của 1 product_id đổi -> KHÔNG update đè, mà:
--       (1) đóng phiên bản hiện tại: valid_to = ngày hiệu lực - 1, is_current = FALSE
--       (2) thêm phiên bản mới: product_key mới, valid_from = ngày hiệu lực,
--           valid_to = 9999-12-31, is_current = TRUE
--   - fact_sales đã load giữ nguyên product_key cũ -> doanh thu quá khứ vẫn gắn với
--     giá cũ; fact mới lookup theo is_current (hoặc theo khoảng valid_from/valid_to).
--   - product_id không còn UNIQUE trên toàn bảng, chỉ UNIQUE trong các dòng is_current.
--   - Chạy lại file nhiều lần không sinh thêm version: hàm bỏ qua nếu giá không đổi.
-- Lưu ý: 04_data_mart.sql là full refresh (TRUNCATE dim_product) nên chạy lại file đó
-- sẽ xóa lịch sử SCD; ở môi trường thật dim SCD2 phải load incremental.
-- =============================================================================

SET search_path TO mart, core, public;

-- -----------------------------------------------------------------------------
-- 1. DDL: thêm cột SCD2
-- -----------------------------------------------------------------------------
ALTER TABLE dim_product ADD COLUMN IF NOT EXISTS valid_from DATE    NOT NULL DEFAULT DATE '1900-01-01';
ALTER TABLE dim_product ADD COLUMN IF NOT EXISTS valid_to   DATE    NOT NULL DEFAULT DATE '9999-12-31';
ALTER TABLE dim_product ADD COLUMN IF NOT EXISTS is_current BOOLEAN NOT NULL DEFAULT TRUE;

-- product_id hết là khóa duy nhất -> bỏ UNIQUE cũ, thay bằng unique partial index.
ALTER TABLE dim_product DROP CONSTRAINT IF EXISTS dim_product_product_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_product_current
  ON dim_product(product_id) WHERE is_current;
CREATE INDEX IF NOT EXISTS idx_dim_product_id_validity
  ON dim_product(product_id, valid_from, valid_to);

ALTER TABLE dim_product DROP CONSTRAINT IF EXISTS chk_dim_product_validity;
ALTER TABLE dim_product ADD CONSTRAINT chk_dim_product_validity CHECK (valid_from <= valid_to);

-- Phiên bản đầu tiên của mỗi sản phẩm có hiệu lực từ ngày sản phẩm được tạo ở OLTP.
UPDATE dim_product dp
SET valid_from = (p.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::DATE
FROM core.products p
WHERE p.product_id = dp.product_id
  AND dp.valid_from = DATE '1900-01-01';

-- -----------------------------------------------------------------------------
-- 2. Hàm SCD2: áp dụng giá mới cho 1 sản phẩm từ ngày p_effective
--    Trả về product_key của phiên bản current sau khi xử lý.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mart.scd2_change_product_price(
  p_product_id VARCHAR,
  p_new_price  NUMERIC,
  p_effective  DATE
) RETURNS INTEGER AS $func$
DECLARE
  v_cur mart.dim_product%ROWTYPE;
  v_new_key INTEGER;
BEGIN
  SELECT * INTO v_cur
  FROM mart.dim_product
  WHERE product_id = p_product_id AND is_current
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Không tìm thấy phiên bản current của %', p_product_id;
  END IF;

  -- Giá không đổi -> không tạo version mới (idempotent).
  IF v_cur.list_price = p_new_price THEN
    RETURN v_cur.product_key;
  END IF;

  IF p_effective <= v_cur.valid_from THEN
    RAISE EXCEPTION 'Ngày hiệu lực % phải sau valid_from % của version hiện tại',
      p_effective, v_cur.valid_from;
  END IF;

  -- (1) đóng version cũ
  UPDATE mart.dim_product
  SET valid_to = p_effective - 1,
      is_current = FALSE
  WHERE product_key = v_cur.product_key;

  -- (2) thêm version mới, copy thuộc tính khác, đổi giá
  INSERT INTO mart.dim_product (product_id, product_name, category_id, category, parent_category,
                                list_price, cost_price, status, valid_from, valid_to, is_current)
  VALUES (v_cur.product_id, v_cur.product_name, v_cur.category_id, v_cur.category,
          v_cur.parent_category, p_new_price, v_cur.cost_price, v_cur.status,
          p_effective, DATE '9999-12-31', TRUE)
  RETURNING product_key INTO v_new_key;

  RETURN v_new_key;
END;
$func$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 3. DEMO: PRD000297 (top 1 doanh thu) tăng giá 10% từ 2026-07-01
-- -----------------------------------------------------------------------------

-- 3.1 Trước khi đổi giá
SELECT product_key, product_id, list_price, valid_from, valid_to, is_current
FROM dim_product
WHERE product_id = 'PRD000297'
ORDER BY valid_from;

-- 3.2 Áp dụng thay đổi (giá mới tính từ version GỐC để chạy lại không tăng tiếp 10%)
SELECT mart.scd2_change_product_price(
         'PRD000297',
         ROUND((SELECT unit_price FROM core.products WHERE product_id = 'PRD000297') * 1.10, -3),
         DATE '2026-07-01') AS current_product_key;

-- 3.3 Sau khi đổi giá: 2 version, chỉ 1 dòng is_current
SELECT product_key, product_id, list_price, valid_from, valid_to, is_current
FROM dim_product
WHERE product_id = 'PRD000297'
ORDER BY valid_from;

-- 3.4 Fact quá khứ vẫn trỏ về version cũ -> lịch sử doanh thu không bị "viết lại"
SELECT dp.product_key, dp.list_price, dp.is_current,
       COUNT(*) AS fact_rows, SUM(f.revenue) AS revenue
FROM fact_sales f
JOIN dim_product dp ON dp.product_key = f.product_key
WHERE dp.product_id = 'PRD000297'
GROUP BY dp.product_key, dp.list_price, dp.is_current;

-- 3.5 Point-in-time lookup: 1 đơn ngày 2026-06-15 và 1 đơn giả định ngày 2026-07-10
--     tra đúng version theo khoảng hiệu lực (cách load fact khi có SCD2).
SELECT x.sale_date, dp.product_key, dp.list_price, dp.is_current
FROM (VALUES (DATE '2026-06-15'), (DATE '2026-07-10')) AS x(sale_date)
JOIN dim_product dp
  ON dp.product_id = 'PRD000297'
 AND x.sale_date BETWEEN dp.valid_from AND dp.valid_to
ORDER BY x.sale_date;

-- 3.6 Kiểm tra toàn vẹn: mỗi product_id đúng 1 dòng current, không có khoảng hiệu lực chồng nhau
SELECT
  (SELECT COUNT(*) FROM (SELECT product_id FROM dim_product WHERE is_current
                         GROUP BY product_id HAVING COUNT(*) <> 1) a)   AS products_bad_current,
  (SELECT COUNT(*) FROM dim_product a JOIN dim_product b
     ON a.product_id = b.product_id AND a.product_key < b.product_key
    AND a.valid_from <= b.valid_to AND b.valid_from <= a.valid_to)      AS overlapping_versions,
  (SELECT COUNT(*) FROM dim_product)                                    AS dim_rows,
  (SELECT COUNT(DISTINCT product_id) FROM dim_product)                  AS distinct_products;
