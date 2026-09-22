# Minh chứng nộp bài

Thư mục được chia theo buổi học, bên trong đặt tên theo **số mục trong đề bài**.

```
docs/evidence/
├── buoi-01/   1.1 1.2 1.3 1.4 2.1 2.2
└── buoi-02/   1.1 1.2 1.3 1.4 2.1 2.2
```

Một số artifact đề bài chỉ định đường dẫn cố định ngoài `docs/evidence/`
(ví dụ `docs/answers_02.md`, `docs/query_results.csv`) thì được giữ đúng vị trí
đó, bảng dưới ghi rõ.

---

## Buổi 01 — Thiết kế Database & Khởi động hệ thống

| Mục | Yêu cầu | File |
|---|---|---|
| 1.1 | Ảnh `docker compose ps` | `buoi-01/1.1/01-docker-ps.png` (+ `01-docker-ps.txt`) |
| 1.1 | Ảnh DBeaver kết nối | `buoi-01/1.1/01-dbeaver.png`, `01-dbeaver-current-database.png` |
| 1.1 | Output 2 câu SQL | `buoi-01/1.1/01-verify-db-sql-output.txt`, `01-verify-db.png` |
| 1.1 | *(bổ sung)* Verify đầy đủ: 7 bảng, số dòng, FK, CHECK | `buoi-01/1.1/01-verify-db-full.txt` |
| 1.2 | Ảnh ERD | `buoi-01/1.2/01-erd.png` |
| 1.2 | File DDL | `../../sql/student/01_create_oltp.sql` |
| 1.2 | Source ERD (DBML) | `../../database/ecommerce_oltp.dbml` |
| 1.2 | Log chạy DDL | `buoi-01/1.2/01-ddl-log.txt` |
| 1.3 | Ảnh `git log --oneline` | `buoi-01/1.3/01-git-log.png` |
| 1.3 | Lệnh push GitHub | `buoi-01/1.3/command_github.txt` |
| 1.3 | `.gitignore` | `../../.gitignore` |
| 1.4 | Reflection 150–200 từ | `../reflection_01.md` |
| 2.1 | Log test constraint bị chặn | `buoi-01/2.1/01-bonus-constraint-test.txt` |
| 2.2 | Hướng dẫn chạy SQL | `../../sql/README.md` |

## Buổi 02 — SQL Fundamentals & Business Analytics

| Mục | Yêu cầu | File |
|---|---|---|
| 1.1 | 5 queries Q1–Q5 | `../../sql/student/02_exercises_basic.sql` |
| 1.1 | Output từng query (5 dòng đầu + row count) | `buoi-02/1.1/02-basic-results.txt` |
| 1.2 | 5 queries Q6–Q10 | `../../sql/student/02_exercises_basic.sql` |
| 1.2 | Output tổng hợp | `buoi-02/1.2/02-agg-results.txt` |
| 1.2 | CSV ≥ 2 bảng (tháng–doanh thu, category–doanh thu, trạng thái) | `../query_results.csv` |
| 1.3 | 5 queries Q11–Q15 | `../../sql/student/02_exercises_basic.sql` |
| 1.3 | Output đối soát Q15 + kết luận MATCH/DIFF | `buoi-02/1.3/02-join-q5.txt` |
| 1.3 | *(bổ sung)* Output Q11–Q14 | `buoi-02/1.3/02-join-results.txt` |
| 1.4 | 5 business questions: SQL + đáp án + nhận xét | `../answers_02.md` |
| 1.4 | Output chạy lại | `buoi-02/1.4/02-business-results.txt` |
| 2.1 | 3 advanced queries | `../../sql/student/03_exercises_advanced.sql` (phần `Bonus 2.1`) |
| 2.1 | Output | `buoi-02/2.1/02-bonus.txt` |
| 2.2 | Giải thích INDEX + EXPLAIN trước/sau | `../explain_output/02-explain.md` |
| 2.2 | Output EXPLAIN thô | `buoi-02/2.2/02-explain-raw.txt` |

---

## Repo GitHub

https://github.com/DoCuong-creat/DE_BK
