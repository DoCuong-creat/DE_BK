# Reflection — Buổi 03: SQL nâng cao, Customer Analytics & Cohort

## Cohort nào giữ chân tốt nhất, vì sao?

Nguồn: `docs/cohort_retention.csv`, heatmap `docs/evidence/03-cohort.png`.

1. **Cohort 2026-01 giữ chân tốt nhất và đáng tin nhất.** Cohort này lớn nhất (540 khách), theo dõi được 5 tháng và retention không giảm theo thời gian: M1 53.7%, M2 58.9%, M5 vẫn 55.6%.
2. Nếu chỉ nhìn M1 thì cohort 2026-04 cao nhất (59.1%), nhưng cohort chỉ có 44 khách, mỗi khách chiếm 2.3 điểm %. Chênh lệch 5 điểm so với T1 chỉ tương đương khoảng 2 người, nên chưa kết luận được. Cohort T5 (22 khách) và T6 (9 khách) còn nhỏ hơn.
3. **Vì sao T1 vượt trội:** cả 987 khách đều có `created_at` trong năm 2025, còn dữ liệu đơn hàng bắt đầu từ 2026-01-01. Vì vậy "cohort T1" thực chất gồm khách cũ mua thường xuyên nhất, là những người xuất hiện ngay tháng đầu. Đây là hiện tượng *left-censoring*: cohort ở đây là "tháng mua đầu tiên trong cửa sổ quan sát", không phải khách mới thật.
4. Các cohort đến muộn (T4 đến T6) là những khách mua thưa, vài tháng mới mua một lần. Cohort càng muộn thì càng nhỏ (540, 235, 137, 44, 22, 9), khớp với cách giải thích này.
5. Đường retention đi ngang quanh 50–59%, không có dạng "rơi mạnh ở M1 rồi tắt dần" như dữ liệu thật. Nhiều khả năng dữ liệu seed được sinh với xác suất mua đều mỗi tháng.
6. **Hành động:** khi so sánh các cohort nên dùng cùng mốc (M1, M2), bỏ qua cohort dưới khoảng 50 khách, và định nghĩa cohort theo `customers.created_at` khi có lịch sử đơn hàng dài hơn.

## Chạy được gì, gặp lỗi gì, kiểm chứng thế nào

- Toàn bộ `sql/student/03_cte_window_cohort.sql` chạy liền một lượt bằng `psql -v ON_ERROR_STOP=1` và không có lỗi.
- **Đơn vị tiền:** ngưỡng 500 / 2000 của đề là số USD, trong khi dữ liệu là VND với trung vị khoảng 55 triệu/khách. Áp nguyên ngưỡng thì 100% khách rơi vào nhóm High, nên đã quy đổi thành 50 / 100 triệu.
- **Ô cohort chưa đến hạn:** lúc đầu các ô này ra 0%, dễ hiểu nhầm là khách rời bỏ. Đã sửa thành NULL khi `cohort_month + k` vượt quá tháng cuối của dữ liệu.
- **Running total (W5):** frame mặc định `RANGE` cộng dồn các đơn trùng `order_date` cùng một lúc. Đã đổi sang `ROWS` và thêm `order_id` làm tie-breaker.
- **Đối soát:** tổng `cohort_size` = 540 + 235 + 137 + 44 + 22 + 9 = 987, bằng đúng số dòng của bảng RFM và của CTE3. RFM không có NULL, `recency_days` nhỏ nhất bằng 87 (≥ 0). Cột `retention_m1_pct` của CTE5 khớp với cột `m1` của bảng cohort.
