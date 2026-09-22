# Buổi 02 — Bonus 2.2: Performance & Optimization

Output thô của lần chạy: `docs/evidence/buoi-02/2.2/02-explain-raw.txt`

## 1. Vì sao cần INDEX cho cột hay dùng trong WHERE/JOIN

Không có index, PostgreSQL phải **Seq Scan** — đọc tuần tự toàn bộ bảng rồi loại bỏ những dòng không thỏa điều kiện. Với `core.orders`, một truy vấn lọc theo `shipping_city` phải đọc cả 5.000 dòng để lấy về 384 dòng, tức **hơn 92% công đọc là lãng phí**.

Index B-tree lưu sẵn giá trị của cột theo thứ tự đã sắp xếp cùng con trỏ tới vị trí dòng trên đĩa, nên planner nhảy thẳng tới đúng nhóm dòng cần lấy thay vì quét hết. Chi phí đánh đổi là index chiếm thêm dung lượng và làm chậm `INSERT`/`UPDATE`/`DELETE` vì mỗi lần ghi phải cập nhật thêm cây index — vì vậy chỉ đánh index cho cột thực sự hay xuất hiện trong `WHERE`, `JOIN`, `ORDER BY`.

Với cột FK như `orders.customer_id` hay `order_items.order_id`, index còn quan trọng hơn: mỗi phép JOIN giữa bảng cha và bảng con đều tra cứu theo cột đó, không có index thì planner buộc phải Hash Join hoặc Nested Loop kèm Seq Scan lặp lại nhiều lần.

## 2. Query dùng để đo

Chọn cột `shipping_city` vì đây là cột **chưa có index** trong schema Lab 2 (các cột `customer_id`, `order_date`, `status` đã được đánh index sẵn nên không thể hiện được sự khác biệt).

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, order_date, order_total
FROM core.orders
WHERE shipping_city = 'Hue' AND status = 'completed';
```

Query trả về **384 dòng / 5.000 dòng** của bảng `orders`.

## 3. TRƯỚC khi tạo index

```
Seq Scan on orders  (cost=0.00..153.00 rows=376 width=34) (actual time=0.004..0.261 rows=384 loops=1)
  Filter: (((shipping_city)::text = 'Hue'::text) AND ((status)::text = 'completed'::text))
  Rows Removed by Filter: 4616
  Buffers: shared hit=78
Planning Time: 0.098 ms
Execution Time: 0.289 ms
```

## 4. Tạo index

```sql
CREATE INDEX idx_orders_shipping_city ON core.orders(shipping_city);
ANALYZE core.orders;
```

## 5. SAU khi tạo index

```
Bitmap Heap Scan on orders  (cost=8.01..93.27 rows=376 width=34) (actual time=0.065..0.174 rows=384 loops=1)
  Recheck Cond: ((shipping_city)::text = 'Hue'::text)
  Filter: ((status)::text = 'completed'::text)
  Rows Removed by Filter: 100
  Heap Blocks: exact=78
  Buffers: shared hit=78 read=3
  ->  Bitmap Index Scan on idx_orders_shipping_city  (cost=0.00..7.91 rows=484 width=0) (actual time=0.052..0.052 rows=484 loops=1)
        Index Cond: ((shipping_city)::text = 'Hue'::text)
Planning Time: 0.119 ms
Execution Time: 0.208 ms
```

## 6. So sánh và nhận xét

| Chỉ số | Trước index | Sau index | Thay đổi |
|---|---|---|---|
| Node quét | Seq Scan | Bitmap Index Scan → Bitmap Heap Scan | đổi chiến lược |
| Estimated cost | 153.00 | 93.27 | **−39%** |
| Execution Time | 0.289 ms | 0.208 ms | **−28%** |
| Rows Removed by Filter | 4.616 | 100 | **−97,8%** |

Điểm quan trọng nhất không nằm ở mili-giây mà ở dòng **`Rows Removed by Filter`**: từ 4.616 dòng đọc thừa xuống còn 100. Index đã loại bỏ gần như toàn bộ công đọc vô ích; 100 dòng còn lại bị loại là do điều kiện thứ hai `status = 'completed'` — index chỉ phủ `shipping_city`.

Mức cải thiện thời gian ở đây khiêm tốn (0,289 → 0,208 ms) vì bảng chỉ có 5.000 dòng, toàn bộ nằm gọn trong shared buffer nên Seq Scan vốn đã rất nhanh. **Khoảng cách này giãn ra rất nhanh theo kích thước bảng**: Seq Scan tăng tuyến tính O(n) theo số dòng, còn tra cứu B-tree chỉ tăng theo O(log n). Ở quy mô hàng triệu đơn — đúng quy mô thật của hệ thống e-commerce mà `business_requirements.md` mô tả — chênh lệch sẽ là hàng trăm mili-giây so với vài mili-giây.

Nếu muốn tối ưu thêm cho đúng truy vấn này, có thể dùng **composite index** phủ cả hai cột điều kiện:

```sql
CREATE INDEX idx_orders_city_status ON core.orders(shipping_city, status);
```

Khi đó `Rows Removed by Filter` sẽ về 0 vì cả hai điều kiện đều được xử lý ngay trong index, không cần lọc lại ở tầng heap.
