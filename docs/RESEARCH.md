# AI-Assisted Modernization of Legacy .NET Applications to Java/Angular: A Claude Code Case Study

**Booz Allen Hamilton — Digital Solutions**
**Author:** Charles David Harris
**Status:** Internal working draft
**Date:** 2026-08-31
**Distribution:** Internal use only — engagement team reference

## Abstract



## 1. Introduction

### 1.1 Research Questions


## 2. Related Work and Background

- **Strangler Fig migration pattern** (Fowler, "StranglerFigApplication," martinfowler.com) — incremental legacy replacement with continuous behavioral parity checks; this project performs a full parallel rebuild rather than an incremental cutover, but borrows the same parity-verification discipline.
- **Layered / N-tier architecture** (Fowler, *Patterns of Enterprise Application Architecture*, 2002) — used as the baseline architecture for both the legacy and target systems, and as the unit of measurement for where AI-generated code required correction (§7).
- **Working with legacy code** (Feathers, *Working Effectively with Legacy Code*, 2004) — the characterization-test technique is used to fix the Phase 1 behavioral baseline (workflow transitions, audit log format) that Phase 2 is measured against.
- **Monolith decomposition** (Newman, *Monolith to Microservices*, 2019) — informs the bounded-domain scoping of the exercise.
- **Accessibility and security baselines** — WCAG 2.1 AA (W3C) and the OWASP Top 10 are used as scored, checklist-based acceptance criteria (§7.4), not narrative goals.
- **AI pair-programming effectiveness studies** — public research on AI coding assistants (e.g., GitHub's controlled studies of Copilot task completion time) generally measures greenfield feature tasks. This project's contribution is applying the same measurement discipline (time-on-task, acceptance rate, defect rate) specifically to a cross-platform migration task, where the assistant must translate semantics rather than originate them.

## 3. Platform Comparison: .NET Framework/C# vs. Java/Spring Boot/Angular


## 4. State of AI-Assisted Development with Claude Code

### 4.1 Capability Overview


### 4.2 Best Practices Applied in This Study

1. **Establish the behavioral baseline before generating target code.** 
2. **Scope prompts to one architectural layer at a time.** 
3. **Ask for the semantic decision explicitly, not just the code.** 
4. **Treat generated tests as a verification artifact, not a formality.** 
5. **Log every substantive prompt and its disposition.** 
6. **Independently verify the categories flagged as high-risk in §3**, 

## 5. Methodology


### Phase 1 — Legacy Baseline (human-authored, not AI-migrated)



### Phase 2 — AI-Assisted Modernization (Claude Code as primary implementer)


### 7.2 Suggestion Acceptance Metrics (by layer, per §3/§6.2 taxonomy)



## 8. Results



## 9. Risk Analysis

## 10. Discussion



## 11. Conclusion and Next Steps

## Disclaimer

This paper is an internal training and methodology exercise prepared for engagement-team reference. It does not represent an official Booz Allen Hamilton publication, client deliverable, or public statement of company position, and should not be distributed outside the firm without review.

## References

1. Fowler, M. *StranglerFigApplication*. martinfowler.com.
2. Fowler, M. (2002). *Patterns of Enterprise Application Architecture*. Addison-Wesley.
3. Feathers, M. (2004). *Working Effectively with Legacy Code*. Prentice Hall.
4. Newman, S. (2019). *Monolith to Microservices*. O'Reilly Media.
5. OWASP Foundation. *OWASP Top Ten*. owasp.org.
6. W3C. *Web Content Accessibility Guidelines (WCAG) 2.1*. w3.org.
