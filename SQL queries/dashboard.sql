USE insurance_pos_3m;
SELECT *FROM v_request_detail;
SELECT * FROM customer;
SELECT * FROM policy;
SELECT * FROM premium_payment;
SELECT * FROM pos_request;

-- One flat row per request, with every field a dashboard needs and a data-quality flag.
CREATE OR REPLACE VIEW v_request_detail AS
SELECT y.*,
       CASE WHEN y.tat_days IS NULL THEN NULL 
       WHEN y.tat_days > y.sla_days THEN 1 ELSE 0 END AS sla_breach,
       CASE WHEN y.status <> 'Pending' THEN NULL
            WHEN y.age_days <= 3 THEN '0-3 days'
            WHEN y.age_days <= 7 THEN '4-7 days'
            ELSE '>7 days' END AS age_bucket,
       CASE WHEN y.dup_rank > 1 THEN 'Duplicate'
            WHEN y.status = 'Closed' AND y.closed_date IS NULL THEN 'Missing closed date'
            WHEN y.closed_date < y.received_date THEN 'Closed before received'
            WHEN y.status = 'Rejected' AND y.reject_reason IS NULL THEN 'Missing reject reason'
            ELSE NULL END AS dq_issue
FROM (
  SELECT r.request_id, r.policy_no, r.request_type, r.channel, r.status, r.stp_flag,
         r.received_date, r.closed_date, r.reject_reason,
         ROW_NUMBER() OVER (PARTITION BY r.policy_no, r.request_type, r.received_date ORDER BY r.request_id) AS dup_rank,
         DATE_FORMAT(r.received_date, '%Y-%m') AS received_month,
         DATE_SUB(r.received_date, INTERVAL WEEKDAY(r.received_date) DAY) AS week_start,
         DAYNAME(r.received_date) AS weekday_name,
         CASE WHEN r.request_type IN ('Policy Loan','Surrender','Revival') THEN 7 ELSE 3 END AS sla_days,
         CASE WHEN r.status = 'Closed' AND r.closed_date >= r.received_date
              THEN DATEDIFF(r.closed_date, r.received_date) END AS tat_days,
         CASE WHEN r.status = 'Pending' THEN DATEDIFF('2026-09-30', r.received_date) END AS age_days,
         p.plan_code, p.status AS policy_status, p.premium_mode,
         c.customer_id, c.city, c.state 
  FROM pos_request r
  JOIN policy p   ON r.policy_no = p.policy_no
  JOIN customer c ON p.customer_id = c.customer_id
) y;

-- Cleaned dataset for the dashboard: rows with data-quality issues removed.
CREATE OR REPLACE VIEW v_request_clean AS
SELECT * FROM v_request_detail WHERE dq_issue IS NULL;

-- Premium collection dataset.
CREATE OR REPLACE VIEW v_premium_detail AS
SELECT pp.payment_id, pp.policy_no, pp.due_date, pp.paid_date, pp.amount,
       DATE_FORMAT(pp.due_date, '%Y-%m') AS due_month,
       p.status AS policy_status, p.plan_code, p.premium_mode,
       CASE WHEN pp.paid_date IS NULL THEN 'Unpaid'
            WHEN pp.paid_date > pp.due_date THEN 'Paid late' ELSE 'Paid on time' END AS payment_status,
       CASE WHEN pp.paid_date > pp.due_date THEN DATEDIFF(pp.paid_date, pp.due_date) END AS days_late
FROM premium_payment pp JOIN policy p ON pp.policy_no = p.policy_no;
 
-- Data-quality summary (shows what was excluded from the clean view; putting this on a "Data notes" page).

SELECT dq_issue, COUNT(*) AS rows_excluded FROM v_request_detail WHERE dq_issue IS NOT NULL GROUP BY dq_issue;

-- 1.1 KPI cards (one row, one number per card)
SELECT COUNT(*)                                              AS total_requests,
       SUM(status = 'Closed')                                AS closed,
       SUM(status = 'Rejected')                              AS rejected,
       SUM(status = 'Pending')                               AS pending,
       ROUND(100*SUM(status = 'Rejected')/COUNT(*), 1)       AS rejection_pct,
       ROUND(100*SUM(stp_flag = 'Y')/COUNT(*), 1)            AS stp_pct,
       ROUND(AVG(tat_days), 1)                               AS avg_tat_days,
       ROUND(100*SUM(sla_breach)/COUNT(sla_breach), 1)       AS sla_breach_pct,
       SUM(status = 'Pending' AND age_days > 7)              AS pending_over_7_days
FROM v_request_clean;
 
-- 1.2 Monthly trend (line/column chart: volume, STP %, TAT, SLA breach %)
SELECT received_month, COUNT(*) AS requests,
       ROUND(100*SUM(stp_flag = 'Y')/COUNT(*), 1)            AS stp_pct,
       ROUND(AVG(tat_days), 1)                               AS avg_tat_days,
       ROUND(100*SUM(sla_breach)/COUNT(sla_breach), 1)       AS sla_breach_pct,
       ROUND(100*SUM(status = 'Rejected')/COUNT(*), 1)       AS rejection_pct
FROM v_request_clean GROUP BY received_month ORDER BY received_month;


-- 1.3 Weekly volume trend
SELECT week_start, COUNT(*) AS requests, ROUND(100*SUM(stp_flag = 'Y')/COUNT(*), 1) AS stp_pct
FROM v_request_clean GROUP BY week_start ORDER BY week_start;
 
-- 1.4 Status split (donut chart)
SELECT status, COUNT(*) AS requests, ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (), 1) AS pct
FROM v_request_clean GROUP BY status;
 
-- ---------------------------------------------------------------------
-- PAGE 2: TURNAROUND AND SLA (by request type)
-- ---------------------------------------------------------------------
-- 2.1 Request type scorecard (table or bar chart)
SELECT request_type, sla_days, COUNT(*) AS requests,
       ROUND(AVG(tat_days), 1)                               AS avg_tat_days,
       ROUND(100*SUM(sla_breach)/COUNT(sla_breach), 1)       AS sla_breach_pct,
       ROUND(100*SUM(stp_flag = 'Y')/COUNT(*), 1)            AS stp_pct,
       ROUND(100*SUM(status = 'Rejected')/COUNT(*), 1)       AS rejection_pct
FROM v_request_clean GROUP BY request_type, sla_days ORDER BY avg_tat_days DESC;
 
-- 2.2 Worst SLA breaches (drill-through table)
SELECT request_id, policy_no, request_type, channel, received_date, closed_date, tat_days, sla_days
FROM v_request_clean WHERE sla_breach = 1 ORDER BY tat_days - sla_days DESC LIMIT 25;
 
-- ---------------------------------------------------------------------
-- PAGE 3: CHANNEL PERFORMANCE
-- ---------------------------------------------------------------------
-- 3.1 Channel scorecard
SELECT channel, COUNT(*) AS requests,
       ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (), 1)          AS share_pct,
       ROUND(100*SUM(stp_flag = 'Y')/COUNT(*), 1)            AS stp_pct,
       ROUND(AVG(tat_days), 1)                               AS avg_tat_days,
       ROUND(100*SUM(status = 'Rejected')/COUNT(*), 1)       AS rejection_pct
FROM v_request_clean GROUP BY channel ORDER BY stp_pct DESC;
 
-- 3.2 STP % heatmap: request type x channel (matrix visual)
SELECT request_type, channel, COUNT(*) AS requests, ROUND(100*SUM(stp_flag = 'Y')/COUNT(*), 1) AS stp_pct
FROM v_request_clean GROUP BY request_type, channel ORDER BY request_type, channel;
 
-- 3.3 Channel STP trend by month (shows whether digital adoption is improving)
SELECT received_month, channel, ROUND(100*SUM(stp_flag = 'Y')/COUNT(*), 1) AS stp_pct
FROM v_request_clean GROUP BY received_month, channel ORDER BY received_month, channel;
 
-- ---------------------------------------------------------------------
-- PAGE 4: REJECTIONS
-- ---------------------------------------------------------------------
-- 4.1 Rejection reasons (Pareto: bar + cumulative %)
SELECT reject_reason, COUNT(*) AS rejections,
       ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (), 1)                              AS pct,
       ROUND(100*SUM(COUNT(*)) OVER (ORDER BY COUNT(*) DESC)/SUM(COUNT(*)) OVER (), 1) AS cumulative_pct
FROM v_request_clean WHERE status = 'Rejected' GROUP BY reject_reason ORDER BY rejections DESC;
 
-- 4.2 Rejection reason by request type (stacked bar)
SELECT request_type, reject_reason, COUNT(*) AS rejections
FROM v_request_clean WHERE status = 'Rejected' GROUP BY request_type, reject_reason ORDER BY request_type, rejections DESC;
 
-- ---------------------------------------------------------------------
-- PAGE 5: PENDING WORKLOAD AND AGEING
-- ---------------------------------------------------------------------
-- 5.1 Pending by age bucket and request type
SELECT age_bucket, request_type, COUNT(*) AS pending_requests
FROM v_request_clean WHERE status = 'Pending' GROUP BY age_bucket, request_type ORDER BY age_bucket, pending_requests DESC;
 
-- 5.2 Oldest pending requests (action list)
SELECT request_id, policy_no, request_type, channel, received_date, age_days
FROM v_request_clean WHERE status = 'Pending' ORDER BY age_days DESC LIMIT 20;
 
-- ---------------------------------------------------------------------
-- PAGE 6: CUSTOMER, PLAN AND GEOGRAPHY
-- ---------------------------------------------------------------------
-- 6.1 Requests by city (map or bar), top 10
SELECT city, state, COUNT(*) AS requests, ROUND(100*SUM(stp_flag = 'Y')/COUNT(*), 1) AS stp_pct
FROM v_request_clean GROUP BY city, state ORDER BY requests DESC LIMIT 10;
 
-- 6.2 Request mix by plan
SELECT plan_code, request_type, COUNT(*) AS requests
FROM v_request_clean GROUP BY plan_code, request_type ORDER BY plan_code, requests DESC;
 
-- 6.3 Repeat requesters: customers with 6+ requests
SELECT customer_id, COUNT(*) AS requests, COUNT(DISTINCT request_type) AS distinct_types
FROM v_request_clean GROUP BY customer_id HAVING COUNT(*) >= 6 ORDER BY requests DESC;
 
-- ---------------------------------------------------------------------
-- PAGE 7: PREMIUM COLLECTION
-- ---------------------------------------------------------------------
-- 7.1 Monthly collection summary
SELECT due_month, COUNT(*) AS installments_due, ROUND(SUM(amount), 0) AS amount_due,
       ROUND(100*SUM(payment_status = 'Paid on time')/COUNT(*), 1) AS on_time_pct,
       ROUND(100*SUM(payment_status = 'Paid late')/COUNT(*), 1)    AS late_pct,
       ROUND(100*SUM(payment_status = 'Unpaid')/COUNT(*), 1)       AS unpaid_pct
FROM v_premium_detail GROUP BY due_month ORDER BY due_month;
 
-- 7.2 Unpaid amount at risk by policy status
SELECT policy_status, COUNT(*) AS unpaid_installments, ROUND(SUM(amount), 0) AS amount_at_risk
FROM v_premium_detail WHERE payment_status = 'Unpaid' GROUP BY policy_status;
 
-- 7.3 Collection by premium mode
SELECT premium_mode, COUNT(*) AS installments,
       ROUND(100*SUM(payment_status = 'Unpaid')/COUNT(*), 1) AS unpaid_pct,
       ROUND(AVG(days_late), 1)                              AS avg_days_late_when_late
FROM v_premium_detail GROUP BY premium_mode;
 

