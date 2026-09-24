package com.masterantique.dbclient.login;

public enum LoginResult {
    /** Username and password match; the user may continue. */
    OK,
    /** The account exists but has no usable password yet (every migrated user): send to "change password". */
    MUST_CHANGE_PASSWORD,
    /** Unknown user or wrong password. Deliberately the same answer for both. */
    INVALID
}
