import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.Properties;

/**
 * The smallest possible connection test: plain JDBC, no Spring. Run it straight from source (Java 11+):
 *   MAR_DB_PASSWORD=... java -cp postgresql-42.7.13.jar JdbcSmokeTest.java
 */
public class JdbcSmokeTest {

    public static void main(String[] args) throws Exception {
        String host = env("MAR_DB_HOST", "localhost");
        String port = env("MAR_DB_PORT", "5433");
        String url = "jdbc:postgresql://" + host + ":" + port + "/" + env("MAR_DB_NAME", "masterantique");

        Properties props = new Properties();
        props.setProperty("user", env("MAR_DB_USER", "mar_app"));
        props.setProperty("password", System.getenv("MAR_DB_PASSWORD"));   // required; never hard-code it
        props.setProperty("connectTimeout", "10");                          // seconds

        try (Connection conn = DriverManager.getConnection(url, props);
             Statement st = conn.createStatement();
             ResultSet rs = st.executeQuery(
                     "select version(), (select count(*) from users), (select count(*) from tickets)")) {
            rs.next();
            System.out.println("Connected to " + url);
            System.out.println(rs.getString(1));
            System.out.println("users=" + rs.getLong(2) + " tickets=" + rs.getLong(3));
        }
    }

    private static String env(String name, String fallback) {
        String v = System.getenv(name);
        return v == null || v.isBlank() ? fallback : v;
    }
}
