# Mail Part H Implementation Plan (H1 type-lift completion)

This plan turns the H1 design specification (`docs/design/13-mail-H1-design.md`)
into ordered build steps for the **type-lift completion** of RFC 8621.
Part H1 adds no new RFC surface; it closes the typed-FP lift campaign by
raising every remaining weakly- or stringly-typed surface into a domain
ADT with a single translator at the wire boundary. Five workstreams land
here: `CompoundHandles[A, B]` (design §2), `ChainedHandles[A, B]` +
`addEmailQueryWithSnippets` (§3), purpose-built `EmailQueryThreadChain`
record + `addEmailQueryWithThreads` (§4; no arity-4 generic — one
inhabitant, no parametric law), `ParsedSmtpReply` retiring the
`SmtpReply` distinct string (§5), and the RFC §10 IANA traceability
audit (§6). The clean-refactor grep gate (§9) is enforced in Phase 5.

6 phases, one commit each. Every phase passes `just ci` before
committing. Cross-cutting requirements apply to every step: SPDX header,
`{.push raises: [], noSideEffect.}` for L1/L2 and `{.push raises: [].}`
for L3, `func`-only in L1–L3 (templates permitted per H21),
`Result`/`ValidationError`/`Opt[T]` from nim-results, no `std/options`.
The **clean-refactor invariant** (design §1.3 #8) applies end-to-end: no
`{.deprecated.}` pragma, no `type OldName* = NewName` alias, no proxy
accessor, no `when defined(jmap_legacy_*)` conditional-compile shim, no
`# old:` / `# formerly:` / `# was:` marker, no commented-out block of
the retired shape. The §9.6 grep gate enforces this mechanically in
Phase 5.

H1 is entirely L1–L3. No C ABI (L5) or transport (L4) changes. G2
test-specification material is out of scope per design §8.4 — tests
touched here are limited to fixture migrations forced by field renames
(§2) and assertion-shape migrations forced by the `SmtpReply` retirement
(§5). No new test files appear.

Phase ordering places the cross-cutting field-rename refactor (§2) first
so every later phase lands on the migrated field names; additive chain
builders (§3, §4) follow; the `ParsedSmtpReply` lift (§5) — the largest
interdependent change — lands as a single atomic commit; structural
audits (§9 grep gate, §6 IANA matrix) close the book.

---

## Phase 1: `CompoundHandles[A, B]` collapse (design §2)

Introduces the generic in `dispatch.nim`, migrates the two per-site
compound handle types to type aliases, deletes the two per-site
`getBoth` bodies, renames field accesses from domain vocabulary
(`.copy`/`.destroy`/`.submission`/`.emailSet`) to RFC 8620 §5.4 verbatim
(`.primary`/`.implicit`), and emits compile-time participation gates at
module scope. Wire output is byte-identical (design §2.5).

- **Step 1:** Add `CompoundHandles[A, B]`, `CompoundResults[A, B]`,
  generic `func getBoth[A, B](resp, handles): Result[CompoundResults[A, B], MethodError]`,
  and the `registerCompoundMethod(Primary, Implicit: typedesc)` template
  to `src/jmap_client/dispatch.nim` per design §2.1 and §2.4. Both
  object definitions carry `{.ruleOff: "objects".}` consistent with the
  existing per-site records.

- **Step 2:** Replace the object body of `EmailCopyHandles`/`EmailCopyResults`
  at `src/jmap_client/mail/mail_builders.nim:253-265` with
  `type EmailCopyHandles* = CompoundHandles[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]`
  and the matching `CompoundResults` alias per design §2.2. Delete the
  per-site `getBoth` body at `mail_builders.nim:310-320`; the generic
  subsumes it.

- **Step 3:** Replace the object body of `EmailSubmissionHandles`/`EmailSubmissionResults`
  at `src/jmap_client/mail/email_submission.nim:536-553` with the
  corresponding type aliases per design §2.2. Delete the per-site
  `getBoth` body at `src/jmap_client/mail/submission_builders.nim:127-140`.

- **Step 4:** Emit `registerCompoundMethod` invocations at module scope
  in `src/jmap_client/mail/mail_entities.nim` per design §2.4:
  `registerCompoundMethod(CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem])`
  and `registerCompoundMethod(EmailSubmissionSetResponse, SetResponse[EmailCreatedItem])`.

- **Step 5:** Grep-and-replace retired field names across `src/` and
  `tests/` per design §2.3 migration table: `.copy` → `.primary`,
  `.destroy` → `.implicit`, `.submission` → `.primary`, `.emailSet` →
  `.implicit`. Fixture constructors migrate in the same pass
  (`EmailCopyHandles(copy: ..., destroy: ...)` →
  `EmailCopyHandles(primary: ..., implicit: ...)`). The four expected
  grep queries in design §2.3 must each return zero hits.

### CI gate

Run `just ci` before committing; the wire-byte regression nets enumerated in design §2.5 must stay green.

---

## Phase 2: `ChainedHandles[A, B]` + `addEmailQueryWithSnippets` (design §3)

Introduces the RFC 8620 §3.7 back-reference-chain sibling generic, the
`ResultRefPath` string-backed enum centralising JSON Pointer paths, and
the first chain builder (RFC 8621 §4.10 snippets workflow). Additive —
no existing wire shape touched.

- **Step 6:** Add `ChainedHandles[A, B]`, `ChainedResults[A, B]`,
  overloaded `func getBoth[A, B](resp, handles): Result[ChainedResults[A, B], MethodError]`,
  `registerChainableMethod(Primary: typedesc)` template, and the
  `ResultRefPath` enum (with the `rrpIds = "/ids"` variant) to
  `src/jmap_client/dispatch.nim` per design §3.2, §3.5, §4.4. The
  overloaded `getBoth` is unambiguous because `CompoundHandles` and
  `ChainedHandles` have no structural overlap.

- **Step 7:** Add `addSearchSnippetGetByRef` helper in
  `src/jmap_client/mail/mail_methods.nim` per design §3.3 — sibling of
  the existing literal-ids `addSearchSnippetGet` at lines 193-213;
  accepts a `ResultReference` for `emailIds`. Add the type alias
  `EmailQuerySnippetChain* = ChainedHandles[QueryResponse[Email], SearchSnippetGetResponse]`
  and the builder `addEmailQueryWithSnippets` with mandatory `filter`
  argument (H6; RFC 8621 §5.1 ¶2) returning
  `(RequestBuilder, EmailQuerySnippetChain)`.

- **Step 8:** Emit `registerChainableMethod(QueryResponse[Email])` at
  module scope in `src/jmap_client/mail/mail_entities.nim` per
  design §3.5.

### CI gate

Run `just ci` before committing.

---

## Phase 3: `EmailQueryThreadChain` + `addEmailQueryWithThreads` (design §4)

Purpose-built record for the RFC 8621 §4.10 first-login workflow
encoded spec-verbatim as four back-referenced invocations. No arity-4
generic: the workflow has one inhabitant and no parametric law worth
abstracting over (design §4.1), so domain vocabulary lives at the
record's field level rather than being traded for positional
`first`/`second`/`third`/`fourth` access. Additive — RFC §4.10
example output reproduced byte-for-byte.

- **Step 9:** Extend the `ResultRefPath` enum in
  `src/jmap_client/dispatch.nim` (introduced in Phase 2 with `rrpIds`)
  with `rrpListThreadId = "/list/*/threadId"` and
  `rrpListEmailIds = "/list/*/emailIds"` per design §4.5. No other
  additions to `dispatch.nim` in this phase — per design §4.1 and
  H10, no arity-4 generic machinery (`ChainedHandles4`,
  `ChainedResults4`, parametric `getAll[A, B, C, D]`) is introduced;
  the arity-4 chain has one inhabitant and no parametric law worth
  abstracting over.

- **Step 10:** Add `addEmailGetByRef` and `addThreadGetByRef` helpers to
  `src/jmap_client/mail/mail_builders.nim` per design §4.3 — siblings of
  the existing literal-ids overloads; each accepts a `ResultReference`
  for `ids` (parity with §3's `addSearchSnippetGetByRef`).

- **Step 11:** Add the `DefaultDisplayProperties*: seq[string]`
  module-level const per design §4.4 (nine RFC 8621 §4.10 example
  properties, RFC-cited docstring). Add the purpose-built
  `EmailQueryThreadChain` record per design §4.2 with domain-named
  handle fields — `queryH: ResponseHandle[QueryResponse[Email]]`,
  `threadIdFetchH: ResponseHandle[GetResponse[Email]]`,
  `threadsH: ResponseHandle[GetResponse[Thread]]`,
  `displayH: ResponseHandle[GetResponse[Email]]` — and the matching
  `EmailQueryThreadResults` record with plain domain-named response
  fields (`query`, `threadIdFetch`, `threads`, `display`; the type
  name already conveys "responses", so no suffix is needed per H11).
  Both records carry `{.ruleOff: "objects".}` consistent with the
  codebase convention. Add the monomorphic
  `func getAll(resp: Response, handles: EmailQueryThreadChain): Result[EmailQueryThreadResults, MethodError]`
  in `mail_builders.nim` alongside the builder (NOT in `dispatch.nim`)
  per design §4.2 / H14 — the extractor has no parametric shape to
  share with the dispatch layer, so co-locating it with its builder
  keeps the dispatch layer clean. Add the builder
  `addEmailQueryWithThreads` with full signature per design §4.3
  (`collapseThreads` defaults `true` per H13), returning
  `(RequestBuilder, EmailQueryThreadChain)`. All three back-reference
  paths use `ResultRefPath` variants, not string literals (H16).

### CI gate

Run `just ci` before committing.

---

## Phase 4: `ParsedSmtpReply` lift (design §5)

Largest phase — retires the `SmtpReply` distinct string wholesale,
introduces the fully-decomposed `ParsedSmtpReply` with RFC 3463
enhanced-code structure, migrates the `DeliveryStatus.smtpReply` field
and its serde, and updates consumer call sites. Atomic commit: type
retirement, new machinery, field migration, serde rewrite, and test
assertion migrations must all land together for `just ci` to stay
green. No compat shim of any kind per H17 and §1.3 invariant 8.

- **Step 12:** Retire `type SmtpReply* = distinct string` at
  `src/jmap_client/mail/submission_status.nim:99`, the
  `defineStringDistinctOps(SmtpReply)` invocation at line 109, and the
  existing module-local `SmtpReplyViolation` enum body at lines 111-127
  per design §9.2. Wholesale deletion — no `type SmtpReply* =
  ParsedSmtpReply` alias, no `{.deprecated.}` pragma, no borrowed-ops
  placeholder.

- **Step 13:** Add the four distinct newtypes + enum per design §5.2:
  `type ReplyCode* = distinct uint16`,
  `type StatusCodeClass* = enum sccSuccess = "2", sccTransientFailure = "4", sccPermanentFailure = "5"`,
  `type SubjectCode* = distinct uint16`, `type DetailCode* = distinct uint16`.
  Borrow templates cover `==`, `$`, `hash` per `nim-type-safety.md`
  convention — NOT ordering ops (`<` / `<=`) since ordering is not a
  meaningful domain operation on Reply-codes per design §5.2.

- **Step 14:** Add the `EnhancedStatusCode` object (`klass`, `subject`,
  `detail`) and the `ParsedSmtpReply` object with field ordering
  `replyCode`, `enhanced: Opt[EnhancedStatusCode]`, `text`, `raw` per
  design §5.3. Both carry `{.ruleOff: "objects".}` matching the existing
  `ParsedDeliveredState`/`ParsedDisplayedState` precedent at
  `submission_status.nim:73-80, 89-93`.

- **Step 15:** Reintroduce `type SmtpReplyViolation* = enum` (exported,
  no longer module-local per H25) at the same site (around line 111)
  with 15 variants per design §5.4 — the first 10 identical in name and
  order to the existing 10 (`srEmpty` through `srMultilineFinalHyphen`),
  followed by five new variants (`srEnhancedMalformedTriple`,
  `srEnhancedClassInvalid`, `srEnhancedSubjectOverflow`,
  `srEnhancedDetailOverflow`, `srEnhancedMultilineMismatch`).

- **Step 16:** Convert the existing `func` detectors to exported
  templates per H21 (template inheritance invariant): `detectReplyCodeGrammar`,
  `detectSeparator`, `detectClassDigit`, `detectSubjectInRange`,
  `detectDetailInRange`, `detectEnhancedTriple`, and the generic
  `detectMultilineConsistency` per design §5.5. The multi-line template
  takes a `pick: proc` with explicit `{.noSideEffect, raises: [].}`
  pragma preserving purity through the closure. Add the composite
  detector `func detectParsedSmtpReply(raw): Result[ParsedSmtpReply, SmtpReplyViolation]`
  composing atomics via `?`. Rewrite the single translator
  `func toValidationError(v: SmtpReplyViolation, raw: string): ValidationError`
  exhaustively over all 15 arms per design §5.5; the compiler catches
  missing arms.

- **Step 17:** Replace `parseSmtpReply` at
  `src/jmap_client/mail/submission_status.nim:234-242` — same name,
  new signature `func parseSmtpReply*(raw: string): Result[ParsedSmtpReply, ValidationError]`
  per H17, with ingress line-terminator leniency per design §5.8.
  Delete the deferral docstring line at 239 ("... enhanced
  status codes per RFC 3463) is deferred (G12)."). Add `renderSmtpReply*`
  deterministic inverse emitting canonical LF-terminated wire form per
  design §5.8 (canonicalisation policy: LF terminators, no trailing
  whitespace, `<ReplyCode><SP><text>` on the final line,
  `<ReplyCode><-><text>` on continuation lines).

- **Step 18:** Migrate `DeliveryStatus.smtpReply` at
  `submission_status.nim:248-253` from `smtpReply*: SmtpReply` to
  `smtpReply*: ParsedSmtpReply` per design §5.6. The other two fields
  (`delivered`, `displayed`) are unchanged; their `Parsed*` wrappers
  were the precedent pattern. `DeliveryStatusMap` shape is unchanged.

- **Step 19:** Rewrite `DeliveryStatus.fromJson` and
  `DeliveryStatus.toJson` in
  `src/jmap_client/mail/serde_submission_status.nim` per design §5.7 —
  `fromJson` reads `smtpReply` as a raw string and runs `parseSmtpReply`;
  `toJson` calls `renderSmtpReply` to reconstruct the canonical wire
  form. The old `fromJson` body yielding `SmtpReply` is deleted
  wholesale, not layered over.

- **Step 20:** Migrate consumer call sites. Audit `rg -n 'smtpReply' src/ tests/`
  per design §5.9 — every hit reviewed: `$smtpReply` (distinct-string
  style) migrates to `smtpReply.raw` for diagnostic or
  `renderSmtpReply(smtpReply)` for canonical; `SmtpReply("...")` literal
  comparisons migrate to structural `ParsedSmtpReply(...)` field
  assertions or `parseSmtpReply("...").get()` equality. Add or update
  fixtures in `tests/serde/mail/tserde_submission_status.nim` to pin the
  LF canonicalisation policy per design §5.8 (CRLF ingress → LF
  emission; `raw` preserves ingress bytes). Existing canonical-LF
  fixtures stay unchanged per H24 (wire-byte-identical invariant).

### CI gate

Run `just ci` before committing.

---

## Phase 5: Clean-refactor grep gate verification (design §9)

Structural audit only — no new code. Proves Phases 1 and 4 left zero
residue in source, tests, or prose. Any positive hit on any listed grep
is remediated in-phase before commit.

- **Step 21:** Run the full §9.6 grep gate, in sequence:
  - **Retired symbols** (design §9.6, each → 0 hits):
    `rg -n 'type\s+SmtpReply\b' src/ tests/`,
    `rg -n 'type\s+EmailCopyHandles\*\s*=\s*object' src/ tests/`,
    `rg -n 'type\s+EmailSubmissionHandles\*\s*=\s*object' src/ tests/`.
  - **Retired field accesses** (each → 0 hits):
    `rg -n '\bhandles\.copy\b|\bhandles\.destroy\b' src/ tests/`,
    `rg -n '\bhandles\.submission\b|\bhandles\.emailSet\b' src/ tests/`,
    `rg -n '\bresults\.copy\b|\bresults\.destroy\b' src/ tests/`,
    `rg -n '\bresults\.submission\b|\bresults\.emailSet\b' src/ tests/`.
  - **No deprecation or compat shims**:
    `rg -n '\{\.deprecated' src/ tests/`,
    `rg -n 'when\s+defined\(jmap_legacy' src/ tests/`,
    `rg -n 'parseSmtpReplyStructured|parseSmtpReplyV2|parseSmtpReply2' src/ tests/`.
  - **No stale deferral prose** in the mail subtree:
    `rg -ni 'G12|deferred to H1|TBD|XXX' src/jmap_client/mail/ tests/`,
    `rg -n '# old:|# formerly:|# was:' src/ tests/`.
  - **No commented-out legacy blocks**:
    `rg -n '# *type SmtpReply|# *type EmailCopyHandles|# *func getBoth' src/ tests/`.
  - **§5 field-migration coverage**: `rg -n 'smtpReply' src/ tests/`
    lands only on `ParsedSmtpReply`-typed contexts
    (`DeliveryStatus.smtpReply`, `ParsedSmtpReply.raw`, `parseSmtpReply`,
    `renderSmtpReply`, structural assertions); no residual
    `SmtpReply`-typed (distinct-string) usages.
  - **Design-doc consistency** (design §9.6 final block):
    `rg -n 'SmtpReply\b' docs/design/` lands only on historical /
    retirement-narrative frames.

### CI gate

Run `just ci` before committing.

---

## Phase 6: RFC §10 IANA traceability audit + final verification (design §6)

Structural audit only — no new code. Confirms every file:line cite in
design §6.1–§6.4 still binds the named symbol post-refactor; amends §6
inline if any cite shifted. Final verification commands close the
implementation.

- **Step 22:** Walk design §6.1–§6.4 row-by-row and verify every RFC 8621
  §10 registration still resolves:
  - **§6.1 Capabilities (§10.1–10.3)** — three `CapabilityKind` variants
    (`ckMail`, `ckSubmission`, `ckVacationResponse`), six `MailCapabilities`
    fields, two `SubmissionCapabilities` fields.
  - **§6.2 Keywords (§10.4)** — four `const` bindings (`kwDraft`,
    `kwSeen`, `kwFlagged`, `kwAnswered`); `$recent` intentionally
    absent per RFC §10.4.5 "do not use" scope; non-§10 keywords
    scoped out per design §8.6.
  - **§6.3 Mailbox roles (§10.5)** — ten `MailboxRoleKind` variants plus
    `mrOther` catch-all; only `mrInbox` is an RFC 8621 §10.5.1
    registration, the rest derive from RFC 6154/5258/5465.
  - **§6.4 SetError codes (§10.6)** — twelve `SetErrorType` variants
    from RFC 8621 §10.6 registrations, plus ten RFC 8620 core arms.
  Any file:line cite that shifted is amended inline in design §6 before
  the Phase 6 commit. No code is written in this step.

- **Step 23:** Run the final verification commands in sequence:
  - `just build` — shared library compiles; no new warnings.
  - `just test` — every migrated test (fixture field rename;
    `ParsedSmtpReply` assertion shape; canonical-LF normalisation)
    passes green.
  - `just analyse` — nimalyzer passes without new suppressions.
  - `just fmt-check` — nph formatting unchanged.
  - `just ci` — full pipeline green (reuse + fmt-check + lint +
    analyse + test).
  - Phase 5's §9.6 grep gate commands re-run; every retired-symbol and
    retired-field grep still returns zero hits.

### CI gate

Run `just ci` before committing. Steps 22 and 23 are prerequisites for
the Phase 6 commit — a failing verification command or a shifted §6
cite blocks the commit just like a test failure.

---

*End of Part H (H1 source-side) implementation plan.*
