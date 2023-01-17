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



--procedura, kt�ra ustawia dat� zamkni�cia konta klienta na miesi�c do przodu,
--jesli klient przez rok nie sp�aci� wi�cej 10% swojej po�yczki


--funkcja, kt�ra dla podanej waluty zrobi jej "bilans" u�ycia
--suma w po�yczkach, suma w inwestycjach, suma w przelewach wewn. i zewn.
--mo�na po czym� pogrupowa� jeszcze


--funkcja zwi�zana z obliczaniem czego� w kredytach i/lub po�yczkach


--procedura przydzielaj�ca bonusy finansowe top 3 najaktywniejszym klientom









