# Phase 2 controller layer

The controller layer is the Spring Boot REST API of the modernized Master Antique Repair application. It exposes the
use cases of the Phase 1 application, not CRUD on every table.

| File | What it is |
|---|---|
| [CONTROLLER.md](CONTROLLER.md) | **The controller contract**: every permitted action, numbered, grouped by role, with the legacy rules it must keep. Status: proposed, awaiting approval. |
| [oracle/CLAUDE.md](oracle/CLAUDE.md) | The controller-oracle plan (run with `Run controller-oracle`): database copy, build, run and smoke test on the migrated Oracle database. Its endpoint list predates the contract and is to be rewritten from it. |
| [`.claude/agents/controller.md`](../../../.claude/agents/controller.md) | The **controller agent**, the Claude Code subagent that owns this layer. |

## The contract

`CONTROLLER.md` lists the actions Phase 1 permits, derived from the legacy pages and their code-behind: 23 actions
for anyone (sign-up, login, password reset), customers, employees and managers, plus the rules the legacy code
enforces (for example, comments only on completed tickets; only employees take tickets).

The contract belongs to the user. To add or change an operation, edit `CONTROLLER.md`:

- Keep the numbers stable: the endpoints, tests and reports cite them. Add new actions at the end of their role group
  and strike through removed ones rather than deleting them.
- Mark an action that is not Phase 1 behaviour, for example "(new, not in Phase 1: reason)", so every parity gap is
  explained.
- Change "Status: proposed" once the list is approved.

## The controller agent

The controller agent (`.claude/agents/controller.md`) handles all controller work: implementing endpoints, request
and response types, the services behind them and their tests, and reviewing plans or code against the contract. It
is available in Claude Code sessions started from this repository; ask the main session to hand it a task, for
example "have the controller agent review the controller-oracle plan against the contract".

It:

- reads the contract, the controller-oracle plan and `model/oracle`'s own instructions at the start of every task;
- implements only actions the contract lists, citing each action's number in the OpenAPI summary, the test name and
  its report, and stops and reports when a task needs an action the contract does not list;
- proposes changes to the contract but edits it only when a task asks for a specific change;
- keeps the Phase 1 rules, checking the legacy source when unsure;
- stays out of authentication and passwords (the security component), the Angular view and the migration tools;
- never writes to the delivered `mar-oracle` database and makes no git changes;
- ends with a table of action number -> endpoint -> test, any contradictions it found, and the build and test results
  it actually ran.

## Limits

- The API has no authentication yet; the security component (`docs/phase2/security/`) is not started.
- Four migrated tables (`roles`, `user_roles`, `user_claims`, `user_logins`) have no use case in Phase 1 and so no
  endpoints.
- Password reset tokens were not migrated, so the password-reset action depends on the security component.
