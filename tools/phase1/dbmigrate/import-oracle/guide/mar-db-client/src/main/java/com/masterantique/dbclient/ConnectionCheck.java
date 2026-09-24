package com.masterantique.dbclient;

import com.masterantique.dbclient.model.TicketState;
import com.masterantique.dbclient.repo.AppUserRepository;
import com.masterantique.dbclient.repo.AuditLogRepository;
import com.masterantique.dbclient.repo.CommentRepository;
import com.masterantique.dbclient.repo.TicketRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** Runs at start-up (unless the first-login demo is running): proves the connection with JDBC and with JPA. */
@Component
@Profile("!first-login-demo")
public class ConnectionCheck implements CommandLineRunner {

    private final JdbcTemplate jdbc;
    private final AppUserRepository users;
    private final TicketRepository tickets;
    private final CommentRepository comments;
    private final AuditLogRepository auditLogs;

    public ConnectionCheck(JdbcTemplate jdbc, AppUserRepository users, TicketRepository tickets,
                           CommentRepository comments, AuditLogRepository auditLogs) {
        this.jdbc = jdbc;
        this.users = users;
        this.tickets = tickets;
        this.comments = comments;
        this.auditLogs = auditLogs;
    }

    @Override
    @Transactional(readOnly = true)
    public void run(String... args) {
        // 1. Plain SQL through Spring's JdbcTemplate.
        String who = jdbc.queryForObject(
                "select user || ' @ ' || sys_context('USERENV', 'CON_NAME') || ', schema '"
                        + " || sys_context('USERENV', 'CURRENT_SCHEMA') || ', Oracle '"
                        + " || (select version_full from product_component_version where rownum = 1) from dual",
                String.class);
        System.out.println("Connected: " + who);

        // 2. The same database through JPA repositories.
        System.out.printf("users=%d tickets=%d comments=%d audit_logs=%d%n",
                users.count(), tickets.count(), comments.count(), auditLogs.count());
        System.out.printf("customers=%d employees=%d managers=%d, must reset password=%d%n",
                users.countByDiscriminator("Customer"), users.countByDiscriminator("Employee"),
                users.countByDiscriminator("Manager"), users.countByMustResetPasswordTrue());
        for (TicketState s : TicketState.values()) {
            System.out.printf("tickets %s=%d%n", s, tickets.countByState(s));
        }

        // 3. Case-insensitive username lookup, as sign-in must do it.
        users.findActiveByName("MANAGER").ifPresent(u ->
                System.out.printf("findActiveByName(\"MANAGER\") -> id %d, name '%s', %s%n",
                        u.getId(), u.getName(), u.getDiscriminator()));
    }
}
