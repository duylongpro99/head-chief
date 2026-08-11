---
session: <session-name>
class: MAIN | SIDECAR
status: PENDING           # CHIEF-DERIVED from the body-terminal **STATUS:** claim; staff never edits this
delivery: unsent          # unsent | sent | held | undelivered (orthogonal to status)
sent_at:                  # helper-stamped UTC set when the send is attempted/held/denied
supersedes:               # optional — log path this request supersedes (e.g. the blocked one it resolves)
superseded_by:            # optional — log path that supersedes this request
created: <stamp via `init_ledger.py --now` — UTC, e.g. 2026-08-11T06:28:00Z>
---

# <One-line request summary>

## Request (written by chief)

Briefs must be **self-contained — the staff session shares no history with you**
(see `.claude/rules/orchestration-protocol.md`). Fill every section, one or two lines each:

- **Goal:** <the outcome, in one sentence>
- **Non-goals:** <what is explicitly out of scope>
- **Files in scope:** <paths to read / change>
- **Acceptance criteria:** <how "done" is verified>
- **STOP-if:** stop and report — do not guess — on an ambiguous spec; and before any
  irreversible/shared-state action (delete/push/merge/cherry-pick/force-push/PR-merge). When
  BLOCKED on a choice, end the `## Response` with a recommendation-first `### Decision needed` A/B.
- **Report what:** <what to put in the `## Response` body: evidence, files touched, follow-ups>
- **Constraints:** <perf / security / deadlines / branch rules>

## Response (written by the assigned staff session)

<Staff session: replace this line with your full outcome — what was done, evidence,
files touched, blockers, follow-ups. Write the BODY FIRST; then append the
body-terminal `**STATUS:**` line below. Do NOT edit the frontmatter `status` — the
chief derives it from your claim after reading this body.>

**STATUS:** <DONE | BLOCKED — append this LAST, after the body above; it is your authoritative claim>
