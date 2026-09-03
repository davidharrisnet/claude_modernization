# asp_modernization

A report of using Claude code to convert legacy ASP.NET to modern Java/Angular using Claude AI.


## Introduction
This repository is the report of an intertive process to investigate using Claude code to convert ASP.NET Framework 4.7.2, C#, MVC or WebForms projects into Java 21/Spring Boot 8.0.  It begins with an exeplar web forms project created by Visual Studio 2017. The asp web forms project is contained in [aspnet-webforms](https://github.com/davidharrisnet/aspnetwebforms) The full report in [RESEARCH.md](docs/RESEARCH.md) has the following format:

## Prerequisites

1. .NET Frameworks 4.7.2.  
Open [.NET Framework 4.7.2](https://support.microsoft.com/en-us/servicing/os/windows/2019/07/microsoft-net-framework-4-7-2-offline-installer-for-windows), then select "Download the Microsoft .NET Framework 4.7.2 offline installer package now."

3. Install Visual Studio 2017
* [Visual Studio 2017 via microsoft.com](https://download.visualstudio.microsoft.com/download/pr/8729ca3d-c3b2-4b32-b6fb-a7ea468a4af2/4448a86b1ae7d5b90bdc9c51e3f18b8f6ab0d3176560aa23b03f102380e02746/vs_Community.exe)

  * Using the Visual Studio Installer, select Modify, the select ASP.NET and web development
  * Add a selection to .NET Framework 4.7.2 development tools
    
### ASP.NET Projects

#### ASP.NET WEb Forms Site

1. File | New | Project | ASP.NET Web Forms Site
2. Ensure Framework is .NET Framework 4.7.2
3. This project has several components
   * aspx file: Default, Contact, About, Global
   * bootstrap style sheets
   * An Account directory with Login pages and security policies specified in the Web.config.\
   * Routing in App_Code/RouteConfig.cs

 ...
## Design
PHASE 1 — Legacy Build
Stack: ASP.NET Framework 4.7.2, C#, MVC or WebForms, SQL Server (or SQLite is fine)

Functional requirements:
•	A single core domain with 3–4 related entities (e.g., a simple case/request tracking app: Requests → Assignees → Status History)
•	Basic CRUD for each entity
•	One approval/status-transition workflow with at least 3 states (e.g., Submitted → In Review → Closed)
•	A simple login/role check (hardcoded roles are fine)
•	One list/search view with filtering and pagination

Non-functional requirements:
•	Layered architecture (UI / business logic / data access clearly separated — no logic in code-behind)
•	Server-side input validation
•	Logging of workflow state changes (this becomes your audit trail in Phase 2)
•	A short README explaining the structure and how to run it

PHASE 2 — AI-Assisted Modernization
Stack: Angular 21, Spring Boot 3, Oracle

Functional requirements:
•	Feature parity with Phase 1 (same entities, workflow, and auth boundary). Where you can't get exact 1:1 parity, note it and explain why.
•	A REST API in Spring Boot backing the Angular SPA (no server-rendered views)
•	A data migration plan/script from the SQL Server schema to Oracle or something database, noting any type or logic differences

Non-functional requirements:
•	Security: server-side validation, no secrets in source, basic protection against injection/XSS
•	Testability: at least one unit test suite per layer (Spring service layer, Angular component)
•	Maintainability: clear separation of concerns — no logic in controllers or components
•	Accessibility: basic WCAG 2.1 AA conformance on the Angular UI (labels, keyboard navigation, contrast)
•	Documentation: a short migration notes doc
•	Auditability: preserve or improve on the workflow logging from Phase 1

DELIVERABLES
1. Working legacy app matching the Phase 1 scope
2. Working modernized app matching the Phase 2 scope, with any parity gaps explained
3. A 1–2-page(s) migration notes doc: key decisions, risks you'd flag in a real migration, what you'd do differently with more time
4. A brief walkthrough of how you used Claude in the process — what you had it do, and what you double-checked or overrode


## Furthe Work
Random Samples
* https://github.com/PavlosTzitzos/asp.net-samples
* https://github.com/f2calv/WebAppDI
* https://github.com/search?q=asp.net+4.7.2&type=repositories





 



 
