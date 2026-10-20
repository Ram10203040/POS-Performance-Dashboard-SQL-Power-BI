USE insurance_practice;
SHOW tables;
SELECT * FROM customer;
SELECT * FROM policy;
SELECT * FROM pos_request;
SELECT * FROM premium_payment;

-- Find In-Force policies in 2024
SELECT * FROM policy
WHERE status ='In Force' 
AND
-- issue_date >= '2024-01-01' AND issue_date <= '2024-12-31';
issue_date BETWEEN '2024-01-01' AND '2024-12-31';

-- Find number of Requests by type
SELECT 
    request_type,
    COUNT(request_id)
FROM pos_request
GROUP BY request_type;

-- 3. Average TAT by request type (MySQL: DATEDIFF(end, start) returns days)

SELECT 
		request_type,
		ROUND(AVG(DATEDIFF(closed_date,received_date)),1) AS avg_tat
FROM pos_request
WHERE status ='closed'
GROUP BY request_type;
-- 4. SLA breaches (> 7 days) 

SELECT 
		request_type,
	    received_date,
        closed_date,
		DATEDIFF(closed_date,received_date) AS avg_tat
FROM pos_request
WHERE DATEDIFF(closed_date,received_date) > 7;
  
  -- 7. Calculate STP % by request type.
    SELECT request_type,
       COUNT(*) AS total,
       -- SUM(CASE WHEN stp_flag = 'Y' THEN 1 ELSE 0 END) AS stp_count,
       ROUND(100.0 * SUM(CASE WHEN stp_flag = 'Y' THEN 1 ELSE 0 END) / COUNT(*), 2) AS stp_pct
FROM pos_request
GROUP BY request_type;
-- 8. What are the top 5 rejection reasons?
SELECT reject_reason, COUNT(*) AS cnt
FROM pos_request
WHERE reject_reason IS NOT NULL
GROUP BY reject_reason
ORDER BY cnt DESC
LIMIT 5;

-- Show the monthly trend of requests.
SELECT FORMAT(received_date, 'yyyy-MM') AS month,
       COUNT(*) AS requests
FROM pos_request
GROUP BY FORMAT(received_date, 'yyyy-MM')
ORDER BY month;

