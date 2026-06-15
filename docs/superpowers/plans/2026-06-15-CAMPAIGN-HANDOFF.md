<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# CAMPAIGN HANDOFF — jmap-client API → libcurl/SQLite refactor

> **You are a fresh agent with zero prior context. Read this whole document
> before doing anything.** It is the single canonical orientation: the mission,
> the non-negotiable design lens, the full history, exactly what is done, exactly
> what is left, every quality gate, and the immediate next action. Last updated
> 2026-06-15 after **S1 completed**. The campaign began 2026-06-14.
>
> Companion auto-loaded memories: `api-libcurl-sqlite-refactor` (campaign
> state), `api-design-only-consumers` (the design lens). Per-sub-project plans
> live in `docs/superpowers/plans/`; gitignored specs in
> `docs/superpowers/specs/`.

---

## 0. TL;DR — where we are right now

- **Project:** `jmap-client` — a cross-platform JMAP (RFC 8620 core + RFC 8621
  mail) **email** client library in Nim, designed for eventual FFI use from
  C/C++. (No video player, no web app — it is an email-protocol library.)
- **Mission:** refactor the library's **public API** so it ages like **libcurl
  and SQLite**, not like **OpenSSL or libdbus**. Driven entirely by the needs of
  **future application developers** who will link this library into email
  clients. RFC 8620 + 8621 are implemented; **Layer-5 C FFI, Push (RFC 8620 §7),
  and Blob upload/download are deferred.**
- **Status:** Campaign decomposed into 6 sub-projects (S0–S4 + a triage ledger).
  - **S0 (truthful contract) — ✅ DONE & merged to `main`** (PR #5).
  - **S1 (one error rail, `JmapError`) — ✅ DONE & merged to `main`** (PR #6,
    merge commit `011830b`, 2026-06-15). Both gates were green at merge.
  - **S2 (read-model uniformity) — ⬜ NEXT.** S3, S4, and the triage ledger
    follow.
- **You are on `main`** (up to date with origin, S1 merged). The immediate work
  is **S2** — start it via the `brainstorming` skill and get the user's design
  approval before coding (§13).

---

## 1. The mission (the user's own words — verbatim)

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
> `96cea22ac075686c4487b9ed2b3dbc459c3e765e`.

So: RFC 8620 + 8621 are implemented; L5 FFI, Push, Blob are deferred. The work
is **API design quality**, judged by a real consumer (the `examples/jmap-cli/`
bench), against the **29 API principles**. The resulting public API must follow
the patterns of **libcurl and SQLite** and avoid the failure modes of **OpenSSL
and libdbus**.

---

## 2. THE NON-NEGOTIABLE DESIGN LENS (read twice — overrides any principle on conflict)

This governs **every** design decision in the campaign. Memorise it.

1. **The ONLY design input is the future application developer** who will
   consume this library. Model the API after **libcurl and SQLite**; actively
   avoid the failure modes of **OpenSSL and libdbus**.
2. **Tests are NOT a design input.** Verbatim: *"Tests should not be a factor in
   the API design. Tests can and should be accommodated to by other means."*
   Never justify an API shape with "easier to test" or "stability bought with
   tests" (P2). Never bend the public surface or the source to placate a tool —
   fix the tool/tests instead.
3. **Incumbent callers are NOT constraints.** Verbatim: *"what `convenience.nim`
   or any other current caller happens to use is not a design input; if a current
   caller breaks under the principled cut, that is a finding, not a constraint."*
   `convenience.nim` is itself a **dissolution candidate** (see decision 2 / S4).
4. **There are 0 users. Blast radius does not matter.** Verbatim: *"There are
   currently 0 users of the library. Blast radius doesn't matter. What does matter
   is clean and comprehensive implementation."* Do not preserve backward
   compatibility for its own sake.
5. **Version-agnostic.** The user explicitly does **not** want a 1.0 freeze or
   version gymnastics: *"I want to fix all the issues, don't care about what
   version we are."* Principles framed around "lock before 1.0" (P1) are
   reinterpreted as **"fix everything now, comprehensively."** Do **not** tag
   versions or split work to protect a release.
6. **Quality is paramount; this is a showcase for the user's team.** Exemplary,
   modern, accurate, complete code. *"comprehensively and cohesively applied
   without cutting any corners or leaving any loose ends … done in an exemplary
   fashion and performed to completion."* The user does not care about speed of
   execution or token cost.

When in doubt, ask: **"would libcurl or SQLite do this? Or is this the
OpenSSL/libdbus choice?"**

---

## 3. The 29 API principles (the rubric)

Full authoritative text: **`docs/design/14-Nim-API-Principles.md`** — read it.
It distils lessons from six C libraries (great: libcurl, SQLite, zlib;
cautionary: OpenSSL, c-client/UW-IMAP, libdbus). One-line summaries:

- **P1** Lock the contract; evolve by addition only. *(reinterpreted §2.5:
  version-agnostic; "fix everything now")*
- **P2** Stability bought with tests. *(do NOT use tests as a design driver — §2.2)*
- **P3** Overloading/default args over `_v2` suffix versioning.
- **P4** Pick a scope; defend it (JMAP only — no IMAP/POP/SMTP/contacts/cals).
- **P5** Single public layer; internals are internal.
- **P6** Convenience APIs quarantined from the protocol-fidelity core.
  *(campaign DECISION: DISSOLVE this — decision 2; readers etc. become core.)*
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

Reviewers cite principles by number. The doc also has a "Concrete decisions to
make before 1.0" list (reinterpreted as the action list, version-agnostic).

---

## 4. How things were when the campaign started (2026-06-14)

- RFC 8620 + 8621 implemented; **L5 FFI, Push, Blob deferred**.
- Commit `39e4891` delivered earlier API enhancements; commit `96cea22` added
  the first `examples/jmap-cli/` bench.
- The bench is the P29 consumer: a CLI driving **only the public API**
  (`import jmap_client` [+ `jmap_client/convenience`]) to exercise every
  RFC 8620/8621 entity area against live JMAP servers (Stalwart/James/Cyrus). It
  sends/receives real email. **Its purpose is the audit, not the CLI.**
- The bench produced three artefacts (READ to understand the findings):
  - **`examples/jmap-cli/AUDIT.md`** — the ledger: **92 findings** (≈16
    positives, ≈76 frictions; 6 high / 7 medium). No command was inexpressible
    via the public API. Now carries an **"S1 resolution" section** mapping each
    error-rail finding to its fix.
  - **`docs/design/16-api-from-the-consumers-chair.md`** — narrative critique.
  - **`docs/superpowers/jmap-cli-api-truth.md`** — recon truth sheet (gitignored).

### The 92 findings reduced to SIX root causes (the key synthesis)

- **R1 — No one-shot for the common single-method case.** (bare-get repetition;
  single-email update triple-seal; single-recipient send.) → **S4.**
- **R2 — Missing total readers/constructors on existing types.** (`FieldEcho`
  has no reader; no `decodedTextBody`/`leafTextParts`; `MailboxRights` no
  roll-up; no `byIds`; no `requireMail`/etc.) → **S3.**
- **R3 — Error-rail fragmentation.** Five call-path rails that don't compose. →
  **S1 — ✅ CLEARED.**
- **R4 — The send path has no ergonomic front door.** (4-layer blueprint
  hand-build; misnamed `parsePartIdFromServer`; the misleading
  `addEmailSubmissionAndEmailSet`; the uncopyable-`RequestBuilder`-in-Ok-arm
  friction.) → **S4.** *(Note: S1 fixed the error-rail part; the uncopyable
  builder + one-shots remain.)*
- **R5 — The contract didn't describe the surface.** The snapshot generator was a
  broken text scraper. → **S0 — ✅ CLEARED.**
- **R6 — Read-model unevenness.** Three idioms for the same job (direct fields vs
  accessors vs `Opt`-vs-`FieldEcho`). → **S2.**

---

## 5. The three locked architectural decisions

The user chose the **maximal-toward-the-libcurl/SQLite-ideal** option on each:

1. **One error rail.** Collapse the 5 call-path rails (R3) into a single
   `JmapError` sum type. → **S1 — ✅ DONE.**
2. **One ergonomic core, no quarantine.** SQLite has no convenience module;
   readers/constructors/predicates/one-shots AND one blessed easy-path per
   operation become first-class on the always-on hub. The P6 quarantine
   **dissolves**; `convenience.nim` folds into the core or is kept only for
   honest multi-method compositions. → **S3 (primitives) + S4 (one-shots/
   easy-path/structure).**
3. **One read idiom.** Uniform access across all entity *data records* and one
   optionality model per field (collapse the `Opt`-vs-`FieldEcho` split).
   Recommended pole: **direct public fields for data records**; opaque-handle +
   accessor discipline (P8) only for *stateful* types (`JmapClient`, `Session`,
   `RequestBuilder`, `BuiltRequest`). Reconcile `Thread`'s `lent seq` accessor.
   → **S2.**

---

## 6. The campaign decomposition (6 sub-projects)

Each is its own spec → plan → implement cycle (superpowers brainstorming →
writing-plans → executing-plans). Dependency order:

| # | Sub-project | Clears | Depends on | Status |
|---|---|---|---|---|
| **S0** | **Truthful contract** (compiler-as-library oracle) | R5 | — | ✅ DONE & merged |
| **S1** | **One error rail** (`JmapError`) | R3 | S0 | ✅ DONE & merged (PR #6) |
| **S2** | **Read-model uniformity** | R6 | S0 | ⬜ NEXT |
| **S3** | **Complete the core** (readers/ctors/predicates/`requireMail`) | R2 | S1, S2 | ⬜ |
| **S4** | **One-shots + easy-path + dissolve quarantine** (`connect`, `sendPlainText`, `queryThenGet`, bare-get one-shots, the uncopyable-builder front door) | R1, R4 | S3 | ⬜ |
| — | **Triage ledger** (AUDIT Phase 2: every `[open]` finding → resolve / accept / file, mapped to its sub-project) | all 92 | across all | ⬜ (S1 error-rail findings done) |

---

## 7. What S0 DID (done & merged — summary)

**Problem.** The frozen contract `tests/wire_contract/public-api.txt` (symbol
signatures) + `type-shapes.txt` (type field shapes), generated by a text scraper
and locked by the H16/H17 lints, was a fiction in both directions (≈436
reachable symbols invisible; ≈22 phantom rows; generator and lints shared the
broken resolver, so the lints passed while the contract lied).

**Solution — a compiler-as-library oracle (the modern, faithful mechanism).**
- **`scripts/api_probe.nim`** — a union re-export of both public hubs
  (`import jmap_client; import jmap_client/convenience; export …`).
- **`scripts/api_oracle.nim`** — loads the module graph, runs `sem`, walks
  `modulegraphs.allSyms(graph, probeModule)` (own + re-exported exported symbols,
  by construction = *what `import jmap_client` exposes*). Two modes via the
  `API_ORACLE_MODE` env var: `api` (signatures) and `type-shapes` (object public
  fields via `sfExported`, enums with wire strings, etc.). Strips template
  `` `gensymN `` suffixes.
- **Rewired** `justfile` recipes (`freeze-api`/`freeze-type-shapes`/
  `lint-public-api`/`lint-type-shapes`, via the private `_api-oracle` build) and
  the lints `tests/lint/h16_public_api_snapshot.nim` / `h17_type_shape_snapshot.nim`
  (now diff the committed snapshot vs the oracle's live output, passed as
  `argv[1]`). Retired the old `api_surface.nim` scraper + freeze scripts.

**Build/run the oracle** (the `just freeze-api` / `just freeze-type-shapes`
recipes do this for you after any surface change):
```
NIMPREFIX="$(dirname "$(dirname "$(readlink -f "$(command -v nim)")")")"
nim c --hints:off --warnings:off -d:nimcore --path:"$NIMPREFIX" \
  -o:/tmp/jmap_api_oracle scripts/api_oracle.nim
API_ORACLE_MODE=api /tmp/jmap_api_oracle check --mm:arc --threads:on --panics:on \
  --path:src --path:vendor/nim-results scripts/api_probe.nim
```
The oracle depends on compiler-internal API (`allSyms`, `ifaces`, `sfExported`);
a Nim upgrade must re-verify it. **Merged to `main` (PR #5).**

---

## 8. What S1 DID (done — both gates green, NOT pushed — full detail)

**Goal (P13).** Collapse the **five** fragmented call-path error rails into ONE
`JmapError` sum so the whole `build → send → get` pipeline composes with a single
`?`. Before S1 the rails were `ValidationError`, `seq[ValidationError]`,
`EmailBlueprintErrors`, `ClientError`, and `GetError` — they did not compose
(`send` returned `ClientError`, `get` returned `GetError`, no converter bridged
them, `?` cannot auto-lift), which forced the CLI bench to abandon `?` and
collapse every stage to `Result[T, string]` with a hand-rolled `joinErrs`.

**The four user-approved design decisions** (all the recommended pole):
1. **L1 purity → lift at the boundary.** Pure L1 smart constructors stay
   `Result[T, ValidationError]`; unification happens at the L3/L4 boundary via a
   sanctioned `.lift` + `toJmapError` overloads (`?` can't auto-convert and
   `converter`s are forbidden). NOT by retyping L1.
2. **`get` returns method errors as DATA** on the ok branch via `MethodOutcome[T]`
   (`mokValue` | `mokMethodError`); only library/dispatch faults ride the rail
   (RFC 8620 §3.6.2 — a method error is response data, like a per-id SetError).
   The fail-fast single-method convenience is deferred to **S4**.
3. **A 5th `jeSession` arm** for "expected capability / primary account absent"
   (the `primaryAccount`/`find*` `Opt` misses had no rail home).
4. **Split `jeMisuse` (consumer bug — handle from a different builder) from
   `jeProtocol` (server-response malformed)**, with `jeProtocol` preserving the
   L2 `SerdeViolation`'s RFC-6901 JsonPath — which forces `JmapError` to live in
   **L3** (and `JmapResult` to relocate there with it).

**What shipped (the result):**
- **`src/jmap_client/internal/protocol/jmap_error.nim`** (new, L3): `JmapError`
  — a flat 6-arm sum `{jeValidation | jeTransport | jeRequest | jeSession |
  jeMisuse | jeProtocol}`, each arm one typed payload (sub-types `SessionFault`,
  `Misuse`, `ProtocolFault`). Plus `MethodOutcome[T]`, the per-arm `jmap*`
  constructors, the `toJmapError` lifts + the generic `lift` helper, `message`/`$`,
  and `JmapResult[T] = Result[T, JmapError]`. Flat arms (not a nested
  `ClientError`) for FFI one-enum isomorphism and to dodge `strictCaseObjects`
  Rule 4. `ProtocolFault`'s call id lives **in the variants** — mandatory
  `MethodCallId` on `pfMissingCall`/`pfMalformedError`, optional `decodeCallId`
  only on `pfDecode` (which also serves the call-less envelope/session decode).
- **`JmapResult` relocated** L1 → L3; the five old rails folded in; `ClientError`,
  `GetError`, `EmailBlueprintErrors` **retired**; the lossy `validationToClientError`
  hack and the synthetic `serverFail` `MethodError`s deleted.
- **`classify.nim`** (L4) returns `JmapError` directly (HTTP/JSON → `jeTransport`,
  RFC 7807 → `jeRequest`, envelope decode → unlocalised `jeProtocol`).
- **`get`/`getBoth`/`getAll`** → `Result[MethodOutcome[T], JmapError]`. Compound
  `getBoth` (RFC 8620 §5.4 implicit call) models the implicit as
  `Opt[MethodOutcome[B]]` — extracted only when the primary succeeds (the server
  emits the implicit only on primary success). **This was a real design gap the
  live gate caught and fixed.**
- The 14 accumulating validators now carry `NonEmptySeq[ValidationError]`.
  `requirePrimaryAccount` (new L3 module `protocol/preflight.nim`) seeds the
  `jeSession` arm. `TokenViolation` / `SmtpReplyViolation` interned (removed from
  the public hubs via `export … except …`). `MethodError` / `SetError` remain
  **response data**, never a public rail.
- **`examples/jmap-cli/` rewritten** to thread one `JmapError` end-to-end —
  `joinErrs` + the `Result[T, string]` collapse deleted; `email_send.nim` is a
  clean single-`?` pipeline (the P29 proof). `convenience.nim` needed no rewrite
  (earlier phases moved its `getBoth` to `MethodOutcome`/`JmapError`).
- **Contract regenerated** from the oracle; **~110 test files migrated** (method
  errors asserted as data; `jeMisuse`/`jeProtocol`; `NonEmptySeq`). The
  compile-time surface audits now actively assert the new rail present + the
  retired rails ABSENT.
- **An independent adversarial review** of the keystone returned *"sound — no
  must-fix correctness bug; RFC-faithful, layer-clean, no method/set-error
  leakage."* Its two DDD-strictness findings were resolved (**D2**: moved
  `ProtocolFault`'s call id into the variants) or consciously accepted with
  documentation (**D1**: kept the `Opt` implicit — `getBoth` is its sole producer
  and never emits a contradictory pair).

**Git.** Branch `api/s1-one-error-rail` (13 commits, Linux-kernel style, 154
files, +3773/−2465) **merged to `main` via PR #6** (merge commit `011830b`).
Both gates were green at merge (`just ci` + the full live `test-full` against
Cyrus + Stalwart + James). Spec (gitignored):
`docs/superpowers/specs/2026-06-15-s1-one-error-rail-design.md`.
Plan (tracked, with a STATE header marked DONE):
`docs/superpowers/plans/2026-06-15-s1-one-error-rail-plan.md`.

---

## 9. What is LEFT (the work ahead)

**S1 push/PR/merge — ✅ DONE** (PR #6 merged to `main`, 2026-06-15). No
immediate outward-facing action pending.

**S2 — Read-model uniformity (NEXT).** Settle the final entity *data-record*
shapes: one access idiom (recommend direct public fields for data records;
opaque handles keep accessors), one optionality model per field (collapse the
`Email`/`PartialEmail` `Opt`-vs-`FieldEcho` split). Reconcile `Thread`'s
`lent seq` accessor. **Do this BEFORE S3** so the readers target final shapes.
Clears R6. Independent of S1 (could even predate it; do it now).

**S3 — Complete the core (R2).** Add the missing total readers / smart
constructors / predicates on the now-final types: a `FieldEcho` reader,
`email.decodedTextBody()` / `leafTextParts`, `MailboxRights.canRead/canWrite/
canDelete`, a plain-text body constructor, `byIds` per-entity get helpers, a
limit shorthand, the per-capability preflight sugar
(`requireMail`/`requireSubmission`/`requireVacation`, building on S1's
`requirePrimaryAccount`). Core completion, NOT "convenience."

**S4 — One-shots + easy-path + dissolve quarantine (R1, R4).** Single-method
one-shot combinators; the dispatch-and-extract shorthand; the blessed easy-path
(`connect(url, user, pass)`, `sendPlainText(...)` hiding the blueprint chain and
the two-creation wiring, `queryThenGet`); the **fail-fast `get` convenience**
deferred from S1 (and the decision "may convenience put a `MethodError` on a
rail?"); a front door for the **uncopyable-`RequestBuilder`** friction
(`addEmailSubmissionAndEmailSet` returns an uncopyable builder in its Ok arm, so
it can't ride `?`/`.lift` today). Decide the fate of `convenience.nim`. This is
the `curl_easy_*` / `sqlite3_exec` surface — first-class, documented as the
simple path over the granular lifecycle.

**Triage ledger (AUDIT Phase 2).** Convert every remaining `[open]` line in
`examples/jmap-cli/AUDIT.md` into `resolved | accepted-as-trade-off |
filed-as-Cn`, mapped to the sub-project that fixes it. (The error-rail findings
are already resolved in the S1 ledger section.)

**Re-bench after each sub-project.** The `examples/jmap-cli/` consumer is the P29
instrument; after each sub-project, re-exercise it and update `AUDIT.md` /
`docs/design/16-…`.

---

## 10. Quality requirements & process (MANDATORY)

### Gates — a sub-project is complete ONLY when BOTH pass
1. **`just ci`** — runs: reuse, fmt-check, the lint battery (incl.
   `lint-public-api`, `lint-type-shapes`, `lint-error-messages`,
   `lint-internal-boundary`, …), `analyse` (nimalyzer), `test` (fast suite).
2. **`just clean && just jmap-reset && just test-full`** — in that EXACT order
   (clean artefacts → reset live JMAP servers → full live suite against
   Stalwart/James/Cyrus). If `test-full` fails, fix, then **re-run the WHOLE
   `clean → jmap-reset → test-full` sequence**; repeat until green.

Other commands: `just` (list), `just build`, `just test` (fast suite; **skips the
slow files in `tests/testament_skip.txt`** — those run only in `test-full`, so a
skip-listed file can hide a break that only `test-full` surfaces), `just fmt`
(nph; **`src/` + `tests/` only, NOT `scripts/`**), `just analyse` (nimalyzer;
scans `src` + `tests`, not `scripts`), `just freeze-api` / `freeze-type-shapes`
(regenerate the contract via the S0 oracle after a surface change),
`just jmap-up`/`jmap-status`.

### Commit format (Linux-kernel style — from CLAUDE.md)
Subject `subsystem: short description` ≤75 cols, imperative. Body wrapped ~75
cols, explains **why**. End EVERY commit body with exactly:
```
Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
```
**No other AI/LLM attribution in any git message.** (A PR *body* may carry the
Claude Code footer — GitHub metadata, not a git message — but confirm if unsure;
the user is strict about attribution.)

### Coding conventions (CLAUDE.md + `.claude/rules/`)
- **Layers:** L1 types, L2 serde, L3 protocol → `{.push raises: [],
  noSideEffect.}` + `func`-only (no `proc`); L4 transport/client, L5 FFI →
  `{.push raises: [].}`. Every `src/` file has `{.experimental:
  "strictCaseObjects".}` right after the push pragma. (Tests are exempt.)
- **Errors:** Railway-Oriented Programming with vendored `nim-results`
  (`Result[T,E]`, `Opt[T]`, `?`, `valueOr`). Smart constructors return
  `Result[T, ValidationError]`; the public pipeline rail is now
  `JmapResult[T] = Result[T, JmapError]`.
- **Style:** `let`/`const` default, `var` only locally; expression-oriented
  (`if`/`case`/`block` as expressions, exhaustive, no catch-all `else` on finite
  enums); `Opt[T]` not `std/options`; prefer `for v in opt`. British-English
  comments/docstrings; **comments explain *why*, not *what***. `--styleCheck:error`.
- **Type safety:** distinct newtypes for identifiers; sum types over bools /
  bit-flags; **make illegal states unrepresentable** (the project's #1 DDD
  principle — an adversarial reviewer will and did flag violations even in
  hub-private-constructed types); phantom/builder lifecycle where a precondition
  exists. Case objects need explicit `==`/`$`/`hash` *where used*; `strictCaseObjects`
  Rule details (combined-arm reads, no nested case-in-case) are in
  `.claude/rules/nim-type-safety.md`.
- **Never** loosen compiler/analyzer settings, suppress nimalyzer rules
  (e.g. `ruleOff: "complexity"` — decompose instead), add module-level mutable
  `var`/globals/global callbacks, or add `converter`s. Detailed rules:
  `.claude/rules/nim-conventions.md`, `nim-type-safety.md`,
  `nim-functional-core.md`, `nim-ffi-boundary.md`. Skills: `jmap-protocol`,
  `nim-json-serde`, `testament`, `nim-ffi-boundary`, `comment-base`.
- One dependency: vendored, patched `nim-results` at `vendor/nim-results`.
  Everything else is Nim stdlib.

### Execution discipline (what has worked across S0 + S1 — keep doing it)
- **Durable, on-disk plan with a STATE/HANDOFF header per sub-project**, updated
  as each phase lands. **Commit per phase** — each commit is a git checkpoint
  that survives compaction. **Keep each commit green** (the chosen S1 discipline:
  every phase left all of `src/` building; tests swept in one later phase; both
  gates at the end). The next agent reads the plan STATE + `git log` and resumes.
- **Use the superpowers skills:** `brainstorming` (design a sub-project with the
  user before coding — HARD GATE: no implementation until the design is
  approved), `writing-plans`, `executing-plans`. Get the user's approval on each
  sub-project's design before building. (`AskUserQuestion` is the tool for the
  genuine design forks.)
- **Use subagents** (the `Agent` tool) for (a) **context economy** — offload
  voluminous mechanical work (the test sweep, the CLI rewrite, mechanical
  reader-updates) with the compiler/oracle as the objective gate; and (b)
  **adversarial verification** — an independent skeptic reviewing high-stakes
  changes (the S0 contract diff; the S1 keystone). **Always review their diffs +
  re-run the gate yourself before committing** — they catch real things AND
  occasionally misjudge.
- **Stage explicit paths; NEVER `git add -A`.** (Lesson: `git add -A` once swept
  untracked files into a commit.)
- **Confirm outward-facing actions (push, PR, merge) with the user** before doing
  them.

### REUSE / SPDX (a `just ci` gate)
`REUSE.toml` covers `src/**`, `tests/**`, `docs/**`, and the common extensions.
**`scripts/**` is NOT glob-covered** — new `.nim` files under `scripts/` need an
inline two-line BSD-2-Clause + copyright header. Docs use a CC-BY-4.0 SPDX
identifier inside an HTML comment. **Caution:** the REUSE linter scans for the
SPDX-identifier string anywhere; a backtick-wrapped SPDX example in markdown prose
trips it — wrap such prose in `<!-- REUSE-IgnoreStart -->` / `<!-- REUSE-IgnoreEnd -->`
(as done in `docs/design/14-Nim-API-Principles.md` and §10 here).

---

## 11. Key file map

- `docs/design/14-Nim-API-Principles.md` — **the 29 principles (the rubric).**
- `docs/design/16-api-from-the-consumers-chair.md` — narrative consumer critique.
- `examples/jmap-cli/AUDIT.md` — the 92-finding ledger (+ the S1 resolution section).
- `examples/jmap-cli/` — the P29 consumer bench (CLI + `commands/*` +
  `cli_session.nim`). Imports only `jmap_client` [+ `convenience`];
  `check-public-only.sh` enforces that. **Now threads one `JmapError` rail.**
- `docs/superpowers/jmap-cli-api-truth.md` — recon truth sheet (gitignored).
- `docs/TODO/pre-1.0-api-alignment.md` — pre-existing Section A–H tracker
  (superseded on the 1.0-freeze framing; its Section C maps to R1/R2/R4).
- `src/jmap_client.nim` — the public re-export hub (L5 C-ABI exports land here).
- `src/jmap_client/convenience.nim` — opt-in pipeline combinators (P6 dissolution
  candidate, S4).
- `src/jmap_client/internal/` — `types/` (L1, incl. `errors.nim`,
  `validation.nim`), `serialisation/` (L2), `protocol.nim` + `protocol/` (L3:
  `builder`, `dispatch`, `methods`, `entity`, **`jmap_error` (S1)**,
  **`preflight` (S1)**), `transport.nim` + `transport/` (L4: `classify`),
  `client.nim` (L4), `mail/` (RFC 8621), `push.nim`/`websocket.nim` (deferred
  stubs).
- `scripts/api_oracle.nim` + `api_probe.nim` — the S0 contract oracle;
  `scripts/freeze_error_messages.nim` — the H15 error-message snapshot generator.
- `tests/wire_contract/{public-api.txt, type-shapes.txt, error-messages.txt}` —
  the frozen contract (oracle-generated). `tests/lint/h16_*`/`h17_*`/`h15_*` —
  the lock lints. `tests/testament_skip.txt` — the fast-suite skip list.
- `config.nims` / `jmap_client.nimble` — compiler flags (`--mm:arc`,
  `strictDefs`, `threads:on`, `panics:on`, the `warningAsError` battery).
- `CLAUDE.md` — project instructions (commit format, principles, conventions).
- `/.nim-reference/` — read-only Nim stdlib + compiler + docs.

---

## 12. Current working state (snapshot, 2026-06-15)

- On **`main`**, up to date with `origin/main` (merge commit `011830b`). **S0 and
  S1 are both merged.** Working tree clean. The `api/s1-one-error-rail` branch
  still exists (local + remote) — harmless; may be deleted.
- Memories present: `api-libcurl-sqlite-refactor` (campaign state, marks S1 DONE
  & merged), `api-design-only-consumers` (the design lens), plus the older
  `api-refactor-section-ab-campaign` (partly superseded).

---

## 13. Immediate next action

**Start S2 — read-model uniformity.** You are on `main` with S0 + S1 merged.
Branch first (e.g. `api/s2-read-model-uniformity`); never implement on `main`.
Invoke the `brainstorming` skill and design the final entity *data-record* shapes
**with the user** against the design lens (§2) and P8/P19/decision 3 (direct
public fields for data records; collapse the `Email`/`PartialEmail`
`Opt`-vs-`FieldEcho` split; reconcile `Thread`'s `lent seq`); get the user's
approval, then `writing-plans` → `executing-plans` with per-phase commits and the
two gates (§10). Treat any `convenience.nim`/CLI/test breakage as a **finding to
fix, never a constraint**. Confirm push/PR/merge with the user (outward-facing).

**When in doubt, re-read §2 (the design lens). Optimise for the future
application developer, comprehensively, no corners cut — libcurl/SQLite, not
OpenSSL/libdbus.**
