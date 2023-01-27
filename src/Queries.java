import java.sql.*;
import java.text.SimpleDateFormat;
import java.util.Scanner;

public class Queries {
    public static void showClients(Connection connection) throws SQLException {
        System.out.println("Lista klientów:");

        Statement statement = connection.createStatement();
        ResultSet rs = statement.executeQuery(
            "SELECT CLIENTS.*, calculate_total_balance(client_id) FROM CLIENTS ORDER BY client_id"
        );

        System.out.println("---------------------------------");
        System.out.printf("%2s %11s %13s %12s %5s %15s %32s %17s\n", "ID", "Imię", "Nazwisko", "PESEL", "Płeć",
                            "Numer telefonu", "Adres email", "Sumaryczne saldo");
        while (rs.next()) {
            System.out.printf("%2s %11s %13s %12s %5s %15s %32s %14s PLN\n", rs.getString(1), rs.getString(2), rs.getString(3),
                                rs.getString(4), rs.getString(5), rs.getString(6), rs.getString(7), rs.getString(8));
        }
        System.out.println("---------------------------------");

        rs.close();
        statement.close();
    }

    public static void showAccountData(Connection connection, Scanner stdin) throws SQLException {
        System.out.println("Podaj ID klienta, którego konta chcesz wyświetlić:");

        PreparedStatement preparedStatement = connection.prepareStatement(
            "SELECT name, surname FROM CLIENTS WHERE client_id = ?"
        );
        String clientId = stdin.nextLine();
        preparedStatement.setString(1, clientId);
        ResultSet rs = preparedStatement.executeQuery();

        if(!rs.next()) {
            System.out.println("To nie jest ID istniejącego klienta!");
            return;
        }
        System.out.printf("Klient %s %s posiada następujące konta:\n", rs.getString(1), rs.getString(2));

        preparedStatement = connection.prepareStatement(
            "SELECT account_id, account_number, type, creation_date, closing_date, " +
                   "transaction_limit, balance, currency_short_name " +
            "FROM CLIENTS_ACCOUNTS " +
            "INNER JOIN ACCOUNTS USING(account_id) " +
            "INNER JOIN ACCOUNT_CURRENCIES USING(account_id) " +
            "WHERE client_id = ? " +
            "ORDER BY account_id"
        );
        preparedStatement.setString(1, clientId);
        rs = preparedStatement.executeQuery();

        System.out.println("---------------------------------");
        System.out.printf("%8s %26s %8s %15s %15s %8s %10s\n", "ID konta", "Numer konta", "Typ",
                          "Data utworzenia", "Data zamknięcia", "Limit", "Saldo");
        while (rs.next()) {
            System.out.printf("%8s %26s %8s %15s %15s %8s %10s\n", rs.getString(1), rs.getString(2), rs.getString(3),
                              rs.getDate(4) != null ? new SimpleDateFormat("yyyy-MM-dd").format(rs.getDate(4)) : "Brak",
                              rs.getDate(5) != null ? new SimpleDateFormat("yyyy-MM-dd").format(rs.getDate(5)) : "Brak",
                              rs.getString(6) != null ? rs.getString(6) : "Brak", rs.getString(7) + " " + rs.getString(8));
        }
        System.out.println("---------------------------------");

        rs.close();
        preparedStatement.close();
    }

    public static void showLoanData(Connection connection, Scanner stdin) throws SQLException {
        System.out.println("Podaj ID konta, którego pożyczki chcesz wyświetlić:");

        PreparedStatement preparedStatement = connection.prepareStatement(
            "SELECT account_id, account_number " +
            "FROM ACCOUNT_CURRENCIES " +
            "INNER JOIN ACCOUNTS USING(account_id)" +
            "WHERE account_id = ?"
        );
        String accountId = stdin.nextLine();
        preparedStatement.setString(1, accountId);
        ResultSet rs = preparedStatement.executeQuery();

        if(!rs.next()) {
            System.out.println("To nie jest ID istniejącego konta!");
            return;
        }
        System.out.printf("Konto o id %s i numerze %s brało następujące pożyczki:\n", rs.getString(1), rs.getString(2));

        preparedStatement = connection.prepareStatement(
            "SELECT loan_id, starting_amount, current_amount, currency_short_name, date_taken, date_due, yearly_interest_rate " +
            "FROM LOANS " +
            "INNER JOIN ACCOUNT_CURRENCIES USING(account_currency_id) " +
            "WHERE account_id = ? " +
            "ORDER BY loan_id"
        );
        preparedStatement.setString(1, accountId);
        rs = preparedStatement.executeQuery();

        System.out.println("---------------------------------");
        System.out.printf("%2s %16s %10s %12s %13s %7s\n", "ID", "Kwota początkowa", "Do spłaty",
                          "Data wzięcia", "Termin spłaty", "Odsetki");
        while (rs.next()) {
            System.out.printf("%2s %16s %10s %12s %13s %5s %%\n", rs.getString(1), rs.getString(2) + " " + rs.getString(4),
                              rs.getString(3) + " " + rs.getString(4),
                              rs.getDate(5) != null ? new SimpleDateFormat("yyyy-MM-dd").format(rs.getDate(5)) : "Brak",
                              rs.getDate(6) != null ? new SimpleDateFormat("yyyy-MM-dd").format(rs.getDate(6)) : "Brak",
                              rs.getString(7));
        }
        System.out.println("---------------------------------");

        rs.close();
        preparedStatement.close();
    }

    public static void showInvestmentData(Connection connection, Scanner stdin) throws SQLException {
        System.out.println("Podaj ID konta, którego lokaty chcesz wyświetlić:");

        PreparedStatement preparedStatement = connection.prepareStatement(
            "SELECT account_id, account_number " +
            "FROM ACCOUNT_CURRENCIES " +
            "INNER JOIN ACCOUNTS USING(account_id)" +
            "WHERE account_id = ?"
        );
        String accountId = stdin.nextLine();
        preparedStatement.setString(1, accountId);
        ResultSet rs = preparedStatement.executeQuery();

        if(!rs.next()) {
            System.out.println("To nie jest ID istniejącego konta!");
            return;
        }
        System.out.printf("Konto o id %s i numerze %s posiadało następujące lokaty:\n", rs.getString(1), rs.getString(2));

        preparedStatement = connection.prepareStatement(
            "SELECT investment_id, date_taken, date_ended, blocked_until, yearly_interest_rate, amount, currency_short_name " +
            "FROM INVESTMENTS " +
            "INNER JOIN ACCOUNT_CURRENCIES USING(account_currency_id) " +
            "WHERE account_id = ? " +
            "ORDER BY investment_id"
        );
        preparedStatement.setString(1, accountId);
        rs = preparedStatement.executeQuery();

        System.out.println("---------------------------------");
        System.out.printf("%2s %15s %16s %18s %14s %10s\n", "ID", "Data utworzenia", "Data zakończenia",
                          "Data końca blokady", "Oprocentowanie", "Kwota");
        while (rs.next()) {
            System.out.printf("%2s %15s %16s %18s %12s %% %10s\n", rs.getString(1),
                              rs.getDate(2) != null ? new SimpleDateFormat("yyyy-MM-dd").format(rs.getDate(2)) : "Brak",
                              rs.getDate(3) != null ? new SimpleDateFormat("yyyy-MM-dd").format(rs.getDate(3)) : "Brak",
                              rs.getDate(4) != null ? new SimpleDateFormat("yyyy-MM-dd").format(rs.getDate(4)) : "Brak",
                              rs.getString(5), rs.getString(6) + " " + rs.getString(7));
        }
        System.out.println("---------------------------------");

        rs.close();
        preparedStatement.close();
    }

    public static void showTransactionHistory(Connection connection, Scanner stdin) throws SQLException {
        System.out.println("Podaj ID klienta, którego transakcje chcesz wyświetlić:");

        PreparedStatement preparedStatement = connection.prepareStatement(
            "SELECT name, surname FROM CLIENTS WHERE client_id = ?"
        );
        String clientId = stdin.nextLine();
        preparedStatement.setString(1, clientId);
        ResultSet rs = preparedStatement.executeQuery();

        if(!rs.next()) {
            System.out.println("To nie jest ID istniejącego klienta!");
            return;
        }
        System.out.printf("Klient %s %s uczestniczył w następujących transakcjach:\n", rs.getString(1), rs.getString(2));

        // large SQL query reused from testing
        preparedStatement = connection.prepareStatement(
            "(SELECT own_a.account_number AS client_account_number, other_a.account_number AS other_account_number, " +
                   "transaction_date, -amount_before AS amount_received, own_ac.currency_short_name AS currency " +
            "FROM INSIDE_TRANSACTIONS_HISTORY it " +
            "INNER JOIN ACCOUNT_CURRENCIES own_ac ON it.account_currency_from_id = own_ac.account_currency_id " +
            "INNER JOIN ACCOUNTS own_a ON own_ac.account_id = own_a.account_id " +
            "INNER JOIN CLIENTS_ACCOUNTS ca ON ca.account_id = own_a.account_id " +
            "INNER JOIN ACCOUNT_CURRENCIES other_ac ON it.account_currency_to_id = other_ac.account_currency_id " +
            "INNER JOIN ACCOUNTS other_a ON other_ac.account_id = other_a.account_id " +
            "WHERE client_id = ? " +
            "UNION " +
            "SELECT own_a.account_number AS client_account_number, other_a.account_number AS other_account_number, " +
                   "transaction_date, amount_after AS amount_received, own_ac.currency_short_name AS currency " +
            "FROM INSIDE_TRANSACTIONS_HISTORY it " +
            "INNER JOIN ACCOUNT_CURRENCIES own_ac ON it.account_currency_to_id = own_ac.account_currency_id " +
            "INNER JOIN ACCOUNTS own_a ON own_ac.account_id = own_a.account_id " +
            "INNER JOIN CLIENTS_ACCOUNTS ca ON ca.account_id = own_a.account_id " +
            "INNER JOIN ACCOUNT_CURRENCIES other_ac ON it.account_currency_from_id = other_ac.account_currency_id " +
            "INNER JOIN ACCOUNTS other_a ON other_ac.account_id = other_a.account_id " +
            "WHERE client_id = ? " +
            "UNION " +
            "SELECT account_number AS client_account_number, ot.outside_account_number AS other_account_number, " +
                   "transaction_date, amount AS amount_received, ac.currency_short_name AS currency " +
            "FROM OUTSIDE_TRANSACTIONS_HISTORY ot " +
            "INNER JOIN ACCOUNT_CURRENCIES ac ON ot.inside_account_currency_id = ac.account_currency_id " +
            "INNER JOIN ACCOUNTS USING(account_id) " +
            "INNER JOIN CLIENTS_ACCOUNTS USING(account_id) " +
            "WHERE client_id = ?) " +
            "ORDER BY transaction_date"
        );
        preparedStatement.setString(1, clientId);
        preparedStatement.setString(2, clientId);
        preparedStatement.setString(3, clientId);
        rs = preparedStatement.executeQuery();

        System.out.println("---------------------------------");
        System.out.printf("%26s %31s %15s %15s\n", "Numer konta tego klienta",
                          "Numer innego konta z transakcji", "Data transakcji", "Otrzymana kwota");
        while (rs.next()) {
            System.out.printf("%26s %31s %15s %15s\n", rs.getString(1), rs.getString(2),
                              new SimpleDateFormat("yyyy-MM-dd").format(rs.getDate(3)),
                              rs.getString(4) + " " + rs.getString(5));
        }
        System.out.println("---------------------------------");
        System.out.println("Ujemna otrzymana kwota oznacza, że przelew był wychodzący.");

        rs.close();
        preparedStatement.close();
    }

    public static void showExchangeRates(Connection connection) throws SQLException {
        System.out.println("Kursy walut:");

        Statement statement = connection.createStatement();
        ResultSet rs = statement.executeQuery(
            "SELECT short_name, full_name, exchange_rate_to_PLN from CURRENCIES"
        );

        System.out.println("---------------------------------");
        System.out.printf("%5s %18s %12s\n", "Skrót", "Pełna nazwa", "Kurs na PLN");
        while (rs.next()) {
            System.out.printf("%5s %18s %12s\n", rs.getString(1), rs.getString(2), rs.getString(3));
        }
        System.out.println("---------------------------------");

        rs.close();
        statement.close();
    }
}
