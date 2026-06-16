<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# EXECUTION HANDOFF — finish S3: the E1 capability-resolution reconcile, then push

> **You are a fresh agent with ZERO prior context. Read this whole document
> before doing anything.** Your immediate job is to **implement one small,
> already-designed-and-approved change** ("E1") on the in-flight `jmap-client`
> API-refactor campaign, then carry S3 to the push/PR decision. The design is
> approved and the design spec is written; you are the *executor*, then you hand
> back to the human for the outward-facing push.
>
> This document is **self-contained** — it folds in the relevant, non-stale
> content from the earlier campaign handoffs (`2026-06-15-CAMPAIGN-HANDOFF.md`,
> `2026-06-16-S3-EXECUTION-HANDOFF.md`) so you do not have to reconstruct context
> from them. They remain on disk for depth, but this is the canonical brief.
>
> **Last updated 2026-06-16.** Branch `api/s3-complete-the-core` is checked out
> with **all of S3 implemented and both gates green** (12 commits); the only work
> left on this branch is the E1 reconcile below, then push/PR.

---

## 0. TL;DR — what to do, right now

1. **Read, in full, before anything:**
   - **this document** (your task + all context);
   - `docs/superpowers/specs/2026-06-16-s3-capability-resolution-reconcile-design.md`
     — **the approved E1 design spec you implement** (gitignored; read from disk);
   - `docs/design/14-Nim-API-Principles.md` — the **29 API principles** (the rubric;
     one-line summaries are in §3 below);
   - `CLAUDE.md` + `.claude/rules/{nim-conventions,nim-type-safety,
     nim-functional-core,nim-ffi-boundary}.md` — project rules;
   - for depth (optional): `docs/superpowers/plans/2026-06-16-S3-EXECUTION-HANDOFF.md`
     and `…-s3-complete-the-core-plan.md` (how S3 was built — same lens/rhythm),
     `…-2026-06-15-CAMPAIGN-HANDOFF.md` (campaign-wide).
   - Auto-loaded memories: `api-libcurl-sqlite-refactor` (campaign state),
     `api-design-only-consumers` (the design lens), `rfc-is-authoritative`.
2. **Confirm your position:** `git branch --show-current` → `api/s3-complete-the-core`;
   `git status` → clean; `git log --oneline -13` → the top commit's subject is
   `docs/s3: add zero-context handoff for the E1 reconcile`. If not on that branch,
   `git checkout api/s3-complete-the-core`. **Never implement on `main`.**
3. **Internalise §2 (the design lens) and §7 (quality gates/conventions) — they
   override everything else on conflict.**
4. **Implement E1** via `superpowers:writing-plans` → `superpowers:subagent-driven-
   development` (the design is already approved, so go straight to writing the
   plan; do NOT re-brainstorm). See §5 + §6.
5. **Run BOTH gates yourself** (`just ci`; then `just clean && just jmap-reset &&
   just test-full`). See §7.1.
6. **Then hand back to the human for the push/PR/merge decision.** All prior
   sub-projects merged via PR only after explicit go-ahead. **Confirm before any
   push/PR/merge.**

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
failure modes of **OpenSSL, c-client, and libdbus**.

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
   Never bend an API shape — or the source — to placate a test or a tool; fix the
   test/tool instead.
3. **Incumbent callers are NOT constraints.** Verbatim: *"what `convenience.nim`
   or any other current caller happens to use is not a design input; if a current
   caller breaks under the principled cut, that is a finding, not a constraint.
   Your only consideration for API design must be future application developers."*
   (`convenience.nim` is itself a dissolution candidate in the later S4.)
4. **There are 0 users; blast radius does not matter.** Verbatim: *"There are
   currently 0 users of the library. Blast radius doesn't matter. What does matter
   is clean and comprehensive implementation."* Do not preserve backward
   compatibility for its own sake.
5. **Version-agnostic.** Verbatim: *"I want to fix all the issues, don't care about
   what version we are."* The human does **not** want a 1.0 freeze. Principles
   framed around "lock before 1.0" (P1) are reinterpreted as **"fix everything now,
   comprehensively."** `docs/design/14` is written in pre-1.0 language; that
   framing is superseded.
6. **Quality is paramount; this is a showcase for the human's team.** Verbatim:
   *"comprehensively and cohesively applied without cutting any corners or leaving
   any loose ends … done in an exemplary fashion and performed to completion."*
   The human does **not** care about speed of execution or token cost. Use
   subagents and Workflow orchestration freely; adversarially verify.

---

## 3. The 29 API principles (the rubric) + the three locked architectural decisions

### 3.1 The 29 principles — one-line summaries
Full authoritative text: **`docs/design/14-Nim-API-Principles.md`** (read it). It
distils six C libraries — great: **libcurl, SQLite, zlib**; cautionary: **OpenSSL,
c-client/UW-IMAP, libdbus**. Reviewers cite principles by number.

- **P1** Lock the contract; evolve by addition only. *(reinterpreted: version-
  agnostic — "fix everything now", §2.5.)*
- **P2** Stability bought with tests. *(but do NOT use tests as a design driver, §2.2.)*
- **P3** Overloading / default args over `_v2` suffix versioning.
- **P4** Pick a scope; defend it (JMAP only — no IMAP/POP/SMTP/contacts/calendars).
- **P5** Single public layer; internals are internal.
- **P6** Convenience APIs quarantined from the core. *(DECISION: DISSOLVE — readers
  etc. become core; the `convenience.nim` quarantine dissolves in S4.)*
- **P7** Watch the wrap rate (if everyone wraps you, the API is wrong).
- **P8** Opaque handles via private fields + ARC `=destroy`. *(Pattern-A wire-data
  types — `Request`/`Response`/`Invocation`/`ResultReference` — have private `raw*`
  fields, hub-public read accessors, hub-private smart ctors.)*
- **P9** Max two context types per concept (one handle + one builder).
- **P10** No global state; configuration is a typed value.
- **P11** No global callbacks; per-handle field + context (closure). *(e.g.
  `setDebugCallback(client, nil)` detaches, libcurl-style.)*
- **P12** Memory ownership encoded in the type (`sink`/`lent`/`var`).
- **P13** One error rail (`Result[T, E]`); name every variant. *(= S1, DONE.)*
- **P14** No thread-local error queues / last-error globals.
- **P15** Smart constructors return `Result`; raw constructors private.
- **P16** Encode preconditions in types (phantom types, builders, sum types).
- **P17** One configuration surface; one parser; one validator.
- **P18** Sum types over bit-flag soup; named enums over bools.
- **P19** Schema-driven typed records are the source of truth, not stringly
  signatures; raw `JsonNode` only for diagnostics/vendor escapes.
- **P20** Add features via additive variants, not new top-level procs.
- **P21** Granular lifecycle via distinct types per phase
  (`RequestBuilder` → `BuiltRequest` → `DispatchedResponse`).
- **P22** Sync-blocking API first; async later via a transport interface (no
  framework lock-in; do NOT import chronos/asyncdispatch in L1–L3).
- **P23** Plan Push/WebSocket as a separate type from day one.
- **P24** Decide the threading invariant explicitly; encode it (L1–L3 pure ⇒
  thread-safe; one `Client` per thread).
- **P25** License clarity (BSD-2-Clause).
- **P26** Standard build tooling (mise + just + nimble); no per-OS branching.
- **P27** Documentation as succession planning.
- **P28** Long-form first-party narrative documentation.
- **P29** Bench API ergonomics with a real consumer (= the `examples/jmap-cli/` bench).

**P15/P16 are the project's #1 DDD principle in practice — "make illegal states
unrepresentable."** Mechanically enforced by the H1/H1b lints and by adversarial
review; both have caught real regressions this campaign.

### 3.2 The three locked architectural decisions
The human chose the **maximal-toward-the-libcurl/SQLite-ideal** option on each:
1. **One error rail.** Collapse the 5 call-path rails into one `JmapError` sum (=
   S1, DONE).
2. **One ergonomic core, no quarantine.** SQLite has no convenience module;
   readers/constructors/predicates/one-shots AND one blessed easy-path per
   operation become first-class on the always-on hub. The P6 quarantine
   **dissolves** (S3 = the primitives, DONE; S4 = the one-shots/easy-path,
   `convenience.nim` fate decided with the human).
3. **One read idiom.** Uniform access across all entity *data records*; one
   optionality model per field — **reframed during S2** (a finding, not a
   constraint): keep BOTH `Opt` and `FieldEcho` (collapsing them destroys the RFC
   8620 §5.3 absent-vs-null bit) and unify at the **reader** layer (= S2, DONE).

---

## 4. The campaign — what it is, how things were, what is done

### 4.1 The project
`jmap-client` is a cross-platform JMAP (RFC 8620 core + RFC 8621 mail) **email**
client library in Nim, designed for eventual FFI use from C/C++. It is a protocol
library — no UI, no app. One dependency: a vendored, patched `nim-results` at
`vendor/nim-results`; everything else is Nim stdlib. The campaign refactors the
**public API** so it ages like libcurl and SQLite.

### 4.2 How things were when the campaign started (2026-06-14)
RFC 8620 + 8621 implemented; L5/Push/Blob deferred. Commit `39e4891` delivered
earlier API enhancements; `96cea22` added the first `examples/jmap-cli/` bench.
**The bench is the P29 consumer:** a CLI driving **only the public API**
(`import jmap_client` [+ `jmap_client/convenience`]) to exercise every RFC
8620/8621 entity area against live Stalwart/James/Cyrus, sending/receiving real
email. **Its purpose is the audit, not the CLI**; `check-public-only.sh` enforces
public-only imports. It produced: **`examples/jmap-cli/AUDIT.md`** (the ledger —
**92 findings**, now with S1/S2/S3 resolution sections); **`docs/design/16-api-
from-the-consumers-chair.md`** (narrative critique); and a gitignored recon sheet.

### 4.3 The 92 findings → SIX root causes (the key synthesis)
- **R1 — No one-shot for the common single-method case** (bare-get repetition;
  single-email update triple-seal; single-recipient send). → **S4.**
- **R2 — Missing total readers/constructors/predicates on existing types.** →
  **S3 (DONE this session).**
- **R3 — Error-rail fragmentation** (five call-path rails that don't compose). →
  **S1 (DONE, merged).**
- **R4 — The send path has no ergonomic front door** (4-layer blueprint
  hand-build; the misleading `addEmailSubmissionAndEmailSet`; the uncopyable-
  `RequestBuilder`-in-Ok-arm friction). → **S4.**
- **R5 — The contract snapshot didn't describe the surface** (the generator was a
  broken text scraper). → **S0 (DONE, merged).**
- **R6 — Read-model unevenness** (three idioms for the same job). → **S2 (DONE,
  merged).**

**Cleared: R2 (S3), R3 (S1), R5 (S0), R6 (S2). Remain: R1, R4 (both S4).**

### 4.4 Sub-project status
| Sub-project | Clears | Status |
|---|---|---|
| **S0** Truthful contract (compiler-as-library oracle) | R5 | ✅ MERGED to `main` (PR #5, `73dee1a`) |
| **S1** One error rail (`JmapError`) | R3 | ✅ MERGED to `main` (PR #6, `011830b`) |
| **S2** Read-model uniformity | R6 | ✅ MERGED to `main` (PR #7, `1be1514`) |
| **RFC-conformance sweep** (post-S2) | — | ✅ MERGED to `main` (PR #8, `ef8c932`) |
| **S3** Complete the core | R2 | ✅ **IMPLEMENTED, both gates green, on branch `api/s3-complete-the-core` — NOT merged** |
| **E1** capability-resolution reconcile | — | ⏳ **DESIGNED + APPROVED, spec on disk, NOT implemented — THIS IS YOUR TASK** |
| **S4** One-shots + dissolve `convenience.nim` | R1, R4 | ⬜ NOT STARTED |
| **Triage ledger** (~79 still-`[open]` AUDIT lines) | all 92 | ⬜ NOT STARTED |

### 4.5 What the DONE sub-projects delivered (with the load-bearing detail + lessons)
- **S0 (PR #5).** Replaced the broken `api_surface.nim` text scraper with a
  **compiler-as-library oracle**: `scripts/api_probe.nim` (union re-export of both
  public hubs) + `scripts/api_oracle.nim` (loads the module graph, runs `sem`,
  walks `modulegraphs.allSyms` = exactly what `import jmap_client` exposes; modes
  `api`/`type-shapes` via `API_ORACLE_MODE`). Rewired the `justfile` freeze recipes
  + the H16/H17 lints to diff the committed snapshot against the live oracle.
  **Caveat: a Nim upgrade must re-verify the oracle** (it depends on
  compiler-internal `allSyms`/`ifaces`/`sfExported`). **E1 regenerates snapshots
  through this oracle (`just freeze-api`/`freeze-type-shapes`).**
- **S1 (PR #6) — the error model E1 touches.** Collapsed five fragmented rails
  (`ValidationError`, `seq[ValidationError]`, `EmailBlueprintErrors`,
  `ClientError`, `GetError`) into one **flat 6-arm `JmapError` sum**
  `{jeValidation | jeTransport | jeRequest | jeSession | jeMisuse | jeProtocol}`
  in L3 (`protocol/jmap_error.nim`). Pure L1 smart constructors stay
  `Result[T, ValidationError]` and **lift at the L3/L4 boundary** via `.lift` +
  `toJmapError` (no `converter`s). `get`/`getBoth`/`getAll` return
  `Result[MethodOutcome[T], JmapError]` — **a server method error is response DATA
  on the ok branch** (`mokValue | mokMethodError`), per RFC 8620 §3.6.2, NOT a rail
  fault. `MethodError`/`SetError` stay response data. `jeSession` carries a
  `SessionFault(kind, capability)` — the variant E1 trims (see §5). The fail-fast
  `get` convenience + the `connect`/`sendPlainText` one-shots were deferred to S4.
- **S2 (PR #7).** Made how a consumer **reads** a returned value uniform: **two
  buckets** — every immutable DATA record reads by **direct public field**;
  accessors survive only on stateful **handles** (`JmapClient`, `RequestBuilder`,
  `BuiltRequest`, `Transport`). Delivered the **`FieldEcho` reader**
  (`valueOr`/`isValue`/`isNull`/`isAbsent`/`items`/`toOpt`; both `Opt` and the
  3-state `FieldEcho` kept), direct fields on Thread/Account/Session/capability
  schemas/`Comparator`/`AddedItem`, Tier-A sealed newtypes (`NonEmptyIdSeq`,
  `DisplayName`, `ApiUrl`), public typed capability arms (raw `JsonNode` vendor arms
  sealed — H1b), `Email` non-default headers → `Opt`, `MailboxChanges` flattened,
  six `SetResponse` projection iterators. **Lesson: Tier-B (`{.requiresInit.}` brand)
  was REJECTED** — under the real `--warningAsError:UnsafeDefault/UnsafeSetLen` a
  `requiresInit` value is a hard ERROR in `seq.add`/`getOrDefault`/`newSeq`.
  **Always verify empirical claims under the project's REAL flags.**
- **RFC-conformance sweep (PR #8).** Whole-codebase audit; **high conformance**.
  **F1** (the one real bug): `parseHeaderValue` rejected JSON `null` for the four
  single-instance header forms (RFC 8621 §4.1.3 returns `null` for a
  requested-but-absent single-instance header) — all `HeaderValue` arms now `Opt`
  (TDD-found). **F2** removed the non-IANA `subscriptions` mailbox role. **F3**
  renamed the fixture-only full-object `Email`/`Mailbox.toJson` → `toJsonForFixture`.
  **F4** dropped the redundant VacationResponse `vrgkId` selector. **F5** wrote
  `docs/design/known-server-deviations.md` (six deliberate Postel receive-side
  leniencies, kept + documented — liberal on receive, strict on send).

### 4.6 What S3 shipped (this session, on the branch)
S3 = "Complete the core": eleven **pure, total, additive** readers / predicates /
constructors on the now-final S2 types so a consumer reads an `Email`, a
`Mailbox`, and a `Session`, and builds a plain-text send body, **without**
`import std/tables`, a hand-walked case object, or a hand-rolled capability
preflight. **No new types**; the contract grew by **+12 lines in `public-api.txt`
only** (the other three snapshots byte-identical).

| File (layer) | Symbols |
|---|---|
| `mail/email.nim` (L1) | `bodyValue` (rich primitive — carries `isTruncated`/`isEncodingProblem`), `leafTextParts` (iterator), `decodedTextBody` (`Opt[string]`, case-insensitive `text/plain` per RFC 2045 §5.1), `textBodies`×2 |
| `mail/mailbox.nim` (L1) | `isInbox`, `hasRole` |
| `mail/email_blueprint.nim` (L1) | `plainTextBody` |
| `protocol/preflight.nim` (L3) | `requireMail` / `requireSubmission` / `requireVacation` (RFC 8620 §2 soft resolution) |
| `types/framework.nim` (L1) | `limit` |

S3 commit range on the branch (oldest→newest): `4637449` (body readers) → `7bd864b`
(role predicates) → `ab9e749` (plainTextBody) → `5ac7385` (require*) → `81f1195`
(limit) → `0b63bb6` (freeze public-api) → `8fe11e0` (CLI re-bench + AUDIT + docs/16)
→ `9481f88` (hardening: preflight accountCapabilities-authoritative + deterministic
fallback) → `af2b664` (hardening: decodedTextBody case-insensitive test +
textBodies(0) doc) → `f03193b` (mark S3 complete), then this handoff commit on top.
**Both gates were green at `f03193b`.**

**Deliberate S3 exclusions (do NOT treat as gaps):** ❌ `canWrite`/`canAdminister`/
`can*` rights roll-ups (RFC 8621 §2 keeps the nine `may*` rights orthogonal; a
conjunction would misreport — the campaign handoff itself had *guessed* these, and
the RFC rejected them); ❌ `roleKind`; ❌ a public part-level body ctor or
send-side `partId` mint; ❌ `htmlBodies()`/`allBodies()`; ❌ `ParsedEmail`
body-reader overloads; ❌ filter/comparator query sugar (→ S4).

A final **5-lens adversarial Workflow** (RFC / 29-principles / purity / libcurl-
SQLite lens / completeness) verified the whole diff: purity came back clean; it
drove the two hardening commits. It also surfaced **design-shape findings** the
human chose to triage rather than silently change — finding **#1 is E1 (your
task)**; findings **#2/#3 are deferred to S4/triage** (see §8).

### 4.7 THE CRITICAL METHODOLOGY LESSON — the RFC is authoritative
Memory `rfc-is-authoritative` (the human's standing correction): *"D5, spec §8 etc
are not authoritative. These are specs made by agents which made many mistakes.
Consult the authoritative figure, the RFC docs."* **The RFC text in `docs/rfcs/`
governs every protocol-correctness question; the agent-authored design docs
(`docs/design/*`, the superpowers specs, the D/A/B-numbered decisions, even these
handoffs) are fallible and have been WRONG.** Grounding work in the RFC has caught
real errors that would otherwise have shipped:
- **D5** — every `toJson` emits `null` for `Opt.none`; RFC 8620 §5.1 says a `/get`
  returns only requested properties (absent, never null). P8/the sweep fixed only
  Email headers; **the broad serde-fidelity defect is DEFERRED** — do NOT blindly
  generalise the omit rule, it needs its own serde audit.
- **B12** — `parseAccount` dropped a read-only account's capabilities (RFC 8620 §2
  violation) — **removed in S2.**
- **H1b** — S2's capability-arm exposure made raw `JsonNode` vendor arms public
  (reopening raw construction past the fallible ctor — P15/P16) — **resealed.**
- **F1, F2** (RFC sweep) — the header-`null` bug and the non-IANA role.
- In S3: the `usableAccount` Postel gap (a `primaryAccounts` pointer trusted
  without checking `accountCapabilities`) — **fixed in hardening** `9481f88`.
**Tell every reviewer subagent to validate against the RFC, not the design docs;
delegate such investigations to subagents to protect context.**

---

## 5. YOUR TASK — E1: reconcile the capability→account resolution surface

**The full approved design is in
`docs/superpowers/specs/2026-06-16-s3-capability-resolution-reconcile-design.md`
(gitignored — read it from disk). This section is the summary; the spec is
authoritative for the change.**

### 5.1 Why
S3 shipped three **named-soft** resolvers (`requireMail`/`requireSubmission`/
`requireVacation`) beside the pre-existing (S1-merged) **general-strict**
`requirePrimaryAccount(session, kind)`. The adversarial review found the surface
incoherent: (a) `requireMail(s)` and `requirePrimaryAccount(s, ckMail)` silently
**disagree** on the no-primary case; (b) `requirePrimaryAccount` now has **zero
production callers** (the CLI moved to `requireMail`; only a compile-surface test +
snapshots reference it); (c) its error variant `sfPrimaryAccountAbsent` is produced
**only** by it (the soft `usableAccount` produces only `sfCapabilityAbsent`). The
human chose **option E1 (subtractive)**: fix the incoherence by *removing the
divergent orphan*, not by adding entry points — the most SQLite-minimal outcome,
no dead surface.

### 5.2 The change (E1)
- **Delete `func requirePrimaryAccount*`** from
  `src/jmap_client/internal/protocol/preflight.nim`. The "designated primary
  specifically" need is already served by the existing public
  `session.primaryAccount(kind): Opt[AccountId]`.
- **Remove the now-dead `sfPrimaryAccountAbsent`** from `SessionFaultKind` in
  `src/jmap_client/internal/protocol/jmap_error.nim`, and drop its arm from the
  `message()` projection. `SessionFaultKind` reduces to the single variant
  `sfCapabilityAbsent` (still meaningful; a one-variant enum is valid/extensible).
- **Keep unchanged:** `requireMail`/`requireSubmission`/`requireVacation`, the
  module-private `usableAccount`/`lowestAdvertising` core (with the S3 hardening
  intact), and every `session.*`/`account.*` capability accessor.
- **Net surface change: −1 public func, −1 error variant. No additions.**

### 5.3 Ripple to handle (the spec §4 lists this precisely)
- Regenerate and confirm **only the expected lines move**: `public-api.txt`
  (`just freeze-api`, loses `requirePrimaryAccount`); `error-messages.txt`
  (`just freeze-error-messages`, loses the `sfPrimaryAccountAbsent` line);
  `type-shapes.txt` (`just freeze-type-shapes`) **iff** the oracle snapshots enum
  members — confirm whether it moves.
- `tests/compile/tcompile_a12_error_constructor_surface.nim` — drop its
  `requirePrimaryAccount`/`sfPrimaryAccountAbsent` surface assertions.
- `scripts/freeze_error_messages.nim` — drop the `sfPrimaryAccountAbsent` sample
  if it enumerates one (then `scripts/**` is NOT REUSE-glob-covered, but you're not
  adding a file, so no header needed).
- **Grep all of `src/` and `tests/` for `requirePrimaryAccount` and
  `sfPrimaryAccountAbsent`; adjust/remove every reference. Sweep for any `case`
  over `SessionFaultKind` the variant removal makes non-exhaustive** (the
  `message()` projection is the known one; the compiler will surface others, since
  catch-all `else` on finite enums is forbidden).
- The existing `require*` unit tests (`tests/unit/tpreflight.nim`) stay green
  unchanged (they never used `requirePrimaryAccount`).
- `examples/jmap-cli/AUDIT.md` — move the `session:capability` finding from
  "partially resolved" to fully resolved.

### 5.4 Out of scope (do NOT do these as part of E1)
The other two surfaced findings are **S4/triage**, not E1:
- **#2** — a read-side `EmailLeaf` view type for `leafTextParts` (P16: `partId`/
  `blobId` sit behind a `case`). Needs a new type → violates S3's "no new types";
  a future additive pass.
- **#3** — `leafTextParts`/`limit` naming; the still-public raw `Blueprint*` part
  constructors (a P15 tightening / non-additive removal).

---

## 6. How to execute E1

You are at the brainstorming skill's terminal step — **the design is approved and
the spec is written/reviewed** — so the next skill is `superpowers:writing-plans`,
then `superpowers:subagent-driven-development`. **Do NOT re-brainstorm; do NOT
re-open the E1 design** (the human approved it).

1. **Write the plan** (`superpowers:writing-plans`) to
   `docs/superpowers/plans/2026-06-16-s3-capability-resolution-reconcile-plan.md` —
   bite-sized tasks with complete code/commands, a STATE block, the conventions
   header, and the kernel-commit + 3-trailers reminder. Because E1 is a *removal*,
   "TDD" here means: delete the symbol/variant, let the compiler + lints point at
   every reference (a failing build = your "red"), fix each reference, regenerate
   snapshots, then green. The `require*` behaviour tests in `tests/unit/tpreflight.nim`
   are the regression guard that the soft resolvers still work.
2. **Implement** (`superpowers:subagent-driven-development`): a **fresh subagent**
   per task; the subagent does the work but **does NOT commit** (you own commits);
   then dispatch **two reviewers** (spec-compliance + code-quality, in parallel,
   read-only); **you re-run the gate yourself** and **author the kernel commit**
   with explicit paths and the three trailers; **you flip the plan's STATE block**
   in the same commit. (This is exactly how all of S3 was built.)
3. **Both gates** (§7.1), then update the STATE block, then **hand back to the
   human for push/PR**.

Use subagents / the Workflow tool freely for context economy and adversarial
verification (the human wants exemplary quality, token cost no object) — but
**always re-run the objective gate (compiler/oracle/`just ci`) yourself**; the
reviewers are not infallible. A good final move (mirroring S3) is an independent
adversarial review of the whole diff before the gates.

---

## 7. Quality requirements, gates, and conventions (MANDATORY)

### 7.1 The two gates — E1 (and S3) are DONE only when BOTH pass
1. **`just ci`** — reuse (SPDX), fmt-check (nph), the full lint battery
   (`lint-public-api` = H16, `lint-type-shapes` = H17, `lint-error-messages` = H15,
   `lint-sealed-distinct` = H1, `lint-fallible-ctor-public-arm` = H1b, plus the
   internal-boundary / module-path / style / typed-builder lints), `analyse`
   (nimalyzer — incl. **`complexity` ≤ 10** and **`hasdoc`**, which fire ONLY here,
   not in `just build`), and the fast `test`.
2. **`just clean && just jmap-reset && just test-full`** — in that EXACT order
   (clean → recreate the live Stalwart/James/Cyrus servers → the full live sharded
   suite). On any failure, fix, then **re-run the WHOLE sequence** until "All shards
   passed". It is long-running (server rebuild + full suite, often 10–25 min); run
   it in the **background** and await completion. (CLAUDE.md says agents normally
   leave `test-full` to the user — but the human has directed agents to run it.)

**Gate lessons (learned the hard way):**
- `just test` (fast) **skips the files in `tests/testament_skip.txt`** (the
  property/stress tests, `tests/protocol/*`, the live tests) — those run only in
  `test-full`. A skip-listed file can hide a break that ONLY `test-full` surfaces;
  when a refactor ripples into tests, **sweep ALL of `tests/`.**
- nimalyzer's `complexity` (≤10) and `hasdoc` run only in `just ci`, NOT in
  `just build`. New per-form branches or **undocumented test helpers** fail there
  (a missing `##` on a test-helper `proc` bit S3 — `hasdoc` applies to `tests/`
  too). **Restructure / add docstrings to comply; NEVER suppress a nimalyzer rule.**
- The per-type **`{.ruleOff: "objects".}`** exemption for a public-field DATA record
  is the **SANCTIONED** mechanism (176-use precedent; `objects` = `check objects
  publicfields`), distinct from suppressing a rule like `complexity`. (E1 adds no
  data records, so you should not need it.)
- `just fmt`/`fmt-check` and `just analyse` cover `src/` + `tests/` only, NOT
  `examples/` — the example CLI is verified by building it (`nim c
  examples/jmap-cli/jmap_cli.nim`) + `bash examples/jmap-cli/check-public-only.sh`.

### 7.2 Coding conventions (CLAUDE.md + `.claude/rules/`)
- **Layers:** L1 types, L2 serde, L3 protocol → `{.push raises: [],
  noSideEffect.}` + `func`/`iterator` only (no `proc`); L4 transport/client, L5
  FFI → `{.push raises: [].}`. Every `src/` file has `{.experimental:
  "strictCaseObjects".}` right after the push pragma. (Tests are exempt from the
  pragma but NOT from `hasdoc`.) **E1 touches L3 (`preflight.nim`,
  `jmap_error.nim`) — pure and total.**
- **strictCaseObjects:** read a variant field only inside a `case` that *proves*
  the discriminator (an `if` is NOT enough — Rule 1). No nested case-in-case;
  prefer a public discriminator; combined-arm reads per `.claude/rules/nim-type-
  safety.md`.
- **Errors:** nim-results (`Result[T,E]`, `Opt[T]`, `?`, `valueOr`). Smart
  constructors return `Result[T, ValidationError]`; the public pipeline rail is
  `JmapResult[T] = Result[T, JmapError]`. `Opt[T]` not `std/options`; prefer `for v
  in opt:`. A `.get()` on a `Result` needs an adjacent invariant comment proving Ok.
- **Style:** `let`/`const` default, `var` only locally; expression-oriented
  (`if`/`case`/`block` as expressions, exhaustive, **no catch-all `else` on finite
  enums** — new variants must force compile errors at every site). `--styleCheck:error`.
- **NEVER** loosen compiler/analyzer settings, suppress a nimalyzer rule (decompose
  instead), add module-level mutable `var`/globals/global callbacks, add
  `converter`s, or use `{.requiresInit.}` (Tier-B — empirically rejected). Make
  illegal states unrepresentable (P15/P16).
- **British-English** comments/docstrings that explain *why*, not *what*;
  **RFC-section refs only** in comments (no design-doc/campaign cross-refs — no
  "S1"/"Pattern 8"/"D5"; no forward-refs to unshipped symbols). Every public
  `func`/`iterator` **and every test-helper `proc`** needs a `##` docstring. (The
  `comment-base` skill governs this.)

### 7.3 Commit format (Linux-kernel style)
Subject `subsystem: short imperative` ≤ 75 cols; body wrapped ~75 cols, explains
**why**. End EVERY commit body with exactly:
```
Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
```
**No other AI/LLM attribution in any git message.** A PR *body* is GitHub metadata,
not a git message — but the human is strict about attribution; the campaign PRs
carry **no** Claude Code footer in the PR body.

### 7.4 Execution discipline
- **Branch first** (already on `api/s3-complete-the-core`); never implement on
  `main`. **Commit per task, each green** (`just build`), with the STATE block
  flipped in the same commit — `git log` + the STATE block reconstruct progress
  after a compaction.
- **Stage explicit paths; NEVER `git add -A`.**
- **Confirm outward-facing actions (push, PR, merge) with the human** before doing
  them.
- **REUSE / SPDX (a `just ci` gate):** `REUSE.toml` covers `src/**`, `tests/**`,
  `docs/**` and common extensions; **`scripts/**` is NOT glob-covered** (new `.nim`
  there needs an inline two-line BSD-2-Clause + copyright header — E1 adds none).
  Docs use a CC-BY-4.0 SPDX id inside an HTML comment. The REUSE linter scans for
  the SPDX-identifier string *anywhere*; a backtick-wrapped SPDX example in markdown
  prose trips it — wrap such prose in `<!-- REUSE-IgnoreStart -->` /
  `<!-- REUSE-IgnoreEnd -->`.

---

## 8. What is LEFT after E1

1. **Push S3 (incl. E1) — the human's call.** Confirm with the human, then push
   `api/s3-complete-the-core` and open a PR to `main` (PR body: no Claude footer;
   summarise the eleven S3 symbols + the E1 reconcile). Do NOT merge without the
   human's go-ahead. Prior sub-projects merged via PR only after explicit OK.
2. **S4 — one-shots + easy-path + dissolve the `convenience.nim` quarantine (R1,
   R4).** The `curl_easy_*`/`sqlite3_exec` surface, first-class on the always-on
   hub: `connect(url, user, pass)`; `sendPlainText(...)` (consumes S3's
   `plainTextBody`; hides the blueprint chain + the two-creation wiring);
   `queryThenGet`; bare-get single-method one-shots; the **fail-fast `get`
   convenience deferred from S1** (open question: may a convenience put a
   `MethodError` on a rail?); a front door for the **uncopyable-`RequestBuilder`**
   friction (`addEmailSubmissionAndEmailSet` returns an uncopyable builder in its
   Ok arm, so it can't ride `?`/`.lift` today). **Two decisions need the human up
   front:** the fate of `convenience.nim` (dissolve the P6 quarantine vs keep), and
   the fail-fast-`get` design. **Brainstorm S4 WITH the human first**
   (`superpowers:brainstorming` HARD GATE — no code until the design is approved).
3. **Triage ledger** — reconcile the ~79 still-`[open]` `examples/jmap-cli/AUDIT.md`
   findings → `resolved-Sn | accepted-as-trade-off | filed-as-Cn`, mapped to the
   fixing sub-project. ~13 are already FIXED by S1/S2 (and now more by S3) but not
   reconciled per-line. Best done after S4. Re-bench the CLI first.
4. **Deferred findings (parked — candidates for S4/triage or a future additive
   pass):** finding **#2** (`EmailLeaf` read-side view type for `leafTextParts`,
   P16) and **#3** (`leafTextParts`/`limit` naming; raw `Blueprint*` constructors
   still public — P15 tightening); the **`NonEmptyIdSeq.toSeq` vs
   `std/sequtils.toSeq` collision** (a `.asSeq` rename would fix it, matching the
   sibling `NonEmptySeq[T].asSeq`); the broad **D5** `toJson` null-for-none
   serde-fidelity defect (RFC 8620 §5.1 — P8 fixed only Email headers; needs its own
   serde audit, do NOT blindly generalise the omit rule); `ParsedEmail` body-reader
   overloads; `htmlBodies()`/`allBodies()` fetch-option siblings.
5. **Re-bench after each sub-project.** The `examples/jmap-cli/` consumer is the P29
   instrument; after S4, re-exercise it and update `AUDIT.md` / `docs/design/16-…`
   (public-only — `check-public-only.sh`).

---

## 9. Key file map

### 9.1 The handoffs / specs / plans
- **`docs/superpowers/specs/2026-06-16-s3-capability-resolution-reconcile-design.md`**
  — the approved E1 design (gitignored; read from disk). **Authoritative for E1.**
- `docs/superpowers/plans/2026-06-16-S3-EXECUTION-HANDOFF.md` — the S3 execution
  handoff (richest single context source for how S3 was built; same conventions/lens).
- `docs/superpowers/plans/2026-06-16-s3-complete-the-core-plan.md` — the S3 plan
  (STATE all ✅; shows what S3 shipped + how each task was built).
- `docs/superpowers/specs/2026-06-16-s3-complete-the-core-design.md` — the S3 design
  rationale (gitignored).
- `docs/superpowers/plans/2026-06-15-CAMPAIGN-HANDOFF.md` — campaign-wide orientation
  (S0–S2 + sweep). **Its §0/§6/§12/§13 are STALE** (say "S3 not started / on main");
  trust *this* document + §4.4 above for current status.
- The earlier sub-project plans (each with a STATE block):
  `…-s0-truthful-contract-plan.md`, `…-s1-one-error-rail-plan.md`,
  `…-s2-read-model-uniformity-plan.md`, `…-rfc-conformance-sweep.md`.
- `docs/superpowers/plans/2026-06-14-jmap-cli-api-bench.md` — the original bench/audit.

### 9.2 The rubric, the RFC, the bench
- `docs/design/14-Nim-API-Principles.md` — **the 29 principles (the rubric).**
- `docs/design/16-api-from-the-consumers-chair.md` — narrative consumer critique
  (S2- and S3-updated).
- `docs/design/known-server-deviations.md` — the RFC-deviation register (sweep F5).
- **`docs/rfcs/`** — the **authoritative** RFC text (8620, 8621, 8887, 2045,
  5321/5322/3461/8909). Consult for any protocol-correctness question (§4.7).
- `examples/jmap-cli/AUDIT.md` — the 92-finding ledger (+ S1/S2/S3 resolution
  sections). `examples/jmap-cli/` — the P29 bench; `check-public-only.sh` enforces
  public-only imports.

### 9.3 The source tree (the whole layout, for orientation)
- `src/jmap_client.nim` — the public re-export hub (L5 C-ABI exports land here).
- `src/jmap_client/convenience.nim` — opt-in pipeline combinators (P6 dissolution
  candidate, S4 — the only public module path besides root).
- `src/jmap_client/internal/`:
  - `types/` (L1): `primitives`, `identifiers`, `validation`, `field_echo`,
    `framework`, `capabilities`, `account_capability_schemas`, `session`,
    `envelope`, `errors`, `collation`, `methods_enum` — re-exported via
    `internal/types.nim`.
  - `serialisation/` (L2): serde leaves (no public hub; in-tree callers import leaves).
  - `protocol.nim` + `protocol/` (L3): `builder`, `dispatch`, `methods`, `entity`,
    **`jmap_error`** (the 6-arm `JmapError` + `SessionFaultKind` — **E1 edits this**),
    **`preflight`** (the require* family — **E1 edits this**).
  - `transport.nim` + `transport/` (L4); `client.nim` (L4, `JmapClient`).
  - `mail/` (RFC 8621 entities — `email`, `mailbox`, `email_blueprint`, `body`,
    `headers`, …; re-exported via `mail/types.nim` → `internal/mail.nim`).
  - `push.nim` / `websocket.nim` — deferred type stubs (RFC 8620 §7 / RFC 8887).
- **E1 source you touch:** `src/jmap_client/internal/protocol/preflight.nim` and
  `…/protocol/jmap_error.nim`. Tests/scripts: `tests/compile/
  tcompile_a12_error_constructor_surface.nim`, `scripts/freeze_error_messages.nim`,
  and whatever grep/the compiler surfaces. Snapshots: `tests/wire_contract/
  {public-api,error-messages,type-shapes}.txt`.

### 9.4 Tooling / config
- `scripts/api_oracle.nim` + `api_probe.nim` — the S0 contract oracle (`just
  freeze-api`/`freeze-type-shapes` drive it); `scripts/freeze_error_messages.nim` —
  the H15 error-message snapshot generator.
- `tests/wire_contract/{public-api,type-shapes,error-messages,module-paths}.txt` —
  the frozen contract. `tests/lint/{h1*,h15,h16,h17,…}` — the lock lints.
  `tests/testament_skip.txt` — the fast-suite skip list (these run only in `test-full`).
- `config.nims` / `jmap_client.nimble` — compiler flags (`--mm:arc`, `strictDefs`,
  `strictEffects`, `threads:on`, `panics:on`, the `warningAsError` battery incl.
  `UnusedImport`/`UnsafeDefault`/`ObservableStores`). `config.nims` puts `src/` +
  `vendor/nim-results` on the path, so `nim c -r tests/path/file.nim` runs a single
  test file standalone (UnusedImport is a hard error there — no unused imports).
- `CLAUDE.md` + `.claude/rules/{nim-conventions,nim-type-safety,nim-functional-core,
  nim-ffi-boundary}.md` — the project rules. Skills: `jmap-protocol`,
  `nim-json-serde`, `testament`, `comment-base`.
- `/.nim-reference/` — read-only Nim stdlib + compiler + docs.

---

## 10. Current working state (snapshot, 2026-06-16)

- On branch **`api/s3-complete-the-core`** (off `main`). Working tree **clean**.
  Top commit subject: `docs/s3: add zero-context handoff for the E1 reconcile`. The
  branch has **all 12 commits** (11 for S3 + this handoff); **both gates were green
  at `f03193b`** (the S3-complete marker).
- `main` has **S0 + S1 + S2 + the RFC-conformance sweep merged** (PRs #5–#8; the
  campaign handoff was refreshed in PR #9).
- **E1 is designed + approved; the spec is on disk (gitignored); NOT implemented.**
  That is your task. After E1, both gates again, then hand back to the human for
  the push/PR decision.
- Memories present (auto-loaded): `api-libcurl-sqlite-refactor` (campaign state —
  updated this session: S3 done, E1 in flight), `api-design-only-consumers` (the
  design lens), `rfc-is-authoritative` (the §4.7 lesson), plus the older
  `api-refactor-section-ab-campaign` (partly superseded).

**When in doubt, re-read §2.** Optimise for the future application developer,
comprehensively, no corners cut — libcurl/SQLite, not OpenSSL/libdbus.
