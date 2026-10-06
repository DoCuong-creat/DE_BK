# Buổi 04 — Bonus 2.2: Performance OLTP vs Data Mart

KPI so sánh: **Revenue by month** (chỉ đơn `completed`), cùng kết quả 6 dòng, tổng 48.077.944.000 VND ở cả 2 phía.

Môi trường: PostgreSQL 16 (container `ecommerce-postgres`), dữ liệu: 5.000 orders / 12.717 order_items.
Mỗi câu chạy `EXPLAIN (ANALYZE)` 6 lần liên tiếp (cache đã ấm), lấy **median** Execution Time.

---

## 1. Câu SQL

### 1a. Trên OLTP (schema `core`) — 3 bảng, phải tính revenue + quy đổi tháng lúc chạy

```sql
SELECT TO_CHAR(o.order_date AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYY-MM') AS year_month,
       COUNT(DISTINCT o.order_id)                               AS orders,
       SUM(oi.quantity * oi.unit_price - oi.discount_amount)    AS revenue
FROM core.orders o
JOIN core.order_items  oi ON oi.order_id = o.order_id
JOIN core.order_status st ON st.status_code = o.status
WHERE st.is_revenue
GROUP BY 1
ORDER BY 1;
```

### 1b. Trên Mart (schema `mart`) — star join, revenue + year_month đã tính sẵn lúc load

```sql
SELECT d.year_month,
       COUNT(DISTINCT f.order_id) AS orders,
       SUM(f.revenue)             AS revenue
FROM mart.fact_sales f
JOIN mart.dim_date d         ON d.date_key = f.date_key
JOIN mart.dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY d.year_month
ORDER BY d.year_month;
```

---

## 2. Output EXPLAIN ANALYZE

### 2a. OLTP

```
 GroupAggregate  (cost=1004.14..1201.42 rows=4915 width=72) (actual time=23.649..25.973 rows=6 loops=1)
   Group Key: (to_char((o.order_date AT TIME ZONE 'Asia/Ho_Chi_Minh'::text), 'YYYY-MM'::text))
   Buffers: shared hit=252
   ->  Sort  (cost=1004.14..1020.04 rows=6358 width=56) (actual time=23.157..23.474 rows=9933 loops=1)
         Sort Key: (to_char((o.order_date AT TIME ZONE 'Asia/Ho_Chi_Minh'::text), 'YYYY-MM'::text)), o.order_id
         Sort Method: quicksort  Memory: 974kB
         Buffers: shared hit=252
         ->  Hash Join  (cost=206.35..602.50 rows=6358 width=56) (actual time=1.383..10.538 rows=9933 loops=1)
               Hash Cond: ((o.status)::text = (st.status_code)::text)
               Buffers: shared hit=249
               ->  Hash Join  (cost=190.50..521.09 rows=12717 width=41) (actual time=1.131..4.839 rows=12717 loops=1)
                     Hash Cond: ((oi.order_id)::text = (o.order_id)::text)
                     Buffers: shared hit=248
                     ->  Seq Scan on order_items oi  (cost=0.00..297.17 rows=12717 width=24) (actual time=0.001..0.716 rows=12717 loops=1)
                           Buffers: shared hit=170
                     ->  Hash  (cost=128.00..128.00 rows=5000 width=27) (actual time=1.080..1.081 rows=5000 loops=1)
                           Buckets: 8192  Batches: 1  Memory Usage: 356kB
                           Buffers: shared hit=78
                           ->  Seq Scan on orders o  (cost=0.00..128.00 rows=5000 width=27) (actual time=0.005..0.412 rows=5000 loops=1)
                                 Buffers: shared hit=78
               ->  Hash  (cost=13.60..13.60 rows=180 width=58) (actual time=0.010..0.011 rows=1 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on order_status st  (cost=0.00..13.60 rows=180 width=58) (actual time=0.004..0.005 rows=1 loops=1)
                           Filter: is_revenue
                           Rows Removed by Filter: 4
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=261
 Planning Time: 0.680 ms
 Execution Time: 26.207 ms
```

### 2b. Mart (index có sẵn trong `04_data_mart.sql`)

```
 GroupAggregate  (cost=423.98..449.48 rows=6 width=48) (actual time=16.450..17.762 rows=6 loops=1)
   Group Key: d.year_month
   Buffers: shared hit=195
   ->  Sort  (cost=423.98..430.34 rows=2543 width=24) (actual time=16.148..16.484 rows=9933 loops=1)
         Sort Key: d.year_month, f.order_id
         Sort Method: quicksort  Memory: 893kB
         Buffers: shared hit=195
         ->  Hash Join  (cost=38.04..280.14 rows=2543 width=24) (actual time=0.323..3.254 rows=9933 loops=1)
               Hash Cond: (f.date_key = d.date_key)
               Buffers: shared hit=189
               ->  Nested Loop  (cost=31.99..267.26 rows=2543 width=20) (actual time=0.268..2.134 rows=9933 loops=1)
                     Buffers: shared hit=187
                     ->  Seq Scan on dim_order_status s  (cost=0.00..1.05 rows=1 width=2) (actual time=0.002..0.004 rows=1 loops=1)
                           Filter: is_revenue
                           Rows Removed by Filter: 4
                           Buffers: shared hit=1
                     ->  Bitmap Heap Scan on fact_sales f  (cost=31.99..240.78 rows=2543 width=22) (actual time=0.264..1.236 rows=9933 loops=1)
                           Recheck Cond: (order_status_key = s.order_status_key)
                           Heap Blocks: exact=177
                           Buffers: shared hit=186
                           ->  Bitmap Index Scan on idx_fact_sales_status  (cost=0.00..31.36 rows=2543 width=0) (actual time=0.246..0.246 rows=9933 loops=1)
                                 Index Cond: (order_status_key = s.order_status_key)
                                 Buffers: shared hit=9
               ->  Hash  (cost=3.80..3.80 rows=180 width=12) (actual time=0.041..0.042 rows=180 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 16kB
                     Buffers: shared hit=2
                     ->  Seq Scan on dim_date d  (cost=0.00..3.80 rows=180 width=12) (actual time=0.004..0.017 rows=180 loops=1)
                           Buffers: shared hit=2
 Planning:
   Buffers: shared hit=498
 Planning Time: 1.050 ms
 Execution Time: 18.015 ms
```

### 2c. Mart + covering index cho cột WHERE/JOIN

```sql
CREATE INDEX IF NOT EXISTS idx_fact_sales_status_date_cov
  ON mart.fact_sales(order_status_key, date_key) INCLUDE (order_id, revenue);
VACUUM ANALYZE mart.fact_sales;
```

```
 GroupAggregate  (cost=287.98..313.49 rows=6 width=48) (actual time=14.822..16.206 rows=6 loops=1)
   Group Key: d.year_month
   Buffers: shared hit=66
   ->  Sort  (cost=287.98..294.34 rows=2543 width=24) (actual time=14.525..14.851 rows=9933 loops=1)
         Sort Key: d.year_month, f.order_id
         Sort Method: quicksort  Memory: 893kB
         Buffers: shared hit=66
         ->  Hash Join  (cost=6.33..144.15 rows=2543 width=24) (actual time=0.078..2.529 rows=9933 loops=1)
               Hash Cond: (f.date_key = d.date_key)
               Buffers: shared hit=60
               ->  Nested Loop  (cost=0.29..131.27 rows=2543 width=20) (actual time=0.018..1.430 rows=9933 loops=1)
                     Buffers: shared hit=58
                     ->  Seq Scan on dim_order_status s  (cost=0.00..1.05 rows=1 width=2) (actual time=0.003..0.005 rows=1 loops=1)
                           Filter: is_revenue
                           Rows Removed by Filter: 4
                           Buffers: shared hit=1
                     ->  Index Only Scan using idx_fact_sales_status_date_cov on fact_sales f  (cost=0.29..104.79 rows=2543 width=22) (actual time=0.014..0.814 rows=9933 loops=1)
                           Index Cond: (order_status_key = s.order_status_key)
                           Heap Fetches: 0
                           Buffers: shared hit=57
               ->  Hash  (cost=3.80..3.80 rows=180 width=12) (actual time=0.036..0.037 rows=180 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 16kB
                     Buffers: shared hit=2
                     ->  Seq Scan on dim_date d  (cost=0.00..3.80 rows=180 width=12) (actual time=0.002..0.015 rows=180 loops=1)
                           Buffers: shared hit=2
 Planning:
   Buffers: shared hit=519
 Planning Time: 1.139 ms
 Execution Time: 16.446 ms
```

---

## 3. Bảng so sánh

6 lần chạy (ms):

| Lần | OLTP | Mart | Mart + covering index |
|---:|---:|---:|---:|
| 1 | 25,660 | 18,212 | 16,090 |
| 2 | 24,706 | 17,799 | 15,634 |
| 3 | 25,053 | 17,021 | 15,854 |
| 4 | 26,094 | 17,042 | 16,297 |
| 5 | 24,954 | 17,443 | 15,608 |
| 6 | 25,355 | 17,235 | 16,015 |

| Chỉ số | OLTP | Mart | Mart + covering index |
|---|---:|---:|---:|
| **Median Execution Time** | **25,20 ms** | **17,34 ms** | **15,93 ms** |
| So với OLTP | 1,00× | nhanh hơn ~31% (1,45×) | nhanh hơn ~37% (1,58×) |
| Shared buffers đọc | 252 | 195 | 66 |
| Thời gian tới hết bước JOIN | 10,5 ms | 3,3 ms | 2,5 ms |
| Kiểu đọc fact / bảng lớn | Seq Scan order_items + orders | Bitmap Index Scan | Index Only Scan (Heap Fetches 0) |

---

## 4. Nhận xét

- **Mart nhanh hơn OLTP ~31% (25,20 → 17,34 ms), thêm covering index ~37% (→ 15,93 ms)** cho cùng kết quả.
- Phần chênh lớn nhất nằm ở bước JOIN (10,5 ms → 3,3 ms): OLTP phải hash join 2 bảng lớn theo khóa `VARCHAR` và tính `TO_CHAR(order_date AT TIME ZONE ...)`, `quantity*unit_price-discount` cho từng dòng lúc query; mart đã tính sẵn `revenue`, `year_month` lúc load và join bằng khóa số nguyên nhỏ (`INT`/`SMALLINT`) với dimension 180 dòng.
- Covering index `(order_status_key, date_key) INCLUDE (order_id, revenue)` cho phép Index Only Scan, giảm buffer đọc từ 195 xuống 66 (−66%), nhưng thời gian chỉ giảm thêm ~1,4 ms.
- Phần còn lại (~13 ms ở cả 2 phía) là bước **Sort 9.933 dòng phục vụ `COUNT(DISTINCT order_id)`**, không phụ thuộc OLTP hay mart. Nếu bỏ đếm đơn hoặc dùng bảng tổng hợp `monthly_summary` thì mart sẽ còn tách biệt rõ hơn.
- Data hiện chỉ 12.717 dòng, mọi thứ nằm gọn trong RAM (`shared hit`, không có `read`) nên chênh lệch tuyệt đối mới vài ms. Với hàng triệu dòng, OLTP phải hash join 2 bảng lớn còn mart chỉ quét fact + dim nhỏ, nên khoảng cách sẽ tăng theo kích thước dữ liệu.
