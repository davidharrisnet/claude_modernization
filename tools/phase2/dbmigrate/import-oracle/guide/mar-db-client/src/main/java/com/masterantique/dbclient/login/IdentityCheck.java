package com.masterantique.dbclient.login;

/**
 * Proves the person setting the first password really owns the account. Migrated users have no old
 * password to check, so a real system needs something else here: a one-time code issued by a manager,
 * or a reset link sent to a verified email address.
 */
public interface IdentityCheck {

    boolean verify(String username, String oneTimeCode);
}
