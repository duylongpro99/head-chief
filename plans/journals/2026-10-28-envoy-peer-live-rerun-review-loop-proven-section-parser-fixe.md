---
title: "envoy-peer live rerun: review loop proven, section parser fixed"
date: 2026-10-28
summary: "With grok and agy signed in on free tier, the full review loop ran live (ACCEPT in round 1; FINDINGS then ACCEPT in round 2); a section-parsing bug that made every clean review look like a conflict was fixed."
---

# envoy-peer live rerun: review loop proven, section parser fixed

## What happened

The user signed in to grok and agy on free-tier accounts. Two blockers remained: omp has no models configured, and codex still routes through a local 9Router proxy that was not running.

The controller ran SKILL.md step by step in the scratch sandbox:
- `fix-greet`: grok was the envoy and claude the reviewer. ACCEPT in round 1.
- `staged-findings`: agy was the envoy. The brief openly limited round 1 to a partial fix. FINDINGS, then `decision-1.md`, then round 2, then ACCEPT.
- A third run had grok run `probe.sh` itself from its own pane: it detected itself as the controller and left grok out of the list.

## Root cause found

`run-state.sh` `section()` stopped only at the next `## ` heading. Both templates end with a contract line (`Verdict: …`, `Status: …`) and have no heading before it. So the last section always included that line:
- `conflicts` printed `present` for every review that said "None.";
- `extract Unresolved` quoted the Status line.

The offline tests never caught this because their fixtures did not use the real templates' layout.

## Decision

- A section now also ends at the exact contract line.
- The conflicts check stays strict, because extra text may hold a real conflict. The claude reviewer kept writing "None." followed by an explanation, so the review template now asks for "None." alone.
- Observed but not changed: on a CLI's first launch in a folder, `start.sh` can report ready before the CLI draws its trust or setup screen. The skill's documented recovery (exit 4 or 6, then the user, then a resend) handled it each time.

## Next steps

- Start 9Router or configure codex's model access, then rerun one codex envoy task.
- Watch whether the new review-template wording stops the "None. + explanation" pattern.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.
