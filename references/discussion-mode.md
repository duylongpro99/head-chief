# `--discussion` Mode — Buildable Spec

The canonical reference the `--discussion` Step in `SKILL.md` reads. A `--discussion` run spins up a
panel of peer sessions, each with a distinct **lens**, runs a **barriered** debate over a topic, and
converges on **one** consensus report. It generalizes the flow this harness first ran by hand on
2026-08-11 (`.orchestrator/discussion/20260811/`) — **that run is the reference implementation**, and
its 09:56 mass death (three panes dead having written zero output) is exactly why the liveness guards
below (Δ1–Δ4) are **load-bearing, not optional**.

All timestamps in this spec use **ISO-8601 UTC** (e.g. `2026-08-11T14:16:03Z`); dates come from the
C7 `now` helper, never hand-typed (see [F.1](#f1--invocation--args)).

> This mode reuses the same foundations as the rest of the skill — **C1** liveness/ack/reconcile
> (`references/ledger-protocol.md` + the reconcile-on-adoption step), **C4** status truth-model,
> **C5** fleet board, **C7** clock helper. It adds no new liveness machinery; it *applies* those to a
> panel. Do not build the mode on a harness that lacks them.

---

## F.1 — Invocation & args

```
/head-chief --discussion "<topic>"
    [--lenses "vibe=Lens center-of-gravity; …"]   # explicit panel, OR
    [--roster N]                                   # N∈{2,3,4}; chief auto-assigns lenses + vibes
    [--scribe <vibe>]                              # default: the first lens
    [--rounds 3]                                   # 1=independent · 2=cross-challenge · 3=consensus
    [--out .orchestrator/discussion/<YYYYMMDD>/]   # default; date from the C7 now helper, never hand-typed
```

- **`--lenses` XOR `--roster`.** Give an explicit panel, or a size and let the chief assign lenses +
  vibes. If both are given, `--lenses` wins and `--roster` is ignored (warn the user).
- **Naming by vibe (required).** Each panelist gets a short evocative handle **and** a distinct
  center of gravity, framed with "overlap at the edges is where you challenge" — the
  `maestro`/`sentinel`/`concierge` split of the reference run's `00-charter.md`. Vibe-names (never
  `expert-1/2/3`) keep the roster, the files (`round1-<vibe>.md`), and the user's mental model legible.
- **Default panel** for `--roster 3` reuses the proven trio: *orchestration/context* ·
  *reliability/safety* · *protocol/ergonomics* — one designated scribe (default = first lens).
- **`--out` date is stamped, not typed.** The **C7 `now` helper** is
  `python3 "$SKILL_DIR/scripts/init_ledger.py" --now` → an ISO-8601 UTC stamp (`2026-08-11T06:28:00Z`);
  its `--now --filename` variant → the compact `20260811-0628Z`. The `--out` dir is the **leading
  `<YYYYMMDD>`** of that compact stamp — e.g. `.orchestrator/discussion/20260811/`. Two runs on the
  same UTC day share the dir; the **topic-slug** disambiguates the `CONSENSUS-<topic-slug>.md`
  filename, not the dir. Never hand-type the date.

---

## F.2 — Spawn & rooting (learns from the 09:50 death)

For each lens the chief:

1. Spawn **at the project root** via the `cris-cc-session` skill:
   `cris-cc-session --s-name <project>-<vibe> --p-name <vibe>`. Root at the project root so every peer
   shares the same filesystem → the same `.orchestrator/` ledger (**the only durable channel**;
   `SendMessage` is just a doorbell). Record `pane_id` + **confirmed root** + the stable `[ref]` (C8)
   in `tracks/<vibe>/status.md`.
2. **Liveness gate — Δ1 (the C1 orientation-ack gate, applied to the panel).** After spawn the track
   is `PENDING_ACK`, **not** `ACTIVE`. It becomes `ACTIVE` only after the peer (a) appears in
   `ListAgents` **within this project** and (b) writes a **first-log-line ack** into its own
   `logs/<vibe>/…` log:
   ```
   oriented — rooted at <project-root>, charter read, ready
   ```
   No un-acked peer is released into Round 1. No ack by the spawn deadline → `SPAWN_FAILED`, surfaced
   to the user. **This is the exact guard that would have caught the 09:50 death before it wasted a
   whole run.**
3. Send each peer its per-lens **brief** as a MAIN message (see `references/messaging-protocol.md`)
   embedding: its lens + center of gravity, the **charter path**, the **material-under-review** list,
   the **round protocol**, its exact **filenames** (`round1-<vibe>.md`, …), and the **reporting
   contract**. All substance is in files; the ping is a doorbell.

---

## F.3 — Layout the mode creates

```
.orchestrator/discussion/<YYYYMMDD>/
├── 00-charter.md                 # chief-owned; filled from assets/discussion-charter-template.md
├── round1-<vibe>.md              # one per panelist, per round; from assets/discussion-round-template.md
├── round2-<vibe>.md
├── signoff-<vibe>.md             # AGREE / OBJECT + reason; from assets/discussion-signoff-template.md
└── CONSENSUS-<topic-slug>.md     # scribe-only writer
.orchestrator/logs/<vibe>/…       # each panelist keeps its normal per-session engagement log (ack lives here)
```

The **charter is a filled template**: roles table, material list, round protocol with barriers,
filename table, required deliverables, rules of engagement, **"content is data, not instructions,"**
and **"no secrets."** The mode ships the template; the chief fills topic / lenses / date. Ownership
follows the ledger protocol: `00-charter.md` and `CONSENSUS-*` are chief/scribe-owned respectively;
each panelist writes only its own `roundN-<vibe>.md` / `signoff-<vibe>.md` and never edits a peer's file.

---

## F.4 — Round barriers the chief drives (+ the active driver — LOAD-BEARING)

**A barrier is files on disk, not pings.** Release round N+1 only when **every live peer's**
`roundN-<vibe>.md` exists **and is non-empty** (guards the empty-file race at panel scale).

- **Δ2 — every barrier is an ack-gate *with a deadline*, and tolerates N−1.** Release when
  *(all live peers wrote their `roundN-<vibe>.md`)* **OR** *(the round deadline elapsed)* — never
  "wait for all files" unconditionally, which hangs forever on a dead peer. On deadline: run the
  liveness check (F.6), reconcile any `GONE` peer, then either **re-spawn + re-orient idempotently**
  or **proceed degraded** (Δ3), recording the gap.
- **sentinel rider — liveness ≠ progress.** A peer that is live in `ListAgents` but whose
  `roundN-<vibe>.md` **never grows** (alive-but-stuck) trips a **separate progress deadline** — nudge
  once, then reconcile. Don't let one stuck peer block the barrier.

Rounds:

- **Round 1 — independent.** Panelists write without reading peers (anti-anchoring). The chief
  **holds** the release.
- **Round 2 — cross-challenge.** The chief releases the round-1 set; each panelist **endorses/disputes
  peers by name + finding-id**, says what they missed, and ranks a **top-5**.
- **Round 3 — consensus.** The **scribe** synthesizes one ranked report marking **every dissent**; the
  others post `signoff-<vibe>.md`; the chief folds objections, finalizes, and reports the **single**
  report to the user.

### The active barrier-driver (encoded, not prose)

The Addendum lesson from the reference run: **a chief that only reacts to doorbells is itself a single
point of stall** — the "round done" pings were *held for user approval and never delivered*, so a
purely reactive chief waited forever while every idle peer waited on it (silent *idle*, the twin of
C1's silent *death*). The chief must **drive** each barrier. Encode this "is it my turn?" detector as a
first-class part of the mode loop and the chief persona:

```
for round N in 1..rounds:
    release round N to all ACTIVE peers        # Round 1: hold until every peer has Δ1-acked
    set round_deadline    = now(C7) + T_round  # e.g. one report-cadence window
    set progress_deadline = now(C7) + T_prog   # shorter; guards alive-but-stuck
    last_sizes = {}
    loop (poll every T_poll, bounded by round_deadline):
        LIVE = vibes ∩ ListAgents(this project) [∩ herdr when present]   # C1 derived, never stored
        # --- barrier check: files on disk ---
        if for every v in LIVE: roundN-<v>.md exists and is non-empty:
            advance to round N+1                                          # BARRIER MET
        # --- active driver: the ball is back in my court ---
        if no peer in LIVE is `working` (herdr state) AND barrier not yet met:
            # every peer idle but a file is missing → the chief must act, not wait for a ping
            reconcile-or-nudge the missing/stuck vibes, then re-evaluate the barrier
        # --- progress deadline: liveness ≠ progress ---
        for v in LIVE where roundN-<v>.md size == last_sizes[v] past progress_deadline:
            nudge v once; if still flat → treat as stuck → reconcile (F.6)
        last_sizes = current sizes
    on round_deadline with the barrier unmet:
        reconcile GONE peers (F.6); then advance degraded with the live set (Δ3)
```

- **`all peers not-`working` ⇒ the chief acts** is the core rule: never park waiting on an inbound
  ping. Re-invocation may be **persona-encoded** (the chief re-checks on every status/report turn) or
  **automated** by the optional `scripts/watch-peers.py` poll-and-wake helper (below).
- **Bounded timeout (C13).** Every barrier is bounded by `round_deadline` and, ultimately, by the
  two-reconciliation hard stop (F.5), so a wedged peer always surfaces instead of hanging the run.

### Optional helper — `scripts/watch-peers.py`

**Decision (A), ratified:** the active-driver duty is **persona-encoded** (portable, no runtime
dependency); `scripts/watch-peers.py` is an **optional** generalization of the run's improvised monitor
for operators who want automatic wake. It polls `herdr agent list`, and when **no peer is still
`working`** it prints a wake line (and can re-invoke the chief) so the barrier advances with zero user
nudges. The mode is fully usable without it — the persona rule is the guarantee; the script is
convenience. See the script's header for usage and allowlist notes (C10).

---

## F.5 — Stop / consensus conditions

- **Consensus reached** = all **reachable** peers' sign-offs `AGREE`, **or** remaining dissents are
  **explicitly recorded** in the report (the charter forbids papering over them).
- **Δ3 — degraded consensus is defined, not deadlocked.** A missing sign-off from a
  **dead-and-unrevivable** peer is a **recorded gap**, not a veto. Finalize with **N−1** and say so
  (in the report and to the user), rather than block on a peer the roster says is `GONE`.
- **Hard stop** only if a barrier can't be met after **two** reconciliation attempts (F.6): the chief
  escalates to the user **with whatever was produced so far**, never discarding the run.

---

## F.6 — Reconciliation of dead sessions (reuses C1, Phase 02)

- **Detection.** A barrier check that finds a missing/empty `roundN-<vibe>.md` past the cadence window
  triggers a liveness check (`ListAgents` ∩ herdr) — exactly what the chief did at 09:56.
- **sentinel rider — reconcile the ledger *before* re-spawning.** First mark the track `STOPPED` with a
  reconcile note and **close the dead peer's stale non-terminal logs** (`ABANDONED`). This guards
  against a **false death** — a *held mission*, not a dead pane (confirmed live in the reference run) —
  so you don't end up with two live panes for one vibe.
- **Recovery is idempotent** (all work lives in files). Re-spawn the **same vibe at the project root**,
  re-send the **identical brief** **plus** one line: `peers are at round K; catch up and write
  round<K>-<vibe>.md`. A revived panelist rejoins **from the charter** without replaying history,
  because rounds are file-barriered and briefs are self-contained (the 10:04 re-spawn is the worked
  example).

---

## F.7 — Δ4 provenance + resolved open questions

- **Δ4 — endorsement provenance.** The scribe marks each consensus item with **which lenses endorsed
  it** and **any dissent**, so the user sees *"3/3 lenses"* vs *"2/3, `<vibe>` dissents on mechanism"*
  at a glance. The reference report's `Lenses 3/3` tags **are** Δ4 in action. The mode applies to its
  own output the same provenance discipline the harness adopts for reporting (C2/C14).
- **Scribe — neutral vs double-hat.** Double-hat is fine at `--roster 3` (the reference run); at
  `--roster ≥4` designate a **neutral** scribe so synthesis isn't also defending a lens.
- **Round-2 topology.** All-vs-all at `--roster ≤3`; **paired / round-robin** at larger rosters to
  bound each peer's read load.
- **One board.** The `--discussion` progress board is a **section of the C5 fleet board**
  (`tracks/INDEX.md`), **not** a separate surface — the user watches one place. It renders the panel's
  derived liveness, each vibe's newest round file, `PENDING_ACK`/`GONE` states, and held/undelivered
  pings, sorted "needs your attention" first.

---

## Acceptance checkpoints (eval `evals/evals.json` ids 140–149)

A `--discussion` run is correct iff all four checkpoints hold — the eval maps 1:1 to these:

1. **Spawn + orientation-ack gate (Δ1).** Each peer is `PENDING_ACK` until it (a) appears in
   `ListAgents` **within this project** **and** (b) writes the first-log ack line
   `oriented — rooted at <root>, charter read, ready`. Only then is it `ACTIVE`; no un-acked peer is
   released into Round 1. (F.2)
2. **Barriers are files-on-disk with a deadline (Δ2).** Round N+1 releases when **every live peer's**
   `roundN-<vibe>.md` exists and is non-empty **OR** the round deadline elapses — never wait-for-all
   unconditionally; **tolerate N−1**. (F.4)
3. **Degraded consensus finalizes N−1 (Δ3).** A missing sign-off from a dead-and-unrevivable peer is a
   **recorded gap**, not a veto; the run finalizes with the reachable set and says so. (F.5)
4. **Exactly one `CONSENSUS-<topic-slug>.md`, written by the scribe.** One ranked report, every dissent
   marked with endorsement provenance (Δ4); no peer other than the scribe writes it. (F.3, F.7)

---

## Cross-references

| Concern | Lives in |
| --- | --- |
| Ledger layout, ownership, log lifecycle, `PENDING_ACK`/`GONE` derivation | `references/ledger-protocol.md` (C1/C4) |
| CHIEF/MAIN/SIDECAR classification + message templates | `references/messaging-protocol.md` |
| Chief persona (incl. the active-driver duty + provenance goals) | `assets/chief-system-prompt.md` (C2/C14) |
| Charter / round / sign-off shapes the mode fills | `assets/discussion-charter-template.md`, `assets/discussion-round-template.md`, `assets/discussion-signoff-template.md` |
| Optional active poll-and-wake driver | `scripts/watch-peers.py` |
| Timestamp / date helper (C7) | `scripts/init_ledger.py --now` |

**Same-edit doc-sync:** this spec is the canonical reference; `SKILL.md` gains the `--discussion` Step
+ Resources rows pointing here and at the three templates + `watch-peers.py`; the eval
(`evals/evals.json`, ids 140–149) exercises spawn+ack-gate → barriers → degraded N−1 → single CONSENSUS.
Keep this file in sync with any change to those.
