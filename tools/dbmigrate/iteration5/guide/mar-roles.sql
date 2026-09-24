-- mar-roles.sql: application logins for the MasterAntiqueRepair database. Run once, as the database owner.
-- The passwords are read from the environment variables APP_PW and RO_PW, never written in this file.
\set ON_ERROR_STOP on
\getenv app_pw APP_PW
\getenv ro_pw RO_PW

-- Read/write login for the application.
CREATE ROLE mar_app LOGIN PASSWORD :'app_pw';
GRANT CONNECT ON DATABASE masterantique TO mar_app;
GRANT USAGE ON SCHEMA public TO mar_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mar_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mar_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mar_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO mar_app;

-- Read-only login for reports and ad-hoc tools.
CREATE ROLE mar_readonly LOGIN PASSWORD :'ro_pw';
GRANT CONNECT ON DATABASE masterantique TO mar_readonly;
GRANT USAGE ON SCHEMA public TO mar_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO mar_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO mar_readonly;
