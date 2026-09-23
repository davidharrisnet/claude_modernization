# Project Status

### September 23, 2026
#### Report
Successfully converted the Windows SQL Server database to sanitized schema and data files, which were then ported to a Dockerized PostgreSQL database. 

Learned lessons about data security. Sanitization involved setting the User tables PasswordHash and SecurityStamp to NULL intrducing a MustResetPassword field set to 1. This will require users to reset their passwords the next time they log in. 
    
   See: docs/dbmigrate/iteration4
* [ITERATION4_REPORT.md](docs/dbmigrate/iteration4/ITERATION4_REPORT.md)
* [MigrationVerificationReport4.doxs](docs/dbmigrate/iteration4/MigrationVerificationReport4.doxs)
* [PostgreSQLDatabaseGuide4.docx](docs/dbmigrate/iteration4/PostgreSQLDatabaseGuide4.docs)

#### What's Next
Used Claude to create a SpringBoot 