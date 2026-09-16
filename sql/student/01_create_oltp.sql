-- =============================================================================
-- 01_create_oltp.sql  |  Module 1 - Session 01
-- E-commerce OLTP schema (CORE) cho PostgreSQL 16
--
-- Chạy:  psql -U de_user -d ecommerce -f sql/student/01_create_oltp.sql
-- Hoặc:  scripts/bootstrap.sh  (drop schema -> chạy file này -> nạp seed data)
--
-- QUYẾT ĐỊNH THIẾT KẾ
--   1. Kiểu ID: dùng mã nghiệp vụ VARCHAR (CUS000001, ORD000001...) theo
--      docs/data_contract.md thay vì SERIAL/INT. Lý do: khóa do hệ thống nguồn
--      sinh ra, phải giữ nguyên để đối soát và để pipeline idempotent
--      (INSERT ... ON CONFLICT (id) DO UPDATE) ở các buổi sau. Dùng SERIAL sẽ
--      làm mất khóa nguồn và không nạp được data/seed/*.csv.
--   2. Tiền tệ: NUMERIC(14,2), không dùng FLOAT/REAL vì sai số nhị phân làm
--      lệch doanh thu khi SUM hàng chục nghìn dòng.
--   3. Thời gian: TIMESTAMPTZ vì dữ liệu nguồn có offset +07:00.
--   4. Trạng thái đơn hàng tách thành bảng tra cứu order_status (bảng thứ 7)
--      thay vì CHECK IN (...): thêm trạng thái mới chỉ cần INSERT một dòng,
--      không phải ALTER TABLE trên bảng orders hàng triệu dòng.
--
-- SƠ ĐỒ QUAN HỆ (cha -> con)
--   order_status (1) --< orders
--   categories   (1) --< categories   (tự tham chiếu: danh mục cha - con)
--   categories   (1) --< products
--   customers    (1) --< orders
--   orders       (1) --< order_items  (ON DELETE CASCADE: xóa đơn thì xóa dòng hàng)
--   products     (1) --< order_items
--   orders       (1) --< payments
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS core;
SET search_path TO core, public;

-- -----------------------------------------------------------------------------
-- 1. order_status - BẢNG TRA CỨU (không có bảng cha)
--    Nguồn của business rule #5: pending/confirmed/shipped/completed/cancelled
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_status (
  status_code VARCHAR(20) PRIMARY KEY,
  status_name VARCHAR(50) NOT NULL,
  sort_order  SMALLINT NOT NULL,
  is_revenue  BOOLEAN NOT NULL DEFAULT FALSE,  -- chỉ 'completed' được tính doanh thu
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO order_status (status_code, status_name, sort_order, is_revenue) VALUES
  ('pending',   'Chờ xác nhận', 1, FALSE),
  ('confirmed', 'Đã xác nhận',  2, FALSE),
  ('shipped',   'Đang giao',    3, FALSE),
  ('completed', 'Hoàn tất',     4, TRUE),
  ('cancelled', 'Đã hủy',       9, FALSE)
ON CONFLICT (status_code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2. categories - DANH MỤC (tự tham chiếu)
--    parent_category_id -> categories.category_id: danh mục con trỏ về danh mục
--    cha; NULL nghĩa là danh mục gốc.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS categories (
  category_id VARCHAR(10) PRIMARY KEY,
  category_name VARCHAR(120) NOT NULL,
  parent_category_id VARCHAR(10) REFERENCES categories(category_id),
  source_system VARCHAR(50) NOT NULL DEFAULT 'unknown',
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 3. customers - KHÁCH HÀNG (bảng cha của orders)
--    Business rule #1: customer_id duy nhất, email hợp lệ và không trùng.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
  customer_id VARCHAR(12) PRIMARY KEY,
  full_name VARCHAR(150) NOT NULL,
  email VARCHAR(200) NOT NULL UNIQUE,
  phone VARCHAR(30),
  city VARCHAR(100),
  customer_segment VARCHAR(30) NOT NULL
    CHECK (customer_segment IN ('Standard','Silver','Gold','Platinum')),
  status VARCHAR(20) NOT NULL CHECK (status IN ('active','inactive')),
  source_system VARCHAR(50) NOT NULL DEFAULT 'unknown',
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 4. products - SẢN PHẨM (con của categories, cha của order_items)
--    Business rule #2: mỗi sản phẩm thuộc 1 category; giá bán/giá vốn không âm.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS products (
  product_id VARCHAR(12) PRIMARY KEY,
  category_id VARCHAR(10) NOT NULL REFERENCES categories(category_id),
  product_name VARCHAR(200) NOT NULL,
  unit_price NUMERIC(14,2) NOT NULL CHECK (unit_price >= 0),
  cost_price NUMERIC(14,2) NOT NULL CHECK (cost_price >= 0),
  status VARCHAR(20) NOT NULL CHECK (status IN ('active','inactive','discontinued')),
  source_system VARCHAR(50) NOT NULL DEFAULT 'unknown',
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 5. orders - ĐƠN HÀNG
--    Con của customers + order_status; cha của order_items và payments.
--    Business rule #3: mỗi đơn thuộc đúng 1 khách hàng -> FK customer_id NOT NULL.
--    Quan hệ 1:N - một customer có nhiều order, một order chỉ thuộc một customer.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS orders (
  order_id VARCHAR(12) PRIMARY KEY,
  customer_id VARCHAR(12) NOT NULL REFERENCES customers(customer_id),
  order_date TIMESTAMPTZ NOT NULL,
  status VARCHAR(20) NOT NULL REFERENCES order_status(status_code),
  shipping_city VARCHAR(100),
  channel VARCHAR(20) NOT NULL CHECK (channel IN ('web','mobile_app','social')),
  order_total NUMERIC(14,2) NOT NULL CHECK (order_total >= 0),
  source_system VARCHAR(50) NOT NULL DEFAULT 'unknown',
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 6. order_items - DÒNG HÀNG (bảng nối N-N giữa orders và products)
--    Business rule #4: quantity > 0; discount không âm và không vượt gross amount.
--    unit_price là snapshot giá tại thời điểm đặt, không join lại products.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_items (
  order_item_id VARCHAR(16) PRIMARY KEY,
  order_id VARCHAR(12) NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  product_id VARCHAR(12) NOT NULL REFERENCES products(product_id),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(14,2) NOT NULL CHECK (unit_price >= 0),
  discount_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  source_system VARCHAR(50) NOT NULL DEFAULT 'unknown',
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (discount_amount <= unit_price * quantity)
);

-- -----------------------------------------------------------------------------
-- 7. payments - THANH TOÁN (con của orders)
--    Business rule #7: payment phải tham chiếu order tồn tại -> FK NOT NULL.
--    Ràng buộc payment_date >= order_date là ràng buộc LIÊN BẢNG, CHECK không
--    làm được (CHECK chỉ nhìn được cột cùng row cùng bảng) -> xử lý bằng trigger
--    ở phần Bonus bên dưới.
--    Quan hệ 1:N - một đơn có thể có 0..N payment (trả góp, retry, hoàn tiền).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payments (
  payment_id VARCHAR(12) PRIMARY KEY,
  order_id VARCHAR(12) NOT NULL REFERENCES orders(order_id),
  payment_date TIMESTAMPTZ NOT NULL,
  payment_method VARCHAR(30) NOT NULL
    CHECK (payment_method IN ('cash','bank_transfer','card','e_wallet')),
  payment_status VARCHAR(20) NOT NULL
    CHECK (payment_status IN ('pending','success','failed','refunded')),
  amount NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
  source_system VARCHAR(50) NOT NULL DEFAULT 'unknown',
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- INDEX: phục vụ join theo FK và lọc incremental theo updated_at (rule #8)
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orders_customer      ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_date          ON orders(order_date);
CREATE INDEX IF NOT EXISTS idx_orders_status        ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_updated_at    ON orders(updated_at);
CREATE INDEX IF NOT EXISTS idx_order_items_order    ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product  ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_payments_order       ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_products_category    ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_customers_updated_at ON customers(updated_at);

-- =============================================================================
-- Session 01 Bonus
-- CHECK constraints bổ sung + DEFAULT cho audit fields.
-- Viết theo cặp DROP IF EXISTS / ADD để file chạy lại nhiều lần không lỗi.
-- =============================================================================

-- Bonus 1: order_date không được ở tương lai
ALTER TABLE orders DROP CONSTRAINT IF EXISTS check_order_date;
ALTER TABLE orders ADD CONSTRAINT check_order_date
  CHECK (order_date IS NULL OR order_date <= NOW());

-- Bonus 2: tổng tiền đơn hàng không âm
ALTER TABLE orders DROP CONSTRAINT IF EXISTS check_order_total_non_negative;
ALTER TABLE orders ADD CONSTRAINT check_order_total_non_negative
  CHECK (order_total >= 0);

-- Bonus 3: số lượng phải lớn hơn 0
ALTER TABLE order_items DROP CONSTRAINT IF EXISTS check_quantity_positive;
ALTER TABLE order_items ADD CONSTRAINT check_quantity_positive
  CHECK (quantity > 0);

-- Bonus 4: số tiền thanh toán không âm
ALTER TABLE payments DROP CONSTRAINT IF EXISTS check_payment_amount_non_negative;
ALTER TABLE payments ADD CONSTRAINT check_payment_amount_non_negative
  CHECK (amount >= 0);

-- Bonus 5: payment_date không ở tương lai
ALTER TABLE payments DROP CONSTRAINT IF EXISTS check_payment_date;
ALTER TABLE payments ADD CONSTRAINT check_payment_date
  CHECK (payment_date IS NULL OR payment_date <= NOW());

-- Bonus 6: DEFAULT NOW() cho audit fields (áp dụng cho bản ghi insert thủ công)
ALTER TABLE categories  ALTER COLUMN created_at SET DEFAULT NOW();
ALTER TABLE categories  ALTER COLUMN updated_at SET DEFAULT NOW();
ALTER TABLE customers   ALTER COLUMN created_at SET DEFAULT NOW();
ALTER TABLE customers   ALTER COLUMN updated_at SET DEFAULT NOW();
ALTER TABLE products    ALTER COLUMN created_at SET DEFAULT NOW();
ALTER TABLE products    ALTER COLUMN updated_at SET DEFAULT NOW();
ALTER TABLE orders      ALTER COLUMN created_at SET DEFAULT NOW();
ALTER TABLE orders      ALTER COLUMN updated_at SET DEFAULT NOW();
ALTER TABLE order_items ALTER COLUMN created_at SET DEFAULT NOW();
ALTER TABLE order_items ALTER COLUMN updated_at SET DEFAULT NOW();
ALTER TABLE payments    ALTER COLUMN created_at SET DEFAULT NOW();
ALTER TABLE payments    ALTER COLUMN updated_at SET DEFAULT NOW();

-- Bonus 7: ràng buộc liên bảng payment_date >= order_date (business rule #7).
-- CHECK không làm được vì phải đọc sang bảng orders -> dùng trigger.
CREATE OR REPLACE FUNCTION core.fn_check_payment_after_order()
RETURNS TRIGGER AS $func$
DECLARE
  v_order_date TIMESTAMPTZ;
BEGIN
  SELECT order_date INTO v_order_date FROM core.orders WHERE order_id = NEW.order_id;
  IF v_order_date IS NOT NULL AND NEW.payment_date < v_order_date THEN
    RAISE EXCEPTION 'payment_date (%) phai >= order_date (%) cua don %',
      NEW.payment_date, v_order_date, NEW.order_id;
  END IF;
  RETURN NEW;
END;
$func$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_payment_after_order ON payments;
CREATE TRIGGER trg_check_payment_after_order
  BEFORE INSERT OR UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION core.fn_check_payment_after_order();
