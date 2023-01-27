import java.io.*;
import java.sql.*;
import java.text.SimpleDateFormat;
import java.util.Scanner;
import java.io.FileInputStream;
import java.util.Properties;

import oracle.jdbc.pool.OracleDataSource;


public class App {
    Connection connection;
    Scanner stdin;

    public void connect() throws SQLException, IOException {
        Properties prop = new Properties();
        FileInputStream in = new FileInputStream("connection.properties");
        prop.load(in);
        in.close();

        String host = prop.getProperty("jdbc.host");
        String username = prop.getProperty("jdbc.username");
        String password = prop.getProperty("jdbc.password");
        String port = prop.getProperty("jdbc.port");
        String serviceName = prop.getProperty("jdbc.service.name");

        String connectionString = String.format(
            "jdbc:oracle:thin:%s/%s@//%s:%s/%s",
            username, password, host, port, serviceName
        );

        OracleDataSource ods;
        ods = new OracleDataSource();

        ods.setURL(connectionString);
        connection = ods.getConnection();
        connection.setAutoCommit(false);
    }

    public void closeConnection() throws SQLException {
        connection.close();
    }

    public static void main(String[] args) {
        App app = new App();
        try {
            app.connect();
        }
        catch (SQLException e) {
            System.err.println("Wyjątek SQL: " + e.getMessage());
        }
        catch (IOException e) {
            System.err.println("Błąd: nie można otworzyć pliku connection.properties" );
        }

        app.stdin = new Scanner(System.in);
        System.out.println("Witaj w aplikacji obługującej bazę danych banku, " +
                           "projektu z BD1 zespołu 88 (Jakub Proboszcz i Kamil Michalak).");
        String answer = new String();
        while(!answer.equals("q")) {
            System.out.println("Wybierz, którą funkcję aplikacji wykonać. Wpisz:");
            System.out.println("1 aby wyświetlić listę klientów;");
            System.out.println("2 aby wyświetlić dane kont danego klienta;");
            System.out.println("3 aby wyświetlić listę pożyczek danego konta;");
            System.out.println("4 aby wyświetlić listę lokat danego konta;");
            System.out.println("5 aby wyświetlić historię transakcji danego klienta;");
            System.out.println("6 aby wyświetlić kursy walut;");
            System.out.println("7 aby zmienić kurs wybranej waluty;");
            System.out.println("8 aby wziąć pożyczkę;");
            System.out.println("9 aby założyć lokatę;");
            System.out.println("q aby zakończyć program.");
            System.out.print("Twój wybór: ");
            answer = app.stdin.nextLine();
            if(answer.equals("q")) {
                break;
            }
            try {
                int choice = Integer.valueOf(answer);
                switch(choice) {
                    case 1:
                        app.showClients();
                        break;
                    case 2:
                        app.showAccountData();
                        break;
                    case 3:
                        app.showLoanData();
                        break;
                    case 4:
                        app.showInvestmentData();
                        break;
                    case 5:
                        app.showTransactionHistory();
                        break;
                    case 6:
                        app.showExchangeRates();
                        break;
                    case 7:
                        break;
                    case 8:
                        break;
                    case 9:
                        break;
                    default:
                        System.out.println("Niewłaściwy wybór.");
                }
            }
            catch(NumberFormatException e) {
                System.out.println("Niewłaściwy wybór.");
            }
            catch(SQLException e) {
                System.err.println("Wyjątek SQL: " + e.getMessage());
            }
        }
        app.stdin.close();

        try {
            app.closeConnection();
        }
        catch (SQLException e) {
            System.err.println("Wyjątek SQL: " + e.getMessage());
        }
    }

    public void showClients() throws SQLException {
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

        stdin.nextLine();
    }

    public void showAccountData() throws SQLException {
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
                              rs.getDate(4) != null ? new SimpleDateFormat("dd.MM.yyyy").format(rs.getDate(4)) : "Brak",
                              rs.getDate(5) != null ? new SimpleDateFormat("dd.MM.yyyy").format(rs.getDate(5)) : "Brak",
                              rs.getString(6) != null ? rs.getString(6) : "Brak", rs.getString(7) + " " + rs.getString(8));
        }
        System.out.println("---------------------------------");

        rs.close();
        preparedStatement.close();

        stdin.nextLine();
    }

    public void showLoanData() throws SQLException {
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
            System.out.printf("%2s %16s %10s %12s %13s %7s\n", rs.getString(1), rs.getString(2) + " " + rs.getString(4),
                              rs.getString(3) + " " + rs.getString(4),
                              rs.getDate(5) != null ? new SimpleDateFormat("dd.MM.yyyy").format(rs.getDate(5)) : "Brak",
                              rs.getDate(6) != null ? new SimpleDateFormat("dd.MM.yyyy").format(rs.getDate(6)) : "Brak",
                              rs.getString(7));
        }
        System.out.println("---------------------------------");

        rs.close();
        preparedStatement.close();

        stdin.nextLine();
    }

    public void showInvestmentData() throws SQLException {
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
            System.out.printf("%2s %15s %16s %18s %14s %10s\n", rs.getString(1),
                              rs.getDate(2) != null ? new SimpleDateFormat("dd.MM.yyyy").format(rs.getDate(2)) : "Brak",
                              rs.getDate(3) != null ? new SimpleDateFormat("dd.MM.yyyy").format(rs.getDate(3)) : "Brak",
                              rs.getDate(4) != null ? new SimpleDateFormat("dd.MM.yyyy").format(rs.getDate(4)) : "Brak",
                              rs.getString(5), rs.getString(6) + " " + rs.getString(7));
        }
        System.out.println("---------------------------------");

        rs.close();
        preparedStatement.close();

        stdin.nextLine();
    }

    public void showTransactionHistory() throws SQLException {
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
                              new SimpleDateFormat("dd.MM.yyyy").format(rs.getDate(3)),
                              rs.getString(4) + " " + rs.getString(5));
        }
        System.out.println("---------------------------------");
        System.out.println("Ujemna otrzymana kwota oznacza, że przelew był wychodzący.");

        rs.close();
        preparedStatement.close();

        stdin.nextLine();
    }

    public void showExchangeRates() throws SQLException {
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

        stdin.nextLine();
    }

    // public void doTransaction() throws SQLException {
    //     System.out.print("Podaj ID konta wysyłającego przelew: ");
    //     String accountId = stdin.nextLine();
    //     System.out.print("Podaj skrót waluty (np. PLN), w której przelew ma być wykonany: ");
    //     String currency = stdin.nextLine();
    //     System.out.print("Podaj numer konta docelowego: ");
    //     String targetNumber = stdin.nextLine();

    //     PreparedStatement preparedStatement = connection.prepareStatement(
    //         "SELECT account_id FROM ACCOUNTS WHERE account_number = ?"
    //     );
    //     preparedStatement.setString(1, targetNumber);
    //     ResultSet targetResultSet = preparedStatement.executeQuery();
    //     boolean inside = targetResultSet.next();

    //     System.out.print("Podaj, ile pieniędzy ma być przesłane: ");
    //     String amount = stdin.nextLine();

    //     try {
    //         PreparedStatement statement;
    //         if(inside) {
    //             statement = connection.prepareStatement("CALL make_inside_transaction(?, ?, ?, ?, ?)");
    //             statement.setString(1, amount);
    //             statement.setString(2, accountId);
    //             statement.setString(3, targetResultSet.getString(1));
    //             statement.setString(4, currency);
    //             statement.setString(5, currency);
    //             statement.executeUpdate();
    //         }
    //         else {
    //             statement = connection.prepareStatement("CALL make_outside_transaction(?, ?, ?, ?)");
    //             statement.setString(1, targetNumber);
    //             statement.setString(2, "-" + amount);
    //             statement.setString(3, accountId);
    //             statement.setString(4, currency);
    //             statement.executeUpdate();
    //         }
    //         while(statement.getMoreResults());
    //         connection.commit();
    //         statement.close();

    //         System.out.println("Transakcja zaksięgowana.");
    //     }
    //     catch (SQLException e) {
    //         System.out.println("Wyjątek SQL: " + e.getMessage());
    //         connection.rollback();
    //         System.out.println("Transakcja wycofana.");
    //     }
    // }

    // public void showEmployees() throws SQLException {
    //     System.out.println("Lista pracowników:");

    //     Statement stat = conn.createStatement(); // Statement przechowujacy polecenie SQL

    //     // wydajemy zapytanie oraz zapisujemy rezultat w obiekcie typu ResultSet
    //     ResultSet rs = stat.executeQuery("SELECT name, surname FROM employees");

    //     System.out.println("---------------------------------");
    //     // iteracyjnie odczytujemy rezultaty zapytania
    //     while (rs.next())
    //         System.out.println(rs.getString(1) + " " + rs.getString(2));
    //     System.out.println("---------------------------------");

    //     rs.close();
    //     stat.close();
    // }

    // public void showEmployeesByDepartment() throws SQLException {
    //     System.out.println("Prepared statement:");

    //     // Zwoc uwage na znak zapytania w zapytaniu. W to miejsce zostanie
    //     // wstawiona wartosc wprowadzona przez uzytkownika
    //     PreparedStatement preparedStatement = conn
    //             .prepareStatement("SELECT name, surname FROM employees WHERE department_id = ?");

    //     System.out.println("Podaj Numer zakładu:");
    //     Scanner in = new Scanner(System.in);

    //     preparedStatement.setString(1, in.nextLine());
    //     ResultSet rs = preparedStatement.executeQuery(); // Wykonaj zapytanie oraz zapamietaj zbior rezultatow

    //     System.out.println("---------------------------------");
    //     while (rs.next()) {
    //         System.out.println(rs.getString(1) + " " + rs.getString(2));        }
    //     System.out.println("---------------------------------");

    //     in.close();
    //     rs.close();
    //     preparedStatement.close();
    // }

    // public void updateSalary() throws SQLException {
    //     System.out.println("Obsluga transakcji");

    //     try {
    //         conn.setAutoCommit(false);

    //         Statement stat = conn.createStatement();
    //         int rsInt = stat.executeUpdate("UPDATE employees SET salary = 4500 WHERE surname LIKE 'J%'");
    //         System.out.println("Liczba uaktualnionych wierszy: " + rsInt);

    //         rsInt = stat.executeUpdate("UPDATE employees SET salary = 4500 WHERE surname LIKE 'K%'");
    //         System.out.println("Liczba uaktualnionych wierszy: " + rsInt);

    //         conn.commit();
    //         stat.close();

    //     } catch (SQLException eSQL) {
    //         System.out.println("Transakcja wycofana");
    //         conn.rollback();
    //     }
    // }

    // public void luckyEmployees() throws SQLException {
    //     System.out.println("Dodatek stażowy");

    //     CallableStatement callFunction = conn.prepareCall("{? = call calculate_seniority_bonus(?)}");
    //     callFunction.registerOutParameter(1, Types.DOUBLE);

    //     Random ran = new Random();
    //     int min = 101;
    //     int max = 150;
    //     int numInterations = 5;

    //     for (int i = 0; i < numInterations; i++) {
    //         int id = ran.nextInt(max-min) + min;
    //         callFunction.setInt(2, id);
    //         callFunction.execute();
    //         double bonus = callFunction.getDouble(1);
    //         System.out.println("Pracownik " + id + " otrzymuje bonus " + bonus);
    //     }
    //     callFunction.close();
    // }
}
