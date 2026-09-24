package com.masterantique.dbclient.login;

import java.io.Console;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * Console walk-through of a migrated user's first login. Run with --spring.profiles.active=first-login-demo.
 * Asks for the values it is not given (demo.username, demo.password, demo.one-time-code, demo.new-password),
 * hiding passwords.
 */
@Component
@Profile("first-login-demo")
public class FirstLoginDemo implements CommandLineRunner {

    private final LoginService login;
    private final String username;
    private final String firstPassword;
    private final String oneTimeCode;
    private final String newPassword;

    public FirstLoginDemo(LoginService login,
                          @Value("${demo.username:}") String username,
                          @Value("${demo.password:}") String firstPassword,
                          @Value("${demo.one-time-code:}") String oneTimeCode,
                          @Value("${demo.new-password:}") String newPassword) {
        this.login = login;
        this.username = username;
        this.firstPassword = firstPassword;
        this.oneTimeCode = oneTimeCode;
        this.newPassword = newPassword;
    }

    @Override
    public void run(String... args) {
        String user = orAsk(username, "Username: ", false);
        String password = orAsk(firstPassword, "Password: ", true);   // migrated users have none yet

        LoginResult first = login.login(user, password);
        System.out.println("1. Sign in as '" + user + "' -> " + first);
        if (first == LoginResult.OK) {
            System.out.println("   Signed in. This account already has its own password.");
            return;
        }
        if (first == LoginResult.INVALID) {
            System.out.println("   Wrong username or password.");
            return;
        }

        System.out.println("   You must change your password before you continue.");
        String code = orAsk(oneTimeCode, "   One-time code from your manager: ", false);
        String pw1 = orAsk(newPassword, "   New password (12+ characters): ", true);
        String pw2 = orAsk(newPassword, "   Repeat the new password: ", true);
        try {
            login.changePassword(user, code, pw1, pw2);
            System.out.println("2. Password changed.");
        } catch (IllegalArgumentException e) {
            System.out.println("2. Not changed: " + e.getMessage());
            return;
        }

        System.out.println("3. Sign in again with the new password -> " + login.login(user, pw1));
        System.out.println("4. Sign in with a wrong password      -> " + login.login(user, pw1 + "x"));
    }

    private static String orAsk(String given, String prompt, boolean secret) {
        if (given != null && !given.isEmpty()) {
            return given;
        }
        Console console = System.console();
        if (console == null) {
            throw new IllegalStateException("No console: pass --demo.username, --demo.one-time-code and --demo.new-password");
        }
        return secret ? new String(console.readPassword(prompt)) : console.readLine(prompt);
    }
}
