<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# CAMPAIGN HANDOFF — jmap-client API → libcurl/SQLite refactor

> **You are a fresh agent with ZERO prior context. Read this whole document
> before doing anything.** It is the single canonical orientation: the mission,
> the non-negotiable design lens, the full history, exactly what is done, exactly
> what is left, every quality gate, and the immediate next action.
>
> **Last updated 2026-06-16, after S0 + S1 + S2 + the RFC-conformance sweep all
> MERGED to `main`.** The campaign began 2026-06-14.
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
  C/C++. It is an email-protocol library — no UI, no app. RFC 8620 + 8621 are
  implemented; **Layer-5 C FFI, Push (RFC 8620 §7), and Blob upload/download are
  deferred** campaign-wide.
- **Mission:** refactor the library's **public API** so it ages like **libcurl
  and SQLite**, not like **OpenSSL or libdbus**, driven entirely by the needs of
  the **future application developer** who will link this library into an email
  client. (Full mission verbatim in §1; the non-negotiable design lens in §2.)
- **Status — four sub-projects DONE & merged to `main`; three remain:**
  - **S0 (truthful contract)** — ✅ merged (PR #5, `73dee1a`). Clears R5.
  - **S1 (one error rail, `JmapError`)** — ✅ merged (PR #6, `011830b`). Clears R3.
  - **S2 (read-model uniformity)** — ✅ merged (PR #7, `1be1514`). Clears R6.
  - **RFC-conformance sweep** (a NEW post-S2 sub-project) — ✅ merged (PR #8,
    `ef8c932`). High overall conformance; one real bug + 3 cleanups fixed, 6
    deliberate Postel divergences documented.
  - **S3 (complete the core)** — ⬜ NOT STARTED. Clears R2.
  - **S4 (one-shots + easy-path + dissolve quarantine)** — ⬜ NOT STARTED. Clears
    R1 + R4.
  - **Triage ledger** — ⬜ NOT STARTED (the AUDIT findings are still mechanically
    `[open]`; reconciling them is this task).
- **Root causes (R1–R6, see §4):** **R3, R5, R6 cleared.** **R1, R2, R4 remain.**
- **You are on `main`** (or wherever the handoff branch is — `git checkout main`
  and `git pull` first). All four merged sub-projects passed BOTH gates (`just ci`
  + the full live `test-full` against Stalwart/James/Cyrus).
- **Immediate next action:** the user directs the order, but the dependency chain
  is **S3 → S4 → triage ledger**. S3 is unblocked (its S2 prerequisite is merged).
  See §9 (scope) and §13 (how to start).

---

## 1. The mission (the user's own words — verbatim, the prompt that began this)

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

**So:** RFC 8620 + 8621 are implemented; L5 FFI, Push, Blob are deferred. The
work is **API design quality**, judged by a real consumer (the
`examples/jmap-cli/` bench), against the **29 API principles**. The resulting
public API must follow the patterns of **libcurl and SQLite** and avoid the
failure modes of **OpenSSL and libdbus**.

---

## 2. THE NON-NEGOTIABLE DESIGN LENS (read twice — overrides any principle on conflict)

This governs **every** design decision in the campaign. Memorise it.

1. **The ONLY design input is the future application developer** who will
   consume this library to add JMAP support to an email client. Model the API
   after **libcurl and SQLite**; actively avoid the failure modes of **OpenSSL
   and libdbus**.
2. **Tests are NOT a design input.** Verbatim: *"Tests should not be a factor in
   the API design. Tests can and should be accommodated to by other means."*
   Never justify an API shape with "easier to test." Never bend the public
   surface or the source to placate a tool — fix the tool/tests instead.
3. **Incumbent callers are NOT constraints.** Verbatim: *"what `convenience.nim`
   or any other current caller happens to use is not a design input; if a current
   caller breaks under the principled cut, that is a finding, not a constraint."*
   `convenience.nim` is itself a **dissolution candidate** (decision 2 / S4).
4. **There are 0 users. Blast radius does not matter.** Verbatim: *"There are
   currently 0 users of the library. Blast radius doesn't matter. What does matter
   is clean and comprehensive implementation."* Do not preserve backward
   compatibility for its own sake.
5. **Version-agnostic.** The user explicitly does **not** want a 1.0 freeze:
   *"I want to fix all the issues, don't care about what version we are."*
   Principles framed around "lock before 1.0" (P1) are reinterpreted as **"fix
   everything now, comprehensively."** Do **not** tag versions or split work to
   protect a release.
6. **Quality is paramount; this is a showcase for the user's team.** Verbatim:
   *"comprehensively and cohesively applied without cutting any corners or leaving
   any loose ends … done in an exemplary fashion and performed to completion."*
   The user does **not** care about speed of execution or token cost.

When in doubt, ask: **"would libcurl or SQLite do this? Or is this the
OpenSSL/libdbus choice?"**

---

## 3. The 29 API principles (the rubric)

Full authoritative text: **`docs/design/14-Nim-API-Principles.md`** — read it. It
distils lessons from six C libraries (great: libcurl, SQLite, zlib; cautionary:
OpenSSL, c-client/UW-IMAP, libdbus). One-line summaries:

- **P1** Lock the contract; evolve by addition only. *(reinterpreted: version-
  agnostic; "fix everything now" — see §2.5)*
- **P2** Stability bought with tests. *(do NOT use tests as a design driver — §2.2)*
- **P3** Overloading/default args over `_v2` suffix versioning.
- **P4** Pick a scope; defend it (JMAP only — no IMAP/POP/SMTP/contacts/calendars).
- **P5** Single public layer; internals are internal.
- **P6** Convenience APIs quarantined from the protocol-fidelity core.
  *(DECISION: DISSOLVE this — decision 2; readers etc. become core. The
  quarantine is `convenience.nim`, dissolved in S4.)*
- **P7** Watch the wrap rate (if everyone wraps you, the API is wrong).
- **P8** Opaque handles via private fields + ARC `=destroy`.
- **P9** Max two context types per concept (handle + builder).
- **P10** No global state; configuration is a typed value.
- **P11** No global callbacks; per-handle field + context (closure).
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
  framework lock-in; don't import chronos/asyncdispatch in L1–L3).
- **P23** Plan Push/WebSocket as a separate type from day one.
- **P24** Decide the threading invariant explicitly; encode it.
- **P25** License clarity (BSD-2-Clause).
- **P26** Standard build tooling (mise + just + nimble); no per-OS branching.
- **P27** Documentation as succession planning.
- **P28** Long-form first-party narrative documentation.
- **P29** Bench API ergonomics with a real consumer (= the `jmap-cli` bench).

Reviewers cite principles by number. **P15/P16 are the project's #1 DDD principle
in practice — "make illegal states unrepresentable."** It is mechanically enforced
by the H1/H1b lints and an adversarial reviewer will (and did) flag violations.

---

## 4. How things were when the campaign started (2026-06-14)

- RFC 8620 + 8621 implemented; **L5 FFI, Push, Blob deferred**.
- Commit `39e4891` delivered earlier API enhancements; commit `96cea22` added the
  first `examples/jmap-cli/` bench.
- **The bench is the P29 consumer:** a CLI driving **only the public API**
  (`import jmap_client` [+ `jmap_client/convenience`]) to exercise every RFC
  8620/8621 entity area against live JMAP servers (Stalwart/James/Cyrus). It
  sends/receives real email. **Its purpose is the audit, not the CLI.** A guard
  script `examples/jmap-cli/check-public-only.sh` enforces public-only imports.
- The bench produced three artefacts (read to understand the findings):
  - **`examples/jmap-cli/AUDIT.md`** — the ledger: **92 findings** (≈16 positives,
    ≈76 frictions; ~6 high / 7 medium). No command was inexpressible via the
    public API. Now carries an **"S1 resolution"** and an **"S2 resolution"**
    section mapping the error-rail and read-model findings to their fixes.
  - **`docs/design/16-api-from-the-consumers-chair.md`** — narrative critique
    (updated by S2 to reflect the now-uniform read model).
  - **`docs/superpowers/jmap-cli-api-truth.md`** — recon truth sheet (gitignored).

### The 92 findings reduced to SIX root causes (the key synthesis)

- **R1 — No one-shot for the common single-method case.** (bare-get repetition;
  single-email update triple-seal; single-recipient send.) → **S4 (not started).**
- **R2 — Missing total readers/constructors on existing types.** → **S3 (not
  started).** NB: the `FieldEcho` reader once parked here was delivered by S2.
- **R3 — Error-rail fragmentation.** Five call-path rails that don't compose. →
  **S1 — ✅ CLEARED.**
- **R4 — The send path has no ergonomic front door.** (4-layer blueprint
  hand-build; the misleading `addEmailSubmissionAndEmailSet`; the uncopyable-
  `RequestBuilder`-in-Ok-arm friction.) → **S4 (not started).** *(S1 fixed only
  the error-rail portion.)*
- **R5 — The contract didn't describe the surface.** The snapshot generator was a
  broken text scraper. → **S0 — ✅ CLEARED.**
- **R6 — Read-model unevenness.** Three idioms for the same job (direct fields vs
  accessors vs `Opt`-vs-`FieldEcho`). → **S2 — ✅ CLEARED.**

---

## 5. Architecture: the three locked decisions + the campaign decomposition

The user chose the **maximal-toward-the-libcurl/SQLite-ideal** option on each:

1. **One error rail.** Collapse the 5 call-path rails (R3) into one `JmapError`
   sum. → **S1 ✅ DONE.**
2. **One ergonomic core, no quarantine.** SQLite has no convenience module;
   readers/constructors/predicates/one-shots AND one blessed easy-path per
   operation become first-class on the always-on hub. The P6 quarantine
   **dissolves**; `convenience.nim` folds into the core or is kept only for honest
   multi-method compositions. → **S3 (primitives) + S4 (one-shots/easy-path).**
3. **One read idiom.** Uniform access across all entity *data records*; one
   optionality model per field. **REFRAMED during S2** (a finding, not a
   constraint): keep BOTH `Opt` and `FieldEcho` — collapsing the types destroys
   the RFC 8620 §5.3 absent-vs-null bit — and unify at the **reader** layer
   instead. → **S2 ✅ DONE.**

**Decomposition into 6 sub-projects** (each its own spec → plan → implement
cycle via the superpowers brainstorming → writing-plans → executing /
subagent-driven-development skills). Order: **S0, then S1 & S2 (independent of
each other), then S3, then S4, then the triage ledger.** A NEW seventh
sub-project — the **RFC-conformance sweep** — was added after S2 (see §8) and is
DONE.

---

## 6. Sub-project status table

| # | Sub-project | Clears | Status | PR / branch |
|---|---|---|---|---|
| **S0** | Truthful contract (compiler-as-library oracle) | R5 | ✅ MERGED | PR #5 `73dee1a` |
| **S1** | One error rail (`JmapError`) | R3 | ✅ MERGED | PR #6 `011830b` |
| **S2** | Read-model uniformity | R6 | ✅ MERGED | PR #7 `1be1514` |
| **—** | RFC-conformance sweep (post-S2) | — | ✅ MERGED | PR #8 `ef8c932` |
| **S3** | Complete the core (readers/ctors/predicates/`requireMail`) | R2 | ⬜ NOT STARTED | — |
| **S4** | One-shots + easy-path + dissolve quarantine | R1, R4 | ⬜ NOT STARTED | — |
| **—** | Triage ledger (AUDIT Phase 2) | all 92 | ⬜ NOT STARTED | — |

---

## 7. What the DONE sub-projects delivered

### S0 — Truthful contract (✅ merged, PR #5)
Replaced the broken `api_surface.nim` text scraper with a **compiler-as-library
oracle**: `scripts/api_probe.nim` (union re-export of both public hubs) +
`scripts/api_oracle.nim` (loads the module graph, runs `sem`, walks
`modulegraphs.allSyms` = exactly what `import jmap_client` exposes; two modes
`api`/`type-shapes` via `API_ORACLE_MODE`). Rewired the `justfile` freeze recipes
(`freeze-api`/`freeze-type-shapes`) and the H16/H17 lints to diff the committed
snapshot against the live oracle. **A Nim upgrade must re-verify the oracle**
(depends on compiler-internal `allSyms`/`ifaces`/`sfExported`).

### S1 — One error rail (✅ merged, PR #6)
Collapsed five fragmented rails (`ValidationError`, `seq[ValidationError]`,
`EmailBlueprintErrors`, `ClientError`, `GetError`) into one **flat 6-arm
`JmapError` sum** `{jeValidation | jeTransport | jeRequest | jeSession | jeMisuse
| jeProtocol}` living in L3 (`protocol/jmap_error.nim`). Pure L1 smart
constructors stay `Result[T, ValidationError]` and **lift at the L3/L4 boundary**
via `.lift` + `toJmapError` (no `converter`s). `get`/`getBoth`/`getAll` return
`Result[MethodOutcome[T], JmapError]` — **a server method error is response DATA
on the ok branch** (`mokValue | mokMethodError`), per RFC 8620 §3.6.2, not a rail
fault. `MethodError`/`SetError` remain response data. The fail-fast `get`
convenience + the `connect`/`sendPlainText` one-shots were **deferred to S4**.

### S2 — Read-model uniformity (✅ merged, PR #7)
Made how a consumer **reads** a returned value uniform (root cause R6). The
design: **two buckets** — every immutable DATA record reads by **direct public
field**; accessors survive only on stateful **HANDLES** (`JmapClient`,
`RequestBuilder`, `BuiltRequest`, `Transport`). Invariants moved into the field
**type** (Tier-A sealed newtypes) or are parse-enforced with raw construction
documented out-of-contract (Tier-C). Delivered:
- **`FieldEcho` reader** — `valueOr` (template, mirrors `Opt.valueOr`),
  `isValue`/`isNull`/`isAbsent`, an `items` iterator, `toOpt`. Both `Opt` and
  `FieldEcho` kept (the 3-state `FieldEcho` carries the RFC 8620 §5.3 absent-vs-
  null bit a 2-state `Opt` would lose).
- **Direct public fields** on Thread, Account, Session, the capability schemas,
  `Comparator`, `AddedItem`; `lent`/accessor ceremony dropped.
- **Tier-A sealed newtypes:** `NonEmptyIdSeq` (relocated to `types/primitives.nim`),
  `DisplayName`, `ApiUrl`.
- **Capability case-objects:** public discriminator + the TYPED arms public; raw
  `JsonNode` vendor arms stay sealed (H1b — see §8).
- **`Email` non-default header fields → `Opt`** (RFC 8621 §4.2 / §5.1: not-fetched
  ≠ empty); `MailboxChangesResponse` flattened to read through `base`; **six
  `SetResponse` projection iterators** (`created`/`updated`/`destroyed` +
  `*Failures`).
- **The example CLI deleted its hand-rolled `fieldEchoOr`** — the headline R6 win.
- **Tier-B (brand + `{.requiresInit.}`) was REJECTED** — under the real
  `--warningAsError:UnsafeDefault/UnsafeSetLen` flags a `requiresInit` value is a
  hard ERROR in `seq.add`/`getOrDefault`/`newSeq`. **Lesson: verify empirical
  claims under the project's REAL flags.**
- Approved spec (gitignored):
  `docs/superpowers/specs/2026-06-15-s2-read-model-uniformity-design.md`; the
  14-phase plan with a STATE block + RFC-AUDIT/DEFERRED-FINDINGS ledgers:
  `docs/superpowers/plans/2026-06-15-s2-read-model-uniformity-plan.md`.

### RFC-conformance sweep (✅ merged, PR #8) — a NEW post-S2 sub-project
A whole-codebase audit of the protocol surface against the authoritative RFC
text. **Verdict: high overall conformance.** Fixes (plan + ledger:
`docs/superpowers/plans/2026-06-15-rfc-conformance-sweep.md`):
- **F1 (the one real bug)** — `parseHeaderValue` rejected JSON `null` for the four
  single-instance header forms; RFC 8621 §4.1.3 returns `null` for a requested-
  but-absent single-instance header, so the library couldn't parse a conformant
  `Email/get`. All `HeaderValue` arms are now `Opt` (TDD-found).
- **F2** — removed the non-IANA `subscriptions` mailbox role (RFC 8621 §2; flows
  through `mrOther`); fixed the design doc's bogus RFC 5465 citation.
- **F3** — renamed the fixture-only full-object `Email`/`Mailbox.toJson` →
  `toJsonForFixture` (they emit `null`-for-none — non-conformant per §5.1 — and
  have no production caller).
- **F4** — dropped the redundant VacationResponse `id` selector (`vrgkId`).
- **F5** — `docs/design/known-server-deviations.md`: the **six deliberate Postel
  receive-side leniencies** (lenient `newState`, non-base64url server ids,
  optional mail-capability fields, `mayDelete` three-state, shared
  `SubmissionParams`) recorded with RFC cites + rationale. **Kept, not bugs** —
  the client is liberal on receive, strict on send.

---

## 8. THE CRITICAL METHODOLOGY LESSON — the RFC is authoritative; the design docs are fallible

**This is the most important process learning of the campaign. Internalise it.**

The user's standing correction (memory `rfc-is-authoritative`): *"D5, spec §8 etc
are not authoritative. These are specs made by agents which made many mistakes.
Consult the authoritative figure, the RFC docs, to resolve all such questions."*

- **The authoritative source for any protocol-correctness question is the RFC
  text in `docs/rfcs/`** (RFC 8620 core, RFC 8621 mail, RFC 8887 WebSocket, plus
  referenced RFCs 5321/5322/3461/8909). The agent-authored design docs
  (`docs/design/*`, the superpowers specs, and the "D"/"A"/"B"-numbered decisions)
  are fallible and have been WRONG.
- Grounding S2/the sweep in the RFC (not the design docs) caught **five**
  agent-doc errors that would otherwise have shipped:
  - **D5** — every `toJson` emits `null` for `Opt.none`; RFC 8620 §5.1 says a
    `/get` returns only requested properties (absent, never null). P8 fixed Email
    headers; the **broader serde-fidelity defect is DEFERRED** (do NOT blindly
    generalise the omit rule — it needs its own serde audit).
  - **B12** — `parseAccount` silently dropped a read-only account's capabilities;
    RFC 8620 §2 says a capability MUST be listed "if the user may use those
    methods" and `isReadOnly` is a separate axis. **Removed in S2.**
  - **H1b** — S2's capability-arm exposure made raw `JsonNode` vendor arms public,
    which reopens raw construction bypassing the fallible constructor's invariant
    (P15/P16); the H1b lint caught it at the gate. **Resealed (typed arms stay
    public).**
  - **F1, F2** (RFC sweep) — the header-`null` bug and the non-IANA role.
- **Tell every reviewer subagent to validate against the RFC, not the design
  docs.** When a correctness question arises, read `docs/rfcs/`; delegate such
  investigations to subagents to protect context.

---

## 9. What is LEFT

### S3 — Complete the core (clears R2) — NOT STARTED, UNBLOCKED
Add the missing total readers / smart constructors / predicates on the now-final
S2 types (the exact set is a planning estimate — re-derive from `AUDIT.md` +
`docs/design/16`):
- **Readers:** `email.decodedTextBody()`; an `email.leafTextParts()` iterator; an
  `Email.bodyValues` reader that does NOT force the consumer to `import std/tables`;
  `Mailbox.isInbox()` / role predicates (the is-inbox three-idiom friction);
  `MailboxRights` roll-ups (`canRead`/`canWrite`/`canDelete`) over the nine
  independent `may*` bools.
- **Smart constructors:** a plain-text body-part constructor (the building block
  S4's `sendPlainText` consumes); the per-capability preflight sugar
  `requireMail`/`requireSubmission`/`requireVacation` (building on S1's
  `requirePrimaryAccount`, lifting capability checks onto the `JmapError` rail).
- **Helpers:** `byIds()` per-entity get convenience; a `limit` shorthand (could
  fold into S4).
- **DO NOT double-count:** the `FieldEcho` reader the original handoff parked here
  was already delivered by S2.

### S4 — One-shots + easy-path + dissolve quarantine (clears R1, R4) — depends on S3
The `curl_easy_*`/`sqlite3_exec` surface, first-class on the always-on hub:
`connect(url, user, pass)`; `sendPlainText(...)` (hides the blueprint chain + the
two-creation wiring); `queryThenGet`; bare-get single-method one-shots; the
**fail-fast `get` convenience deferred from S1** (open design question: may a
convenience put a `MethodError` on a rail?); a front door for the
**uncopyable-`RequestBuilder`** friction (`addEmailSubmissionAndEmailSet` returns
an uncopyable builder in its Ok arm, so it can't ride `?`/`.lift` today). **Two
decisions need explicit user sign-off before coding:** the fate of
`convenience.nim` (dissolve the P6 quarantine vs keep) and the fail-fast-`get`
design.

### Triage ledger (AUDIT Phase 2) — best done after S4
`examples/jmap-cli/AUDIT.md` still has **~92 findings mechanically marked
`[open]`** (Phase 1 was observe-only). ~13 are already FIXED by S1/S2 (described
in the AUDIT's resolution sections) but not reconciled per-line. **Convert every
`[open]` line → `resolved-Sn | accepted-as-trade-off | filed-as-Cn`**, mapped to
its fixing sub-project, with rationale. Re-bench the CLI against the final S3+S4
deliverables first.

### Deferred findings (parked, out of scope for the current sub-projects)
1. **`NonEmptyIdSeq.toSeq` collides with `std/sequtils.toSeq`** and is inconsistent
   with the sibling `NonEmptySeq[T].asSeq`. Minor; a future public-API rename to
   `.asSeq` would fix it. (Recorded in the S2 plan's DEFERRED FINDINGS.)
2. **D5 — the broad `toJson` null-for-none serde-fidelity defect** (RFC 8620
   §5.1). P8 fixed only Email headers; the general case is a future serde-audit
   sub-project, NOT a blind generalisation.

### Re-bench after each sub-project
The `examples/jmap-cli/` consumer is the P29 instrument; after S3 and S4,
re-exercise it and update `AUDIT.md` / `docs/design/16-…`. Keep imports
public-only (`check-public-only.sh`).

---

## 10. Quality requirements & process (MANDATORY)

### Gates — a sub-project is complete ONLY when BOTH pass
1. **`just ci`** — runs: reuse (SPDX), fmt-check (nph), the full lint battery
   (incl. `lint-public-api`/`lint-type-shapes`/`lint-error-messages`,
   `lint-fallible-ctor-public-arm` = H1b, `lint-sealed-distinct` = H1, the
   internal-boundary/module-path/style lints), `analyse` (nimalyzer — incl. the
   `complexity` ≤10 and `hasdoc` rules), and `test` (the fast suite).
2. **`just clean && just jmap-reset && just test-full`** — in that EXACT order
   (clean → reset live servers → full live suite against Stalwart/James/Cyrus).
   On failure, fix, then **re-run the WHOLE sequence** until "All shards passed".
   *(Per CLAUDE.md, agents normally run `just ci`/`just test` and leave
   `test-full` to the user — but the user has directed agents to run it; confirm.)*

**Lessons from running the gates:**
- `just test` (fast) **skips the files in `tests/testament_skip.txt`** — those run
  only in `test-full`. A skip-listed file (e.g. `tests/protocol/*`, the property/
  stress tests, the live tests) can hide a break that ONLY `test-full` surfaces.
  When a refactor ripples into tests, sweep ALL of `tests/`, not just the fast set.
- nimalyzer's `complexity` (≤10) and `hasdoc` rules run only in `just ci`, NOT in
  `just build`. New per-form branches or undocumented test helpers fail there.
  **Restructure to comply; NEVER suppress a nimalyzer rule.**
- The per-type `{.ruleOff: "objects".}` exemption for a public-field data record
  is the SANCTIONED mechanism (176-use precedent), distinct from suppressing a
  rule like `complexity`. The `objects` rule = `check objects publicfields`.

### Commit format (Linux-kernel style — from CLAUDE.md)
Subject `subsystem: short imperative` ≤75 cols. Body wrapped ~75 cols, explains
**why**. End EVERY commit body with exactly:
```
Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
```
**No other AI/LLM attribution in any git message.** (A PR *body* is GitHub
metadata, not a git message — but the user is strict about attribution; the four
campaign PRs used NO Claude Code footer in the PR body. Confirm if unsure.)

### Coding conventions (CLAUDE.md + `.claude/rules/`)
- **Layers:** L1 types, L2 serde, L3 protocol → `{.push raises: [],
  noSideEffect.}` + `func`-only (no `proc`); L4 transport/client, L5 FFI →
  `{.push raises: [].}`. Every `src/` file has `{.experimental:
  "strictCaseObjects".}` right after the push pragma. (Tests are exempt.)
- **Errors:** Railway-Oriented Programming with vendored `nim-results`
  (`Result[T,E]`, `Opt[T]`, `?`, `valueOr`). Smart constructors return
  `Result[T, ValidationError]`; the public pipeline rail is `JmapResult[T] =
  Result[T, JmapError]`.
- **Style:** `let`/`const` default, `var` only locally; expression-oriented
  (`if`/`case`/`block` as expressions, exhaustive, no catch-all `else` on finite
  enums); `Opt[T]` not `std/options`; prefer `for v in opt`. **British-English**
  comments/docstrings; **comments explain *why*, not *what*** (the `comment-base`
  skill: RFC-section refs only, NO design-doc cross-refs in code comments).
  `--styleCheck:error`.
- **Type safety:** distinct/sealed newtypes for identifiers; sum types over
  bools/bit-flags; **make illegal states unrepresentable** (P15/P16 — enforced by
  H1/H1b and by adversarial review). `strictCaseObjects` rules (combined-arm
  reads, public discriminator preferred, no nested case-in-case) are in
  `.claude/rules/nim-type-safety.md`.
- **NEVER** loosen compiler/analyzer settings, suppress a nimalyzer rule (decompose
  instead), add module-level mutable `var`/globals/global callbacks, add
  `converter`s, or use `{.requiresInit.}` (Tier-B — rejected). Detailed rules:
  `.claude/rules/nim-conventions.md`, `nim-type-safety.md`, `nim-functional-core.md`,
  `nim-ffi-boundary.md`. Skills: `jmap-protocol`, `nim-json-serde`, `testament`,
  `comment-base`.
- One dependency: vendored, patched `nim-results` at `vendor/nim-results`.
  Everything else is Nim stdlib.

### Execution discipline (what carried S0 → the RFC sweep — keep doing it)
- **Branch first** (`api/<sub-project>`); never implement on `main`. **Commit per
  phase, each green** (`just build` per phase keeps `src/` building; tests sweep
  in a later phase; both gates at the end). **A durable on-disk plan with a
  STATE/HANDOFF block per sub-project**, updated as each phase lands. The plan
  STATE + `git log` reconstruct progress after a compaction.
- **Use the superpowers skills:** `brainstorming` (design a sub-project WITH the
  user before coding — HARD GATE: no implementation until the design is approved),
  `writing-plans`, `subagent-driven-development` / `executing-plans`. Get the
  user's approval on each sub-project's design.
- **Use subagents + the Workflow tool** for (a) context economy (offload the test
  sweep, the CLI rewrite, the RFC audit — compiler/oracle as the objective gate)
  and (b) adversarial verification (independent skeptics; the RFC investigations).
  **Always review their diffs + re-run the gate yourself before committing** —
  they catch real things AND occasionally misjudge. Run a TDD test that fails
  first for a real bug fix (F1 did this).
- **Stage explicit paths; NEVER `git add -A`.**
- **Confirm outward-facing actions (push, PR, merge) with the user** before doing
  them. (S2 = PR #7, the RFC sweep = PR #8 — both merged after explicit user
  go-ahead.)

### REUSE / SPDX (a `just ci` gate)
`REUSE.toml` covers `src/**`, `tests/**`, `docs/**` and common extensions.
**`scripts/**` is NOT glob-covered** — new `.nim` there needs an inline two-line
BSD-2-Clause + copyright header. Docs use a CC-BY-4.0 SPDX identifier inside an
HTML comment. Caution: the REUSE linter scans for the SPDX-identifier string
anywhere; a backtick-wrapped SPDX example in markdown prose trips it — wrap such
prose in `<!-- REUSE-IgnoreStart -->` / `<!-- REUSE-IgnoreEnd -->`.

---

## 11. Key file map

- `docs/design/14-Nim-API-Principles.md` — **the 29 principles (the rubric).**
- `docs/design/16-api-from-the-consumers-chair.md` — narrative consumer critique
  (S2-updated).
- `docs/design/known-server-deviations.md` — the RFC-deviation register (RFC sweep
  F5; the 6 kept Postel divergences).
- `docs/rfcs/` — **the authoritative RFC text** (8620, 8621, 8887, …). Consult for
  any protocol-correctness question (§8).
- `examples/jmap-cli/AUDIT.md` — the 92-finding ledger (+ S1 & S2 resolution
  sections). `examples/jmap-cli/` — the P29 consumer bench (imports only
  `jmap_client` [+ `convenience`]; `check-public-only.sh` enforces it).
- **Sub-project plans** (tracked, each with a STATE block):
  `docs/superpowers/plans/2026-06-15-s1-one-error-rail-plan.md`,
  `…-s2-read-model-uniformity-plan.md`, `…-rfc-conformance-sweep.md`. Specs are
  gitignored under `docs/superpowers/specs/`.
- `src/jmap_client.nim` — the public re-export hub (L5 C-ABI exports land here).
- `src/jmap_client/convenience.nim` — opt-in pipeline combinators (P6 dissolution
  candidate, S4).
- `src/jmap_client/internal/` — `types/` (L1: `primitives`, `identifiers`,
  `validation`, `field_echo`, `framework`, `capabilities`,
  `account_capability_schemas`, `session`, `errors`, …), `serialisation/` (L2),
  `protocol.nim` + `protocol/` (L3: `builder`, `dispatch`, `methods`, `entity`,
  `jmap_error`, `preflight`), `transport.nim` + `transport/` (L4), `client.nim`
  (L4), `mail/` (RFC 8621 entities), `push.nim`/`websocket.nim` (deferred stubs).
- `scripts/api_oracle.nim` + `api_probe.nim` — the S0 contract oracle;
  `scripts/freeze_error_messages.nim` — the H15 error-message snapshot generator.
- `tests/wire_contract/{public-api.txt, type-shapes.txt, error-messages.txt}` —
  the frozen contract (oracle-generated). `tests/lint/h1b_*`/`h16_*`/`h17_*`/`h15_*`
  — the lock lints. `tests/testament_skip.txt` — the fast-suite skip list (these
  run only in `test-full`).
- `config.nims` / `jmap_client.nimble` — compiler flags (`--mm:arc`, `strictDefs`,
  `threads:on`, `panics:on`, the `warningAsError` battery incl.
  `UnsafeDefault`/`UnsafeSetLen`).
- `CLAUDE.md` — project instructions (commit format, principles, conventions).
- `/.nim-reference/` — read-only Nim stdlib + compiler + docs.

---

## 12. Current working state (snapshot, 2026-06-16)

- On **`main`** (up to date with `origin/main`, merge `ef8c932`). **S0, S1, S2 and
  the RFC-conformance sweep are ALL merged.** No code changes pending; the merged
  branches (`api/s2-read-model-uniformity`, `api/rfc-conformance-sweep`, etc.)
  still exist on origin — harmless.
- **S3, S4, and the triage ledger have not started.**
- Memories present + current: `api-libcurl-sqlite-refactor` (campaign state —
  marks S0–S2 + RFC sweep merged, S3/S4/triage next), `api-design-only-consumers`
  (the design lens), `rfc-is-authoritative` (the §8 lesson), plus the older
  `api-refactor-section-ab-campaign` (partly superseded).

---

## 13. Immediate next action

The user directs the order, but the dependency chain is **S3 → S4 → triage
ledger** (the RFC sweep is done; deferred findings are parked).

**To start S3 (Complete the core, clears R2):**
1. Re-read §2 (the design lens), §8 (RFC-is-authoritative), §10 (gates/conventions),
   and `docs/design/14-Nim-API-Principles.md`. Skim `examples/jmap-cli/AUDIT.md`
   and `docs/design/16-…` for the open R2 readers/predicates.
2. **Use the `brainstorming` skill to design S3 WITH the user first** (HARD GATE —
   no code until the design is approved). The concrete scope is in §9; confirm the
   exact reader/predicate/constructor set and any design forks via
   `AskUserQuestion`.
3. Then `writing-plans` → `subagent-driven-development`: branch
   `api/s3-complete-the-core` off `main`, a STATE-tracked plan, green-per-phase
   commits, both gates at the end. Ground every protocol question in the RFC
   (§8), not the design docs. Confirm push/PR/merge with the user.

**When in doubt, re-read §2.** Optimise for the future application developer,
comprehensively, no corners cut — libcurl/SQLite, not OpenSSL/libdbus.
