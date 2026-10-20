-- MySQL 8.0 versions of the interview queries. Run one at a time.
USE insurance_practice;

-- 1. In-force policies issued in 2025
SELECT policy_no, plan_code, issue_date, sum_assured
FROM policy
WHERE status = 'In Force'
  AND issue_date >= '2025-01-01' AND issue_date < '2026-01-01';

-- 2. Requests by type
SELECT request_type, COUNT(*) AS total_requests
FROM pos_request GROUP BY request_type ORDER BY total_requests DESC;

-- 3. Average TAT by request type (MySQL: DATEDIFF(end, start) returns days)
SELECT request_type, ROUND(AVG(DATEDIFF(closed_date, received_date)),1) AS avg_tat_days
FROM pos_request WHERE status = 'Closed' GROUP BY request_type;

-- 4. SLA breaches (> 7 days)
SELECT request_id, policy_no, request_type, DATEDIFF(closed_date, received_date) AS tat_days
FROM pos_request
WHERE DATEDIFF(closed_date, received_date) > 7;

-- 5. STP % by request type
SELECT request_type, COUNT(*) AS total,
       SUM(stp_flag = 'Y') AS stp_count,
       ROUND(100.0 * SUM(stp_flag = 'Y') / COUNT(*), 2) AS stp_pct
FROM pos_request GROUP BY request_type;

-- 6. Top 5 rejection reasons (MySQL: LIMIT instead of TOP)
SELECT reject_reason, COUNT(*) AS cnt
FROM pos_request WHERE reject_reason IS NOT NULL
GROUP BY reject_reason ORDER BY cnt DESC LIMIT 5;

-- 7. Monthly trend (MySQL: DATE_FORMAT instead of FORMAT)
SELECT DATE_FORMAT(received_date, '%Y-%m') AS month, COUNT(*) AS requests
FROM pos_request GROUP BY month ORDER BY month;

-- 8. Aging buckets for pending requests (MySQL: CURDATE() instead of GETDATE())
SELECT request_id, DATEDIFF(CURDATE(), received_date) AS age_days,
  CASE WHEN DATEDIFF(CURDATE(), received_date) <= 3 THEN '0-3 days'
       WHEN DATEDIFF(CURDATE(), received_date) <= 7 THEN '4-7 days'
       ELSE '>7 days' END AS age_bucket
FROM pos_request WHERE status = 'Pending';

-- 9. Policies that never raised a POS request
SELECT p.policy_no
FROM policy p LEFT JOIN pos_request r ON p.policy_no = r.policy_no
WHERE r.policy_no IS NULL;

-- 10. Address change requests with customer name and city
SELECT r.request_id, c.name, c.city, r.received_date
FROM pos_request r
JOIN policy p   ON r.policy_no = p.policy_no
JOIN customer c ON p.customer_id = c.customer_id
WHERE r.request_type = 'Address Change';

-- 11. Duplicate requests
SELECT policy_no, request_type, received_date, COUNT(*) AS dup_count
FROM pos_request
GROUP BY policy_no, request_type, received_date
HAVING COUNT(*) > 1;

-- 12. Overdue unpaid premiums
SELECT policy_no, due_date FROM premium_payment
WHERE paid_date IS NULL AND due_date < CURDATE();

-- 13. Second highest sum assured
SELECT MAX(sum_assured) AS second_highest
FROM policy WHERE sum_assured < (SELECT MAX(sum_assured) FROM policy);

-- 14. Latest request per policy (window function, MySQL 8+)
SELECT * FROM (
  SELECT r.*, ROW_NUMBER() OVER (PARTITION BY policy_no ORDER BY received_date DESC) AS rn
  FROM pos_request r
) t WHERE rn = 1;

-- 15. CTE: SLA breach % by channel
WITH tat AS (
  SELECT channel, DATEDIFF(closed_date, received_date) AS tat_days
  FROM pos_request WHERE status = 'Closed'
)
SELECT channel, COUNT(*) AS closed_requests,
       ROUND(100.0 * SUM(tat_days > 7) / COUNT(*), 2) AS breach_pct
FROM tat GROUP BY channel;
