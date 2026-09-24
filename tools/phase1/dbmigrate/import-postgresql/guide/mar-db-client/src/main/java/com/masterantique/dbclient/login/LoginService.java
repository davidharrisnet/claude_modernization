package com.masterantique.dbclient.login;

import com.masterantique.dbclient.model.AppUser;
import com.masterantique.dbclient.repo.AppUserRepository;
import java.util.Optional;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.factory.PasswordEncoderFactories;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Sign-in against the migrated users table, including the forced password change every migrated user
 * meets on first login (password_hash is NULL and must_reset_password is true after the migration).
 */
@Service
public class LoginService {

    private static final Logger log = LoggerFactory.getLogger(LoginService.class);
    private static final int MIN_LENGTH = 12;

    private final AppUserRepository users;
    private final IdentityCheck identityCheck;
    // Stores "{bcrypt}$2a$10$..." so the algorithm can be changed later without breaking old hashes.
    private final PasswordEncoder encoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
    // Compared against when the user is unknown, so both cases take about the same time.
    private final String dummyHash = encoder.encode("not-a-real-password");

    public LoginService(AppUserRepository users, IdentityCheck identityCheck) {
        this.users = users;
        this.identityCheck = identityCheck;
    }

    @Transactional(readOnly = true)
    public LoginResult login(String username, String password) {
        Optional<AppUser> found = users.findActiveByName(username);
        if (found.isEmpty()) {
            encoder.matches(password, dummyHash);
            return LoginResult.INVALID;
        }
        AppUser user = found.get();
        if (user.isMustResetPassword() || user.getPasswordHash() == null) {
            return LoginResult.MUST_CHANGE_PASSWORD;
        }
        return encoder.matches(password, user.getPasswordHash()) ? LoginResult.OK : LoginResult.INVALID;
    }

    /**
     * Sets the first password. Throws IllegalArgumentException with a message fit to show the user when the
     * identity check or the password policy fails.
     */
    @Transactional
    public void changePassword(String username, String oneTimeCode, String newPassword, String confirmPassword) {
        AppUser user = users.findActiveByName(username)
                .orElseThrow(() -> new IllegalArgumentException("Unknown or inactive user."));
        if (!identityCheck.verify(user.getName(), oneTimeCode)) {
            throw new IllegalArgumentException("The one-time code is not valid.");
        }
        checkPolicy(user.getName(), newPassword, confirmPassword);
        user.setNewPassword(encoder.encode(newPassword), UUID.randomUUID().toString());
        // Saved on commit (the entity is managed). Record the event, never the password.
        log.info("Password changed for user id {} ({}); must_reset_password cleared", user.getId(), user.getDiscriminator());
    }

    static void checkPolicy(String username, String password, String confirm) {
        if (password == null || password.length() < MIN_LENGTH) {
            throw new IllegalArgumentException("The password must have at least " + MIN_LENGTH + " characters.");
        }
        if (!password.equals(confirm)) {
            throw new IllegalArgumentException("The two passwords do not match.");
        }
        if (password.toLowerCase().contains(username.toLowerCase())) {
            throw new IllegalArgumentException("The password must not contain the username.");
        }
    }
}
