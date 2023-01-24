import java.io.FileInputStream;
import java.io.*;
import java.sql.*;
import java.util.Properties;

import oracle.jdbc.pool.OracleDataSource;


public class Connector {
    static Connection connection;

    public static void connect() throws SQLException, IOException {
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
    }

    public static void closeConnection() throws SQLException {
        connection.close();
    }
}
