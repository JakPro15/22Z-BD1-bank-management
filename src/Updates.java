import java.sql.*;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Scanner;

public class Updates {
    public static void changeCurrencyExchangeRate(Connection connection, Scanner stdin) throws SQLException {
        System.out.println("Podaj skróconą nazwę waluty, której kurs chcesz zmienić:");

        PreparedStatement preparedStatement = connection.prepareStatement(
            "SELECT full_name FROM CURRENCIES WHERE short_name = ?"
        );
        String shortName = stdin.nextLine();
        if(shortName.equals("PLN")) {
            System.out.println("Nie można zmienić kursu PLN względem PLN!");
            return;
        }
        preparedStatement.setString(1, shortName);
        ResultSet rs = preparedStatement.executeQuery();

        if(!rs.next()) {
            System.out.println("Waluta o tej nazwie nie istnieje!");
            return;
        }

        System.out.printf("Podaj kurs waluty '%s' jaki chcesz ustawić:\n", rs.getString(1));

        preparedStatement = connection.prepareStatement(
            "UPDATE CURRENCIES " +
            "SET exchange_rate_to_PLN = ? " +
            "WHERE short_name = ?"
        );
        String rate = stdin.nextLine();
        preparedStatement.setString(1, rate);
        preparedStatement.setString(2, shortName);
        int result = preparedStatement.executeUpdate();

        if (result != 1) {
            throw new SQLException();
        }

        System.out.println("Pomyślnie zmieniono kurs waluty!");

        rs.close();
        preparedStatement.close();
    }

    public static void takeLoan(Connection connection, Scanner stdin) throws SQLException {
        System.out.println("Podaj kwotę pożyczki, którą chcesz wziąć:");
        String amount = stdin.nextLine();

        System.out.println("Podaj termin spłaty pożyczki (format daty: yyyy-MM-dd):");
        String dateDue = stdin.nextLine();

        System.out.println("Podaj procent rocznych odsetek:");
        String interestRate = stdin.nextLine();

        System.out.println("Podaj ID konta:");
        String accountId = stdin.nextLine();

        System.out.println("Podaj skrót waluty, w której chcesz wziąć pożyczkę:");
        String shortName = stdin.nextLine();


        CallableStatement callProcedure = connection.prepareCall(
            "{CALL take_loan(?, ?, ?, ?, ?)}"
        );

        callProcedure.setString(1, amount);
        try {
            callProcedure.setDate(2, new Date (new SimpleDateFormat("yyyy-MM-dd").parse(dateDue).getTime()));
        }
        catch (ParseException e) {
            System.out.println("Data podana w złym formacie!");
            return;
        }
        callProcedure.setString(3, interestRate);
        callProcedure.setString(4, accountId);
        callProcedure.setString(5, shortName);

        callProcedure.execute();

        System.out.println("Udało się wziąć pożyczkę!");

        callProcedure.close();
    }

    public static void makeInvestment(Connection connection, Scanner stdin) throws SQLException {
        System.out.println("Podaj kwotę lokaty, jaką chcesz założyć:");
        String amount = stdin.nextLine();

        System.out.println("Podaj termin, do kiedy lokata ma być zablokowana (format daty: yyyy-MM-dd):");
        String dateBlocked = stdin.nextLine();

        System.out.println("Podaj oprocentowanie lokaty:");
        String interestRate = stdin.nextLine();

        System.out.println("Podaj ID konta:");
        String accountId = stdin.nextLine();

        System.out.println("Podaj skrót waluty, w której chcesz założyć lokatę:");
        String shortName = stdin.nextLine();


        CallableStatement callProcedure = connection.prepareCall(
            "{CALL make_investment(?, ?, ?, ?, ?)}"
        );

        callProcedure.setString(1, amount);
        try {
            callProcedure.setDate(2, new Date (new SimpleDateFormat("yyyy-MM-dd").parse(dateBlocked).getTime()));
        }
        catch (ParseException e) {
            System.out.println("Data podana w złym formacie!");
            return;
        }
        callProcedure.setString(3, interestRate);
        callProcedure.setString(4, accountId);
        callProcedure.setString(5, shortName);

        callProcedure.execute();

        System.out.println("Udało się założyć lokatę!");

        callProcedure.close();
    }

    public static void doTransaction(Connection connection, Scanner stdin) throws SQLException {
        System.out.print("Podaj ID konta wysyłającego przelew: ");
        String accountId = stdin.nextLine();
        System.out.print("Podaj skrót waluty (np. PLN), w której przelew ma być wykonany: ");
        String currency = stdin.nextLine();
        System.out.print("Podaj numer konta docelowego: ");
        String targetNumber = stdin.nextLine();

        PreparedStatement preparedStatement = connection.prepareStatement(
            "SELECT account_id FROM ACCOUNTS WHERE account_number = ?"
        );
        preparedStatement.setString(1, targetNumber);
        ResultSet targetResultSet = preparedStatement.executeQuery();
        boolean inside = targetResultSet.next();

        System.out.print("Podaj, ile pieniędzy ma być przesłane: ");
        String amount = stdin.nextLine();

        CallableStatement statement;
        if(inside) {
            statement = connection.prepareCall("{CALL make_inside_transaction(?, ?, ?, ?, ?)}");
            statement.setString(1, amount);
            statement.setString(2, accountId);
            statement.setString(3, targetResultSet.getString(1));
            statement.setString(4, currency);
            statement.setString(5, currency);
            statement.execute();
        }
        else {
            statement = connection.prepareCall("{CALL make_outside_transaction(?, ?, ?, ?)}");
            statement.setString(1, targetNumber);
            statement.setString(2, "-" + amount);
            statement.setString(3, accountId);
            statement.setString(4, currency);
            statement.execute();
        }
        while(statement.getMoreResults());
        statement.close();

        System.out.println("Transakcja zaksięgowana.");
    }
}
