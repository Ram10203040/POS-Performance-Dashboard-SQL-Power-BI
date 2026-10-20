-- Practice queries for insurance_pos_3m (MySQL 8.0+). Run one at a time.
-- Data window: requests received 1 Jul - 30 Sep 2026. "Today" for aging = 30 Sep 2026.
USE insurance_pos_3m;
SET @asof = '2026-09-30';

-- 1. Requests by month and status
SELECT DATE_FORMAT(received_date,'%Y-%m') AS month, status, COUNT(*) AS requests
FROM pos_request GROUP BY month, status ORDER BY month, status;

-- 2. Average TAT (days) by request type (closed requests only)
SELECT request_type, COUNT(*) AS closed_cnt,
       ROUND(AVG(DATEDIFF(closed_date, received_date)),1) AS avg_tat
FROM pos_request
WHERE status = 'Closed' AND closed_date IS NOT NULL
GROUP BY request_type ORDER BY avg_tat DESC;

-- 3. STP % by channel
SELECT channel, COUNT(*) AS total,
       ROUND(100*SUM(stp_flag='Y')/COUNT(*),1) AS stp_pct
FROM pos_request GROUP BY channel ORDER BY stp_pct DESC;

-- 4. Monthly STP % trend (the dataset has a planted improving trend)
SELECT DATE_FORMAT(received_date,'%Y-%m') AS month, COUNT(*) AS total,
       ROUND(100*SUM(stp_flag='Y')/COUNT(*),1) AS stp_pct
FROM pos_request GROUP BY month ORDER BY month;

-- 5. SLA breach % by request type (SLA: 3 days for simple, 7 for loan/surrender/revival)
WITH t AS (
  SELECT request_type, DATEDIFF(closed_date, received_date) AS tat,
         CASE WHEN request_type IN ('Policy Loan','Surrender','Revival') THEN 7 ELSE 3 END AS sla
  FROM pos_request WHERE status = 'Closed' AND closed_date >= received_date
)
SELECT request_type, COUNT(*) AS closed_cnt, SUM(tat > sla) AS breaches,
       ROUND(100*SUM(tat > sla)/COUNT(*),1) AS breach_pct
FROM t GROUP BY request_type ORDER BY breach_pct DESC;

-- 6. Rejection reasons, ranked
SELECT reject_reason, COUNT(*) AS cnt,
       ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct_of_rejects
FROM pos_request WHERE status = 'Rejected' AND reject_reason IS NOT NULL
GROUP BY reject_reason ORDER BY cnt DESC;

-- 7. Aging of pending requests as of 30 Sep 2026
SELECT CASE WHEN DATEDIFF(@asof, received_date) <= 3 THEN '0-3 days'
            WHEN DATEDIFF(@asof, received_date) <= 7 THEN '4-7 days'
            ELSE '>7 days' END AS age_bucket,
       COUNT(*) AS pending_cnt
FROM pos_request WHERE status = 'Pending' GROUP BY age_bucket;

-- 8. Request volume by weekday (shows weekend dip) and month-end spike
SELECT DAYNAME(received_date) AS weekday, COUNT(*) AS requests
FROM pos_request GROUP BY weekday, DAYOFWEEK(received_date) ORDER BY DAYOFWEEK(received_date);

-- 9. Which plan generates the most POS requests, with customer city mix (joins)
SELECT p.plan_code, COUNT(*) AS requests
FROM pos_request r JOIN policy p ON r.policy_no = p.policy_no
GROUP BY p.plan_code ORDER BY requests DESC;

-- 10. Top 10 cities by request volume (3-table join)
SELECT c.city, COUNT(*) AS requests
FROM pos_request r
JOIN policy p   ON r.policy_no = p.policy_no
JOIN customer c ON p.customer_id = c.customer_id
GROUP BY c.city ORDER BY requests DESC LIMIT 10;

-- 11. Customers with 6 or more requests in the quarter
SELECT c.customer_id, c.name, COUNT(*) AS requests
FROM pos_request r
JOIN policy p   ON r.policy_no = p.policy_no
JOIN customer c ON p.customer_id = c.customer_id
GROUP BY c.customer_id, c.name HAVING COUNT(*) >= 6 ORDER BY requests DESC;

-- 12. Policies that never raised a request
SELECT COUNT(*) AS policies_without_requests
FROM policy p LEFT JOIN pos_request r ON p.policy_no = r.policy_no
WHERE r.request_id IS NULL;

-- 13. Overdue unpaid premiums on policies still In Force
SELECT p.status, COUNT(*) AS unpaid_installments, ROUND(SUM(pp.amount),2) AS amount_at_risk
FROM premium_payment pp JOIN policy p ON pp.policy_no = p.policy_no
WHERE pp.paid_date IS NULL AND pp.due_date < @asof
GROUP BY p.status;

-- 14. Late-payment rate by premium mode
SELECT p.premium_mode, COUNT(*) AS paid_cnt,
       ROUND(100*SUM(pp.paid_date > pp.due_date)/COUNT(*),1) AS late_pct
FROM premium_payment pp JOIN policy p ON pp.policy_no = p.policy_no
WHERE pp.paid_date IS NOT NULL GROUP BY p.premium_mode;

-- 15. Latest request per policy (window function)
SELECT * FROM (
  SELECT r.*, ROW_NUMBER() OVER (PARTITION BY policy_no ORDER BY received_date DESC, request_id DESC) AS rn
  FROM pos_request r
) t WHERE rn = 1 LIMIT 20;

-- 16. Month-over-month change in request volume (LAG)
WITH m AS (
  SELECT DATE_FORMAT(received_date,'%Y-%m') AS month, COUNT(*) AS cnt FROM pos_request GROUP BY month
)
SELECT month, cnt, cnt - LAG(cnt) OVER (ORDER BY month) AS change_vs_prev FROM m;

-- ================= DATA-QUALITY CHECKS (answer key is in README.md) =================
-- DQ1. Closed requests with no closed date
SELECT request_id FROM pos_request WHERE status = 'Closed' AND closed_date IS NULL;

-- DQ2. Requests closed before they were received
SELECT request_id, received_date, closed_date FROM pos_request WHERE closed_date < received_date;

-- DQ3. Rejected requests with no reason
SELECT request_id FROM pos_request WHERE status = 'Rejected' AND reject_reason IS NULL;

-- DQ4. Duplicate requests (same policy, type and received date)
SELECT policy_no, request_type, received_date, COUNT(*) AS dup_count, GROUP_CONCAT(request_id) AS request_ids
FROM pos_request GROUP BY policy_no, request_type, received_date HAVING COUNT(*) > 1;

-- DQ5. Requests received before the policy was issued (should return 0 rows)
SELECT r.request_id FROM pos_request r JOIN policy p ON r.policy_no = p.policy_no
WHERE r.received_date < p.issue_date;
