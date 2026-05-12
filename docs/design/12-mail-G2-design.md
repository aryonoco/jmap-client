# RFC 8621 JMAP Mail — Design G2: EmailSubmission — Test Specification

Companion test specification for [`12-mail-G1-design.md`](./12-mail-G1-design.md).
The section number below is kept at `8` so cross-references from G1
(`(G2, G3)`, `(G21)`, `(G27)`, the Decision Traceability Matrix) remain
valid without renumbering. See G1 for the full context (type surface,
phantom-state indexing, cross-entity compound builder, Decision
Traceability Matrix).

This document is a living artefact: it reflects the implementation as
the source of truth. Where the test surface refines or sharpens the
type surface that G1 prose sketches, the refinement is documented
inline in the relevant section.

---

## 8. Test Specification

### 8.1. Testing strategy

Part G mirrors Parts E and F's test-category shape, calibrated to the
surface G1 actually introduces:

1. **Unit** — per-type smart-constructor invariants and serde round-trip
   for every new type. Includes embedded `assertNotCompiles` scenarios
   where a **phantom-type invariant** (G2/G3) or a **Pattern A seal**
   (G38) is load-bearing — the two places in G1 where the type system
   enforces a rule that runtime cannot.
2. **Serde** — `toJson`/`fromJson` output shape per field, per variant,
   per RFC constraint, plus the typed-update → wire `PatchObject`
   translation (the single-variant `esuSetUndoStatusToCanceled` →
   `{"undoStatus": "canceled"}` pin).
3. **Property-based** — a single `tprop_mail_g.nim` file covering nine
   property groups (§8.2.1) focused on the surface areas G1 uniquely
   introduces: RFC 5321 Mailbox grammar totality, strict/lenient
   relationship, `SubmissionParamKey` identity algebra,
   `AnyEmailSubmission` parse-and-dispatch (the existential wrapper is
   `fromJson`-only, so the property is one-way rather than a round-
   trip), `ParsedDeliveredState` raw-backing preservation, and
   `parseSmtpReply` Reply-code digit boundary.
4. **Adversarial** — a single `tadversarial_mail_g.nim` file covering
   malformed `Envelope` and `SubmissionParam` wire shapes,
   `ParsedSmtpReply` grammar violations, wild `undoStatus` dispatch
   values, cross-entity coherence for
   `getBoth(EmailSubmissionHandles)`, and the scale-tier invariants
   (§8.12). Does NOT re-cover generic JSON-structural attacks (BOM,
   NaN, deep nesting, duplicate keys, cast-bypass) —
   `tests/stress/tadversarial_mail_f.nim` already exercises the
   `std/json` boundary and G1 introduces no new parser pathway; the
   adversarial file references F by name and inherits the coverage.
5. **Compile-time reachability** —
   `tests/compile/tcompile_mail_g_public_surface.nim` (159 lines)
   proves every new public symbol is reachable through the top-level
   `jmap_client` re-export chain. 99 `declared()` assertions plus one
   runtime `doAssert` anchor (`$mnEmailSubmissionSet ==
   "EmailSubmission/set"`). See §8.2.2 for the authoritative symbol
   list.

**Deliberately absent** (carry forward as negative commitments):

- No replica of F2's RFC 6901 escape bijectivity property. G1 adds no
  new JSON-Pointer escape sites — the submission serde goes through the
  same `jsonPointerEscape` helper F1 property-tests. Property group D
  in `tests/property/tprop_mail_f.nim` is the authoritative pin;
  referencing by name is correct, re-running is duplication.
- No replica of F2's JSON-structural attack suite (BOM prefix, NaN /
  Infinity literals, duplicate keys, deep nesting, 1 MB strings,
  cast-bypass). G1 introduces no new `std/json` pathway; the existing
  `tadversarial_mail_f.nim` blocks apply transitively to every decode
  surface, including the G1 response types.
- No conflict-pair classification matrix (F2 §8.7 analogue).
  `EmailSubmissionUpdate` has exactly one variant
  (`esuSetUndoStatusToCanceled`, per G16). There is no pair to
  classify.
- No `moveToMailbox ≡ setMailboxIds` equivalence property. G1 has no
  analogous equivalence partner for `cancelUpdate` — it is the only
  typed transition helper.

**File-naming note.** Part G mirrors Part F's part-lettered convention
for the three cross-cutting test files: `tprop_mail_g.nim`,
`tcompile_mail_g_public_surface.nim`, `tadversarial_mail_g.nim`. Part E
adversarial is `tests/stress/tadversarial_blueprint.nim` (per-concept);
the stabilised convention from Parts F and G onwards is
`*_mail_<letter>.nim` when the file spans multiple types within the
part.

**Test-idiom note.** The test style across every new file in this
part is `block <name>:` plus `assertOk` / `assertErr` / `assertEq`
/ `assertLen` / `assertSvKind` / `assertSvPath` from
`tests/massertions.nim`, plus raw `doAssert` for inline probes. No
`std/unittest` `test "name":` blocks, no `suite` wrappers. The
canonical precedents for the style are
`tests/unit/mail/temail_submission_blueprint.nim` and
`tests/unit/mail/tonsuccess_extras.nim`. Prescriptions in §8.3 and
§8.4 below name `block` identifiers directly, not unittest-style
titles.

Test-infrastructure additions (§8.9) follow Part E's 7-step fixture
protocol (`tests/mfixtures.nim:7-14`) and naming convention (`make<Type>`
minimal / `makeFull<Type>` populated). **No new test-support modules are
introduced**: submission factories and equality helpers land in
`mfixtures.nim` alongside `setErrorEq` (`mfixtures.nim:717`) and the
`make*Blueprint` family; generators land in `mproperty.nim` alongside
`genEmailBlueprint`. Fragmenting the support layer for one feature is
explicitly disallowed — this matches F2 §8.6's stance.

**Implementation reality — supplementary types and helpers.**

Five places where the implementation introduces type-level structure
beyond what a bare reading of G1 prose would suggest. Tests calibrate
against the code shapes below.

1. **`NonEmptyOnSuccessUpdateEmail` / `NonEmptyOnSuccessDestroyEmail`.**
   The implementation (`mail/email_submission.nim`) wraps the
   `onSuccessUpdateEmail` and `onSuccessDestroyEmail` payloads in two
   distinct-type non-empty containers: `distinct Table[IdOrCreationRef,
   EmailUpdateSet]` and `distinct seq[IdOrCreationRef]`. Construction
   is gated by `parseNonEmptyOnSuccessUpdateEmail`
   (`email_submission.nim:556`) and `parseNonEmptyOnSuccessDestroyEmail`
   (`email_submission.nim:577`). Empty-input rejection produces
   `"must contain at least one entry"` (`email_submission.nim:567,586`)
   and duplicate-key/element rejection produces
   `"duplicate id or creation reference"` (`email_submission.nim:568,587`).
   Those strings are locked in §8.3's error-rail table and must not be
   re-invented in new blocks.
2. **Compile test has 99 `declared()` assertions plus one runtime
   anchor.** `tcompile_mail_g_public_surface.nim` covers 45 types,
   49 functions, and 5 enum-value anchors (14 smart constructors /
   parsers, 2 server-side infallible parsers, 12 typed parameter
   constructors, 11 infallible ctors + phantom-boundary helpers, 2
   domain helpers, 4 onSuccess NonEmpty extras [2 types + 2 parsers],
   6 L3 method builders, 5 method-enum route variants), plus 1 runtime
   `doAssert $mnEmailSubmissionSet == "EmailSubmission/set"` anchor.
   §8.2.2 enumerates the full list.
3. **`toAny` phantom-boundary helper.** `AnyEmailSubmission` construction
   from a phantom-typed `EmailSubmission[S]` flows through a `toAny`
   family (three overloads, one per phantom instantiation) exported via
   `email_submission.nim:63-73`. The compile test pins its presence at
   line 120. Tests that construct `AnyEmailSubmission` from
   `EmailSubmission[S]` exercise `toAny(...)` rather than brace
   literals — mirrors the codebase's general "constructors are
   privileges" principle.
4. **`AnyEmailSubmission` Pattern A sealing.** The branch fields of
   the existential wrapper are module-private
   (`rawPending`/`rawFinal`/`rawCanceled`, `email_submission.nim:55-61`)
   and external readers use the three `asPending`/`asFinal`/`asCanceled`
   accessors (`email_submission.nim:103-128`), each returning
   `Opt[EmailSubmission[S]]`. The sealing makes wrong-branch access
   unrepresentable at the API layer — the runtime `FieldDefect` path
   is unreachable from external code, which matters because under
   `--panics:on` (project default, `config.nims:24`) `FieldDefect`
   is fatal and cannot be caught. Tests that need the underlying
   `EmailSubmission[S]` use the accessor + `Opt` pattern
   (`for s in a.asPending(): ...` or `a.asPending().get()` after a
   state check), never the `raw*` fields. Serde `fromJson` constructs
   via `toAny(sub)` — there is no brace-literal construction of
   `AnyEmailSubmission` outside its defining module. Item 3's
   principle ("constructors are privileges") applies with equal force
   to readers: accessors are the reading privilege.
5. **`ParsedSmtpReply` decomposition.** The SMTP-reply payload is
   carried as `ParsedSmtpReply = object` (`submission_status.nim:153-161`)
   with four fields: `replyCode: ReplyCode` (the RFC 5321 §4.2.3
   numeric code, `distinct uint16`), `enhanced: Opt[EnhancedStatusCode]`
   (the RFC 3463 §2 `class.subject.detail` triple, when present on
   the final line), `text: string` (the assembled textstring with
   enhanced-code prefix stripped), and `raw: string` (the verbatim
   ingress bytes preserved for diagnostic round-trip and the H24
   canonicalisation contract). The companion `renderSmtpReply`
   function emits the canonical LF-terminated form, which is not
   byte-equal to `raw` when ingress used CRLF.
   `parseSmtpReply` returns `Result[ParsedSmtpReply, ValidationError]`;
   the closed `SmtpReplyViolation` enum
   (`submission_status.nim:163-188`) carries 15 variants (10 surface
   grammar + 5 RFC 3463 enhanced-status-code), each translated to
   `ValidationError` at the wire boundary by `toValidationError`
   (`submission_status.nim:190-229`). The supporting types
   `ReplyCode`, `StatusCodeClass`, `SubjectCode`, `DetailCode`, and
   `EnhancedStatusCode` are all module-public.

---

### 8.2. Part-lettered test files

Following Parts E and F's convention, the lettered-by-part files cover
test concerns whose scope spans multiple types within the Part.

**Cross-cutting test files:**

| File | Description |
|------|-------------|
| `tests/property/tprop_mail_g.nim` | All nine property groups in §8.2.1 land with canonical block names `propRFC5321MailboxTotality` (line 54), `propRFC5321MailboxStrictLenientSuperset` (83), `propSubmissionParamsInsertionOrderRoundTrip` (130), `propSubmissionParamKeyIdentity` (154), `propAnyEmailSubmissionStateDispatch` (185), `propCancelUpdateKindInvariant` (239), `propNonEmptyEmailSubmissionUpdatesDuplicateId` (259), `propParsedDeliveredStateRawBackingRoundTrip` (306), `propParseSmtpReplyDigitBoundary` (358). Registered in `tests/testament_skip.txt` (runs under `just test-full`, not `just test`). |
| `tests/compile/tcompile_mail_g_public_surface.nim` | 99 `declared()` assertions plus one runtime anchor covering every G1 public symbol. See §8.2.2. |
| `tests/stress/tadversarial_mail_g.nim` | The six adversarial-scenario blocks in §8.2.3 plus the §8.12 scale block, organised as 7 enclosing group blocks (`rfc5321MailboxAdversarialGroup`, `submissionParamAdversarialGroup`, `envelopeCoherenceGroup`, `anyEmailSubmissionDispatchGroup`, `smtpReplyGrammarGroup`, `getBothSubmissionAdversarialGroup`, `scaleInvariantsGroup`) with per-scenario assertions as nested child blocks. Registered in `tests/testament_skip.txt` (runs under `just stress` / `just test-full`). |

#### 8.2.1. `tests/property/tprop_mail_g.nim`

Nine property groups, calibrated against the trial-count cost model
(§8.9.3) and the Part E/F precedents (`tprop_mail_e.nim:64`,
`tprop_mail_f.nim` Group D/F). No `CrossProcessTrials` group — the
`distinct seq` / `distinct OrderedTable` design of
`NonEmptyEmailSubmissionUpdates`, `SubmissionParams`,
`NonEmptyRcptList`, and `DeliveryStatusMap` preserves insertion order
on serialisation, eliminating the hash-seed nondeterminism that would
justify a cross-process probe.

| Group | Property | Tier | Notes |
|-------|----------|------|-------|
| A | `parseRFC5321Mailbox` **totality** — for all `rng`-generated byte sequences (length 0..512, mixed ASCII + control characters + chosen printable sets), the parser returns `Ok` xor `Err` (never panics, never blocks). **Mandatory edge-bias schedule**: trial 0 = `"user@example.com"` (canonical baseline); trial 1 = `""` (empty); trial 2 = `"@"` (minimal malformed); trial 3 = `"user@[127.0.0.1]"` (IPv4 address-literal); trial 4 = `"user@[IPv6:::1]"` (IPv6 address-literal); trial 5 = `"\"quoted\"@example.com"` (quoted-string local-part); trial 6 = `"user@[IPv6:::1]general"` (General-address-literal). Random sampling from trial 7 onward. | `DefaultTrials` (500) | Totality is the primary safety invariant for the RFC 5321 parser — 553 lines of L1 code. A panic here would surface on the client construction path. |
| B | `parseRFC5321Mailbox` **strict/lenient coverage** — for every string accepted by the strict parser (`parseRFC5321Mailbox`), the lenient parser (`parseRFC5321MailboxFromServer`) also accepts. At least one generated input is accepted by the lenient parser but rejected by the strict one (the relationship is a proper superset, not equality). Quantified via the paired call: `(strictOk.isOk and lenientOk.isOk) or (strictOk.isErr)`; separately, trial 0 forces `"admin"` (no @ — rejected by both) and trial 1 forces a lenient-only shape. | `DefaultTrials` (500) | Pins Postel's law at the type level. Without this test, the strict/lenient split (G7) decays silently into duplicate code — the lenient parser could drift into rejecting strict-valid inputs, violating the superset invariant. |
| C | `SubmissionParams` **insertion-order round-trip** — for any seq of distinct-key `SubmissionParam` values (0..20 entries), `parseSubmissionParams(seq)` on success produces a `SubmissionParams` whose `toJson` output lists keys in the seq's original order. Mandatory edge-bias: trial 0 = empty seq; trial 1 = single `spkBody` entry; trial 2 = all 11 well-known variants in declaration order; trial 3 = all 11 + one `spkExtension`; trial 4 = reverse declaration order. | `DefaultTrials` (500) | `OrderedTable` is a claim; server wire ordering is a correctness property for SMTP parameter replay (some servers apply parameters positionally). The property makes the claim executable. |
| D | `SubmissionParamKey` **identity algebra** — for all pairs `(p1, p2)`, `paramKey(p1) == paramKey(p2)` iff `p1.kind == p2.kind` AND (when `p1.kind == spkExtension`) `p1.extName == p2.extName` byte-wise. Enumerate all `SubmissionParamKind` × `SubmissionParamKind` combinations at trials 0..143 (12² = 144); random composition thereafter. Extension-name adversaries biased at trials 144..160: `("X-FOO", "x-foo")` (case-insensitive equality via `RFC5321Keyword`), `("X-FOO", "X-BAR")`, same-prefix variants. | `DefaultTrials` (500) | The derived-not-stored pattern (G8a) is load-bearing for uniqueness in `SubmissionParams` Table lookups; a regression here would let duplicate keys slip through. The property exercises the hash + `==` contract together. |
| E | `AnyEmailSubmission` **state dispatch** — `AnyEmailSubmission` is `fromJson`-only (`serde_email_submission.nim` module header), so the property is a parse-only dispatch: for each generated `UndoStatus`, build wire JSON directly with the matching `undoStatus` token, parse, and confirm `state` matches AND the three accessors yield exactly one `Opt.some` (the matching arm) and two `Opt.none`. Mandatory edge-bias: trial 0 = `usPending`; trial 1 = `usFinal`; trial 2 = `usCanceled` (one per variant forced early). Random `UndoStatus` selection from trial 3 onward via `genUndoStatus`. | `DefaultTrials` (500) | Pins the existential-wrapper discharge on the wire dispatch path. The serde boundary dispatch (G1 §7.1) recovers the phantom parameter from the wire `undoStatus` field; a regression breaks every `case sub.state of usPending:` consumer. |
| F | `cancelUpdate` **invariant** — for every `EmailSubmission[usPending]` generated via `genEmailSubmission[usPending]`, the returned `cancelUpdate(s)` satisfies `kind == esuSetUndoStatusToCanceled`. Trivially true but pins the phantom-constrained helper against regression. | `QuickTrials` (200) | Cheap predicate; the value-level property is regression-detection only. The **type-level** enforcement — that `cancelUpdate` refuses `EmailSubmission[usFinal]` and `EmailSubmission[usCanceled]` — lives in the `assertNotCompiles` block in §8.3's `temail_submission.nim`. Two tools for two layers: do **not** promote this group to `DefaultTrials`, and do **not** demote the compile-time probe to runtime. |
| G | `NonEmptyEmailSubmissionUpdates` **duplicate-Id invariant** — for all maps with at least one duplicated `Id` (≥ 2 occurrences), the constructor accumulates ≥ 1 violation. Quantifies over the duplicate's position, total map size, and update value. Mandatory edge-bias: trial 0 = duplicate at positions (0, 1) (early-bound); trial 1 = duplicate at positions (n−2, n−1) (late-bound — guards against an `i > 0` early-bail bug); trial 2 = three-occurrence duplicate; trial 3 = many-position duplicate cluster. Random sampling from trial 4. Mirrors `tprop_mail_f.nim` Group C for `NonEmptyEmailImportMap`. | `DefaultTrials` (500) | Reuses the `validateUniqueByIt` contract (G17); pin behavioural equivalence with F1's `NonEmptyEmailImportMap`. |
| H | `ParsedDeliveredState.rawBacking` **round-trip for unknown values** — for all generated byte strings (including the four RFC-defined values `"queued"`, `"yes"`, `"no"`, `"unknown"`), `parseDeliveredState(s)` produces a `ParsedDeliveredState` whose `rawBacking == s`; for values outside the RFC-defined set, `state == dsOther`. `toJson` emits `rawBacking` byte-for-byte. Symmetric group covers `DisplayedState` / `ParsedDisplayedState`. Mandatory edge-bias: trials 0..3 = the four RFC-defined values for `DeliveredState`; trial 4 = one RFC-defined for `DisplayedState` (`"yes"`); trials 5..6 = unknown values (`"pending"` — note: this is NOT a `DeliveredState` value, pin the catch-all rather than a `UndoStatus`-style collision). | `DefaultTrials` (500) | The `dsOther` / `dpOther` catch-all (G10, G11) is forwards-compatibility insurance; raw-backing preservation must not lose bytes. Without this property, a server adding a new delivery state (e.g., `"deferred"`) would round-trip through the client as `"unknown"` or similar — silent corruption. |
| I | `parseSmtpReply` **Reply-code boundary scan** — for all generated strings of form `"<d1><d2><d3>"` plus optional `<sep><text>`, with `d1, d2, d3 ∈ '0'..'9'`, the parser's Ok/Err verdict matches RFC 5321 §4.2's grammar: `d1 ∈ '2'..'5'`, `d2 ∈ '0'..'5'`, `d3 ∈ '0'..'9'`. Mandatory edge-bias: trial 0 = `"199 text"` (d1 below range — reject); trial 1 = `"200 text"` (d1 at low boundary — accept); trial 2 = `"559 text"` (d1 at high boundary — accept); trial 3 = `"650 text"` (d1 above range — reject); trial 4 = `"260 text"` (d2 above range — reject); trial 5 = `"259 text"` (d3 at high boundary — accept); trial 6 = `"250"` (bare code, no separator — accepted by `parseSmtpReply` as a final-line short form); trial 7 = multi-line `"250-ok\r\n250 done"` (accept); trial 8 = multi-line `"250 ok\r\n250 done"` (reject — non-final must hyphen). Random sampling from trial 9. | `DefaultTrials` (500) | Reply-code grammar is finite at the digit level but the text-continuation grammar is not; boundaries at `2xx` / `5xx` endpoints are where real-world SMTP servers drift. A property here catches accidental off-by-one in digit-range checks. |

**Deliberately absent property groups**:

- **Conflict-pair classification.** F2 Group A (Class 1/2/3) was dropped
  in F2 itself on the basis that conflict detection is a unit-tier
  concern when the variant space is finite. G1's `EmailSubmissionUpdate`
  has exactly **one** variant (`esuSetUndoStatusToCanceled`, per G16) —
  there are no pairs to classify, and no equivalence classes exist.
  The group is omitted outright; no placeholder row is carried.
- **RFC 6901 JSON Pointer escape bijectivity.** The submission serde
  goes through the same `jsonPointerEscape` helper F1 property-tests at
  `tprop_mail_f.nim` Group D. Re-running it here adds no coverage;
  reference the existing group and stop. G1 introduces no new
  keyword-substitution site.
- **`moveToMailbox ≡ setMailboxIds` equivalence.** No G1 analogue
  exists. `cancelUpdate` is the only typed transition helper and has no
  equivalence partner at a different abstraction layer.

The single compound-handle short-circuit concern migrates to a
table-driven enumeration in `tests/protocol/tmail_builders.nim` (§8.4) —
a single fixed response shape per variant, with the variant set finite,
makes a property test redundant. The implementation uses the native
`for variant in MethodErrorType:` idiom (precedent: `terrors.nim:428`).

#### 8.2.2. `tests/compile/tcompile_mail_g_public_surface.nim`

Compile-only smoke test. A single top-level `import jmap_client` plus
a `static:` block containing 99 `declared(<symbol>)` assertions, one
per new public symbol, organised into 17 comment-separated groups. A
single runtime-scope `doAssert $mnEmailSubmissionSet ==
"EmailSubmission/set"` at line 159 pins the imported module against
Nim's `UnusedImport` check via a genuine Part G method-enum variant.

**Why `declared()` and not `compiles()`.** `declared()` sidesteps
overload-resolution ambiguity on the three phantom-typed `toAny` arms
and on `getBoth` (distinct overloads for `EmailCopyHandles` and
`EmailSubmissionHandles`). A naïve `compiles(let x: AnyEmailSubmission
= toAny(default(EmailSubmission[usPending])))` probe would snag on the
overload set; `declared()` asks only "is this identifier visible at
this site?", which is exactly the re-export invariant under test. The
file documents this choice in its opening docstring (lines 12–16).

**Covered symbols** (authoritative, in source order):

- **RFC 5321 atoms + capability refinement (4):**
  `RFC5321Mailbox`, `RFC5321Keyword`, `OrcptAddrType`,
  `SubmissionExtensionMap`. (lines 22–25)
- **SMTP parameter payload newtypes and enums (6):**
  `BodyEncoding`, `DsnRetType`, `DsnNotifyFlag`, `DeliveryByMode`,
  `HoldForSeconds`, `MtPriority`. (lines 28–33)
- **SMTP parameter algebra (4):**
  `SubmissionParamKind`, `SubmissionParam`, `SubmissionParamKey`,
  `SubmissionParams`. (lines 36–39)
- **Envelope composite types (5):**
  `SubmissionAddress`, `ReversePathKind`, `ReversePath`,
  `NonEmptyRcptList`, `Envelope`. (lines 42–46)
- **Status types (8):**
  `UndoStatus`, `DeliveredState`, `ParsedDeliveredState`,
  `DisplayedState`, `ParsedDisplayedState`, `ParsedSmtpReply`,
  `DeliveryStatus`, `DeliveryStatusMap`. (lines 49–56)
- **Entity phantom-indexed + existential wrapper + creation ref (5):**
  `EmailSubmission`, `AnyEmailSubmission`, `IdOrCreationRefKind`,
  `IdOrCreationRef`, `EmailSubmissionBlueprint`. (lines 59–63)
- **Update algebra (4):**
  `EmailSubmissionUpdate`, `EmailSubmissionUpdateVariantKind`,
  `NonEmptyEmailSubmissionUpdates`, `NonEmptyIdSeq`. (lines 66–69)
- **Query typing (3):**
  `EmailSubmissionFilterCondition`, `EmailSubmissionSortProperty`,
  `EmailSubmissionComparator`. (lines 72–74)
- **/set response shape and compound handles (4):**
  `EmailSubmissionCreatedItem`, `EmailSubmissionSetResponse`,
  `EmailSubmissionHandles`, `EmailSubmissionResults`. (lines 77–80)
- **Smart constructors / parsers (14):**
  `parseRFC5321Mailbox`, `parseRFC5321MailboxFromServer`,
  `parseRFC5321Keyword`, `parseOrcptAddrType`, `parseHoldForSeconds`,
  `parseMtPriority`, `parseSubmissionParams`, `parseNonEmptyRcptList`,
  `parseNonEmptyRcptListFromServer`, `parseSmtpReply`,
  `parseEmailSubmissionBlueprint`, `parseNonEmptyEmailSubmissionUpdates`,
  `parseNonEmptyIdSeq`, `parseEmailSubmissionComparator`. (lines 83–96)
- **Server-side infallible parsers (2):**
  `parseDeliveredState`, `parseDisplayedState`. (lines 99–100)
- **Typed parameter constructors (12):**
  `bodyParam`, `byParam`, `envidParam`, `extensionParam`,
  `holdForParam`, `holdUntilParam`, `mtPriorityParam`, `notifyParam`,
  `orcptParam`, `retParam`, `sizeParam`, `smtpUtf8Param`. (lines 103–114)
- **Infallible constructors + phantom-boundary helpers (11):**
  `nullReversePath`, `reversePath`, `paramKey`, `toAny`,
  `asPending`, `asFinal`, `asCanceled`, `setUndoStatusToCanceled`,
  `cancelUpdate`, `directRef`, `creationRef`. (lines 117–127)
- **Domain helpers on `DeliveryStatusMap` (2):**
  `countDelivered`, `anyFailed`. (lines 130–131)
- **onSuccess* NonEmpty extras (4):**
  `NonEmptyOnSuccessUpdateEmail`, `NonEmptyOnSuccessDestroyEmail`,
  `parseNonEmptyOnSuccessUpdateEmail`,
  `parseNonEmptyOnSuccessDestroyEmail`. (lines 134–137)
- **L3 method builders (6):**
  `addEmailSubmissionGet`, `addEmailSubmissionChanges`,
  `addEmailSubmissionQuery`, `addEmailSubmissionQueryChanges`,
  `addEmailSubmissionSet`, `addEmailSubmissionAndEmailSet`.
  (lines 140–145)
- **Method enum route variants (5):**
  `mnEmailSubmissionGet`, `mnEmailSubmissionChanges`,
  `mnEmailSubmissionQuery`, `mnEmailSubmissionQueryChanges`,
  `mnEmailSubmissionSet`. (lines 148–152)
- **Runtime anchor (1):**
  `doAssert $mnEmailSubmissionSet == "EmailSubmission/set"` at line 159.

**What the file deliberately does NOT do:**

- **No phantom-kind exhaustiveness probe.** A block of the form
  `assertNotCompiles(let _: EmailSubmission[usOther] =
  default(EmailSubmission[usOther]))` is trivially true — `usOther` is
  not a member of `UndoStatus` (G3 closed the enum), so the compiler
  rejects it regardless of the `static UndoStatus` constraint on the
  phantom parameter. The compiler's existing exhaustiveness check at
  every `case anySub.state:` site (e.g., the serde boundary in
  `serde_email_submission.nim`) already forces a build error when a
  hypothetical fourth variant is added — a dedicated probe would add
  no coverage.
- **No `fromJson`-absence pin for toJson-only types.**
  `EmailSubmissionBlueprint`, `EmailSubmissionFilterCondition`,
  `EmailSubmissionComparator`, and `IdOrCreationRef` have no `fromJson`
  defined in `serde_email_submission.nim` (by G22/G26 contract — these
  flow client → server only). The primary verification is the grep
  check: `grep -n 'fromJson' src/jmap_client/mail/serde_email_submission.nim`
  — any future `fromJson` addition would show up and force an explicit
  review. A compile-level `assertNotCompiles` gate on these types would
  conflate "not implemented" with "compile error for an unrelated
  reason" and is thus rejected (F2 §8.2.2 set this policy for the
  `EmailUpdate*` family; G2 inherits it).
- **No variant-kind exhaustiveness probes.** Internal `case` sites in
  `email_submission.nim`, `serde_email_submission.nim`, and
  `submission_param.nim` already force the compiler to witness every
  `UndoStatus`, `SubmissionParamKind`, and `EmailSubmissionUpdateVariantKind`
  variant. Dedicated probes would duplicate the coverage the production
  code already provides.

The `cancelUpdate` phantom-typed arrow is exercised by an
`assertNotCompiles` block in `tests/unit/mail/temail_submission.nim`
(`phantomArrowStaticRejectsFinalAndCanceled`, line 78) and again in
`tests/compliance/trfc_8620.nim`'s
`rfc8621Section7ConstraintTableCompileTimeAnchor` block (line 1801–1803),
where the constraint-table audit walks both the positive and negative
arms of the typed arrow inline.

#### 8.2.3. `tests/stress/tadversarial_mail_g.nim`

Adversarial scenarios, organised into six blocks corresponding to
matrices §8.3 (per-concept messages), §8.6 (cross-entity coherence),
§8.7 (parameter boundaries), §8.12 (scale invariants), and three
cross-cutting blocks covering `AnyEmailSubmission` dispatch,
`ParsedSmtpReply` grammar, and `Envelope` coherence. Each numbered
block below corresponds to one enclosing group block (`*Group`); per-
scenario rows land as nested child blocks under that group, not as
top-level peers.

**Block 1 — RFC 5321 Mailbox adversarial.** Inside the enclosing
`rfc5321MailboxAdversarialGroup` block
(`tadversarial_mail_g.nim:54`). Each row below is a nested child
block with the cited name. The strict parser must reject; the lenient
parser (`parseRFC5321MailboxFromServer`) either rejects or accepts
per the Postel split — the actual contract is captured in the table.

| Test name | Input | Strict outcome | Lenient outcome | Rule |
|-----------|-------|----------------|-----------------|------|
| `mailboxTrailingDotLocal` | `"user.@example.com"` | `Err` ("local-part is not a valid dot-string") | `Err` (structural: still malformed) | RFC 5321 §4.1.2 Dot-string |
| `mailboxUnclosedQuoted` | `"\"unterminated@example.com"` | `Err` ("local-part is not a valid quoted-string") | `Err` (structural) | RFC 5321 §4.1.2 Quoted-string |
| `mailboxBracketlessIPv6` | `"user@IPv6:::1"` | `Err` ("domain contains an invalid label") | `Ok` — lenient checks only `len ≤ 255 ∧ no control chars ∧ '@' present` (`submission_mailbox.nim:546-556`) | RFC 5321 §4.1.3 requires `[…]` |
| `mailboxOverlongLocalPart` | local-part 65 octets + `"@example.com"` | `Err` ("local-part exceeds 64 octets") | `Ok` — lenient does not enforce per-part bounds | RFC 5321 §4.5.3.1.1 |
| `mailboxOverlongDomain` | `"user@"` + domain 256 octets | `Err` ("domain exceeds 255 octets") | `Err` — lenient also enforces the total 1..255 octet bound via `detectLenientToken` | RFC 5321 §4.5.3.1.2 |
| `mailboxGeneralLiteralStandardizedTagTrailingHyphen` | `"user@[foo-:bar]"` (Standardized-tag ends in hyphen) | `Err` ("address-literal has invalid general form") | `Ok` — lenient does not parse address-literal grammar | RFC 5321 §4.1.3 Standardized-tag MUST end in `Let-dig`; contrast with `RFC5321Keyword` (G1 §2.2) which permits trailing hyphen because it uses the looser `esmtp-keyword` grammar |
| `mailboxControlChar` | `"u\x01ser@example.com"` | `Err` ("contains control characters") | `Err` (same) | Structural |
| `mailboxEmpty` | `""` | `Err` ("must not be empty") | `Err` (same) | Structural |

The `mailboxGeneralLiteralStandardizedTagTrailingHyphen` case is the
load-bearing contrast test — G1 §2.2 documents that
`RFC5321Keyword` permits trailing hyphen (per `esmtp-keyword`) while
`RFC5321Mailbox`'s embedded Standardized-tag uses the stricter
`Ldh-str`. A bug that unifies the two check routines would pass all
the positive mailbox tests but fail this single row.

**Block 2 — `SubmissionParam` wire adversarial.** Inside the enclosing
`submissionParamAdversarialGroup` block (`tadversarial_mail_g.nim:104`).
Drives through the typed parameter constructors and
`toJson`/`fromJson` on `SubmissionParams`.

| Test name | Input | Expected |
|-----------|-------|----------|
| `paramRetUnknownValue` | wire input `{"RET": "BOTH"}` | `SubmissionParams.fromJson` → `Err` (closed-enum rejection at `parseEnumByBackingString[DsnRetType]`) |
| `paramNotifyNeverWithOthers` | `notifyParam({dnfNever, dnfSuccess})` | `Err` (`"NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY"` per `submission_param.nim:212`) |
| `paramNotifyEmptyFlags` | `notifyParam({})` | `Err` (`"NOTIFY flags must not be empty"` per `submission_param.nim:207`) |
| `paramHoldForNegative` | wire input `{"HOLDFOR": "-1"}` | `Err` — `parseUnsignedDecimal` rejects the leading `-` (`serde_submission_envelope.nim:35`); the L1 type is `UnsignedInt` so a negative value is unrepresentable at construction |
| `paramMtPriorityBelowRange` | `parseMtPriority(-10)` | `Err` (`"must be in range -9..9"` per `submission_param.nim:103`) |
| `paramMtPriorityAboveRange` | `parseMtPriority(10)` | `Err` (same) |
| `paramSizeAt2Pow53Boundary` | `{"SIZE": "9007199254740991"}` (`2^53 − 1`, max exact-representable; SIZE rides as a JSON string per RFC 8621 §7.3.2) | `Ok` |
| `paramSizeAbove2Pow53` | `{"SIZE": "9007199254740992"}` | `Err` — `parseUnsignedInt` rejects per `primitives.nim` (`MaxUnsignedInt = 2^53 − 1`) |
| `paramEnvidXtextEncoded` | `{"ENVID": "hello\\x2Bworld"}` — per the G1 resolved note (§7.2), no xtext helpers exist; the JMAP wire carries plain UTF-8 | `Ok` — string stored verbatim |
| `paramDuplicateKey` | Two `spkBody` entries in the input seq | `Err` (`"duplicate parameter key"` per `submission_param.nim:428`) |

**Block 3 — `Envelope` serde coherence.** Inside the enclosing
`envelopeCoherenceGroup` block (`tadversarial_mail_g.nim:175`). Tests
the null-reverse-path shape, the strict/lenient duplicate split, and
the parameters-on-null case.

| Test name | Wire JSON | Expected |
|-----------|-----------|----------|
| `envelopeNullMailFromWithParams` | `{"mailFrom": {"email": "", "parameters": {"ENVID": "id-1"}}, "rcptTo": [...]}` | `Ok` — G32 permits parameters on the null reverse path; `rpkNullPath` carries `Opt.some(SubmissionParams)` |
| `envelopeNullMailFromNoParams` | `{"mailFrom": {"email": "", "parameters": null}, "rcptTo": [...]}` | `Ok` — `rpkNullPath` with `Opt.none` |
| `envelopeMalformedMailFrom` | `{"mailFrom": {"email": "noAtSign.example.com", "parameters": null}, "rcptTo": [...]}` (input lacking `@` — the lenient server-side parser still rejects this structural failure) | `Err` |
| `envelopeEmptyRcptTo` | `{"mailFrom": {...}, "rcptTo": []}` | `Err` — pins the `NonEmptyRcptList` contract, complementing `emptyRcptToIsRejected` at `tserde_submission_envelope.nim:110-119` |
| `envelopeDuplicateRcptToLenient` | `{"mailFrom": {...}, "rcptTo": [alice, alice]}` via `parseNonEmptyRcptListFromServer` | `Ok` — lenient parser accepts duplicates (G7 Postel split) |
| `envelopeDuplicateRcptToStrict` | Same via `parseNonEmptyRcptList` (client path) | `Err` (`"duplicate recipient mailbox"` per `submission_envelope.nim:128`) |
| `envelopeOptNoneVsEmptyParams` | `SubmissionAddress` with `Opt.none(SubmissionParams)` toJson → `"parameters": null`; with `Opt.some(emptyParams)` toJson → `"parameters": {}` | Wire shapes are distinct; both round-trip preserving the distinction (G34) |

**Block 4 — `AnyEmailSubmission` dispatch adversarial.** Inside the
enclosing `anyEmailSubmissionDispatchGroup` block
(`tadversarial_mail_g.nim:262`). Critical note: `UndoStatus` is the
phantom parameter (G3), so the forwards-compat catch-all pattern that
applies to `DeliveredState`/`DisplayedState` (G10/G11) does **not**
apply here. Any wire `undoStatus` value outside
`{"pending", "final", "canceled"}` must `Err` —
`parseUndoStatus` (`serde_submission_status.nim:37-56`) emits
`svkEnumNotRecognised`.

`AnyEmailSubmission` is `fromJson`-only by design
(`serde_email_submission.nim` module header) — there is no `toJson`,
so the verification pivots from a round-trip to a parse-and-dispatch
shape: a wire JSON object is built directly from each `UndoStatus`
token and the resulting `AnyEmailSubmission.state` is checked against
the input.

| Test name | Wire JSON (AnyEmailSubmission) | Expected |
|-----------|-------------------------------|----------|
| `anyMissingUndoStatus` | object without `undoStatus` field | `Err` |
| `anyUndoStatusWrongKindInt` | `{"undoStatus": 1, ...}` | `Err` |
| `anyUndoStatusWrongKindNull` | `{"undoStatus": null, ...}` | `Err` |
| `anyUndoStatusUnknownValue` | `{"undoStatus": "deferred", ...}` | `Err` (`svkEnumNotRecognised` — NOT a silent `usOther` fallback) |
| `anyUndoStatusCaseMismatch` | `{"undoStatus": "PENDING", ...}` | `Err` — wire tokens are lowercase per G1 §3.1 |
| `anyDispatchAllThreeVariants` | Build wire JSON from each `UndoStatus`; confirm `state` matches each token | Ok; per-state dispatch verified |

**Block 5 — `ParsedSmtpReply` grammar adversarial.** Inside the
enclosing `smtpReplyGrammarGroup` block
(`tadversarial_mail_g.nim:350`). Per the error strings at
`submission_status.nim:194–215` (surface-grammar arms of
`SmtpReplyViolation.toValidationError`).

| Test name | Input | Expected |
|-----------|-------|----------|
| `smtpReplyEmpty` | `""` | `Err` (`"must not be empty"`) |
| `smtpReplyControlChar` | `"250 o\x01k"` | `Err` (`"contains disallowed control characters"`) |
| `smtpReplyTooShort` | `"25"` | `Err` (`"line shorter than 3-digit Reply-code"`) |
| `smtpReplyFirstDigitZero` | `"050 ok"` | `Err` (`"first Reply-code digit must be in 2..5"`) |
| `smtpReplyFirstDigitOne` | `"150 ok"` | `Err` (same) |
| `smtpReplyFirstDigitSix` | `"650 ok"` | `Err` (same) |
| `smtpReplyFirstDigitNine` | `"950 ok"` | `Err` (same) |
| `smtpReplySecondDigitSix` | `"260 ok"` | `Err` (`"second Reply-code digit must be in 0..5"`) |
| `smtpReplyThirdDigitBoundary` | `"259 ok"` | `Ok` (boundary high) |
| `smtpReplyBadSeparator` | `"250?ok"` | `Err` (`"character after Reply-code must be SP, HT, or '-'"`) |
| `smtpReplyMultilineCodeMismatch` | `"250-ok\r\n251 done"` | `Err` (`"multi-line reply has inconsistent Reply-codes"`) |
| `smtpReplyMultilineFinalHyphen` | `"250-ok\r\n250-done"` | `Err` (`"final reply line must not use '-' continuation"`) |
| `smtpReplyMultilineNonFinalSpace` | `"250 ok\r\n250 done"` | `Err` (`"non-final reply line must use '-' continuation"`) |
| `smtpReplyBareCodeNoText` | `"250"` | Tolerated by the parser (totality probe — both `Ok` and `Err` are accepted by the assertion) |

The five RFC 3463 §2 enhanced-status-code violations
(`srEnhancedMalformedTriple`, `srEnhancedClassInvalid`,
`srEnhancedSubjectOverflow`, `srEnhancedDetailOverflow`,
`srEnhancedMultilineMismatch`) carry their own error strings at
`submission_status.nim:216–229`; those rejection paths are exercised
by the property group I digit-grammar scan (§8.2.1) and by the
`smtpReplyEnhancedCodeHappy` block in `tsubmission_status.nim:147`
(which pins the positive arm).

**Block 6 — `getBoth(EmailSubmissionHandles)` cross-entity
adversarial.** Inside the enclosing `getBothSubmissionAdversarialGroup`
block (`tadversarial_mail_g.nim:446`). Cross-references §8.6; each row
in that matrix is realised here as a nested child block with a
complete wire `Response` fixture. Unlike F1's same-entity
`getBoth(EmailCopyHandles)`, these scenarios involve two entity
namespaces (`EmailSubmission/*` and `Email/*`) sharing one
request-response envelope. Block 7 (the §8.12 scale invariants — 3
blocks) is inside a parallel `scaleInvariantsGroup` block
(`tadversarial_mail_g.nim:563`).

The generic `getBoth[A, B]` (`dispatch.nim:254-264`) chains `?` on
`dr.get(handles.implicit)`, so the inner handle's
`NameBoundHandle.callId` and `methodName` filters drive every
adversarial outcome. Two consequences are non-obvious from the spec:

- An `"error"` invocation at the inner slot does not match the
  `"Email/set"` method-name filter, so the dispatch surfaces
  `serverFail` ("no Email/set response for call ID …") rather than
  the inner `MethodError`. Rows 2 and 3 share that shape.
- `getBothCreationRefNotInCreateMap` is a client-hands-off pin: the
  client does NOT pre-validate creation-ref resolution; the wire
  shape parses successfully and coherence is the server's
  responsibility.

| Test name | Scenario | Expected `getBoth` outcome |
|-----------|----------|---------------------------|
| `getBothBothSucceed` | Outer `EmailSubmission/set` ok + `created` populated; inner `Email/set` ok | `Ok(EmailSubmissionResults{primary, implicit})` |
| `getBothInnerMethodError` | Outer ok; inner is an `"error"` invocation tagged `accountNotFound` | `Err(serverFail)` ("no Email/set response for call ID c0") — the inner error is masked by the method-name filter |
| `getBothInnerAbsent` | Outer ok; inner response absent | `Err(serverFail)` (same description) |
| `getBothInnerMcIdMismatch` | Outer ok; inner present at wrong `methodCallId` | `Err(serverFail)` (same description) |
| `getBothOuterNotCreatedSole` | Outer ok with `notCreated` sole entry; no inner `Email/set` invocation at the shared call id | `Err(serverFail)` — the `NameBoundHandle` cannot resolve without an inner invocation; the unit-tier analogue in `tmail_builders.nim:881` covers the alternative where the server emits an empty inner invocation and `getBoth` returns `Ok` |
| `getBothOuterIfInStateMismatch` | Outer is an `"error"` invocation tagged `stateMismatch`; inner no invocation | `Err(metStateMismatch)` — the outer's plain `ResponseHandle` routes through `extractInvocation`, which surfaces method errors by name-tag, so `getBoth` short-circuits before consulting the inner |
| `getBothCreationRefNotInCreateMap` | Outer ok with `onSuccessUpdateEmail: {"#c-missing": ...}`; inner present at the shared call id | `Ok` — wire shape parses regardless; client-side dispatch does NOT pre-validate creation-ref resolution (server's job) |

Reference — do **not** duplicate — `tests/stress/tadversarial_mail_f.nim`'s
JSON-structural attacks (BOM prefix, NaN/Infinity, duplicate keys, deep
nesting, 1 MB strings) and cast-bypass pins. G1 introduces no new
`std/json` pathway; those attacks apply transitively to every G1
decode surface, and re-enumerating them here would duplicate coverage.

---

### 8.3. Per-concept test files

**Error-rail shape (applies to every rejection assertion below).** The
`ValidationError` record has exactly three fields: `typeName: string`,
`message: string`, `value: string`. There is no `classification`
field, `kind` enum, or similar typed discriminator on
`ValidationError`; rejection assertions check `error[<i>].message`
against the literal string the production code emits. The
authoritative messages, read from source:

| Type | Invariant | `message` | `value` | Source |
|------|-----------|-----------|---------|--------|
| `RFC5321Keyword` | bad length | `"length must be 1-64 octets"` | offending raw | `submission_atoms.nim:79` |
| `RFC5321Keyword` | bad lead char | `"first character must be ALPHA or DIGIT"` | offending raw | `submission_atoms.nim:81` |
| `RFC5321Keyword` | bad tail chars | `"characters must be ALPHA / DIGIT / '-'"` | offending raw | `submission_atoms.nim:83` |
| `OrcptAddrType` | empty | `"must not be empty"` | `""` | `submission_atoms.nim:133` |
| `OrcptAddrType` | bad lead char | `"first character must be ALPHA or DIGIT"` | offending raw | `submission_atoms.nim:135` |
| `OrcptAddrType` | bad tail chars | `"characters must be ALPHA / DIGIT / '-'"` | offending raw | `submission_atoms.nim:137` |
| `SmtpReply` | empty | `"must not be empty"` | offending raw | `submission_status.nim:195` |
| `SmtpReply` | control chars | `"contains disallowed control characters"` | offending raw | `submission_status.nim:197` |
| `SmtpReply` | too short | `"line shorter than 3-digit Reply-code"` | offending raw | `submission_status.nim:199` |
| `SmtpReply` | first digit out of range | `"first Reply-code digit must be in 2..5"` | offending raw | `submission_status.nim:201` |
| `SmtpReply` | second digit out of range | `"second Reply-code digit must be in 0..5"` | offending raw | `submission_status.nim:203` |
| `SmtpReply` | third digit out of range | `"third Reply-code digit must be in 0..9"` | offending raw | `submission_status.nim:205` |
| `SmtpReply` | bad separator | `"character after Reply-code must be SP, HT, or '-'"` | offending raw | `submission_status.nim:207-209` |
| `SmtpReply` | multi-line code mismatch | `"multi-line reply has inconsistent Reply-codes"` | offending raw | `submission_status.nim:211` |
| `SmtpReply` | non-final continuation | `"non-final reply line must use '-' continuation"` | offending raw | `submission_status.nim:213` |
| `SmtpReply` | final with hyphen | `"final reply line must not use '-' continuation"` | offending raw | `submission_status.nim:215` |
| `SmtpReply` | enhanced triple malformed | `"enhanced status code not a numeric dot-separated triple"` | offending raw | `submission_status.nim:217-219` |
| `SmtpReply` | enhanced class invalid | `"enhanced status-code class must be 2, 4, or 5"` | offending raw | `submission_status.nim:221` |
| `SmtpReply` | enhanced subject overflow | `"enhanced status-code subject out of 0..999"` | offending raw | `submission_status.nim:223` |
| `SmtpReply` | enhanced detail overflow | `"enhanced status-code detail out of 0..999"` | offending raw | `submission_status.nim:225` |
| `SmtpReply` | enhanced multi-line mismatch | `"multi-line reply has inconsistent enhanced status codes"` | offending raw | `submission_status.nim:227-229` |
| `RFC5321Mailbox` | empty | `"must not be empty"` | offending raw | `submission_mailbox.nim:109` |
| `RFC5321Mailbox` | control chars | `"contains control characters"` | offending raw | `submission_mailbox.nim:111` |
| `RFC5321Mailbox` | no `@` | `"missing '@' separator"` | offending raw | `submission_mailbox.nim:113` |
| `RFC5321Mailbox` | empty local-part | `"local-part must not be empty"` | offending raw | `submission_mailbox.nim:115` |
| `RFC5321Mailbox` | local-part > 64 octets | `"local-part exceeds 64 octets"` | offending raw | `submission_mailbox.nim:117` |
| `RFC5321Mailbox` | local-part bad dot-string | `"local-part is not a valid dot-string"` | offending raw | `submission_mailbox.nim:119` |
| `RFC5321Mailbox` | local-part bad quoted | `"local-part is not a valid quoted-string"` | offending raw | `submission_mailbox.nim:121` |
| `RFC5321Mailbox` | empty domain | `"domain must not be empty"` | offending raw | `submission_mailbox.nim:123` |
| `RFC5321Mailbox` | domain > 255 octets | `"domain exceeds 255 octets"` | offending raw | `submission_mailbox.nim:125` |
| `RFC5321Mailbox` | domain bad label | `"domain contains an invalid label"` | offending raw | `submission_mailbox.nim:127` |
| `RFC5321Mailbox` | addr-literal unclosed | `"address-literal missing closing ']'"` | offending raw | `submission_mailbox.nim:129` |
| `RFC5321Mailbox` | addr-literal bad IPv4 | `"address-literal has invalid IPv4 form"` | offending raw | `submission_mailbox.nim:131` |
| `RFC5321Mailbox` | addr-literal bad IPv6 | `"address-literal has invalid IPv6 form"` | offending raw | `submission_mailbox.nim:133` |
| `RFC5321Mailbox` | addr-literal bad general | `"address-literal has invalid general form"` | offending raw | `submission_mailbox.nim:135` |
| `MtPriority` | out of range | `"must be in range -9..9"` | offending int as string | `submission_param.nim:103` |
| `SubmissionParam` (notifyParam) | empty flags | `"NOTIFY flags must not be empty"` | `""` | `submission_param.nim:207` |
| `SubmissionParam` (notifyParam) | NEVER + others | `"NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY"` | `""` | `submission_param.nim:212` |
| `SubmissionParams` | duplicate key | `"duplicate parameter key"` | key as string | `submission_param.nim:428` |
| `NonEmptyRcptList` (strict) | empty | `"recipient list must not be empty"` | `""` | `submission_envelope.nim:127` |
| `NonEmptyRcptList` (strict) | duplicate | `"duplicate recipient mailbox"` | offending address | `submission_envelope.nim:128` |
| `NonEmptyRcptList` (lenient) | empty | `"recipient list must not be empty"` | `""` | `submission_envelope.nim:142` |
| `NonEmptyOnSuccessUpdateEmail` | empty | `"must contain at least one entry"` | `""` | `email_submission.nim:567` |
| `NonEmptyOnSuccessUpdateEmail` | duplicate key | `"duplicate id or creation reference"` | duplicated ref as string | `email_submission.nim:568` |
| `NonEmptyOnSuccessDestroyEmail` | empty | `"must contain at least one entry"` | `""` | `email_submission.nim:586` |
| `NonEmptyOnSuccessDestroyEmail` | duplicate element | `"duplicate id or creation reference"` | duplicated ref as string | `email_submission.nim:587` |
| `NonEmptyEmailSubmissionUpdates` | empty | `"must contain at least one entry"` | `""` | `email_submission.nim:248` |
| `NonEmptyEmailSubmissionUpdates` | duplicate `Id` | `"duplicate submission id"` | offending Id | `email_submission.nim:249` |
| `NonEmptyIdSeq` | empty | `"must not be empty"` | `""` | `email_submission.nim:299` |
| `EmailSubmissionBlueprint` | invalid `identityId` | `"contains characters outside base64url alphabet"` (reached via `parseId`; blueprint accepts pre-parsed `Id` so the rejection surfaces at the `Id` boundary) | offending raw | `validation.nim:273` (via `parseId`) |
| `EmailSubmissionBlueprint` | invalid `emailId` | `"contains characters outside base64url alphabet"` (same path) | offending raw | `validation.nim:273` (via `parseId`) |

**Implementation note** for the bottom rows:

- `NonEmptyEmailSubmissionUpdates`, `NonEmptyIdSeq` — local
  `err(validationError(...))` literals in `email_submission.nim` at
  the cited lines.
- `EmailSubmissionBlueprint` per-field —
  `parseEmailSubmissionBlueprint` accepts pre-parsed `Id` values
  (`email_submission.nim:152-161`), so there is no blueprint-level
  `ValidationError` literal. The authoritative strings live in the
  `toValidationError(TokenViolation)` translator at
  `validation.nim:255-274`; tests pin via
  `parseId("bad@identity").error.message`, not via the blueprint
  constructor. Mirrors F2 §8.3's policy.

**Per-concept file table:**

| File | Scope |
|------|-------|
| `tests/unit/mail/temail_submission_blueprint.nim` (166L) | Sealed-blueprint construction (Pattern A) and per-field rejection. `parseEmailSubmissionBlueprint` accepts pre-parsed `Id` values (`email_submission.nim:152-161`), so malformed identityId/emailId rejection surfaces at the upstream `parseId` boundary. `block` names: `symbolsExported` (19), `minimalBlueprint` (23), `accessorContract` (34), `sealingContract` (45), `blueprintWithEnvelope` (67), `defaultEnvelopeIsNone` (80), `inequalityOnIdentity` (86), `blueprintInvalidIdentityId` (94), `blueprintInvalidEmailId` (105), `blueprintAccumulatesBothIdErrors` (113), `blueprintPatternASealExplicitRawField` (142). |
| `tests/unit/mail/tonsuccess_extras.nim` (157L) | Empty-rejection, duplicate-rejection, arm-distinctness, happy-path construction, `toJson` wire shape, and `IdOrCreationRef` vs `Referencable[T]` distinctness for the two compound `onSuccess*` extras. `block` names (six lettered sections): A — `parseNonEmptyOnSuccessUpdateEmailRejectsEmpty` (28), `parseNonEmptyOnSuccessDestroyEmailRejectsEmpty` (36); B — `parseNonEmptyOnSuccessUpdateEmailRejectsDuplicateKey` (45), `parseNonEmptyOnSuccessDestroyEmailRejectsDuplicateElement` (53); C — `parseNonEmptyOnSuccessUpdateEmailAcceptsArmDistinctSamePayload` (62), `parseNonEmptyOnSuccessDestroyEmailAcceptsArmDistinctSamePayload` (75); D — `parseNonEmptyOnSuccessUpdateEmailHappyPath` (83), `parseNonEmptyOnSuccessDestroyEmailHappyPath` (88); E — `toJsonNonEmptyOnSuccessUpdateEmailDirectKey` (94), `toJsonNonEmptyOnSuccessUpdateEmailCreationKey` (106); F — `toJsonNonEmptyOnSuccessDestroyEmailEmitsWireKeyArray` (116); G — `idOrCreationRefWireDirectIsBareString` (128), `idOrCreationRefWireCreationHasHashPrefix` (137), `idOrCreationRefVsReferencableAreDistinctTypes` (145). |
| `tests/unit/mail/temail_submission.nim` (146L) | Per-phantom-variant construction via `toAny`; value-level `cancelUpdate` discriminator; `static:` block proving `cancelUpdate(default(EmailSubmission[usFinal]))` and `cancelUpdate(default(EmailSubmission[usCanceled]))` fail to compile (the single most load-bearing compile-time test in G2); `existentialBranchAccessorContract` pins Pattern A sealing — accessor visibility, compile-time refusal of `raw*` and historical public-name brace construction, and the 3 × 3 `Opt[T]` projection matrix. `block` names: `toAnyPendingBranchPreserved` (24), `toAnyFinalBranchPreserved` (39), `toAnyCanceledBranchPreserved` (51), `cancelUpdateProducesSetUndoStatusToCanceled` (63), `phantomArrowStaticRejectsFinalAndCanceled` (78), `existentialBranchAccessorContract` (93). |
| `tests/unit/mail/temail_submission_update.nim` (79L) | `setUndoStatusToCanceled()` discriminator pin; `parseNonEmptyEmailSubmissionUpdates` empty and duplicate-`Id` rejection (message strings grep-locked per §8.3's error-rail table); single-entry happy path. `block` names: `setUndoStatusToCanceledValueShape` (24), `parseUpdatesRejectsEmpty` (38), `parseUpdatesRejectsDuplicateId` (49), `parseUpdatesHappyPathSingleEntry` (63). |
| `tests/unit/mail/tsubmission_params.nim` (380L) | One block per `SubmissionParamKind` (§8.7 matrix), the NOTIFY mutual-exclusion rule, the `SubmissionParamKey` identity matrix (12² × extension-name partition), `paramKey` derivation totality, and three fixed insertion sequences asserting `toJson(SubmissionParams)` preserves wire-key order. `block` names (in source order): `submissionParamBodyValidEncodings` (55), `submissionParamSmtpUtf8Nullary` (66), `submissionParamSizeAcceptsZeroAndUpperBound` (73), `submissionParamEnvidStoresInputBytesUnchanged` (94), `submissionParamRetFullAndHdrs` (103), `submissionParamNotifyValidShapes` (113), `submissionParamOrcptParserPath` (129), `submissionParamHoldForInfallibleWrap` (145), `submissionParamHoldUntilParserPath` (157), `submissionParamByDeadlineAndMode` (173), `submissionParamMtPriorityRangeBoundary` (186), `submissionParamExtensionWithKeywordAndOptValue` (204), `submissionParamNotifyMutualExclusionAndEmptyRejection` (230), `submissionParamKeyIdentityDiscriminatorMatrix` (267), `submissionParamKeyExtensionNamePartitions` (287), `paramKeyDerivationTotality` (309), `submissionParamsToJsonPreservesDeclarationOrder` (324), `submissionParamsToJsonPreservesReverseOrder` (344), `submissionParamsToJsonPreservesShuffledOrderWithExtension` (363). |
| `tests/unit/mail/tsubmission_mailbox.nim` (215L) | `RFC5321Mailbox` strict parser representatives across local-part × domain-form shapes; strict/lenient divergence cases; case-insensitive `RFC5321Keyword` equality and byte-equal `OrcptAddrType` equality with cross-type compile-time distinctness via `assertNotCompiles`. `block` names: `mailboxDotStringPlainDomain` (34), `mailboxDotStringIPv4Literal` (43), `mailboxDotStringIPv6Literal` (58), `mailboxDotStringGeneralLiteral` (73), `mailboxQuotedPlainDomain` (95), `mailboxQuotedIPv6Literal` (112), `mailboxStrictLenientSupersetOnPlainDomain` (127), `mailboxStrictLenientSupersetOnMalformedLocalPart` (141), `rfc5321KeywordCaseInsensitive` (163), `orcptAddrTypeByteEqual` (188). |
| `tests/unit/mail/tsubmission_status.nim` (246L) | `DeliveredState` and `DisplayedState` round-trip per variant including raw-backing preservation; `ParsedSmtpReply` happy-path surface (single-line, multi-line, RFC 3463 enhanced-status-code) plus the H24 canonicalisation contract for `renderSmtpReply` (LF round-trip on canonical input; CRLF normalisation to LF on the wire emit while `raw` preserves the ingress bytes); `DeliveryStatus` composite construction; `DeliveryStatusMap` `countDelivered` and `anyFailed` over three hand-constructed maps. `block` names: `deliveredStateQueuedRoundTrip` (28), `deliveredStateYesRoundTrip` (38), `deliveredStateNoRoundTrip` (47), `deliveredStateUnknownRoundTrip` (57), `deliveredStateOtherPreservesRawBacking` (67), `displayedStateYesRoundTrip` (83), `displayedStateUnknownRoundTrip` (92), `displayedStateOtherPreservesRawBacking` (100), `smtpReplyHappy200` (115), `smtpReplyHappy550` (125), `smtpReplyMultilineHappy` (135), `smtpReplyEnhancedCodeHappy` (147), `renderCanonicalReplyIsIdempotent` (162), `renderCrlfInputCanonicalisesToLf` (168), `deliveryStatusComposite` (181), `deliveryStatusMapCountDelivered` (201), `deliveryStatusMapAnyFailedFalseWhenAllDelivered` (221), `deliveryStatusMapAnyFailedTrueWhenOneFailed` (233). |
| `tests/serde/mail/tserde_submission_envelope.nim` (330L) | Full parameter-family serde coverage — all 12 families (BODY, SIZE, NOTIFY, ORCPT, extension + ENVID, RET, HOLDFOR, HOLDUNTIL, BY, MT-PRIORITY, SMTPUTF8); `ReversePath` case object toJson/fromJson per arm (positive round-trip for `rpkNullPath` with and without params; `rpkMailbox` with and without params); the G34 distinction `Opt.none(SubmissionParams)` vs `Opt.some(emptyParams)` round-trip. `block` names: `roundTripEnvelopeWithRichParameters` (22), `nullReversePathWireShape` (84), `emptyRcptToIsRejected` (110), `paramEnvidAndRetRoundTrip` (122), `paramHoldForAndHoldUntilRoundTrip` (153), `paramByAndMtPriorityAndSmtpUtf8RoundTrip` (186), `reversePathNullWithParamsRoundTrip` (223), `reversePathMailboxWithoutParamsRoundTrip` (257), `parametersOptNoneDistinctFromEmptyObject` (292). |
| `tests/serde/mail/tserde_submission_status.nim` (174L) | `UndoStatus` round-trip per variant; closed-enum gate (`"deferred"` → `svkEnumNotRecognised`, pinning G3); `DeliveryStatus` composite round-trip (including `Parsed*` raw-backing fields and an unknown delivered/displayed state pair); `DeliveryStatusMap` round-trip; the H24 CRLF→LF canonicalisation on `DeliveryStatus.toJson`. `block` names: `undoStatusPendingRoundTrip` (27), `undoStatusFinalRoundTrip` (37), `undoStatusCanceledRoundTrip` (45), `undoStatusUnknownIsRejected` (55), `deliveryStatusRoundTrip` (69), `deliveryStatusMapRoundTripPreservesOrder` (101), `deliveryStatusToJsonCanonicalisesSmtpReplyLineEndings` (162). |
| `tests/serde/mail/tserde_email_submission.nim` (392L) | `AnyEmailSubmission` dispatch round-trip — one block per phantom variant, confirming the wire-`undoStatus` field drives `fromJson` dispatch; `EmailSubmissionBlueprint` toJson-only wire shape (no `fromJson` defined); `EmailSubmissionFilterCondition` toJson-only sparse emission and the `NonEmptyIdSeq` empty-list rejection (G18, G37); `EmailSubmissionComparator` pinning the `"sentAt"` wire-token vs `sendAt` field-name mismatch (G19); `IdOrCreationRef` toJson per arm; the full `SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission]` envelope round-trip plus the two server-divergence shapes (Stalwart-style `{"id": "<id>"}` only and HOLDFOR-style `{"id", "sendAt", "undoStatus"}`). `block` names: `anyEmailSubmissionPendingRoundTrip` (43), `anyEmailSubmissionFinalRoundTrip` (73), `anyEmailSubmissionCanceledRoundTrip` (103), `blueprintToJsonOnlyNoFromJson` (148), `blueprintOptNoneEnvelopePassesThrough` (165), `filterConditionAllFieldsPopulated` (184), `filterConditionOnlyUndoStatus` (210), `filterConditionRejectsEmptyIdSeq` (232), `comparatorSentAtTokenNotSendAt` (245), `comparatorAscendingByEmailId` (261), `idOrCreationRefDirectWire` (278), `idOrCreationRefCreationWire` (287), `emailSubmissionSetResponseEntityRoundTrip` (297), `emailSubmissionCreatedItemUndoStatusAbsent` (372), `emailSubmissionCreatedItemUndoStatusPending` (385). |

---

### 8.4. Existing-file appends

| File | Additions |
|------|-----------|
| `tests/protocol/tmail_builders.nim` (1057L) | The five simple builders: `addEmailSubmissionGetInvocation` (§P, line 955), `addEmailSubmissionChangesInvocation` (§Q, 978), `addEmailSubmissionQueryInvocation` (§R, 997), `addEmailSubmissionQueryChangesInvocation` (§S, 1016), `addEmailSubmissionSetSimpleInvocation` (§T, 1035) — one `block` per method with a wire-shape assertion table. The compound builder block `addEmailSubmissionAndEmailSetWireAnchor` (§O.1, line 736) anchors the wire shape; the `getBoth` cross-entity matrix (§8.6) follows as unit-tier representatives: `getBothBothSucceed` (§O.2, line 775), `getBothInnerMethodError` (§O.3, 808), `getBothInnerAbsent` (§O.4, 832), `getBothInnerMcIdMismatch` (§O.5, 851), `getBothOuterNotCreatedSole` (§O.6, 881), `getBothOuterIfInStateMismatch` (§O.7, 927). The seventh cross-entity scenario (`getBothCreationRefNotInCreateMap`) lives only in `tadversarial_mail_g.nim` Block 6; no unit-tier analogue exists in this file. |
| `tests/protocol/tmail_entities.nim` (348L) | One new block: `emailSubmissionEntityRegisteredWithSubmissionCapability` (line 326) anchors the capability URI (`urn:ietf:params:jmap:submission`), method namespace (`EmailSubmission/*`), and `toJson(EmailSubmissionFilterCondition)` surface. Mirrors the existing `Mailbox` / `Email` / `Identity` entity blocks. |
| `tests/protocol/tmail_method_errors.nim` (566L) | `emailSubmissionSetMethodErrorSurface` (line 381) covers submission-specific `MethodError` surface (e.g., `accountNotFound`, `stateMismatch`); the per-variant §8.8 applicability blocks — `emailSubmissionSetInvalidEmailOnCreate` (412), `emailSubmissionSetTooManyRecipientsOnCreate` (427), `emailSubmissionSetNoRecipientsOnCreate` (440), `emailSubmissionSetInvalidRecipientsOnCreate` (448), `emailSubmissionSetForbiddenMailFromOnCreate` (459), `emailSubmissionSetForbiddenFromOnCreate` (467), `emailSubmissionSetForbiddenToSendOnCreate` (475), `emailSubmissionSetTooLargeOnCreate` (483), `emailSubmissionSetCannotUnsendOnUpdate` (498) — and the singleton-not-emittable pins for create and update (`emailSubmissionSetSingletonParsesButNotEmittableOnCreate` at 521 and `…OnUpdate` at 529), plus the closing `emailSubmissionSetErrorApplicabilityExhaustiveFold` (548). The 8 SetError variants' existence is classified in `trfc_8620.nim`; this file drives applicability. |
| `tests/serde/mail/tserde_mail_capabilities.nim` (418L) | `SubmissionExtensionMap` distinct-wrapper round-trip per G25. Case-insensitive key behaviour (`"X-FOO"` and `"x-foo"` collide as the same key under `RFC5321Keyword` equality). A legacy-wire-shape probe pins forwards-compat. `block` names: `submissionExtensionMapRoundTripPreservesOrder` (line 342), `submissionExtensionMapCaseInsensitiveKey` (366), `submissionExtensionMapParsesLegacyWireShape` (396). |
| `tests/compliance/trfc_8620.nim` (1851L) | `rfc8621Section7ConstraintTableCompileTimeAnchor` (line 1756) anchors the RFC 8621 §7 constraint table — a compile-time `static:` assertion per row of G1 §1.4 plus a positive-and-negative `compiles(cancelUpdate(...))` walk for the typed phantom-arrow (lines 1801–1803). The pre-existing `rfc8621_submissionErrorsClassified` block at line 953 pins three of the eight submission-specific `SetError` variants via `parseSetErrorType`; the `static:` block above pins every type-level row, with the SetError enum-value rows (`setInvalidEmail`, `setTooManyRecipients`, `setNoRecipients`, `setInvalidRecipients`, `setForbiddenMailFrom`, `setForbiddenFrom`, `setForbiddenToSend`, `setCannotUnsend`) at `declared()` precision. |

---

### 8.5. Phantom-type state-transition matrix

(Unique to G2 — F2 had no analogue because F1 has no phantom types.)

G1 §4.1–§4.3 commits to three `EmailSubmission[S]` phantom
instantiations plus an `AnyEmailSubmission` existential wrapper.
The type system enforces that `cancelUpdate` accepts only the
`usPending` branch; the compiler rejects `usFinal` and `usCanceled`
inputs. This matrix enumerates every operation × state pair and the
expected outcome at the level the enforcement lives (compile time vs
runtime). The number of rows is small — three typed-arrow rows plus two
existential-dispatch rows — because `cancelUpdate` is the sole typed
transition helper (G4) and the closed `UndoStatus` enum caps the phantom
space at three.

| From state | Operation | Expected | Test site |
|------------|-----------|----------|-----------|
| `EmailSubmission[usPending]` | `cancelUpdate(s)` | ✅ compiles | `temail_submission.nim` `cancelUpdateProducesSetUndoStatusToCanceled` (line 63) |
| `EmailSubmission[usFinal]` | `cancelUpdate(s)` | ❌ `assertNotCompiles` | `temail_submission.nim` `static:` block `phantomArrowStaticRejectsFinalAndCanceled` (line 78) |
| `EmailSubmission[usCanceled]` | `cancelUpdate(s)` | ❌ `assertNotCompiles` | Same block |
| `AnyEmailSubmission.asPending()` | projection when `state == usPending` | ✅ `Opt.some` with payload preserved | `temail_submission.nim` `toAnyPendingBranchPreserved` (line 24) |
| `AnyEmailSubmission.asFinal()` / `asCanceled()` | projection when `state == usPending` | `Opt.none` (the same accessor on a non-matching state); module-private `raw*` fields cannot be read externally | `temail_submission.nim` `existentialBranchAccessorContract` (line 93) — pins accessor visibility, compile-time refusal of `raw*` brace construction, and the 3 × 3 `Opt[T]` projection matrix |

The existential-dispatch row is compile-time enforced at the API
surface: the branch fields are module-private
(`rawPending`/`rawFinal`/`rawCanceled`) and external consumers read
via the `asPending`/`asFinal`/`asCanceled` accessor family. Wrong-
branch field access is not writable at the call site — a regression
would need to either touch the case-object fields inside the
`email_submission` module itself or break the `Opt[T]` return-type
shape. The test block does not attempt `doAssertRaises(FieldDefect)`:
under `--panics:on` (project default, `config.nims:24`) `FieldDefect`
is fatal (`rawQuit(1)`, no unwinding, no `finally`), so the runtime
exception path is unreachable as well as uncatchable. The block pins
the stronger compile-time contract via `assertNotCompiles` +
`Opt.none` shape probes.

Reference G1 §4.1–§4.3 for the decision rationale (GADT-style phantom
encoding + existential wrapper, chosen over flat record + runtime
switch). Do not restate the rationale here — the matrix is a test
anchor, not a design restatement.

---

### 8.6. Cross-entity `getBoth` coherence matrix

(Unique to G2 — F2's `getBoth(EmailCopyHandles)` was same-entity.)

F1's `EmailCopyHandles` spans two calls within the same entity
namespace (`Email/copy` + implicit `Email/set destroy`). G1's
`EmailSubmissionHandles` spans **two entity namespaces**
(`EmailSubmission/set` + implicit `Email/set` via `onSuccessUpdateEmail`
/ `onSuccessDestroyEmail`). The failure modes are strictly richer:
the inner response may come from a different entity's routing table,
may be absent entirely (RFC §7.5 permits omission when no `onSuccess*`
target created), or may share method-call-id space with unrelated
invocations. This matrix enumerates the coherence scenarios.

Each row is one named test, realised as a block in
`tests/stress/tadversarial_mail_g.nim` (the full adversarial cases with
wire fixtures) and as a unit-tier representative in
`tests/protocol/tmail_builders.nim` §O.2–O.7 (each block fixes a single
method-level response and asserts the `getBoth` outcome).

| # | Scenario | Outer `EmailSubmission/set` | Inner `Email/set` | `getBoth` result |
|---|----------|-----------------------------|-------------------|------------------|
| 1 | Both present, both succeed | `ok` + `created` populated | `ok` + corresponding update/destroy | `Ok(EmailSubmissionResults{submission, emailSet})` |
| 2 | Outer succeeds, inner `MethodError` | `ok` | `Err(accountNotFound)` | `Err(methodError)` — surfaces inner error; the chained `?` propagates through |
| 3 | Outer succeeds, inner absent from response | `ok` | (no invocation in response) | `Err(serverFail)` — the generic `getBoth[A, B]` chains `?` on `dr.get(handles.implicit)`, so absence surfaces as a `MethodError(metServerFail)` with description `"no Email/set response for call ID …"` |
| 4 | Outer succeeds, inner present but `methodCallId` mismatch | `ok` | `ok` but under wrong `methodCallId` | `Err(serverFail)`-like — surfaces as a server-routing error; documents that `NameBoundHandle.callId` must match |
| 5 | Outer `notCreated` sole entry | `ok` but `notCreated` non-empty | (server emits an empty `Email/set` invocation at the shared call-id under RFC 8621 §7.5 ¶3 "if any implicit actions attempted" wording) | `Ok` with `r.primary.createResults` carrying an `Err` entry and `r.implicit.createResults` empty — `getBoth` does not synthesise an empty inner; the absent-inner case (no `Email/set` invocation at all) is row 3's shape |
| 6 | Outer `ifInState` mismatch `stateMismatch` | `Err(stateMismatch)` | (no invocation) | `Err` — inner never reached; the outer error short-circuits the chained `?` |
| 7 | `onSuccessUpdateEmail` uses `creationRef(cid)` where `cid` is not in outer `create` map | `Ok` | server-side error expected | Pin: wire shape must validate regardless (client-side contract check); the client does not pre-validate creation-ref resolution — that is a server responsibility |

Rows 3 and 4 are the structurally novel scenarios that F2's analogue
did not need to cover. Row 3 ("inner absent") is the common case when
the outer succeeds but produces no target for the inner's update /
destroy (e.g., `onSuccessDestroyEmail = none`, `onSuccessUpdateEmail =
none` — the server correctly omits the inner invocation entirely).
Row 4 ("mcId mismatch") is the adversarial case where the server's
method-routing layer drops or duplicates an invocation, producing a
response with the wrong method-call-id; `getBoth` must detect this
rather than silently returning stale data.

---

### 8.7. Submission parameter coverage matrix

(Unique to G2 — F1 has no analogous complex typed-payload algebra.)

Per-family rejection and acceptance table; one row per
`SubmissionParamKind` × representative boundary. Each row corresponds
to one unit block in `tests/unit/mail/tsubmission_params.nim`; the
matrix drives the file layout.

| Kind | Valid representative | Invalid representative | Rule source |
|------|----------------------|------------------------|-------------|
| `spkBody` | `"7BIT"`, `"8BITMIME"`, `"BINARYMIME"` | `"BASE64"` | `BodyEncoding` closed enum (G8b) |
| `spkSmtpUtf8` | (no payload — `smtpUtf8Param()` nullary) | unexpected payload on wire | `discard` arm in `SubmissionParam` case object |
| `spkSize` | `0`, `2^53 − 1` | negative (compile-time blocked by `UnsignedInt`), non-numeric wire | `UnsignedInt` type (primitives.nim) |
| `spkEnvid` | ≤ 106 octets, plain UTF-8 (xtext decoding is server-side per G1 §7.2 resolved note) | empty | RFC 3461 §4.4 |
| `spkRet` | `"FULL"`, `"HDRS"` | `"SOMETHING"` | `DsnRetType` closed enum |
| `spkNotify` | `{dnfSuccess}`, `{dnfFailure, dnfDelay}`, `{dnfNever}` | `{dnfNever, dnfSuccess}` | Mutual exclusion per G1 §2.3; message `"NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY"` |
| `spkOrcpt` | `(parseOrcptAddrType("rfc822").get(), "alice@example.com")` | empty `addrType`, invalid `addrType` (bad first char, trailing hyphen beyond `esmtp-keyword` grammar) | `OrcptAddrType` byte-equal + `esmtp-keyword` grammar |
| `spkHoldFor` | `parseHoldForSeconds(UnsignedInt(600)).get()` | `parseHoldForSeconds(...)` with wire-invalid value; negative blocked by `UnsignedInt` at construction | `HoldForSeconds` smart ctor |
| `spkHoldUntil` | valid `UTCDate` (e.g., `2026-04-22T12:00:00Z`) | malformed ISO-8601 | `UTCDate` (primitives.nim) smart ctor |
| `spkBy` | `(JmapInt(123), dbmReturn)` deadline + mode | mode outside `{R, N, RT, NT}` | `DeliveryByMode` closed enum |
| `spkMtPriority` | `-9`, `0`, `+9` | `-10`, `+10` | `MtPriority` smart ctor; message `"must be in range -9..9"` |
| `spkExtension` | `(parseRFC5321Keyword("X-VENDOR-FOO").get(), Opt.some("bar"))` | invalid keyword chars (e.g., leading hyphen, space) | `RFC5321Keyword` parser |

One row = one `block` in `tsubmission_params.nim`; matrix drives the
file layout. The load-bearing row is `spkNotify` (mutual exclusion) —
the only variant with a cross-field invariant. All other rows are
per-field boundary tests using the existing `UnsignedInt` / `Id` /
`UTCDate` smart-ctor infrastructure.

The `spkBody`, `spkRet`, `spkBy` rows each exercise the closed-enum
decoding path. The serde layer routes those tokens through
`parseEnumByBackingString[E]` (`serde_submission_envelope.nim:147`),
which yields a `ValidationError` (`"unrecognised value"`) wrapped at
the field path as `svkFieldParserFailed`. The closed-enum dispatch
on the wire `undoStatus` token uses a different path
(`parseUndoStatus`, `serde_submission_status.nim:37-56`), which
emits `svkEnumNotRecognised` directly.

---

### 8.8. `SetError` applicability matrix (G1-specific)

Mirrors F2 §8.11 in structure, calibrated to the 9 submission-relevant
`SetError` variants (8 submission-specific plus standard `tooLarge`).
Critical framing: this is **applicability** (which error applies where),
not **existence** (already tested in `tmail_errors.nim` and pinned in
`tests/compliance/trfc_8620.nim` via the
`rfc8621_submissionErrorsClassified` block). G23 / G24 committed to no
new variants and no new accessors, so this matrix enumerates where each
existing variant is exercised on the submission methods.

| `SetError` variant | RFC citation | Applicable to `/set create` | Applicable to `/set update` | Test site |
|-------------------|--------------|-----------------------------|-----------------------------|-----------|
| `setInvalidEmail` | §7.5 ¶5 | ✓ | ✗ | `tmail_method_errors.nim` append (invocation-level); existence in `trfc_8620.nim` |
| `setTooManyRecipients` | §7.5 ¶5 | ✓ | ✗ | Reuse; one named test per method |
| `setNoRecipients` | §7.5 ¶5 | ✓ | ✗ | Reuse |
| `setInvalidRecipients` | §7.5 ¶5 | ✓ | ✗ | Reuse |
| `setForbiddenMailFrom` | §7.5 ¶5 | ✓ | ✗ | Reuse |
| `setForbiddenFrom` | §7.5 ¶5 | ✓ | ✗ | Reuse |
| `setForbiddenToSend` | §7.5 ¶5 | ✓ | ✗ | Reuse |
| `setTooLarge` | §7.5 ¶3 | ✓ | ✗ | Reuse (existence already classified; applicability pin needed in `tmail_method_errors.nim`) |
| `setCannotUnsend` | §7.5 ¶6 | ✗ | ✓ | `emailSubmissionSetCannotUnsendOnUpdate` (`tmail_method_errors.nim:498`) — pending → canceled refused when server determines unsend impossible |

`setCannotUnsend` is the sole update-only applicability pin in the
matrix — every other submission-specific `SetError` variant applies
on `/set create`.

**Native enum iteration is mandatory** for this matrix. The
implementation MUST fold via `for kind in SetErrorType:` (precedent:
`terrors.nim:428` and F2 §8.11). No helper combinator is introduced.
The explicit loop makes the variant set visible at the call site and
the compiler enforces exhaustiveness via `case` inside the loop body.

---

### 8.9. Infrastructure additions (fixtures, generators, assertions)

Mirrors F2 §8.6. Additions only — **no new test-support modules**.

Submission-type factories, generators, and assertion helpers live in
`tests/mfixtures.nim`, `tests/mproperty.nim`, and
`tests/massertions.nim` alongside their precedents from earlier
parts. Low-volume per-concept files construct fixtures inline using
the public smart constructors; a factory is extracted when a
construction recipe is repeated across three or more blocks.

#### 8.9.1. Reuse-mapping table

Each factory / generator / assertion template lists its closest
existing precedent. Format matches F2 §8.6.1.

| New item | Closest existing precedent | Path:Line |
|----------|---------------------------|-----------|
| `makeRFC5321Mailbox(raw = "user@example.com")` (`mfixtures.nim:2043`), `makeFullRFC5321Mailbox()` (`mfixtures.nim:2046`) — quoted-string local-part + IPv6 address-literal | `makeAccountId` / `makeFullAccountId` (identifier-shaped factories) | `mfixtures.nim:71` |
| `makeRFC5321Keyword(raw = "X-VENDOR-FOO")` (`mfixtures.nim:2054`), `makeOrcptAddrType(raw = "rfc822")` (`mfixtures.nim:2057`) | Identifier-shaped factories | `mfixtures.nim:71` |
| `makeSubmissionParam(kind: SubmissionParamKind)` — dispatches on `kind` and produces a minimal typed value per variant (nullary arm returns `smtpUtf8Param()`; all others use a fixed canonical payload) | `makeSetErrorInvalidProperties` / `makeSetErrorAlreadyExists` (per-variant naming for case-object factories) | `mfixtures.nim:2062` (precedent at `mfixtures.nim:315,321`) |
| `makeFullSubmissionParams()` populated with one of each of the 11 well-known variants plus one `spkExtension` | `makeFullEmailBlueprint` (composite populated factory) | `mfixtures.nim:2089` (precedent at `mfixtures.nim:1184`) |
| `makeSubmissionAddress(mailbox = makeRFC5321Mailbox())` (`mfixtures.nim:2113`), `makeFullSubmissionAddress()` (`mfixtures.nim:2119`, fully parameterised via `makeFullSubmissionParams()`) | `makeEmailAddress` | `mfixtures.nim:1011` |
| `makeNullReversePath()` (`mfixtures.nim:2135`, infallible wrapper over `nullReversePath()`), `makeMailboxReversePath(addr = makeSubmissionAddress())` (`mfixtures.nim:2140`) | No direct precedent — wraps the L1 infallible ctor | — |
| `makeEnvelope(mailFrom = makeMailboxReversePath(), rcptTo = @[makeSubmissionAddress()])` (`mfixtures.nim:2152`), `makeFullEnvelope()` (`mfixtures.nim:2158`) | `makeFullEmailBlueprint` composite style | `mfixtures.nim:1184` |
| `makeNonEmptyRcptList(items = @[makeSubmissionAddress()])` | `makeNonEmptyMailboxIdSet(ids)` | `mfixtures.nim:2147` (precedent at `mfixtures.nim:1099`) |
| `makeEmailSubmission[S: static UndoStatus](...)` — generic fixture returning `EmailSubmission[S]`; callers pass `usPending`/`usFinal`/`usCanceled` | No direct precedent — phantom-parameter-generic factory | `mfixtures.nim:2202` |
| `makeAnyEmailSubmission(state: UndoStatus)` — returns `AnyEmailSubmission` with the branch matching `state` populated | Per-variant case-object factory | `mfixtures.nim:2225` |
| `makeEmailSubmissionBlueprint(identityId, emailId, envelope = Opt.none(Envelope))` (`mfixtures.nim:2234`), `makeFullEmailSubmissionBlueprint()` (`mfixtures.nim:2244`, with envelope + params) | `makeEmailBlueprint` / `makeFullEmailBlueprint` | `mfixtures.nim:1178,1184` |
| `makeDeliveryStatus(smtpReply, delivered, displayed)` (`mfixtures.nim:2175`), `makeSmtpReply(raw = "250 OK")` (`mfixtures.nim:2172`) | Composite typed-record factory | — |
| `makeDeliveryStatusMap(entries: openArray[(RFC5321Mailbox, DeliveryStatus)])` | `makeNonEmptyMailboxIdSet(ids)` (distinct-table wrapper) | `mfixtures.nim:2182` (precedent at `mfixtures.nim:1099`) |
| `makeIdOrCreationRefDirect(id)` (`mfixtures.nim:2192`), `makeIdOrCreationRefCreation(cid)` (`mfixtures.nim:2195`) | Per-variant case-object factory | `mfixtures.nim:315,321` |
| `makeEmailSubmissionHandles(submissionMcid, emailSetMcid)` | `makeEmailCopyHandles` (F1) | `mfixtures.nim:2258` (precedent at `mfixtures.nim:1893`) |
| `genRFC5321Mailbox(rng, trial)` — edge-bias trial 0 = plain `Dot-string` + `Domain`; 1 = IPv4-literal; 2 = IPv6-literal; 3 = `Quoted-string` local; 4 = General-address-literal; random from 5 | `genKeyword(rng, trial)` (edge-biased RFC-grammar generator) | `mproperty.nim:3489` (precedent at `mproperty.nim:1611`) |
| `genInvalidRFC5321Mailbox(rng, trial)` — trailing-dot, unclosed-quote, bracketless-IPv6, overlong local-part | (no `genInvalidKeyword` precedent; pattern lifted from positive generator + adversarial-mutation seq) | `mproperty.nim:3559` |
| `genRFC5321Keyword(rng, trial)` (`mproperty.nim:3431`), `genSubmissionParam(rng, trial)` (`mproperty.nim:3762`), `genSubmissionParams(rng, trial)` (`mproperty.nim:3781`) | `genSetError(rng)` (variant enumeration with edge bias) | `mproperty.nim:624` |
| `genUndoStatus(rng)` — closed enum; 3 values with equal-weight sampling | (no direct precedent — `UndoStatus` is itself closed per G3) | `mproperty.nim:3576` |
| `genDeliveredState(rng, trial)` (`mproperty.nim:3604`), `genDisplayedState(rng, trial)` (`mproperty.nim:3622`) — include `dsOther` / `dpOther` raw-backing adversarial strings at trials ≥ 5 | Open-world enum with catch-all | — |
| `genSmtpReply(rng, trial)` — digit-class edge-bias per property group I | `genBlueprintErrorTrigger` (J-11 trigger-builder pattern) | `mproperty.nim:3673` (precedent at `mproperty.nim:2740`) |
| `genEmailSubmission[S: static UndoStatus](rng, trial)` — generic generator for the phantom-typed entity | `genEmailBlueprint(rng, trial)` (trial-biased composition J-10) | `mproperty.nim:3879` (precedent at `mproperty.nim:2486`) |
| `genAnyEmailSubmission(rng, trial)` — trials 0/1/2 force `usPending`/`usFinal`/`usCanceled`; random from trial 3 | `genEmailBlueprint(rng, trial)` | `mproperty.nim:3947` (precedent at `mproperty.nim:2486`) |
| `genEmailSubmissionBlueprint(rng, trial)` (`mproperty.nim:3820`), `genEmailSubmissionUpdate(rng, trial)` (`mproperty.nim:3976`), `genEmailSubmissionFilterCondition(rng, trial)` (`mproperty.nim:4019`) | `genEmailBlueprint(rng, trial)` | `mproperty.nim:2486` |
| `assertPhantomVariantEq(actual: AnyEmailSubmission, expected: AnyEmailSubmission)` — asserts `state` field equality plus branch-dispatched payload equality | `setErrorEq` (case-object arm-dispatch equality helper) | `mfixtures.nim:717` |
| `assertDeliveryStatusMapEq(actual, expected: DeliveryStatusMap)` — ordered-table equality honouring insertion order | `nonEmptyMailboxIdSetEq` (distinct-table equality) | `mfixtures.nim:1417` |
| `assertSubmissionParamKeyEq(a, b: SubmissionParamKey)` — identity across the 12-kind matrix | `assertSetOkEq` (variant-dispatch equality wrapper) | `massertions.nim:196` |
| `assertIdOrCreationRefWire(v: IdOrCreationRef, expected: string)` — wire-form pin; `directRef(id)` → `$id`; `creationRef(cid)` → `"#" & $cid` | `assertJsonFieldEq` (wire-shape pin) | `massertions.nim:183` |

**Mandatory edge-bias schedules** (mirror F2 §8.6.1 format):

- `genRFC5321Mailbox(rng, trial)` — trials 0..4 enumerate the five
  canonical grammar shapes (plain Dot-string, IPv4, IPv6, Quoted-string,
  General-address-literal); trial 5 = overlong local-part at the
  64-octet boundary; trial 6 = overlong domain at 255-octet boundary;
  trial 7 = unicode-containing domain label. Random from trial 8.
- `genSubmissionParam(rng, trial)` — trials 0..11 enumerate the 12
  `SubmissionParamKind` values in declaration order (one per variant);
  trial 12 = `spkExtension` with an adversarial-casing keyword
  (`"X-FOO"` vs `"x-foo"`); trial 13 = `spkNotify` with
  `{dnfSuccess, dnfFailure}` (most-common payload); trial 14 =
  `spkNotify` with `{dnfNever}` (the mutual-exclusion boundary).
  Random from trial 15.
- `genAnyEmailSubmission(rng, trial)` — trials 0, 1, 2 force
  `UndoStatus.usPending`, `usFinal`, `usCanceled` respectively (one
  per variant, early-bound); random from trial 3.

#### 8.9.2. Equality-helper classification

Nim's compiler-derived `==` on case objects and plain objects is
structural for fields whose types themselves carry `==`. G1 introduces
one case object (`EmailSubmission[S]` / `AnyEmailSubmission`) plus
several distinct-table wrappers (`SubmissionParams`, `DeliveryStatusMap`,
`NonEmptyOnSuccessUpdateEmail`). The classification:

| Helper | Classification | Rationale |
|--------|----------------|-----------|
| `anyEmailSubmissionEq` | **NEEDED** | `AnyEmailSubmission` is a case object with three branches; Nim requires an explicit arm-dispatch `==` for case objects (derived `==` does not compile per the codebase-wide `nim-type-safety.md` rule). The arm-dispatched `==` lives on the type itself (`email_submission.nim:75-101`); the test wrapper is `assertPhantomVariantEq`. |
| `emailSubmissionEq[S]` | **REDUNDANT** | Plain object; derived `==` is structural across all fields (`Id`, `Opt[Envelope]`, `UTCDate`, `Opt[DeliveryStatusMap]`, `seq[BlobId]`). Phantom parameter `S` does not affect equality. |
| `submissionParamEq` | **NEEDED** | `SubmissionParam` is a case object; requires arm-dispatch. |
| `submissionParamKeyEq` | **NEEDED-trivial** | `SubmissionParamKey` is a case object with one-arm dispatch (`spkExtension` carries `extName`; all others are identity by `kind` alone). One-line implementation. |
| `submissionParamsEq` | **NEEDED-trivial** | `distinct OrderedTable[SubmissionParamKey, SubmissionParam]`; borrow `==` via `defineOrderedTableDistinctOps` (or analogous template), delegating element equality to `submissionParamEq`. |
| `envelopeEq` | **REDUNDANT** | Plain object; `ReversePath` + `NonEmptyRcptList` both derive structurally through their constituent plain-object fields. |
| `reversePathEq` | **NEEDED-trivial** | Case object with two arms; one-line arm-dispatch. |
| `submissionAddressEq` | **REDUNDANT** | Plain object; `RFC5321Mailbox` + `Opt[SubmissionParams]` both have `==`. |
| `deliveryStatusMapEq` | **NEEDED-trivial** | `distinct Table[RFC5321Mailbox, DeliveryStatus]`; borrowed `==` honouring insertion order. |
| `deliveryStatusEq` | **REDUNDANT** | Plain object; all three fields (`ParsedSmtpReply`, `ParsedDeliveredState`, `ParsedDisplayedState`) have derivable `==` (all three are plain objects). |
| `parsedSmtpReplyEq` | **REDUNDANT** | Plain object with four fields (`replyCode`, `enhanced`, `text`, `raw`); derived `==` is structural across all four. The `ReplyCode` and `EnhancedStatusCode` components carry their own `==` via `defineIntDistinctOps` and structural object equality respectively (`submission_status.nim:119-151`). |
| `idOrCreationRefEq` | **NEEDED-trivial** | Case object with two arms. One-line. |
| `emailSubmissionBlueprintEq` | **REDUNDANT** | Plain object with three fields; derived `==` is structural. The test `inequalityOnIdentity` at `temail_submission_blueprint.nim:86-92` relies on this. |
| `emailSubmissionUpdateEq` | **REDUNDANT-trivial** | Case object with exactly one (empty-payload) variant; Nim derives `==` as "equal iff both values exist". |
| `nonEmptyOnSuccessUpdateEmailEq` | **NEEDED-trivial** | `distinct Table[IdOrCreationRef, EmailUpdateSet]`; borrowed `==` delegating to `idOrCreationRefEq` + `emailUpdateSetEq` (F1 precedent). |

**Total new helpers needed:** 3 (`anyEmailSubmissionEq`, `submissionParamEq`, `submissionParamKeyEq`) plus 8 NEEDED-trivial one-liners.
Not 15; most decompose via Nim's structural derivation.

#### 8.9.3. Property trial-count calibration

Per-group assignment for §8.2.1's nine groups, mirroring F2 §8.6.3's
trial-count tier definitions (`tests/mproperty.nim:41-58`):

| Group | Per-trial cost estimate | Tier |
|-------|-------------------------|------|
| A — RFC 5321 Mailbox totality | ~5 ms (random byte seq + structural parser) | `DefaultTrials` |
| B — Strict/lenient coverage | ~8 ms (paired parser calls) | `DefaultTrials` |
| C — `SubmissionParams` insertion order | ~3 ms (build + serialise + compare order) | `DefaultTrials` |
| D — `SubmissionParamKey` identity algebra | ~1 ms (hash + eq per pair) | `DefaultTrials` |
| E — `AnyEmailSubmission` round-trip | ~4 ms (composite entity + JSON encode/decode) | `DefaultTrials` |
| F — `cancelUpdate` invariant | ~0.3 ms (single value construction) | `QuickTrials` |
| G — `NonEmptyEmailSubmissionUpdates` duplicate-Id | ~2 ms (map construction + error count) | `DefaultTrials` |
| H — `ParsedDeliveredState.rawBacking` preservation | ~1 ms (parse + re-emit) | `DefaultTrials` |
| I — `parseSmtpReply` digit boundary | ~2 ms (Reply-code digit sweep) | `DefaultTrials` |

Group F is the sole `QuickTrials` group — predicate is cheap and any
divergence surfaces in the first handful of trials. This matches F2
Group F's placement. **Do not promote F to `DefaultTrials`** — the
`Id`-charset coverage gained from 500 vs 200 trials is marginal for a
value-level pin of a phantom-constrained helper, and the compile-time
`assertNotCompiles` block is the authoritative type-level test.

**`CrossProcessTrials` applicability.** `CrossProcessTrials` (100)
exists for tests that `exec` a sibling process and compare byte output.
Part G adds **none** — the distinct-seq / distinct-OrderedTable design
of `NonEmptyEmailSubmissionUpdates`, `SubmissionParams`,
`NonEmptyRcptList`, and `DeliveryStatusMap` (keyed on
`RFC5321Mailbox`, iterated in insertion order) means `toJson` output is
a function of input alone, with no hash-seed input path. The tier
remains available in `mproperty.nim` for future parts; G groups do not
consume it.

---

### 8.10. RFC 8621 §7 constraint traceability matrix

Copies G1 §1.4's constraint table with a fourth "Test site" column
identifying which file locks each constraint. 27 rows. Mirrors F2 §8.12
in role — the single-inspection point for "is every RFC constraint
pinned by a test?". New G-part promises added by future G3/G4/... parts
MUST add a row here before the implementation merges.

| RFC ref | Constraint | Nim type | Test site |
|---------|-----------|----------|-----------|
| §7 ¶3 | `identityId` MUST reference a valid Identity in the account | `Id` (referential; server-authoritative) | `tserde_email_submission.nim` blueprint round-trip — client cannot enforce server-side referential integrity; only the structural `Id` shape |
| §7 ¶3 | `emailId` MUST reference a valid Email in the account | `Id` | Same as above |
| §7 ¶3 | `threadId` is immutable, server-set | Not in `EmailSubmissionBlueprint`; only on read model | `temail_submission_blueprint.nim` blocks pin absence (no field on the blueprint); `tserde_email_submission.nim` pins presence on the read-model round-trip |
| §7 ¶4 | `envelope` is immutable; if null, server synthesises from Email headers | `Opt[Envelope]` on blueprint (G14); `Opt[Envelope]` on entity | `tserde_email_submission.nim` `blueprintOptNoneEnvelopePassesThrough` (line 165); `temail_submission_blueprint.nim` `defaultEnvelopeIsNone` (line 80) |
| §7 ¶5 | `envelope.mailFrom` cardinality: exactly 1; MAY be empty string; parameters permitted on null path | `ReversePath` (`rpkNullPath + Opt[SubmissionParams]` or `rpkMailbox`) (G32) | `tserde_submission_envelope.nim` `nullReversePathWireShape` (line 84); `envelopeNullMailFromWithParams` in `tadversarial_mail_g.nim` `envelopeCoherenceGroup` (line 176) |
| §7 ¶5 | `envelope.rcptTo` cardinality: 1..N | `NonEmptyRcptList` (G7) | `tserde_submission_envelope.nim` `emptyRcptToIsRejected` (line 110) |
| §7 ¶5 | `envelope.Address.email` is RFC 5321 Mailbox | `RFC5321Mailbox` (G6) | `tsubmission_mailbox.nim` (blocks lines 34–188); `propRFC5321MailboxTotality` (`tprop_mail_g.nim:54`) |
| §7 ¶5 | `envelope.Address.parameters` is `Object \| null` | `Opt[SubmissionParams]` on `SubmissionAddress` (G34) | `tserde_submission_envelope.nim` `parametersOptNoneDistinctFromEmptyObject` (line 292) |
| §7 ¶5 | `envelope.Address.parameters` keys are RFC 5321 esmtp-keywords | `SubmissionParamKey` + `RFC5321Keyword` (G8, G8a) | `tsubmission_params.nim` `paramKeyDerivationTotality` (line 309); property group D `propSubmissionParamKeyIdentity` (`tprop_mail_g.nim:154`) |
| §7 ¶7 | `undoStatus` values: "pending", "final", "canceled" | `UndoStatus` enum (closed; phantom parameter) (G3) | `tserde_submission_status.nim` `undoStatusUnknownIsRejected` (line 55); `anyUndoStatusUnknownValue` in `tadversarial_mail_g.nim` `anyEmailSubmissionDispatchGroup` (line 295) |
| §7 ¶7 | Only transition: "pending" → "canceled" via client update | `cancelUpdate(s: EmailSubmission[usPending])` typed arrow (G4) | `temail_submission.nim` `static:` block `phantomArrowStaticRejectsFinalAndCanceled` (line 78) — the load-bearing compile-time pin; also pinned in `trfc_8620.nim` constraint-anchor block (lines 1801–1803) |
| §7 ¶8 | `deliveryStatus` is per-recipient, keyed on email address | `DeliveryStatusMap` (distinct Table keyed on `RFC5321Mailbox`) (G9) | `tsubmission_status.nim` `deliveryStatusMapCountDelivered` (line 201) etc.; `tserde_submission_status.nim` `deliveryStatusMapRoundTripPreservesOrder` (line 101) |
| §7 ¶8 | `delivered` values: "queued", "yes", "no", "unknown" | `DeliveredState` enum + `dsOther` catch-all (G10) | `tsubmission_status.nim` per-variant round-trip blocks `deliveredStateQueuedRoundTrip`–`deliveredStateOtherPreservesRawBacking` (lines 28–67); property group H `propParsedDeliveredStateRawBackingRoundTrip` (`tprop_mail_g.nim:306`) |
| §7 ¶8 | `displayed` values: "unknown", "yes" | `DisplayedState` enum + `dpOther` catch-all (G11) | `tsubmission_status.nim` `displayedState*` blocks (lines 83–100); property group H symmetric |
| §7 ¶8 | `smtpReply` is structured SMTP reply text | `ParsedSmtpReply` (record carrying `replyCode`, `enhanced`, `text`, `raw`) (G12) | `tsubmission_status.nim` `smtpReplyHappy200` (line 115), `smtpReplyHappy550` (125), `smtpReplyMultilineHappy` (135), `smtpReplyEnhancedCodeHappy` (147), `renderCanonicalReplyIsIdempotent` (162), `renderCrlfInputCanonicalisesToLf` (168); property group I `propParseSmtpReplyDigitBoundary` (`tprop_mail_g.nim:358`); adversarial `smtpReplyGrammarGroup` (`tadversarial_mail_g.nim:350`) |
| §7 ¶9 | `dsnBlobIds`, `mdnBlobIds` are server-set arrays | `seq[BlobId]` on read model only | `tserde_email_submission.nim` `emailSubmissionSetResponseEntityRoundTrip` (line 297) |
| §7.5 ¶1 | Only `undoStatus` updatable post-create | `EmailSubmissionUpdate` single variant (G16) | `temail_submission_update.nim` `setUndoStatusToCanceledValueShape` (line 24) — pins single-variant shape |
| §7.5 ¶3 | `onSuccessUpdateEmail` applies PatchObject to Email on success | `NonEmptyOnSuccessUpdateEmail` = `distinct Table[IdOrCreationRef, EmailUpdateSet]` (G22, G35, with NonEmpty wrapper per implementation-reality note 1) | `tonsuccess_extras.nim` `toJsonNonEmptyOnSuccessUpdateEmailDirectKey` (line 94), `toJsonNonEmptyOnSuccessUpdateEmailCreationKey` (106) |
| §7.5 ¶3 | `onSuccessDestroyEmail` destroys Email on success | `NonEmptyOnSuccessDestroyEmail` = `distinct seq[IdOrCreationRef]` (G22, G35) | `tonsuccess_extras.nim` `toJsonNonEmptyOnSuccessDestroyEmailEmitsWireKeyArray` (line 116) |
| §7.5 ¶5 | SetError `invalidEmail` includes problematic property names | `setInvalidEmail` + `invalidEmailPropertyNames` accessor (G23) | `tmail_method_errors.nim` `emailSubmissionSetInvalidEmailOnCreate` (line 412); existence in `trfc_8620.nim` `rfc8621_submissionErrorsClassified` (line 953) |
| §7.5 ¶5 | SetError `tooManyRecipients` includes max count | `setTooManyRecipients` + `maxRecipientCount` accessor (G23) | `tmail_method_errors.nim` `emailSubmissionSetTooManyRecipientsOnCreate` (line 427); existence `trfc_8620.nim:953` |
| §7.5 ¶5 | SetError `noRecipients` when rcptTo empty | `setNoRecipients` (G23) | `tmail_method_errors.nim` `emailSubmissionSetNoRecipientsOnCreate` (line 440); existence `trfc_8620.nim:953` |
| §7.5 ¶5 | SetError `invalidRecipients` includes bad addresses | `setInvalidRecipients` + `invalidRecipients` accessor (G23) | `tmail_method_errors.nim` `emailSubmissionSetInvalidRecipientsOnCreate` (line 448); existence `trfc_8620.nim:953` |
| §7.5 ¶5 | SetError `forbiddenMailFrom` when SMTP MAIL FROM disallowed | `setForbiddenMailFrom` (G23) | `tmail_method_errors.nim` `emailSubmissionSetForbiddenMailFromOnCreate` (line 459); existence `trfc_8620.nim:953` |
| §7.5 ¶5 | SetError `forbiddenFrom` when RFC 5322 From disallowed | `setForbiddenFrom` (G23) | `tmail_method_errors.nim` `emailSubmissionSetForbiddenFromOnCreate` (line 467); existence `trfc_8620.nim:953` |
| §7.5 ¶5 | SetError `forbiddenToSend` when user lacks send permission | `setForbiddenToSend` (G23) | `tmail_method_errors.nim` `emailSubmissionSetForbiddenToSendOnCreate` (line 475); existence `trfc_8620.nim:953` |
| §7.5 ¶6 | SetError `cannotUnsend` when cancel fails | `setCannotUnsend` (G23) | `tmail_method_errors.nim` `emailSubmissionSetCannotUnsendOnUpdate` (line 498) — the single update-only applicability per §8.8 |
| §1.3.2 | Capability `maxDelayedSend` is `UnsignedInt` seconds | `SubmissionCapabilities.maxDelayedSend` | `tserde_mail_capabilities.nim` `maxDelayedSendZero` (line 166) |
| §1.3.2 | Capability `submissionExtensions` is EHLO-name → args map | `SubmissionExtensionMap` (distinct OrderedTable) (G25) | `tserde_mail_capabilities.nim` `submissionExtensionMapRoundTripPreservesOrder` (line 342), `submissionExtensionMapCaseInsensitiveKey` (366), `submissionExtensionMapParsesLegacyWireShape` (396) |

The matrix is a **living artefact**: any new §7 promise (added under
G40+ architecture amendments or later G parts) MUST add a row here
before the implementation merges. The matrix is the single artefact
that proves test-spec adequacy for RFC §7 constraints by inspection.

---

### 8.11. Verification commands

Verification sequence:

- `just build` — shared library compiles; no new warnings.
- `just test` — the fast suite runs green. `tests/property/tprop_mail_g.nim`
  and `tests/stress/tadversarial_mail_g.nim` are listed in
  `tests/testament_skip.txt` and run under `just test-full`, not the
  fast suite (matching `tadversarial_mail_f.nim` /
  `tprop_mail_e.nim`). Agent validation workflows use `just test` for
  iteration and `just test-full` for final verification.
- `just test-full` — full suite including property and stress tiers.
- `just analyse` — nimalyzer passes without new suppressions.
- `just fmt-check` — nph formatting unchanged.
- `just ci` — full pipeline green (reuse + fmt-check + lint + analyse + test).
- Single-file invocation example:
  `testament pat tests/unit/mail/temail_submission.nim` — works per-
  file once a test is failing in the suite; preferred over rerunning
  the full suite during iteration.

The compile-only smoke (`tests/compile/tcompile_mail_g_public_surface.nim`,
§8.2.2) fails loudly at the `static:` block if any new public symbol
is not re-exported through `src/jmap_client.nim`'s cascade. Variant-
kind exhaustiveness is witnessed by the internal production `case`
sites in `src/jmap_client/mail/email_submission.nim`,
`submission_param.nim`, `serde_email_submission.nim`, and
`serde_submission_envelope.nim` on every build. The `cancelUpdate`
phantom-typed arrow's compile-time rejection is pinned in
`temail_submission.nim`'s `static:` block
`phantomArrowStaticRejectsFinalAndCanceled` (line 78) and re-exercised
in `trfc_8620.nim`'s `rfc8621Section7ConstraintTableCompileTimeAnchor`
(lines 1801–1803).

Property tests in `tprop_mail_g.nim` cover the RFC 5321 Mailbox
totality (A), strict/lenient coverage (B), `SubmissionParams`
insertion-order round-trip (C), `SubmissionParamKey` identity algebra
(D), `AnyEmailSubmission` parse-and-dispatch (E), `cancelUpdate`
value-level invariant (F), `NonEmptyEmailSubmissionUpdates` duplicate-
Id (G), `ParsedDeliveredState.rawBacking` preservation (H), and
`parseSmtpReply` Reply-code boundary (I). Coverage matrix §8.13 is
the single inspection point for "is every G1 decision pinned by a
test?".

---

### 8.12. Scale invariants (lean)

F2 §8.10 tested 10 000-entry `EmailUpdateSet` with staggered conflicts
plus 100k-entry wall-clock bound. G1's single-variant
`EmailSubmissionUpdate` has no conflict-staggering scenarios to test —
the §8.10 "three classes at positions 0/500/999" pattern does not
translate. Scale is only interesting for:

| Test name | Constructor | Input shape | Expected outcome |
|-----------|-------------|-------------|------------------|
| `nonEmptyEmailSubmissionUpdates10kWithDupAtEnd` | `parseNonEmptyEmailSubmissionUpdates` | 10 000 entries; duplicate `Id` at position 9999 | `Err` with the duplicate violation; capacity bounded by `≤ 2 × 10 000`; mirrors `nonEmptyImportMap10kWithDupAtEnd` in F2 §8.10 |
| `submissionParams1kExtensionEntries` | `parseSubmissionParams` | 1 000 distinct `spkExtension` entries | `Ok`; `OrderedTable` insertion order preserved on `toJson`; wall-clock bound ≤ 500 ms on CI hardware (linear scaling pin) |
| `nonEmptyRcptList1kWithDupAt999` | `parseNonEmptyRcptList` (strict) | 1 000 recipients; duplicate at position 999 | `Err` with `"duplicate recipient mailbox"`; single-pass algorithm does not bail at a prefix |

Three blocks in `tests/stress/tadversarial_mail_g.nim`. **Small compared
to F2 §8.10** — G1's single-variant update algebra has no
conflict-staggering scenarios to test, and the parameter algebra's
hash-keyed uniqueness invariant is structurally enforced at construction
time (not an accumulating algorithm that needs scale testing). Document
the omissions explicitly so a future reviewer does not read the smaller
matrix as a gap: there is nothing more to test at the 10k / 100k scale
for G1.

---

### 8.13. Coverage matrix — G1 decisions to test cases

Mechanical mapping between every G1 decision (§13 Decision Traceability
Matrix, 37 rows from G1 through G39) and the test cases that pin it.
Mirrors F2 §8.12 in role. Rows where a decision is purely structural
(module organisation, naming) or has no executable test surface are
tagged as such. Surfaces holes by inspection — every G-decision that
makes a behavioural promise has at least one row.

| G # | Promise | Test file | Test name / evidence |
|-----|---------|-----------|----------------------|
| G1 | Module organisation across 5 L1 + 3 L2 files | `tcompile_mail_g_public_surface.nim` | Symbol re-export cascade validates the split mechanically; no dedicated block |
| G2 | `EmailSubmission[S: static UndoStatus]` phantom-typed entity + `AnyEmailSubmission` wrapper | `temail_submission.nim`; `tserde_email_submission.nim`; `tprop_mail_g.nim` | `toAnyPendingBranchPreserved` (line 24), `toAnyFinalBranchPreserved` (39), `toAnyCanceledBranchPreserved` (51); `anyEmailSubmissionPendingRoundTrip` (`tserde_email_submission.nim:43`); property group E `propAnyEmailSubmissionStateDispatch` (`tprop_mail_g.nim:185`) |
| G3 | `[S: static UndoStatus]` generic as DataKinds encoding; enum IS phantom | `temail_submission.nim` `static:` block; `tadversarial_mail_g.nim` | `phantomArrowStaticRejectsFinalAndCanceled` (line 78) — load-bearing compile-time pin; also `anyUndoStatusUnknownValue` in `anyEmailSubmissionDispatchGroup` (`tadversarial_mail_g.nim:295` — closed-enum commitment) |
| G4 | `cancelUpdate(s: EmailSubmission[usPending])` typed arrow at L1 | `temail_submission.nim`; `tprop_mail_g.nim` | `cancelUpdateProducesSetUndoStatusToCanceled` (line 63); property group F `propCancelUpdateKindInvariant` (`tprop_mail_g.nim:239`) |
| G6 | Distinct `RFC5321Mailbox` + `SubmissionAddress` | `tsubmission_mailbox.nim` (215L); property group A | 10 grammar blocks (lines 34–188); adversarial `rfc5321MailboxAdversarialGroup` (`tadversarial_mail_g.nim:54`); `propRFC5321MailboxTotality` (`tprop_mail_g.nim:54`) |
| G7 | `NonEmptyRcptList` strict/lenient parser pair | `tserde_submission_envelope.nim`; `tprop_mail_g.nim`; `tadversarial_mail_g.nim` | `emptyRcptToIsRejected` (`tserde_submission_envelope.nim:110`); property group B `propRFC5321MailboxStrictLenientSuperset` (`tprop_mail_g.nim:83`); `envelopeDuplicateRcptToStrict` / `envelopeDuplicateRcptToLenient` nested under `envelopeCoherenceGroup` (`tadversarial_mail_g.nim:230,236`) |
| G8 | Typed sealed sum + extension arm for `SubmissionParam` | `tsubmission_params.nim` (380L) | 19 per-kind / matrix blocks (§8.7); adversarial `submissionParamAdversarialGroup` (`tadversarial_mail_g.nim:104`) |
| G8a | `distinct OrderedTable[SubmissionParamKey, SubmissionParam]` | `tsubmission_params.nim`; property groups C, D | `paramKeyDerivationTotality` (line 309) |
| G8b | 11 typed variants + extension arm | `tsubmission_params.nim` | §8.7 matrix (one block per row) |
| G8c | Per-parameter typed payloads | `tsubmission_params.nim` | Per-variant blocks |
| G9 | `distinct Table[RFC5321Mailbox, DeliveryStatus]` (`DeliveryStatusMap`) | `tsubmission_status.nim`; `tserde_submission_status.nim` | `deliveryStatusMapCountDelivered` (`tsubmission_status.nim:201`); `deliveryStatusMapRoundTripPreservesOrder` (`tserde_submission_status.nim:101`) |
| G10 | `DeliveredState` + `dsOther` catch-all + `ParsedDeliveredState` | `tsubmission_status.nim`; property group H | Per-variant round-trip blocks (lines 28–77); `propParsedDeliveredStateRawBackingRoundTrip` (`tprop_mail_g.nim:306`) |
| G11 | `DisplayedState` + `dpOther` catch-all | Same pattern as G10 | `displayedState*` blocks (lines 83–109) |
| G12 | `ParsedSmtpReply` + smart ctor + RFC 3463 enhanced status code + canonicalising renderer | `tsubmission_status.nim`; property group I; `tadversarial_mail_g.nim` | `smtpReplyHappy200`/`smtpReplyHappy550`/`smtpReplyMultilineHappy`/`smtpReplyEnhancedCodeHappy`/`renderCanonicalReplyIsIdempotent`/`renderCrlfInputCanonicalisesToLf` (lines 115–175); 14 rejection rows in `smtpReplyGrammarGroup` (`tadversarial_mail_g.nim:350`); `propParseSmtpReplyDigitBoundary` (`tprop_mail_g.nim:358`) |
| G13 | `EmailSubmissionBlueprint` naming | `temail_submission_blueprint.nim` | `symbolsExported` (19), `minimalBlueprint` (23) + sibling blocks |
| G14 | `Opt[Envelope]`; `None` = server synthesises | `temail_submission_blueprint.nim` | `defaultEnvelopeIsNone` (line 80) |
| G15 | Accumulating-error `Blueprint` smart ctor | `temail_submission_blueprint.nim` | `blueprintAccumulatesBothIdErrors` (line 113) |
| G16 | Single-variant `EmailSubmissionUpdate` | `temail_submission_update.nim` | `setUndoStatusToCanceledValueShape` (line 24) |
| G17 | `NonEmptyEmailSubmissionUpdates` | `temail_submission_update.nim`; property group G | `parseUpdatesRejectsEmpty` (line 38), `parseUpdatesRejectsDuplicateId` (49); `propNonEmptyEmailSubmissionUpdatesDuplicateId` (`tprop_mail_g.nim:259`) |
| G18 | Typed `EmailSubmissionFilterCondition` with `NonEmptyIdSeq` | `tserde_email_submission.nim` | `filterConditionAllFieldsPopulated` (line 184), `filterConditionOnlyUndoStatus` (210) |
| G19 | `EmailSubmissionSortProperty` enum + `esspOther` catch-all | `tserde_email_submission.nim` | `comparatorSentAtTokenNotSendAt` (line 245) — pins the wire-token vs field-name mismatch |
| G20 | `addEmailSubmissionAndEmailSet` AND-connector naming | `tmail_builders.nim` §O.1 | `addEmailSubmissionAndEmailSetWireAnchor` (line 736) |
| G21 | Specific `EmailSubmissionHandles` (no generic) | `tmail_builders.nim` §O.2–O.7; `tadversarial_mail_g.nim` | `getBoth*` blocks (lines 775–947); adversarial `getBothSubmissionAdversarialGroup` (`tadversarial_mail_g.nim:446`); compile-test symbol pin |
| G22 | Typed `EmailUpdateSet` values with `IdOrCreationRef` keys | `tonsuccess_extras.nim` | `toJsonNonEmptyOnSuccessUpdateEmail*` blocks (lines 94, 106) |
| G23 | No new `SetError` variants; reuse 8 + `tooLarge` | `trfc_8620.nim`; `tmail_method_errors.nim` | `rfc8621_submissionErrorsClassified` (`trfc_8620.nim:953`); `emailSubmissionSetMethodErrorSurface` (`tmail_method_errors.nim:381`); applicability §8.8 |
| G24 | No new payload-less accessors | Structural decision; no executable test | — (structural) |
| G25 | `SubmissionExtensionMap` distinct wrapper | `tserde_mail_capabilities.nim` | `submissionExtensionMapRoundTripPreservesOrder` (line 342), `submissionExtensionMapCaseInsensitiveKey` (366), `submissionExtensionMapParsesLegacyWireShape` (396) |
| G26 | Serde error rail via `SerdeViolation` + `JsonPath` | All G2 `tserde_*.nim` files; pattern enforced via `assertSvKind` / `assertSvPath` per `massertions.nim` | Pattern enforced across `tserde_email_submission.nim`, `tserde_submission_envelope.nim`, `tserde_submission_status.nim`, `tserde_mail_capabilities.nim` |
| G27 | `fromJson` synthesises `Opt.none` when wire is null | `tserde_email_submission.nim` | `blueprintOptNoneEnvelopePassesThrough` (line 165) |
| G32 | `ReversePath` sum with nullable params | `tserde_submission_envelope.nim`; `tadversarial_mail_g.nim` | `nullReversePathWireShape` (line 84); `envelopeNullMailFromWithParams` in `envelopeCoherenceGroup` (`tadversarial_mail_g.nim:176`) |
| G33 | `ReversePath` at `Envelope.mailFrom` field (not on `SubmissionAddress`) | `tserde_submission_envelope.nim` | `reversePathNullWithParamsRoundTrip` (line 223), `reversePathMailboxWithoutParamsRoundTrip` (257) |
| G34 | `Opt[SubmissionParams]` nullability | `tserde_submission_envelope.nim` | `parametersOptNoneDistinctFromEmptyObject` (line 292) |
| G35 | `IdOrCreationRef` sum for `onSuccess*` keys | `tonsuccess_extras.nim` | `parseNonEmptyOnSuccess*AcceptsArmDistinct*` (lines 62, 75) + `idOrCreationRefWireDirectIsBareString` (128), `idOrCreationRefWireCreationHasHashPrefix` (137), `idOrCreationRefVsReferencableAreDistinctTypes` (145) |
| G36 | `IdOrCreationRef` vs `Referencable[T]` separate types | `tonsuccess_extras.nim` | `idOrCreationRefVsReferencableAreDistinctTypes` (line 145) compile-time pin |
| G37 | `Opt[NonEmptyIdSeq]` filter list rejects empty | `tserde_email_submission.nim` | `filterConditionRejectsEmptyIdSeq` (line 232) |
| G38 | Pattern A sealing on `EmailSubmissionBlueprint` | `temail_submission_blueprint.nim` | `sealingContract` (line 45); `blueprintPatternASealExplicitRawField` (142) — diagnostic per-field probes |
| G39 | `SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission]` type alias | `tcompile_mail_g_public_surface.nim`; `tserde_email_submission.nim` | `EmailSubmissionSetResponse` symbol pin; `emailSubmissionSetResponseEntityRoundTrip` (`tserde_email_submission.nim:297`) plus the two server-divergence shapes (`emailSubmissionCreatedItemUndoStatusAbsent` at 372, `emailSubmissionCreatedItemUndoStatusPending` at 385) |

The matrix shows full coverage across 37 G-decisions plus the
implementation-reality divergences (`NonEmptyOnSuccessUpdateEmail` /
`NonEmptyOnSuccessDestroyEmail` NonEmpty wrappers, `toAny`
phantom-boundary helpers and `asPending`/`asFinal`/`asCanceled`
accessors, `ParsedSmtpReply` with RFC 3463 enhanced-status-code
support, the 99-assertion compile test). Where a row is tagged
"structural", the decision has no executable test surface: adopting
or rejecting it is visible in the codebase by inspection, not by
test.

---

### 8.14. What should NOT go in G2

Enumerate these in this dedicated subsection (F2's trailing convention).
Each exclusion cites the G1 decision or prior-part precedent that
obviates the test:

| Not in G2 | Why |
|-----------|-----|
| Conflict-pair classification matrix (F2 §8.7 analogue) | G16 chose single-variant `EmailSubmissionUpdate` (`esuSetUndoStatusToCanceled`) — no pairs exist. A 3-class enumeration on one variant is theatre. |
| RFC 6901 escape bijectivity property | G1 adds no new JSON-Pointer escape sites. `tprop_mail_f.nim` Group D covers the shared `jsonPointerEscape` helper. Reference, do not duplicate. |
| New `SetError` variant tests | G23 / G24: no new variants added. `tmail_errors.nim` + `trfc_8620.nim` already classify the 8 submission-specific + `tooLarge`. |
| Generic `CompoundHandles[A, B]` promotion tests | G21 / F3 Rule-of-Three still holds. No generic exists to test. |
| `PatchObject`-demotion `assertNotCompiles` gate | Already documented in F2 §8.2.2 as trivially-true; `PatchObject` is removed entirely from `framework.nim`. G1 inherits this; do not re-pin. |
| `fromJson` absence pins for creation-only types | `serde_email_submission.nim` does not declare `fromJson` for `EmailSubmissionBlueprint`, `EmailSubmissionFilterCondition`, `EmailSubmissionComparator`, or `IdOrCreationRef`. The `grep -n 'fromJson' src/jmap_client/mail/serde_email_submission.nim` check is the primary verification, matching F2 §8.2.2's position. |
| JSON-structural attacks — BOM/NaN/Infinity/deep-nesting/duplicate-keys/1-MB-strings | `tadversarial_mail_f.nim` already exercises the `std/json` boundary. G1 introduces no new parser pathway; reference the existing file by name in `tadversarial_mail_g.nim`'s closing paragraph and do not re-cover. |
| Cast-bypass behaviour per-type pins | F2 §8.2.3 documented this as a codebase-wide negative contract (`cast[T](...)` opts out of invariant guarantees). G1 inherits the same contract for every distinct-seq / distinct-table submission type; a single pointer to F2 §8.2.3 is enough — not per-G1-type repetition. |
| Separate "variant-kind exhaustiveness" compile probes | Internal `case AnyEmailSubmission.state`, `case SubmissionParamKind`, and `case EmailSubmissionUpdateVariantKind` sites already force compiler witness at every build. `grep` for every such site confirms coverage; dedicated synthetic probes add nothing. |
| Generator-driven property for the phantom-type arrow | Group F in §8.2.1 uses `QuickTrials = 200` deliberately because the predicate is value-level and trivially true. The type-level enforcement is the `assertNotCompiles` in §8.3's `temail_submission.nim`. **Two tools for two layers** — do not promote Group F to `DefaultTrials`, and do not demote the `assertNotCompiles` to runtime. |
| A `tserde_email_submission_adversarial.nim` per-file analogue | F2 did not create a `tserde_email_adversarial_f.nim`; it folded serde adversarial into `tadversarial_mail_f.nim`. Follow the same shape — keep `tadversarial_mail_g.nim` as the single adversarial file spanning serde + protocol + coherence. |
| `CrossProcessTrials` property group | The distinct-seq / distinct-OrderedTable design across G1 eliminates hash-seed nondeterminism; `toJson` output is a function of input alone. `CrossProcessTrials` applicability is documented as non-existent in §8.9.3; if a future change moves any G1 container to a regular `Table`, the group must be added. |
| `PatchObject`-variant tests for `EmailSubmissionUpdate` wire encoding | `EmailSubmissionUpdate` is a typed algebra (F1 pattern inherited); `toJson` emits the wire patch object (`{"undoStatus": "canceled"}`) directly. No separate `PatchObject` type exists for submission updates; testing against a non-existent layer would be meaningless. |

The exclusion list is the single inspection point for "did G2 omit
something deliberately or by oversight?". Every item here has a
decision-traceability anchor either in G1 §13 (a Gxx decision) or in an
earlier F1/F2 commitment that G1 inherits. New G-decisions that
introduce a G2 exclusion MUST add a row here, citing the decision and
its rationale.

---

*End of Part G2 design document.*
