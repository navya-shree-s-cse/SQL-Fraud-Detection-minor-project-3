
-- RedFlag - Fraud check project
-- Student: Navyashree

USE redflag;

-- =====================================================================
-- PATTERN 1 - VELOCITY FRAUD (TOO MANY TRANSACTIONS)
-- Check users who made 30 or more transactions on the same day.
-- =====================================================================
SELECT
    user_id,
    DATE(txn_time) AS transaction_date,
    COUNT(*) AS transaction_count
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY transaction_count DESC;

-- Result: 50 users (rows)
-- example: user_id  transcation_date  transaction_count
-- 		   14501     2024-04-14            37

-- =====================================================================
-- PATTERN 2 - ROUND NUMBER PAYMENTS
-- Check users who have 15 or more payments with common round amounts.
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS round_amount_txns
FROM transactions
WHERE amount IN (100, 200, 500, 1000, 2000, 5000, 10000)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY round_amount_txns DESC;

-- Result: 25 rows
-- ex:
-- user_id  round_amount_txns
-- 14548      28

-- =====================================================================
-- PATTERN 3 - CARD TESTING (SMALL PAYMENT TESTING)
-- Check users making 30 or more payments below 10 on one day.
-- =====================================================================
SELECT
    user_id,
    DATE(txn_time) AS transaction_date,
    COUNT(*) AS small_txn_count
FROM transactions
WHERE amount < 10
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY small_txn_count DESC;

-- Result: 20 rows
-- ex: user_id  transcation_date  small_txn_count
--       14569   2024-04-03            60

-- =====================================================================
-- PATTERN 4 - FAILED THEN SUCCESS
-- Check users having 20 or more failed transactions.
-- This uses the simple version from the project brief.
-- =====================================================================
SELECT
    f.user_id,
    COUNT(*) AS retry_pairs
FROM transactions AS f
JOIN transactions AS s
    ON  s.user_id  = f.user_id
    AND s.status   = 'SUCCESS'
    AND s.amount   = f.amount
    AND s.txn_time >= f.txn_time
    AND TIMESTAMPDIFF(MINUTE, f.txn_time, s.txn_time) <= 2
WHERE f.status = 'FAILED'
GROUP BY f.user_id
HAVING COUNT(*) >= 20
ORDER BY retry_pairs DESC;

-- Result: 25 users

-- =====================================================================
-- PATTERN 5 - ODD HOURS (LATE NIGHT ACTIVITY)
-- Check users with most of their transactions between 2 AM and 4 AM.
-- They should also have at least 30 transactions in total.
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS total_txns,
    SUM(
        CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
            ELSE 0
        END
    ) AS odd_hour_txns,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS odd_hour_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 30
   AND SUM(
        CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
            ELSE 0
        END
       ) / COUNT(*) >= 0.80
ORDER BY odd_hour_percentage DESC;

-- Result: 20 rows
-- =====================================================================
-- PATTERN 6 - MULE ACCOUNT ACTIVITY
-- Check for a credit followed by a large debit from the same user
-- within 30 minutes.
-- =====================================================================
SELECT
    c.user_id,
    COUNT(*) AS matched_credit_events
FROM transactions AS c
WHERE c.txn_type = 'CREDIT'
  AND EXISTS (
      SELECT 1
      FROM transactions AS d
      WHERE d.user_id = c.user_id
        AND d.txn_type = 'DEBIT'
        AND d.txn_time > c.txn_time
        AND d.txn_time <= c.txn_time + INTERVAL 30 MINUTE
        AND d.amount >= 0.70 * c.amount
  )
GROUP BY c.user_id
HAVING COUNT(*) >= 5
ORDER BY matched_credit_events DESC;


-- =====================================================================
-- PATTERN 7 - TOO MANY REFUNDS
-- Check users with 20 or more transactions where refunds are over 40%.
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS total_txns,
    SUM(
        CASE
            WHEN txn_type = 'REFUND' THEN 1
            ELSE 0
        END
    ) AS refund_count,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN txn_type = 'REFUND' THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS refund_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 20
   AND SUM(
        CASE
            WHEN txn_type = 'REFUND' THEN 1
            ELSE 0
        END
       ) / COUNT(*) > 0.40
ORDER BY refund_percentage DESC;


-- =====================================================================
-- PATTERN 8 - MERCHANT AND USER CONNECTION
-- Check merchants where the top five users make up more than 60%
-- of the total transaction amount.
-- =====================================================================
WITH user_merchant_totals AS (
    SELECT
        merchant_id,
        user_id,
        SUM(amount) AS user_value
    FROM transactions
    GROUP BY merchant_id, user_id
),
ranked_users AS (
    SELECT
        merchant_id,
        user_id,
        user_value,
        ROW_NUMBER() OVER (
            PARTITION BY merchant_id
            ORDER BY user_value DESC
        ) AS user_rank
    FROM user_merchant_totals
),
merchant_totals AS (
    SELECT
        merchant_id,
        SUM(amount) AS merchant_value
    FROM transactions
    GROUP BY merchant_id
),
top_five AS (
    SELECT
        merchant_id,
        SUM(user_value) AS top_five_value
    FROM ranked_users
    WHERE user_rank <= 5
    GROUP BY merchant_id
)
SELECT
    m.merchant_id,
    m.merchant_value,
    t.top_five_value,
    ROUND(100.0 * t.top_five_value / m.merchant_value, 2) AS top_five_percentage
FROM merchant_totals AS m
JOIN top_five AS t
    ON m.merchant_id = t.merchant_id
WHERE t.top_five_value / m.merchant_value > 0.60
ORDER BY top_five_percentage DESC;

-- result: 15 rows
-- add up the top 5-> comparing with merchant total
-- =====================================================================
-- PATTERN 9 - PAYMENTS JUST BELOW LIMIT
-- Check users who made 10 or more payments of exactly 9999.00.
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS threshold_txn_count
FROM transactions
WHERE amount = 9999.00
GROUP BY user_id
HAVING COUNT(*) >= 10
ORDER BY threshold_txn_count DESC;

-- result: 20 rows
-- 10 or more from user is flagged

-- =====================================================================
-- PATTERN 10 - INACTIVE THEN ACTIVE
-- Check users who had a 90+ day gap and then made at least 15 transactions.
-- =====================================================================
WITH ordered_txns AS (
    SELECT
        user_id,
        txn_time,
        LAG(txn_time) OVER (
            PARTITION BY user_id
            ORDER BY txn_time
        ) AS previous_txn_time
    FROM transactions
),
long_gaps AS (
    SELECT
        user_id,
        txn_time AS restart_time
    FROM ordered_txns
    WHERE previous_txn_time IS NOT NULL
      AND TIMESTAMPDIFF(DAY, previous_txn_time, txn_time) >= 90
),
activity_after_gap AS (
    SELECT
        g.user_id,
        g.restart_time,
        COUNT(t.txn_id) AS post_gap_txns
    FROM long_gaps AS g
    JOIN transactions AS t
      ON t.user_id = g.user_id
     AND t.txn_time >= g.restart_time
    GROUP BY g.user_id, g.restart_time
)
SELECT
    user_id,
    restart_time,
    post_gap_txns
FROM activity_after_gap
WHERE post_gap_txns >= 15
ORDER BY post_gap_txns DESC;
 
 -- RESult: 26 rows


-- =====================================================================
-- PATTERN 11 - SUDDEN TRANSACTION SPIKE
-- Check users whose busiest month has at least 20 transactions
-- and is five or more times their monthly average.
-- =====================================================================
WITH monthly_counts AS (
    SELECT
        user_id,
        DATE_FORMAT(txn_time, '%Y-%m') AS transaction_month,
        COUNT(*) AS monthly_txn_count
    FROM transactions
    GROUP BY user_id, DATE_FORMAT(txn_time, '%Y-%m')
),
user_stats AS (
    SELECT
        user_id,
        AVG(monthly_txn_count) AS average_monthly_txns,
        MAX(monthly_txn_count) AS peak_monthly_txns
    FROM monthly_counts
    GROUP BY user_id
)
SELECT
    user_id,
    ROUND(average_monthly_txns, 2) AS average_monthly_txns,
    peak_monthly_txns,
    ROUND(peak_monthly_txns / average_monthly_txns, 2) AS peak_to_average_ratio
FROM user_stats
WHERE peak_monthly_txns >= 20
  AND peak_monthly_txns / average_monthly_txns >= 5
ORDER BY peak_to_average_ratio DESC;

-- result: 3 users (rows)
-- (switched to dividing by 6)

-- =====================================================================
-- PATTERN 12 - GEOGRAPHIC IMPOSSIBILITY(FAST CITY CHANGE)
-- Check users who made consecutive transactions in different cities
-- within 60 minutes.(ai assistance)
-- =====================================================================

WITH with_prev AS (
    SELECT
        user_id,
        txn_time,
        city,
        LAG(city)     OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_city,
        LAG(txn_time) OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_time
    FROM transactions
)
SELECT
    user_id,
    COUNT(*)      AS city_jumps,
    MIN(txn_time) AS first_jump_time
FROM with_prev
WHERE prev_city IS NOT NULL
  AND city <> prev_city
  AND TIMESTAMPDIFF(MINUTE, prev_time, txn_time) <= 60
GROUP BY user_id
ORDER BY city_jumps DESC;

-- result: 15 users (rows)
-- ex: user_id  city_jumps  first_jump_time
--       14755       8       2024-01-17 16:22:06