-- queries.sql: sample queries on the migrated MasterAntiqueRepair data (SQL*Plus).
SET LINESIZE 160 PAGESIZE 100 TAB OFF FEEDBACK OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = masterantique;
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF3';
SET FEEDBACK ON
COLUMN name FORMAT A12
COLUMN customer FORMAT A12
COLUMN employee FORMAT A12
COLUMN discriminator FORMAT A13
COLUMN workflow_state FORMAT A14
COLUMN description FORMAT A50
COLUMN text FORMAT A60
COLUMN created_at FORMAT A23
COLUMN timestamp FORMAT A23

-- Users by type (customers, employees, managers share one table)
SELECT discriminator, COUNT(*) FROM users GROUP BY discriminator ORDER BY discriminator;

-- Tickets by workflow state (0 SUBMITTED, 1 INPROGRESS, 2 COMPLETED)
SELECT state,
       CASE state WHEN 0 THEN 'SUBMITTED' WHEN 1 THEN 'INPROGRESS' WHEN 2 THEN 'COMPLETED' END AS workflow_state,
       COUNT(*)
FROM tickets GROUP BY state ORDER BY state;

-- Open tickets with customer and assigned employee
SELECT t.id, c.name AS customer, e.name AS employee, SUBSTR(t.description, 1, 50) AS description
FROM tickets t
JOIN users c ON c.id = t.customer_id
LEFT JOIN users e ON e.id = t.user_id
WHERE t.state <> 2
ORDER BY t.id
FETCH FIRST 5 ROWS ONLY;

-- Comments on one ticket, oldest first
SELECT cm.created_at, u.name, cm.text
FROM comments cm JOIN users u ON u.id = cm.user_id
WHERE cm.ticket_id = 1
ORDER BY cm.created_at;

-- Latest audit events
SELECT a.timestamp, u.name, a.action, a.entity_type, a.entity_id
FROM audit_logs a JOIN users u ON u.id = a.user_id
ORDER BY a.timestamp DESC
FETCH FIRST 5 ROWS ONLY;

-- Case-insensitive username lookup, the way sign-in must do it: the condition repeats the expression of the index
-- ix_users_name_active, so Oracle uses it (and soft-deleted users, whose expression is NULL, never match)
SELECT id, name, discriminator, must_reset_password
FROM users WHERE CASE WHEN deleted_at IS NULL THEN LOWER(name) END = LOWER('MANAGER');
