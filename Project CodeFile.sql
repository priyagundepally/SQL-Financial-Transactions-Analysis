SELECT * FROM cards LIMIT 10;
SELECT * FROM users LIMIT 10;
 
SELECT * FROM mcc_lookup LIMIT 10;
 
SELECT * FROM transactions LIMIT 10;
 
--DATA cleanup
--Cleaned up json file and loaded to mcc_lookup table using python script
 
--Column 'Amount' in transactions table is of format 'VARCHAR'
--We can create a new column in the table to store the dollar amount value in 'decimal' format
 
ALTER TABLE transactions
ADD COLUMN dollar_amount_value DECIMAL(10, 2); 
 
UPDATE transactions
SET dollar_amount_value = CAST(
        REPLACE(
            REPLACE(
                REPLACE(
                    REPLACE(amount, '$', ''),
                    ',',''),                      -- Remove dollar sign
                    '(', ''),                    -- Replace '(' with '-'
                    ')', '' )                    -- Remove ')'
         AS DECIMAL(10, 2));
 
-- Card brand of Top 5 Users with highest spending
SELECT u.current_age,
u.gender, c.card_brand, c.card_on_dark_web,
c.card_type,
hsd."Spending per Card",
hsd."Total Spending"
FROM 
(SELECT t1.client_id, t1.card_id,
SUM(t1.dollar_amount_value) AS "Spending per Card",
t3."Total Spending"
FROM transactions t1
INNER JOIN 
(SELECT t2.client_id,
SUM(t2.dollar_amount_value) AS "Total Spending"
FROM transactions t2
GROUP BY t2.client_id
ORDER BY "Total Spending" DESC
LIMIT 5) t3
ON t1.client_id = t3.client_id
GROUP BY t1.client_id, t1.card_id, t3."Total Spending"
ORDER BY t3."Total Spending" DESC
) hsd 
INNER JOIN cards c ON c.id = hsd.card_id
INNER JOIN users u ON u.id = hsd.client_id


--Total Spending Analysis per card brand
SELECT 
    c.CARD_BRAND,
    SUM(CAST(t.DOLLAR_AMOUNT_VALUE AS DECIMAL)) AS total_spent,
    ROUND(
        (SUM(CAST(t.DOLLAR_AMOUNT_VALUE AS DECIMAL)) * 100.0) /
        SUM(SUM(CAST(t.DOLLAR_AMOUNT_VALUE AS DECIMAL))) OVER (), 2
    ) AS percent_spent
FROM 
    transactions t
JOIN 
    cards c ON t.CARD_ID = c.ID
GROUP BY 
    c.CARD_BRAND
ORDER BY 
    total_spent DESC;


--Spending Analysis per Category
SELECT DISTINCT
    m.DESCRIPTION AS mcc_category,
    SUM(t.dollar_amount_value) OVER (PARTITION BY t.mcc) AS TotalSpendingValue,
    (SUM(t.dollar_amount_value) OVER (PARTITION BY t.mcc) /
    SUM(t.dollar_amount_value) OVER ()) * 100 AS PercentageSpendingValue,
    COUNT(*) OVER (PARTITION BY t.mcc) AS transaction_count,
    (COUNT(*) OVER (PARTITION BY t.mcc) /
    COUNT(*) OVER ()) * 100 AS percentage_of_transactions
FROM
    transactions t
JOIN
    mcc_lookup m ON t.mcc = m.mcc_id
ORDER BY
    TotalSpendingValue DESC
LIMIT 10;


--Total Spending Analysis per State
SELECT DISTINCT
    t.MERCHANT_STATE,
    SUM(t.DOLLAR_AMOUNT_VALUE) OVER (PARTITION BY t.MERCHANT_STATE) AS total_spent,
    COUNT(*) OVER (PARTITION BY t.MERCHANT_STATE) AS transaction_count,
    ((SUM(t.DOLLAR_AMOUNT_VALUE) OVER (PARTITION BY t.MERCHANT_STATE)) /
    SUM(t.DOLLAR_AMOUNT_VALUE) OVER ()) * 100 AS "% of total spending",
    (COUNT(*) OVER (PARTITION BY t.MERCHANT_STATE) /
    COUNT(*) OVER ()) * 100 AS "% of transactions"
FROM
    transactions t
ORDER BY
    total_spent DESC;


--Transaction Error Analysis
WITH TRANSACTIONS_SUMMARY AS (
    SELECT
        c.card_brand AS brand,
        COUNT(*) AS TotalTransactions,
        SUM(CASE WHEN UPPER(t.errors) LIKE 'TECHNICAL%' THEN 1 ELSE 0 END) AS TechnicalErrorTransactions
    FROM transactions t
    INNER JOIN cards c ON c.id = t.card_id
    GROUP BY c.card_brand
)
SELECT
    brand,
    ROUND((TechnicalErrorTransactions * 100.0) / SUM(TechnicalErrorTransactions) OVER (), 2) AS "% of Total Technical Errors",
    ROUND((TechnicalErrorTransactions * 100.0) / TotalTransactions, 2) AS "% of Total Transactions Per Brand"
FROM
    TRANSACTIONS_SUMMARY
ORDER BY
    "% of Total Technical Errors" DESC;


--Transaction Error and User Behavior Analysis
WITH MAXED_OUT_TRANSACTIONS_SUMMARY AS (
    SELECT
        CASE
            WHEN u.credit_score BETWEEN 300 AND 579 THEN 'Poor'
            WHEN u.credit_score BETWEEN 580 AND 669 THEN 'Fair'
            WHEN u.credit_score BETWEEN 670 AND 739 THEN 'Good'
            WHEN u.credit_score BETWEEN 740 AND 799 THEN 'Very Good'
            WHEN u.credit_score BETWEEN 800 AND 850 THEN 'Exceptional'
            ELSE 'Unknown'
        END AS credit_score_range,
        COUNT(*) AS TotalTransactions,
        SUM(CASE WHEN t.errors LIKE '%INSUFFICIENT%' OR t.errors LIKE 'INSUFFICIENT%' THEN 1 ELSE 0 END) AS MaxedOutErrors
    FROM
        transactions t
    INNER JOIN users u ON u.id = t.client_id
    GROUP BY
        CASE
            WHEN u.credit_score BETWEEN 300 AND 579 THEN 'Poor'
            WHEN u.credit_score BETWEEN 580 AND 669 THEN 'Fair'
            WHEN u.credit_score BETWEEN 670 AND 739 THEN 'Good'
            WHEN u.credit_score BETWEEN 740 AND 799 THEN 'Very Good'
            WHEN u.credit_score BETWEEN 800 AND 850 THEN 'Exceptional'
            ELSE 'Unknown'
        END
)
SELECT
    credit_score_range,
    ROUND((MaxedOutErrors * 100.0) / TotalTransactions, 2) AS "Maxed Out Errors/Total Transaction(%)",
    ROUND((MaxedOutErrors * 100.0) / SUM(MaxedOutErrors) OVER (), 2) AS "% share of Total Maxed Out Errors"
FROM
    MAXED_OUT_TRANSACTIONS_SUMMARY
ORDER BY
    "Maxed Out Errors/Total Transaction(%)" DESC;

--For altering and updating the users table
ALTER TABLE Users
MODIFY COLUMN credit_score_range VARCHAR(20);

UPDATE Users
SET credit_score_range = CASE
    WHEN credit_score BETWEEN 300 AND 579 THEN 'Poor'
    WHEN credit_score BETWEEN 580 AND 669 THEN 'Fair'
    WHEN credit_score BETWEEN 670 AND 739 THEN 'Good'
    WHEN credit_score BETWEEN 740 AND 799 THEN 'Very Good'
    WHEN credit_score BETWEEN 800 AND 850 THEN 'Exceptional'
    ELSE 'Unknown'
END;


--Financial Stability Index For States(1/2)
-- Step 1: Assign user home state
WITH USER_HOME_STATE AS (
    SELECT 
        t.client_id AS user_id,
        t.merchant_state,
        COUNT(*) AS transaction_count,
        RANK() OVER (PARTITION BY t.client_id ORDER BY COUNT(*) DESC) AS rank_by_state
    FROM 
        transactions t
    GROUP BY 
        t.client_id, t.merchant_state
),
HOME_STATE_ASSIGNED AS (
    SELECT 
        user_id, 
        merchant_state AS home_state
    FROM 
        USER_HOME_STATE
    WHERE 
        rank_by_state = 1
),
-- Step 2: Combine Home State with Financial Metrics
USER_METRICS AS (
    SELECT 
        u.id AS user_id,
        hs.home_state,
        u.total_debt_value,
        u.yearly_income_value,
        SUM(CASE WHEN t.card_id IS NOT NULL THEN t.dollar_amount_value END) / SUM(c.credit_limit_value) AS credit_utilization,
        COUNT(CASE WHEN t.errors LIKE 'INSUFFICIENT%' OR t.errors LIKE '%INSUFFICIENT%' THEN 1 ELSE NULL END) AS maxed_out_errors
    FROM 
        users u
    LEFT JOIN 
        HOME_STATE_ASSIGNED hs ON u.id = hs.user_id
    LEFT JOIN 
        transactions t ON t.client_id = u.id
    LEFT JOIN 
        cards c ON t.card_id = c.id
    WHERE 
        u.yearly_income_value > 0 AND c.credit_limit_value > 0
    GROUP BY 
        u.id, hs.home_state, u.total_debt_value, u.yearly_income_value
)


--Financial Stability Index For States(2/2)
SELECT 
    home_state,
    ROUND(AVG((total_debt_value / yearly_income_value) * 100), 2) AS avg_debt_ratio,
    ROUND(AVG(credit_utilization * 100), 2) AS avg_credit_util,
    SUM(maxed_out_errors) AS total_maxed_out_errors,
    ROUND(
        (
            AVG((total_debt_value / yearly_income_value) * 100) * 0.45 +
            AVG(credit_utilization * 100) * 0.45 +
            SUM(maxed_out_errors) * 0.1 / COUNT(*)
        ), 
        2
    ) AS financial_stress_index
FROM 
    USER_METRICS
GROUP BY 
    home_state
ORDER BY 
    financial_stress_index DESC;