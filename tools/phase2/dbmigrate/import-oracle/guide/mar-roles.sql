-- mar-roles.sql: application logins for the MasterAntiqueRepair database. Run once, as SYS in the container.
-- The passwords arrive as the substitution variables app_pw and ro_pw, defined on standard input just before this script
-- (see the guide), never written in this file. SET VERIFY OFF keeps SQL*Plus from echoing them.
SET VERIFY OFF
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = FREEPDB1;

-- Read/write login for the application. Schema privileges (Oracle 23ai and later) cover every table in the schema,
-- including tables added later.
CREATE USER mar_app IDENTIFIED BY "&app_pw" DEFAULT TABLESPACE users;
GRANT CREATE SESSION TO mar_app;
GRANT SELECT ANY TABLE, INSERT ANY TABLE, UPDATE ANY TABLE, DELETE ANY TABLE ON SCHEMA masterantique TO mar_app;

-- Read-only login for reports and ad-hoc tools.
CREATE USER mar_readonly IDENTIFIED BY "&ro_pw" DEFAULT TABLESPACE users;
GRANT CREATE SESSION TO mar_readonly;
GRANT SELECT ANY TABLE ON SCHEMA masterantique TO mar_readonly;
EXIT
