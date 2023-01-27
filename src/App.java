import java.io.*;
import java.sql.*;
import java.util.Scanner;
import java.util.Properties;

import oracle.jdbc.pool.OracleDataSource;


public class App {
    Connection connection;
    Scanner stdin = new Scanner(System.in);

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
        connection.setAutoCommit(true);
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

        app.userLoop();

        try {
            app.closeConnection();
        }
        catch (SQLException e) {
            System.err.println("Wyjątek SQL: " + e.getMessage());
        }
    }

    public void userLoop() {
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
            System.out.println("10 aby wykonać przelew;");
            System.out.println("q aby zakończyć program.");
            System.out.print("Twój wybór: ");
            answer = stdin.nextLine();
            if(answer.equals("q")) {
                break;
            }
            try {
                int choice = Integer.valueOf(answer);
                switch(choice) {
                    case 1:
                        Queries.showClients(connection);
                        break;
                    case 2:
                        Queries.showAccountData(connection, stdin);
                        break;
                    case 3:
                        Queries.showLoanData(connection, stdin);
                        break;
                    case 4:
                        Queries.showInvestmentData(connection, stdin);
                        break;
                    case 5:
                        Queries.showTransactionHistory(connection, stdin);
                        break;
                    case 6:
                        Queries.showExchangeRates(connection);
                        break;
                    case 7:
                        Updates.changeCurrencyExchangeRate(connection, stdin);
                        break;
                    case 8:
                        Updates.takeLoan(connection, stdin);
                        break;
                    case 9:
                        Updates.makeInvestment(connection, stdin);
                        break;
                    case 10:
                        Updates.doTransaction(connection, stdin);
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
            finally {
                stdin.nextLine();
            }
        }
        stdin.close();

        try {
            closeConnection();
        }
        catch (SQLException e) {
            System.err.println("Wyjątek SQL: " + e.getMessage());
        }
    }
}
