-- Users by type (customers, employees, managers share one table)
SELECT discriminator, count(*) FROM users GROUP BY discriminator ORDER BY discriminator;

-- Tickets by workflow state (0 SUBMITTED, 1 INPROGRESS, 2 COMPLETED)
SELECT state,
       CASE state WHEN 0 THEN 'SUBMITTED' WHEN 1 THEN 'INPROGRESS' WHEN 2 THEN 'COMPLETED' END AS workflow_state,
       count(*)
FROM tickets GROUP BY state ORDER BY state;

-- Open tickets with customer and assigned employee
SELECT t.id, c.name AS customer, e.name AS employee, left(t.description, 50) AS description
FROM tickets t
JOIN users c ON c.id = t.customer_id
LEFT JOIN users e ON e.id = t.user_id
WHERE t.state <> 2
ORDER BY t.id
LIMIT 5;

-- Comments on one ticket, oldest first
SELECT cm.created_at, u.name, cm.text
FROM comments cm JOIN users u ON u.id = cm.user_id
WHERE cm.ticket_id = 1
ORDER BY cm.created_at;

-- Latest audit events
SELECT a.timestamp, u.name, a.action, a.entity_type, a.entity_id
FROM audit_logs a JOIN users u ON u.id = a.user_id
ORDER BY a.timestamp DESC
LIMIT 5;

-- Case-insensitive username lookup, the way sign-in must do it (uses ix_users_name_active)
SELECT id, name, discriminator, must_reset_password
FROM users WHERE lower(name) = lower('MANAGER') AND deleted_at IS NULL;
