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
    LEFT JOIN CLIENTS_ACCOUNTS USING(client_id)
    LEFT JOIN ACCOUNTS USING(account_id)
    LEFT JOIN CARDS c USING(account_id)
    WHERE client_id = p_client_id AND c.type = 'D' AND
          (c.expiration_date > SYSDATE OR c.expiration_date IS NULL)
          AND c.blocked = 'N';
    
    SELECT COUNT(*)
    INTO v_credit_cards_amount
    FROM CLIENTS
    LEFT JOIN CLIENTS_ACCOUNTS USING(client_id)
    LEFT JOIN ACCOUNTS USING(account_id)
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
    INNER JOIN CLIENTS_ACCOUNTS ca USING(account_id)
    WHERE ca.client_id = p_client_id;
    
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
    INNER JOIN CLIENTS_ACCOUNTS ca USING(account_id)
    WHERE ca.client_id = p_client_id;
    
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
    INNER JOIN CLIENTS_ACCOUNTS ca USING(account_id)
    WHERE ca.client_id = p_client_id;
    
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


-- Procedura rejestruje wziêcie po¿yczki przez podane konto i dodaje pieni¹dze do konta
CREATE OR REPLACE PROCEDURE take_loan(p_starting_amount NUMERIC, p_date_due DATE, 
                                      p_yearly_interest_rate NUMERIC, p_account_id NUMBER,
                                      p_currency_short_name CHAR)
AS
    v_account_currency_id NUMBER;
BEGIN
    SELECT account_currency_id
    INTO v_account_currency_id
    FROM ACCOUNT_CURRENCIES
    WHERE account_id = p_account_id AND currency_short_name = p_currency_short_name;

    UPDATE ACCOUNT_CURRENCIES
    SET balance = balance + p_starting_amount
    WHERE account_currency_id = v_account_currency_id;

    INSERT INTO LOANS VALUES (
        NULL, p_starting_amount, p_starting_amount, SYSDATE, p_date_due,
        p_yearly_interest_rate, v_account_currency_id
    );
    NULL;
EXCEPTION
    WHEN no_data_found THEN
        dbms_output.put_line('This account does not have this currency. Please add the account currency first.');
        RAISE;
END;
/

SELECT * FROM ACCOUNTS WHERE account_id = 11;
SELECT * FROM ACCOUNT_CURRENCIES WHERE account_id = 11;
SELECT * FROM LOANS ORDER BY loan_id DESC FETCH NEXT 1 ROWS ONLY;
EXEC take_loan(100000, '2025-01-01', 5 / 100, 11, 'GBP');
ROLLBACK;


-- Procedura rejestruje za³o¿enie lokaty przez podane konto i odejmuje pieni¹dze z konta.
CREATE OR REPLACE PROCEDURE make_investment(p_amount NUMERIC, p_blocked_until DATE, 
                                            p_yearly_interest_rate NUMERIC, p_account_id NUMBER,
                                            p_currency_short_name CHAR)
AS
    v_account_currency_id NUMBER;
    v_current_balance NUMBER;
BEGIN
    SELECT account_currency_id, balance
    INTO v_account_currency_id, v_current_balance 
    FROM ACCOUNT_CURRENCIES
    WHERE account_id = p_account_id AND currency_short_name = p_currency_short_name;

    IF v_current_balance >= p_amount
    THEN
        UPDATE ACCOUNT_CURRENCIES
        SET balance = balance - p_amount
        WHERE account_currency_id = v_account_currency_id;
        
        INSERT INTO INVESTMENTS VALUES (
            NULL, SYSDATE, NULL, p_blocked_until, p_yearly_interest_rate,
            p_amount, v_account_currency_id
        );
    ELSE
        RAISE_APPLICATION_ERROR(-20001, 'Tego konta nie staæ na za³o¿enie takiej lokaty!');
    END IF;
EXCEPTION
    WHEN no_data_found THEN
        dbms_output.put_line('This account does not have this currency. Please add the account currency first.');
        RAISE;
END;
/


-- Procedura rejestruje przelew wewnêtrzny. Dodaje/odejmuje pieni¹dze zgodnie z obecnym kursem walut.
CREATE OR REPLACE PROCEDURE make_inside_transaction(p_amount NUMERIC, p_account_from_id NUMBER,
                                                    p_account_to_id NUMBER, p_currency_sent CHAR,
                                                    p_currency_received CHAR)
AS
    v_account_currency_from_id NUMBER;
    v_account_currency_to_id NUMBER;
    v_current_sender_balance NUMERIC(12, 2);
    v_sender_currency_rate NUMERIC(12, 2);
    v_receiver_currency_rate NUMERIC(12, 2);
    v_amount_after_convert NUMERIC(12, 2);
    v_sender_limit NUMERIC(12, 2);
BEGIN
    SELECT transaction_limit
    INTO v_sender_limit
    FROM ACCOUNTS
    WHERE account_id = p_account_from_id;
    
    SELECT exchange_rate_to_pln
    INTO v_sender_currency_rate
    FROM CURRENCIES
    WHERE short_name = p_currency_sent;
    
    IF v_sender_limit < p_amount * v_sender_currency_rate
    THEN
        RAISE_APPLICATION_ERROR(-20001, 'Konto wysy³aj¹ce nie mo¿e wys³aæ takiego przelewu!');
    END IF;

    SELECT account_currency_id, balance
    INTO v_account_currency_from_id, v_current_sender_balance 
    FROM ACCOUNT_CURRENCIES
    WHERE account_id = p_account_from_id AND currency_short_name = p_currency_sent;
    
    SELECT account_currency_id
    INTO v_account_currency_to_id
    FROM ACCOUNT_CURRENCIES
    WHERE account_id = p_account_to_id AND currency_short_name = p_currency_received;
    
    IF v_current_sender_balance >= p_amount
    THEN        
        SELECT exchange_rate_to_pln
        INTO v_receiver_currency_rate
        FROM CURRENCIES
        WHERE short_name = p_currency_received;
        
        v_amount_after_convert := p_amount * v_sender_currency_rate / v_receiver_currency_rate;
    
        UPDATE ACCOUNT_CURRENCIES
        SET balance = balance - p_amount
        WHERE account_currency_id = v_account_currency_from_id;
        
        INSERT INTO INSIDE_TRANSACTIONS_HISTORY VALUES (
            NULL, p_amount, v_amount_after_convert, SYSDATE,
            v_account_currency_from_id, v_account_currency_to_id
        );
        
        UPDATE ACCOUNT_CURRENCIES
        SET balance = balance + v_amount_after_convert
        WHERE account_currency_id = v_account_currency_to_id;
    ELSE
        RAISE_APPLICATION_ERROR(-20001, 'Konta wysy³aj¹cego nie staæ na wykonanie takiego przelewu!');
    END IF;
END;
/

SELECT * FROM ACCOUNT_CURRENCIES WHERE account_id IN (11, 17);
SELECT * FROM INSIDE_TRANSACTIONS_HISTORY ORDER BY inside_transaction_id DESC FETCH NEXT 4 ROWS ONLY;
EXEC make_inside_transaction(100, 17, 11, 'GBP', 'PLN');
ROLLBACK;



-- Procedura rejestruje przelew zewnêtrzny (wychodz¹cy do lub przychodz¹cy z innego banku)
-- i dodaje/odejmuje odpowiedni¹ iloœæ pieniêdzy.
CREATE OR REPLACE PROCEDURE make_outside_transaction(p_outside_account_number VARCHAR2, 
                                                     p_amount NUMBER, p_account_id NUMBER,
                                                     p_currency_short_name CHAR)
AS
    v_account_currency_id NUMBER;
    v_current_sender_balance NUMERIC(12, 2);
    v_inside_account_limit NUMERIC(12, 2);
BEGIN
    SELECT account_currency_id, balance
    INTO v_account_currency_id, v_current_sender_balance 
    FROM ACCOUNT_CURRENCIES
    WHERE account_id = p_account_id AND currency_short_name = p_currency_short_name;
    
    SELECT transaction_limit
    INTO v_inside_account_limit
    FROM ACCOUNTS
    WHERE account_id = p_account_id;
    
    IF -p_amount > v_inside_account_limit
    THEN
        RAISE_APPLICATION_ERROR(-20001, 'Wewnêtrzne konto nie mo¿e wykonaæ takiego przelewu!');
    END IF;
    
    IF v_current_sender_balance + p_amount >= 0
    THEN
        UPDATE ACCOUNT_CURRENCIES
        SET balance = balance + p_amount
        WHERE account_currency_id = v_account_currency_id;
    
        INSERT INTO OUTSIDE_TRANSACTIONS_HISTORY VALUES (
            NULL, p_outside_account_number, p_amount, SYSDATE, v_account_currency_id
        );
    ELSE
        RAISE_APPLICATION_ERROR(-20001, 'Wewnêtrznego konta nie staæ na wykonanie takiego przelewu!');
    END IF;
END;
/

SELECT * FROM ACCOUNT_CURRENCIES WHERE account_id = 11;
SELECT * FROM OUTSIDE_TRANSACTIONS_HISTORY ORDER BY outside_transaction_id DESC FETCH NEXT 4 ROWS ONLY;
EXEC make_outside_transaction('abbc', -1000, 11, 'PLN');
ROLLBACK;


-- Procedura blokuje wszystkie konta, które przez rok nie sp³aci³y 10% wziêtej po¿yczki.
-- Zablokowanie konta oznacza ustawienie jego limitu transakcji na 0 i zablokowanie wszystkich jego kart.
CREATE OR REPLACE PROCEDURE block_unpaid_accounts
AS
    v_loan_paid NUMBER;
    v_time_passed NUMBER;
    CURSOR cr is SELECT * FROM LOANS;
    v_rec_loans LOANS%ROWTYPE;
    v_account_to_block_id NUMBER;
BEGIN
    OPEN cr;
    LOOP
        EXIT WHEN cr%NOTFOUND;
        FETCH cr INTO v_rec_loans;
        
        v_loan_paid := v_rec_loans.starting_amount - v_rec_loans.current_amount;
        v_time_passed := SYSDATE - v_rec_loans.date_taken;
        
        IF v_time_passed > 365 AND v_loan_paid < 0.1 * v_rec_loans.starting_amount
        THEN
            SELECT account_id
            INTO v_account_to_block_id
            FROM ACCOUNTS a 
            INNER JOIN ACCOUNT_CURRENCIES ac USING(account_id)
            INNER JOIN LOANS l USING(account_currency_id)
            WHERE l.loan_id = v_rec_loans.loan_id;
            
            UPDATE ACCOUNTS
            SET transaction_limit = 0
            WHERE account_id = v_account_to_block_id;
            
            UPDATE CARDS
            SET blocked = 'Y'
            WHERE account_id = v_account_to_block_id;
            
            dbms_output.put_line('Blocked account ' || v_account_to_block_id);
        END IF;
    END LOOP;
    CLOSE cr;
END;
/

EXEC block_unpaid_accounts;
SELECT * FROM ACCOUNTS WHERE account_id = 5;
SELECT * FROM CARDS WHERE account_id = 5;
SELECT * FROM LOANS WHERE account_currency_id IN (SELECT account_currency_id FROM ACCOUNT_CURRENCIES WHERE account_id = 5);

--wyzwalacz, który sprawdza, czy osoba zak³adaj¹ca konto ukoñczy³a 18 lat


