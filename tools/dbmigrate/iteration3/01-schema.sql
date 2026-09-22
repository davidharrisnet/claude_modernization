-- MasterAntiqueRepair schema for SQLite (generated from SQL Server catalog 'aspnet-MasterAntiqueRepair-e93a6129-7f74-4486-97e8-8d4ab1a709b4')
PRAGMA foreign_keys = ON;

CREATE TABLE "Roles" (
    "Id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    "Name" VARCHAR(256) NOT NULL
);

CREATE TABLE "Users" (
    "Id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    "Name" VARCHAR(256) NOT NULL,
    "CreatedAt" DATETIME NOT NULL,
    "PasswordHash" TEXT,
    "Discriminator" VARCHAR(128) NOT NULL,
    "DeletedAt" DATETIME,
    "Email" VARCHAR(256),
    "EmailConfirmed" INTEGER NOT NULL DEFAULT 0 CHECK ("EmailConfirmed" IN (0, 1)),
    "SecurityStamp" TEXT,
    "PhoneNumber" TEXT,
    "PhoneNumberConfirmed" INTEGER NOT NULL DEFAULT 0 CHECK ("PhoneNumberConfirmed" IN (0, 1)),
    "TwoFactorEnabled" INTEGER NOT NULL DEFAULT 0 CHECK ("TwoFactorEnabled" IN (0, 1)),
    "LockoutEndDateUtc" DATETIME,
    "LockoutEnabled" INTEGER NOT NULL DEFAULT 0 CHECK ("LockoutEnabled" IN (0, 1)),
    "AccessFailedCount" INTEGER NOT NULL DEFAULT 0,
    "MustResetPassword" INTEGER NOT NULL DEFAULT 0 CHECK ("MustResetPassword" IN (0, 1))
);

CREATE TABLE "AuditLogs" (
    "Id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    "Timestamp" DATETIME NOT NULL,
    "UserId" INTEGER NOT NULL,
    "Action" INTEGER NOT NULL,
    "EntityType" INTEGER NOT NULL,
    "EntityId" INTEGER NOT NULL,
    CONSTRAINT "FK_dbo.AuditLogs_dbo.Users_UserId" FOREIGN KEY ("UserId") REFERENCES "Users" ("Id") ON DELETE CASCADE
);

CREATE TABLE "Tickets" (
    "Id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    "State" INTEGER NOT NULL,
    "Description" VARCHAR(2000),
    "User_Id" INTEGER,
    "Customer_Id" INTEGER,
    "SubmittedDate" DATETIME,
    "AssignedDate" DATETIME,
    "CompletedDate" DATETIME,
    CONSTRAINT "FK_dbo.Orders_dbo.Users_Customer_Id" FOREIGN KEY ("Customer_Id") REFERENCES "Users" ("Id") ON DELETE NO ACTION,
    CONSTRAINT "FK_dbo.Orders_dbo.Users_User_Id" FOREIGN KEY ("User_Id") REFERENCES "Users" ("Id") ON DELETE NO ACTION
);

CREATE TABLE "Comments" (
    "Id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    "UserId" INTEGER NOT NULL,
    "TicketId" INTEGER NOT NULL,
    "Text" VARCHAR(2000),
    "CreatedAt" DATETIME NOT NULL,
    CONSTRAINT "FK_dbo.Comments_dbo.Tickets_TicketId" FOREIGN KEY ("TicketId") REFERENCES "Tickets" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_dbo.Comments_dbo.Users_UserId" FOREIGN KEY ("UserId") REFERENCES "Users" ("Id") ON DELETE CASCADE
);

CREATE TABLE "UserClaims" (
    "Id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    "UserId" INTEGER NOT NULL,
    "ClaimType" TEXT,
    "ClaimValue" TEXT,
    CONSTRAINT "FK_dbo.UserClaims_dbo.Users_UserId" FOREIGN KEY ("UserId") REFERENCES "Users" ("Id") ON DELETE CASCADE
);

CREATE TABLE "UserLogins" (
    "LoginProvider" VARCHAR(128) NOT NULL,
    "ProviderKey" VARCHAR(128) NOT NULL,
    "UserId" INTEGER NOT NULL,
    PRIMARY KEY ("LoginProvider", "ProviderKey", "UserId"),
    CONSTRAINT "FK_dbo.UserLogins_dbo.Users_UserId" FOREIGN KEY ("UserId") REFERENCES "Users" ("Id") ON DELETE CASCADE
);

CREATE TABLE "UserRoles" (
    "UserId" INTEGER NOT NULL,
    "RoleId" INTEGER NOT NULL,
    PRIMARY KEY ("UserId", "RoleId"),
    CONSTRAINT "FK_dbo.UserRoles_dbo.Roles_RoleId" FOREIGN KEY ("RoleId") REFERENCES "Roles" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_dbo.UserRoles_dbo.Users_UserId" FOREIGN KEY ("UserId") REFERENCES "Users" ("Id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX "RoleNameIndex" ON "Roles" ("Name");
CREATE UNIQUE INDEX "IX_Users_Name_Active" ON "Users" ("Name") WHERE "DeletedAt" IS NULL;
CREATE INDEX "AuditLogs_IX_UserId" ON "AuditLogs" ("UserId");
CREATE INDEX "IX_Customer_Id" ON "Tickets" ("Customer_Id");
CREATE INDEX "IX_User_Id" ON "Tickets" ("User_Id");
CREATE INDEX "Comments_IX_UserId" ON "Comments" ("UserId");
CREATE INDEX "IX_TicketId" ON "Comments" ("TicketId");
CREATE INDEX "UserClaims_IX_UserId" ON "UserClaims" ("UserId");
CREATE INDEX "UserLogins_IX_UserId" ON "UserLogins" ("UserId");
CREATE INDEX "IX_RoleId" ON "UserRoles" ("RoleId");
CREATE INDEX "UserRoles_IX_UserId" ON "UserRoles" ("UserId");
