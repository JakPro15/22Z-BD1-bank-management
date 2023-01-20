-- Funkcja oblicza miesiêczn¹ op³atê za karty p³atnicze dla danego klienta.
CREATE OR REPLACE FUNCTION monthly_card_payment(p_client_id NUMBER)
RETURN NUMERIC
AS
    c_debit_card_payment NUMERIC(12, 2) := 5.0;
    c_credit_card_payment NUMERIC(12, 2) := 10.0;
    v_debit_cards_amount NUMBER;
    v_credit_cards_amount NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO v_debit_cards_amount
    FROM CLIENTS
    LEFT JOIN ACCOUNTS USING(client_id)
    LEFT JOIN CARDS c USING(account_id)
    WHERE client_id = p_client_id AND c.type = 'D' AND
          (c.expiration_date > SYSDATE OR c.expiration_date IS NULL)
          AND c.blocked = 'N';
    
    SELECT COUNT(*)
    INTO v_credit_cards_amount
    FROM CLIENTS
    LEFT JOIN ACCOUNTS USING(client_id)
    LEFT JOIN CARDS c USING(account_id)
    WHERE client_id = p_client_id AND c.type = 'C' AND
          (c.expiration_date > SYSDATE OR c.expiration_date IS NULL)
          AND c.blocked = 'N';
    
    RETURN v_debit_cards_amount * c_debit_card_payment + v_credit_cards_amount * c_credit_card_payment;
END;
/

SELECT client_id, monthly_card_payment(client_id)
FROM CLIENTS;


-- Funkcja oblicza ogólny balans w PLN wszystkich kont klienta, wliczaj¹c po¿yczki i lokaty.
CREATE OR REPLACE FUNCTION calculate_total_balance(p_client_id NUMBER)
RETURN NUMERIC
AS
    v_total_balance NUMERIC(12, 2);
    v_total_investments NUMERIC(12, 2);
    v_total_loans NUMERIC(12, 2);
BEGIN
    SELECT SUM(ac.balance * c.exchange_rate_to_pln)
    INTO v_total_balance
    FROM ACCOUNT_CURRENCIES ac
    INNER JOIN CURRENCIES c ON c.short_name = ac.currency_short_name
    INNER JOIN ACCOUNTS a USING(account_id)
    WHERE a.client_id = p_client_id;
    
    IF v_total_balance IS NULL
    THEN
        v_total_balance := 0;
    END IF;

    SELECT SUM(i.amount * c.exchange_rate_to_pln)
    INTO v_total_investments
    FROM INVESTMENTS i
    INNER JOIN ACCOUNT_CURRENCIES ac USING(account_currency_id)
    INNER JOIN CURRENCIES c ON c.short_name = ac.currency_short_name
    INNER JOIN ACCOUNTS a USING(account_id)
    WHERE a.client_id = p_client_id;
    
    IF v_total_investments IS NULL
    THEN
        v_total_investments := 0;
    END IF;

    SELECT SUM(l.current_amount * c.exchange_rate_to_pln)
    INTO v_total_loans
    FROM LOANS l
    INNER JOIN ACCOUNT_CURRENCIES ac USING(account_currency_id)
    INNER JOIN CURRENCIES c ON c.short_name = ac.currency_short_name
    INNER JOIN ACCOUNTS a USING(account_id)
    WHERE a.client_id = p_client_id;
    
    IF v_total_loans IS NULL
    THEN
        v_total_loans := 0;
    END IF;
    
    RETURN v_total_balance + v_total_investments - v_total_loans;
END;
/

SELECT client_id, calculate_total_balance(client_id)
FROM CLIENTS;


SELECT outside_transaction_id, transaction_date, creation_date, closing_date,
       CASE WHEN(transaction_date < creation_date OR transaction_date > closing_date) THEN 1 ELSE 0 END AS invalid
FROM OUTSIDE_TRANSACTIONS_HISTORY
INNER JOIN ACCOUNT_CURRENCIES ON account_currency_id = inside_account_currency_id
INNER JOIN ACCOUNTS USING(account_id)
ORDER BY outside_transactions_history.outside_transaction_id;


--procedura odpowiedzialna za wziêcie po¿yczki i dodania pieniêdzy do konta
CREATE OR REPLACE PROCEDURE take_loan (v_starting_amount NUMBER, v_date_due DATE, 
    v_yearly_interest_rate NUMBER, v_account_currency_id NUMBER)
AS
BEGIN
    UPDATE ACCOUNT_CURRENCIES
    SET balance = balance + v_starting_amount
    WHERE account_currency_id = v_account_currency_id;

    INSERT INTO LOANS VALUES (NULL, v_starting_amount, v_starting_amount, SYSDATE, 
        v_date_due, v_yearly_interest_rate, v_account_currency_id);
    
END;
/


--procedura odpowiedzialna za za³o¿enie lokaty i pobrania pieniedzy z konta
CREATE OR REPLACE PROCEDURE make_investment (v_blocked_until DATE, v_yearly_interest_rate NUMBER,
    v_amount NUMBER, v_account_currency_id NUMBER)
AS
    v_current_balance NUMBER;
BEGIN
    SELECT balance INTO v_current_balance 
    FROM ACCOUNT_CURRENCIES 
    WHERE account_currency_id = v_account_currency_id;
    
    IF v_current_balance - v_amount >= 0
    THEN
        UPDATE ACCOUNT_CURRENCIES
        SET balance = balance - v_amount
        WHERE account_currency_id = v_account_currency_id;
        
        INSERT INTO INVESTMENTS VALUES (NULL, SYSDATE, NULL, v_blocked_until, 
            v_yearly_interest_rate, v_amount, v_account_currency_id); 
    END IF;
END;
/


--procedura odpowiedzialna za robienie przelewów wewnêtrznych
CREATE OR REPLACE PROCEDURE make_inside_transaction (v_amount NUMBER, v_acc_from_id NUMBER, v_acc_to_id NUMBER)
AS
    v_current_sender_balance NUMBER;
    v_sender_currency_rate NUMBER;
    v_receiver_currency_rate NUMBER;
    v_amount_after_convert NUMBER;
BEGIN
    SELECT balance INTO v_current_sender_balance 
    FROM ACCOUNT_CURRENCIES 
    WHERE account_currency_id = v_acc_from_id;
    
    IF v_current_sender_balance - v_amount >= 0
    THEN
        SELECT c.exchange_rate_to_pln INTO v_sender_currency_rate
        FROM CURRENCIES c JOIN ACCOUNT_CURRENCIES ac ON c.short_name = ac.currency_short_name
        WHERE ac.account_currency_id = v_acc_from_id;
        
        SELECT c.exchange_rate_to_pln INTO v_receiver_currency_rate
        FROM CURRENCIES c JOIN ACCOUNT_CURRENCIES ac ON c.short_name = ac.currency_short_name
        WHERE ac.account_currency_id = v_acc_to_id;
        
        v_amount_after_convert := v_current_sender_balance / v_sender_currency_rate * v_receiver_currency_rate;
    
        UPDATE ACCOUNT_CURRENCIES
        SET balance = balance - v_amount
        WHERE account_currency_id = v_acc_from_id;
        
        INSERT INTO INSIDE_TRANSACTIONS_HISTORY VALUES (NULL, v_amount, 
            v_amount_after_convert, SYSDATE, v_acc_from_id, v_acc_to_id);
        
        UPDATE ACCOUNT_CURRENCIES
        SET balance = balance + v_amount_after_convert
        WHERE account_currency_id = v_acc_to_id;
    END IF;
END;
/


--procedura odpowiedzialna za wykonywanie przelewu "na zewnatrz" (do innego banku)
CREATE OR REPLACE PROCEDURE make_outside_transaction (v_outside_acc_number NUMBER, 
    v_amount NUMBER, v_inside_currency_id NUMBER)
AS
    v_current_sender_balance NUMBER;
BEGIN
    SELECT balance INTO v_current_sender_balance 
    FROM ACCOUNT_CURRENCIES 
    WHERE account_currency_id = v_inside_currency_id;
    
    IF v_current_sender_balance + v_amount >= 0
    THEN
        UPDATE ACCOUNT_CURRENCIES
        SET balance = balance + v_amount
        WHERE account_currency_id = v_inside_currency_id;
    
        INSERT INTO OUTSIDE_TRANSACTIONS_HISTORY VALUES (NULL, v_outside_acc_number, 
            v_amount, SYSDATE, v_inside_currency_id);
    END IF;
END;
/


--procedura, która zamyka konto klienta,jesli klient przez rok nie sp³aci³ wiêcej 10% swojej po¿yczki
CREATE OR REPLACE PROCEDURE close_unpaid_accounts
AS
    v_loan_paid NUMBER;
    v_time_passed NUMBER;
    CURSOR cr is SELECT * FROM LOANS;
    v_rec_loans LOANS%ROWTYPE;
BEGIN

    OPEN cr;
    LOOP
        EXIT WHEN cr%NOTFOUND;
        FETCH cr INTO v_rec_loans;
        
        v_loan_paid := v_rec_loans.starting_amount - v_rec_loans.current_amount;
        v_time_passed := SYSDATE - v_rec_loans.date_taken;
        
        IF v_time_passed > 365 AND v_loan_paid <= 0.1 * v_rec_loans.starting_amount
        THEN
            UPDATE ACCOUNTS
            SET closing_date = SYSDATE
            WHERE account_id in (SELECT a.account_id 
                FROM ACCOUNTS a 
                JOIN ACCOUNT_CURRENCIES ac ON a.account_id = ac.account_id
                JOIN LOANS l ON ac.account_currency_id = l.account_currency_id
                WHERE l.loan_id = v_rec_loans.loan_id);
        END IF;
    END LOOP;
    CLOSE cr;

END;
/


--wyzwalacz, który sprawdza, czy osoba zak³adaj¹ca konto ukoñczy³a 18 lat


