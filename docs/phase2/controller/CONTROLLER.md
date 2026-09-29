# Controller use cases: the actions Phase 1 permits

The Phase 2 REST API is confined to the use cases of the Phase 1 application, not CRUD on every table. This list is
derived from the legacy pages' markup and code-behind (`master-antique-repair/MasterAntiqueRepair/MasterAntiqueRepair/*.aspx(.cs)`,
`Account/*.aspx(.cs)`) and the domain classes in `MasterAntiqueRepairData/App_Code/`. The role is the user's
discriminator, checked by `RepairAuthHelper.RequireRole` on every page. Status: proposed, for the user to approve,
refine or extend.

## Anyone (not signed in) - `Account/`

1. **Sign up as a customer**: username and password; audit CreateUser with the new customer as the actor; signs them in.
2. **Log in**: rejects deleted users; locks the account for 15 minutes after 5 failed attempts; audit Login.
3. **Forgot password**: creates a reset token; audit RequestPasswordReset.
4. **Reset password with a token**: sets the password and clears any lockout; audit ResetPassword.

## Customer

5. **Submit a repair** (`SubmitRepair`): description of up to 2,000 characters, trimmed, no control characters; the
   ticket starts SUBMITTED with the submitted date set; audit CreateTicket.
6. **List my tickets** (`CustomerView`), newest first, each with its comments split into employee and customer comments.
7. **Add a comment** to one of my tickets; audit AddComment.
8. **Edit my own comment**; audit EditComment.
9. **Delete my own comment**; audit DeleteComment.

## Employee

10. **List all unassigned tickets** (`EmployeeView`).
11. **List my assigned tickets**, with their comments.
12. **Take ("Assign to Me") an unassigned ticket**: it becomes INPROGRESS with the assigned date set; audit AssignTicket.
13. **Mark complete** a ticket assigned to me, with an optional comment: it becomes COMPLETED with the completed date
    set; audit CompleteTicket (the optional comment gets no AddComment row).
14. **Add / edit / delete a comment**, as 7-9, but only on tickets assigned to me.

## Manager

15. **List unassigned tickets** with the customer (`ManagerView`).
16. **View an employee's tickets**.
17. **Add an employee or a customer**: username and password, unique among active users; audit CreateUser.
18. **Edit an employee or a customer**: the username, and optionally a new password; audit EditUser.
19. **Delete an employee or a customer**: soft delete; audit DeleteUser.
20. **Look up by id** (`TicketDetailView`): a ticket with its comments, a customer with their tickets, or an employee
    with their tickets.
21. **Text search** across comment text and ticket descriptions.
22. **Audit log** (`AuditLogView`): filter by entity id, newest first, paged (10 rows per page, page size selectable).
23. **Metrics** (`Metrics`): completions per employee over a rolling 7-day window, the period total and average per
    day, and tickets and comments created in the period.

## Rules the legacy code enforces

- **Comments on completed tickets only**: `User.AddComment` throws unless the ticket is COMPLETED.
- **Managers cannot comment**: no manager page offers it.
- **Managers cannot take tickets**: `Manager` inherits from `User`, not `Employee`, and taking looks the user up with
  `OfType<Employee>()`.
- **No page uses these tables**: `roles`, `user_roles`, `user_claims` and `user_logins`; authorization comes from the
  discriminator.
- **No ticket edit or delete**, and no reassignment by a manager.
- **Password reset tokens were not migrated**: action 3 depends on `PasswordResetTokens`, which is not among the eight
  tables in the migrated schema.
- **Passwords belong to the security component**: actions 1-4 and the password fields of 17-18 set passwords and sign
  people in; the controller-oracle plan leaves that to `docs/phase2/security/`. For the controller, 17 would create
  users with no password and must-reset set, as that plan already says.
