# Documentation Rewrite - Continuation Prompt

Copy and paste this prompt to continue the documentation rewrite project:

---

```
Continue the Jac documentation rewrite project.

Planning docs: docs/_planning/
- DOCUMENTATION_PROGRESS_REPORT.md - Status & checklists
- DOCUMENTATION_REWRITE_PHASES.md - Phase plan (includes MANDATORY validation requirements)
- DOCUMENTATION_AUDIT_AND_PLAN.md - Audit findings

Instructions:
1. Read progress report, find next uncompleted task
2. Complete as many tasks as possible this session
3. **VALIDATE EVERYTHING** - See validation requirements in phase plan:
   - Activate venv: `source .venv/bin/activate`
   - Test CLI commands with `--help` AND actual execution
   - Run all code examples to verify they work
   - Run `mkdocs build` to verify no new warnings
4. Update progress report: change  to  for completed items
5. If you discover gaps, add them to "Discovered Gaps" section in progress report - don't modify the phase plan
6. Report: what you completed, what's next, any gaps found, validation performed

Priority: Complete existing tasks before addressing new gaps.
Never document based on assumptions - always verify actual behavior.
```

---

## Notes

- Run this prompt repeatedly until all Phase 1-6 tasks show
- Each session picks up where the last left off
- Progress is tracked in `DOCUMENTATION_PROGRESS_REPORT.md`
- New discoveries go in the "Discovered Gaps" table, not the phase plan
- **VALIDATION IS MANDATORY** - every documentation claim must be verified against actual behavior
