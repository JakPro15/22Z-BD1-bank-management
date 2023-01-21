-- Funkcja oblicza miesi�czn� op�at� za karty p�atnicze dla danego klienta.
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

-- Funkcja oblicza og�lny balans w PLN wszystkich kont klienta, wliczaj�c po�yczki i lokaty.
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

-- Procedura rejestruje wzi�cie po�yczki przez podane konto i dodaje pieni�dze do konta
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
        dbms_output.put_line('To konto nie ma tej waluty. Nale�y najpierw doda� t� walut� do tego konta.');
        RAISE;
END;
/

-- Procedura rejestruje za�o�enie lokaty przez podane konto i odejmuje pieni�dze z konta.
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
        RAISE_APPLICATION_ERROR(-20001, 'Tego konta nie sta� na za�o�enie takiej lokaty!');
    END IF;
EXCEPTION
    WHEN no_data_found THEN
        dbms_output.put_line('To konto nie ma tej waluty. Nale�y najpierw doda� t� walut� do tego konta.');
        RAISE;
END;
/

-- Procedura rejestruje przelew wewn�trzny. Dodaje/odejmuje pieni�dze zgodnie z obecnym kursem walut.
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
        RAISE_APPLICATION_ERROR(-20001, 'Konto wysy�aj�ce nie mo�e wys�a� takiego przelewu!');
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
        RAISE_APPLICATION_ERROR(-20001, 'Konta wysy�aj�cego nie sta� na wykonanie takiego przelewu!');
    END IF;
EXCEPTION
    WHEN no_data_found THEN
        dbms_output.put_line('Dodanie transakcji wewn�trznej si� nie powiod�o. Nale�y zweryfikowa�, czy konta istniej� i maj� takie waluty.');
        RAISE;
END;
/

-- Procedura rejestruje przelew zewn�trzny (wychodz�cy do lub przychodz�cy z innego banku)
-- i dodaje/odejmuje odpowiedni� ilo�� pieni�dzy.
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
        RAISE_APPLICATION_ERROR(-20001, 'Wewn�trzne konto nie mo�e wykona� takiego przelewu!');
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
        RAISE_APPLICATION_ERROR(-20001, 'Wewn�trznego konta nie sta� na wykonanie takiego przelewu!');
    END IF;
EXCEPTION
    WHEN no_data_found THEN
        dbms_output.put_line('Dodanie transakcji wewn�trznej si� nie powiod�o. Nale�y zweryfikowa�, czy konta istniej� i maj� takie waluty.');
        RAISE;
END;
/

-- Procedura blokuje wszystkie konta, kt�re przez rok nie sp�aci�y 10% wzi�tej po�yczki.
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

-- Wyzwalacz weryfikuje, czy data wpisywanej transakcji wewn�trznej jest mi�dzy za�o�eniem a zamkni�ciem uczestnicz�cych kont.
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
        RAISE_APPLICATION_ERROR(-20001, 'Konto wysy�aj�ce przelew nie istnia�o w momencie transakcji!');
    END IF;

    SELECT creation_date, closing_date
    INTO v_creation_date_2, v_closing_date_2
    FROM ACCOUNTS
    INNER JOIN ACCOUNT_CURRENCIES USING(account_id)
    WHERE account_currency_id = :new.account_currency_to_id;
    
    IF :new.transaction_date < v_creation_date_2 OR :new.transaction_date > v_closing_date_2
    THEN
        RAISE_APPLICATION_ERROR(-20001, 'Konto odbieraj�ce przelew nie istnia�o w momencie transakcji!');
    END IF;
END;
/

-- Wyzwalacz weryfikuje, czy data wpisywanej transakcji zewn�trznej jest mi�dzy za�o�eniem a zamkni�ciem konta.
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
        RAISE_APPLICATION_ERROR(-20001, 'Konto uczestnicz�ce w przelewie nie istnia�o w momencie transakcji!');
    END IF;
END;
/

-- Wyzwalacz weryfikuje, czy data wzi�cia wpisywanej po�yczki s� mi�dzy za�o�eniem a zamkni�ciem konta.
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
        RAISE_APPLICATION_ERROR(-20001, 'To konto nie istnia�o w momencie wzi�cia po�yczki!');
    END IF;
END;
/

-- Wyzwalacz weryfikuje, czy daty wzi�cia i zako�czenia wpisywanej lokaty s� mi�dzy za�o�eniem a zamkni�ciem konta.
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
        RAISE_APPLICATION_ERROR(-20001, 'To konto nie istnia�o w momencie wzi�cia lub zako�czenia lokaty!');
    END IF;
END;
/

-- Wyzwalacz sprawdza, czy niepe�noletni w�a�ciciel konta wsp�dzieli to konto z co najmniej jedn� osob� pe�noletni�.
CREATE OR REPLACE TRIGGER account_owner_trig
BEFORE INSERT OR UPDATE ON CLIENTS_ACCOUNTS
FOR EACH ROW
DECLARE
    v_adult_owners NUMBER := 0;
    v_pesel CLIENTS.pesel%TYPE;
    v_pesel_birth_number NUMBER;
BEGIN
    FOR v_client_id IN (SELECT client_id
                        FROM CLIENTS_ACCOUNTS
                        WHERE account_id = :new.account_id
                        UNION
                        SELECT :new.client_id
                        FROM DUAL)
    LOOP
        SELECT pesel
        INTO v_pesel
        FROM CLIENTS
        WHERE client_id = v_client_id.client_id;

        IF v_pesel IS NOT NULL
        THEN
            v_pesel_birth_number := TO_NUMBER(SUBSTR(v_pesel, 1, 2));
            IF v_pesel_birth_number < MOD(EXTRACT(YEAR FROM SYSDATE), 100)
            THEN
                v_pesel_birth_number := v_pesel_birth_number + 2000;
            ELSE
                v_pesel_birth_number := v_pesel_birth_number + 1900;
            END IF;
            
            IF EXTRACT(YEAR FROM SYSDATE) - v_pesel_birth_number >= 18
            THEN
                v_adult_owners := v_adult_owners + 1;
            END IF;
        END IF;
    END LOOP;
    
    IF v_adult_owners = 0
    THEN
        RAISE_APPLICATION_ERROR(-20001, 'Konto musi mie� co najmniej jednego pe�noletniego w�a�ciciela!');
    END IF;
END;
/

