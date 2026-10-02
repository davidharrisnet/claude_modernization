# View contract: the Phase 2 Angular pages

The Phase 2 Angular view reproduces the pages of the Phase 1 Web Forms application, confined to the actions of the
approved controller contract. This file was derived from the legacy pages' markup and code-behind
(`master-antique-repair/MasterAntiqueRepair/MasterAntiqueRepair/Account/*.aspx(.cs)` and `*.aspx(.cs)`), `Site.master`
and `Site.Master.cs`, the web project's `App_Code/` (`RepairAuthHelper`, `IdentityModels.cs`, `UiHelpers`,
`Startup.Auth.cs`, `BundleConfig.cs`), `Bundle.config` and `Content/Site.css`, and built against
`docs/phase2/controller/CONTROLLER.md` (Status: approved, actions 1 to 29). The decisions behind its rules are in
`EXPORT_VIEW_DECISIONS.md`; the styling is in `STYLE.md`. "Action n" always means CONTROLLER.md action n.

Status: proposed

## Navigation

### Header (every page)

A fixed dark navbar across the top, content in a centred container below it.

- **Brand** (left): a wrench icon and "Home", linking to the home route `/`.
- **Menu** (left, after the brand). Each item is shown only to its role; nobody sees an item of another role:

  | Label | Route | Role |
  |---|---|---|
  | "My Repairs" | `/customer-view` | Customer |
  | "My Tickets" | `/employee-view` | Employee |
  | "Administration" | `/manager-view` | Manager |
  | "Audit Log" | `/audit-log-view` | Manager |
  | "Search" | `/ticket-detail-view` | Manager |
  | "Metrics" | `/metrics` | Manager |

- **Right side, not signed in**: "Sign up" (`/account/customer-sign-up`), "Log in" (`/account/login`).
- **Right side, signed in**: the text "Hello, {username}!" and a "Log off" link. Log off signs the user out (security
  component; no audit row) and goes to `/`.
- **Collapsed on narrow screens** behind a toggle button.
- The header needs the signed-in user's username and role. CONTROLLER.md has no "current user" action; this comes from
  the security component (see Decisions made on this run).

### Footer (every page)

A horizontal rule, then "© {current year} - Master Antique Repair", kept at the bottom of the viewport on short pages.

### Page title

Every route sets the document title to "{Page title} - Master Antique Repair", using the page title given under each
page below.

### Landing routes

| Event | Destination |
|---|---|
| Login succeeds with a valid return URL | that return URL |
| Login succeeds, no return URL | Employee `/employee-view`; Manager `/manager-view`; Customer `/customer-view`; otherwise `/` (legacy checks the user type in that order) |
| Sign-up succeeds | `/customer-view` (signed in as the new customer); a return URL is not used |
| Submit a repair succeeds | `/customer-view` |
| Log off | `/` |
| First login that requires a password change | the password change screen (Phase 2 additions) before anything else |

**Return URL rule**: accepted only when it is an internal application route (starts with a single `/`, not `//` or
`/\`, no scheme). Anything else is ignored and the role's landing route is used. This is the legacy
`IdentityHelper.IsLocalUrl` rule.

### Access to protected routes

- **Not signed in**: go to `/account/login` with the requested route as return URL (legacy: `RepairAuthHelper.RequireRole`
  redirects to the login page).
- **Signed in, wrong role**: show the "not authorised" page (Phase 2 additions). Legacy redirected to the login page;
  this is a deliberate parity change (EXPORT_VIEW_DECISIONS §5).
- **API 401**: clear the signed-in state, go to `/account/login` with the current route as return URL.
- **API 403**: show the "not authorised" page.
- These checks only decide what the UI shows. The server enforces every role check for every action.

## Pages

### 1. Sign up

- **Route**: `/account/customer-sign-up` (legacy `Account/CustomerSignUp.aspx`)
- **Access**: anyone. A signed-in user may open it (legacy has no check).
- **Page title**: "Sign Up"
- **Layout**:
  - Heading "Sign Up."
  - Error message area (danger text), empty until the server rejects the sign-up.
  - Horizontal form:
    - Sub-heading "Create an account to submit and track repair requests.", then a horizontal rule.
    - Validation summary (danger text) listing the client-side errors.
    - "User name": text input, autocomplete `username`.
    - "Password": password input, autocomplete `new-password`.
    - "Confirm password": password input, autocomplete `new-password`.
    - Button "Sign Up" (primary).
- **Actions**: "Sign Up" -> action 1. On success go to `/customer-view`.
- **Text**:
  - Client-side: "The user name field is required.", "The password field is required.", "The confirm password field
    is required.", "The password and confirmation password do not match."
  - Server (action 1): the rate-limit message "Too many sign-up attempts from this location. Please try again later.",
    "That username is already taken.", "The user name field is required.", and the password-policy messages, shown in
    the error area.
- **Lists**: none.
- **Dates and numbers**: none.
- **Accessibility fixes**:
  - Legacy shows each client-side error twice (in the summary and next to the field). Phase 2 shows it next to the
    field, tied with `aria-describedby`, sets `aria-invalid`, and puts the server error in a `role="alert"` region.
  - Sub-heading is `h4` directly under the page heading (skips a level): make it a paragraph or `h2` under the `h1`.
- **Security notes**: the error area is an unencoded `asp:Literal` carrying `AuthService`/Identity exception messages
  (fixed strings, no user input echoed). Sign-up is a security-component screen; failures count towards the per-IP
  `signup` limit (server).

### 2. Forgot password

- **Route**: `/account/forgot-password` (legacy `Account/ForgotPassword.aspx`)
- **Access**: anyone.
- **Page title**: "Forgot Password"
- **Layout**:
  - Heading "Forgot Password."
  - Paragraph "Enter your username and we'll generate a password reset link."
  - Result area (hidden until a request is made):
    - Result message paragraph.
    - When a link was generated: a button-styled link whose text and target are the full reset URL; then muted text
      with an info icon: "This app has no email configured, so the reset link is shown here directly instead of being
      emailed. This link expires in 1 hour and can only be used once."
  - Horizontal form: "User name" text input (autocomplete `username`); button "Request reset link" (primary).
- **Actions**: "Request reset link" -> action 2. The reset URL points to `/account/reset-password` with the query
  parameters `userId` and `code` from the action's result.
- **Text**:
  - Client-side: "The user name field is required."
  - Results: "A reset link was generated for that account.", "No account found with that username.", and the
    rate-limit message "Too many requests from this location. Please try again later."
- **Lists**: none. **Dates and numbers**: none.
- **Accessibility fixes**: put the result area in a `role="status"` live region and move focus to it after the
  request; the info icon is decorative (`aria-hidden`); field error tied with `aria-describedby`.
- **Security notes**:
  - The result message is an unencoded `asp:Literal` (fixed strings).
  - **Risk carried forward**: the reset link is shown to whoever typed the username, and "No account found with that
    username." reveals which usernames exist. Kept for parity; to be decided by the security component.
  - The reset token travels in the URL query string (browser history, logs, `Referer`). Same risk owner.

### 3. Log in

- **Route**: `/account/login` (legacy `Account/Login.aspx`); optional query parameter `returnUrl`.
- **Access**: anyone.
- **Page title**: "Log in"
- **Layout**:
  - Heading "Log in."
  - Section with a horizontal form:
    - Sub-heading "Use a local account to log in.", then a horizontal rule.
    - Error message (danger text), hidden until login fails.
    - "User name": text input. "Password": password input.
    - Button "Log in" (primary).
  - Paragraph: link "Sign up" (to `/account/customer-sign-up`) followed by " if you're a customer without an account
    yet."
  - Paragraph: link "Forgot your password?" (to `/account/forgot-password`).
- **Actions**: "Log in" -> action 3, then the landing rules under Navigation (or the first-login password change).
- **Text**:
  - Client-side: "The user name field is required.", "The password field is required."
  - Server (action 3): "Invalid username or password.", "This account is temporarily locked due to repeated failed
    login attempts. Please try again later.", "Too many login attempts from this location. Please try again later."
- **Lists**: none. **Dates and numbers**: none.
- **Accessibility fixes**: error in a `role="alert"` region; field errors tied with `aria-describedby`; sub-heading
  level as on page 1.
- **Security notes**:
  - Both legacy fields have `autocomplete="off"`. Phase 2 uses `username` and `current-password` (deliberate change,
    EXPORT_VIEW_DECISIONS §6).
  - The error is an unencoded `asp:Literal` (fixed strings).
  - Legacy passes the return URL on to the sign-up link, but sign-up ignores it; Phase 2 does not pass it.
  - Return URL limited to internal routes (Navigation).

### 4. Reset password

- **Route**: `/account/reset-password` (legacy `Account/ResetPassword.aspx`); query parameters `userId` and `code`.
- **Access**: anyone.
- **Page title**: "Reset Password"
- **Layout**:
  - Heading "Reset Password."
  - Error area (hidden by default): danger text with the message, then a link "Request a new reset link" (to
    `/account/forgot-password`).
  - Success area (hidden by default): success text with a check icon: "Your password has been reset. " followed by a
    link "Log in" (to `/account/login`) and " with your new password."
  - Form (shown unless the link is invalid or the reset succeeded):
    - "New password": password input, autocomplete `new-password`.
    - "Confirm password": password input, autocomplete `new-password`.
    - Button "Reset password" (primary).
- **Actions**: on load -> action 4 (an invalid link hides the form and shows the error); "Reset password" -> action 5
  (success hides the form and shows the success area).
- **Text**:
  - Client-side: "The new password field is required.", "The confirm password field is required.", "The password and
    confirmation password do not match."
  - Server: "This password reset link is invalid or has expired." (invalid or expired token, from action 4 or 5); the
    password-policy messages from action 5 (form stays visible).
- **Lists**: none. **Dates and numbers**: none.
- **Accessibility fixes**: error area `role="alert"`, success area `role="status"` with focus moved to it; check icon
  decorative; field errors tied with `aria-describedby`.
- **Security notes**: the error is an unencoded `asp:Literal` (fixed strings and Identity password-policy messages).
  Token in the URL (see page 2). A non-numeric `userId` is treated as 0 by the legacy page, which makes the token
  invalid.

### 5. Audit log

- **Route**: `/audit-log-view` (legacy `AuditLogView.aspx`)
- **Access**: Manager.
- **Page title**: "Audit Log"
- **Layout**:
  - Heading "Audit Log."
  - Inline form (space below it):
    - "Entity Id": text input.
    - Button "Search" (primary); button "Clear" (link style).
    - "Rows per page": select with "10" (default) and "20"; changing it reloads the list at page 1.
  - Table with columns, in order: "Timestamp", "User", "Action", "Entity", "Entity Id", and an unlabelled column with a
    "View" link (link style, extra small).
  - Pager below the table, centred: numeric page links, up to 10 at a time, with "First" and "Last".
  - Empty table text: "No activity logged yet."
- **Actions**:
  - List, search, clear, rows per page, paging -> action 14.
  - "View": shown on Ticket rows (to `/ticket-detail-view?id={entity id}`) and on Comment rows whose ticket still
    exists (to `/ticket-detail-view?id={that ticket id}`); not shown otherwise. Opens page 12 (action 26).
- **Text**: as above. "Action" and "Entity" show the audit code names (for example AssignTicket, Ticket).
- **Lists**: newest first; 10 or 20 rows per page; filter by entity id (any entity type). A non-numeric entity id is
  treated as no filter (legacy `int.TryParse`). Search and Clear reset to page 1.
- **Dates and numbers**: Timestamp `{0:g}` (short date and short time). Audit timestamps are server local time; show
  the time zone in the column header or a note.
- **Accessibility fixes**: the unlabelled column gets a visually hidden header ("Open"); each "View" link gets an
  accessible name naming the ticket ("View ticket #12"); the pager is a `nav` with an `aria-label` and
  `aria-current="page"` on the current page; the table gets a caption (visually hidden is fine).
- **Security notes**: none on the page (bound fields are encoded).

### 6. My repairs

- **Route**: `/customer-view` (legacy `CustomerView.aspx`)
- **Access**: Customer.
- **Page title**: "My Repairs"
- **Layout**:
  - Heading "My Repairs."
  - Button-styled link "Submit a new repair request" (primary) to `/submit-repair`.
  - Sub-heading "My Repair Requests".
  - Table with columns, in order:
    - "Id"
    - "Description"
    - "Status": a status badge (see STYLE.md) with the state name (SUBMITTED, INPROGRESS, COMPLETED).
    - "Submitted"
    - "Employee Comments": a bulleted list of comments by employees; each shows the first 60 characters (then "...")
      as a popover trigger whose popover shows the full text, followed by the small text "({created date})".
    - "Customer Comments": the same list for comments by customers; then, only when the ticket is COMPLETED, a button
      "Add Comment" (info, small).
  - Empty table text: "You haven't submitted any repair requests yet."
  - Modal "Add Comment": close button (×); error text (danger, hidden until an error); "Comment": multi-line text
    (3 rows); footer buttons "Cancel" (secondary, closes) and "Post Comment" (primary).
- **Actions**: table -> action 6; "Submit a new repair request" -> page 11; "Post Comment" -> action 7 for the
  ticket whose button opened the modal. On success the modal closes, the text clears and the table reloads; on error
  the message shows in the modal.
- **Text**: server messages of action 7, for example "Comments can only be added to completed tickets." and the
  comment text rules.
- **Lists**: tickets newest first (id descending); comments oldest first in each column.
- **Dates and numbers**: Submitted `{0:g}`; comment dates `{0:g}`.
- **Accessibility fixes**:
  - Popover trigger: legacy `span` with `role="button"` and `tabindex="0"`; Phase 2 uses a `button` (shows the
    truncated text, opens the full text on focus or click).
  - "Add Comment" buttons repeat the same text on every row: give each an accessible name with the ticket id ("Add
    comment to ticket #12").
  - Modal: focus moves into it, is trapped, and returns to the opening button on close; the error is announced
    (`role="alert"`).
- **Security notes**: comment text is encoded in both the popover and the cell. The modal error is an `asp:Label`,
  which writes its text unencoded; it carries `CommentService`/`User.AddComment` exception messages (fixed strings).

### 7. Home

- **Route**: `/` (legacy `Default.aspx`)
- **Access**: anyone.
- **Page title**: "Home Page"
- **Layout**:
  - Hero panel (primary background, centred):
    - Heading with a wrench icon: "Master Antique Repair".
    - Lead paragraph "Bring your antiques back to life. Submit a repair request and we'll take it from there."
    - Not signed in: button-styled links "Sign Up" (success, large, to `/account/customer-sign-up`) and "Log In"
      (secondary, large, to `/account/login`).
    - Signed in: one button-styled link (success, large): Manager "Go to Administration" (`/manager-view`), else
      Employee "Go to My Tickets" (`/employee-view`), else Customer "Go to My Repairs" (`/customer-view`). Legacy
      checks the role in that order.
  - Three centred columns, each with a large icon, a sub-heading and a paragraph:
    - inbox icon (primary colour), "Submit", "Describe the item and the repair it needs."
    - wrench icon (info colour), "Repair", "An employee picks it up and gets to work."
    - check-circle icon (success colour), "Complete", "Track status and leave comments once it's done."
- **Actions**: none (navigation only; the role comes from the signed-in state).
- **Text**: as above.
- **Lists**: none. **Dates and numbers**: none.
- **Accessibility fixes**: the legacy icons sit alone inside `h2` elements (empty headings for a screen reader) and
  the column titles are `h4` under them; Phase 2 makes the icons decorative (`aria-hidden`, not headings) and the
  column titles `h2` under the page's `h1`. Check the contrast of white text on the primary hero background.
- **Security notes**: none.

### 8. My tickets

- **Route**: `/employee-view` (legacy `EmployeeView.aspx`)
- **Access**: Employee.
- **Page title**: "My Tickets"
- **Layout**:
  - Heading "My Tickets."
  - Sub-heading "Unassigned Tickets".
  - Table: "Id", "Description", "Submitted", and an unlabelled column with a button "Assign to Me" (success, small).
    Empty text: "No unassigned tickets right now."
  - Sub-heading "My Tickets".
  - Table with columns, in order:
    - "Id", "Description"
    - "Status": status badge
    - "Assigned", "Completed"
    - "Employee Comments": comment list as on page 6; then, only when the ticket is COMPLETED, a button "Add Comment"
      (info, small).
    - "Customer Comments": comment list as on page 6.
    - "Complete": only when the ticket is not COMPLETED, a button "Mark Complete" (success, small).
    - Empty text: "You haven't picked up any tickets yet."
  - Modal "Complete Repair": close button (×); a paragraph with the ticket's description (as plain text); "Employee
    Comment": multi-line text (3 rows, optional); footer "Cancel" (secondary) and "Mark Complete" (success).
  - Modal "Add Comment": as on page 6.
- **Actions**:
  - Unassigned table -> action 9; "Assign to Me" -> action 11, then both tables reload.
  - My Tickets table -> action 10.
  - "Mark Complete" (modal) -> action 12 with the optional comment, then both tables reload.
  - "Post Comment" -> action 13; behaviour as on page 6.
- **Text**: server messages of actions 12 and 13 (comment text rules, "Comments can only be added to completed
  tickets."). Legacy action 11 and 12 failures are silent (CONTROLLER.md "Silent no-ops"); Phase 2 shows whatever
  error the API returns.
- **Lists**: unassigned by id; my tickets by id; comments oldest first.
- **Dates and numbers**: Submitted, Assigned, Completed and comment dates `{0:g}`; an empty date shows nothing.
- **Accessibility fixes**: as page 6 for popovers, repeated buttons ("Assign ticket #12 to me", "Mark ticket #12
  complete", "Add comment to ticket #12") and modals; visually hidden header for the unlabelled column.
- **Security notes**: the description is passed to the modal with `JavaScriptStringEncode` and set as `innerText`
  (safe); Phase 2 binds it by interpolation. Legacy crashes on an invalid completion comment (CONTROLLER.md "Unclear:
  completing with an invalid comment"); Phase 2 shows the API's error in the modal.

### 9. Administration

- **Route**: `/manager-view` (legacy `ManagerView.aspx`)
- **Access**: Manager.
- **Page title**: "Administration"
- **Layout**:
  - Heading "Administration" (no full stop, unlike the other pages).
  - Collapsible card "Employee Management" (collapsed by default; the header is a toggle with a chevron that turns when
    open). Body, two columns:
    - Left, sub-heading "Add New Employee": error text (danger), success text (success); horizontal form "User name"
      (text, autocomplete `username`), "Password" and "Confirm password" (password, `new-password`); button "Add
      Employee" (primary).
    - Right, sub-heading "Edit Employee": error and success text; horizontal form:
      - "Employee": select, first option "-- Select an employee --", then active employees by username. Choosing one
        fills "User name" and clears the password fields and messages; choosing the first option clears "User name".
      - "User name" (text), "New password" (password) with help text "Leave blank to keep the current password.",
        "Confirm new password" (password).
      - Buttons "Save Changes" (primary) and "Delete Employee" (danger). Delete asks first: "Are you sure? This
        employee will no longer be able to log in, but their existing tickets, comments, and history are kept."
  - Collapsible card "Customer Management", the same as Employee Management with "customer" in place of "employee":
    "Add New Customer", "Add Customer", "Edit Customer", "Customer", "-- Select a customer --", "Delete Customer",
    and the confirmation "Are you sure? This customer will no longer be able to log in, but their existing tickets,
    comments, and history are kept."
  - "Choose an employee to view": select, "-- Select an employee --" then active employees by username.
  - Card (hidden until an employee is chosen): header with the employee's username; a fixed-layout compact table with
    columns "Ticket Descriptions" and "Status" (120 px wide, status badge); "No tickets assigned." when empty.
  - Sub-heading "Unassigned Tickets"; table "Id", "Description", "Customer"; empty text "No unassigned tickets right
    now."
- **Actions**:
  - Employee selects -> action 15; "Add Employee" -> 16; "Save Changes" -> 17; "Delete Employee" -> 18. After each,
    both employee selects reload.
  - Customer select -> 19; "Add Customer" -> 20; "Save Changes" -> 21; "Delete Customer" -> 22.
  - "Choose an employee to view" -> action 23 (hide the card if the employee no longer exists).
  - Unassigned table -> action 24.
- **Text**:
  - Success: "Employee account created for {username}.", "Changes saved for {username}.", "{username} has been
    removed." (and the same for customers).
  - Errors: "Choose an employee first." / "Choose a customer first." (Save or Delete with nothing chosen), "That
    employee no longer exists." / "That customer no longer exists.", "The user name field is required.", "The password
    and confirmation password do not match.", "That username is already taken.", and the password-policy messages.
- **Lists**: selects by username; employee's tickets by id; unassigned by id.
- **Dates and numbers**: none.
- **Accessibility fixes**:
  - The success and error texts are not announced: `role="status"` and `role="alert"`.
  - Help text tied to "New password" with `aria-describedby`.
  - The employee card header is a plain `div`: make it a heading.
  - The browser `confirm()` dialog becomes an accessible confirmation modal with the same text (Decisions made on
    this run).
  - The collapse toggles already have `aria-expanded` and `aria-controls`; keep them (ng-bootstrap accordion does).
- **Security notes**:
  - The four error areas are unencoded `asp:Literal`s carrying `AccountService`/Identity exception messages (fixed
    strings, no input echoed). The success messages contain the username and are encoded.
  - The password fields belong to the security component (CONTROLLER.md).

### 10. Metrics

- **Route**: `/metrics` (legacy `Metrics.aspx`)
- **Access**: Manager.
- **Page title**: "Metrics"
- **Layout**:
  - Heading "Metrics."
  - When there is no data, only the muted text "No completed tickets yet - metrics will appear here once employees
    start closing tickets."
  - Otherwise:
    - Card "Tickets Closed by Employee (per day)": a line chart, one line per active employee, x axis the days of the
      period, y axis from zero, whole numbers.
    - Card "Total Tickets Closed by Employee (this period)": a bar chart, one bar per employee (same colour as their
      line), no legend, y axis from zero to the period total.
    - Two columns:
      - Left: card "Totals (this period)", a compact table of row headers and values: "Total Tickets Closed",
        "Average Closed Per Day", "Average Created Per Day", "Closed/Created Ratio", "Most Productive Day", "Busiest
        Employee", "Quiet Days (no closures)". Then card "Comment Activity (this period)": "Total Comments", "Average
        Comments Per Day", "From Employees", "From Customers", "Most Commented Ticket". Each card body is 330 px high
        and scrolls.
      - Right: card "Comments by Customer (this period)" and card "Comments by Employee (this period)", each a pie
        chart (300 by 300 px, white borders), 330 px high.
- **Actions**: everything -> action 25.
- **Text and number formats**:
  - Total Tickets Closed: integer. Average Closed Per Day, Average Created Per Day, Average Comments Per Day: `0.0`.
  - Closed/Created Ratio: "{closed} / {created} = {ratio}" with the ratio `0.00`, or "N/A" when nothing was created.
  - Most Productive Day: "{MMM d} ({count} closed)".
  - Busiest Employee: "{username} ({count} closed)" or "(none)".
  - Quiet Days: "{quiet days} of {days in period}".
  - Most Commented Ticket: "#{id} ({count} comments)" or "(none)".
  - Chart day labels `MMM d`; the bar dataset label "Tickets closed".
- **Lists**: employees by username (action 25).
- **Accessibility fixes**:
  - The four charts are canvases with no text alternative: give each an accessible name and a visually hidden data
    table (or a toggle to show the data) with the same numbers.
  - Table row headers get `scope="row"`.
  - The scrolling card bodies must be reachable by keyboard (`tabindex="0"`, with a label).
  - Chart series are told apart by colour only; the legend and the data table give the text equivalent.
- **Security notes**:
  - **Legacy defect**: "Busiest Employee" is written with an unencoded `asp:Literal` and contains the employee's
    username, which a manager sets and which has no character restriction. A username containing HTML would run as
    script in every manager's Metrics page (stored XSS). Phase 2 interpolation removes it; recorded in
    EXPORT_VIEW_DECISIONS.
  - The other Metrics values are numbers or fixed text.
  - The chart data is JSON injected into a script block (with `</` escaped); Phase 2 gets it from the API as data.
  - Chart.js 4.4.0 loads from `cdn.jsdelivr.net` with no integrity hash; Phase 2 bundles it from npm.

### 11. Submit a repair

- **Route**: `/submit-repair` (legacy `SubmitRepair.aspx`)
- **Access**: Customer. Reached from page 6's "Submit a new repair request"; not in the menu.
- **Page title**: "Submit a Repair"
- **Layout**:
  - Heading "Submit a Repair."
  - Horizontal form:
    - Sub-heading "Tell us about the item you'd like repaired.", then a horizontal rule.
    - Validation summary (danger); error text (danger, hidden until the server rejects).
    - "Description": multi-line text (4 rows).
    - Button "Submit" (primary).
- **Actions**: "Submit" -> action 8; on success go to `/customer-view`.
- **Text**: client-side "Please describe the item and the repair needed."; server: the description text rules of
  action 8.
- **Lists**: none. **Dates and numbers**: none.
- **Accessibility fixes**: as page 1 (one error per field, tied with `aria-describedby`; server error `role="alert"`;
  sub-heading level).
- **Security notes**: the error text is encoded. Legacy silently stays on the page if the ticket is not created
  (CONTROLLER.md "Silent no-ops"); Phase 2 shows the API's error.

### 12. Search

- **Route**: `/ticket-detail-view` (legacy `TicketDetailView.aspx`); optional query parameters `id`, `customerId`,
  `employeeId`.
- **Access**: Manager.
- **Page title**: "Search"
- **Layout**:
  - Heading "Search."
  - Two columns: on the left (3 of 12) vertical pills "Ticket Search", "Customer Search", "Employee Search", "Comment
    Search"; on the right (9 of 12) the selected panel. The initial tab is Employee Search when `employeeId` is given,
    otherwise Customer Search when `customerId` is given, otherwise Ticket Search.
  - **Ticket Search** panel:
    - Sub-heading "Ticket Search". Inline form: "Choose a ticket" select ("-- Select a ticket --", then
      "#{id} - {description, first 40 characters then ...}" for every ticket by id; choosing one shows it), "Or enter a
      Ticket Id" text input, button "Search" (primary).
    - Not found (danger): "No ticket found with that Id." (also for a non-numeric id).
    - Ticket: sub-heading "Ticket #{id}", then a description list: "Description", "Status" (status badge), "Customer"
      (the username as a link to `?customerId={id}`, or "(none)"), "Assigned To" (the username as a link to
      `?employeeId={id}`, or "(unassigned)"), "Submitted", "Assigned", "Completed".
    - "Employee Comments" followed by "({assignee username link})" when assigned, then the comment list as on page 6,
      or "(none)".
    - "Customer Comments" followed by "({customer username link})", then the comment list, or "(none)".
  - **Customer Search** panel:
    - Sub-heading "Customer Search". Inline form: "Choose a customer" select ("-- Select a customer --", then
      "#{id} - {username}" plus " (deleted)" for soft-deleted ones), "Or enter a Customer Id", "Search".
    - Not found: "No customer found with that Id."
    - Customer: sub-heading "Customer #{id}" with a grey "Deleted" badge when soft-deleted; description list "Name",
      "Created"; sub-heading "Submitted Tickets"; fixed-layout compact table "Id" (60 px, link "#{id}" to
      `?id={id}`), "Description", "Status" (120 px, badge); "(none)" when empty.
  - **Employee Search** panel: as Customer Search with "employee": "Choose an employee", "-- Select an employee --",
    "Or enter an Employee Id", "No employee found with that Id.", "Employee #{id}", "Assigned Tickets".
  - **Comment Search** panel:
    - Sub-heading "Comment Search". Inline form: "Search comment text" text input, button "Search".
    - Error (danger): "Enter some text to search for." when the text is blank after trimming.
    - Fixed-layout compact table: "Type" (110 px; "Comment" or "Ticket Description"), "Text" (truncated to 80
      characters with the full text in a popover), "Author" (140 px), "Posted" (160 px), "Ticket" (80 px, link
      "#{id}" to `?id={id}`).
    - Empty: "No matching comments or ticket descriptions found."
- **Actions**: Ticket Search -> action 26; Customer Search -> 27; Employee Search -> 28; Comment Search -> 29. A link
  to another ticket, customer or employee opens this route with the query parameter and the matching tab.
- **Text**: as above.
- **Lists**: ticket select by id; customer and employee selects by id; customer's tickets newest first; employee's
  tickets by id; search results newest first; comments oldest first.
- **Dates and numbers**: Submitted, Assigned, Completed, Created, Posted and comment dates `{0:g}`.
- **Accessibility fixes**:
  - The pills are links with no tab semantics: use a tab list (`role="tablist"`, `tab`, `tabpanel`, arrow keys), as
    ng-bootstrap's nav provides.
  - Not-found and error texts in `role="alert"`.
  - Id inputs get `inputmode="numeric"`.
  - Popover triggers as on page 6.
  - Tables get captions (visually hidden is fine).
- **Security notes**:
  - Unencoded `asp:Literal`s: the status badge (built from the state enum), the person links (built in code-behind
    with the username HTML-encoded), and the search error (fixed text). Phase 2 builds these with templates, not HTML
    strings.
  - Soft-deleted users stay visible here (CONTROLLER.md actions 27 and 28).

## Phase 2 additions

1. **Change password at first login** (new, not in Phase 1: the migration invalidates every legacy password, and the
   model's `LoginService` forces a change). Route `/account/change-password`. Shown right after a login that requires
   it; no other route is reachable until it is done (except log off). Fields "New password" and "Confirm password"
   (`new-password`), button "Change password"; the password rules of action 1; then the role's landing route. Its
   server action belongs to the security component (not in CONTROLLER.md).
2. **Not authorised** (new, not in Phase 1: legacy sent a wrong-role user to the login page). Route
   `/not-authorised`, page title "Not Authorised": a heading and the text "You do not have access to this page.", a
   link to the user's landing route.
3. **Not found** (new, not in Phase 1: unknown URLs got the web server's error page). Wildcard route, page title "Not
   Found": a heading and the text "Page not found.", a link to `/`.

## Not carried forward

| Legacy item | Reason |
|---|---|
| `Site.Mobile.master`, `ViewSwitcher.ascx` | The Web Forms template's separate mobile layout; no page references them. The responsive Bootstrap 5 layout replaces them. |
| `Content/bootstrap-theme.css` | Bootstrap 3 only, and not loaded by the app (`Bundle.config` bundles only `bootstrap.css` and `Site.css`). |
| jQuery, Modernizr, `MsAjaxBundle`, `WebFormsBundle` and the `WebForms*.js` scripts (`Site.master` `ScriptManager`, `BundleConfig.cs`) | Web Forms and Bootstrap 3 plumbing; Angular and ng-bootstrap replace them. |
| `UpdatePanel` partial postbacks, `MaintainScrollPositionOnPostBack` (AuditLogView, ManagerView, TicketDetailView) | Postback mechanics; a single-page app updates in place. |
| Web Forms anti-XSRF token (`Site.Master.cs`, `ViewStateUserKey`) | Postback-specific; CSRF protection for the API is decided by the security component. |
| `autocomplete="off"` on the whole form (`Site.master`) and on the login fields | Replaced by the standard autocomplete values. |
| Browser `confirm()` for deletes (ManagerView) | Replaced by an accessible confirmation modal with the same text. |
| Chart.js from a CDN (Metrics) | Bundled from npm. |
| Return URL passed to the sign-up link (Login) | Sign-up never used it. |
| Default.aspx | **Carried forward** as the home route (page 7); listed here only because the decisions report asked. |

## Unused controller actions

None: actions 1 to 29 are all used by a page above. Log off is a security-component operation with no number in
CONTROLLER.md; it is used by the header.

## Decisions made on this run

| # | Decision | Page | Reason |
|---|---|---|---|
| 1 | Routes are the kebab-case legacy page names (`/customer-view`, `/account/customer-sign-up`, ...), home is `/` | all | Mechanical and traceable to the legacy page; one route per page |
| 2 | Query parameters keep their legacy names (`id`, `customerId`, `employeeId`, `userId`, `code`, `returnUrl`) | 4, 12, 3 | Links between pages and reset links stay recognisable |
| 3 | Add a not-found page for unknown routes | Phase 2 additions | A single-page app must handle unknown routes itself |
| 4 | Delete confirmation becomes an accessible modal with the legacy text | 9 | `confirm()` cannot be styled or tested and breaks focus handling |
| 5 | Client-side errors shown once, next to the field, instead of in both a summary and the field | 1, 3, 4, 11 | Duplicate announcements for screen readers; same messages |
| 6 | Repeated row buttons get ticket-specific accessible names; visible text unchanged | 5, 6, 8 | WCAG 2.4.6 / 4.1.2: identical names on every row |
| 7 | Every chart gets an accessible name and a data-table alternative | 10 | Canvas charts have no text alternative (WCAG 1.1.1) |
| 8 | A skip link to the main content and a `main` landmark; the navbar toggle gets the name "Toggle navigation" | header | WCAG 2.4.1; the legacy toggle has no accessible name |
| 9 | The header's username and role come from the security component | header | CONTROLLER.md has no "current user" action |
| 10 | A non-numeric audit entity id keeps meaning "no filter" | 5 | Parity with `int.TryParse` |
| 11 | Server errors for legacy silent no-ops (take, complete, submit, comment) are shown | 6, 8, 11 | The API returns explicit errors (CONTROLLER.md "Silent no-ops") |
| 12 | Busiest Employee and every other value are interpolated, removing the legacy stored XSS | 10 | Interpolation-only rule |
| 13 | The return URL is not passed on to sign-up | 3 | Sign-up ignores it in the legacy app |

## Rules for the Angular build

1. **The server is the access check.** Route guards and hidden menu items only shape the UI. Never rely on them to
   protect data or actions; the API enforces every role rule.
2. **Interpolation only.** No `innerHTML`, `outerHTML`, `bypassSecurityTrust*`, or HTML assembled from strings.
   Status badges, person links and popovers are templates or components.
3. **401** clears the signed-in state and goes to `/account/login` with the current route as return URL; **403** shows
   `/not-authorised`. Never show server error details beyond the message the API returns for the user.
4. **Return URLs** are internal routes only (Navigation).
5. **No CDN.** Bootstrap 5.3, Bootstrap Icons, ng-bootstrap and the chart library come from npm, bundled and pinned.
6. **ng-bootstrap, not Bootstrap's JavaScript**, for modals, collapses, popovers and tabs. No jQuery.
7. **Session and CSRF** follow the security component (`docs/phase2/security/`), which also owns sign-up, login,
   password reset, the first-login password change, log off and the password fields of the manager forms.
8. **Client-side validation** mirrors the server's rules for usability; the server's validation and messages win.
9. **Every control calls only the CONTROLLER.md action listed for it.** A control that needs an action not listed is
   a contract change, not an implementation detail.
10. **Exact text** as written in this file, including the trailing full stops in page headings.
11. **WCAG 2.1 AA**: apply every accessibility fix listed per page; one `h1` per page with no skipped levels;
    `lang="en"`.
12. **Styling** follows `STYLE.md`.
13. **Component tests** (the brief's Angular test suite) cover at least each page's role-dependent display and each
    form's validation messages.
