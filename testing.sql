-- Zapytanie demonstruje działanie funkcji monthly_card_payment.
-- Pokazuje wartość funkcji oraz liczbę kart każdego typu dla wszystkich klientów.
SELECT client_id, monthly_card_payment(client_id), NVL(debit_cards, 0) AS debit_cards, NVL(credit_cards, 0) AS credit_cards
FROM CLIENTS
LEFT JOIN (SELECT client_id, COUNT(card_id) AS debit_cards
           FROM CLIENTS
           INNER JOIN CLIENTS_ACCOUNTS USING(client_id)
           INNER JOIN ACCOUNTS USING(account_id)
           INNER JOIN CARDS USING(account_id)
           WHERE blocked = 'N' AND (SYSDATE < expiration_date OR expiration_date IS NULL) AND CARDS.type = 'D'
           GROUP BY client_id) USING(client_id)
LEFT JOIN (SELECT client_id, COUNT(card_id) AS credit_cards
           FROM CLIENTS
           INNER JOIN CLIENTS_ACCOUNTS USING(client_id)
           INNER JOIN ACCOUNTS USING(account_id)
           INNER JOIN CARDS USING(account_id)
           WHERE blocked = 'N' AND (SYSDATE < expiration_date OR expiration_date IS NULL) AND CARDS.type = 'C'
           GROUP BY client_id) USING(client_id)
ORDER BY client_id;


-- Zapytanie demonstruje działanie funkcji calculate_total_balance.
-- Pokazuje ilość pieniędzy na wszystkich kontach, pożyczkach i lokatach każdego z klientów.
SELECT client_id, 'account' AS type, currency_short_name AS currency, balance,
       calculate_total_balance(client_id)
FROM CLIENTS
INNER JOIN CLIENTS_ACCOUNTS USING(client_id)
INNER JOIN ACCOUNTS USING(account_id)
INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
UNION
SELECT client_id, 'loan' AS type, currency_short_name AS currency, -current_amount AS balance,
       calculate_total_balance(client_id)
FROM CLIENTS
INNER JOIN CLIENTS_ACCOUNTS USING(client_id)
INNER JOIN ACCOUNTS USING(account_id)
INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
INNER JOIN LOANS USING(account_currency_id)
UNION
SELECT client_id, 'investment' AS type, currency_short_name AS currency, amount AS balance,
       calculate_total_balance(client_id)
FROM CLIENTS
INNER JOIN CLIENTS_ACCOUNTS USING(client_id)
INNER JOIN ACCOUNTS USING(account_id)
INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
INNER JOIN INVESTMENTS USING(account_currency_id);


-- Poniżej jest demonstracja działania procedury take_loan.
-- Stan konta sprzed wzięcia pożyczki:
SELECT account_id, balance, currency_short_name
FROM ACCOUNT_CURRENCIES
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id = 18;

EXEC take_loan(10000, '2025-01-01', 8 / 100, 18, 'PLN');

-- Ilość pieniędzy na koncie wzrosła.
SELECT account_id, balance, currency_short_name
FROM ACCOUNT_CURRENCIES
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id = 18;
-- Pożyczka została też dodana do tabeli LOANS.
SELECT *
FROM LOANS
ORDER BY date_taken DESC FETCH NEXT 1 ROWS ONLY;
ROLLBACK;


-- Poniżej jest analogiczna demonstracja działania procedury make_investment.
-- Stan konta sprzed wzięcia lokaty:
SELECT account_id, balance, currency_short_name
FROM ACCOUNT_CURRENCIES
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id = 18;

EXEC make_investment(3000, '2024-01-01', 3 / 100, 18, 'PLN');

-- Tlość pieniędzy na koncie zmalała.
SELECT account_id, balance, currency_short_name
FROM ACCOUNT_CURRENCIES
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id = 18;
-- Lokata została też dodana do tabeli INVESTMENTS.
SELECT *
FROM INVESTMENTS
ORDER BY date_taken DESC FETCH NEXT 1 ROWS ONLY;

ROLLBACK;


-- Poniżej jest analogiczna demonstracja działania procedury make_investment.
-- Stan konta sprzed wzięcia lokaty:
SELECT account_id, balance, currency_short_name
FROM ACCOUNT_CURRENCIES
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id = 18;

EXEC make_investment(3000, '2024-01-01', 3 / 100, 18, 'PLN');

-- Poniższe zapytanie pokazuje, że ilość pieniędzy na koncie wzrosła.
SELECT account_id, balance, currency_short_name
FROM ACCOUNT_CURRENCIES
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id = 18;
-- Lokata została też dodana do tabeli INVESTMENTS.
SELECT *
FROM INVESTMENTS
ORDER BY date_taken DESC FETCH NEXT 1 ROWS ONLY;

ROLLBACK;


-- Poniżej jest demonstracja działania procedury make_inside_transaction.
-- Stany kont sprzed przelewu:
SELECT account_id, balance, currency_short_name
FROM ACCOUNT_CURRENCIES
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id IN (17, 18);

-- przelew z przewalutowaniem, z funtów na złote
EXEC make_inside_transaction(5000, 17, 18, 'GBP', 'PLN');

-- Ilości pieniędzy na kontach się zmieniły.
SELECT account_id, balance, currency_short_name
FROM ACCOUNT_CURRENCIES
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id IN (17, 18);

-- Transakcja została zaksięgowana. amount_after jest ilością pieniędzy po przewalutowaniu.
SELECT *
FROM INSIDE_TRANSACTIONS_HISTORY
ORDER BY transaction_date DESC FETCH NEXT 1 ROWS ONLY;

ROLLBACK;


-- Poniżej jest demonstracja działania procedury make_outside_transaction.
-- Stan konta sprzed przelewu:
SELECT account_id, balance, currency_short_name
FROM ACCOUNT_CURRENCIES
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id = 18;

-- amount > 0, przelew przychodzący
EXEC make_outside_transaction('PT5000002012312345678', 10000, 18, 'PLN');

-- Stan konta po przelewie się zmienił
SELECT account_id, balance, currency_short_name
FROM ACCOUNT_CURRENCIES
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id = 18;
-- Transakcja została zaksięgowana.
SELECT *
FROM OUTSIDE_TRANSACTIONS_HISTORY
ORDER BY transaction_date DESC FETCH NEXT 1 ROWS ONLY;

ROLLBACK;

-- Poniżej jest demonstracja procedury block_unpaid_accounts.
SELECT account_id, date_taken, starting_amount, current_amount
FROM ACCOUNTS
INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
INNER JOIN LOANS USING(account_currency_id)
WHERE SYSDATE - date_taken > 365 AND current_amount > 0.9 * starting_amount;
-- Do zablokowania są 2 konta - o ID 5 i 22.

EXEC block_unpaid_accounts;

-- Limity transakcji kont zostały ustawione na 0, i wszystkie ich karty zostały zablokowane.
SELECT *
FROM ACCOUNTS
WHERE account_id IN (5, 22);

SELECT *
FROM CARDS
INNER JOIN ACCOUNTS USING(account_id)
WHERE account_id IN (5, 22);

ROLLBACK;


SELECT * FROM ACCOUNTS
INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
WHERE account_currency_id = 13;

-- Demonstracja działania wyzwalaczy:
-- inside_transaction_date_trig
 -- nie przechodzi - konto wysyłające nie istniało
INSERT INTO INSIDE_TRANSACTIONS_HISTORY VALUES (NULL, 3190, 2828.87, '2007-03-09', 45, 30);
 -- nie przechodzi - konto odbierające nie istniało
INSERT INTO INSIDE_TRANSACTIONS_HISTORY VALUES (NULL, 3190, 2828.87, '2007-03-09', 30, 45);
 -- przechodzi - daty się zgadzają
INSERT INTO INSIDE_TRANSACTIONS_HISTORY VALUES (NULL, 3190, 2828.87, '2020-03-09', 30, 45);

-- outside_transaction_date_trig
 -- nie przechodzi - konto nie istniało
INSERT INTO OUTSIDE_TRANSACTIONS_HISTORY VALUES (NULL, 'IT40S0542811101000000123456', -7300, '2018-05-11', 21);
 -- przechodzi - daty się zgadzają
INSERT INTO OUTSIDE_TRANSACTIONS_HISTORY VALUES (NULL, 'IT40S0542811101000000123456', -7300, '2021-05-11', 21);

-- loan_date_trig
 -- nie przechodzi - konto nie istniało
INSERT INTO LOANS VALUES (NULL, 95000, 20000, '2018-05-05', '2026-04-02', 11.15, 48);
 -- przechodzi - daty się zgadzają
INSERT INTO LOANS VALUES (NULL, 95000, 20000, '2016-05-05', '2026-04-02', 11.15, 48);

-- investment_date_trig
 -- nie przechodzi - konto nie istniało
INSERT INTO INVESTMENTS VALUES (NULL, '2014-04-25', '2021-01-01', NULL, 5.66, 36300, 13);
 -- przechodzi - daty się zgadzają
INSERT INTO INVESTMENTS VALUES (NULL, '2016-04-25', '2021-01-01', NULL, 5.66, 36300, 13);
