<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# CAMPAIGN HANDOFF — jmap-client API → libcurl/SQLite refactor (COMPLETE)

> **You are a fresh agent with ZERO prior context. Read this whole document
> before doing anything.** It is the single canonical orientation for the
> campaign as of 2026-06-18, after **ALL SEVEN items — S0, S1, S2, the
> RFC-conformance sweep, S3+E1, S4, and the triage ledger — are merged to `main`.
> THE CAMPAIGN IS COMPLETE.** It supersedes the earlier handoffs
> (`2026-06-15-CAMPAIGN-HANDOFF.md`,
> `2026-06-16-CAMPAIGN-HANDOFF-S4-AND-TRIAGE.md`,
> `2026-06-16-E1-RECONCILE-AND-S3-WRAPUP-HANDOFF.md`) for *current status* — those
> say "S4 is your next job"; **S4 and the triage ledger are both DONE.**
>
> It tells you: what the human is trying to achieve, what this campaign is, how
> things were at the start, exactly what is done, exactly what is left, every
> quality gate, every convention, the non-negotiable design lens, all 29
> principles, the process discipline that carried seven merges, and the immediate
> next action.
>
> **The TRIAGE LEDGER — the campaign's last item — is MERGED** (PR #13, merge
> `57429ff`, 2026-06-18; branch `api/triage`, both gates green, 8 commits).
> It flipped all 90 inline `examples/jmap-cli/AUDIT.md` findings to a disposition
> (56 resolved-S0..S4 / 14 affirmed / 11 accepted / 9 filed), authored the
> missing `## S0 resolution` section, audited Section C of the pre-1.0 tracker
> (C1–C10 reconciled, C11–C22 filed), and landed two clean code fixes (the
> `asSeq` sealed-seq unification + test-hygiene). **With it merged, the entire
> campaign is COMPLETE** — only the Section C parking lot (C11–C22, future
> additive passes) remains, at the human's discretion. Details:
> `docs/superpowers/plans/2026-06-16-triage-ledger-plan.md`. See §6 and §11.
>
> Companion auto-loaded memories (in
> `~/.claude/projects/-workspaces-jmap-client/memory/`):
> `api-libcurl-sqlite-refactor` (campaign state — marks all seven items merged,
> campaign complete), `api-design-only-consumers` (the design lens),
> `rfc-is-authoritative`
> (the methodology lesson — read it). Per-sub-project plans live in
> `docs/superpowers/plans/`; gitignored design specs in `docs/superpowers/specs/`.

---

## 0. TL;DR — where we are right now (2026-06-18)

- **Project:** `jmap-client` — a cross-platform JMAP (RFC 8620 core + RFC 8621
  mail) **email** client library in Nim, designed for eventual FFI use from
  C/C++. A protocol library — no UI, no app. RFC 8620 + 8621 are implemented;
  **Layer-5 C FFI, Push (RFC 8620 §7), and Blob upload/download are deferred**
  campaign-wide.
- **Mission:** refactor the library's **public API** so it ages like **libcurl
  and SQLite**, not like **OpenSSL or libdbus**, driven entirely by the **future
  application developer** who will link this library into an email client.
  (Mission verbatim in §1; the non-negotiable design lens in §2.)
- **Status — ALL SEVEN items DONE & merged to `main`; THE CAMPAIGN IS COMPLETE:**
  - **S0 (truthful contract)** — ✅ merged (PR #5, `73dee1a`). Clears R5.
  - **S1 (one error rail, `JmapError`)** — ✅ merged (PR #6, `011830b`). Clears R3.
  - **S2 (read-model uniformity)** — ✅ merged (PR #7, `1be1514`). Clears R6.
  - **RFC-conformance sweep** — ✅ merged (PR #8, `ef8c932`).
  - **S3 (complete the core) + E1 (capability reconcile)** — ✅ merged (PR #10,
    `266fd80`). Clears R2.
  - **S4 (one-shots + easy-path + dissolve the quarantine)** — ✅ **merged
    (PR #12, merge `a525d80`, 2026-06-16). Clears R1 + R4.** (See §4.6 for what it
    shipped.)
  - **Triage ledger** — ✅ **MERGED (PR #13, merge `57429ff`, 2026-06-18). The
    campaign is COMPLETE.**
- **Root causes (R1–R6, see §4.3): ALL CLEARED.**
- **You are on `main`** (`git checkout main && git pull` first). `main`'s tip is
  the triage merge (PR #13, `57429ff`); `just build` → SuccessX. Every merged
  item passed BOTH gates (`just ci` + the full live `test-full` against
  Stalwart/James/Cyrus).
- **Immediate next action:** NONE — the campaign is COMPLETE. Only the Section C
  parking lot (C11–C22, all future *additive* passes) remains, entirely at the
  human's discretion (§6.2, §11). The deferred-campaign-wide items (Layer-5 C FFI,
  Push, Blob) remain open by design. **No implementation is planned.**

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
> As a way to test the quality of the API ... I built an example CLI app,
> completely separate from the library and trying to just use the public API ...
> The important thing however is not to have a pretty CLI but to document all
> aspects of the public API of the library from the perspective of an application
> developer. ... it made clear that the API is in a horrible state.

**So:** RFC 8620 (JMAP core) + RFC 8621 (JMAP mail) are implemented; **Layer-5 C
FFI, Push, Blob are deferred** campaign-wide. The work is **API-design quality**,
judged by a real consumer (the `examples/jmap-cli/` bench) against the **29 API
principles**. The resulting public API must follow **libcurl and SQLite** and
avoid the failure modes of **OpenSSL, c-client/UW-IMAP, and libdbus**.

---

## 2. THE NON-NEGOTIABLE DESIGN LENS (read twice — overrides any principle on conflict)

The human's own words. They govern **every** decision. When a principle, a test,
a current caller, or your own instinct conflicts with one of these, **the lens
wins.**

1. **The ONLY design input is the future application developer** who will consume
   this library to add JMAP support to an email client. Model the API after
   **libcurl and SQLite**; actively avoid **OpenSSL and libdbus**. When in doubt,
   ask: *"would libcurl or SQLite do this, or is this the OpenSSL/libdbus
   choice?"*
2. **Tests are NOT a design input.** *"Tests should not be a factor in the API
   design. Tests can and should be accommodated to by other means."* Never bend
   an API shape — or the source — to placate a test or a tool; fix the test/tool.
3. **Incumbent callers are NOT constraints.** *"what `convenience.nim` or any
   other current caller happens to use is not a design input; if a current caller
   breaks under the principled cut, that is a finding, not a constraint."*
   (`convenience.nim` was itself dissolved in S4.)
4. **There are 0 users; blast radius does not matter.** *"There are currently 0
   users of the library. Blast radius doesn't matter. What does matter is clean
   and comprehensive implementation."* Do not preserve backward compatibility for
   its own sake.
5. **Version-agnostic.** *"I want to fix all the issues, don't care about what
   version we are."* No 1.0 freeze. Principles framed around "lock before 1.0"
   (P1) are reinterpreted as **"fix everything now, comprehensively."**
6. **Quality is paramount; this is a showcase for the human's team.**
   *"comprehensively and cohesively applied without cutting any corners or leaving
   any loose ends … done in an exemplary fashion and performed to completion …
   Quality of code is of utmost importance."* The human does **not** care about
   speed of execution or token cost. Use subagents and Workflow orchestration
   freely; adversarially verify.

---

## 3. The 29 API principles (the rubric) + the three locked architectural decisions

### 3.1 The 29 principles — one-line summaries
Full authoritative text: **`docs/design/14-Nim-API-Principles.md`** (read it). It
distils six C libraries — great: **libcurl, SQLite, zlib**; cautionary:
**OpenSSL, c-client/UW-IMAP, libdbus**. Reviewers cite principles by number.

- **P1** Lock the contract; evolve by addition only *(reinterpreted: §2.5).*
- **P2** Stability bought with tests *(but tests are NOT a design driver, §2.2).*
- **P3** Overloading / default args over `_v2` suffix versioning.
- **P4** Pick a scope; defend it (JMAP only — no IMAP/POP/SMTP/contacts/calendars).
- **P5** Single public layer; internals are internal.
- **P6** Convenience APIs quarantined from the core *(OVERRIDDEN — S4 dissolved
  the quarantine: the combinators + one-shots are first-class on the always-on
  hub).*
- **P7** Watch the wrap rate (if everyone wraps you, the API is wrong).
- **P8** Opaque handles via private fields + ARC `=destroy`.
- **P9** Max two context types per concept (one handle + one builder).
- **P10** No global state; configuration is a typed value.
- **P11** No global callbacks; per-handle field + context (closure).
- **P12** Memory ownership encoded in the type (`sink`/`lent`/`var`).
- **P13** One error rail (`Result[T, E]`); name every variant *(= S1; S4 added the
  `jeMethod`/`jeSet` arms additively).*
- **P14** No thread-local error queues / last-error globals.
- **P15** Smart constructors return `Result`; raw constructors private.
- **P16** Encode preconditions in types (phantom types, builders, sum types).
- **P17** One configuration surface; one parser; one validator.
- **P18** Sum types over bit-flag soup; named enums over bools.
- **P19** Schema-driven typed records; raw `JsonNode` only for diagnostics/vendor.
- **P20** Add features via additive variants, not new top-level procs.
- **P21** Granular lifecycle via distinct types per phase.
- **P22** Sync-blocking API first; async later via a transport interface.
- **P23** Plan Push/WebSocket as a separate type from day one.
- **P24** Decide the threading invariant explicitly; encode it.
- **P25** License clarity (BSD-2-Clause).
- **P26** Standard build tooling; no per-OS branching.
- **P27** Documentation as succession planning.
- **P28** Long-form first-party narrative documentation.
- **P29** Bench API ergonomics with a real consumer (= the `examples/jmap-cli/`
  bench → `AUDIT.md`).

**P15/P16 are the project's #1 DDD principle in practice — "make illegal states
unrepresentable."** CLAUDE.md restates it: *"Make illegal states unrepresentable.
One source of truth per fact. Booleans are a code smell. Newtype everything that
has meaning."* S4's final adversarial review acted on exactly this — see §4.6.

### 3.2 The three locked architectural decisions (all now realised)
1. **One error rail.** Collapse the 5 call-path rails into one `JmapError` sum (=
   S1). S4 added two **additive** arms — `jeMethod` and `jeSet` — for the
   single-purpose one-shots (§4.6).
2. **One ergonomic core, no quarantine.** SQLite has no convenience module; the
   readers/constructors/predicates AND the one-shots/easy-path AND the pipeline
   combinators are all first-class on the always-on hub. The P6 quarantine
   **dissolved** in S4.
3. **One read idiom.** Uniform access across all entity data records; one
   optionality model per field — reframed in S2: keep BOTH `Opt` and `FieldEcho`
   (the RFC 8620 §5.3 absent-vs-null bit) and unify at the **reader** layer.

---

## 4. The campaign — what it is, how things were, what is done

### 4.1 The project
`jmap-client` is a cross-platform JMAP (RFC 8620 core + RFC 8621 mail) **email**
client library in Nim. One dependency: a vendored, patched `nim-results` at
`vendor/nim-results` (`Result[T,E]`, `Opt[T]`, `?`, `valueOr`); everything else is
Nim stdlib. **Layers:** L1 types, L2 serde, L3 protocol (all pure: `{.push raises:
[], noSideEffect.}` + `func`/`iterator` only); L4 transport/client, L5 FFI
(deferred) — `{.push raises: [].}`. Every `src/` file has `{.experimental:
"strictCaseObjects".}`.

### 4.2 How things were when the campaign started (2026-06-14)
RFC 8620 + 8621 implemented; the public API was "in a horrible state." A CLI
bench (`examples/jmap-cli/`) drives **only the public API** against live
Stalwart/James/Cyrus and produced **`examples/jmap-cli/AUDIT.md`** (the ledger —
92 findings, now 98 inline `[open]` lines after S1/S2/S3/S4 added cross-cutting
ones) and **`docs/design/16-api-from-the-consumers-chair.md`** (narrative
critique). `examples/jmap-cli/check-public-only.sh` enforces public-only imports.

### 4.3 The findings → SIX root causes → ALL CLEARED
- **R1 — No one-shot for the common single-method case** → **S4 ✅.**
- **R2 — Missing total readers/constructors/predicates** → **S3 + E1 ✅.**
- **R3 — Error-rail fragmentation** (five rails) → **S1 ✅.**
- **R4 — The send path has no ergonomic front door** → **S4 ✅.**
- **R5 — The contract snapshot didn't describe the surface** → **S0 ✅.**
- **R6 — Read-model unevenness** (three idioms) → **S2 ✅.**

### 4.4 Sub-project status
| Sub-project | Clears | Status |
|---|---|---|
| **S0** Truthful contract (compiler-as-library oracle) | R5 | ✅ MERGED (PR #5, `73dee1a`) |
| **S1** One error rail (`JmapError`) | R3 | ✅ MERGED (PR #6, `011830b`) |
| **S2** Read-model uniformity | R6 | ✅ MERGED (PR #7, `1be1514`) |
| **RFC-conformance sweep** | — | ✅ MERGED (PR #8, `ef8c932`) |
| **S3** Complete the core **+ E1** | R2 | ✅ MERGED (PR #10, `266fd80`) |
| **S4** One-shots + easy-path + dissolve | R1, R4 | ✅ MERGED (PR #12, `a525d80`) |
| **Triage ledger** | all | ✅ MERGED (PR #13, `57429ff`) |

(There were also docs-only handoff PRs #9 `1517a76` and #11 `de19d04`.)

### 4.5 What S0–S3/E1 delivered (load-bearing detail — read the canonical lessons)
- **S0 (PR #5).** Replaced the broken `api_surface.nim` text scraper with a
  **compiler-as-library oracle** (`scripts/api_oracle.nim` + `api_probe.nim`):
  loads the module graph, runs `sem`, walks `modulegraphs.allSyms` = exactly what
  `import jmap_client` exposes. Drives `just freeze-api`/`freeze-type-shapes` and
  the H16/H17 lints. **Caveat: a Nim upgrade must re-verify the oracle.**
- **S1 (PR #6).** One **flat 6-arm `JmapError` sum** in L3 (`protocol/jmap_error.nim`)
  folded five rails. Pure L1 ctors stay `Result[T, ValidationError]` and lift at
  the L3/L4 boundary via `.lift` + `toJmapError`. `get`/`getBoth`/`getAll` return
  `Result[MethodOutcome[T], JmapError]` — **a server method error is response
  DATA on the ok branch** (`mokValue | mokMethodError`), RFC 8620 §3.6.2, NOT a
  rail fault. `MethodError`/`SetError` stay response data.
- **S2 (PR #7).** Every immutable DATA record reads by **direct public field**;
  accessors survive only on stateful **handles**. Shipped the `FieldEcho` reader
  (`valueOr`/predicates/`items`/`toOpt`); Tier-A newtypes (`NonEmptyIdSeq`,
  `DisplayName`, `ApiUrl`); typed capability arms (raw `JsonNode` sealed). **Lesson:
  Tier-B (`{.requiresInit.}`) was REJECTED under the real warning-as-error flags —
  always verify empirical claims under the project's REAL flags.**
- **RFC sweep (PR #8).** High conformance. F1 (the one real bug): `parseHeaderValue`
  rejected JSON `null` for single-instance headers (RFC 8621 §4.1.3). F5 wrote
  `docs/design/known-server-deviations.md` (the Postel-divergence register).
- **S3 + E1 (PR #10).** Eleven pure additive readers/predicates/constructors
  (`decodedTextBody`, `bodyValue`, `leafTextParts`, `isInbox`, `hasRole`,
  `plainTextBody`, `requireMail`/`requireSubmission`/`requireVacation`, `limit`,
  …). E1 flattened `SessionFault` to a plain `{ capability }` object after a 4-lens
  adversarial review caught a write-only discriminator. **Lesson: when subtraction
  degenerates a sum to one inhabitant, flatten it.**

### 4.6 What S4 delivered (PR #12 — clears R1 + R4; the work you just inherited)
**Nine commits `de19d04..907aace` + a tooling chore `8787a54`. Both gates green.**

- **The one-shot easy-path** — a new **L4 module `src/jmap_client/internal/one_shot.nim`**,
  re-exported by the root hub. All return a **flat `Result[T, JmapError]`**:
  - `connect(url, user, pass)` + a `connect(url, user, pass, transport)` overload —
    folds the endpoint + credential constructors + `initJmapClient`; lazy session.
  - **Bare-gets** returning the full `GetResponse[T]` (keeps `.state`/`.notFound`):
    `getMailboxes`, `getIdentities`, `getEmails`, `getThreads`,
    `getEmailSubmissions`, `getVacationResponse`.
  - **Query-then-gets** → `QueryThenGet[T]{query, get}`: `queryEmails`,
    `queryMailboxes`, `queryEmailSubmissions`.
  - **`sendPlainText(client, accountId, identityId, mailboxes: SendMailboxes,
    message: PlainTextMessage)`** → `Result[SentEmail, JmapError]` — the RFC 8621
    §7.5.1 two-mailbox send (create draft in Drafts with `$draft`, submit, the
    server moves it to Sent on success). **Inputs are swap-proof records**
    (`PlainTextMessage{fromAddr, to, subject, body, cc, bcc}`,
    `SendMailboxes{drafts, sent}`) — the final adversarial review caught that the
    earlier flat-11-positional-param form had same-typed-`Id` adjacency (a
    `draftMailbox`/`sentMailbox` swap compiled and ran the move backwards),
    violating "make illegal states unrepresentable"; the human chose the records.
- **The error-model additions** (in `protocol/jmap_error.nim`):
  - `fulfil(outcome: MethodOutcome[T], methodName: MethodName): Result[T,
    JmapError]` — **public** collapse helper; the engine of every one-shot.
  - **`jeMethod`** arm (`MethodFault{methodName, error: MethodError}`) — a single
    method's §3.6.2 error lifted onto the rail.
  - **`jeSet`** arm (`SetFault{methodName, error: SetError}`) — a single create's
    §5.3 `SetError` lifted onto the rail (symmetric to `jeMethod`; a one-shot has
    no sibling create to protect).
  - **Both arms' constructors are hub-private** (`jmapMethod`/`methodFault`/
    `jmapSet`/`setFault` are in `protocol.nim`'s `export jmap_error except (…)`
    list, like `jmapMisuse`/`jmapProtocol`); the `MethodFault`/`SetFault` **types**,
    their `message`, and `fulfil` stay public for read + collapse. The general
    `get`/`getBoth`/`getAll` keep `MethodOutcome` (batches keep data-not-rail).
- **Structured send-path root-fixes** (not just hidden behind the one-shot):
  - `EmailSubmissionBlueprint.emailId` is now a typed **`IdOrCreationRef`** — no
    more `parseIdFromServer("#" & $cid)` smuggle (RFC 8620 §5.3).
  - One **total `addEmailSubmissionSet(b, account, spec)`** via a smart-constructed
    **`EmailSubmissionSetSpec`** (`parseEmailSubmissionSet`, which moved the §5.3
    onSuccess↔create cross-ref validation in and now accumulates all bad refs),
    **replacing both** the simple `addEmailSubmissionSet` and the misleadingly
    named, fallible `addEmailSubmissionAndEmailSet` — the uncopyable-`RequestBuilder`-in-`Result`
    friction is gone.
  - The RFC 8620 §5.4 implicit handle is now **conditional** — `CompoundHandles.implicit`
    is `Opt[NameBoundHandle[B]]` and **`getBoth` is total**: a not-requested
    implicit reads as `Opt.none`, a requested-but-absent one still faults. Every
    caller extracts uniformly through `getBoth`; the get(primary)-vs-getBoth
    footgun is gone. (`addEmailCopyAndDestroy` always requests its implicit.)
- **The dissolution.** The eight pure pipeline combinators moved from
  `src/jmap_client/convenience.nim` to **`src/jmap_client/internal/mail/combinators.nim`**,
  re-exported through the mail hub. **The public `jmap_client/convenience` module
  path is DELETED**; `import jmap_client` reaches everything. The public symbol set
  was proven byte-identical (relocated, not altered); the H10 internal boundary is
  now *stronger* (a direct import of the relocated module is forbidden).
- **Bench re-bench.** `examples/jmap-cli/` adopts the one-shots (the send command
  239 → 84 lines); `AUDIT.md` gained an "S4 resolution" section; `docs/design/16`
  flips Sending from "wrap it" to "reach for it".
- **Four user-decisions surfaced mid-flight** (via `AskUserQuestion`): full
  dissolve + `jeMethod`; two-mailbox atomic send; uniform `getBoth` (the `Opt`
  implicit handle); the `jeSet` arm; the `sendPlainText` records. **The human owns
  surface-shape decisions** — surface them, don't unilaterally decide them.

---

## 5. THE CRITICAL METHODOLOGY LESSON — the RFC is authoritative; the design docs are fallible

**Internalise this.** Memory `rfc-is-authoritative` (the human's standing
correction): *"These are specs made by agents which made many mistakes. Consult
the authoritative figure, the RFC docs."* **The RFC text in `docs/rfcs/` governs
every protocol-correctness question; the agent-authored design docs
(`docs/design/*`, the superpowers specs, the D/A/B-numbered decisions, even these
handoffs) are fallible and have been WRONG.**

Grounding in the RFC has repeatedly caught real errors: D5 (the broad `toJson`
null-for-none defect, RFC 8620 §5.3 — still **parked**, §6.2); B12 (`parseAccount`
dropped a read-only account's caps); F1 (the header-`null` bug). **S4's own
adversarial Workflow caught one:** a comment cited RFC 8621 §7.5 ¶3 as *mandating*
the conditional implicit Email/set, but §7.5 ¶3's literal text is an
**unconditional MUST** — the conditionality is *observed server behaviour*
(Stalwart/Cyrus/James omit the implicit absent an `onSuccess*` change). It is now
attributed as such and recorded in `docs/design/known-server-deviations.md`.
**Tell every reviewer subagent to validate against the RFC, not the design docs.**

---

## 6. What is LEFT

### 6.1 The triage ledger (AUDIT Phase 2) — ✅ DONE (merged, PR #13)
The campaign's last item. `examples/jmap-cli/AUDIT.md` had **98 inline findings
mechanically marked `[open]`** (Phase 1 was observe-only). The triage flipped
every one to a disposition — `resolved-Sn` / `affirmed` / `accepted-as-trade-off`
/ `filed-as-Cn` — cross-checked against the per-sub-project resolution sections
and (for `resolved-S0`) the verified `public-api.txt` contract, then authored the
once-missing `## S0 resolution` section and audited Section C of the pre-1.0
tracker. **Final tally: 56 resolved / 14 affirmed / 11 accepted / 9 filed** (§11).
It also landed two clean code fixes — the `asSeq` sealed-seq unification and a
test-hygiene pass — each through the full subagent loop, then a 5-lens adversarial
Workflow before both gates. Full executed record: the triage plan
`docs/superpowers/plans/2026-06-16-triage-ledger-plan.md` and the dispositioned
`AUDIT.md`.

### 6.2 The deferred parking lot (filed as C11–C22 — future *additive* passes)
The triage filed these in Section C of `docs/TODO/pre-1.0-api-alignment.md`
(C11–C22). None is freeze-blocking (the campaign is version-agnostic); each is a
future additive pass at the human's discretion:
- **A read-side `EmailLeaf` view type** for `leafTextParts` (P16: `partId`/`blobId`
  sit behind a `case`). Needs a NEW type — out of S3's "no new types" scope.
- **`leafTextParts` / `limit` naming**; the still-public raw `Blueprint*` part
  constructors (a P15 tightening / non-additive removal).
- **D5 — the broad `toJson` null-for-none serde-fidelity defect** (RFC 8620 §5.3).
  Only Email headers fixed so far; needs its OWN serde audit, NOT a blind
  generalisation of the omit rule.
- **`ParsedEmail` body-reader overloads; `htmlBodies()`/`allBodies()` fetch-option
  siblings.**
- **The API gaps S4 surfaced honestly** (recorded in `AUDIT.md`'s S4 section):
  **no Email/set *write* one-shot** (flag/move/vacation-set keep the triple-seal +
  the `Table` `updateResults`), and **no search-snippet one-shot**
  (`addEmailQueryWithSnippets` stays hand-wired). These are the obvious next
  additive combinators if the human wants a "write/snippet one-shots" follow-up —
  but they are NOT in the planned scope.

### 6.3 Explicitly NOT in scope (deferred campaign-wide)
Layer-5 C FFI, Push (RFC 8620 §7), Blob upload/download. Do not start these.

---

## 7. Quality requirements, gates, and conventions (MANDATORY)

### 7.1 The two gates — a unit of work is DONE only when BOTH pass
1. **`just ci`** — reuse (SPDX), fmt-check (nph), the full lint battery (H1/H1b
   sealed-distinct + fallible-ctor; H10 internal-boundary; H11 typed-builder-no-JsonNode;
   H13 module-paths; H15 error-messages; H16 public-api; H17 type-shapes; style;
   isolation), `analyse` (nimalyzer — incl. **`complexity ≤ 10`**, **`hasdoc`**,
   **`caseStatements min 2`**, which fire ONLY here, not in `just build`), and the
   fast `test`.
2. **`just clean && just jmap-reset && just test-full`** — in that EXACT order. It
   spawns **FOUR shards**: a `joinable` shard (the non-live megatest) + one live
   shard per server (`stalwart`/`james`/`cyrus`), each hardlinking
   `tests/integration/live/*.nim` into `tests/integration/live-<name>/` and logging
   to `testresults/test-full/<shard>.log`. **Fail-fast** (first failing shard
   SIGTERMs siblings). Success sentinel: **"All shards passed."** Long-running
   (~10–25 min); run in the **background** and await. **The stdout interleaves only
   one shard's tagged lines — confirm all four via the per-shard logs**
   (`grep -c 'PASS:' testresults/test-full/*.log`; each live shard ≈ 73 PASS,
   joinable ≈ 23). CLAUDE.md says agents normally leave `test-full` to the user —
   but the human has directed agents to run it.

**Gate lessons (internalise):**
- `just test` (fast) **skips `tests/testament_skip.txt`** (property/stress/
  `tests/protocol/*`/live) — those run only in `test-full`. When a refactor ripples
  into tests, **sweep ALL of `tests/`** and standalone-compile touched non-live
  files (`UnusedImport`/`strictDefs` are hard errors there).
- nimalyzer `complexity`/`hasdoc`/`caseStatements min 2` run only in `just ci`.
  **`hasdoc` rejects a docstring TRAILING the `= object` line** — a type docstring
  MUST be on its own `##` line below `= object` (this bit S4; nph will collapse a
  single-line own-line docstring back onto the `= object` line, so make type
  docstrings **two lines**). `caseStatements min 2` forbids a single-arm `case`.
  `tno_asserts_in_src` forbids `doAssert` under `src/` even in `static:`.
- The per-type **`{.ruleOff: "objects".}`** for a public-field DATA record (incl.
  write-side carriers like `PlainTextMessage`/`SendMailboxes`) is the SANCTIONED
  mechanism, distinct from suppressing a rule.
- `just fmt`/`analyse` cover `src/` + `tests/` only, NOT `examples/` — verify the
  CLI by `nim c examples/jmap-cli/jmap_cli.nim` + `check-public-only.sh`, and
  hand-format example edits to nph style.
- After any hand-edit, run `just fmt` before the gate. **Run the gate YOURSELF —
  reviewers and implementers have BOTH claimed green when `analyse` actually
  failed** (the controller's re-run is the objective truth).

### 7.2 Coding conventions (CLAUDE.md + `.claude/rules/`)
- **Layers/purity:** L1–L3 `func`/`iterator` only under `{.push raises: [],
  noSideEffect.}` + `strictCaseObjects`; L4/L5 `{.push raises: [].}`. Smart
  constructors return `Result[T, ValidationError]`; the public rail is
  `JmapResult[T] = Result[T, JmapError]`. `Opt[T]` not `std/options`; `for v in
  opt:`. `.get()` on a `Result` needs an adjacent invariant comment. No catch-all
  `else` on finite enums. NEVER `Table.[]` — use `withValue`/`getOrDefault` (note:
  the read-only `Table.withValue` injects a `let` cursor — `entry`, not `entry[]`).
- **strictCaseObjects:** read a variant field only inside a `case` that proves the
  discriminator (an `if` is not enough). See `.claude/rules/nim-type-safety.md`.
- **NEVER** loosen compiler/analyzer settings, suppress a nimalyzer rule
  (decompose to comply), add global `var`/callbacks, add `converter`s, or use
  `{.requiresInit.}`. Make illegal states unrepresentable; single-value fields are
  a smell.
- **British-English** comments/docstrings that explain *why*, not *what*;
  **RFC-section refs only** in comments — no design-doc/campaign cross-refs (no
  "S4"/"P6"/"decision N"; the `comment-base` skill governs this). Naming a
  toolchain constraint (a nimalyzer rule, a compliance test) IS acceptable
  why-context. Every public symbol **and every test-helper `proc`** needs a `##`
  docstring (`hasdoc` fires over `tests/` too).

### 7.3 Commit format (Linux-kernel style)
Subject `subsystem: short imperative` ≤ 75 cols; body wrapped ~75 cols, explains
**why**. End EVERY commit body with exactly:
```
Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
```
**No other AI/LLM attribution in any git message.** A **PR body carries NO Claude
Code footer.**

### 7.4 Execution discipline
- **Branch first** (`api/<sub-project>` or `api/triage`); **NEVER implement on
  `main`.** **Commit per task, each green** with the plan's STATE block flipped in
  the same commit. **Stage explicit paths; NEVER `git add -A`** (and `git add`
  aborts the whole list if any pathspec doesn't match — e.g. a `git mv`'d old path
  — so list current paths only).
- **Confirm outward-facing actions (push, PR, merge) with the human** before doing
  them. The flow the human uses: push → open PR (no Claude footer) → merge to main
  → switch to main → pull → verify main's tree is byte-identical to the
  gates-green branch tip + ghost-free.
- **REUSE/SPDX:** `REUSE.toml` covers `src/**`/`tests/**`/`docs/**`; `scripts/**`
  is NOT glob-covered (new `.nim` there needs an inline header). A backtick-wrapped
  SPDX example in markdown trips the linter — wrap in `<!-- REUSE-IgnoreStart -->`.

---

## 8. The process discipline that carried seven merges (keep doing it)

- **`superpowers:brainstorming` (HARD GATE)** — design WITH the human before any
  code; present 2–3 approaches; get approval; write the spec to
  `docs/superpowers/specs/` (gitignored). (For the triage ledger, the "design" is
  light — confirm the resolved/accept/file taxonomy and any spawned fix.)
- **`superpowers:writing-plans`** — a durable on-disk plan with a **STATE block**
  and a **ripple-completeness ledger** (every reference, from a fresh `grep` — the
  specs have under-named ripple before).
- **`superpowers:subagent-driven-development`** — per task: (1) a **fresh
  implementer** does the work but **does NOT commit**; (2) you dispatch **two
  reviewers** (spec + quality, parallel, read-only) — tell them the RFC is
  authoritative; (3) **you re-run the gate yourself** (the objective truth); (4)
  **you author the kernel commit** and flip the STATE block in the same commit.
  Note: in this environment `SendMessage` to continue an implementer is
  unavailable — apply a reviewer's narrow, fully-specified fix yourself, then
  re-run the gate.
- **Adversarial verification (the Workflow tool)** — a final multi-lens review of
  the whole diff *before* the gates (RFC / 29-principles / purity / libcurl-SQLite
  lens / completeness), each finding adversarially refuted. **Proven its worth
  twice:** E1 (the write-only discriminator → flatten) and S4 (the `sendPlainText`
  records, the §7.5 ¶3 divergence citation, the stale AUDIT row). Use freely;
  always re-run the objective gate yourself.
- **When a reviewer/Workflow surfaces a decision that changes the public contract
  or overturns an approved spec, put it to the human** (`AskUserQuestion`). S4 did
  this five times. The human owns surface-shape decisions.
- **Compaction-safety** — the on-disk plan STATE block + `git log` + the
  `api-libcurl-sqlite-refactor` memory are the durable record; update them as work
  lands.

---

## 9. Key file map

### 9.1 Handoffs / specs / plans
- **THIS FILE** — current canonical orientation (post-S4). Read first.
- `…-2026-06-16-CAMPAIGN-HANDOFF-S4-AND-TRIAGE.md` — the prior canonical (its
  status is now STALE; trust THIS file). `…-2026-06-15-CAMPAIGN-HANDOFF.md` — older
  umbrella (stale).
- Per-sub-project plans (each with a STATE block): `…-s1-…`, `…-s2-…`,
  `…-rfc-conformance-sweep.md`, `…-s3-complete-the-core-plan.md`,
  `…-s3-capability-resolution-reconcile-plan.md` (E1),
  **`…-2026-06-16-s4-one-shots-easy-path-plan.md`** (S4, all STATE rows ✅).
- Gitignored design specs under `docs/superpowers/specs/` (incl.
  `…-s4-one-shots-easy-path-design.md`).

### 9.2 The rubric, the RFC, the bench
- `docs/design/14-Nim-API-Principles.md` — the 29 principles.
- `docs/design/16-api-from-the-consumers-chair.md` — narrative consumer critique
  (S2/S3/S4-updated).
- `docs/design/known-server-deviations.md` — the Postel-divergence register
  (sweep F5 + the S4 §7.5 ¶3 implicit-Email/set entry).
- **`docs/rfcs/`** — the **authoritative** RFC text (8620, 8621, 8887, 2045,
  5321/5322, …). Consult for any protocol question (§5).
- **`examples/jmap-cli/AUDIT.md`** — the ledger (98 inline `[open]` + the
  S1/S2/S3/S4 resolution sections). **This is the triage input.**
  `examples/jmap-cli/` — the P29 bench; `check-public-only.sh` enforces public-only.

### 9.3 The source tree (post-S4)
- `src/jmap_client.nim` — the public re-export hub (L5 C-ABI exports land here).
- `src/jmap_client/internal/`:
  - `types/` (L1) — primitives, identifiers, validation, field_echo, framework,
    capabilities, session, envelope, errors, collation, methods_enum (re-exported
    via `internal/types.nim`).
  - `serialisation/` (L2) — serde leaves (no public hub).
  - `protocol.nim` + `protocol/` (L3): `builder`, `dispatch` (`get`/`getBoth`/
    `CompoundHandles.implicit: Opt[...]`/`reference`), `methods`, `entity`,
    **`jmap_error`** (the now-8-arm `JmapError` + `MethodOutcome` + `fulfil` +
    `MethodFault`/`SetFault`; `protocol.nim`'s `except` list keeps the arm ctors
    hub-private), `preflight`.
  - `transport.nim` + `transport/` (L4); `client.nim` (L4, `JmapClient`);
    **`one_shot.nim`** (L4 — connect/the bare-gets/the query-then-gets/
    sendPlainText + `QueryThenGet`/`SentEmail`/`PlainTextMessage`/`SendMailboxes`;
    re-exported by root).
  - `mail/` — `email`, `mailbox`, `email_blueprint`, `email_submission`
    (`EmailSubmissionSetSpec`, `emailId: IdOrCreationRef`), `submission_builders`
    (the one total `addEmailSubmissionSet`), **`combinators.nim`** (the relocated
    pipeline combinators), … (re-exported via `mail/types.nim` → `internal/mail.nim`).
  - `push.nim` / `websocket.nim` — deferred stubs.
  - **`convenience.nim` NO LONGER EXISTS** (relocated to `mail/combinators.nim`;
    the public `jmap_client/convenience` path is deleted).

### 9.4 Tooling / config
- `scripts/api_oracle.nim` + `api_probe.nim` — the S0 oracle (`just
  freeze-api`/`freeze-type-shapes`). `scripts/freeze_error_messages.nim` — the H15
  snapshot generator; **the H15 lint `tests/lint/h15_error_message_snapshot.nim`
  inlines the same sample sequence VERBATIM — edit both in lockstep** (currently
  43 samples; `je8`=jeMethod, `je9`=jeSet).
- `tests/wire_contract/{public-api,type-shapes,error-messages,module-paths}.txt` —
  the frozen contract. `tests/lint/{h1*,h10,h11,h13,h15,h16,h17}` — the lock lints.
  `tests/compile/tcompile_a1b_protocol_hub_surface.nim` — the protocol-hub
  presence/absence audit (asserts `MethodFault`/`SetFault` present, `jmapMethod`/
  `methodFault`/`jmapSet`/`setFault` absent). `nimalyzer.cfg` — NEVER relax.
- `config.nims` / `jmap_client.nimble` — `--mm:arc`, `strictDefs`, `panics:on`,
  the `warningAsError` battery. `config.nims` puts `src/` + `vendor/nim-results` on
  the path, so `nim c -r tests/path/file.nim` runs a single test standalone.
- `CLAUDE.md` + `.claude/rules/{nim-conventions,nim-type-safety,nim-functional-core,
  nim-ffi-boundary}.md`. Skills: `comment-base`, `jmap-protocol`, `nim-json-serde`,
  `testament`. `/.nim-reference/` — read-only Nim stdlib + compiler + docs.

---

## 10. Current working state (snapshot, 2026-06-18)

- On **`main`** (up to date with `origin/main`, tip `57429ff` = PR #13). **S0 + S1
  + S2 + the RFC sweep + S3 + E1 + S4 + the triage ledger are ALL merged; the
  campaign is COMPLETE.** Working tree clean. `main`'s tree verified byte-identical
  to the gates-green branch tip `3c32c58`; `just build` → SuccessX.
- **The campaign is COMPLETE — no work remains** beyond the Section C parking lot
  (C11–C22, future *additive* passes, at the human's discretion).
- Memories present + current: `api-libcurl-sqlite-refactor` (marks all seven items
  merged, campaign complete), `api-design-only-consumers`, `rfc-is-authoritative`.

---

## 11. Immediate next action

**The triage ledger is MERGED — the campaign is COMPLETE.** The triage landed on
branch `api/triage` (8 commits, both gates green: `just ci` ✅ + the four-shard
live `test-full` ✅ "All shards passed", stalwart/james/cyrus 73 each + joinable
23, 0 fail) and merged to `main` as **PR #13** (merge `57429ff`, 2026-06-18;
`main` verified byte-identical to the gates-green tip `3c32c58`, ghost-free,
`just build` → SuccessX). It dispositioned all 90 inline `AUDIT.md` findings,
authored the `## S0 resolution` section, audited Section C (C1–C10 reconciled,
C11–C22 filed), and landed the `asSeq` unification + test-hygiene fixes — each
through the full subagent loop, then a 5-lens adversarial Workflow (which caught
and fixed two more `resolved-S2` over-claims, re-filed to C15). Plan + STATE +
ripple ledger: `docs/superpowers/plans/2026-06-16-triage-ledger-plan.md`.

**The campaign is COMPLETE; there is NO planned work left.** The only remaining
items are the Section C parking lot (C11–C22 in
`docs/TODO/pre-1.0-api-alignment.md`) — all future *additive* passes (write/snippet
one-shots, the `EmailLeaf` view type, the D5 serde audit, a query filter/sort
builder, …), entirely at the human's discretion. The deferred-campaign-wide items
(Layer-5 C FFI, Push, Blob) remain open by design.

**When in doubt, re-read §2.** Optimise for the future application developer,
comprehensively, no corners cut, exemplary/showcase quality — **libcurl/SQLite,
not OpenSSL/libdbus.** Would libcurl or SQLite do this?
