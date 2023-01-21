SELECT client_id, monthly_card_payment(client_id)
FROM CLIENTS;


SELECT client_id, calculate_total_balance(client_id)
FROM CLIENTS;


SELECT inside_transaction_id, transaction_date, creation_date, closing_date,
       CASE WHEN(transaction_date < creation_date OR transaction_date > closing_date) THEN 1 ELSE 0 END AS invalid
FROM INSIDE_TRANSACTIONS_HISTORY
INNER JOIN ACCOUNT_CURRENCIES ON account_currency_id = account_currency_from_id
INNER JOIN ACCOUNTS USING(account_id)
ORDER BY inside_transactions_history.inside_transaction_id;


SELECT outside_transaction_id, transaction_date, creation_date, closing_date,
       CASE WHEN(transaction_date < creation_date OR transaction_date > closing_date) THEN 1 ELSE 0 END AS invalid
FROM OUTSIDE_TRANSACTIONS_HISTORY
INNER JOIN ACCOUNT_CURRENCIES ON account_currency_id = inside_account_currency_id
INNER JOIN ACCOUNTS USING(account_id)
ORDER BY outside_transactions_history.outside_transaction_id;


SELECT loan_id, date_taken, creation_date, closing_date,
       CASE WHEN(date_taken < creation_date OR date_taken > closing_date) THEN 1 ELSE 0 END AS invalid
FROM LOANS
LEFT JOIN ACCOUNT_CURRENCIES USING (account_currency_id)
LEFT JOIN ACCOUNTS USING(account_id)
ORDER BY loan_id;


SELECT * FROM ACCOUNTS WHERE account_id = 11;
SELECT * FROM ACCOUNT_CURRENCIES WHERE account_id = 11;
SELECT * FROM LOANS ORDER BY loan_id DESC FETCH NEXT 1 ROWS ONLY;
EXEC take_loan(100000, '2025-01-01', 5 / 100, 11, 'GBP');
ROLLBACK;


SELECT * FROM ACCOUNT_CURRENCIES WHERE account_id IN (11, 17);
SELECT * FROM INSIDE_TRANSACTIONS_HISTORY ORDER BY inside_transaction_id DESC FETCH NEXT 4 ROWS ONLY;
EXEC make_inside_transaction(100, 17, 11, 'GBP', 'PLN');
ROLLBACK;


SELECT * FROM ACCOUNT_CURRENCIES WHERE account_id = 11;
SELECT * FROM OUTSIDE_TRANSACTIONS_HISTORY ORDER BY outside_transaction_id DESC FETCH NEXT 4 ROWS ONLY;
EXEC make_outside_transaction('abbc', -1000, 11, 'PLN');
ROLLBACK;


EXEC block_unpaid_accounts;
SELECT * FROM ACCOUNTS WHERE account_id = 5;
SELECT * FROM CARDS WHERE account_id = 5;
SELECT * FROM LOANS WHERE account_currency_id IN (SELECT account_currency_id FROM ACCOUNT_CURRENCIES WHERE account_id = 5);