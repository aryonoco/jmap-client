<!--
SPDX-License-Identifier: BSD-2-Clause
Copyright (c) 2026 Aryan Ameri
-->

# HANDOFF — Layer-5 C ABI execution

**You are the controller for an in-flight, subagent-driven implementation.**
Tasks 1–9 of 18 are done and reviewed clean. Your job is Tasks 10–17, then the
final whole-branch review, then the PR.

This document is transient orientation, rewritten before each compaction; the
plan and the design docs are the durable record. Where they disagree with this
file about *what to build*, they win. Where this file records an owner ruling
or a hard-won gotcha, it wins — those are things the plan cannot know.

---

## 1. What this project is

`jmap-client` is a cross-platform JMAP (RFC 8620 core, RFC 8621 mail) client
library in Nim, designed from the outset to be consumed from C. It is a
showcase project: the owner cares about the API being *exemplary*, not merely
working. The Nim API is frozen pre-1.0 after a long alignment campaign. Layers
are L1 types → L2 serde → L3 protocol → L4 client/transport/one-shots → **L5 C
ABI**, and L5 is what you are building.

The library ships as `bin/libjmap_client.so` with a hand-curated C header at
`include/jmap_client.h`. The C surface is modelled on **libcurl and SQLite** —
opaque handles, paired `_new`/`_free`, status-code returns with out-parameters,
library-owned borrows. That comparison is not decoration: the owner uses it as
the deciding argument at design forks, and so should you.

`CLAUDE.md` at the repo root is the project's own standing instruction set and
binds you.

---

## 2. Read these, in this order

1. `CLAUDE.md` — conventions, commands, coding rules. Binding.
2. `docs/design/17-L5-FFI-Principles.md` — **authoritative** for L5: error
   model, handle lifecycle, borrow rules, threading, versioning, the header and
   its gates, the P1–P29 principle map. ~510 lines. Read in full.
3. `docs/superpowers/plans/2026-08-04-l5-c-abi.md` — **the plan you execute**.
   5054 lines, 18 tasks. Read the header, **Global Constraints (lines 34–124)**
   and the **File Map (from line 125)** in full. Do NOT read the task bodies —
   extract those one at a time with `scripts/task-brief` and hand the path to
   an implementer. Reading task bodies into your own context is the single most
   expensive mistake available to you.
4. `.superpowers/sdd/2026-08-04-l5-c-abi/progress.md` — **the ledger**, ~530
   lines, git-ignored. Your recovery map and the per-task record: every
   completion, fix round, deferred minor and owner ruling. Read in full.
5. `docs/TODO/pre-1.0-api-alignment.md` — status dashboard only, for context.

Do not read `docs/superpowers/specs/`; the plan supersedes it for execution.

---

## 3. Where things stand

Branch `api/l5-c-abi`, forked from `main` at `d234e03`. HEAD `4e3a543`, 26
commits, clean tree. `just ci` green, `just test-c` green (t01–t08 + t13 under
ASan/UBSan with **zero suppressions**), 72 exported C symbols, and
`git diff tests/wire_contract/` empty against the merge base.

**Done (1–9):** init/version/strerror and the init latch; the client handle
with its per-handle error slot and `jmap_errmsg`; bring-your-own-HTTP (C
transport vtable → Nim closures) plus the `ctests/canned.h` harness; account
accessors over a lazy session fetch; the wire-debug callback; and four result
objects — mailboxes, emails, threads/identities/vacation, and the email write
verbs with partial-success set results.

**Left (10–17):** Vacation set (10), state bootstrap and incremental sync (11),
Query — the typed setopt surface (12), Send (13), the header gates H18 + H19
(14), Tier-1 panic-surface macro tests (15), the C bench `examples/jmap-c-cli`
(16), docs/skills/ledger close-out (17). Then the final whole-branch review,
then the PR.

Two commits are **out of plan scope** and must be called out in the PR body:
`a0e50c7` (REUSE licence-lint fix for pre-existing breakage that blocked every
commit gate) and `0bd94a3` (a pre-existing Layer-4 memory leak — see §7.2).

---

## 4. The execution model

Load `superpowers:subagent-driven-development` (6.2.0) with the Skill tool and
follow it. Scripts:

```
/home/vscode/.claude/plugins/cache/claude-plugins-official/superpowers/6.2.0/skills/subagent-driven-development/scripts/
```

Workspace (git-ignored): `/workspaces/jmap-client/.superpowers/sdd/2026-08-04-l5-c-abi/`

**Per-task loop, exactly as run for Tasks 1–9:**

1. `scripts/task-brief <plan> N` → writes `task-N-brief.md`, prints the path.
2. Record BASE = `git rev-parse HEAD`.
3. Dispatch ONE implementer (never parallel implementers). The dispatch
   contains: one line on where the task fits; the brief path introduced as
   *"read this first — it is your requirements, with the exact values to use
   verbatim"*; what earlier tasks produced that the brief cannot know; the
   binding Global Constraints copied verbatim; the accumulated gotchas from §7
   that apply; the report path; and the short return contract. **Never paste
   plan text or prior-task history into a dispatch.**
4. Controller-verify before review: `git diff tests/wire_contract/` empty, no
   starred `exportc`, clean tree.
5. `scripts/review-package <plan> BASE HEAD` → dispatch the task reviewer with
   that path plus the brief and report paths, and a constraints block that acts
   as its attention lens. **Never pre-judge** — do not tell a reviewer what not
   to flag. If you think a finding would be a false positive, let it be raised
   and adjudicate it.
6. Fix loop: rounds 1–3 resume the SAME implementer via SendMessage with the
   findings verbatim; rounds 4–5 use a fresh implementer one tier up. Every
   round ends with a scoped re-review over `FIX_BASE..HEAD` — no exceptions,
   however small the fix. (A three-line "obvious" fix introduced a defect on
   this branch.) Cap 5 rounds, then adjudicate.
7. Append the completion line to the ledger, then move on.

**Models — always specify explicitly.** `sonnet` for implementers (the plan
carries complete code, so implementation is transcription plus testing) and for
scoped re-reviews of small fix diffs. `opus` for every task reviewer, for
re-reviews where the fix touched a template or a memory-safety boundary, for
judgement-heavy implementation (Tasks 14–17), and for the final whole-branch
review. Never Haiku. Never omit the model.

**Reviewer `⚠️ Cannot verify from diff` items are YOURS to resolve** — you hold
the cross-task context the reviewer lacks. Resolve each before completing the
task; if one is a real gap it enters the fix loop. Several of the best catches
on this branch came from doing this properly (ledger: Task 3's fixture gap,
Task 9's missing `move` coverage).

**Do not fix findings yourself.** Controller fixes pollute your context and skip
review. The one exception already exercised: amendments to the *plan document*
are controller work — dispatched to a subagent, committed separately from task
code, with `just ci` green first.

---

## 5. The owner's rules — non-negotiable

**Ask at every fork.** At any genuine decision point — design, scope, naming,
doc treatment, process — do not assume. Use `AskUserQuestion`, **one question
per message**, 2–4 viable options, recommendation first and labelled
"(Recommended)". Give the *repercussions* of each option, not just the choice,
and put the framing prose in the message body rather than only in the option
blurbs — under-contextualised questions have been rejected. When a fork is
about C API design, **frame it against what libcurl and SQLite actually do**,
and verify those claims rather than asserting them. Proceed only when every
outstanding fork is answered.

**Findings get applied, not quietly deferred.** Minor findings that are genuine
violations of the stated principles get fixed in the fix round. Only
contestable, cross-task or out-of-scope findings go to the ledger as deferred
minors. There are currently **13 deferred minors**; the final review triages
which must be fixed before merge.

**Plan-mandated findings are the owner's call.** If a finding conflicts with
what the plan's text requires, present the finding beside the plan text and ask
which governs. Do not dismiss it, and do not dispatch a fix that contradicts
the plan.

**Never spawn a Workflow-tool fan-out** without the owner's direct, explicit
authorisation. Ultracode being on is *not* authorisation. One workflow was
killed mid-run for being too large. Use individually dispatched subagents that
write to files and return short summaries, so a stopped run is salvageable.

**Quality gates, before every commit:**
- `just fmt && just fmt-check`
- `just ci` green — reuse, fmt-check, the full lint battery incl. the
  H15/H16/H17 snapshot locks, nimalyzer `analyse`, and the fast test suite
- `just test-c` green — every C test, ASan+UBSan, **zero suppressions**
- `git diff tests/wire_contract/` **empty** — the Nim public surface must not
  move. If a snapshot changes, a `*` leaked: fix the leak, never re-freeze.
- New C symbols present in `nm -D bin/libjmap_client.so`

**`just test-full` and the live-server suite are the OWNER's to run.** Do not
attempt them.

**Git:**
- Kernel-style commits: `subsystem: imperative subject` under 75 chars, body
  wrapped ~75 columns explaining **why**, ending with EXACTLY:

  ```
  Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
  Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
  Assisted-by: Claude:claude-5-fable
  ```

  No other AI/LLM attribution in any format, anywhere. PR bodies carry **no**
  Claude/AI footer. Do not put plan-internal task numbers in commit bodies —
  they mean nothing to a later reader of the history.
- Stage explicit paths only. **NEVER `git add -A`.**
- Never implement on `main`. **No worktree** — this project works on a branch
  in the main tree; that overrides the skill's worktree step.
- **The owner merges.** You open the PR; you never merge it.

**Communication:** report faithfully. If a test fails, say so with the output.
Never claim work is done until it is verified. Keep narration between tool
calls to one short line — the ledger carries the record.

---

## 6. Settled decisions — do NOT re-litigate

1. **Typed query setters** (`jmap_query_set_str` / `_u32`) replace doc 17 §5's
   variadic — Nim cannot read C varargs without `{.emit.}`, which is banned.
2. **Non-const, lazily-fetching account accessors** amend doc 17 §4 — connect
   performs no network IO; the session is fetched on first use.
3. **All L5 symbols are Nim-private**: `{.exportc: "jmap_x", dynlib, cdecl,
   raises: [].}` with **no** `*`. Verified: unstarred `exportc` symbols survive
   in the `.so`. Adding `*` moves the frozen Nim surface — never do it.
4. **Latch scope narrowed** (owner ruling): the `l5Initialised` check binds only
   exports that *allocate* GC'd memory or return `jmap_status`. Pure reads
   through a live handle and the `*_free` family are exempt — a handle is
   obtainable only from a constructor, and constructors check the latch, so a
   non-nil handle proves `NimMain()` ran. Use after `jmap_cleanup` is undefined
   by contract, as sqlite3 documents for post-shutdown use. A *redundant* latch
   check on a pure read is an inconsistency, not extra safety.
5. **C tests live in top-level `ctests/`**, never under `tests/` — testament's
   `all` mode hard-asserts on a `tests/<dir>/` holding zero `.nim` files
   (`categories.nim`), which breaks the `just ci` gate every task needs.
6. **L5 projects over existing public Layer-4 API** — the one-shots in
   `src/jmap_client/internal/one_shot.nim` for whole operations, the client
   handle and transport interface for the rest. Where a one-shot exists it MUST
   be called, never its builder/dispatch/extract sequence rebuilt. If a task
   needs an operation no public L4 symbol provides, the implementer reports
   **BLOCKED** and you escalate — widening the Nim API is not a task's call.
7. **Handle boxes use `createShared`/`deallocShared`** with
   `` `=destroy`(handle[]) `` immediately before the free; the `.so` is built
   `-d:useMalloc`. See §7.3 for why both matter.
8. **The C-header snapshot lock (H19)** is in scope, lands in Task 14. The
   bench's live run stays manual, recorded as a dated doc 17 amendment in Task
   17 — hosted CI (`.github/workflows/ci.yml`) stands up no JMAP server.

Doc 17's dated amendments are written in **Task 17 only** — do not edit doc 17
before then.

---

## 7. Gotchas — every one has already cost this branch

**7.1 Narrowing a caller-supplied `csize_t` — this class shipped THREE times.**
A range-checked conversion of a value ≥ 2^63 raises `RangeDefect` and
**terminates the host process** through a `cdecl` boundary declared
`raises: []`. `SIZE_MAX` is not exotic — it is what an ordinary `count - 1`
underflow produces at `count == 0`.

The rule is **not** "indexed accessors": the third instance was a *count*
parameter, and an implementer following the narrower rule faithfully still
shipped it. State it as: **any** narrowing of a caller-supplied `size_t` —
index, count, length or offset — validates in the unsigned domain FIRST and
narrows only a value already proven in range. Every such site gets a `SIZE_MAX`
assertion in its C test, and each assertion must be proven to **fail before**
the guard and pass after. Insist implementers demonstrate that by temporarily
reintroducing the bug; Tasks 8 and 9 did, and it works. The plan's listings
were swept in commit `312589e` — that sweep found **7 of 12 accessors had no
out-of-range assertion at all**.

**7.2 A user-defined `=destroy` suppresses the compiler's generated field
destruction.** `TransportObj` declared one and never released its two closure
fields, leaking ~3.1 KB per client since the transport was written. Fixed in
`0bd94a3` (out of scope; flag in the PR). If a task defines any `=destroy` on a
type with fields, it owns releasing every field by hand — nothing in the tree
enforces that, so check it by review.

**7.3 `-d:useMalloc` is what makes the sanitisers see anything.** Without it Nim
takes pages via mmap and LeakSanitizer observes no Nim allocation at all — 50
deliberately leaked handles produced no report. With it (`mmdisp.nim:72` selects
`system/mm/malloc`, where the shared allocators map onto the regular ones),
every Nim allocation is a tracked libc chunk. That is why `just test-c` runs
with **zero suppressions**, and why a leak an implementer introduces is a hard
failure to fix, never suppress.

**7.4 Do not trust `--mm:orc` as evidence about a leak.** ORC's generated
`=trace` still walks fields a user `=destroy` has stopped releasing, so a bug
can vanish under ORC while remaining a real defect. The project is `--mm:arc`
and stays that way.

**7.5 A pointer handed to C must never be NULL and never point at a per-call
temporary.** An empty payload gets a stable static sentinel — a file-scope
`const` array, verified in the generated C to be `NIM_CONST` static storage.
`memcpy(dst, bytes, 0)` from NULL is UB and a consumer will write it.

**7.6 Absent must stay distinguishable from present-but-empty.** Where it
genuinely cannot be, the header must say so explicitly.

**7.7 Docstrings must not assert properties the code does not guarantee.** Four
instances so far: "never a defect" (it aborted), "always populated" (a presence
check can return NULL), "NULL when absent" (returns `""`), and a blanket rule
wrong for one non-optional field.

**7.8 Projections to a frozen C ordinal must be exhaustive `case` expressions**
— one arm per member, **no `else`**, no array literals — so an L4 *addition* is
a compile error, not a silent degradation. Pinning against a *reorder* is not
enough. Prove exhaustiveness by adding an L4 enum member in a scratch copy and
confirming the build breaks; a reviewer did exactly that for Task 6.

**7.9 `docs/rfcs/` is authoritative — verify every section number against the
text.** A plausible-but-wrong citation was introduced *by a fix round* and had
to be corrected along with its source in untouched L4. A wrong reference is
worse than none.

**7.10 Fixtures must be generated, never hand-written.** The strict decoder
rejects hand-written session JSON. Generate from `tests/mfixtures.nim`'s
builders (or the real captures under `tests/testdata/captured/`) via a throwaway
`nim r`, round-trip through the real decoder, paste, and delete the throwaway.
The shared `SESSION_JSON` — two accounts, A1 mail-primary, Z9 non-mail,
deliberately out of ascending order — is used by t03–t08 and t13; reuse it.

**7.11 `usableAccount` (`src/jmap_client/internal/protocol/preflight.nim:40-62`)
treats an account's own `accountCapabilities` as authoritative**;
`primaryAccounts` is merely a pointer into it. A fixture with
`accountCapabilities: {}` cannot resolve a mail account whatever
`primaryAccounts` says. This silently broke a fixture once.

**7.12 Set errors are DATA inside a successful response**, not errors on the
rail. A call returns `JMAP_OK` while individual ids fail; the wire type string
(`rawType`) must reach C losslessly; the per-handle error slot must not be
polluted by per-id refusals.

**7.13 Result collections come back in server-table order, not submission
order** — verified nondeterministic. A consumer correlating by index against
its own array mispairs silently. The header must say so and say to match by id.

**7.14 nimalyzer's complexity ceiling is 10 and no `ruleOff` is permitted** —
decompose along a real seam. Do not proliferate `…Tail` helpers by reflex; one
exists in Task 6 and is acknowledged as a mechanical cut, not a model.
`objects publicfields` is incompatible with encapsulated types, so
`{.ruleOff: "objects".}` on L5 handle/view types is sanctioned and has 181
precedents in `src/`.

**7.15 `warningAsError` traps:** `CStringConv`, `PtrToCstringConv`,
`AnyEnumConv`. Copy the existing ordinal-matching idioms; never cast
`int` → `enum`.

**7.16 Pre-existing red to leave alone:** `tests/compile/tcompile_a12_*` and
`tcompile_a2_*` fail under standalone `nim c` (UnusedImport) but are masked in
the megatest. Not yours.

---

## 8. Lookahead for Tasks 10–17

Per-task requirements live in the plan; these are the risks *around* them.

- **Task 10 (Vacation set)** — Task 8 established that a `VacationResponse/get`
  list whose length is not exactly 1 answers `JMAP_E_PROTOCOL` rather than
  splicing a record that never existed on the wire (RFC 8621 §8.1: "There MUST
  only be exactly one VacationResponse object in an account"). Keep the set
  path consistent with that.
- **Task 11 (state bootstrap / incremental sync)** — introduces state strings
  and a sync handle. Watch borrow lifetime across a state refresh, and whether
  a stale state token is distinguishable from an absent one.
- **Task 12 (Query — typed setopt)** — the query handle stores **core-typed**
  values (`Opt[Filter[EmailFilterCondition]]`, `Opt[seq[EmailComparator]]`,
  `QueryParams`) that the setters validate at the boundary; there is no
  lowering at the call site. The query handle has no error slot, so misuse is
  code-granular. Expect a compiler fight around `resp.get().get`; the plan
  carries a let-bound fallback.
- **Task 13 (Send)** — projects the `sendPlainText` one-shot; addresses are
  parsed onto the rail internally.
- **Task 14 (header gates)** — **opus**. Builds H18 (both-directions exportc ↔
  header name inventory) and H19 (the C-header snapshot: parameter types, enum
  ordering, struct field order, version macros — what an inventory cannot see),
  modelled on `tests/lint/h16_public_api_snapshot.nim` and
  `h17_type_shape_snapshot.nim` with their paired justfile recipes, and
  `scripts/render_c_header.nim` shared between freeze and lint the way
  `scripts/api_oracle.nim` is. **`tests/wire_contract/c-header.txt` is the one
  file in this plan written by a freeze recipe** — the sole exception to the
  no-freeze rule. This task also wires `build`, the header gates and `test-c`
  into `just ci` and into `.github/workflows/ci.yml`; note hosted CI currently
  runs a *subset* of `just ci` and no live servers.
- **Task 15 (Tier-1 panic-surface macro tests)** — **opus**. Has a **STOP rule:
  if it requires more than 15 source changes, report BLOCKED.** Verify
  `tffi_panic_surface.nim`'s `staticRead` paths resolve.
- **Task 16 (C bench, `examples/jmap-c-cli`)** — **opus**. CI builds it only;
  the live run stays manual.
- **Task 17 (close-out)** — **opus**. The *only* task that edits
  `docs/design/17-L5-FFI-Principles.md`, and it adds **dated amendments**
  rather than editing ratified rows. Amendments owed: §2 (the shared-heap
  handle pair) and §11/§12 (bench builds in CI, live run manual). Also touches
  `.claude/rules/nim-ffi-boundary.md` and the skill files (visibility
  correction) and `docs/TODO/pre-1.0-api-alignment.md`. **`.claude/` files are
  timeless** — no dates, no ledger IDs, no settled-narration.

---

## 9. Finishing

1. All tasks complete → `scripts/review-package <plan> $(git merge-base main HEAD) HEAD`
   → dispatch the final whole-branch reviewer on **opus** using
   `superpowers:requesting-code-review`'s `code-reviewer.md`. **Point it at the
   ledger's deferred-minor and parked lines** so it can triage which must be
   fixed before merge.
2. ONE fix wave for its findings — a single subagent with the complete list,
   not one fixer per finding — then exactly one scoped re-review of that wave.
   Adjudicate residuals: park with a ruling, or stop on load-bearing ones.
3. `rm -rf` this plan's workspace directory. Git history is the record.
4. `superpowers:finishing-a-development-branch`, base branch `main`.
5. Push and open the PR. The body must:
   - note the Nim public surface did **not** move (empty wire-contract diff);
   - flag the two out-of-scope commits, `a0e50c7` (REUSE) and `0bd94a3` (the L4
     transport leak), with why each was unavoidable;
   - recommend the owner run `just test-full` **and** a manual live
     `bin/jmap-c-cli` run before merging;
   - carry **no** Claude/AI footer.
6. **The owner merges.** Not you.
