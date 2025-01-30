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