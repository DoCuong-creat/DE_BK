# Buổi 04 — 5 KPI từ Sales Data Mart

Database: `ecommerce` / schema `mart` (build bằng `sql/student/04_data_mart.sql`).
Cả 5 query chỉ đọc `mart.fact_sales` JOIN các `mart.dim_*`, **không JOIN bảng `core.*`**.
File SQL: `sql/student/04_kpi_from_mart.sql`. Output chạy lại: `docs/evidence/04-kpi-results.txt`.

Định nghĩa doanh thu: `SUM(fact_sales.revenue)` (net, đã trừ discount) của các dòng có
`dim_order_status.is_revenue = TRUE` (= đơn `completed`), thống nhất với Buổi 2–3.
Phạm vi: 2026-01-01 → 2026-06-29 (giờ VN).

---

## KPI1. Total revenue by month

```sql
SELECT d.year_month,
       COUNT(DISTINCT f.order_id) AS orders,
       SUM(f.revenue)             AS revenue
FROM fact_sales f
JOIN dim_date d         ON d.date_key = f.date_key
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY d.year_month
ORDER BY d.year_month;
```

| year_month | orders | revenue (VND) |
|---|---:|---:|
| 2026-01 | 654 | 8.231.711.000 |
| 2026-02 | 590 | 7.058.655.000 |
| 2026-03 | 712 | **8.998.721.500** |
| 2026-04 | 623 | 7.801.828.500 |
| 2026-05 | 675 | 8.230.727.000 |
| 2026-06 | 626 | 7.756.301.000 |
| **Tổng** | **3.880** | **48.077.944.000** |

**Đáp án: tháng cao nhất là 03/2026 — 8.998.721.500 VND; thấp nhất 02/2026 — 7.058.655.000 VND.**

Nhận xét: doanh thu dao động trong biên ~7–9 tỷ/tháng, tháng 2 thấp do ít ngày hơn và trùng Tết; số tháng 6 (7.756.301.000) khớp với đáp án B1 của Buổi 2 tính trực tiếp trên OLTP.

---

## KPI2. Revenue by category

```sql
SELECT p.parent_category                                      AS category,
       SUM(f.revenue)                                         AS revenue,
       ROUND(100.0 * SUM(f.revenue) / SUM(SUM(f.revenue)) OVER (), 2) AS pct_of_total
FROM fact_sales f
JOIN dim_product p      ON p.product_key = f.product_key
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY p.parent_category
ORDER BY revenue DESC;
```

| category | revenue (VND) | % |
|---|---:|---:|
| Beauty | 11.308.194.500 | 23,52 |
| Home & Living | 10.207.795.000 | 21,23 |
| Electronics | 9.437.830.500 | 19,63 |
| Sports | 9.338.564.000 | 19,42 |
| Books | 7.785.560.000 | 16,19 |

**Đáp án: Beauty dẫn đầu với 11.308.194.500 VND (23,52%).**

Nhận xét: 5 nhóm khá cân bằng (16–24%), nhờ `dim_product` đã denormalize sẵn danh mục cha nên chỉ cần 1 JOIN thay vì products → categories → categories như OLTP.

---

## KPI3. Top 10 products theo revenue

```sql
SELECT p.product_id, p.product_name, p.category,
       SUM(f.quantity) AS units_sold,
       SUM(f.revenue)  AS revenue
FROM fact_sales f
JOIN dim_product p      ON p.product_key = f.product_key
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY p.product_id, p.product_name, p.category
ORDER BY revenue DESC, p.product_id
LIMIT 10;
```

| # | product_id | product_name | category | units | revenue (VND) |
|---:|---|---|---|---:|---:|
| 1 | PRD000297 | Product 297 Cell | Skincare | 40 | 302.895.000 |
| 2 | PRD000309 | Product 309 Ability | Home Decor | 43 | 297.192.000 |
| 3 | PRD000203 | Product 203 Environment | Phones | 36 | 260.936.000 |
| 4 | PRD000300 | Product 300 Term | Sportswear | 35 | 259.776.000 |
| 5 | PRD000173 | Product 173 Trade | Skincare | 35 | 248.452.500 |
| 6 | PRD000268 | Product 268 Stuff | Accessories | 33 | 247.468.500 |
| 7 | PRD000204 | Product 204 Realize | Phones | 34 | 238.183.000 |
| 8 | PRD000126 | Product 126 One | Personal Care | 35 | 236.880.000 |
| 9 | PRD000238 | Product 238 Character | Fitness | 33 | 233.859.500 |
| 10 | PRD000084 | Product 084 Job | Home Decor | 32 | 233.227.500 |

**Đáp án: top 1 là PRD000297 — Product 297 Cell — 302.895.000 VND.**

Nhận xét: top 10 trải đều nhiều danh mục và chỉ chiếm ~5,3% tổng doanh thu, tức doanh thu không phụ thuộc vào vài sản phẩm chủ lực. GROUP BY `product_id` (không phải `product_key`) để vẫn đúng khi `dim_product` có nhiều version SCD2.

---

## KPI4. AOV (Average Order Value)

```sql
SELECT SUM(f.revenue)                                        AS revenue,
       COUNT(DISTINCT f.order_id)                            AS orders,
       ROUND(SUM(f.revenue) / COUNT(DISTINCT f.order_id), 2) AS aov
FROM fact_sales f
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue;
```

**Đáp án: AOV = 48.077.944.000 / 3.880 đơn = 12.391.222,68 VND.**

Nhận xét: vì grain là order_item nên bắt buộc `COUNT(DISTINCT order_id)` (degenerate dimension); dùng `COUNT(*)` sẽ ra số dòng hàng và làm AOV thấp sai ~2,5 lần.

---

## KPI5. Customer count by segment / region

```sql
-- 5a. theo segment
SELECT c.customer_segment,
       COUNT(DISTINCT f.customer_key)                            AS customers,
       SUM(f.revenue)                                            AS revenue,
       ROUND(SUM(f.revenue) / COUNT(DISTINCT f.customer_key), 2) AS revenue_per_customer
FROM fact_sales f
JOIN dim_customer c     ON c.customer_key = f.customer_key
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY c.customer_segment
ORDER BY revenue DESC;

-- 5b. theo region (city)
SELECT c.city AS region,
       COUNT(DISTINCT f.customer_key) AS customers,
       SUM(f.revenue)                 AS revenue
FROM fact_sales f
JOIN dim_customer c     ON c.customer_key = f.customer_key
JOIN dim_order_status s ON s.order_status_key = f.order_status_key
WHERE s.is_revenue
GROUP BY c.city
ORDER BY customers DESC, region;
```

| segment | customers | revenue (VND) | revenue / customer |
|---|---:|---:|---:|
| Standard | 549 | 28.241.059.000 | 51.440.908,93 |
| Silver | 233 | 10.975.640.000 | 47.105.751,07 |
| Gold | 147 | 6.854.916.500 | 46.632.085,03 |
| Platinum | 44 | 2.006.328.500 | 45.598.375,00 |
| **Tổng** | **973** | **48.077.944.000** | |

| region | customers | revenue (VND) |
|---|---:|---:|
| Bac Ninh | 111 | 5.664.023.500 |
| Vinh | 110 | 5.354.184.500 |
| Ho Chi Minh City | 109 | 5.404.917.500 |
| Hai Phong | 97 | 4.549.735.500 |
| Can Tho | 94 | 4.785.581.500 |
| Da Nang | 94 | 4.707.089.000 |
| Hue | 94 | 4.302.904.500 |
| Nha Trang | 91 | 5.163.161.500 |
| Quang Ninh | 90 | 4.522.311.000 |
| Hanoi | 83 | 3.624.035.500 |

**Đáp án: 973 khách có đơn completed; đông nhất là segment Standard (549 khách), region Bac Ninh (111 khách).**

Nhận xét: doanh thu/khách gần như không tăng theo hạng (Platinum còn thấp hơn Standard) — tiêu chí xếp hạng segment hiện chưa phản ánh giá trị mua thực tế, nên xem lại cùng kết quả RFM Buổi 3. Region dùng `city` của khách hàng (dim_customer), không phải `shipping_city` của đơn.
