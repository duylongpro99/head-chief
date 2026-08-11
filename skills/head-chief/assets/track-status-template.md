---
session: <session-name>
ref: <stable [ref] from ListAgents — ALWAYS address by this, never the bare name (collisions misdeliver)>
project: <project this session is confirmed a member of (from the C8 cwd/repo probe)>
cwd: <working dir from the first-contact SIDECAR probe; membership confirmed before any MAIN routing>
pane_id: <herdr pane id if chief-spawned, else n/a>
status: ACTIVE            # ACTIVE | IDLE | STOPPED — a hint only; liveness is DERIVED from ListAgents
last_confirmed_live: <UTC via `init_ledger.py --now` — last time seen in ListAgents; feeds C5 board>
created: <stamp via `init_ledger.py --now` — UTC, e.g. 2026-08-11T06:28:00Z>
---

# Track — <session-name>

## Mission

<One paragraph: what this session is responsible for right now.>

## Open loops

Delegations still open for this session — chief-maintained; tick/append on every `DONE`/`BLOCKED`
so "what's still open across the fleet" is a structural read, not memory (survives compaction/restart):

- [ ] <delegation one-liner> — <log path> — <derived-status>

## Timeline

| When | Event | Log |
| --- | --- | --- |
| <UTC `…Z` via `init_ledger.py --now`> | Registered by head chief | — |
