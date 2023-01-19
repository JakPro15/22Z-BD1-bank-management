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
    v_current_balance INTEGER;
BEGIN
    SELECT balance INTO v_current_balance FROM ACCOUNT_CURRENCIES WHERE account_currency_id = v_account_currency_id;

    UPDATE ACCOUNT_CURRENCIES
    SET balance = v_current_balance + v_starting_amount
    WHERE account_currency_id = v_account_currency_id;

    INSERT INTO LOANS VALUES (NULL, v_starting_amount, v_starting_amount, SYSDATE, v_date_due, 
        v_yearly_interest_rate, v_account_currency_id);
    
END;
/

--procedura odpowiedzialna za za³o¿enie lokaty i pobrania pieniedzy z konta
CREATE OR REPLACE PROCEDURE make_investment (v_blocked_until DATE, v_yearly_interest_rate NUMBER,
    v_amount NUMBER, v_account_currency_id NUMBER)
AS
    v_current_balance INTEGER;
BEGIN
    SELECT balance INTO v_current_balance FROM ACCOUNT_CURRENCIES WHERE account_currency_id = v_account_currency_id;
    
    IF v_current_balance - v_amount > 0
    THEN
        UPDATE ACCOUNT_CURRENCIES
        SET balance = v_current_balance - v_amount
        WHERE account_currency_id = v_account_currency_id;
        
        INSERT INTO INVESTMENTS VALUES (NULL, SYSDATE, NULL, v_blocked_until, v_yearly_interest_rate,
            v_amount, v_account_currency_id); 
    END IF;
END;
/


--procedura, która ustawia datê zamkniêcia konta klienta na miesi¹c do przodu,
--jesli klient przez rok nie sp³aci³ wiêcej 10% swojej po¿yczki


--funkcja, która dla podanej waluty zrobi jej "bilans" u¿ycia
--suma w po¿yczkach, suma w inwestycjach, suma w przelewach wewn. i zewn.
--mo¿na po czymœ pogrupowaæ jeszcze


--funkcja zwi¹zana z obliczaniem czegoœ w kredytach i/lub po¿yczkach


--procedura przydzielaj¹ca bonusy finansowe top 3 najaktywniejszym klientom









