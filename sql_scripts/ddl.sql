CREATE TABLE CLIENTS (
    client_ID NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY START WITH 1 PRIMARY KEY,
    name VARCHAR2(40 CHAR) NOT NULL,
    surname VARCHAR2(40 CHAR) NOT NULL,
    pesel CHAR(11 CHAR) UNIQUE,
    gender CHAR(1 CHAR) NOT NULL,
    phone_number VARCHAR2(15 CHAR),
    email_address VARCHAR2(40 CHAR),
    CONSTRAINT contact CHECK(phone_number IS NOT NULL OR email_address IS NOT NULL)
);

CREATE SEQUENCE account_numbers_seq START WITH 75125045191000153169965084
                     INCREMENT BY 100 MAXVALUE 75125045191000153170000000 NOCYCLE;

CREATE TABLE ACCOUNTS (
    account_ID NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY START WITH 1 PRIMARY KEY,
    account_number CHAR(26 CHAR) DEFAULT ON NULL TO_CHAR(account_numbers_seq.NEXTVAL) UNIQUE CHECK(SUBSTR(account_number, 3, 4) = '1250'),
    type VARCHAR2(40 CHAR) NOT NULL,
    creation_date DATE DEFAULT ON NULL SYSDATE NOT NULL,
    closing_date DATE,
    transaction_limit NUMBER(12, 2),
    CONSTRAINT close_after_create CHECK(closing_date >= creation_date)
);

CREATE TABLE CLIENTS_ACCOUNTS (
    client_ID NUMBER REFERENCES CLIENTS(client_ID) NOT NULL,
    account_ID NUMBER REFERENCES ACCOUNTS(account_ID) NOT NULL,
    CONSTRAINT clients_accounts_pk PRIMARY KEY (client_ID, account_ID)
);

CREATE TABLE CARDS (
    card_ID NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY START WITH 1 PRIMARY KEY,
    type VARCHAR2(1 CHAR) NOT NULL,
    card_number CHAR(16 CHAR) NOT NULL UNIQUE,
    limit NUMBER(12, 2) CHECK(limit >= 0),
    expiration_date DATE,
    blocked CHAR(1) DEFAULT 'N' NOT NULL,
    account_ID NUMBER REFERENCES ACCOUNTS(account_ID) NOT NULL
);

CREATE TABLE CURRENCIES (
    short_name CHAR(3 CHAR) NOT NULL PRIMARY KEY,
    full_name VARCHAR2(40 CHAR) NOT NULL UNIQUE,
    exchange_rate_to_pln NUMBER(12, 2) NOT NULL CHECK(exchange_rate_to_pln > 0)
);

CREATE TABLE ACCOUNT_CURRENCIES (
    account_currency_ID NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY START WITH 1 PRIMARY KEY,
    balance NUMBER(12, 2) NOT NULL,
    currency_short_name CHAR(3 CHAR) REFERENCES CURRENCIES(short_name) NOT NULL,
    account_ID NUMBER REFERENCES ACCOUNTS(account_ID) NOT NULL
);

CREATE TABLE LOANS (
    loan_ID NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY START WITH 1 PRIMARY KEY,
    starting_amount NUMBER(12, 2) NOT NULL CHECK(starting_amount > 0),
    current_amount NUMBER(12, 2) NOT NULL CHECK(current_amount >= 0),
    date_taken DATE DEFAULT ON NULL SYSDATE NOT NULL,
    date_due DATE NOT NULL,
    yearly_interest_rate NUMBER(8, 4) NOT NULL CHECK(yearly_interest_rate >= 0),
    account_currency_ID NUMBER REFERENCES ACCOUNT_CURRENCIES(account_currency_ID) NOT NULL,
    CONSTRAINT end_after_begin CHECK(date_due >= date_taken)
);

CREATE TABLE INVESTMENTS (
    investment_ID NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY START WITH 1 PRIMARY KEY,
    date_taken DATE DEFAULT ON NULL SYSDATE NOT NULL,
    date_ended DATE,
    blocked_until DATE,
    yearly_interest_rate NUMBER(8, 4) NOT NULL CHECK(yearly_interest_rate >= 0),
    amount NUMBER(12, 2) NOT NULL CHECK(amount > 0),
    account_currency_ID NUMBER REFERENCES ACCOUNT_CURRENCIES(account_currency_ID) NOT NULL,
    CONSTRAINT date_order CHECK(blocked_until >= date_taken AND
                                date_ended >= blocked_until AND
                                date_ended >= date_taken)
);

CREATE TABLE INSIDE_TRANSACTIONS_HISTORY (
    inside_transaction_ID NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY START WITH 1 PRIMARY KEY,
    -- before and after might differ if the currencies differ
    amount_before NUMBER(12, 2) NOT NULL CHECK(amount_before > 0),
    amount_after NUMBER(12, 2) NOT NULL CHECK(amount_after > 0),
    transaction_date DATE DEFAULT ON NULL SYSDATE NOT NULL,
    account_currency_from_ID NUMBER REFERENCES ACCOUNT_CURRENCIES(account_currency_ID) NOT NULL,
    account_currency_to_ID NUMBER REFERENCES ACCOUNT_CURRENCIES(account_currency_ID) NOT NULL
);

CREATE TABLE OUTSIDE_TRANSACTIONS_HISTORY (
    outside_transaction_ID NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY START WITH 1 PRIMARY KEY,
    outside_account_number VARCHAR2(30 CHAR) NOT NULL,
    amount NUMBER NOT NULL, -- negative means outgoing transaction, positive means incoming
    transaction_date DATE DEFAULT ON NULL SYSDATE NOT NULL,
    inside_account_currency_ID NUMBER REFERENCES ACCOUNT_CURRENCIES(account_currency_ID) NOT NULL
);