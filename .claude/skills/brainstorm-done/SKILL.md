---
name: brainstorm-done
description: Ends /brainstorm mode and returns to normal behavior. Use when the user types /brainstorm-done or says they're done brainstorming, want to stop exploring, or want to switch to normal/action mode.
---

# /brainstorm-done — leave brainstorm mode

The `/brainstorm` skill cannot be unloaded once invoked, so this skill explicitly supersedes it for the rest of the conversation. That includes its strict `--edit` rule: **edits are no longer restricted by the flag** and normal edit behavior resumes (edit when the user asks for a change, as in any ordinary session).

## Do

- Confirm in one short line that brainstorm mode is over.
- From here on, behave normally: plans, `AskUserQuestion` menus, Plan Mode, and multi-step implementation are all fair game again, and answers can be as long as the task needs.
- If the user included a task with the command (e.g. `/brainstorm-done implement the Oracle dialect`), do that task now as a normal request.
- If the conversation surfaced conclusions the user is likely to act on, offer a two- or three-line summary of them, but only if that helps. Don't produce a report unprompted.

## Don't

- Don't start implementing anything the user didn't ask for just because the brainstorm touched on it. Exiting the mode is not a request to build.
- Don't keep applying the brainstorm restrictions: short prose only, no menus, no plans, and the `--edit` rule (do not keep waiting for `--edit` before making a requested change).
- Don't treat this as blanket permission to change things unprompted. Only make the changes the user actually asks for.
- Don't re-invoke `/brainstorm` unless the user asks to go back to exploring.
