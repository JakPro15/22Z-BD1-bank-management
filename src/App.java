import java.io.*;
import java.sql.*;
import java.util.Random;
import java.util.Scanner;


public class App {
    Connection conn; // obiekt Connection do nawiazania polaczenia z baza danych

    public static void main(String[] args) {
        try {
            Connector.connect();
        }
        catch (SQLException e) {
            System.err.println("Wyjątek SQL: " + e.getMessage());
        }
        catch (IOException e) {
            System.err.println("Błąd: nie można otworzyć pliku connection.properties" );
        }

        Scanner sc = new Scanner(System.in);
        System.out.println("Witaj w aplikacji obługującej bazę danych banku, " +
                           "projektu z BD1 zespołu 88 (Jakub Proboszcz i Kamil Michalak).");
        String answer = new String();
        while(!answer.equals("q")) {
            System.out.println("Wybierz, którą funkcję aplikacji wykonać. Wpisz:");
            System.out.println("1 aby wyświetlić listę klientów;");
            System.out.println("2 aby wyświetlić dane, ogólne saldo i listę kont danego klienta;");
            System.out.println("3 aby wyświetlić bilansy wszystkich kont danego klienta;");
            System.out.println("4 aby wyświetlić listę pożyczek danego konta;");
            System.out.println("5 aby wyświetlić listę lokat danego konta;");
            System.out.println("6 aby wyświetlić historię transakcji danego klienta;");
            System.out.println("7 aby wyświetlić kursy walut;");
            System.out.println("8 aby zmienić kurs wybranej waluty;");
            System.out.println("9 aby wykonać przelew;");
            System.out.println("10 aby wziąć pożyczkę;");
            System.out.println("11 aby założyć lokatę;");
            System.out.println("q aby zakończyć program.");
            System.out.print("Twój wybór: ");
            answer = sc.nextLine();
        }
        sc.close();

        try {
            Connector.closeConnection();
        }
        catch (SQLException e) {
            System.err.println("Wyjątek SQL: " + e.getMessage());
        }
    }

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
