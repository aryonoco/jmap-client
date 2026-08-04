# HANDOFF — post-compaction orientation (written 2026-08-04, session `api-refinement`)

You are picking up mid-stream with zero context. This document tells you
what the project is, what has been done, what is left, and exactly how
the human wants you to work. It is TRANSIENT — overwritten before each
compaction; durable truth lives in the specs/plans/ledger it points to.
Read the "Read these first" list, then resume at "WHERE WE STOPPED".

## Read these first (in this order)

1. `CLAUDE.md` (auto-loaded) — what the library is, commands,
   conventions, the MANDATORY commit-message format.
2. `docs/design/17-L5-FFI-Principles.md` — the Layer-5 C ABI design
   note. AUTHORITATIVE for everything L5. Three of its sketches were
   amended by owner decision AFTER ratification (see "Settled
   decisions" below) — the plan encodes the amended forms; doc 17
   itself gets its dated amendments only in the plan's Task 17.
3. `docs/superpowers/plans/2026-08-04-l5-c-abi.md` — THE PLAN you will
   execute next. 18 tasks (0–17), complete code in every step, written
   from a 7-agent research workflow over the real landed surface plus
   verified compiler experiments. Its Global Constraints bind every
   task.
4. `docs/TODO/pre-1.0-api-alignment.md` — ONLY the status dashboard
   (~L60–110). It is ~4200 lines; grep for specific items (C24 will be
   new, C6, D10, H-numbers) when a task needs them.
5. Skim `docs/design/14-Nim-API-Principles.md` — the 29-principle
   rubric (P-numbers cited everywhere); read bodies on demand.

Your auto-memory (MEMORY.md) carries the standing user directives —
[[ask-at-every-fork]] and [[claude-dir-timeless]] are non-negotiable.

## The project, in four sentences

`jmap-client` is a cross-platform JMAP (RFC 8620/8621) email library in
Nim, layered L1–L4, whose public API is held to libcurl/SQLite
standards via a consumer bench (`examples/jmap-cli/`) and frozen
wire-contract snapshots. The 2026-06 API-refactor campaign (PRs #5–#15)
and this session's PRs #16 (docs reconcile), #17 (C12 seal), #18 (L5
design note) and #19 (the C15 easy-path one-shots: write verbs,
vacation set, state bootstrap, `syncEmails`, plus two owner-approved
library fixes) are ALL MERGED — `main` is at `8b22cab`. The current
phase is Layer 5 itself: the C ABI specified in doc 17, wrapping the
one-shot easy path only. The implementation plan for it is written and
self-reviewed; execution has not started.

## WHERE WE STOPPED (the exact resume point)

- `main` is synced at `8b22cab` (PR #19 merge); the C15 branch is
  deleted local+remote. The working tree is clean except TWO untracked
  files: the L5 plan (`docs/superpowers/plans/2026-08-04-l5-c-abi.md`,
  committed by its own Task 0 on branch `api/l5-c-abi`) and this
  HANDOFF (never commit it).
- **The pending question the user has NOT yet answered**: execution
  approach for the L5 plan — subagent-driven
  (`superpowers:subagent-driven-development`, recommended) vs inline
  (`superpowers:executing-plans`). The user interrupted to request this
  handoff instead of answering. ASK IT AGAIN before executing (one
  AskUserQuestion, two options, recommend subagent-driven — this PR
  introduces the repo's first C code and first exportc surface, where
  independent review earns its cost most).
- Do not start Task 0 until that question is answered. Nothing else is
  pending.

## Settled decisions — DO NOT re-ask or re-litigate

All doc-17 decisions stand (per-handle error state, easy-path-only v1,
library-owned borrows, hand-curated header + gate, opaque views,
single ctor with NULL-transport-default, mandatory account_id,
jmap_version). THREE further forks were put to the owner on 2026-08-04
during plan research and are BAKED INTO THE PLAN:

1. **Typed query setters** (`jmap_query_set_str`/`jmap_query_set_u32`,
   sqlite3_bind discipline) replace §5's ratified variadic — Nim cannot
   read C varargs without `{.emit.}` raw C (verified). Task 17 records
   the dated §5 amendment.
2. **Non-const lazy-fetch account accessors** — the substrate's session
   is lazy (connect does NO network IO; verified), so
   `jmap_client_primary_account`/`account_count` take non-const
   `jmap_client*` and fetch-and-cache on first use. Task 17 records the
   §4 amendment.
3. **Nim-private exportc** — L5 symbols carry `{.exportc.}` but NO Nim
   export marker (verified: unstarred exportc symbols survive in the
   `.so`). Consequence: the frozen Nim snapshots must NOT move — every
   task verifies `git diff tests/wire_contract/` is EMPTY (the exact
   opposite of the C15 PR's refreeze-per-task rhythm). A snapshot
   change means a `*` leaked. The FFI skill's starred examples get
   corrected in Task 17 (timeless edits).

Also settled earlier and still governing: two-plans sequencing (C15
first — done; this is plan #2), D1/D1.5/D9/D18 deferred, B6/P18 is the
sole remaining pre-1.0-tag decision, the pairs-leak and vendored
nim-results raiseResultDefect patches are landed reality (main).

## How the user works — OBEY THESE

- **Ask at every fork.** Never assume at any decision point. One
  AskUserQuestion per message, full context, 2–4 viable options,
  recommendation first marked "(Recommended)". Proceed only when every
  outstanding fork is directly answered. Absolute; enforced repeatedly.
- **Superpowers process skills are mandatory, loaded via the Skill
  tool.** Execution via whichever skill the user picks (see pending
  question). The installed superpowers version is 6.2.0 — its
  subagent-driven-development is the LEDGER-BASED process: run
  `scripts/sdd-workspace PLAN_FILE` for the plan's workspace, keep
  `progress.md` there (first line names the plan file), extract
  per-task briefs with `scripts/task-brief`, build review diffs with
  `scripts/review-package BASE HEAD`, dispatch implementer → task
  reviewer (spec+quality) → fix rounds (resume the SAME implementer
  via SendMessage, rounds 1–3) → scoped re-review each round → ledger
  every completion/parked finding → final whole-branch review (ONE fix
  wave, one scoped re-review) → finishing-a-development-branch.
- **Subagent models**: `sonnet` for plan-complete transcription tasks
  and scoped re-reviews, `opus` for task reviewers, the final review,
  and judgment-heavy implementers — NEVER Haiku, NEVER omit the model
  (omitting inherits Fable, which the user excluded for subagents).
  For THIS plan give opus to: Task 14 (header-gate lint), Task 15
  (raw-index audit — its macro core is adapt-from-named-siblings, the
  plan's one deliberately thin spot), Task 16 (bench), Task 17
  (close-out), and any fix round that stalls.
- **Reviews are real**: they found genuine defects on every C15 task.
  Nice-to-have findings get APPLIED (standing preference); genuine
  design choices inside findings go back to the user as questions;
  plan-conflicting findings are the user's call, not yours.
- **Outward-facing**: pushes and PR-opening for commissioned work are
  fine; MERGING is always the user's. PR bodies carry NO Claude/AI
  footer; snapshot-relevant PRs describe their contract deltas in the
  body (this one's headline: the Nim surface did NOT move).
- **Git**: never work on main; branch `api/l5-c-abi` (Task 0); stage
  explicit paths only; kernel-style commits ending with EXACTLY the
  three trailers in CLAUDE.md (`Assisted-by: Claude:claude-5-fable`).
  Working-tree branch, NO worktree (project convention overrides the
  skill's worktree step).
- **Gates**: `just ci` before EVERY commit. This plan ADDS gates
  mid-flight: from Task 1 `just test-c` exists (gcc compliance tests;
  needs `just build` first); Task 14 wires `build`+`lint-c-header`+
  `test-c` into `ci` and hosted CI. The live gate (`just jmap-up` +
  `just test-full`) is the USER'S; the PR body must ALSO recommend a
  manual live run of `bin/jmap-c-cli` (it will never have spoken to a
  real server).
- **`.claude/` files are timeless** (no dates/ledger-ids/narration);
  docs British English, why-not-what, RFC citations allowed in source,
  design-doc/ledger references not. Dates written into docs are
  verified against `git log`, never the session clock.

## What was done this session (all merged unless noted)

1. **PR #19 (merged, `8b22cab`)** — the C15 easy-path one-shots,
   executed subagent-driven: 9 tasks + fix rounds + final review; six
   one-shots + `addEmailChangesToGetAll` combinator + CLI adoption +
   ledger close-out (C15/C17/C21 DONE, C23 opened-and-closed,
   dashboard 82 DONE / 32 TODO). Two owner-approved scope extensions
   now on main and load-bearing for L5: (a) vendored nim-results'
   `raiseResultDefect` probes effect-provability (`.error` was
   uncompilable for Email-carrying Results; locked by
   `tests/compile/tcompile_error_accessor_email.nim`); (b) the
   pairs-instantiation leak sealed via `tables.pairs(...)`
   qualification in the six /set projection iterators + two generic
   toJson overloads.
2. **The L5 research workflow** (7 agents, all verbatim-verified):
   one-shot/session/entity/query surfaces, build+gates, FFI mechanics,
   transport lifecycle, bench/test wiring. Full results in this
   session's task output file (gone after compaction) — every fact the
   plan needs was baked INTO the plan, so you should not need them.
3. **Three verified compiler experiments** deciding the forks above
   (unstarred-exportc symbol survival; `compiles()` effect-probing;
   `bind pairs` failure vs `tables.pairs` success — the last two are
   already on main from PR #19).
4. **The L5 plan** written under the writing-plans skill and
   self-reviewed; the review added Task 8 (threads/identities/vacation
   reads — a doc 17 §8 row the draft missed, which also let the bench
   resolve its send identity through the API instead of an env-var
   hack), renumbered 8–16→9–17, added the missing `JMAP_E_METHOD`
   static assert, and sanitiser guidance on `test-c`.

## Pitfalls and gotchas ahead (beyond the plan's own text)

- **`tests/c_abi/` would be DELETED by `just test-full`** unless
  Task 1's prune-whitelist edit lands (the prune removes any
  `tests/<dir>/` with zero `.nim` files). Do not defer that edit.
- **Latch-before-GC**: `--noMain` means module globals are
  uninitialised until `jmap_init` runs NimMain. Any exported proc
  touching a string/seq/ref before checking `l5Initialised` can
  crash the host. Reviewers should hunt for this specifically.
- **Fixture generation**: every C test's JSON fixtures are printed
  from the Nim suite's own builders (`tests/mfixtures.nim` etc.) via
  throwaway `nim r` snippets and pasted verbatim — hand-written
  session JSON will be rejected by the strict decoder. The plan gives
  the commands; implementers must not improvise fixtures.
- **H19 numbering**: verify the next free H-number in the ledger
  before naming the header-gate lint (the plan flags this).
- **Task 15's STOP rule**: if the raw-index audit demands source
  changes at >15 sites, the implementer reports BLOCKED — that means
  guard-recognition needs widening, not 40 unreviewed parser edits.
  Also verify `tffi_panic_surface.nim`'s staticRead paths (possibly
  stale post-refactor) before relying on its walker.
- **t03 has a deliberately deferred block** (restored by Task 4 when
  `jmap_client_primary_account` exists) — the plan says exactly what
  to defer and restore; don't "fix" it early.
- **Doc 17 amendments belong to Task 17 ONLY** — do not edit doc 17
  when implementing Tasks 4/12 even though their signatures differ
  from its ratified sketches.
- **`resp.get().get`** in Task 12 (Result unwrap then the
  `QueryThenGet.get` field) may fight the compiler — the plan gives
  the let-bound fallback.
- **CStringConv / PtrToCstringConv / AnyEnumConv are warningAsError**:
  the plan's ordinal-matching idioms (jmap_strerror,
  jmap_mailbox_has_right) exist because of this; copy them, never
  cast int→enum.
- **ASan on `test-c` is best-effort**: if the sanitised-C /
  uninstrumented-.so mix fails at runtime, drop the flag and record it
  (the plan licenses this explicitly).
- **SDD ledger discipline**: the C15 run survived earlier compactions
  because of `.superpowers/sdd/<plan>/progress.md` — create it at
  skill start, append task completions/parked findings/user decisions
  as they happen. After any compaction trust it + `git log` over
  recollection. Delete the workspace only after the final review is
  clean (the C15 one was archived to scratchpad then deleted).
- Pre-existing red (NOT yours): `tests/compile/tcompile_a12_*` and
  `tcompile_a2_*` fail standalone `nim c` with UnusedImport, masked in
  megatest; reproduced on clean main. Leave them.
- Workflow/subagent empty-result caveat: check the workflow
  `journal.jsonl` or re-derive inline before trusting a summary.

## The road ahead

1. Re-ask the execution question → execute the L5 plan Tasks 0–17
   exactly as written (per-task gates and the empty-snapshot check are
   IN the tasks). Continuous execution; stop only for BLOCKED,
   genuine forks, or completion.
2. Final whole-branch review (opus) → ONE fix wave → push
   `api/l5-c-abi` + open the PR (commissioned), body recommending
   `just test-full` AND a manual live `bin/jmap-c-cli` run pre-merge.
   User merges.
3. After merge: sync main, delete the branch. Open items at the
   user's discretion: B6/P18 ship-or-affirm (sole pre-tag decision),
   the bench's FINDINGS section feeding a v1.1 additive pass, C6's
   Nim-side half, D20 layer-doc uplift, H7 (CI mechanisation of
   check-public-only), deferred D1/D1.5/D9/D18.
