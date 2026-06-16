<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# S3 EXECUTION HANDOFF — implement "Complete the core"

> **You are a fresh agent with ZERO prior context. Read this whole document
> before doing anything.** Your job is to **implement sub-project S3** of an
> in-flight API-refactor campaign on the `jmap-client` library, using the
> **subagent-driven-development** approach. The design is already approved and
> the implementation plan is already written, reviewed, and committed — you are
> the *executor*, not the designer.
>
> **Last updated 2026-06-16.** Branch `api/s3-complete-the-core` is checked out
> with the S3 plan committed; `main` has S0 + S1 + S2 + the RFC-conformance sweep
> all merged.

---

## 0. TL;DR — what to do, right now

1. **Read, in full, before anything:** this document; then
   `docs/superpowers/plans/2026-06-16-s3-complete-the-core-plan.md` (the
   task-by-task implementation plan you will execute); then
   `docs/superpowers/specs/2026-06-16-s3-complete-the-core-design.md` (the design
   rationale, gitignored — read from disk); then the campaign-wide orientation
   `docs/superpowers/plans/2026-06-15-CAMPAIGN-HANDOFF.md`; then
   `docs/design/14-Nim-API-Principles.md` (the 29-principle rubric).
2. **Confirm your position:** `git status` (expect clean), `git branch
   --show-current` (expect `api/s3-complete-the-core`), `git log --oneline -3`
   (the top commit is the S3 plan, `docs/s3: plan the Complete-the-core
   sub-project (R2)`). If you are not on that branch, `git checkout
   api/s3-complete-the-core`. Do **not** implement on `main`.
3. **Internalise §2 (the design lens) and §6 (quality requirements) of THIS
   document — they override everything else on conflict.**
4. **Execute the plan with `superpowers:subagent-driven-development`** — a fresh
   subagent per task, two-stage (spec then quality) review, you review the full
   diff and re-run the gate yourself before each commit. See §5.
5. **Confirm with the human before any push / PR / merge.** All prior
   sub-projects merged via PR only after explicit go-ahead.

---

## 1. The mission (the human's own words — verbatim, the prompt that began this)

> Note about the project: The layer 5 C FFI is deferred for now and push and
> blob upload/download are also deferred for now. Other than that, I believe I
> have implemented all of RFC 8620 and RFC 8621 here.
>
> Now I'm focused on the project's API from the pov of an application developer,
> a consumer of the library. This project is supposed to be a library which other
> application developers can then use and link to to add JMAP support to their
> email clients, allowing their clients to talk to JMAP servers. Libraries like
> this live or die by their API design.
>
> I defined a set of 29 API Principles for this project to adhere to which are
> defined in `docs/design/14-Nim-API-Principles.md`.
>
> I delivered some of the required API enhancements in git commit
> `39e4891aac531759440fcede26a0d7c2e7c4fae1`.
>
> As a way to test the quality of the API to see if it adheres to my principles,
> I built an example CLI app, completely separate from the library and trying to
> just use the public API of the library to communicate and talk to JMAP servers.
> Send and receive actual email and do all the things which an email client is
> supposed to do. The important thing however is not to have a pretty CLI but to
> document all aspects of the public API of the library from the perspective of
> an application developer. A first revision of this CLI was built in commit
> `96cea22ac075686c4487b9ed2b3dbc459c3e765e`, and it made clear that the API is
> in a horrible state.

**So:** RFC 8620 (JMAP core) + RFC 8621 (JMAP mail) are implemented; **Layer-5 C
FFI, Push (RFC 8620 §7), and Blob upload/download are deferred** campaign-wide.
The work is **API-design quality**, judged by a real consumer (the
`examples/jmap-cli/` bench) against the **29 API principles**. The resulting
public API must follow the patterns of **libcurl and SQLite** and avoid the
failure modes of **OpenSSL and libdbus**.

---

## 2. THE NON-NEGOTIABLE DESIGN LENS (read twice — overrides any principle on conflict)

These are the human's own words. They govern **every** design and implementation
decision. When a principle, a test, a current caller, or your own instinct
conflicts with one of these, **the lens wins.**

1. **The ONLY design input is the future application developer** who will consume
   this library to add JMAP support to an email client. Model the API after
   **libcurl and SQLite**; actively avoid the failure modes of **OpenSSL and
   libdbus**. When in doubt, ask: *"would libcurl or SQLite do this, or is this
   the OpenSSL/libdbus choice?"*
2. **Tests are NOT a design input.** Verbatim: *"Tests should not be a factor in
   the API design. Tests can and should be accommodated to by other means."*
   Never justify or bend an API shape to make testing easier; fix the tests, not
   the surface.
3. **Incumbent callers are NOT constraints.** Verbatim: *"what `convenience.nim`
   or any other current caller happens to use is not a design input; if a current
   caller breaks under the principled cut, that is a finding, not a constraint."*
   (`convenience.nim` is itself a dissolution candidate in the later S4.)
4. **There are 0 users; blast radius does not matter.** Verbatim: *"There are
   currently 0 users of the library. Blast radius doesn't matter. What does matter
   is clean and comprehensive implementation."* Do not preserve backward
   compatibility for its own sake.
5. **Version-agnostic.** The human does **not** want a 1.0 freeze: fix everything
   now, comprehensively; do not tag versions or split work to protect a release.
6. **Quality is paramount; this is a showcase for the human's team.** Verbatim:
   *"comprehensively and cohesively applied without cutting any corners or leaving
   any loose ends … done in an exemplary fashion and performed to completion."*
   The human does **not** care about speed of execution or token cost.

**For S3 specifically, this lens has already been applied** to settle every design
fork (§4) — your job is to honour those settled decisions exactly, not to
re-open them.

---

## 3. The campaign — what it is, how things were, what is done

### 3.1 The project

`jmap-client` is a cross-platform JMAP (RFC 8620 core + RFC 8621 mail) **email**
client library in Nim, designed for eventual FFI use from C/C++. It is a
protocol library — no UI, no app. The campaign refactors the library's **public
API** so it ages like libcurl and SQLite. The 29 principles are in
`docs/design/14-Nim-API-Principles.md` (read it). The most load-bearing in
practice are **P15/P16 — "make illegal states unrepresentable"** (smart
constructors return `Result`; raw construction private; encode preconditions in
types), which the H1/H1b lints and an adversarial reviewer enforce.

### 3.2 How things were when the campaign started (2026-06-14)

RFC 8620 + 8621 implemented; L5/Push/Blob deferred. A P29 consumer bench
(`examples/jmap-cli/`, a CLI driving **only the public API** against live
Stalwart/James/Cyrus, sending/receiving real email) produced three artefacts:
`examples/jmap-cli/AUDIT.md` (the ledger — **92 findings**), `docs/design/16-api-
from-the-consumers-chair.md` (the narrative critique), and a gitignored recon
sheet. The 92 findings reduced to **six root causes**:

- **R1** — no one-shot for the common single-method case → **S4 (not started).**
- **R2** — **missing total readers/constructors/predicates on existing types →
  S3 (THIS sub-project).**
- **R3** — error-rail fragmentation → **S1 (DONE).**
- **R4** — the send path has no ergonomic front door → **S4 (not started).**
- **R5** — the contract snapshot didn't describe the surface → **S0 (DONE).**
- **R6** — read-model unevenness → **S2 (DONE).**

### 3.3 What is DONE and merged to `main`

| Sub-project | Clears | Status | PR / merge |
|---|---|---|---|
| **S0** Truthful contract (compiler-as-library oracle) | R5 | ✅ MERGED | PR #5 `73dee1a` |
| **S1** One error rail (`JmapError`) | R3 | ✅ MERGED | PR #6 `011830b` |
| **S2** Read-model uniformity | R6 | ✅ MERGED | PR #7 `1be1514` |
| **RFC-conformance sweep** (post-S2) | — | ✅ MERGED | PR #8 `ef8c932` |
| **S3** Complete the core | R2 | ⏳ **PLAN WRITTEN, NOT IMPLEMENTED** | branch `api/s3-complete-the-core` |
| **S4** One-shots + dissolve `convenience.nim` | R1, R4 | ⬜ NOT STARTED | — |
| **Triage ledger** (reconcile the ~79 `[open]` AUDIT lines) | all 92 | ⬜ NOT STARTED | — |

- **S0** replaced a broken text-scraper contract generator with a
  compiler-as-library oracle (`scripts/api_oracle.nim`).
- **S1** collapsed five fragmented error rails into one flat 6-arm `JmapError` sum
  (`jeValidation|jeTransport|jeRequest|jeSession|jeMisuse|jeProtocol`); L1 smart
  constructors stay on `ValidationError` and lift at the boundary via `.lift` /
  `toJmapError`. A server method error / set error is **response DATA** (on the ok
  branch via `MethodOutcome[T]` / `SetResponse`), not a rail error.
- **S2** made every immutable DATA record read by **direct public field**;
  accessors survive only on stateful **handles**. Kept both `Opt` and `FieldEcho`
  (the 3-state `FieldEcho` carries the RFC 8620 §5.3 absent-vs-null bit) and
  unified at the reader (`valueOr` etc.).
- **The RFC-conformance sweep** fixed one real bug + cleanups and recorded six
  deliberate Postel receive-side leniencies (`docs/design/known-server-
  deviations.md`).

**Root causes R3/R5/R6 cleared; R1/R2/R4 remain.**

### 3.4 THE CRITICAL METHODOLOGY LESSON — the RFC is authoritative

The most important process learning of the campaign (memory
`rfc-is-authoritative`): **the RFC text in `docs/rfcs/` is authoritative for every
protocol-correctness question; the agent-authored design docs (`docs/design/*`,
the superpowers specs, the D/A/B-numbered decisions) are fallible and have been
WRONG.** Grounding work in the RFC (not the design docs) has repeatedly caught
errors that would otherwise have shipped — including, in S3's own design phase,
**two MailboxRights roll-ups the campaign handoff itself had guessed** (see §4).
When a correctness question arises, read `docs/rfcs/`; tell every reviewer
subagent to validate against the RFC, not the design docs; delegate such
investigations to subagents to protect your context.

---

## 4. What S3 IS — scope, the settled forks, and the exclusions

**S3 = "Complete the core."** It adds the missing **pure, total readers /
predicates / smart constructors** on the now-final S2 types so a consumer reads
an `Email`, a `Mailbox`, and a `Session`, and builds a plain-text send body,
**without** `import std/tables`, a hand-walked case object, or a hand-rolled
capability preflight. **Everything S3 adds operates on an already-final value;
NOTHING dispatches** (build → dispatch → extract one-shots are S4).

### 4.1 What S3 ships (11 names; all verified to compile against the real types)

| File (layer) | Symbols | What / why |
|---|---|---|
| `mail/email.nim` (L1) | `bodyValue` · `leafTextParts` · `decodedTextBody` · `textBodies`×2 | tables-free body reading; `bodyValue` is the **rich primitive** (carries `isTruncated`/`isEncodingProblem`), `decodedTextBody → Opt[string]` is the **simple convenience** — SQLite's `column` vs `exec` split |
| `mail/mailbox.nim` (L1) | `isInbox` · `hasRole` | one blessed spelling for the 3-idiom "is this the inbox?" — the libcurl named-constant move |
| `mail/email_blueprint.nim` (L1) | `plainTextBody` | the one **new construction primitive**; closes the 4-layer plain-text send-body gap; S4's `sendPlainText` building block |
| `protocol/preflight.nim` (L3) | `requireMail` · `requireSubmission` · `requireVacation` | uniform bare-`AccountId` resolve on the `JmapError` rail |
| `types/framework.nim` (L1) | `limit` | kills the `QueryParams(limit: Opt.some(parse…get()))` triple-wrap |

No new **types** are introduced, so only `tests/wire_contract/public-api.txt`
changes (twelve lines — `textBodies` has two overloads); `type-shapes.txt`,
`module-paths.txt`, `error-messages.txt` must stay byte-identical.

### 4.2 The design forks — settled by the libcurl/SQLite lens (do NOT re-open)

These were decided by asking "what would libcurl/SQLite do?" — with the
cross-cutting bar **SQLite-minimal** (a symbol ships only if it removes a real
seal or footgun; a symbol that merely renames a field that already reads well does
NOT ship):

1. **Input helpers are core** (libcurl `setopt` / SQLite `bind` — constructing
   inputs is first-class), gated by the SQLite-minimal bar → only `limit` and
   `textBodies` qualify in S3.
2. **MailboxRights → primitives only.** SQLite ships `column` primitives, never a
   composite over orthogonal facts. The nine `may*` rights (RFC 8621 §2) are
   public plain bools (post-S2); read them directly.
3. **`decodedTextBody` → `Opt[string]`**, with truncation read via the
   `bodyValue` primitive (the SQLite exec/column layering). A bare `string` was
   rejected (it would hide the load-bearing `isTruncated` signal — the c-client
   "caveat in prose" anti-pattern); a new `DecodedText` record was rejected (it
   duplicates the primitive and invents a type the RFC doesn't define).
4. **`require*` → uniform bare `AccountId`** (SQLite-`prepare`/libcurl-`init`:
   resolve returns the identity; capabilities are read separately via the existing
   `account.mailCapability` etc. — the `getinfo` pattern). The richer
   `(AccountId, capabilities)` tuple was rejected: `requireVacation` has no account
   schema, so a tuple breaks family uniformity (the OpenSSL inconsistent-context
   smell).

### 4.3 What S3 deliberately does NOT ship (the SQLite-minimal discipline, visible)

- ❌ `canWrite` (RFC overreach — RFC 8621 §2 keeps the nine `may*` rights
  orthogonal; a drop-box with `mayAddItems` true, `maySetKeywords` false genuinely
  *can* write — the OpenSSL "convenience that lies"). **The campaign handoff §9
  had guessed this; grounding in the RFC rejected it.**
- ❌ `canAdminister` (no `mayAdminister` field exists; RFC 8621 deliberately omits
  IMAP ACL's `a` bit). **Also a handoff guess, rejected by the RFC.**
- ❌ `can*` 1:1 aliases, `roleKind`, a public part-level body ctor / send-side
  `partId` mint, filter/comparator query sugar (→ S4).

### 4.4 The `require*` refinement (important — keeps merged S1 code intact)

`require*` are **RFC-faithful soft resolution** (RFC 8620 §2, confirmed against
the authoritative text during review): prefer the designated primary account for
the capability, else any account whose `accountCapabilities` advertises it, else
`err(sfCapabilityAbsent)`. `primaryAccounts` MAY legitimately have no entry for a
supported capability — so `requireVacation` (vacationresponse usually has no
primary) must use the fallback or it spuriously fails. **The merged S1
`requirePrimaryAccount` is left strict and unchanged**; `require*` get their own
soft resolution via a module-private `usableAccount` helper. This keeps both
`SessionFault` variants meaningful and avoids an S1 behaviour regression.

### 4.5 The plan was adversarially reviewed before you got it

Four reviewer subagents **compiled the proposed S3 source against the real types**
and validated the RFC claim. Verdict: **all S3 source code is correct as written**
(purity under `{.push raises: [], noSideEffect.}`, `strictCaseObjects`,
`decodedTextBody` cyclomatic complexity ~7 ≤ 10, no `limit`/field collision, RFC
8620 §2 confirms the soft resolution). The review's must-fix findings were all in
the plan's *test import blocks* (nim-results reaches a test only via
`types/validation`'s `export results`) plus one `import std/tables` in
`preflight.nim` — **all already folded into the committed plan.** Trust the plan's
code, but still run every gate yourself (the reviewers are not infallible).

---

## 5. How to execute — subagent-driven-development

Use the `superpowers:subagent-driven-development` skill. The plan
(`docs/superpowers/plans/2026-06-16-s3-complete-the-core-plan.md`) is a STATE-
tracked, 8-task, bite-sized TDD plan; its STATE block is the source of truth for
progress (update it as each task lands).

**Per-task loop:**
1. Dispatch a **fresh subagent** with the task's exact steps (the plan gives
   complete code + complete tests + exact commands + expected output).
2. The subagent works **TDD**: write the failing test → run it, confirm it fails
   for the stated reason → implement the minimal code → run, confirm it passes →
   `just build` (keeps `src/` green) → `just fmt`.
3. **You review the subagent's full diff yourself** (two-stage: does it match the
   spec? is it quality?) and **re-run the gate yourself** before committing —
   subagents catch real things and occasionally misjudge.
4. **Commit** with explicit paths (never `git add -A`) and the kernel format (§6).
5. **Update the plan's STATE block** (mark the task ✅ with its commit SHA).

**The 8 tasks** (see the plan for the exact code of each):
1. Email body readers (`bodyValue`, `leafTextParts`, `decodedTextBody`,
   `textBodies`) + test.
2. Mailbox role predicates (`isInbox`, `hasRole`) + test.
3. `plainTextBody` send-body constructor + test (round-trips through
   `parseEmailBlueprint`).
4. `require*` preflight — **RFC-verify RFC 8620 §2 first, cite it in the commit,
   TDD the no-`primaryAccounts`-entry case** — + the private `usableAccount`
   helper + `import std/tables` + test.
5. `limit` query-window helper + test.
6. Regenerate `public-api.txt` (`just freeze-api`); confirm the other three
   snapshots are unchanged; run the full `just ci`.
7. Re-bench `examples/jmap-cli/` against the S3 symbols (replace the hand-rolled
   body-walk with `decodedTextBody`, the inbox idiom with `isInbox`, the preflight
   with `requireMail`); add an "S3 resolution" section to `AUDIT.md`; update the
   "deferred to S3" markers in `docs/design/16-…`. Keep imports public-only
   (`examples/jmap-cli/check-public-only.sh`).
8. **Both full gates** (see §6); update the STATE block; hand back to the human for
   push/PR/merge.

**Use the Workflow tool / subagents for context economy and adversarial
verification** (e.g. an independent review of the final diff before the gates),
mirroring how the plan itself was produced — but always review their output and
re-run the objective gate (the compiler/oracle) yourself.

---

## 6. Quality requirements, gates, and conventions (MANDATORY)

### 6.1 The two gates — S3 is DONE only when BOTH pass
1. **`just ci`** — reuse (SPDX), fmt-check (nph), the full lint battery (incl. the
   H1/H1b sealed-construction lints and the H16/H17 contract snapshots),
   `analyse` (nimalyzer — incl. the **`complexity` ≤ 10** and **`hasdoc`** rules,
   which fire ONLY here, not in `just build`), and the fast `test`.
2. **`just clean && just jmap-reset && just test-full`** — in that EXACT order
   (clean → reset the live Stalwart/James/Cyrus servers → the full live suite). On
   any failure, fix, then **re-run the WHOLE sequence** until "All shards passed".

**Gate lessons:** `just test` (fast) **skips the files in
`tests/testament_skip.txt`** (property/stress/`tests/protocol/`/live tests) —
those run only in `test-full`; a refactor ripple can hide there, so when anything
ripples, sweep ALL of `tests/`. nimalyzer `complexity`/`hasdoc` fire only in `just
ci`. **NEVER suppress a nimalyzer rule** — decompose to comply. (S3 is purely
additive, so ripples are unlikely, but verify.)

### 6.2 Coding conventions (CLAUDE.md + `.claude/rules/`)
- **Layers:** L1 types, L2 serde, L3 protocol → `{.push raises: [],
  noSideEffect.}` + `func`/`iterator` only (no `proc`); L4 transport/client, L5
  FFI → `{.push raises: [].}`. Every `src/` file has `{.experimental:
  "strictCaseObjects".}` right after the push pragma. **All S3 code is L1/L3 — pure
  and total.**
- **strictCaseObjects:** read a variant field only inside a `case` that *proves*
  the discriminator (an `if` is NOT enough — Rule 1). Reading
  `EmailBodyPart.partId` requires `case part.isMultipart of false:`.
- **Errors:** nim-results (`Result[T,E]`, `Opt[T]`, `?`, `valueOr`). Smart
  constructors return `Result[T, ValidationError]`; the public pipeline rail is
  `JmapResult[T] = Result[T, JmapError]`. `Opt[T]` not `std/options`; prefer `for
  v in opt:`. A `.get()` on a `Result` needs an adjacent invariant comment proving
  Ok (used once, in `plainTextBody`).
- **NEVER** loosen compiler/analyzer settings, add `converter`s / module-level
  mutable `var` / globals, or use `{.requiresInit.}` (it was empirically rejected
  earlier in the campaign). Make illegal states unrepresentable (P15/P16).
- **British-English** comments/docstrings that explain *why*, not *what*;
  **RFC-section refs only** in comments (no design-doc cross-refs). Every public
  `func` needs a docstring (nimalyzer `hasdoc`). `--styleCheck:error`.

### 6.3 Commit format (Linux-kernel style)
Subject `subsystem: short imperative` ≤ 75 cols; body wrapped ~75 cols, explains
**why**. End EVERY commit body with exactly:
```
Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
```
**No other AI/LLM attribution in any git message.** PR bodies carry **no** Claude
Code footer (the human is strict about attribution). For the Task-4 preflight
commit, **cite RFC 8620 §2** in the body.

### 6.4 Execution discipline
- **Branch first** (already on `api/s3-complete-the-core`); never implement on
  `main`. **Commit per task, each green** (`just build`). Keep the plan's STATE
  block current — it + `git log` reconstruct progress after a compaction.
- **Stage explicit paths; NEVER `git add -A`.**
- **Confirm outward-facing actions (push, PR, merge) with the human** before doing
  them.
- **REUSE/SPDX:** new files under `src/`/`tests/`/`docs/` are glob-covered by
  `REUSE.toml`; new `scripts/*.nim` would need an inline header (S3 adds none).

---

## 7. What is LEFT after S3

- **S4 — one-shots + easy-path + dissolve the `convenience.nim` quarantine (R1,
  R4).** The `curl_easy_*`/`sqlite3_exec` surface: `connect(url, user, pass)`;
  `sendPlainText(...)` (consumes S3's `plainTextBody`); `queryThenGet`; bare-get
  one-shots; the fail-fast `get` deferred from S1; a front door for the uncopyable
  `addEmailSubmissionAndEmailSet` builder. **Two decisions need the human up
  front:** the fate of `convenience.nim` (dissolve the P6 quarantine vs keep), and
  "may a convenience put a `MethodError` on a rail?". Design S4 WITH the human via
  `superpowers:brainstorming` first (HARD GATE — no code until the design is
  approved).
- **Triage ledger** — reconcile the ~79 still-`[open]` `examples/jmap-cli/AUDIT.md`
  findings → `resolved-Sn | accepted-as-trade-off | filed-as-Cn`, mapped to the
  fixing sub-project. Best done after S4. Re-bench the CLI first.
- **Deferred findings (parked):** the `NonEmptyIdSeq.toSeq` vs `std/sequtils.toSeq`
  collision; the broad **D5** `toJson` null-for-none serde-fidelity defect (RFC
  8620 §5.1 — P8 fixed only Email headers; do NOT blindly generalise the omit
  rule — it needs its own serde audit). `ParsedEmail` body-reader overloads and
  `htmlBodies()`/`allBodies()` fetch-option siblings are additive future work.

---

## 8. Key file map

- **`docs/superpowers/plans/2026-06-16-s3-complete-the-core-plan.md`** — the S3
  implementation plan you execute (8 tasks, complete code + tests, STATE block).
- **`docs/superpowers/specs/2026-06-16-s3-complete-the-core-design.md`** — the S3
  design rationale (gitignored; read from disk).
- **`docs/superpowers/plans/2026-06-15-CAMPAIGN-HANDOFF.md`** — campaign-wide
  orientation (S0–S2 + RFC sweep).
- **`docs/design/14-Nim-API-Principles.md`** — the 29 principles (the rubric).
- **`docs/design/16-api-from-the-consumers-chair.md`** — the narrative consumer
  critique (has "deferred to S3" markers Task 7 resolves).
- **`examples/jmap-cli/AUDIT.md`** — the 92-finding ledger (+ S1/S2 resolution
  sections; Task 7 adds the S3 section). `examples/jmap-cli/` — the P29 bench
  (`check-public-only.sh` enforces public-only imports).
- **`docs/rfcs/`** — the **authoritative** RFC text (8620, 8621, …). Consult for
  any protocol question (§3.4).
- **Source you touch:** `src/jmap_client/internal/mail/{email,mailbox,
  email_blueprint}.nim`, `src/jmap_client/internal/protocol/preflight.nim`,
  `src/jmap_client/internal/types/framework.nim`. Hub re-export chain (new public
  funcs auto-surface): `mail/types.nim` → `internal/mail.nim` → `src/jmap_client.nim`;
  `internal/types.nim` (for `framework`); `protocol.nim` `export preflight`.
- **`CLAUDE.md`** + `.claude/rules/{nim-conventions,nim-type-safety,
  nim-functional-core,nim-ffi-boundary}.md` — the project rules. Skills:
  `jmap-protocol`, `nim-json-serde`, `testament`, `comment-base`.
- **`/.nim-reference/`** — read-only Nim stdlib + compiler + docs.

---

## 9. Current working state (snapshot, 2026-06-16)

- On branch **`api/s3-complete-the-core`** (off `main`). Top commit: the S3 plan
  (`docs/s3: plan the Complete-the-core sub-project (R2)`). Working tree clean.
- `main` has **S0 + S1 + S2 + the RFC-conformance sweep all merged** (PRs #5–#8;
  the campaign handoff was refreshed in PR #9).
- **S3 source is NOT yet implemented** — the plan is written, reviewed, and
  committed; you implement Tasks 1–8.
- Memories present (auto-loaded): `api-libcurl-sqlite-refactor` (campaign state),
  `api-design-only-consumers` (the design lens), `rfc-is-authoritative` (the §3.4
  lesson).

**When in doubt, re-read §2.** Optimise for the future application developer,
comprehensively, no corners cut — libcurl/SQLite, not OpenSSL/libdbus.
