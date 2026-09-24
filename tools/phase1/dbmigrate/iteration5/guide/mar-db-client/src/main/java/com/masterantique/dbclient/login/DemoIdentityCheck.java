package com.masterantique.dbclient.login;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * DEMO ONLY: accepts one fixed code from configuration (demo.issued-code, default DEMO-1234). Replace with a
 * real one-time-code or email-link check before anything goes near production.
 */
@Component
public class DemoIdentityCheck implements IdentityCheck {

    private static final Logger log = LoggerFactory.getLogger(DemoIdentityCheck.class);

    private final String expectedCode;

    public DemoIdentityCheck(@Value("${demo.issued-code:DEMO-1234}") String expectedCode) {
        this.expectedCode = expectedCode;
    }

    @Override
    public boolean verify(String username, String oneTimeCode) {
        log.warn("DEMO identity check used for '{}': replace DemoIdentityCheck before production", username);
        return expectedCode.equals(oneTimeCode);
    }
}
