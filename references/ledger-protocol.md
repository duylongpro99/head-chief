# Ledger Protocol (`.orchestrator/`)

Persistent, plain-markdown ledger at the project root. Survives session restarts; any session in the project can read it, so the chief and staff share it as the durable channel (SendMessage carries only brief plain-text pings).

## Layout

```
<project-root>/.orchestrator/
├── system-prompt.md              # chief persona; seeded from skill asset, project-editable
├── tracks/
│   ├── INDEX.md                  # generated fleet board (chief-owned, regenerated on every track write)
│   └── <session-name>/
│       └── status.md             # roster entry + mission + timeline (chief-owned)
└── logs/
    └── <session-name>/
        └── <YYYYMMDD>-<HHMM>Z-<slug>.md   # one file per chief→staff request
```

- `<session-name>` = the name the session answers to in `ListAgents` (e.g. `mds-portal-fix`). If a name contains `/` or spaces, replace with `-` for the directory name.
- `<slug>` = 2-5 kebab-case words describing the request (e.g. `20260810-1432Z-fix-login-500.md`). The `<YYYYMMDD>-<HHMM>Z` prefix is helper-stamped UTC — see **Timestamps & clock** below.

## Timestamps & clock (C7)

Every ledger timestamp — log **filenames** and every frontmatter/body date — comes from the helper,
**never** hand-typed (hand-typed stamps produced provably impossible orderings in production):

```bash
python3 "$SKILL_DIR/scripts/init_ledger.py" --now              # 2026-08-11T06:28:00Z   (frontmatter/body)
python3 "$SKILL_DIR/scripts/init_ledger.py" --now --filename   # 20260811-0628Z          (filename prefix)
```

- **Format = ISO-8601 UTC with a literal `Z`.** Unambiguous zone, sorts lexically. Frontmatter/body
  stamps look like `2026-08-11T06:28:00Z`; filenames use `<YYYYMMDD>-<HHMM>Z-<slug>.md`.
- **UTC wholesale — do not mix zones.** Older ledgers wrote local `+07`; the switch to UTC is
  wholesale so a chief reading an old `+07` stamp beside a new `…Z` one is never misled about order.
  Historical logs are **not** retro-rewritten (live ledger, out of scope).
- **`filename` time == frontmatter `created`** — same instant, same zone.
- **Ordering guard:** no `completed` / `resolved_at` / `sent_at` may be earlier than the log's
  `created`. A stamp that violates this is a clock error to fix, not a record to trust.

## Ownership rules (prevents write conflicts)

| Path | Writer | Others |
| --- | --- | --- |
| `system-prompt.md` | user (chief seeds it once) | read-only |
| `tracks/INDEX.md` | chief only (**generated** — derived rollup, never hand-edited) | staff read-only |
| `tracks/**` | chief only | staff read-only |
| `logs/**` request sections | chief (at creation) | staff read-only |
| `logs/**` `## Response` body + body-terminal `**STATUS:**` claim | assigned staff session | chief reads |
| `logs/**` frontmatter `status` field | chief (derived from the body-terminal `**STATUS:**` claim) | staff never writes it; chief may close `ABANDONED` after a `GONE` verdict |

**One writer per field (C4/D-α):** the frontmatter `status` is **chief-derived only** — staff writes the body-terminal `**STATUS:**` *claim*, never the frontmatter field. This eliminates the two-writer status race by construction. Chief edits nothing outside `.orchestrator/`; staff edit nothing in the ledger except their own log's `## Response` body and its body-terminal `**STATUS:**` claim.

**Single chief per project (C12/D-γ):** this ownership table is **advisory** — it does not stop a second `/head-chief` from clobbering `tracks/**`. The invariant is enforced the **live** way at init (SKILL.md Step 1): a starting chief `ListAgents` for a reachable `*-head-chief` and, on a hit, offers the user **adopt/handoff** rather than running concurrently; an **unreachable** incumbent is simply adopted (the C1 reconcile-on-adoption path). **Never a lock file** — a liveness-blind lock would convert a crashed chief into a lock-out at the exact moment recovery is needed.

## Log lifecycle

`status` frontmatter field, single upper-case token:

- `PENDING` — chief wrote the request, message sent, no response yet.
- `IN_PROGRESS` — staff acknowledged / started (staff sets, optional).
- `DONE` — staff finished and filled `## Response`.
- `BLOCKED` — staff cannot proceed; blocker described in `## Response`.
- `ABANDONED` — chief closed it (session stopped, superseded, or user cancelled).

**Write-order invariant (C4 — layout does the work).** The status signal is a **body-terminal** line, never a top-of-file frontmatter value the staff edits. Order is never reordered:
1. staff writes the `## Response` **body**, then
2. staff appends the body-terminal `**STATUS:** DONE|BLOCKED` **claim**, then
3. staff pings the chief with `"<logfile> updated"` (a doorbell that names the file — no status token to contradict the log).

The chief then **derives** the machine-readable frontmatter `status` from that claim *after* confirming the body is non-placeholder. A `**STATUS:**` claimed while the body is still the placeholder is **not reported** — wait one beat, re-read, nudge once. Because the status line is written *after* the body, a top-down editor produces the correct order by construction, not by willpower.

Chief reports to the user from the log body, not from the brief reply message. On `DONE`/`BLOCKED`, chief appends one timeline row to the session's `tracks/<session-name>/status.md`.

**SLA over non-terminal logs (C13).** On every status turn the chief sweeps all non-terminal logs
(`PENDING`/`IN_PROGRESS`), ages each via the C7 `--now` helper, and applies two **tunable-default**
thresholds: **T1 (default 10 min, no update) → nudge once**, **T2 (default 30 min) → escalate to the
user**. This replaces "PENDING far beyond expectation" with a concrete cadence; the numbers are
operator-ratified defaults, not hard-coded.

### Delivery axis (orthogonal stored axis, C1)

Whether a message *reached* a session is a **separate stored axis** from the lifecycle `status` — this
folds "held"/"undeliverable" into one axis instead of inventing new lifecycle tokens. Log frontmatter:

- `delivery:` — `unsent | sent | held | undelivered`, set the instant a send is made / held / denied / expires.
- `sent_at:` — helper-stamped UTC of the send attempt.

A `held` delivery means the *message* is stuck, **not** that the session is dead — the session may be
fully live (see the false-death guard).

### Liveness is derived, not stored (C1)

Track `status` frontmatter (`ACTIVE`/`IDLE`/`STOPPED`) is **not** the liveness source. Liveness is
recomputed from `ListAgents` (∩ herdr when present) on every status turn and every chief (re)adoption.
`PENDING_ACK`, `GONE`, and `SPAWN_FAILED` are **derived verdicts**, never stored lifecycle tokens:

- `PENDING_ACK` — spawned but not yet confirmed live *and* oriented (SKILL.md Step 3 ack-gate).
- `GONE` — a tracked session absent from `ListAgents`. Only then may the chief set that session's
  non-terminal logs to `ABANDONED` (chief-only, and only after a `GONE` verdict).
- `SPAWN_FAILED` — no ack by the deadline after a spawn.

Key `GONE` off `ListAgents` *presence*, never off a missing ping — a held ping is not a dead pane.

### Decomposition & log links (C9-light)

A blocked→decision→follow-up thread is a first-class pattern the schema models with two **optional**
log-frontmatter links (they replace the improvised `resolved_at`/`resolution` ad-hoc fields — a
resolution now lives in the `## Response` body + the body-terminal `**STATUS:**` line, C4):

- `supersedes:` — log path this request supersedes (e.g. the blocked request it resolves).
- `superseded_by:` — log path that supersedes this one.

Together with each track's `## Open loops` checklist, this makes "what's still open across the fleet"
a structural read instead of chief memory.

> **Deferred: cross-session `depends-on` graph (D-β — do NOT build yet).** The heavy form (a
> `DECOMPOSE` step + cross-session `depends-on` ordering) is deferred until **(a)** a real
> multi-session *ordered* request actually appears **AND (b)** C1 liveness/reconcile is in place —
> and even then only **with** an explicit "**blocked parent halts its dependents**" rule. Until all
> three hold, only the light `## Open loops` + `supersedes` form exists. Adding `depends-on` "while
> here" is a new plan, not this schema.

## Track file (`status.md`)

One per managed session; see `assets/track-status-template.md`. Contains:

- frontmatter: `session`, `ref` (the stable `[ref]` — **always address by this**, never the bare name; C8), `project` + `cwd` (recorded from the first-contact SIDECAR probe; **membership is confirmed here before any MAIN routing** — `ListAgents` returns no working dir, so membership must be probed, not assumed), `pane_id` (if chief spawned it via cris-cc-session), `status` (`ACTIVE`/`IDLE`/`STOPPED` — a hint, **not** the liveness source; see "Liveness is derived"), `last_confirmed_live` (helper-stamped UTC of the last time the session was seen in `ListAgents`; feeds the C5 board freshness), `created` (helper-stamped UTC — see **Timestamps & clock**)
- `## Mission` — one paragraph, current assignment
- `## Open loops` — chief-maintained checklist of this session's still-open delegations
  (`- [ ] <one-liner> — <log> — <derived-status>`); ticked/appended on every `DONE`/`BLOCKED` so
  fleet-open-work is a **structural read** that survives compaction/restart (feeds C1 restart-recovery)
- `## Timeline` — append-only table rows: `| datetime | event | log file |` (datetimes are helper-stamped UTC `…Z`)

Additional progressive files (design notes, longer summaries) may be added beside `status.md`; `status.md` stays the entry point.

## Fleet board (`tracks/INDEX.md`, C5)

A single chief-owned, **generated** rollup so the user watches **one** place, not N `status.md` files.
Regenerated on **every track write**. It is derived output — never hand-edited.

Columns: `session | derived-status | mission (one line) | newest open log | last-confirmed-live` (+ `cwd`, C8).

- **`derived-status` is computed from the turn's `ListAgents`** (∩ herdr), never read from track
  frontmatter — a board asserting a stored `ACTIVE` while the pane is dead is the exact bug C5/C1 fix.
- A pinned **"needs your attention"** section sits at the **top**: `GONE` sessions (C1) and
  `held`/`undelivered` logs (delivery axis) surface there first.
- `last_confirmed_live` (per-track, helper-stamped UTC) supplies the freshness column.

The per-track `status.md` files remain the **row source**; `INDEX.md` is their derived rollup. The
`--discussion` mode's progress board is a **section of this board**, not a separate surface.

## Hygiene

- Never write secrets into any ledger file — this binds **every writer** (chief *and* staff), not just the chief's own writes. See SKILL.md security policy and `.claude/rules/secrets-nondisclosure.md`.
- **Redaction on forward:** staff bodies routinely brush against secrets; when the chief copies a staff `## Response` body into `tracks/` or a report, it **redacts secret-shaped strings first** (DSNs, `DS_*`/`TOKEN_*`, `.env` values, connection strings → `<redacted>`).
- Ledger is per-project state, not documentation — do not mirror it into `docs/`.
- **Gitignore is decided once, at init (C10):** Step 1 asks the user the one-time question — gitignore `.orchestrator/`? (committed = durable audit trail; ignored = no leak of orchestration internals in a git repo) — **records the decision**, and never re-asks. The chief **surfaces the recommendation and asks**; it **never edits `.gitignore` (or any settings file) on its own initiative** — that is a user action.
