# Controller use cases: the actions Phase 1 permits

The Phase 2 REST API is confined to the use cases of the Phase 1 application, not CRUD on every table. This list is
derived from the legacy pages' markup and code-behind (`master-antique-repair/MasterAntiqueRepair/MasterAntiqueRepair/Account/*.aspx(.cs)`
and `*.aspx(.cs)`), the web project's `App_Code/` (`AuthService`, `RepairAuthHelper`, `IpThrottle`, `IdentityModels`),
`Site.master`, and the data project's `MasterAntiqueRepairData/App_Code/` (domain classes, `Services/`, `Repositories/`,
`IdentityConfig`, `AuditLog`). A page's role is checked by `RepairAuthHelper.RequireRole`. Actions are numbered in page
order (Account pages, then the other pages, each alphabetically; within a page, in markup order).

Status: approved

## Anyone (not signed in)

1. **Sign up as a customer** (`Account/CustomerSignUp`): username, password and confirmation. The username is required
   and must be unique among active users; the password must be 8 to 128 characters with at least one letter, one digit
   and one non-alphanumeric character; the confirmation must match. Creates a Customer with `CreatedAt` now, assigns the
   `Customer` role, and signs them in. Audit CreateUser (actor: the new customer, entity: User). Failed attempts count
   towards the per-IP limit (`signup` scope).
2. **Request a password reset** (`Account/ForgotPassword`): username. Unknown username returns "No account found with
   that username." Otherwise generates a reset token valid for 1 hour and returns the reset link itself (no email is
   configured). Audit RequestPasswordReset (actor and entity: that user). Every request counts towards the per-IP limit
   (`forgotpassword` scope).
3. **Log in** (`Account/Login`): username and password. Rejects a soft-deleted user and a wrong password with the same
   "Invalid username or password."; rejects a locked account (5 failed attempts lock it for 15 minutes). Success resets
   the failed-attempt count and signs the user in. Audit Login (actor and entity: that user). Failures count towards the
   per-IP limit (`login` scope). The page then sends the user to their role's view.
4. **Check a reset link** (`Account/ResetPassword`, on load): user id and token; says whether the token is valid for
   that user.
5. **Reset the password with a token** (`Account/ResetPassword`): user id, token, new password and confirmation (same
   password rules as 1). An invalid or expired token returns "This password reset link is invalid or has expired."
   Sets the password and resets the failed-attempt count. Audit ResetPassword (actor and entity: that user).

## Customer

6. **List my tickets** (`CustomerView`): my tickets, newest first (by id descending), each with id, description,
   state and submitted date, and its comments split into employee comments and customer comments, each oldest first.
7. **Add a comment to my ticket** (`CustomerView`): ticket id and text. Only on my own ticket, and only when it is
   COMPLETED ("Comments can only be added to completed tickets."). Text: required, trimmed, at most 2,000 characters, no
   control characters other than CR, LF and TAB. Audit AddComment (actor: the customer, entity: Comment).
8. **Submit a repair** (`SubmitRepair`): description, with the same text rules as 7. Creates a ticket for me in state
   SUBMITTED with the submitted date now. Audit CreateTicket (actor: the customer, entity: Ticket).

## Employee

9. **List unassigned tickets** (`EmployeeView`): tickets with no assignee, by id, with id, description and submitted
   date.
10. **List my assigned tickets** (`EmployeeView`): tickets assigned to me, by id, with state and the comments split into
    employee and customer comments, each oldest first.
11. **Take a ticket ("Assign to Me")** (`EmployeeView`): ticket id. Only if the ticket has no assignee (otherwise
    nothing happens). Assigns it to me, sets it INPROGRESS with the assigned date now. Audit AssignTicket (actor: the
    employee, entity: Ticket).
12. **Mark a ticket complete** (`EmployeeView`): ticket id and an optional comment. Only on a ticket assigned to me
    (otherwise nothing happens). Sets it COMPLETED with the completed date now; a non-blank comment is added with the
    rules of 7. Audit CompleteTicket only (the comment gets no AddComment row).
13. **Add a comment to my assigned ticket** (`EmployeeView`): as 7, but only on a ticket assigned to me. Audit
    AddComment (actor: the employee).

## Manager

14. **Audit log** (`AuditLogView`): all audit rows, newest first, optionally filtered by entity id (matching any entity
    type), 10 or 20 rows per page. Each row: timestamp, actor's username, action, entity type, entity id, and for Ticket
    and Comment rows the ticket id to open (a Comment row's ticket is looked up from the comment; none if it is gone).
15. **List active employees** (`ManagerView`): employees not soft-deleted, by username (id and username).
16. **Add an employee** (`ManagerView`): username, password and confirmation, with the rules of 1. Creates an Employee
    with `CreatedAt` now and assigns the `Employee` role. Audit CreateUser (actor: the manager, entity: User).
17. **Edit an employee** (`ManagerView`): employee id, username, and optionally a new password with confirmation. The
    username is required and unique among other active users; a new password follows the rules of 1 and replaces the
    old one outright. "That employee no longer exists." if the id is not an employee. Audit EditUser (actor: the
    manager, entity: User).
18. **Delete an employee** (`ManagerView`): employee id. Soft delete (sets `DeletedAt` now); their tickets, comments and
    audit rows are kept and the username becomes free. Audit DeleteUser (actor: the manager, entity: User).
19. **List active customers** (`ManagerView`): customers not soft-deleted, by username (id and username).
20. **Add a customer** (`ManagerView`): as 16, creating a Customer with the `Customer` role. Audit CreateUser.
21. **Edit a customer** (`ManagerView`): as 17 for a customer ("That customer no longer exists."). Audit EditUser.
22. **Delete a customer** (`ManagerView`): as 18 for a customer. Audit DeleteUser.
23. **View an employee's tickets** (`ManagerView`): employee id; the employee's username and the tickets assigned to
    them, by id.
24. **List unassigned tickets with their customer** (`ManagerView`): as 9, plus each ticket's customer.
25. **Metrics** (`Metrics`): nothing if no ticket is completed. Otherwise, over a 7-day window ending today (starting no
    earlier than the first completion): completions per day per active employee (zero-filled, employees by username),
    the period total, average completions per day, tickets created in the period and per day, the completed/created
    ratio (none when nothing was created), the most productive day, the number of days with no completions, the busiest
    employee, comments in the period (total, per day, by employees, by customers, per commenter username), and the most
    commented ticket.
26. **Look up a ticket** (`TicketDetailView`): a picker listing every ticket by id (id and description); by id, the
    ticket's description, state, customer, assignee, submitted/assigned/completed dates, and its comments split into
    employee and customer comments, each oldest first. "Not found" for an unknown id.
27. **Look up a customer** (`TicketDetailView`): a picker listing every customer by id, soft-deleted ones included and
    marked; by id, the customer's username, created date, deleted flag and tickets (newest first).
28. **Look up an employee** (`TicketDetailView`): as 27 for employees; the tickets assigned to them, by id.
29. **Text search** (`TicketDetailView`): search text, trimmed and required ("Enter some text to search for."). Returns
    comments whose text contains it and tickets whose description contains it, newest first, each with type (Comment or
    Ticket Description), the text, the author's username (the commenter, or the ticket's customer), the date posted and
    the ticket id.

## Rules the legacy code enforces

- **Roles come from `user_roles`, not the discriminator.** `RepairAuthHelper.RequireRole` checks `User.IsInRole`, whose
  role claims are built from the user's `user_roles` rows at sign-in (`RepairAuthHelper.SignIn`). Every user gets exactly
  one role when created (`AuthService.SignUp`, `AccountService.AddEmployee`/`AddCustomer` call `AddToRole`). The
  discriminator separately decides what a user can do: the services look users up with `OfType<Customer>()`,
  `OfType<Employee>()` or `OfType<Manager>()` (`UserRepository`). `roles` and `user_roles` are therefore in use;
  `user_claims` and `user_logins` are ASP.NET Identity tables no page uses (0 rows).
- **Comments are add-only.** `CommentService` (comment at line 5): "Edit/Delete were removed from the app entirely".
  `User.EditComment` and `User.DeleteComment` still exist but nothing calls them, and the audit codes EditComment and
  DeleteComment remain in `AuditLog.ActionType` unused.
- **Comments on completed tickets only**: `User.AddComment` throws unless the ticket is COMPLETED. A customer comments
  only on their own tickets (`TicketRepository.GetByIdForCustomer`), an employee only on tickets assigned to them
  (`GetByIdForEmployee`).
- **Managers cannot comment or take tickets**: `Manager` inherits from `User`, not `Employee`; no manager page offers
  either, and the services resolve the actor with `GetEmployeeById`/`GetCustomerById`.
- **Workflow**: SUBMITTED -> INPROGRESS (take, 11) -> COMPLETED (complete, 12). `Employee.TakeTicket` checks only that
  the ticket has no assignee, and `Employee.CompleteTicket` only that it is assigned to this employee; neither checks the
  current state. There is no ticket edit, delete, reassignment or reopening.
- **Soft delete**: `User.Delete` sets `DeletedAt`. A deleted user cannot log in (`AuthService.Login`), is left out of the
  active lists (15, 19, 25) but included in lookups (26-28, `SearchService`), and frees the username
  (`IdentityConfig.ActiveUsernameValidator` plus the filtered unique index on `Users.Name`).
- **Text rules**: ticket descriptions (`Ticket.CreateSubmitted`) and comments (`User.ValidateCommentText`) are required,
  trimmed, at most 2,000 characters, with no control characters other than CR, LF and TAB.
- **Silent no-ops**: `TicketService.SubmitTicket`, `AssignToMe`, `CompleteTicket` and `CommentService.Add*Comment` return
  without an error when the user or ticket does not resolve or the ticket is not theirs. The Phase 2 API needs an
  explicit response for these (for example not found or conflict); that is a Phase 2 decision.
- **Unclear: completing with an invalid comment.** In 12, an over-long or invalid comment makes `User.AddComment` throw
  `ArgumentException`, which `EmployeeView.ConfirmComplete_Click` does not catch (the page errors).
- **Audit rows** (`AuditLogger.Log`): timestamp (local time, `DateTime.Now`), actor, action, entity type and entity id,
  never comment text or descriptions. `ActionType` ordinals: CreateUser 0, Login 1, CreateTicket 2, AssignTicket 3,
  CompleteTicket 4, AddComment 5, EditComment 6, DeleteComment 7, RequestPasswordReset 8, ResetPassword 9, EditUser 10,
  DeleteUser 11; `EntityKind`: User 0, Ticket 1, Comment 2. Manager account actions (16-18, 20-22) are audited only if
  the actor resolves to a Manager (`AccountService.LogIfManager`).
- **Rate limits**: `IpThrottle` blocks an IP for 15 minutes after 20 attempts within 15 minutes, per scope (`login`,
  `signup`, `forgotpassword`); in memory only.
- **Security component** (`docs/phase2/security/`): actions 1-5, the password fields of 16, 17, 20 and 21, and log off
  (any signed-in user, from `Site.master`'s `LoginStatus`; no audit row) set passwords, sign people in or out. Reset
  tokens are not stored in any table: they are ASP.NET Identity data-protector tokens with a 1-hour lifespan
  (`IdentityModels.cs`), bound to the user's security stamp. The migration sets every `password_hash` and
  `security_stamp` to NULL and `must_reset_password` to true, so no legacy password or token carries over.
- **Unclear: lockout after a reset.** `AuthService.ResetPassword` calls `ResetAccessFailedCount` with the comment that
  it "also clears any existing account lockout"; that call resets the failed-attempt count but not the lockout end
  date, so a locked account may stay locked until the 15 minutes pass.
