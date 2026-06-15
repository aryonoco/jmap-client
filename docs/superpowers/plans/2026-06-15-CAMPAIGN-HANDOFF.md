<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# CAMPAIGN HANDOFF — jmap-client API → libcurl/SQLite refactor

> **You are a fresh agent with zero prior context. Read this whole document
> before doing anything.** It tells you the mission, the non-negotiable design
> lens, the full history, exactly what is done, exactly what is left, every
> quality gate, and the immediate next action. Written 2026-06-15. The campaign
> began 2026-06-14.
>
> Companion memories (auto-loaded each session): `api-libcurl-sqlite-refactor`,
> `api-design-only-consumers`. Per-sub-project plans live in
> `docs/superpowers/plans/`. The S0 plan
> (`2026-06-14-s0-truthful-contract-plan.md`) has a STATE/HANDOFF header of its
> own.

---

## 0. TL;DR — where we are right now

- **Project:** `jmap-client` — a cross-platform JMAP (RFC 8620 core + RFC 8621
  mail) **email** client library in Nim, designed for eventual FFI use from
  C/C++. (No video player, no web app — it is an email-protocol library.)
- **Mission:** refactor the library's **public API** so it ages like libcurl
  and SQLite, not like OpenSSL or libdbus. Driven entirely by the needs of
  **future application developers** who will link this library into email
  clients.
- **Status:** Campaign decomposed into 6 sub-projects (S0–S4 + a triage
  ledger). **S0 is COMPLETE and fully verified.** S1 is the next sub-project.
- **S0 deliverable:** replaced a broken text-scraping public-API contract
  generator with a **compiler-as-library oracle**, so the frozen contract files
  now faithfully describe the consumer-reachable surface.
- **Git:** branch `api/s0-truthful-contract`, 6 clean commits, `just ci` green
  AND `just clean && just jmap-reset && just test-full` green. The **only**
  remaining S0 step is `git push` + open a PR, which is paused awaiting the
  user's explicit go-ahead (it is an outward-facing action). The user was last
  shown a drafted PR title/body and asked to approve the push.

---

## 1. The mission (the user's own words)

The user's initiating prompt, verbatim:

> Note about the project: The layer 5 C FFI is deferred for now and push and
> blob upload/download are also deferred for now. Other than that, I believe I
> have implemented all of RFC 8620 and RFC 8621 here.
>
> Now I'm focused on the project's API from the pov of an application
> developer, a consumer of the library. This project is supposed to be a
> library which other application developers can then use and link to to add
> JMAP support to their email clients, allowing their clients to talk to JMAP
> servers. Libraries like this live or die by their API design.
>
> I defined a set of 29 API Principles for this project to adhere to which are
> defined in `docs/design/14-Nim-API-Principles.md`.
>
> I delivered some of the required API enhancements in git commit
> `39e4891aac531759440fcede26a0d7c2e7c4fae1`.
>
> As a way to test the quality of the API … I built an example CLI app,
> completely separate from the library and trying to just use the public API
> … Send and receive actual email and do all the things which an email client
> is supposed to do. The important thing however is not to have a pretty CLI
> but to document all aspects of the public API … from the perspective of an
> application developer. A first revision of this CLI was built in commit
> `96cea22ac075686c4487b9ed2b3dbc459c3e765e`.

So: RFC 8620 + 8621 are implemented; **Layer 5 C FFI, Push (RFC 8620 §7), and
Blob upload/download are deferred**. The work is *API design quality*, judged by
a real consumer (the `examples/jmap-cli/` bench), against 29 principles.

---

## 2. THE NON-NEGOTIABLE DESIGN LENS (read twice)

This governs **every** design decision in the campaign and **overrides any
principle where they conflict**. Memorise it.

1. **The ONLY design input is the future application developer** who will
   consume this library. Model the API after **libcurl and SQLite**; actively
   avoid the failure modes of **OpenSSL and libdbus**.
2. **Tests are NOT a design input.** "Tests can and should be accommodated to by
   other means." Never justify an API shape with "stability bought with tests"
   (P2) or "easier to test." Never bend the public surface or the source to
   placate a tool (e.g. in S0 we fixed the *contract generator*, never edited a
   `0'u64` literal or dropped an operator to make the tool's life easier).
3. **Incumbent callers are NOT constraints.** What `convenience.nim`, the
   `examples/jmap-cli/` CLI, or any test happens to use is not a design input.
   **If a current caller breaks under the principled cut, that is a FINDING to
   report, not a reason to preserve the old shape.** `convenience.nim` is itself
   a *dissolution candidate* (see S4).
4. **There are 0 users. Blast radius does not matter.** What matters is a
   **clean and comprehensive** implementation. Do not preserve backward
   compatibility for its own sake.
5. **Version-agnostic.** The user explicitly does **not** want a 1.0 freeze or
   any version gymnastics. "I want to fix all the issues, don't care about what
   version we are." So principles framed around "lock before 1.0" (P1) are
   reinterpreted as "fix everything now, comprehensively." Do **not** tag
   versions or split work to protect a release.
6. **Quality is paramount; this is a showcase for the user's team.** Exemplary,
   modern, accurate, complete code. No corners cut, nothing half-baked,
   everything performed to completion. The user does not care about speed of
   execution or token cost.

---

## 3. The 29 API principles (the rubric)

Full authoritative text: **`docs/design/14-Nim-API-Principles.md`** — read it.
It distils lessons from six C libraries (great: libcurl, SQLite, zlib;
cautionary: OpenSSL, c-client/UW-IMAP, libdbus). One-line summaries so you know
what each number means in review:

- **P1** Lock the contract; evolve by addition only. *(reinterpreted: §2.5 —
  version-agnostic; "fix everything now")*
- **P2** Stability bought with tests. *(do NOT use tests as a design driver —
  §2.2)*
- **P3** Overloading/default args over `_v2` suffix versioning.
- **P4** Pick a scope; defend it (JMAP only — no IMAP/POP/SMTP/contacts/cals).
- **P5** Single public layer; internals are internal.
- **P6** Convenience APIs quarantined from the protocol-fidelity core.
  *(the campaign DECISION is to DISSOLVE this — see §6 decision 2; readers etc.
  become core, `convenience.nim` may be dissolved/repurposed.)*
- **P7** Watch the wrap rate (if everyone wraps you, the API is wrong).
- **P8** Opaque handles via private fields + ARC `=destroy`.
- **P9** Max two context types per concept (handle + builder).
- **P10** No global state; configuration is a typed value.
- **P11** No global callbacks; per-handle field + context (closure) pointer.
- **P12** Memory ownership encoded in the type (`sink`/`lent`/`var`).
- **P13** One error rail (`Result[T, E]`); name every variant. *(= S1.)*
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
- **P25** License clarity (BSD-2-Clause) from v0.1.0.
- **P26** Standard build tooling (mise + just + nimble); no per-OS branching.
- **P27** Documentation as succession planning.
- **P28** Long-form first-party narrative documentation.
- **P29** Bench API ergonomics with a real consumer (= the `jmap-cli` bench).

`docs/design/14-Nim-API-Principles.md` also has a "Concrete decisions to make
before 1.0" list and is the rubric reviewers cite by number.

---

## 4. How things were when the campaign started (2026-06-14)

- RFC 8620 + 8621 implemented; **L5 FFI, Push, Blob deferred**.
- Commit `39e4891` delivered earlier API enhancements; commit `96cea22`
  (the base of our work, a merge) added the first `examples/jmap-cli/` bench.
- The bench is the P29 consumer: a thin CLI driving **only the public API**
  (`import jmap_client` [+ `jmap_client/convenience`]) to exercise every
  RFC 8620/8621 entity area against live JMAP servers (Stalwart/James/Cyrus).
  It sends/receives real email. Its purpose is the **audit**, not the CLI.
- The bench produced three artefacts (READ THEM to understand the findings):
  - **`examples/jmap-cli/AUDIT.md`** — the terse ledger: **92 findings**, Phase 1
    "observe-only" (every finding tagged `[open]`; triage into
    resolve/accept/file is a deferred "Phase 2"). ≈16 positives, ≈76 frictions;
    6 high / 7 medium severity flagged. **No command was inexpressible** via the
    public API.
  - **`docs/design/16-api-from-the-consumers-chair.md`** — the narrative
    critique: per-area P7 verdict ("reach for it directly" vs "you'll wrap it").
  - **`docs/superpowers/jmap-cli-api-truth.md`** — a per-area recon "truth
    sheet" (gitignored scratch, but present on disk). Symbol-level ground truth.
- A pre-existing tracker, **`docs/TODO/pre-1.0-api-alignment.md`** (Sections
  A–H, ~118 items), tracks principle alignment. Sections A (freeze surface) and
  B (type-safety) are largely DONE; Section C (consumer ergonomics), D
  (policy), F (verification), H (CI lints) are largely TODO. **This campaign
  supersedes that tracker's 1.0-freeze framing where they conflict** (we are
  version-agnostic), but its Section C items map onto our R1/R2/R4.

### The 92 findings reduce to SIX root causes (this is the key synthesis)

- **R1 — No one-shot for the common single-method case.** Behind: bare-get
  repetition (every read repeats `newBuilder → add*Get → freeze → send → get`),
  the single-email update triple-seal (flag/move), the single-recipient send.
- **R2 — Missing total readers/constructors on existing types.** `FieldEcho`
  has no reader; no `decodedTextBody`/`leafTextParts`; `MailboxRights` has no
  roll-up; no plain-text body constructor; no `byIds`; no limit shorthand; no
  capability pre-flight (`requireMail`). These are arguably *bugs against
  parse-don't-validate*: the library parses once but never shipped the read-once
  accessor.
- **R3 — Error-rail fragmentation.** Five call-path rails that don't compose:
  `ValidationError`, `seq[ValidationError]`, `EmailBlueprintErrors`,
  `ClientError`, `GetError`. No lifts between them; no hub-public `ClientError`
  constructor (so a consumer can't even return on the library's own rail).
- **R4 — The send path has no ergonomic front door.** RFC-faithful but brutal:
  a 4-layer blueprint hand-build, `parsePartIdFromServer` misnamed for send-side
  use, the misleading `addEmailSubmissionAndEmailSet` (does NOT create the
  email), and an untyped `emailId` forward-reference smuggled via
  `parseIdFromServer("#" & cid)`.
- **R5 — The contract didn't describe the surface.** The `public-api.txt` /
  `type-shapes.txt` snapshot generator was a broken text scraper. **S0 FIXED
  THIS.**
- **R6 — Read-model unevenness.** Three idioms for the same job: direct public
  fields (`Mailbox`, `Identity`), accessor funcs (`Thread`), and the
  `Opt`-vs-`FieldEcho` split for the same field (`Email` vs `PartialEmail`).

The decisive slice is **freeze-blocking vs additive** is now moot (version-
agnostic): we fix **all** root causes comprehensively, including the
type-touching ones.

---

## 5. The three locked architectural decisions

The user chose the **maximal-toward-the-libcurl/SQLite-ideal** option on each:

1. **One error rail.** Collapse the 5 call-path rails (R3) into a single
   `JmapError` sum type with named arms (validation / transport / dispatch).
   Add a hub-public constructor so consumers return on it. The whole
   `newBuilder → add* → freeze → send → get` pipeline composes with one `?`.
   `MethodError` / `SetError` stay **response DATA** (RFC-faithful — JMAP
   defines method-level and set-level errors as values inside successful
   responses; like SQLite's `SQLITE_ROW` vs `SQLITE_DONE` row status). SQLite
   has ONE int code; libcurl ONE `CURLcode`. This is the single most
   libcurl/SQLite-defining change available. → **S1.**
2. **One ergonomic core, no quarantine.** SQLite has no convenience module —
   `sqlite3_column_text` (a reader) is on the core; libcurl's easy-path is
   first-class. So readers / smart constructors / predicates / single-method
   one-shots, AND one blessed easy-path per operation (`connect`,
   `sendPlainText`, `queryThenGet`), all become first-class on the always-on
   hub. The P6 quarantine **dissolves**; `convenience.nim` either folds into the
   core or is kept only for honest multi-method pipeline compositions (decided
   in S4). → **S3 (primitives) + S4 (one-shots/easy-path/structure).**
3. **One read idiom.** Uniform access across all entity *data records* and one
   optionality model per field (collapse the `Opt`-vs-`FieldEcho` split).
   Recommended pole: **direct public fields for data records**
   (Mailbox/Email/Identity/Thread/PartialEmail), reserving opaque-handle +
   accessor discipline (P8) for the *stateful* types (`JmapClient`, `Session`,
   `RequestBuilder`, `BuiltRequest`) — mirrors SQLite exactly (opaque handles
   for stateful objects, direct access for the data you pull out). The one
   wrinkle to reconcile is `Thread`'s `lent seq` accessor. → **S2.**

---

## 6. The campaign decomposition (6 sub-projects)

Each is its own spec → plan → implement cycle (the superpowers
brainstorming → writing-plans → executing-plans flow). Dependency order:

| # | Sub-project | Clears | Depends on | Status |
|---|---|---|---|---|
| **S0** | **Truthful contract** | R5 | — | **✅ DONE & verified** |
| **S1** | **One error rail** (`JmapError`) | R3 | S0 | ⬜ NEXT |
| **S2** | **Read-model uniformity** | R6 | S0 | ⬜ |
| **S3** | **Complete the core** (readers/ctors/predicates/`requireMail`) | R2 | S1, S2 | ⬜ |
| **S4** | **One-shots + easy-path + dissolve quarantine** (`connect`, `sendPlainText`, `queryThenGet`, bare-get one-shots) | R1, R4 | S3 | ⬜ |
| — | **Triage ledger** (AUDIT Phase 2: every `[open]` finding → resolve / accept / file-as-Cn, mapped to the sub-project that fixes it) | all 92 | runs across all | ⬜ |

S0 and S1 are independent of each other; S1 is the architectural keystone
(it changes nearly every public return type), so it is the recommended next
step. Build the regression net (S0) first — done — then the keystone.

---

## 7. What S0 DID (complete, in detail)

**Problem.** The frozen contract `tests/wire_contract/public-api.txt` (symbol
signatures) and `type-shapes.txt` (type field shapes), generated by
`scripts/api_surface.nim` (a text scraper) and locked by the H16/H17 lints, was
a **fiction in both directions**:
- **~436 reachable symbols invisible**: a char-literal state machine treated a
  typed integer literal `0'u64` as an unterminated char literal and ran away to
  EOF (swallowing `send`/`freeze`/`newBuilder`/the `EmailUpdateSet` family/…);
  `#` inside comments and string/char literals caused the same; grouped
  `const`/`type`-block members (`egp*`, `kw*`, `roleInbox`, `ResponseHandle`)
  were dropped; and ~212 template-generated operators (`==`/`$`/`hash`/… from
  the `defineSealed*` family) are structurally invisible to any text scrape.
- **~22 phantom rows**: generic template *bodies* were rendered as bogus
  unbound-`T` decls (`func hash (a: T)`).
- The generator and the lints **shared the resolver**, so the lints passed while
  the contract lied — false confidence (the OpenSSL/libdbus failure mode).

**Solution — a compiler-as-library oracle (the modern, faithful mechanism).**
- **`scripts/api_probe.nim`** (new): a union re-export of both public hubs
  (`import jmap_client; import jmap_client/convenience; export …`). In-repo so
  the project's own `config.nims` applies (config faithfulness).
- **`scripts/api_oracle.nim`** (new): loads the module graph, runs `sem`, and
  walks `modulegraphs.allSyms(graph, probeModule)` — which yields **own +
  re-exported** exported symbols because `semdata.exportSym` AND `reexportSym`
  both write the same `ifaces.interf` table `allSyms` iterates. This is, by
  construction, *what `import jmap_client` exposes* — the compiler's own
  definition. Renders two views from the AST: `--mode:api` (signatures, grouped
  by module, operators + const members included, a `## re-exported from
  nim-results` provenance section) and `--mode:type-shapes` (object public
  fields via `sfExported` filter — so private `raw*` fields are excluded — plus
  enum members with wire strings, case scaffolding, proc-type/alias RHS like
  `SendProc`). Mode via the `API_ORACLE_MODE` env var. Strips template
  `` `gensymN `` suffixes for stability.
- **Retired** `scripts/api_surface.nim`, `freeze_public_api.nim`,
  `freeze_type_shapes.nim`.
- **Rewired** `justfile` recipes `freeze-api` / `freeze-type-shapes` /
  `lint-public-api` / `lint-type-shapes` (shared private `_api-oracle` build
  recipe) and `tests/lint/h16_public_api_snapshot.nim` /
  `h17_type_shape_snapshot.nim` (now diff the committed snapshot against the
  oracle's live output, passed as `argv[1]` by the recipe). The lints no longer
  import the scraper.
- **Regenerated** both snapshots as the honest baseline (api +1326/−297, shapes
  +138).

**Build / run the oracle** (for when S1+ need to regenerate the contract after
changing the surface — `just freeze-api` / `just freeze-type-shapes` do this for
you):
```
NIMPREFIX="$(dirname "$(dirname "$(readlink -f "$(command -v nim)")")")"
nim c --hints:off --warnings:off -d:nimcore --path:"$NIMPREFIX" \
  -o:/tmp/jmap_api_oracle scripts/api_oracle.nim
API_ORACLE_MODE=api /tmp/jmap_api_oracle check --mm:arc --threads:on --panics:on \
  --path:src --path:vendor/nim-results scripts/api_probe.nim
```
(`--path:'$nim'` also works — Nim expands `$nim` to its prefix on the command
line; the recipes use that.) The oracle depends on **compiler-internal API**
(`allSyms`, `ifaces`, `sfExported`); Nim is pinned via mise; a Nim upgrade must
re-verify it. The `compiler/` package is available in CI (nimalyzer/`just
analyse` already use `--path:$nim`).

**Verification (all green):** `errorCounter=0`; strict superset of the old
surface (0 real symbols lost — adversarially audited by an independent subagent;
the single removal `fromJson(MailboxChangesResponse)` is a **correctness win**:
the oracle honours `mail.nim`'s `export types except fromJson`, compile-verified
unreachable, which the scraper violated); byte-deterministic; the **negative
control** (add a throwaway `*`-export → H16 now fails and names it → revert →
passes) proves the contract *actually locks* now (the old blind lint could not).
`just ci` green; `just clean && just jmap-reset && just test-full` green.

**Git:** branch `api/s0-truthful-contract`, commits (oldest→newest):
`b6d0666` (spec+plan), `a6882c6` (oracle core), `7a5180f` (api render),
`d83a0ca` (type-shape render), `ca90c99` (atomic switch: rewire + retire +
regen), `05f188d` (record verification). S0 spec (gitignored, on disk):
`docs/superpowers/specs/2026-06-14-s0-truthful-contract-design.md`. S0 plan
(tracked): `docs/superpowers/plans/2026-06-14-s0-truthful-contract-plan.md`.

**Immediate S0 remainder:** `git push -u origin api/s0-truthful-contract` +
`gh pr create` — **paused for the user's go-ahead** (outward-facing). A PR
title/body was drafted and shown to the user; mention in the PR that the
`fromJson(MailboxChangesResponse)` removal is a correctness fix, not an API loss.

---

## 8. What is LEFT (the work ahead)

**S1 — One error rail (next, the keystone).** Design & build `JmapError`, a
single sum type with named arms covering the build + dispatch failure modes
(validation, transport, dispatch/get). Provide a hub-public constructor.
Migrate every public fallible signature so `newBuilder → add* → freeze → send →
get` composes with one `?`. Keep `MethodError`/`SetError` as response data
(RFC-faithful). Expect this to break `convenience.nim`, the CLI, and tests —
those breakages are **findings**, not constraints; fix the callers afterward,
do not preserve the old rails. Touches the previously-"frozen" A12 error surface
— fine, we are version-agnostic. This also makes the eventual L5 C-ABI cleaner
(one enum → one set of C codes, per P13/P14).

**S2 — Read-model uniformity.** Settle the final entity *data-record* shapes:
one access idiom (recommend direct public fields for data records; opaque
handles keep accessors), one optionality model per field (collapse
`Email`/`PartialEmail` `Opt`-vs-`FieldEcho`). Reconcile `Thread`'s `lent seq`
accessor. Do this BEFORE S3 so the readers target final shapes.

**S3 — Complete the core (R2).** Add the missing total readers / smart
constructors / predicates on the now-final types: a `FieldEcho` reader,
`email.decodedTextBody()` / `leafTextParts`, `MailboxRights.canRead/canWrite/
canDelete`, a plain-text body constructor, `byIds` per-entity get helpers, a
limit shorthand, capability pre-flight (`requireMail`/`requireSubmission`/
`requireVacation`), and a hub-public `ClientError`/`JmapError` constructor. These
are core completion, NOT "convenience."

**S4 — One-shots + easy-path + dissolve quarantine (R1, R4).** Single-method
one-shot combinators, a dispatch-and-extract shorthand, and the blessed
easy-path: `connect(url, user, pass)`, `sendPlainText(account, identity, from,
to, subject, body)` (hiding the blueprint chain, the `#`-ref smuggle, the
two-creation wiring, the move ceremony), `queryThenGet`. Decide the fate of
`convenience.nim` (fold into core vs keep for honest pipeline compositions
only). This is the curl_easy / sqlite3_exec surface — first-class, documented as
the simple path over the granular lifecycle.

**Triage ledger (AUDIT Phase 2).** Convert every `[open]` line in
`examples/jmap-cli/AUDIT.md` into `resolved | accepted-as-trade-off |
filed-as-Cn`, each mapped to the sub-project that addresses it. This is the
acceptance checklist that proves comprehensiveness.

**Re-bench after each sub-project.** The `examples/jmap-cli/` consumer is the
P29 instrument; after S1–S4 land, re-exercise it (it will need updating since
the API changes — those updates are how you confirm the new API is better) and
update `AUDIT.md` / `docs/design/16-…`.

---

## 9. Quality requirements & process (MANDATORY)

### Gates — work is complete ONLY when both pass
1. **`just ci`** — runs: `reuse fmt-check lint lint-isolated lint-style
   lint-internal-boundary lint-typed-builder-jsonnode lint-sealed-distinct
   lint-fallible-ctor-public-arm lint-h12-no-test-backdoors lint-module-paths
   lint-error-messages lint-public-api lint-type-shapes analyse test`.
2. **`just clean && just jmap-reset && just test-full`** — in that EXACT order
   (clean build artefacts → reset live JMAP servers → full live suite). If
   `test-full` fails, fix, then re-run the WHOLE `clean → jmap-reset →
   test-full` sequence; repeat until green.

Other useful commands: `just` (list), `just build`, `just test` (fast suite),
`just fmt` (nph; **only `src/` + `tests/`, NOT `scripts/`**), `just analyse`
(nimalyzer; scans `src` + `tests`, not `scripts`), `just freeze-api` /
`freeze-type-shapes` (regenerate the contract via the S0 oracle after a surface
change), `just jmap-up`/`jmap-status`.

### Commit format (Linux-kernel style — from CLAUDE.md)
Subject `subsystem: short description` ≤75 cols, imperative ("add" not "added").
Body wrapped ~75 cols, explains **why**. End EVERY commit body with exactly:
```
Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
```
**No other AI/LLM attribution in any git message.** (A PR *body* may carry the
Claude Code footer — it is GitHub metadata, not a git message — but confirm with
the user if unsure; they are strict about attribution.)

### Coding conventions (CLAUDE.md + `.claude/rules/`)
- **Layers:** L1 types, L2 serde, L3 protocol — `{.push raises: [],
  noSideEffect.}` and `func` only (no `proc`); L4 transport/client, L5 FFI —
  `{.push raises: [].}`. Every `src/` file has `{.experimental:
  "strictCaseObjects".}` right after the push pragma. (Tests are exempt.)
- **Errors:** Railway-Oriented Programming with vendored `nim-results`
  (`Result[T,E]`, `Opt[T]`, `?`, `valueOr`). Smart constructors return
  `Result[T, ValidationError]`; raw distinct/case constructors are private.
  `JmapResult[T] = Result[T, ClientError]` (→ becomes `JmapError` in S1).
- **Style:** `let`/`const` default, `var` only locally when necessary;
  expression-oriented (`if`/`case`/`block` as expressions, exhaustive, no
  catch-all `else` on finite enums); `Opt[T]` not `std/options`; prefer `for v
  in opt`. British-English comments/docstrings; **comments explain *why*, not
  *what*** (the *what* lives in the types). `--styleCheck:error` casing.
- **Type safety:** distinct newtypes for identifiers; sum types over bools /
  bit-flags; make illegal states unrepresentable; phantom types / builder
  lifecycle where a precondition exists.
- **Never** loosen compiler/analyzer settings, suppress nimalyzer rules, or add
  module-level mutable `var`/globals/global callbacks. The detailed rule files:
  `.claude/rules/nim-conventions.md`, `nim-type-safety.md`,
  `nim-functional-core.md`, `nim-ffi-boundary.md`. There are also Skills:
  `jmap-protocol`, `nim-json-serde`, `testament`, `nim-ffi-boundary`,
  `comment-base`.
- One dependency: vendored, patched `nim-results` at `vendor/nim-results`.
  Everything else is Nim stdlib.

### Execution discipline (what has worked; keep doing it)
- **Durable, on-disk plan with a STATE/HANDOFF header per sub-project**; update
  it as each phase lands. **Commit per phase** — each commit is a git checkpoint
  that survives compaction. The next agent reads the plan STATE + `git log` and
  resumes exactly.
- **Use the superpowers skills:** `brainstorming` (design a sub-project before
  coding — HARD GATE: no implementation until the design is approved),
  `writing-plans` (bite-sized plan with verification gates), `executing-plans`
  (per-phase, stop-and-ask on blockers). Get the user's approval on each
  sub-project's design before building.
- **Use subagents** (the `Agent` tool) for (a) **context economy** — offload
  iteration-heavy implementation so the churn stays out of the main context, and
  (b) **adversarial verification** — an independent skeptic reviewing
  high-stakes changes (e.g. the S0 contract diff). Review their output before
  committing.
- **Stage explicit paths; NEVER `git add -A`.** (Lesson: `git add -A` swept two
  pre-existing untracked files into an S0 commit; had to `--amend` them out.)
- Confirm outward-facing actions (push, PR) with the user before doing them.

### REUSE / SPDX (a `just ci` gate)
`REUSE.toml` covers `src/**`, `tests/**`, `docs/**`, `**/*.md`, `**/*.txt`,
`**/*.cfg`, etc. **`scripts/**` is NOT glob-covered** — new `.nim` files under
`scripts/` need an inline `# SPDX-License-Identifier: BSD-2-Clause` +
`# Copyright (c) 2026 Aryan Ameri` header (the oracle/probe have them). Docs use
`<!-- SPDX-License-Identifier: CC-BY-4.0 -->`.

---

## 10. Key file map

- `docs/design/14-Nim-API-Principles.md` — **the 29 principles (the rubric).**
- `docs/design/16-api-from-the-consumers-chair.md` — narrative consumer critique.
- `examples/jmap-cli/AUDIT.md` — **the 92-finding ledger** (Phase-1 observe-only).
- `examples/jmap-cli/` — the P29 consumer bench (CLI + `cli_session.nim`
  connect helper + `commands/*`). Imports only `jmap_client`
  [+ `jmap_client/convenience`]; `check-public-only.sh` enforces that.
- `docs/superpowers/jmap-cli-api-truth.md` — recon truth sheet (gitignored).
- `docs/TODO/pre-1.0-api-alignment.md` — pre-existing Section A–H tracker
  (superseded on the 1.0-freeze framing; Section C maps to R1/R2/R4).
- `src/jmap_client.nim` — the public re-export hub (L5 C-ABI exports land here).
- `src/jmap_client/convenience.nim` — opt-in P6 pipeline combinators
  (dissolution candidate, S4).
- `src/jmap_client/internal/` — `types/` (L1), `serialisation/` (L2),
  `protocol.nim` (L3), `transport.nim` + `client.nim` (L4), `mail/` (RFC 8621),
  `push.nim`/`websocket.nim` (deferred stubs). See CLAUDE.md "Important
  Directories".
- `scripts/api_oracle.nim` + `api_probe.nim` — the S0 contract oracle.
- `tests/wire_contract/{public-api.txt,type-shapes.txt}` — the frozen contract
  (now oracle-generated). `tests/lint/h16_*`, `h17_*` — the lock lints.
- `config.nims` / `jmap_client.nimble` — compiler flags (`--mm:arc`,
  `strictDefs`, `threads:on`, `panics:on`, `floatChecks`, the `warningAsError`
  battery; `styleCheck` enforced per-file via `just lint-style` over `src/`).
- `CLAUDE.md` — project instructions (commit format, principles, conventions).
- `/.nim-reference/` — read-only Nim stdlib + compiler + docs (audit the
  oracle's compiler-API usage here).

---

## 11. Current working state (snapshot, 2026-06-15)

- Branch `api/s0-truthful-contract` checked out, **working tree clean**, 6
  commits ahead of `main`, both gates green.
- In-session task list (ephemeral) had S0 Phases 0–6; Phase 6's only remainder
  is the push+PR awaiting user go-ahead.
- Memories present: `api-libcurl-sqlite-refactor` (campaign),
  `api-design-only-consumers` (the design lens), plus the older
  `api-refactor-section-ab-campaign` (the pre-1.0 tracker, partly superseded).

---

## 12. Immediate next action

1. If the user has approved: `git push -u origin api/s0-truthful-contract` and
   open the S0 PR (draft in the conversation / §7). Mark the
   `fromJson(MailboxChangesResponse)` removal as a correctness fix in the body.
2. Otherwise, or once S0 is merged: start **S1 (one error rail)** — invoke the
   `brainstorming` skill, design `JmapError` against the design lens (§2) and
   P13/P5/P15/P18, get the user's approval, then `writing-plans` →
   `executing-plans` with per-phase commits and the two gates (§9). Treat any
   `convenience.nim`/CLI/test breakage as a finding to fix, never a constraint.

**When in doubt, re-read §2 (the design lens) and ask: "would libcurl or SQLite
do this? Or is this the OpenSSL/libdbus choice?"** Optimise for the future
application developer, comprehensively, no corners cut.
