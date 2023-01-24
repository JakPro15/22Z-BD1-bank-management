-- Funkcja oblicza miesięczną opłatę za karty płatnicze dla danego klienta.
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

-- Funkcja oblicza ogólny balans w PLN wszystkich kont klienta, wliczając pożyczki i lokaty.
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

-- Procedura rejestruje wzięcie pożyczki przez podane konto i dodaje pieniądze do konta
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
        dbms_output.put_line('To konto nie ma tej waluty. Należy najpierw dodać tę walutę do tego konta.');
        RAISE;
END;
/

-- Procedura rejestruje założenie lokaty przez podane konto i odejmuje pieniądze z konta.
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
        RAISE_APPLICATION_ERROR(-20001, 'Tego konta nie stać na założenie takiej lokaty!');
    END IF;
EXCEPTION
    WHEN no_data_found THEN
        dbms_output.put_line('To konto nie ma tej waluty. Należy najpierw dodać tę walutę do tego konta.');
        RAISE;
END;
/

-- Procedura rejestruje przelew wewnętrzny. Dodaje/odejmuje pieniądze zgodnie z obecnym kursem walut.
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
        RAISE_APPLICATION_ERROR(-20001, 'Konto wysyłające nie może wysłać takiego przelewu!');
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
        RAISE_APPLICATION_ERROR(-20001, 'Konta wysyłającego nie stać na wykonanie takiego przelewu!');
    END IF;
EXCEPTION
    WHEN no_data_found THEN
        dbms_output.put_line('Dodanie transakcji wewnętrznej się nie powiodło. Należy zweryfikować, czy konta istnieją i mają takie waluty.');
        RAISE;
END;
/

-- Procedura rejestruje przelew zewnętrzny (wychodzący do lub przychodzący z innego banku)
-- i dodaje/odejmuje odpowiednią ilość pieniędzy.
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
        RAISE_APPLICATION_ERROR(-20001, 'Wewnętrzne konto nie może wykonać takiego przelewu!');
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
        RAISE_APPLICATION_ERROR(-20001, 'Wewnętrznego konta nie stać na wykonanie takiego przelewu!');
    END IF;
EXCEPTION
    WHEN no_data_found THEN
        dbms_output.put_line('Dodanie transakcji wewnętrznej się nie powiodło. Należy zweryfikować, czy konta istnieją i mają takie waluty.');
        RAISE;
END;
/

-- Procedura blokuje wszystkie konta, które przez rok nie spłaciły 10% wziętej pożyczki.
-- Zablokowanie konta oznacza ustawienie jego limitu transakcji na 0 i zablokowanie wszystkich jego kart.
CREATE OR REPLACE PROCEDURE block_unpaid_accounts
AS
    v_loan_paid NUMBER;
    v_time_passed NUMBER;
    CURSOR cr is SELECT * FROM LOANS;
    v_loan LOANS%ROWTYPE;
    v_account_to_block_id NUMBER;
BEGIN
    OPEN cr;
    LOOP
        EXIT WHEN cr%NOTFOUND;
        FETCH cr INTO v_loan;

        v_loan_paid := v_loan.starting_amount - v_loan.current_amount;
        v_time_passed := SYSDATE - v_loan.date_taken;

        IF v_time_passed > 365 AND v_loan_paid < 0.1 * v_loan.starting_amount
        THEN
            SELECT account_id
            INTO v_account_to_block_id
            FROM ACCOUNTS a
            INNER JOIN ACCOUNT_CURRENCIES ac USING(account_id)
            WHERE ac.account_currency_id = v_loan.account_currency_id;

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

-- Wyzwalacz weryfikuje, czy data wpisywanej transakcji wewnętrznej jest między założeniem a zamknięciem uczestniczących kont.
CREATE OR REPLACE TRIGGER inside_transaction_date_trig
BEFORE INSERT OR UPDATE OF transaction_date ON INSIDE_TRANSACTIONS_HISTORY
FOR EACH ROW
WHEN (new.transaction_date IS NOT NULL)
DECLARE
    v_creation_date_1 DATE;
    v_closing_date_1 DATE;
    v_creation_date_2 DATE;
    v_closing_date_2 DATE;
BEGIN
    SELECT creation_date, closing_date
    INTO v_creation_date_1, v_closing_date_1
    FROM ACCOUNTS
    INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
    WHERE account_currency_id = :new.account_currency_from_id;

    IF :new.transaction_date < v_creation_date_1 OR :new.transaction_date > v_closing_date_1
    THEN
        RAISE_APPLICATION_ERROR(-20001, 'Konto wysyłające przelew nie istniało w momencie transakcji!');
    END IF;

    SELECT creation_date, closing_date
    INTO v_creation_date_2, v_closing_date_2
    FROM ACCOUNTS
    INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
    WHERE account_currency_id = :new.account_currency_to_id;

    IF :new.transaction_date < v_creation_date_2 OR :new.transaction_date > v_closing_date_2
    THEN
        RAISE_APPLICATION_ERROR(-20001, 'Konto odbierające przelew nie istniało w momencie transakcji!');
    END IF;
END;
/

-- Wyzwalacz weryfikuje, czy data wpisywanej transakcji zewnętrznej jest między założeniem a zamknięciem konta.
CREATE OR REPLACE TRIGGER outside_transaction_date_trig
BEFORE INSERT OR UPDATE OF transaction_date ON OUTSIDE_TRANSACTIONS_HISTORY
FOR EACH ROW
WHEN (new.transaction_date IS NOT NULL)
DECLARE
    v_creation_date DATE;
    v_closing_date DATE;
BEGIN
    SELECT creation_date, closing_date
    INTO v_creation_date, v_closing_date
    FROM ACCOUNTS
    INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
    WHERE account_currency_id = :new.inside_account_currency_id;

    IF :new.transaction_date < v_creation_date OR :new.transaction_date > v_closing_date
    THEN
        RAISE_APPLICATION_ERROR(-20001, 'Konto uczestniczące w przelewie nie istniało w momencie transakcji!');
    END IF;
END;
/

-- Wyzwalacz weryfikuje, czy data wzięcia wpisywanej pożyczki są między założeniem a zamknięciem konta.
CREATE OR REPLACE TRIGGER loan_date_trig
BEFORE INSERT OR UPDATE OF date_taken ON LOANS
FOR EACH ROW
DECLARE
    v_creation_date DATE;
    v_closing_date DATE;
BEGIN
    SELECT creation_date, closing_date
    INTO v_creation_date, v_closing_date
    FROM ACCOUNTS
    INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
    WHERE account_currency_id = :new.account_currency_id;

    IF :new.date_taken < v_creation_date OR :new.date_taken > v_closing_date
    THEN
        RAISE_APPLICATION_ERROR(-20001, 'To konto nie istniało w momencie wzięcia pożyczki!');
    END IF;
END;
/

-- Wyzwalacz weryfikuje, czy daty wzięcia i zakończenia wpisywanej lokaty są między założeniem a zamknięciem konta.
CREATE OR REPLACE TRIGGER investment_date_trig
BEFORE INSERT OR UPDATE OF date_taken, date_ended ON INVESTMENTS
FOR EACH ROW
DECLARE
    v_creation_date DATE;
    v_closing_date DATE;
BEGIN
    SELECT creation_date, closing_date
    INTO v_creation_date, v_closing_date
    FROM ACCOUNTS
    INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
    WHERE account_currency_id = :new.account_currency_id;

    IF :new.date_taken < v_creation_date OR :new.date_taken > v_closing_date OR
       :new.date_ended < v_creation_date OR :new.date_ended > v_closing_date
    THEN
        RAISE_APPLICATION_ERROR(-20001, 'To konto nie istniało w momencie wzięcia lub zakończenia lokaty!');
    END IF;
END;
/
