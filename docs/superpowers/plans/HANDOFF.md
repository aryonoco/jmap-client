<!--
SPDX-License-Identifier: BSD-2-Clause
Copyright (c) 2026 Aryan Ameri
-->

# HANDOFF — Layer-5 C ABI execution

**You are the controller for an in-flight, subagent-driven implementation.**
Tasks 1–15 of 17 are done and reviewed clean. Your job is Tasks 16 and 17,
then the final whole-branch review, then the PR.

**STOP: the owner has paused execution before Task 16.** Do not dispatch it
until they say to. Read this file, confirm the state below, and wait.

This document is transient orientation, rewritten before each compaction. The
plan and the design docs are the durable record. Where they disagree with this
file about *what to build*, they win. Where this file records an owner ruling
or a hard-won gotcha, it wins — those are things the plan cannot know.

---

## 1. What this project is

`jmap-client` is a cross-platform JMAP (RFC 8620 core, RFC 8621 mail) client
library in Nim, designed from the outset to be consumed from C. It is a
showcase project: the owner cares about the API being *exemplary*, not merely
working. Layers are L1 types → L2 serde → L3 protocol → L4
client/transport/one-shots → **L5 C ABI**, and L5 is what this branch builds.

The library ships as `bin/libjmap_client.so` with a hand-curated C header at
`include/jmap_client.h`. The C surface is modelled on **libcurl and SQLite** —
opaque handles, paired `_new`/`_free`, status-code returns with
out-parameters, library-owned borrows.

**Two separate rules about those two libraries, do not confuse them:**

- When *you* face a C API design fork, frame the options against what libcurl
  and SQLite actually do, and **verify the claim** (read the installed headers
  under `/usr/include/aarch64-linux-gnu/curl/`, or fetch the docs) rather than
  asserting it from memory. The owner has rejected an unverified framing.
- The **header file itself must never mention them.** The owner had all such
  comparisons removed. `include/jmap_client.h` is the only file a C developer
  is expected to read, and it must stand alone.

`CLAUDE.md` at the repo root is the project's own standing instruction set and
binds you.

---

## 2. Read these, in this order

1. `CLAUDE.md` — conventions, commands, coding rules. Binding.
2. `docs/design/17-L5-FFI-Principles.md` — **authoritative** for L5: error
   model, handle lifecycle, borrow rules, threading, versioning, the header
   and its gates. ~510 lines. Read in full. Note it still carries stale
   pre-1.0-contradicting text that Task 17 fixes (see §8).
3. `docs/superpowers/plans/2026-08-04-l5-c-abi.md` — **the plan you execute**.
   6416 lines, 18 tasks. Read the header, **Global Constraints** and the
   **File Map** in full. Do NOT read the task bodies — extract those one at a
   time with `scripts/task-brief` and hand the path to an implementer.
   Reading task bodies into your own context is the single most expensive
   mistake available to you.
4. `.superpowers/sdd/2026-08-04-l5-c-abi/progress.md` — **the ledger**, 1657
   lines, git-ignored. Your recovery map and the full per-task record. Read it
   in full; it is long but it is the only place many rulings exist.
5. `.superpowers/sdd/2026-08-04-l5-c-abi/minor-defect-register.md` — 165
   lines, 26 items (A1–E13). Leftover minors awaiting the owner's triage at
   the end. Read it; you present it in the finishing sequence.
6. `docs/TODO/pre-1.0-api-alignment.md` — status dashboard only, for context.

Do not read `docs/superpowers/specs/`; the plan supersedes it for execution.

---

## 3. Where things stand

Branch `api/l5-c-abi`, forked from `main` at `d234e03`. HEAD `0c23ed3`, **58
commits**, clean tree. `just ci` green, `just test-c` green (13 C programs
under ASan+UBSan, **zero suppressions**), **102 exported C symbols**, header
953 lines, and `git diff tests/wire_contract/` shows **only** the new
`c-header.txt` — the Nim public surface has not moved.

**Done (1–15):** init/version/strerror and the init latch; the client handle
with its per-handle error slot, `jmap_errmsg` and `jmap_errtype`;
bring-your-own-HTTP (C transport vtable → Nim closures) plus the
`ctests/canned.h` offline harness; account accessors over a lazy session
fetch; the wire-debug callback; result objects for mailboxes, emails,
threads/identities/vacation; the email write verbs with partial-success set
results; the vacation update handle; state bootstrap and incremental sync; the
query handle; the send message handle; the three header gates H18/H19/H20 plus
CI wiring; and the panic-surface audits.

**Plus, at the owner's request and outside the plan:** the entire
`include/jmap_client.h` comment set was rewritten in plain English in
libcurl's style (`e8415c2`, `0c23ed3`). Proven comments-only: stripping all
comments from the current file and from the pre-rewrite original leaves
byte-identical text.

**Left (16–17):** the C bench `examples/jmap-c-cli` (16), and docs/skills/
ledger close-out (17). Then the final whole-branch review, one fix wave, the
register triage, the commit-message decision, workspace deletion, and the PR.

Three commits are **out of plan scope** and must be called out in the PR body:
`a0e50c7` (REUSE licence-lint fix for pre-existing breakage that blocked every
commit gate), `0bd94a3` (a pre-existing Layer-4 memory leak, see §7.2), and
the `cfd6347`/`040e2bc` pair (a wrong RFC citation corrected at its source in
untouched Layer 4).

---

## 4. The execution model

Load `superpowers:subagent-driven-development` (6.2.0) with the Skill tool and
follow it. Scripts:

```
/home/vscode/.claude/plugins/cache/claude-plugins-official/superpowers/6.2.0/skills/subagent-driven-development/scripts/
```

Workspace (git-ignored): `/workspaces/jmap-client/.superpowers/sdd/2026-08-04-l5-c-abi/`

**Per-task loop, exactly as run for Tasks 1–15:**

1. `scripts/task-brief <plan> N` → writes `task-N-brief.md`, prints the path.
2. Record BASE = `git rev-parse HEAD`.
3. Dispatch ONE implementer (never parallel implementers on the same files).
   The dispatch contains: one line on where the task fits; the brief path
   introduced as *"read this first — it is your requirements, with the exact
   values to use verbatim"*; what earlier tasks produced that the brief cannot
   know; the binding Global Constraints copied verbatim; the accumulated
   gotchas from §7 that apply; the report path; and the short return contract.
   **Never paste plan text or prior-task history into a dispatch.**
4. Controller-verify before review — see §6, and do it every time.
5. `scripts/review-package <plan> BASE HEAD` → dispatch the task reviewer with
   that path plus the brief and report paths, and a constraints block that
   acts as its attention lens. **Never pre-judge** — do not tell a reviewer
   what not to flag. Naming an *area* to scrutinise is fine and valuable;
   telling it what to conclude is not.
6. Fix loop: rounds 1–3 resume the SAME implementer via SendMessage with the
   findings verbatim; rounds 4–5 use a fresh implementer one tier up. Every
   round ends with a scoped re-review over `FIX_BASE..HEAD`. Cap 5 rounds,
   then adjudicate.
7. Append the completion line to the ledger, then move on.

**Models — always specify explicitly.** `sonnet` for implementers on tasks
whose plan text carries complete code, and for scoped re-reviews of small
mechanical fix diffs. `opus` for every task reviewer, for re-reviews touching
a template or a memory-safety boundary, for judgement-heavy implementation
(Tasks 14–17 were all opus), and for the final whole-branch review. Never
Haiku. Never omit the model.

**Reviewer `⚠️ Cannot verify from diff` items are YOURS to resolve** — you hold
the cross-task context the reviewer lacks. Resolve each before completing the
task; if one is a real gap it enters the fix loop.

**Do not fix findings yourself.** Controller fixes pollute your context and
skip review. The exceptions already exercised: amendments to the *plan
document* are controller work (dispatched to a subagent, committed separately,
`just ci` green first), and repairing a damaged working tree (see §7.16).

**A scoped re-review may be skipped only when the tracked diff is provably
empty** — a message-only amend where `git diff OLD NEW` is empty. Record the
determination in the ledger; never skip silently. This has been done twice and
both are documented there.

---

## 5. The owner's rules — non-negotiable

**Ask at every fork.** At any genuine decision point — design, scope, naming,
doc treatment, process — do not assume. Use `AskUserQuestion`, **one question
per message**, 2–4 viable options, recommendation first and labelled
"(Recommended)". Give the *repercussions* of each option, not just the choice,
and put the framing prose in the message body rather than only in the option
blurbs — under-contextualised questions have been rejected. For C API forks,
frame against verified libcurl/SQLite behaviour (§1). Nine forks have been
raised and answered this way; every one improved the result.

**No 1.0 freeze.** The repo has had zero users outside the owner. 1.0 gets
called only after real-world use. Nothing on this branch may declare 1.0 or
promise ABI stability. Version macros are `0.1.0` and stay there. The header
gates are **change detectors**, not compatibility promises, and their own
docstrings say so. This binds Task 16's README and Task 17's doc amendments.

**Route minors into fix rounds.** Minor findings that are genuine violations
of the stated principles get fixed in the round, not deferred. Only what is
genuinely out of scope, cross-cutting or contestable goes to the register,
which is presented to the owner **at the end** for triage.

**Plan-mandated findings are the owner's call** — but only when fixing one
would *contradict* the plan. Strengthening something the plan under-specified
(e.g. adding assertions to a weak test) is additive, not contradictory, and
goes straight into the fix round.

**Never spawn a Workflow-tool fan-out** without the owner's direct, explicit
authorisation. Ultracode being on is *not* authorisation.

**Quality gates, before every commit:**
- `just fmt && just fmt-check`
- `just ci` green — now includes `lint-defect-audits`, `build`, the three
  header gates, and `test-c`
- `just test-c` green — every C test, ASan+UBSan, **zero suppressions**
- `git diff tests/wire_contract/` shows **only** `c-header.txt`. If
  `public-api.txt`, `type-shapes.txt` or `error-messages.txt` moves, a `*`
  leaked: fix the leak, never re-freeze.
- New C symbols present in `nm -D bin/libjmap_client.so`

**`just test-full` and the live-server suite are the OWNER's to run.** Do not
attempt them; `test-full` hard-errors without live JMAP servers anyway.

**Git:**
- Kernel-style commits: `subsystem: imperative subject` under 75 chars, body
  wrapped ~75 columns explaining **why**, ending with EXACTLY:

  ```
  Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
  Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
  Assisted-by: Claude:claude-5-fable
  ```

  No other AI/LLM attribution anywhere. PR bodies carry **no** Claude/AI
  footer.
- **No scaffolding references in commit bodies** — no `task`, `round`,
  `review`, `ledger`, `brief` or finding numbers. Six violations have been
  caught. Grep every body before committing. (Naming the plan document in a
  commit that *edits* the plan document is a self-reference, not a violation.)
- Never name a file in a commit body without checking it exists.
- Stage explicit paths only. **NEVER `git add -A`.**
- Never implement on `main`. **No worktree** — this project works on a branch
  in the main tree.
- **The owner merges.** You open the PR; you never merge it.

**Communication:** report faithfully. If a test fails, say so with the output.
Never claim work is done until it is verified. Keep narration between tool
calls to one short line.

---

## 6. Controller verification — run this after every single task

Agents have reported "working tree clean" while the tree was damaged. Verify,
never trust the claim:

```sh
git status --porcelain                      # MUST be empty
git log --oneline BASE..HEAD
git log BASE..HEAD --format='%h|%B' | grep -niE '\btask\b|\bround\b|\breview\b|ledger|\bbrief\b|finding'
git diff --stat d234e03 -- tests/wire_contract/   # only c-header.txt
grep -nE '^\s*(func|proc)\s+\w+\*.*\{\.exportc' src/jmap_client.nim   # must be empty
nm -D bin/libjmap_client.so | grep -c ' T jmap_'
```

Also confirm every file named in a commit body exists, and re-run `just ci`
yourself after any concurrent work — an agent's green run is evidence about
the tree at *its* moment, not yours.

---

## 7. Gotchas — every one has already cost this branch

**7.1 Narrowing a caller-supplied `csize_t` — this class shipped THREE times.**
A range-checked conversion of a value ≥ 2^63 raises `RangeDefect` and
**terminates the host process** through a `cdecl` boundary declared
`raises: []`. The rule is **any** narrowing of a caller-supplied `size_t` —
index, count, length or offset — validates in the unsigned domain FIRST.
Every such site gets a `SIZE_MAX` assertion in its C test. A compile-time
audit now covers this class at the L5 boundary; see §8, Task 15's entry.

**7.2 A user-defined `=destroy` suppresses the compiler's generated field
destruction.** `TransportObj` declared one and never released its two closure
fields, leaking ~3.1 KB per client. Fixed in `0bd94a3`. If a task defines any
`=destroy` on a type with fields, it owns releasing every field by hand.
**Prefer not defining one at all** — every L5 handle relies on the generated
destructor, which is why they are leak-free.

**7.3 `-d:useMalloc` is what makes the sanitisers see anything.** Without it
Nim takes pages via mmap and LeakSanitizer observes nothing. That is why
`just test-c` runs with **zero suppressions**, and why a leak an implementer
introduces is a hard failure to fix, never suppress.

**7.4 A test or gate that cannot fail is worse than none — this class has now
recurred FOUR times.** A vacuous assertion reading back a canned constant
(Task 11); a gate passing on empty input (Task 14); a pre-existing audit green
over an empty string (Task 15); and the narrowing rule passing on zero
routines (Task 15 again, *inside the fix for the previous one*). **Put this in
every review lens.** Require: a deliberate violation, the exact failure
message, restoration, and a check that empty/missing input is refused.

**7.5 `staticRead` in macro-argument position silently returns `""`.** It is
folded under `tryConstExpr`, which both silences and un-counts the "cannot
open file" error (`vmdeps.nim:18-30`, `sem.nim:362-403`). A stale path
therefore compiles green while auditing nothing. Put `staticRead` in the macro
**body**, and add a length backstop.

**7.6 Fixtures must be generated, never hand-written.** The strict decoder
rejects hand-written session JSON. Generate via a throwaway `nim r` echo,
round-trip through the real decoder, paste, delete the throwaway. The shared
`SESSION_JSON` is reused verbatim across `ctests/t03…t12`.

**7.7 `usableAccount` (`src/jmap_client/internal/protocol/preflight.nim:40-62`)
treats `accountCapabilities` as authoritative**; `primaryAccounts` is merely a
pointer into it. A fixture with `accountCapabilities: {}` cannot resolve a
mail account whatever `primaryAccounts` says.

**7.8 Docstrings must not assert properties the code does not guarantee.**
Eleven instances caught. The worst were an RFC *inference* that did not follow
from the cited text, a claimed losslessness, a documented error outcome that
was unreachable, and a safety caveat true for one bound kind and false for
another. **Disclose limits in the file, not only in the report** — reports are
deleted when the work lands.

**7.9 `docs/rfcs/` is authoritative — verify every section number against the
text.** Wrong citations were introduced twice by *fix rounds*. One wrong
citation existed in untouched L4 and was corrected at source so it would stop
propagating.

**7.10 Reports overstate.** Three report-accuracy gaps caught: a claimed
correction never applied; a plausible mitigation ("compile-and-link catches
type mismatches") that was false under test; an invented justification
attributing an instruction to the brief. Reviewers must verify claims against
the diff, and mutation proofs must name an assertion that exists in the landed
file.

**7.11 Set errors are DATA inside a successful response.** A call returns
`JMAP_OK` while individual ids fail. The wire type string reaches C losslessly.
The per-handle error slot must not be polluted by per-id refusals.

**7.12 Result collections come back in server order, not submission order.**
A consumer correlating by index mispairs silently. The header says to match by
id.

**7.13 nimalyzer's complexity ceiling is 10 and no `ruleOff` is permitted** —
decompose along a real seam. Note that refactors forced by the ceiling are
where behaviour quietly changes; re-prove the affected guard afterwards.

**7.14 `warningAsError` traps:** `CStringConv`, `PtrToCstringConv`,
`AnyEnumConv`, and `XDeclaredButNotUsed` — an unused symbol is a build
failure, which invalidated one mutation proof.

**7.15 Two tables that must DIFFER are not a duplication to eliminate.** A DRY
merge of a conversion-target width table and a bound-ceiling width table made
a safety audit *less* sound while looking like cleanup. One type can
legitimately carry two widths when the two roles have opposite safe
directions.

**7.16 An agent deleted 82 tracked files from the working tree.** A
mutation-testing cleanup reached outside its isolated copy and removed
`tests/serde/captured/` entirely. Nothing was committed;
`git checkout -- <path>` restored it byte-identically. **Tell every dispatch
not to delete or move files**, and run the §6 check after every task.

**7.17 Pre-existing red to leave alone:** `tests/compile/tcompile_a12_*` and
`tcompile_a2_*` fail under standalone `nim c` (UnusedImport) but are masked in
the megatest. Not yours.

---

## 8. Settled decisions — do NOT re-litigate

Nine owner rulings, all recorded in the ledger with their evidence:

1. **All L5 symbols are Nim-private**: `{.exportc: "jmap_x", dynlib, cdecl,
   raises: [].}` with **no** `*`. Adding `*` moves the frozen Nim surface.
2. **Latch scope narrowed**: `l5Initialised` binds only exports that allocate
   GC'd memory or return `jmap_status`. Pure reads through a live handle and
   the `*_free` family are exempt.
3. **C tests live in top-level `ctests/`**, never under `tests/` — testament's
   `all` mode hard-asserts on a `tests/<dir>/` holding zero `.nim` files.
4. **L5 projects over existing public Layer-4 API.** Where a one-shot exists
   it MUST be called. If a task needs an operation no public L4 symbol
   provides, the implementer reports **BLOCKED** and you escalate.
5. **Handle boxes use `createShared`/`deallocShared`** with
   `` `=destroy`(handle[]) `` immediately before the free; `.so` built
   `-d:useMalloc`.
6. **Configuring an operation uses a handle plus typed setters**, never a wide
   flat function. This was ruled three times: the vacation update handle, the
   query handle, and the message handle for send. `set_str` replaces;
   `jmap_message_add_str` appends to list-valued roles; passing NULL to a
   setter clears. The reasoning each time was that a fixed arity cannot grow
   and that eight consecutive `const char *` parameters make a silent
   transposition possible.
7. **`jmap_errtype()` exists** so method-error types are machine-readable.
   Error *text* is for humans; branching on it is what the reference libraries
   explicitly warn against.
8. **The four non-joinable compliance audits are gated** in `check`, `ci` and
   hosted CI via `lint-defect-audits` (~2.9 s). They previously ran only under
   `just test-full`, which is why one of them rotted unnoticed.
9. **The narrowing audit is scoped to every routine in `src/jmap_client.nim`**,
   not only `{.exportc.}` ones — the third historical incident was in a
   private helper reached through an exported entry point.

Doc 17's dated amendments are written in **Task 17 only** — do not edit doc 17
before then.

---

## 9. Lookahead for Tasks 16 and 17

Per-task requirements live in the plan; these are the risks *around* them.

- **Task 16 (C bench, `examples/jmap-c-cli`)** — opus. CI builds it only; the
  live run stays manual, because hosted CI stands up no JMAP server. The bench
  is the first *consumer* of the C API written from outside, so treat anything
  awkward in it as a finding about the API, not about the bench. Its README
  must not claim stability. The plan's `cmd_send` uses `set_str` only (one
  recipient) — deliberate, recorded. Its `cmd_vacation` was updated when the
  vacation surface was reshaped.
- **Task 17 (close-out)** — opus. The *only* task that edits
  `docs/design/17-L5-FFI-Principles.md`, and it adds **dated amendments**
  rather than editing ratified rows. Amendments owed: the shared-heap handle
  pair; the bench building in CI with a manual live run; the query typed
  setters; the lazily-fetching account accessors; and — added this session —
  **doc 17 still asserts "ordinals never reused, nothing removed after v1" and
  claims the header states an additive-only rule, both of which the pre-1.0
  header rewrite made false.** Also touches `.claude/rules/nim-ffi-boundary.md`
  and the skill files, and `docs/TODO/pre-1.0-api-alignment.md`. **`.claude/`
  files are timeless** — no dates, no ledger IDs, no settled-narration.

---

## 10. Finishing

1. All tasks complete → `scripts/review-package <plan> $(git merge-base main HEAD) HEAD`
   → dispatch the final whole-branch reviewer on **opus** using
   `superpowers:requesting-code-review`'s `code-reviewer.md`. **Point it at
   the register and at the ledger's deferred-minor lines** so it can triage
   what must be fixed before merge. This is the first look at all 58+ commits
   together.
2. ONE fix wave for its findings — a single subagent with the complete list,
   not one fixer per finding — then exactly one scoped re-review of that wave.
   Adjudicate residuals: park with a ruling, or stop on load-bearing ones.
3. **Present the minor-defect register to the owner for triage.** 26 items,
   A1–E13, in `minor-defect-register.md`. Two need their explicit word:
   - **C1: the branch-wide commit-message rewrite.** Two subjects literally
     read `ffi: fix vacation-view review round 1`, plus bodies referencing
     task numbers, all predating this session. ~15 commits, message-only,
     trees provably unchanged. Cheapest done once, immediately before the PR.
   - **D1: the send envelope gap** — no `replyTo`/`inReplyTo`/`references`, so
     a C consumer can send but cannot reply in-thread. Needs an L4 widening,
     which is post-1.0 and the owner's call.
4. `rm -rf` this plan's workspace directory. Git history is the record.
5. `superpowers:finishing-a-development-branch`, base branch `main`.
6. Push and open the PR. The body must:
   - note the Nim public surface did **not** move (only `c-header.txt` is new);
   - flag the out-of-scope commits `a0e50c7`, `0bd94a3`, `cfd6347`/`040e2bc`,
     with why each was unavoidable;
   - state the library is **pre-1.0** with no ABI compatibility promise;
   - name the C API's known limitation (no in-thread reply, D1);
   - recommend the owner run `just test-full` **and** a manual live
     `bin/jmap-c-cli` run before merging;
   - carry **no** Claude/AI footer.
7. **The owner merges.** Not you.
