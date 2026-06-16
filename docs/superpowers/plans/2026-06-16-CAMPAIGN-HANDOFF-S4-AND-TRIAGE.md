<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# CAMPAIGN HANDOFF — jmap-client API → libcurl/SQLite refactor (post-S3/E1)

> **You are a fresh agent with ZERO prior context. Read this whole document
> before doing anything.** It is the single canonical orientation for the
> campaign as of 2026-06-16, after **S0 + S1 + S2 + the RFC-conformance sweep +
> S3 + E1 are ALL merged to `main`**. It folds in the still-relevant content of
> the earlier handoffs and supersedes them for *current status*.
>
> It tells you: what the human is trying to achieve, what this campaign is, how
> things were at the start, exactly what is done, exactly what is left, every
> quality gate, every convention, the non-negotiable design lens, all 29
> principles, the process discipline that has carried six sub-projects, and the
> immediate next action.
>
> **Your immediate next job is S4** (the ergonomic one-shots + dissolving the
> `convenience.nim` quarantine), and **S4 starts with a design conversation WITH
> the human — a HARD GATE: no code until the design is approved.** Then the
> triage ledger. See §8 and §13.
>
> Companion auto-loaded memories (in
> `~/.claude/projects/-workspaces-jmap-client/memory/`):
> `api-libcurl-sqlite-refactor` (campaign state), `api-design-only-consumers`
> (the design lens), `rfc-is-authoritative` (the methodology lesson — read it).
> Per-sub-project plans live in `docs/superpowers/plans/`; gitignored design
> specs in `docs/superpowers/specs/`.

---

## 0. TL;DR — where we are right now (2026-06-16)

- **Project:** `jmap-client` — a cross-platform JMAP (RFC 8620 core + RFC 8621
  mail) **email** client library in Nim, designed for eventual FFI use from
  C/C++. It is a protocol library — no UI, no app. RFC 8620 + 8621 are
  implemented; **Layer-5 C FFI, Push (RFC 8620 §7), and Blob upload/download are
  deferred** campaign-wide.
- **Mission:** refactor the library's **public API** so it ages like **libcurl
  and SQLite**, not like **OpenSSL or libdbus**, driven entirely by the needs of
  the **future application developer** who will link this library into an email
  client. (Mission verbatim in §1; the non-negotiable design lens in §2.)
- **Status — SIX sub-projects DONE & merged to `main`; TWO remain:**
  - **S0 (truthful contract)** — ✅ merged (PR #5, `73dee1a`). Clears R5.
  - **S1 (one error rail, `JmapError`)** — ✅ merged (PR #6, `011830b`). Clears R3.
  - **S2 (read-model uniformity)** — ✅ merged (PR #7, `1be1514`). Clears R6.
  - **RFC-conformance sweep** (post-S2) — ✅ merged (PR #8, `ef8c932`).
  - **S3 (complete the core) + E1 (capability-resolution reconcile)** — ✅ merged
    (PR #10, merge `266fd80`, 2026-06-16). Clears R2.
  - **S4 (one-shots + easy-path + dissolve quarantine)** — ⬜ **NOT STARTED.**
    Clears R1 + R4. **THIS IS YOUR NEXT JOB.** Brainstorm WITH the human first.
  - **Triage ledger** — ⬜ NOT STARTED (the ~79 still-`[open]` AUDIT findings).
- **Root causes (R1–R6, see §4):** **R2, R3, R5, R6 cleared. R1, R4 remain**
  (both S4).
- **You are on `main`** (`git checkout main && git pull` first). All six merged
  sub-projects passed BOTH gates (`just ci` + the full live `test-full` against
  Stalwart/James/Cyrus).
- **Immediate next action:** S4. **Do NOT write code first.** Use
  `superpowers:brainstorming` to design S4 WITH the human (two decisions need
  their explicit sign-off — see §8). See §13.

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
failure modes of **OpenSSL, c-client/UW-IMAP, and libdbus**.

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
   Your only consideration for API design must be future application developers
   who will use this library."* (`convenience.nim` is itself the **dissolution
   candidate** of S4 — see §8.)
4. **There are 0 users; blast radius does not matter.** Verbatim: *"There are
   currently 0 users of the library. Blast radius doesn't matter. What does matter
   is clean and comprehensive implementation."* Do not preserve backward
   compatibility for its own sake.
5. **Version-agnostic.** Verbatim: *"I want to fix all the issues, don't care
   about what version we are."* The human does **not** want a 1.0 freeze.
   Principles framed around "lock before 1.0" (P1) are reinterpreted as **"fix
   everything now, comprehensively."** `docs/design/14` is written in pre-1.0
   language; that framing is superseded.
6. **Quality is paramount; this is a showcase for the human's team.** Verbatim:
   *"comprehensively and cohesively applied without cutting any corners or leaving
   any loose ends … done in an exemplary fashion and performed to completion …
   Quality of code is of utmost importance."* The human does **not** care about
   speed of execution or token cost. Use subagents and Workflow orchestration
   freely; adversarially verify.

---

## 3. The 29 API principles (the rubric) + the three locked architectural decisions

### 3.1 The 29 principles — one-line summaries
Full authoritative text: **`docs/design/14-Nim-API-Principles.md`** (read it). It
distils six C libraries — great: **libcurl, SQLite, zlib**; cautionary: **OpenSSL,
c-client/UW-IMAP, libdbus**. Reviewers cite principles by number.

- **P1** Lock the contract; evolve by addition only. *(reinterpreted: version-
  agnostic — "fix everything now", §2.5.)*
- **P2** Stability bought with tests. *(but tests are NOT a design driver, §2.2.)*
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
review; both have caught real regressions this campaign. **The CLAUDE.md domain
rules restate this:** *"Make illegal states unrepresentable. One source of truth
per fact. If two fields can disagree, one shouldn't exist. Booleans are a code
smell."* (E1 acted on exactly this — see §6.)

### 3.2 The three locked architectural decisions
The human chose the **maximal-toward-the-libcurl/SQLite-ideal** option on each:
1. **One error rail.** Collapse the 5 call-path rails into one `JmapError` sum (=
   S1, DONE).
2. **One ergonomic core, no quarantine.** SQLite has no convenience module;
   readers/constructors/predicates/one-shots AND one blessed easy-path per
   operation become first-class on the always-on hub. The P6 quarantine
   **dissolves** (S3 delivered the primitives, DONE; **S4 delivers the
   one-shots/easy-path and decides `convenience.nim`'s fate — YOUR job**).
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
`vendor/nim-results` (`Result[T,E]`, `Opt[T]`, `?`, `valueOr`); everything else is
Nim stdlib. The campaign refactors the **public API** so it ages like libcurl and
SQLite.

### 4.2 How things were when the campaign started (2026-06-14)
RFC 8620 + 8621 implemented; L5/Push/Blob deferred. Commit `39e4891` delivered
earlier API enhancements; `96cea22` added the first `examples/jmap-cli/` bench.
**The bench is the P29 consumer:** a CLI driving **only the public API**
(`import jmap_client` [+ `jmap_client/convenience`]) to exercise every RFC
8620/8621 entity area against live Stalwart/James/Cyrus, sending/receiving real
email. **Its purpose is the audit, not the CLI**; `examples/jmap-cli/check-public-only.sh`
enforces public-only imports. It produced: **`examples/jmap-cli/AUDIT.md`** (the
ledger — **92 findings**, now with S1/S2/S3/E1 resolution sections);
**`docs/design/16-api-from-the-consumers-chair.md`** (narrative critique); and a
gitignored recon sheet.

### 4.3 The 92 findings → SIX root causes (the key synthesis)
- **R1 — No one-shot for the common single-method case** (bare-get repetition;
  single-email update triple-seal; single-recipient send). → **S4 (NOT STARTED).**
- **R2 — Missing total readers/constructors/predicates on existing types.** →
  **S3 + E1 (DONE, merged).**
- **R3 — Error-rail fragmentation** (five call-path rails that don't compose). →
  **S1 (DONE, merged).**
- **R4 — The send path has no ergonomic front door** (4-layer blueprint
  hand-build; the misleading `addEmailSubmissionAndEmailSet`; the uncopyable-
  `RequestBuilder`-in-Ok-arm friction). → **S4 (NOT STARTED).**
- **R5 — The contract snapshot didn't describe the surface** (the generator was a
  broken text scraper). → **S0 (DONE, merged).**
- **R6 — Read-model unevenness** (three idioms for the same job). → **S2 (DONE,
  merged).**

**Cleared: R2 (S3/E1), R3 (S1), R5 (S0), R6 (S2). Remain: R1, R4 (both S4).**

### 4.4 Sub-project status
| Sub-project | Clears | Status |
|---|---|---|
| **S0** Truthful contract (compiler-as-library oracle) | R5 | ✅ MERGED `main` (PR #5, `73dee1a`) |
| **S1** One error rail (`JmapError`) | R3 | ✅ MERGED `main` (PR #6, `011830b`) |
| **S2** Read-model uniformity | R6 | ✅ MERGED `main` (PR #7, `1be1514`) |
| **RFC-conformance sweep** (post-S2) | — | ✅ MERGED `main` (PR #8, `ef8c932`) |
| **S3** Complete the core **+ E1** capability reconcile | R2 | ✅ MERGED `main` (PR #10, merge `266fd80`) |
| **S4** One-shots + easy-path + dissolve `convenience.nim` | R1, R4 | ⬜ **NOT STARTED — YOUR JOB** |
| **Triage ledger** (~79 still-`[open]` AUDIT lines) | all 92 | ⬜ NOT STARTED |

(There was also PR #9, merge `1517a76` — a docs-only refresh of the campaign
handoff. Not a code sub-project.)

### 4.5 What the DONE sub-projects delivered (load-bearing detail + lessons)
- **S0 (PR #5).** Replaced the broken `api_surface.nim` text scraper with a
  **compiler-as-library oracle**: `scripts/api_probe.nim` (union re-export of both
  public hubs) + `scripts/api_oracle.nim` (loads the module graph, runs `sem`,
  walks `modulegraphs.allSyms` = exactly what `import jmap_client` exposes; modes
  `api`/`type-shapes` via `API_ORACLE_MODE`). Rewired the `justfile` freeze recipes
  (`freeze-api`/`freeze-type-shapes`) + the H16/H17 lints to diff the committed
  snapshot against the live oracle. **Caveat: a Nim upgrade must re-verify the
  oracle** (it depends on compiler-internal `allSyms`/`ifaces`/`sfExported`).
- **S1 (PR #6).** Collapsed five fragmented rails (`ValidationError`,
  `seq[ValidationError]`, `EmailBlueprintErrors`, `ClientError`, `GetError`) into
  one **flat 6-arm `JmapError` sum** `{jeValidation | jeTransport | jeRequest |
  jeSession | jeMisuse | jeProtocol}` in L3 (`protocol/jmap_error.nim`). Pure L1
  smart constructors stay `Result[T, ValidationError]` and **lift at the L3/L4
  boundary** via `.lift` + `toJmapError` (no `converter`s). `get`/`getBoth`/`getAll`
  return `Result[MethodOutcome[T], JmapError]` — **a server method error is response
  DATA on the ok branch** (`mokValue | mokMethodError`), per RFC 8620 §3.6.2, NOT a
  rail fault. `MethodError`/`SetError` stay response data. The fail-fast `get`
  convenience + the `connect`/`sendPlainText` one-shots were **deferred to S4**.
- **S2 (PR #7).** Made how a consumer **reads** a returned value uniform: **two
  buckets** — every immutable DATA record reads by **direct public field**;
  accessors survive only on stateful **handles** (`JmapClient`, `RequestBuilder`,
  `BuiltRequest`, `Transport`). Delivered the **`FieldEcho` reader**
  (`valueOr`/`isValue`/`isNull`/`isAbsent`/`items`/`toOpt`; both `Opt` and the
  3-state `FieldEcho` kept), direct fields on Thread/Account/Session/capability
  schemas/`Comparator`/`AddedItem`, Tier-A sealed newtypes (`NonEmptyIdSeq`,
  `DisplayName`, `ApiUrl`), public typed capability arms (raw `JsonNode` vendor
  arms sealed — H1b), `Email` non-default headers → `Opt`, `MailboxChanges`
  flattened, six `SetResponse` projection iterators. **Lesson: Tier-B
  (`{.requiresInit.}` brand) was REJECTED** — under the real
  `--warningAsError:UnsafeDefault/UnsafeSetLen` a `requiresInit` value is a hard
  ERROR in `seq.add`/`getOrDefault`/`newSeq`. **Always verify empirical claims
  under the project's REAL flags.**
- **RFC-conformance sweep (PR #8).** Whole-codebase audit; **high conformance**.
  **F1** (the one real bug): `parseHeaderValue` rejected JSON `null` for the four
  single-instance header forms (RFC 8621 §4.1.3 returns `null` for a
  requested-but-absent single-instance header) — all `HeaderValue` arms now `Opt`
  (TDD-found). **F2** removed the non-IANA `subscriptions` mailbox role. **F3**
  renamed the fixture-only full-object `Email`/`Mailbox.toJson` → `toJsonForFixture`.
  **F4** dropped the redundant VacationResponse `vrgkId` selector. **F5** wrote
  `docs/design/known-server-deviations.md` (six deliberate Postel receive-side
  leniencies — kept + documented: liberal on receive, strict on send).
- **S3 (part of PR #10).** "Complete the core": eleven **pure, total, additive**
  readers/predicates/constructors on the final S2 types so a consumer reads an
  `Email`/`Mailbox`/`Session` and builds a plain-text send body **without**
  `import std/tables`, a hand-walked case object, or a hand-rolled capability
  preflight. **No new types**; the contract grew **+12 lines in `public-api.txt`
  only**. Symbols: `mail/email`: `bodyValue`, `leafTextParts` (iterator),
  `decodedTextBody` (case-insensitive `text/plain`, RFC 2045 §5.1), `textBodies`×2;
  `mail/mailbox`: `isInbox`, `hasRole`; `mail/email_blueprint`: `plainTextBody`;
  `protocol/preflight`: `requireMail`/`requireSubmission`/`requireVacation` (RFC
  8620 §2 soft resolution — `accountCapabilities` authoritative, primary-preferred,
  deterministic lowest-`$AccountId` fallback); `types/framework`: `limit`.
  **Deliberate S3 exclusions (NOT gaps):** `can*` rights roll-ups (RFC 8621 §2
  keeps the nine `may*` rights orthogonal — a conjunction would misreport; the
  campaign handoff had *guessed* these and the RFC rejected them), `roleKind`, a
  public part-level body ctor / send-side `partId` mint, `htmlBodies()`/`allBodies()`.
- **E1 (part of PR #10).** A subtractive reconcile folded into S3's branch before
  the push. S3 shipped three **named-soft** resolvers beside the S1-merged
  **general-strict** `requirePrimaryAccount`, which had **zero production callers**
  and silently disagreed on the no-primary case. E1 **(a)** removed
  `requirePrimaryAccount` and its dead `sfPrimaryAccountAbsent` fault, then **(b)** —
  after a 4-lens adversarial review caught that the subtraction left
  `SessionFault.kind` a *single-valued, write-only discriminator* — **flattened
  `SessionFault` to a plain `{ capability }` object** (dropping `SessionFaultKind`,
  `sfCapabilityAbsent`, and the constructor's `kind` param), matching its flat
  single-reason sibling `Misuse`. The designated-primary need is served by the
  existing public `session.primaryAccount(kind): Opt`. **Net E1: −42 LoC, purely
  subtractive.** This deliberately **overturned the approved E1 spec §3.2 "no
  further collapse of SessionFault"** — the spec's "a one-variant enum is valid and
  extensible" was the fallible-design-doc call; the review + the human's decision
  took it to the leaner, principle-aligned end-state (CLAUDE.md: "single-value
  fields are a code smell"). **Lesson: when subtraction degenerates a sum type to
  one inhabitant, flatten it — do not ship a write-only discriminator.**

---

## 5. THE CRITICAL METHODOLOGY LESSON — the RFC is authoritative; the design docs are fallible

**Internalise this.** Memory `rfc-is-authoritative` (the human's standing
correction): *"D5, spec §8 etc are not authoritative. These are specs made by
agents which made many mistakes. Consult the authoritative figure, the RFC docs."*
**The RFC text in `docs/rfcs/` governs every protocol-correctness question; the
agent-authored design docs (`docs/design/*`, the superpowers specs, the D/A/B-
numbered decisions, even these handoffs) are fallible and have been WRONG.**
Grounding work in the RFC has caught real errors that would otherwise have shipped:
- **D5** — every `toJson` emits `null` for `Opt.none`; RFC 8620 §5.1 says a `/get`
  returns only requested properties (absent, never null). The sweep fixed only
  Email headers; **the broad serde-fidelity defect is DEFERRED** — do NOT blindly
  generalise the omit rule, it needs its own serde audit (parked, §8).
- **B12** — `parseAccount` dropped a read-only account's capabilities (RFC 8620 §2
  violation) — removed in S2.
- **H1b** — S2's capability-arm exposure made raw `JsonNode` vendor arms public
  (reopening raw construction past the fallible ctor — P15/P16) — resealed.
- **F1, F2** (RFC sweep) — the header-`null` bug and the non-IANA role.
- In S3: the `usableAccount` Postel gap (a `primaryAccounts` pointer trusted
  without checking `accountCapabilities`) — fixed in S3 hardening.
**Tell every reviewer subagent to validate against the RFC, not the design docs;
delegate such investigations to subagents to protect context.**

---

## 6. What is LEFT

### 6.1 S4 — one-shots + easy-path + dissolve the `convenience.nim` quarantine (clears R1, R4) — YOUR JOB
The `curl_easy_*` / `sqlite3_exec` surface, first-class on the always-on hub.
Scope (re-derive the exact set from `examples/jmap-cli/AUDIT.md` + `docs/design/16`
+ the S1/S3 "deferred to S4" notes):
- `connect(url, user, pass)` — the missing one-call session bootstrap.
- `sendPlainText(...)` — consumes S3's `plainTextBody`; hides the 4-layer blueprint
  chain **and** the two-creation (EmailSubmission + Email/set) wiring.
- `queryThenGet` — the query→get combinator (the bare-get repetition, R1).
- bare-get single-method one-shots (the per-entity get convenience deferred from S1).
- the **fail-fast `get`** convenience deferred from S1 — **OPEN DESIGN QUESTION:
  may a convenience put a `MethodError` (normally response *data* on the ok branch,
  RFC 8620 §3.6.2) onto the `JmapError` rail?** This needs the human's decision.
- a front door for the **uncopyable-`RequestBuilder`** friction
  (`addEmailSubmissionAndEmailSet` returns an uncopyable builder in its Ok arm, so
  it can't ride `?`/`.lift` today).

**TWO DECISIONS NEED THE HUMAN'S EXPLICIT SIGN-OFF BEFORE ANY CODE:**
1. **The fate of `convenience.nim`** — dissolve the P6 quarantine entirely (fold
   the blessed easy-path onto the always-on hub) vs keep it only for honest
   multi-method compositions. (Decision 2 in §3.2 leans toward dissolve; confirm.)
2. **The fail-fast-`get` design** — see the open question above.

**HARD GATE:** S4 begins with `superpowers:brainstorming` — design WITH the human,
present 2–3 approaches, get approval. **No implementation skill, no code, until the
design is approved and written to `docs/superpowers/specs/`.** Then
`superpowers:writing-plans` → `superpowers:subagent-driven-development` (§10), both
gates (§7.1), confirm push/PR with the human.

### 6.2 Triage ledger (AUDIT Phase 2) — best done after S4
`examples/jmap-cli/AUDIT.md` still has **~79 findings mechanically marked
`[open]`** (Phase 1 was observe-only). ~13+ are already FIXED by S1/S2/S3/E1 (and
described in the AUDIT's resolution sections) but not reconciled per-line. **Convert
every `[open]` line → `resolved-Sn | accepted-as-trade-off | filed-as-Cn`**, mapped
to its fixing sub-project, with rationale. **Re-bench the CLI** against the final
S4 deliverables first (public-only — `check-public-only.sh`); update `AUDIT.md` /
`docs/design/16`.

### 6.3 Deferred parking lot (out of scope for the current sub-projects; candidates for S4/triage or a future additive pass)
- **#2** — a read-side `EmailLeaf` view type for `leafTextParts` (P16: `partId`/
  `blobId` sit behind a `case`). Needs a NEW type → was out of S3's "no new types"
  scope; a future additive pass.
- **#3** — `leafTextParts` / `limit` naming; the still-public raw `Blueprint*` part
  constructors (a P15 tightening / non-additive removal).
- **`NonEmptyIdSeq.toSeq` vs `std/sequtils.toSeq` collision** (a `.asSeq` rename
  matching the sibling `NonEmptySeq[T].asSeq` would fix it).
- **D5 — the broad `toJson` null-for-none serde-fidelity defect** (RFC 8620 §5.1).
  Only Email headers fixed so far; needs its own serde audit, NOT a blind
  generalisation of the omit rule.
- `ParsedEmail` body-reader overloads; `htmlBodies()`/`allBodies()` fetch-option
  siblings.

---

## 7. Quality requirements, gates, and conventions (MANDATORY)

### 7.1 The two gates — a sub-project is DONE only when BOTH pass
1. **`just ci`** — reuse (SPDX), fmt-check (nph), the full lint battery
   (`lint-public-api` = H16, `lint-type-shapes` = H17, `lint-error-messages` = H15,
   `lint-sealed-distinct` = H1, `lint-fallible-ctor-public-arm` = H1b, plus the
   internal-boundary / module-path / style / typed-builder lints), `analyse`
   (nimalyzer — incl. **`complexity` ≤ 10**, **`hasdoc`**, and **`caseStatements
   min 2`**, which fire ONLY here, not in `just build`), and the fast `test`.
2. **`just clean && just jmap-reset && just test-full`** — in that EXACT order
   (clean → recreate the live Stalwart/James/Cyrus servers → the full live sharded
   suite). On any failure, fix, then **re-run the WHOLE sequence** until **"All
   shards passed"**. Long-running (server rebuild + full suite, ~10–25 min); run it
   in the **background** and await completion. (CLAUDE.md says agents normally leave
   `test-full` to the user — but the human has directed agents to run it.)

**Gate lessons (learned the hard way — internalise):**
- `just test` (fast) **skips the files in `tests/testament_skip.txt`** (the
  property/stress tests, `tests/protocol/*`, the live tests) — those run only in
  `test-full`. A skip-listed file can hide a break that ONLY `test-full` surfaces;
  when a refactor ripples into tests, **sweep ALL of `tests/`.**
- nimalyzer's `complexity` (≤10), `hasdoc`, and `caseStatements min 2` run only in
  `just ci`, NOT in `just build`. New per-form branches or **undocumented test
  helpers** fail there (`hasdoc` applies to `tests/` too — a missing `##` on a
  test-helper `proc` bit S3). **Restructure / add docstrings to comply; NEVER
  suppress a nimalyzer rule.**
- **`caseStatements min 2`** forbids a single-arm `case`. **`tno_asserts_in_src`**
  (a compliance test) forbids `doAssert` anywhere under `src/` — **even inside
  `static:`**. So when a sum type degenerates to one variant and you still want
  exhaustiveness, the **CI-blessed idiom** is a module-scope guard:
  `when MyEnumKind.low != MyEnumKind.high: {.error: "a new variant was added;
  rewrite as a case dispatch".}` (precedent:
  `src/jmap_client/internal/mail/serde_email_submission.nim`). **But first ask:
  should the type be flattened instead?** (E1's lesson — a write-only single-valued
  discriminator is a smell; flatten it.)
- The per-type **`{.ruleOff: "objects".}`** exemption for a public-field DATA record
  is the **SANCTIONED** mechanism (176-use precedent; `objects` = `check objects
  publicfields`), distinct from suppressing a rule like `complexity`.
- `just fmt`/`fmt-check` and `just analyse` cover `src/` + `tests/` only, NOT
  `examples/` — the example CLI is verified by building it (`nim c
  examples/jmap-cli/jmap_cli.nim`) + `bash examples/jmap-cli/check-public-only.sh`.
- After any hand-edit, run `just fmt` (nph) before the gate; nph reflows lines.

### 7.2 Coding conventions (CLAUDE.md + `.claude/rules/`)
- **Layers:** L1 types, L2 serde, L3 protocol → `{.push raises: [],
  noSideEffect.}` + `func`/`iterator` only (no `proc`); L4 transport/client, L5
  FFI → `{.push raises: [].}`. Every `src/` file has `{.experimental:
  "strictCaseObjects".}` right after the push pragma. (Tests are exempt from the
  pragma but NOT from `hasdoc`.)
- **strictCaseObjects:** read a variant field only inside a `case` that *proves*
  the discriminator (an `if` is NOT enough — Rule 1). No nested case-in-case;
  prefer a public discriminator; combined-arm reads per `.claude/rules/
  nim-type-safety.md`. (A FLAT object's `kind`-typed field is a plain enum, NOT a
  case object — no strict obligation.)
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
  illegal states unrepresentable (P15/P16). One source of truth per fact;
  single-value fields are a smell.
- **British-English** comments/docstrings that explain *why*, not *what*;
  **RFC-section refs only** in comments (no design-doc/campaign cross-refs — no
  "S1"/"E1"/"D5"/"Pattern 8"; no forward-refs to unshipped symbols). Naming a
  toolchain constraint that governs the code's shape (a nimalyzer rule, a
  compliance test) IS acceptable why-context. Every public `func`/`iterator` **and
  every test-helper `proc`** needs a `##` docstring.

### 7.3 Commit format (Linux-kernel style)
Subject `subsystem: short imperative` ≤ 75 cols; body wrapped ~75 cols, explains
**why**. End EVERY commit body with exactly:
```
Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
```
**No other AI/LLM attribution in any git message.** A PR *body* is GitHub metadata,
not a git message — but the human is strict about attribution; **the campaign PRs
carry NO Claude Code footer in the PR body.**

### 7.4 Execution discipline
- **Branch first** (`api/<sub-project>`); **NEVER implement on `main`.** **Commit
  per task, each green** (`just build` keeps `src/` building; the full gate at the
  end), with the plan's STATE block flipped in the same commit — `git log` + the
  STATE block reconstruct progress after a compaction.
- **Stage explicit paths; NEVER `git add -A`.**
- **Confirm outward-facing actions (push, PR, merge) with the human** before doing
  them. The human authorises these explicitly; prior sub-projects merged via PR
  only after the go-ahead.
- **REUSE / SPDX (a `just ci` gate):** `REUSE.toml` covers `src/**`, `tests/**`,
  `docs/**` and common extensions; **`scripts/**` is NOT glob-covered** (new `.nim`
  there needs an inline two-line BSD-2-Clause + copyright header). Docs use a
  CC-BY-4.0 SPDX id inside an HTML comment. The REUSE linter scans for the
  SPDX-identifier string *anywhere*; a backtick-wrapped SPDX example in markdown
  prose trips it — wrap such prose in `<!-- REUSE-IgnoreStart -->` /
  `<!-- REUSE-IgnoreEnd -->`.

---

## 8. The process discipline that has carried six sub-projects (keep doing it)

This is *how* the work is done, not just *what*. It is why every merge was both-gates-green.

- **`superpowers:brainstorming` (HARD GATE)** — design each sub-project WITH the
  human before any code; present 2–3 approaches; get approval; write the spec to
  `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` (gitignored). No
  implementation skill until approved.
- **`superpowers:writing-plans`** — a durable, on-disk plan with a **STATE/HANDOFF
  block** and a **ripple-completeness ledger** (every reference the change touches,
  built from a fresh `grep` — the design specs have under-named ripple before).
  Bite-sized tasks, exact code/commands, no placeholders.
- **`superpowers:subagent-driven-development`** — the per-task loop:
  1. a **fresh implementer subagent** does the work but **does NOT commit** (you own
     commits);
  2. you dispatch **two reviewers** (spec-compliance + code-quality, in parallel,
     read-only) — tell them the RFC is authoritative;
  3. **you re-run the gate yourself** (compiler/oracle/`just ci` is the objective
     truth — reviewers are not infallible, and have caught AND misjudged things);
  4. **you author the Linux-kernel commit** (explicit paths, the three trailers) and
     **flip the plan's STATE block in the same commit**.
- **Adversarial verification (the Workflow tool)** — a final multi-lens review of
  the whole diff *before* the gates (RFC / 29-principles / purity / libcurl-SQLite
  lens / completeness). This session's 4-lens Workflow on E1 found no correctness
  defect but surfaced the write-only-discriminator design nit that became the
  flatten — a real quality win the subtraction alone would have shipped past. Use
  subagents/Workflow freely (token cost is no object); **always re-run the objective
  gate yourself.**
- **Compaction-safety** — the on-disk plan STATE block + `git log` + the
  `api-libcurl-sqlite-refactor` memory are the durable record; update them as each
  task lands so a fresh agent recovers full state. Per-task durable commits mean no
  work is lost across a compaction mid-sub-project.
- **When a reviewer/Workflow surfaces a design decision that overturns an approved
  spec or changes the public contract, put it to the human** (this session asked
  via `AskUserQuestion` whether to flatten `SessionFault` — the human chose to). The
  human owns surface-shape decisions.

---

## 9. Key file map

### 9.1 Handoffs / specs / plans
- **THIS FILE** — the current canonical orientation (post-S3/E1). Read first.
- `docs/superpowers/plans/2026-06-15-CAMPAIGN-HANDOFF.md` — the older umbrella
  handoff. **Its §0/§6/§12/§13 are STALE** (say "S3 not started"); trust THIS file.
- `docs/superpowers/plans/2026-06-16-E1-RECONCILE-AND-S3-WRAPUP-HANDOFF.md` — the
  E1 brief (now DONE; useful for how S3/E1 were built).
- Per-sub-project plans (each with a STATE block): `…-s1-one-error-rail-plan.md`,
  `…-s2-read-model-uniformity-plan.md`, `…-rfc-conformance-sweep.md`,
  `…-2026-06-16-s3-complete-the-core-plan.md`,
  `…-2026-06-16-s3-capability-resolution-reconcile-plan.md` (E1).
- Gitignored design specs under `docs/superpowers/specs/`.

### 9.2 The rubric, the RFC, the bench
- `docs/design/14-Nim-API-Principles.md` — **the 29 principles (the rubric).**
- `docs/design/16-api-from-the-consumers-chair.md` — narrative consumer critique
  (S2/S3-updated).
- `docs/design/known-server-deviations.md` — the RFC-deviation register (sweep F5).
- **`docs/rfcs/`** — the **authoritative** RFC text (8620, 8621, 8887, 2045,
  5321/5322/3461/8909). Consult for any protocol-correctness question (§5).
- `examples/jmap-cli/AUDIT.md` — the 92-finding ledger (+ S1/S2/S3/E1 resolution
  sections). `examples/jmap-cli/` — the P29 bench; `check-public-only.sh` enforces
  public-only imports.

### 9.3 The source tree
- `src/jmap_client.nim` — the public re-export hub (L5 C-ABI exports land here).
- `src/jmap_client/convenience.nim` — opt-in pipeline combinators (**the P6
  dissolution candidate — S4 decides its fate**; the only public module path
  besides root).
- `src/jmap_client/internal/`:
  - `types/` (L1): `primitives`, `identifiers`, `validation`, `field_echo`,
    `framework`, `capabilities`, `account_capability_schemas`, `session`,
    `envelope`, `errors`, `collation`, `methods_enum` — re-exported via
    `internal/types.nim`.
  - `serialisation/` (L2): serde leaves (no public hub; in-tree callers import leaves).
  - `protocol.nim` + `protocol/` (L3): `builder`, `dispatch`, `methods`, `entity`,
    `jmap_error` (the 6-arm `JmapError`; `SessionFault` is now a flat
    `{ capability }` after E1), `preflight` (the `requireMail`/`requireSubmission`/
    `requireVacation` family + private `usableAccount`/`lowestAdvertising`).
  - `transport.nim` + `transport/` (L4); `client.nim` (L4, `JmapClient`).
  - `mail/` (RFC 8621 entities — `email`, `mailbox`, `email_blueprint`, `body`,
    `headers`, `email_update`, …; re-exported via `mail/types.nim` → `internal/mail.nim`).
  - `push.nim` / `websocket.nim` — deferred type stubs (RFC 8620 §7 / RFC 8887).

### 9.4 Tooling / config
- `scripts/api_oracle.nim` + `api_probe.nim` — the S0 contract oracle (`just
  freeze-api`/`freeze-type-shapes` drive it); `scripts/freeze_error_messages.nim` —
  the H15 error-message snapshot generator (and the H15 lint
  `tests/lint/h15_error_message_snapshot.nim` **inlines the same sample sequence
  verbatim** — edit both in lockstep).
- `tests/wire_contract/{public-api,type-shapes,error-messages,module-paths}.txt` —
  the frozen contract (oracle-generated). `tests/lint/{h1*,h15,h16,h17,…}` — the
  lock lints. `tests/testament_skip.txt` — the fast-suite skip list (run only in
  `test-full`). `tests/compliance/tno_asserts_in_src.nim` — forbids `doAssert` in src/.
- `nimalyzer.cfg` — the static-analysis rules (`complexity`, `hasdoc`,
  `caseStatements min 2`, `objects`, `params`, …). NEVER relax.
- `config.nims` / `jmap_client.nimble` — compiler flags (`--mm:arc`, `strictDefs`,
  `strictEffects`, `threads:on`, `panics:on`, the `warningAsError` battery incl.
  `UnusedImport`/`UnsafeDefault`/`ObservableStores`). `config.nims` puts `src/` +
  `vendor/nim-results` on the path, so `nim c -r tests/path/file.nim` runs a single
  test file standalone (UnusedImport is a hard error there).
- `CLAUDE.md` + `.claude/rules/{nim-conventions,nim-type-safety,nim-functional-core,
  nim-ffi-boundary}.md` — the project rules. Skills: `jmap-protocol`,
  `nim-json-serde`, `testament`, `comment-base`.
- `/.nim-reference/` — read-only Nim stdlib + compiler + docs.

---

## 10. Current working state (snapshot, 2026-06-16)

- On **`main`** (up to date with `origin/main`, merge `266fd80` = PR #10). **S0 +
  S1 + S2 + the RFC-conformance sweep + S3 + E1 are ALL merged.** Working tree
  clean; no code changes pending. `main`'s tree was verified byte-identical to the
  both-gates-green branch tip and ghost-free after the merge.
- **S4 and the triage ledger have NOT started.**
- Memories present + current: `api-libcurl-sqlite-refactor` (campaign state — marks
  S0–S3/E1 merged, S4/triage next), `api-design-only-consumers` (the design lens),
  `rfc-is-authoritative` (the §5 lesson), plus the older
  `api-refactor-section-ab-campaign` (partly superseded).

---

## 11. Immediate next action

**S4 (one-shots + easy-path + dissolve the `convenience.nim` quarantine; clears R1,
R4).** Steps:
1. `git checkout main && git pull`. Re-read §2 (design lens), §5 (RFC-is-
   authoritative), §7 (gates/conventions), §8 (process), and
   `docs/design/14-Nim-API-Principles.md`. Skim `examples/jmap-cli/AUDIT.md` and
   `docs/design/16` for the open R1/R4 friction lines and the deferred parking lot.
2. **Use `superpowers:brainstorming` to design S4 WITH the human first (HARD GATE —
   no code until approved).** Get explicit sign-off on the **two decisions** in §6.1
   (the fate of `convenience.nim`; the fail-fast-`get` design). Present 2–3
   approaches via `AskUserQuestion`; write the approved spec to
   `docs/superpowers/specs/`.
3. Then `superpowers:writing-plans` → `superpowers:subagent-driven-development`:
   branch `api/s4-one-shots` off `main`, a STATE-tracked plan with a ripple ledger,
   green-per-task commits with the three trailers, both gates at the end. Ground
   every protocol question in the RFC (§5). Re-bench the CLI public-only and update
   `AUDIT.md`/`docs/design/16`. **Confirm push/PR/merge with the human.**
4. After S4 merges: the **triage ledger** (§6.2).

**When in doubt, re-read §2.** Optimise for the future application developer,
comprehensively, no corners cut, exemplary/showcase quality — **libcurl/SQLite, not
OpenSSL/libdbus.** Would libcurl or SQLite do this?
