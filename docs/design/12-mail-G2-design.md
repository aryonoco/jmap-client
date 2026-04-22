# RFC 8621 JMAP Mail — Design G2: EmailSubmission — Test Specification

Companion test specification for [`12-mail-G1-design.md`](./12-mail-G1-design.md).
The section number below is kept at `8` so cross-references from G1
(`(G2, G3)`, `(G21)`, `(G27)`, the Decision Traceability Matrix) remain
valid without renumbering. See G1 for the full context (type surface,
phantom-state indexing, cross-entity compound builder, Decision
Traceability Matrix).

This document was written after the G1 implementation landed. Where G1's
prose and the shipped code disagree, **the shipped code is
authoritative** and this document specifies tests against it. The
per-section "Implementation reality" notes flag the places where the
test shape differs from what G1 prose would have suggested.

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
   `AnyEmailSubmission` existential round-trip, `ParsedDeliveredState`
   raw-backing preservation, and `SmtpReply` Reply-code digit boundary.
4. **Adversarial** — a single `tadversarial_mail_g.nim` file covering
   malformed `Envelope` and `SubmissionParam` wire shapes, `SmtpReply`
   grammar violations, wild `undoStatus` dispatch values, cross-entity
   coherence for `getBoth(EmailSubmissionHandles)`, and the scale-tier
   invariants (§8.12). Does **not** re-cover generic JSON-structural
   attacks (BOM, NaN, deep nesting, duplicate keys, cast-bypass) —
   `tests/stress/tadversarial_mail_f.nim` already exercises the
   `std/json` boundary and G1 introduces no new parser pathway; the
   adversarial file references F by name and inherits the coverage.
5. **Compile-time reachability** — the shipped file
   `tests/compile/tcompile_mail_g_public_surface.nim` (**SHIPPED**, 156
   lines) proves every new public symbol is reachable through the
   top-level `jmap_client` re-export chain. 96 `declared()` assertions
   plus one runtime `doAssert` anchor (`$mnEmailSubmissionSet ==
   "EmailSubmission/set"`). See §8.2.2 for the authoritative symbol
   list and the optional enhancement pinning the phantom-typed arrow.

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

**Test-idiom note.** The shipped test style across every new file in
this part is `block <name>:` plus `assertOk` / `assertErr` / `assertEq`
/ `assertLen` / `assertSvKind` / `assertSvPath` from
`tests/massertions.nim`, plus raw `doAssert` for inline probes. No
`std/unittest` `test "name":` blocks, no `suite` wrappers. The canonical
precedent for the style is `tests/unit/mail/temail_submission_blueprint.nim`
(already shipped for Part G with the seven blocks at lines 20–92) and
`tests/unit/mail/tonsuccess_extras.nim` (already shipped for Part G
with ten blocks across six lettered sections at lines 25–124).
Prescriptions in §8.3 and §8.4 below name proposed `block` identifiers
directly, not unittest-style titles.

Test-infrastructure additions (§8.9) follow Part E's 7-step fixture
protocol (`tests/mfixtures.nim:7-14`) and naming convention (`make<Type>`
minimal / `makeFull<Type>` populated). **No new test-support modules are
introduced**: submission factories and equality helpers land in
`mfixtures.nim` alongside `setErrorEq` (`mfixtures.nim:707`) and the
`make*Blueprint` family; generators land in `mproperty.nim` alongside
`genEmailBlueprint`. Fragmenting the support layer for one feature is
explicitly disallowed — this matches F2 §8.6's shipped stance.

**Implementation reality — shipped divergences from G1 prose.**

Three places where the shipped code diverges from the G1 design text;
tests are written against code, not prose:

1. **`NonEmptyOnSuccessUpdateEmail` / `NonEmptyOnSuccessDestroyEmail`.**
   G1 §9.1 describes `onSuccessUpdateEmail: Opt[Table[IdOrCreationRef,
   EmailUpdateSet]]` and `onSuccessDestroyEmail: Opt[seq[IdOrCreationRef]]`
   — raw `Table`/`seq`. The shipped code (`mail/email_submission.nim`)
   introduces two distinct-type wrappers around the non-empty contract,
   smart-constructor gated by `parseNonEmptyOnSuccessUpdateEmail` and
   `parseNonEmptyOnSuccessDestroyEmail`. The smoke file
   `tests/unit/mail/tonsuccess_extras.nim` pins empty-rejection (message
   `"must contain at least one entry"`) and duplicate-rejection
   (message `"duplicate id or creation reference"`) — those strings are
   locked in §8.3's error-rail table and must not be re-invented in
   new blocks.
2. **Compile test has 96 assertions, not the "46" an earlier draft
   mentioned.** The shipped `tcompile_mail_g_public_surface.nim` covers
   43 types plus 53 functions (smart constructors, parsers, typed
   parameter constructors, infallible ctors + phantom helpers, domain
   helpers, onSuccess NonEmpty types, L3 method builders, and method
   enum route variants). §8.2.2 enumerates the full list.
3. **`toAny` phantom-boundary helper.** G1 §4.2 describes
   `AnyEmailSubmission` construction via direct case-object literal at
   the serde boundary. The shipped code introduces a `toAny` family
   (three overloads, one per phantom instantiation) exported via
   `email_submission.nim`. The compile test pins its presence at line
   120. Tests that construct `AnyEmailSubmission` from
   `EmailSubmission[S]` should exercise `toAny(...)` rather than brace
   literals — mirrors the codebase's general "constructors are
   privileges" principle.
4. **`AnyEmailSubmission` Pattern A sealing.** The shipped code seals
   the existential wrapper's branch fields: they are module-private
   (`rawPending`/`rawFinal`/`rawCanceled`) and external readers use
   the three `asPending`/`asFinal`/`asCanceled` accessors, each
   returning `Opt[EmailSubmission[S]]`. The sealing makes wrong-branch
   access unrepresentable at the API layer — the runtime `FieldDefect`
   path is unreachable from external code, which matters because
   under `--panics:on` (project default, `config.nims:23`)
   `FieldDefect` is fatal and cannot be caught. Tests that need the
   underlying `EmailSubmission[S]` use the accessor + `Opt` pattern
   (`for s in a.asPending(): ...` or `a.asPending().get()` after a
   state check), never the `raw*` fields. Serde `fromJson` constructs
   via `toAny(sub)` — there is no brace-literal construction of
   `AnyEmailSubmission` outside its defining module. Item 3's
   principle ("constructors are privileges") applies with equal force
   to readers: accessors are the reading privilege.

---

### 8.2. New test files — part-lettered

Following Parts E and F's convention, the lettered-by-part files cover
test concerns whose scope spans multiple types within the Part.

**State of play (as of the G1 implementation landing):**

| File | Status |
|------|--------|
| `tests/property/tprop_mail_g.nim` | **Not yet created** — all nine property groups in §8.2.1 are still to be written. Per precedent from `tprop_mail_e.nim`, the file will land in `tests/testament_skip.txt` (it runs under `just test-full`, not `just test`). |
| `tests/compile/tcompile_mail_g_public_surface.nim` | **SHIPPED** — 96 `declared()` assertions plus one runtime anchor covering every G1 public symbol. See §8.2.2 for the shape and optional enhancements. |
| `tests/stress/tadversarial_mail_g.nim` | **Not yet created** — the six adversarial-scenario blocks in §8.2.3 are still to be written. Per precedent from `tadversarial_mail_f.nim`, the file will land in `tests/testament_skip.txt` (runs under `just stress` / `just test-full`). |

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
| E | `AnyEmailSubmission` **round-trip** — for every generated `AnyEmailSubmission`, `fromJson(toJson(x))` preserves `x.state` AND the phantom-branch payload. Mandatory edge-bias: trial 0 = `usPending` branch; trial 1 = `usFinal`; trial 2 = `usCanceled` (one per variant forced early). Random `UndoStatus` selection from trial 3 onward via `genUndoStatus`. Equality checked via `assertPhantomVariantEq` (§8.9). | `DefaultTrials` (500) | Pins the existential-wrapper discharge on the full entity payload. The serde boundary dispatch (G1 §7.1) recovers the phantom parameter from the wire `undoStatus` field; a regression breaks every `case sub.state of usPending:` consumer. |
| F | `cancelUpdate` **invariant** — for every `EmailSubmission[usPending]` generated via `genEmailSubmission[usPending]`, the returned `cancelUpdate(s)` satisfies `kind == esuSetUndoStatusToCanceled`. Trivially true but pins the phantom-constrained helper against regression. | `QuickTrials` (200) | Cheap predicate; the value-level property is regression-detection only. The **type-level** enforcement — that `cancelUpdate` refuses `EmailSubmission[usFinal]` and `EmailSubmission[usCanceled]` — lives in the `assertNotCompiles` block in §8.3's `temail_submission.nim`. Two tools for two layers: do **not** promote this group to `DefaultTrials`, and do **not** demote the compile-time probe to runtime. |
| G | `NonEmptyEmailSubmissionUpdates` **duplicate-Id invariant** — for all maps with at least one duplicated `Id` (≥ 2 occurrences), the constructor accumulates ≥ 1 violation. Quantifies over the duplicate's position, total map size, and update value. Mandatory edge-bias: trial 0 = duplicate at positions (0, 1) (early-bound); trial 1 = duplicate at positions (n−2, n−1) (late-bound — guards against an `i > 0` early-bail bug); trial 2 = three-occurrence duplicate; trial 3 = many-position duplicate cluster. Random sampling from trial 4. Mirrors `tprop_mail_f.nim` Group C for `NonEmptyEmailImportMap`. | `DefaultTrials` (500) | Reuses the `validateUniqueByIt` contract (G17); pin behavioural equivalence with F1's `NonEmptyEmailImportMap`. |
| H | `ParsedDeliveredState.rawBacking` **round-trip for unknown values** — for all generated byte strings (including the four RFC-defined values `"queued"`, `"yes"`, `"no"`, `"unknown"`), `parseDeliveredState(s)` produces a `ParsedDeliveredState` whose `rawBacking == s`; for values outside the RFC-defined set, `state == dsOther`. `toJson` emits `rawBacking` byte-for-byte. Symmetric group covers `DisplayedState` / `ParsedDisplayedState`. Mandatory edge-bias: trials 0..3 = the four RFC-defined values for `DeliveredState`; trial 4 = one RFC-defined for `DisplayedState` (`"yes"`); trials 5..6 = unknown values (`"pending"` — note: this is NOT a `DeliveredState` value, pin the catch-all rather than a `UndoStatus`-style collision). | `DefaultTrials` (500) | The `dsOther` / `dpOther` catch-all (G10, G11) is forwards-compatibility insurance; raw-backing preservation must not lose bytes. Without this property, a server adding a new delivery state (e.g., `"deferred"`) would round-trip through the client as `"unknown"` or similar — silent corruption. |
| I | `parseSmtpReply` **Reply-code boundary scan** — for all generated strings of form `"<d1><d2><d3>"` plus optional `<sep><text>`, with `d1, d2, d3 ∈ '0'..'9'`, the parser's Ok/Err verdict matches RFC 5321 §4.2's grammar: `d1 ∈ '2'..'5'`, `d2 ∈ '0'..'5'`, `d3 ∈ '0'..'9'`. Mandatory edge-bias: trial 0 = `"199 text"` (d1 below range — reject); trial 1 = `"200 text"` (d1 at low boundary — accept); trial 2 = `"559 text"` (d1 at high boundary — accept); trial 3 = `"560 text"` (d1 above range — reject); trial 4 = `"260 text"` (d2 above range — reject); trial 5 = `"299 text"` (d3 at high boundary — accept); trial 6 = `"200"` (bare code, no separator — behaviour-specific, pin whatever the shipped code does); trial 7 = multi-line `"250-ok\r\n250 done"` (accept); trial 8 = multi-line `"250 ok\r\n250 done"` (reject — non-final must hyphen). Random sampling from trial 9. | `DefaultTrials` (500) | Reply-code grammar is finite at the digit level but the text-continuation grammar is not; boundaries at `2xx` / `5xx` endpoints are where real-world SMTP servers drift. A property here catches accidental off-by-one in digit-range checks. |

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

**SHIPPED.** Compile-only smoke test; the shipped shape is a single
top-level `import jmap_client` plus a `static:` block containing 96
`declared(<symbol>)` assertions, one per new public symbol, organised
into 17 comment-separated groups. A single runtime-scope
`doAssert $mnEmailSubmissionSet == "EmailSubmission/set"` at line 156
pins the imported module against Nim's `UnusedImport` check via a
genuine Part G method-enum variant.

**Why `declared()` and not `compiles()`.** `declared()` sidesteps
overload-resolution ambiguity on the three phantom-typed `toAny` arms
and on `getBoth` (distinct overloads for `EmailCopyHandles` and
`EmailSubmissionHandles`). A naïve `compiles(let x: AnyEmailSubmission
= toAny(default(EmailSubmission[usPending])))` probe would snag on the
overload set; `declared()` asks only "is this identifier visible at
this site?", which is exactly the re-export invariant under test. The
shipped file documents this choice in its opening docstring (lines
12–16).

**Covered symbols** (authoritative, in source order, matching the
shipped file):

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
  `DisplayedState`, `ParsedDisplayedState`, `SmtpReply`,
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
- **Infallible constructors + phantom-boundary helpers (8):**
  `nullReversePath`, `reversePath`, `paramKey`, `toAny`,
  `setUndoStatusToCanceled`, `cancelUpdate`, `directRef`,
  `creationRef`. (lines 117–124)
- **Domain helpers on `DeliveryStatusMap` (2):**
  `countDelivered`, `anyFailed`. (lines 127–128)
- **onSuccess* NonEmpty extras (4):**
  `NonEmptyOnSuccessUpdateEmail`, `NonEmptyOnSuccessDestroyEmail`,
  `parseNonEmptyOnSuccessUpdateEmail`,
  `parseNonEmptyOnSuccessDestroyEmail`. (lines 131–134)
- **L3 method builders (6):**
  `addEmailSubmissionGet`, `addEmailSubmissionChanges`,
  `addEmailSubmissionQuery`, `addEmailSubmissionQueryChanges`,
  `addEmailSubmissionSet`, `addEmailSubmissionAndEmailSet`.
  (lines 137–142)
- **Method enum route variants (5):**
  `mnEmailSubmissionGet`, `mnEmailSubmissionChanges`,
  `mnEmailSubmissionQuery`, `mnEmailSubmissionQueryChanges`,
  `mnEmailSubmissionSet`. (lines 145–149)
- **Runtime anchor (1):**
  `doAssert $mnEmailSubmissionSet == "EmailSubmission/set"` at line 156.

**What the shipped file deliberately does NOT do:**

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

**Optional enhancement** — if reviewer strictness demands it:

A subsequent PR could add a block that directly exercises the
phantom-typed `cancelUpdate` arrow at compile time, co-located in
`tcompile_mail_g_public_surface.nim` rather than in the per-concept
file (§8.3 `temail_submission.nim`):

```nim
static:
  # Positive: usPending compiles.
  doAssert compiles(cancelUpdate(default(EmailSubmission[usPending])))
  # Negative: usFinal and usCanceled must not compile.
  doAssert not compiles(cancelUpdate(default(EmailSubmission[usFinal])))
  doAssert not compiles(cancelUpdate(default(EmailSubmission[usCanceled])))
```

This is **not** in the shipped file; it is a potential addition if the
`temail_submission.nim`-embedded version proves insufficient in
practice. F2 §8.2.2's optional-enhancement posture is the precedent.

#### 8.2.3. `tests/stress/tadversarial_mail_g.nim`

**Not yet created.** Adversarial scenarios, organised into six blocks
corresponding to matrices §8.3 (per-concept messages), §8.6 (cross-entity
coherence), §8.7 (parameter boundaries), §8.12 (scale invariants), and
three cross-cutting blocks covering `AnyEmailSubmission` dispatch,
`SmtpReply` grammar, and `Envelope` coherence.

**Block 1 — RFC 5321 Mailbox adversarial.** Each row is one named test
in the stress file. The strict parser must reject; the lenient parser
(`parseRFC5321MailboxFromServer`) either rejects or accepts per the
Postel split — pin whichever the shipped code does and treat it as a
contract test.

| Test name | Input | Strict outcome | Lenient outcome | Rule |
|-----------|-------|----------------|-----------------|------|
| `mailboxTrailingDotLocal` | `"user.@example.com"` | `Err` ("local-part is not a valid dot-string") | `Err` (structural: still malformed) | RFC 5321 §4.1.2 Dot-string |
| `mailboxUnclosedQuoted` | `"\"unterminated@example.com"` | `Err` ("local-part is not a valid quoted-string") | `Err` (structural) | RFC 5321 §4.1.2 Quoted-string |
| `mailboxBracketlessIPv6` | `"user@IPv6:::1"` | `Err` ("domain contains an invalid label") | Pin shipped behaviour | RFC 5321 §4.1.3 requires `[…]` |
| `mailboxOverlongLocalPart` | local-part 65 octets + `"@example.com"` | `Err` ("local-part exceeds 64 octets") | Pin shipped behaviour | RFC 5321 §4.5.3.1.1 |
| `mailboxOverlongDomain` | `"user@"` + domain 256 octets | `Err` ("domain exceeds 255 octets") | Pin shipped behaviour | RFC 5321 §4.5.3.1.2 |
| `mailboxGeneralLiteralStandardizedTagTrailingHyphen` | `"user@[foo-:bar]"` (Standardized-tag ends in hyphen) | `Err` ("address-literal has invalid general form") | Pin | RFC 5321 §4.1.3 Standardized-tag MUST end in `Let-dig`; contrast with `RFC5321Keyword` (G1 §2.2) which permits trailing hyphen because it uses the looser `esmtp-keyword` grammar |
| `mailboxControlChar` | `"u\x01ser@example.com"` | `Err` ("contains control characters") | `Err` (same) | Structural |
| `mailboxEmpty` | `""` | `Err` ("must not be empty") | `Err` (same) | Structural |

The `mailboxGeneralLiteralStandardizedTagTrailingHyphen` case is the
load-bearing contrast test — G1 §2.2 documents that
`RFC5321Keyword` permits trailing hyphen (per `esmtp-keyword`) while
`RFC5321Mailbox`'s embedded Standardized-tag uses the stricter
`Ldh-str`. A bug that unifies the two check routines would pass all
the positive mailbox tests but fail this single row.

**Block 2 — `SubmissionParam` wire adversarial.** Drives through the
typed parameter constructors and `toJson`/`fromJson` on
`SubmissionParams`.

| Test name | Input | Expected |
|-----------|-------|----------|
| `paramRetUnknownValue` | `retParam(...)` (not a valid `DsnRetType`) — exercised via wire input `{"RET": "BOTH"}` | `SubmissionParams.fromJson` → `Err` ("unknown RET value" — pin shipped string) |
| `paramNotifyNeverWithOthers` | `notifyParam({dnfNever, dnfSuccess})` | `Err` (`"NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY"` per `submission_param.nim:211`) |
| `paramNotifyEmptyFlags` | `notifyParam({})` | `Err` (`"NOTIFY flags must not be empty"`) |
| `paramHoldForNegative` | `parseHoldForSeconds(-1)` | Compile error — parameter type is `UnsignedInt`; the wire parser on `{"HOLDFOR": -1}` rejects with a structural error |
| `paramMtPriorityBelowRange` | `parseMtPriority(-10)` | `Err` (`"must be in range -9..9"` per `submission_param.nim:102`) |
| `paramMtPriorityAboveRange` | `parseMtPriority(10)` | `Err` (same) |
| `paramSizeAt2Pow53Boundary` | `{"SIZE": 9007199254740991}` (`2^53 − 1`, max exact-representable) | `Ok` — crossing this boundary would flip to lossy `JFloat` decoding; pin acceptance |
| `paramSizeAbove2Pow53` | `{"SIZE": 9007199254740992}` | Behaviour-specific (`std/json` `getBiggestInt` boundary); pin whatever the shipped code does |
| `paramEnvidXtextEncoded` | `{"ENVID": "hello\\x2Bworld"}` — per the G1 resolved note (§7.2), no xtext helpers exist; the JMAP wire carries plain UTF-8 | `Ok` — string stored verbatim |
| `paramDuplicateKey` | Two `spkBody` entries in the input seq | `Err` (`"duplicate parameter key"` per `submission_param.nim:367`) |

**Block 3 — `Envelope` serde coherence.** Tests the null-reverse-path
shape, the strict/lenient duplicate split, and the parameters-on-null
case.

| Test name | Wire JSON | Expected |
|-----------|-----------|----------|
| `envelopeNullMailFromWithParams` | `{"mailFrom": {"email": "", "parameters": {"ENVID": "id-1"}}, "rcptTo": [...]}` | `Ok` — G32 permits parameters on the null reverse path; `rpkNullPath` carries `Opt.some(SubmissionParams)` |
| `envelopeNullMailFromNoParams` | `{"mailFrom": {"email": "", "parameters": null}, "rcptTo": [...]}` | `Ok` — `rpkNullPath` with `Opt.none` |
| `envelopeMalformedMailFrom` | `{"mailFrom": {"email": "not@an@address", "parameters": null}, "rcptTo": [...]}` | `Err` (`svkFieldParserFailed` at `/mailFrom/email`) |
| `envelopeEmptyRcptTo` | `{"mailFrom": {...}, "rcptTo": []}` | `Err` (`svkFieldParserFailed` at `/rcptTo`) — pins the `NonEmptyRcptList` contract, complementing the shipped `emptyRcptToIsRejected` at `tserde_submission_envelope.nim:110-119` |
| `envelopeDuplicateRcptToLenient` | `{"mailFrom": {...}, "rcptTo": [alice, alice]}` via `parseNonEmptyRcptListFromServer` | `Ok` — lenient parser accepts duplicates (G7 Postel split) |
| `envelopeDuplicateRcptToStrict` | Same via `parseNonEmptyRcptList` (client path) | `Err` (`"duplicate recipient mailbox"` per `submission_envelope.nim:118`) |
| `envelopeOptNoneVsEmptyParams` | `SubmissionAddress` with `Opt.none(SubmissionParams)` toJson → `"parameters": null`; with `Opt.some(emptyParams)` toJson → `"parameters": {}` | Round-trip preserves the distinction (G34) |

**Block 4 — `AnyEmailSubmission` dispatch adversarial.** Critical note:
`UndoStatus` is the phantom parameter (G3), so the forwards-compat
catch-all pattern that applies to `DeliveredState`/`DisplayedState`
(G10/G11) does **not** apply here. Any wire `undoStatus` value outside
`{"pending", "final", "canceled"}` must `Err` — the client commits to
closed enumeration.

| Test name | Wire JSON (AnyEmailSubmission) | Expected |
|-----------|-------------------------------|----------|
| `anyMissingUndoStatus` | object without `undoStatus` field | `Err` (`svkMissingField` at `/undoStatus`) |
| `anyUndoStatusWrongKindInt` | `{"undoStatus": 1, ...}` | `Err` (`svkWrongKind` at `/undoStatus`) |
| `anyUndoStatusWrongKindNull` | `{"undoStatus": null, ...}` | `Err` (`svkWrongKind` at `/undoStatus`) |
| `anyUndoStatusUnknownValue` | `{"undoStatus": "deferred", ...}` | `Err` (`svkEnumValueUnknown` or equivalent — NOT a silent `usOther` fallback) |
| `anyUndoStatusCaseMismatch` | `{"undoStatus": "PENDING", ...}` | `Err` — wire tokens are lowercase per G1 §3.1 |
| `anyDispatchRoundTripPerVariant` | Serialise a fully-populated `usPending` / `usFinal` / `usCanceled` instance; confirm phantom branch on `fromJson` | Ok; `state` matches, branch payload preserved |

**Block 5 — `SmtpReply` grammar adversarial.** Per the shipped error
strings at `submission_status.nim:134–152`.

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
| `smtpReplyBareCodeNoText` | `"250"` | Pin shipped behaviour (may be `Ok` or `Err` depending on whether `<sep>text>` is required) |

**Block 6 — `getBoth(EmailSubmissionHandles)` cross-entity
adversarial.** Cross-references §8.6; each row in that matrix is
realised here as a named test with a complete wire `Response` fixture.
Unlike F1's same-entity `getBoth(EmailCopyHandles)`, these scenarios
involve two entity namespaces (`EmailSubmission/*` and `Email/*`)
sharing one request-response envelope.

| Test name | Scenario | Expected `getBoth` outcome |
|-----------|----------|---------------------------|
| `getBothBothSucceed` | Outer `EmailSubmission/set` ok + `created` populated; inner `Email/set` ok + corresponding update/destroy | `Ok(EmailSubmissionResults{submission, emailSet})` |
| `getBothInnerMethodError` | Outer ok; inner `MethodError(accountNotFound)` | `Err(methodError)` — inner error surfaces |
| `getBothInnerAbsent` | Outer ok; inner response absent (server did not run implicit set) | Structured `Err` (NOT silent default; pin the exact error type the shipped code produces) |
| `getBothInnerMcIdMismatch` | Outer ok; inner present but with wrong `methodCallId` | `Err(serverFail)`-like — surfaces as a client-side coherence check |
| `getBothOuterNotCreatedSole` | Outer ok but `notCreated` contains the sole creation; inner no invocation (RFC §7.5 permits omission when no `onSuccess*` target created) | `Ok` with empty `emailSet.created` — the shipped `getBoth` does not synthesise the inner response |
| `getBothOuterIfInStateMismatch` | Outer `Err(stateMismatch)`; inner no invocation | `Err` — inner never reached |
| `getBothCreationRefNotInCreateMap` | Outer ok with `onSuccessUpdateEmail: {creationRef("c-missing"): updates}` where `c-missing` is not in outer `create` | Pin: wire shape must validate regardless (client-side contract check); server-side `invalidResultReference`-like behaviour expected |

Reference — do **not** duplicate — `tests/stress/tadversarial_mail_f.nim`'s
JSON-structural attacks (BOM prefix, NaN/Infinity, duplicate keys, deep
nesting, 1 MB strings) and cast-bypass pins. G1 introduces no new
`std/json` pathway; those attacks apply transitively to every G1
decode surface, and re-enumerating them here would duplicate coverage.

---

### 8.3. New per-concept test files

**State-of-play key.** Each row below is tagged:

- **SHIPPED** — the blocks already exist in the cited file after the G1
  implementation merge. Scope additions go *after the last shipped
  block*; the append line is cited per file.
- **TO-ADD** — blocks still to be written in the cited file (creating
  the file first if it does not exist).

**Error-rail shape (applies to every TO-ADD below unless noted).** The
shipped `ValidationError` record has exactly three fields: `typeName:
string`, `message: string`, `value: string`. There is **no**
`classification` field, `kind` enum, or similar typed discriminator on
`ValidationError`; all rejection assertions check
`error[<i>].message` against the literal string the production code
emits. The authoritative messages, read from the shipped source:

| Type | Invariant | `message` | `value` | Source |
|------|-----------|-----------|---------|--------|
| `RFC5321Keyword` | bad length | `"length must be 1-64 octets"` | offending raw | `submission_atoms.nim:78` |
| `RFC5321Keyword` | bad lead char | `"first character must be ALPHA or DIGIT"` | offending raw | `submission_atoms.nim:80` |
| `RFC5321Keyword` | bad tail chars | `"characters must be ALPHA / DIGIT / '-'"` | offending raw | `submission_atoms.nim:82` |
| `OrcptAddrType` | empty | `"must not be empty"` | `""` | `submission_atoms.nim:132` |
| `OrcptAddrType` | bad lead char | `"first character must be ALPHA or DIGIT"` | offending raw | `submission_atoms.nim:134` |
| `OrcptAddrType` | bad tail chars | `"characters must be ALPHA / DIGIT / '-'"` | offending raw | `submission_atoms.nim:136` |
| `SmtpReply` | empty | `"must not be empty"` | `""` | `submission_status.nim:134` |
| `SmtpReply` | control chars | `"contains disallowed control characters"` | offending raw | `submission_status.nim:136` |
| `SmtpReply` | too short | `"line shorter than 3-digit Reply-code"` | offending raw | `submission_status.nim:138` |
| `SmtpReply` | first digit out of range | `"first Reply-code digit must be in 2..5"` | first digit | `submission_status.nim:140` |
| `SmtpReply` | second digit out of range | `"second Reply-code digit must be in 0..5"` | second digit | `submission_status.nim:142` |
| `SmtpReply` | third digit out of range | `"third Reply-code digit must be in 0..9"` | third digit | `submission_status.nim:144` |
| `SmtpReply` | bad separator | `"character after Reply-code must be SP, HT, or '-'"` | offending byte | `submission_status.nim:146` |
| `SmtpReply` | multi-line code mismatch | `"multi-line reply has inconsistent Reply-codes"` | offending raw | `submission_status.nim:148` |
| `SmtpReply` | non-final continuation | `"non-final reply line must use '-' continuation"` | offending line | `submission_status.nim:150` |
| `SmtpReply` | final with hyphen | `"final reply line must not use '-' continuation"` | offending line | `submission_status.nim:152` |
| `RFC5321Mailbox` | empty | `"must not be empty"` | `""` | `submission_mailbox.nim:108` |
| `RFC5321Mailbox` | control chars | `"contains control characters"` | offending raw | `submission_mailbox.nim:110` |
| `RFC5321Mailbox` | no `@` | `"missing '@' separator"` | offending raw | `submission_mailbox.nim:112` |
| `RFC5321Mailbox` | empty local-part | `"local-part must not be empty"` | offending raw | `submission_mailbox.nim:114` |
| `RFC5321Mailbox` | local-part > 64 octets | `"local-part exceeds 64 octets"` | offending raw | `submission_mailbox.nim:116` |
| `RFC5321Mailbox` | local-part bad dot-string | `"local-part is not a valid dot-string"` | offending raw | `submission_mailbox.nim:118` |
| `RFC5321Mailbox` | local-part bad quoted | `"local-part is not a valid quoted-string"` | offending raw | `submission_mailbox.nim:120` |
| `RFC5321Mailbox` | empty domain | `"domain must not be empty"` | offending raw | `submission_mailbox.nim:122` |
| `RFC5321Mailbox` | domain > 255 octets | `"domain exceeds 255 octets"` | offending raw | `submission_mailbox.nim:124` |
| `RFC5321Mailbox` | domain bad label | `"domain contains an invalid label"` | offending raw | `submission_mailbox.nim:126` |
| `RFC5321Mailbox` | addr-literal unclosed | `"address-literal missing closing ']'"` | offending raw | `submission_mailbox.nim:128` |
| `RFC5321Mailbox` | addr-literal bad IPv4 | `"address-literal has invalid IPv4 form"` | offending raw | `submission_mailbox.nim:130` |
| `RFC5321Mailbox` | addr-literal bad IPv6 | `"address-literal has invalid IPv6 form"` | offending raw | `submission_mailbox.nim:132` |
| `RFC5321Mailbox` | addr-literal bad general | `"address-literal has invalid general form"` | offending raw | `submission_mailbox.nim:134` |
| `MtPriority` | out of range | `"must be in range -9..9"` | offending int as string | `submission_param.nim:102` |
| `SubmissionParam` (notifyParam) | empty flags | `"NOTIFY flags must not be empty"` | `""` | `submission_param.nim:206` |
| `SubmissionParam` (notifyParam) | NEVER + others | `"NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY"` | `""` | `submission_param.nim:211` |
| `SubmissionParams` | duplicate key | `"duplicate parameter key"` | key as string | `submission_param.nim:367` |
| `NonEmptyRcptList` (strict) | empty | `"recipient list must not be empty"` | `""` | `submission_envelope.nim:117` |
| `NonEmptyRcptList` (strict) | duplicate | `"duplicate recipient mailbox"` | offending address | `submission_envelope.nim:118` |
| `NonEmptyRcptList` (lenient) | empty | `"recipient list must not be empty"` | `""` | `submission_envelope.nim:132` |
| `NonEmptyOnSuccessUpdateEmail` | empty | `"must contain at least one entry"` | `""` | `tonsuccess_extras.nim:33` (shipped test pinning shipped string) |
| `NonEmptyOnSuccessUpdateEmail` | duplicate key | `"duplicate id or creation reference"` | duplicated ref as string | `tonsuccess_extras.nim:50` |
| `NonEmptyOnSuccessDestroyEmail` | empty | `"must contain at least one entry"` | `""` | `tonsuccess_extras.nim:40` |
| `NonEmptyOnSuccessDestroyEmail` | duplicate element | `"duplicate id or creation reference"` | duplicated ref as string | `tonsuccess_extras.nim:57` |
| `NonEmptyEmailSubmissionUpdates` | empty | pin shipped string (grep `parseNonEmptyEmailSubmissionUpdates`) | `""` | `email_submission.nim` (read before writing) |
| `NonEmptyEmailSubmissionUpdates` | duplicate `Id` | pin shipped string | offending Id | `email_submission.nim` |
| `NonEmptyIdSeq` | empty | pin shipped string | `""` | `email_submission.nim` |
| `EmailSubmissionBlueprint` | invalid `identityId` | pin shipped string | offending raw | `email_submission.nim` |
| `EmailSubmissionBlueprint` | invalid `emailId` | pin shipped string | offending raw | `email_submission.nim` |

The **implementation reality note**: three bottom rows
(`NonEmptyEmailSubmissionUpdates`, `NonEmptyIdSeq`,
`EmailSubmissionBlueprint` per-field) ship with messages not inspected
during spec authoring; when writing the corresponding test blocks, the
first step is `grep -n 'validationError\|ValidationError(' src/jmap_client/mail/email_submission.nim`
to read the authoritative strings, then lock them in the block
assertions. This mirrors F2 §8.3's policy — do not invent strings.

**Per-concept file table:**

| File | Status | Append position | Scope additions |
|------|--------|-----------------|-----------------|
| `tests/unit/mail/temail_submission_blueprint.nim` | **SHIPPED** (92L) | After line 92 | Per-field rejection matrix: invalid `identityId`, invalid `emailId`, invalid inner `Envelope` nested through `parseEmailSubmissionBlueprint`'s accumulating rail (the `rawEnvelope` field accepts an `Envelope` value that is already validated, so inner violations cannot propagate via `Blueprint` — but **both** malformed id inputs must accumulate); `assertNotCompiles` record-literal sidestep for Pattern A (G38); cross-check against shipped `ValidationError.message` strings via grep-then-lock. Proposed `block` names: `blueprintInvalidIdentityId`, `blueprintInvalidEmailId`, `blueprintAccumulatesBothIdErrors`, `blueprintPatternASealExplicitRawField`. |
| `tests/unit/mail/tonsuccess_extras.nim` | **SHIPPED** (124L) | After line 124 | `IdOrCreationRef` vs `Referencable[T]` distinction: wire-shape pins (`directRef(id)` → JSON string `$id`; `creationRef(cid)` → JSON string `"#" & $cid`; `Referencable[T]` result-reference → JSON object `{"resultOf":..., "name":..., "path":...}`). Compile-time pin that the two types are distinct (`assertNotCompiles(let _: Referencable[seq[Id]] = directRef(id))`). Proposed `block` names: `idOrCreationRefWireDirectIsBareString`, `idOrCreationRefWireCreationHasHashPrefix`, `idOrCreationRefVsReferencableAreDistinctTypes`. |
| `tests/unit/mail/temail_submission.nim` | **TO-CREATE** (~250L) | New file | Per-phantom-variant construction smoke: `EmailSubmission[usPending]`, `EmailSubmission[usFinal]`, `EmailSubmission[usCanceled]` via `toAny` lifting; `AnyEmailSubmission` construction with `state` discriminator; value-level `cancelUpdate(EmailSubmission[usPending])` producing `esuSetUndoStatusToCanceled`; **`static:` block with `assertNotCompiles` proving `cancelUpdate(default(EmailSubmission[usFinal]))` and `cancelUpdate(default(EmailSubmission[usCanceled]))` fail to compile**. This is the single most load-bearing compile-time test in G2 — a regression collapses the phantom-typed transition arrow to a runtime check. Block 6 (`existentialBranchAccessorContract`) pins the Pattern A sealing contract (§8 item 4): (i) accessor visibility for the three `asX` projections, (ii) compile-time refusal of brace construction with both `raw*` names (now module-private) and the pre-sealing public names (no longer exist), and (iii) the `Opt[T]` projection shape for each state × accessor combination (3 × 3 = 9 probes). Proposed `block` names: `toAnyPendingBranchPreserved`, `toAnyFinalBranchPreserved`, `toAnyCanceledBranchPreserved`, `cancelUpdateProducesSetUndoStatusToCanceled`, `phantomArrowStaticRejectsFinalAndCanceled` (the `static:` block), `existentialBranchAccessorContract`. |
| `tests/unit/mail/temail_submission_update.nim` | **TO-CREATE** (~120L) | New file | `setUndoStatusToCanceled()` value-level construction; `parseNonEmptyEmailSubmissionUpdates` empty and duplicate-`Id` cases with message-string assertions (grep-locked per §8.3's error-rail table); accumulating behaviour when both empty and duplicate shapes co-occur (they can't — empty has no duplicates — so each invariant fires in its own input shape, matching F1 `NonEmptyEmailImportMap` style). Proposed `block` names: `setUndoStatusToCanceledValueShape`, `parseUpdatesRejectsEmpty`, `parseUpdatesRejectsDuplicateId`, `parseUpdatesHappyPathSingleEntry`. |
| `tests/unit/mail/tsubmission_params.nim` | **TO-CREATE** (~400L) | New file | 11 well-known variants, each with a valid representative and an invalid-boundary representative per §8.7; NOTIFY mutual-exclusion rule at unit tier; `SubmissionParamKey` identity enumeration across the 12-kind × extension-name matrix; `paramKey` derivation totality (every `SubmissionParam` value produces a well-formed `SubmissionParamKey`); `SubmissionParams` insertion-order preservation (non-property enumerator — three fixed insertion sequences checked against `toJson` output). File layout driven by §8.7 matrix — one `block` per row. |
| `tests/unit/mail/tsubmission_mailbox.nim` | **TO-CREATE** (~300L) | New file | `RFC5321Mailbox` strict parser: each of 4 local-part shapes (`Dot-string`, `Quoted-string`, long `Dot-string` near 64-octet limit, `Quoted-string` with escaped quote) × 4 domain-form shapes (plain `Domain`, IPv4 address-literal, IPv6 address-literal, General-address-literal) with one representative each — property group A covers the rest. Strict/lenient divergence cases (lenient accepts more — pin representatives). Case-insensitive `RFC5321Keyword` equality (`parseRFC5321Keyword("X-FOO") == parseRFC5321Keyword("x-foo")`); byte-equal `OrcptAddrType` equality (`parseOrcptAddrType("rfc822") != parseOrcptAddrType("RFC822")`) — pin that the two distinct types share grammar but not semantics. Proposed `block` names: `mailboxDotStringPlainDomain`, `mailboxDotStringIPv4Literal`, `mailboxDotStringIPv6Literal`, `mailboxDotStringGeneralLiteral`, `mailboxQuotedPlainDomain`, `mailboxQuotedIPv6Literal`, `mailboxStrictLenientSupersetOnPlainDomain`, `mailboxStrictLenientSupersetOnMalformedLocalPart`, `rfc5321KeywordCaseInsensitive`, `orcptAddrTypeByteEqual`. |
| `tests/unit/mail/tsubmission_status.nim` | **TO-CREATE** (~200L) | New file | `DeliveredState` round-trip per variant including `dsOther` raw-backing preservation; `DisplayedState` round-trip per variant including `dpOther`; `SmtpReply` Reply-code digit-class cases (mirror the unit-tier representatives of property group I); `DeliveryStatus` composite construction from all three fields; `DeliveryStatusMap` `countDelivered` and `anyFailed` domain operations exercised on hand-constructed maps with known outcomes (three maps: all-delivered, all-failed, mixed). Proposed `block` names: `deliveredStateQueuedRoundTrip`, `deliveredStateYesRoundTrip`, `deliveredStateNoRoundTrip`, `deliveredStateUnknownRoundTrip`, `deliveredStateOtherPreservesRawBacking`, `displayedStateYesRoundTrip`, `displayedStateUnknownRoundTrip`, `displayedStateOtherPreservesRawBacking`, `smtpReplyHappy200`, `smtpReplyHappy550`, `smtpReplyMultilineHappy`, `deliveryStatusComposite`, `deliveryStatusMapCountDelivered`, `deliveryStatusMapAnyFailedFalseWhenAllDelivered`, `deliveryStatusMapAnyFailedTrueWhenOneFailed`. |
| `tests/serde/mail/tserde_submission_envelope.nim` | **SHIPPED** (119L) | After line 119 | Full parameter-family serde coverage — the shipped file covers five families (BODY, SIZE, NOTIFY, ORCPT, extension) but omits six others. Add per-family round-trip blocks: `ENVID`, `RET`, `HOLDFOR`, `HOLDUNTIL`, `BY`, `MT-PRIORITY`, `SMTPUTF8`. `ReversePath` case object toJson/fromJson per arm (positive round-trip for `rpkNullPath` with and without params; for `rpkMailbox` with and without params). `Opt.none(SubmissionParams)` vs `Opt.some(emptyParams)` wire distinction (G34) — `Opt.none` → `"parameters": null`; `Opt.some(emptyParams)` → `"parameters": {}`; both round-trip preserving. Proposed `block` names (mirror shipped section style, lettered D through H): `D. roundTripEnvelopeEnvidAndRetParams`, `E. roundTripEnvelopeHoldForAndHoldUntilParams`, `F. roundTripEnvelopeByAndMtPriorityAndSmtpUtf8Params`, `G. reversePathNullWithParamsRoundTrip`, `H. reversePathMailboxWithoutParamsRoundTrip`, `I. parametersOptNoneDistinctFromEmptyObject`. |
| `tests/serde/mail/tserde_submission_status.nim` | **TO-CREATE** (~200L) | New file | `UndoStatus` round-trip per variant and reject-unknown (`"deferred"` → `Err`, pinning G3's closed-enum commitment); `DeliveryStatus` composite round-trip (including `Parsed*` raw-backing fields); `DeliveryStatusMap` round-trip preserving key ordering (exercises `distinct Table[RFC5321Mailbox, DeliveryStatus]` serde). Proposed `block` names: `undoStatusPendingRoundTrip`, `undoStatusFinalRoundTrip`, `undoStatusCanceledRoundTrip`, `undoStatusUnknownIsRejected`, `deliveryStatusRoundTrip`, `deliveryStatusMapRoundTripPreservesOrder`. |
| `tests/serde/mail/tserde_email_submission.nim` | **TO-CREATE** (~350L) | New file | `AnyEmailSubmission` dispatch round-trip — one block per phantom variant, confirming the wire-`undoStatus` field drives `fromJson` dispatch; `EmailSubmissionBlueprint` toJson-only wire shape (pin absence of `fromJson` via a block that constructs, serialises, and does **not** attempt to deserialise); `EmailSubmissionFilterCondition` toJson-only with representative field combinations (`Opt.some(NonEmptyIdSeq)` for `identityIds`; `Opt.some(UndoStatus)` for `undoStatus`; `Opt.some(UTCDate)` for `before`/`after`); `EmailSubmissionComparator` including the `sentAt` wire-token vs `sendAt` field-name mismatch (G19 — the wire emits `"sentAt"` even though the entity property is named `sendAt`); `IdOrCreationRef` toJson-only for both arms (`directRef` → JSON string; `creationRef` → JSON string with `#` prefix). Proposed `block` names: `anyEmailSubmissionPendingRoundTrip`, `anyEmailSubmissionFinalRoundTrip`, `anyEmailSubmissionCanceledRoundTrip`, `blueprintToJsonOnlyNoFromJson`, `filterConditionAllFieldsPopulated`, `filterConditionOnlyUndoStatus`, `comparatorSentAtTokenNotSendAt`, `comparatorAscendingByEmailId`, `idOrCreationRefDirectWire`, `idOrCreationRefCreationWire`. |

---

### 8.4. Existing-file appends

| File | Status | Additions |
|------|--------|-----------|
| `tests/protocol/tmail_builders.nim` | **SHIPPED** (766L with §O — the `addEmailSubmissionAndEmailSet` wire anchor block) | Append blocks for the 5 simple builders: `addEmailSubmissionGet`, `addEmailSubmissionChanges`, `addEmailSubmissionQuery`, `addEmailSubmissionQueryChanges`, `addEmailSubmissionSet` (simple, non-compound). One `block` per method with a wire-shape assertion table (method name, argument projection) plus one error-rail case per method. Existing `addEmailSubmissionAndEmailSet` block extended with the `getBoth` cross-entity matrix (§8.6) realised as unit-tier representatives — five named blocks, one per scenario row. Proposed `block` names for the 5 simple builders (mirroring existing `tmail_builders.nim` naming): `P. addEmailSubmissionGetInvocation`, `Q. addEmailSubmissionChangesInvocation`, `R. addEmailSubmissionQueryInvocation`, `S. addEmailSubmissionQueryChangesInvocation`, `T. addEmailSubmissionSetSimpleInvocation`. Extend §O with six cross-entity blocks: `O.2 getBothBothSucceed`, `O.3 getBothInnerMethodError`, `O.4 getBothInnerAbsent`, `O.5 getBothInnerMcIdMismatch`, `O.6 getBothOuterNotCreatedSole`, `O.7 getBothOuterIfInStateMismatch`. |
| `tests/protocol/tmail_entities.nim` | **SHIPPED** (308L) | One new block: `EmailSubmission` entity registration anchoring the capability URI (`urn:ietf:params:jmap:submission`), method namespace (`EmailSubmission/*`), and `toJson(EmailSubmissionFilterCondition)` surface. Mirrors the existing `Mailbox` / `Email` / `Identity` entity blocks. Proposed `block` name: `emailSubmissionEntityRegisteredWithSubmissionCapability`. |
| `tests/protocol/tmail_method_errors.nim` | **SHIPPED** (367L) | One block covering submission-specific `MethodError` surface (e.g., `accountNotFound` on `EmailSubmission/set` flows, `stateMismatch` on `ifInState` mismatch). Reference-only for the 8 `SetError` variants — existence already classified in `trfc_8620.nim`; the **applicability** matrix (§8.8) drives net-new tests. Proposed `block` name: `emailSubmissionSetMethodErrorSurface`. |
| `tests/serde/mail/tserde_mail_capabilities.nim` | **SHIPPED** (314L) | Append: `SubmissionExtensionMap` distinct-wrapper round-trip after the G25 amendment. Case-insensitive key behaviour (`"X-FOO"` and `"x-foo"` collide as the same key under the `RFC5321Keyword` equality). Migration probe: JSON originally serialised under the pre-G25 `OrderedTable[string, seq[string]]` shape still parses into the new distinct type (forwards-compat pin — the wire is unchanged). Proposed `block` names: `W. submissionExtensionMapRoundTripPreservesOrder`, `X. submissionExtensionMapCaseInsensitiveKey`, `Y. submissionExtensionMapParsesLegacyWireShape`. |
| `tests/compliance/trfc_8620.nim` | **SHIPPED** (with `rfc8621_submissionErrorsClassified` block) | Append: one block anchoring RFC 8621 §7 constraint table — a compile-time `static:` assertion per row of the 27-row table in G1 §1.4 that the Nim type named for each constraint is reachable and of the documented shape. The shipped `rfc8621_submissionErrorsClassified` block already pins the 8-variant SetError surface per G23; the new block pins every other row in the matrix. Proposed `block` name: `rfc8621Section7ConstraintTableCompileTimeAnchor`. |

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
| `EmailSubmission[usPending]` | `cancelUpdate(s)` | ✅ compiles | `temail_submission.nim` unit block `cancelUpdateProducesSetUndoStatusToCanceled` |
| `EmailSubmission[usFinal]` | `cancelUpdate(s)` | ❌ `assertNotCompiles` | `temail_submission.nim` `static:` block `phantomArrowStaticRejectsFinalAndCanceled` |
| `EmailSubmission[usCanceled]` | `cancelUpdate(s)` | ❌ `assertNotCompiles` | Same block |
| `AnyEmailSubmission.asPending()` | projection when `state == usPending` | ✅ `Opt.some` with payload preserved | `temail_submission.nim` unit block `toAnyPendingBranchPreserved` |
| `AnyEmailSubmission.asFinal()` / `asCanceled()` | projection when `state == usPending` | ❌ compile error — branch fields sealed (Pattern A); accessor returns `Opt.none` | `temail_submission.nim` block `existentialBranchAccessorContract` — pins accessor visibility, compile-time refusal of raw-name and deprecated public-name brace construction, and the 3 × 3 `Opt[T]` projection matrix |

The existential-dispatch row (post-sealing) is **compile-time
enforced** at the API surface: the branch fields have been renamed to
module-private `rawPending`/`rawFinal`/`rawCanceled` and external
consumers read via the `asPending`/`asFinal`/`asCanceled` accessor
family. Wrong-branch field access is no longer writable at the call
site — a regression would need to either touch the case-object fields
inside the `email_submission` module itself or break the `Opt[T]`
return-type shape. The test block does not attempt
`doAssertRaises(FieldDefect)`: under `--panics:on` (project default,
`config.nims:23`) `FieldDefect` is fatal (`rawQuit(1)`, no unwinding,
no `finally`), so the runtime exception path is unreachable as well
as uncatchable. The block instead pins the stronger compile-time
contract via `assertNotCompiles` + `Opt.none` shape probes.

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
| 3 | Outer succeeds, inner absent from response | `ok` | (no invocation in response) | Structured `Err` — NOT silent default. The shipped `getBoth` produces an error describing the missing handle; test pins the exact type |
| 4 | Outer succeeds, inner present but `methodCallId` mismatch | `ok` | `ok` but under wrong `methodCallId` | `Err(serverFail)`-like — surfaces as a server-routing error; documents that `NameBoundHandle.callId` must match |
| 5 | Outer `notCreated` sole entry | `ok` but `notCreated` non-empty | (no invocation per RFC §7.5 when no creation succeeded and no update/destroy targets existed) | `Ok` with empty `emailSet.created` — the shipped code does not synthesise the inner response |
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
decoding path; a wire value not in the enum produces a
`SerdeViolation` with `svkEnumValueUnknown` (or the shipped equivalent
variant). Pin the exact path and kind per row.

---

### 8.8. `SetError` applicability matrix (G1-specific)

Mirrors F2 §8.11 in structure, calibrated to the 9 submission-relevant
`SetError` variants (8 submission-specific plus standard `tooLarge`).
Critical framing: this is **applicability** (which error applies where),
not **existence** (already tested in `tmail_errors.nim` and pinned in
`tests/compliance/trfc_8620.nim` via the shipped
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
| `setCannotUnsend` | §7.5 ¶6 | ✗ | ✓ | **New test** — pending → canceled refused when server determines unsend impossible (e.g., message already flushed to SMTP) |

The single net-new test is the `setCannotUnsend` applicability pin —
this variant is update-only and exercises the reverse applicability
from the other eight. Proposed block name:
`emailSubmissionSetCannotUnsendOnUpdate`.

**Native enum iteration is mandatory** for this matrix. The
implementation MUST fold via `for kind in SetErrorType:` (precedent:
`terrors.nim:428` and F2 §8.11). No helper combinator is introduced.
The explicit loop makes the variant set visible at the call site and
the compiler enforces exhaustiveness via `case` inside the loop body.

---

### 8.9. Infrastructure additions (fixtures, generators, assertions)

Mirrors F2 §8.6. Additions only — **no new test-support modules**.

**Shipped state as of the G1 implementation merge.** Per the grep
evidence, `tests/mfixtures.nim`, `tests/mproperty.nim`, and
`tests/massertions.nim` contain **zero** submission-type factories,
generators, or assertion helpers (the only submission references are in
session-capability stubs at `mfixtures.nim:239,262` and
`mproperty.nim:505`, which construct `ckSubmission` capability entries,
not domain-entity values). Every proposal below is NET-NEW. The shipped
smoke tests (`temail_submission_blueprint.nim`, `tonsuccess_extras.nim`,
`tserde_submission_envelope.nim`) construct fixtures inline using the
public smart constructors — that pattern remains valid for low-volume
test files. Extract a factory when a construction recipe is repeated
across three or more blocks; otherwise inline.

#### 8.9.1. Reuse-mapping table

Each new factory / generator / assertion template lists its closest
existing precedent so the implementation PR follows the established
pattern rather than reinventing it. Format matches F2 §8.6.1.

| New item | Closest existing precedent | Path:Line |
|----------|---------------------------|-----------|
| `makeRFC5321Mailbox(raw = "user@example.com")`, `makeFullRFC5321Mailbox()` (quoted-string local-part + IPv6 address-literal) | `makeAccountId` / `makeFullAccountId` (identifier-shaped factories) | `mfixtures.nim:~200` |
| `makeRFC5321Keyword(raw = "X-VENDOR-FOO")`, `makeOrcptAddrType(raw = "rfc822")` | Identifier-shaped factories | `mfixtures.nim:~200` |
| `makeSubmissionParam(kind: SubmissionParamKind)` — dispatches on `kind` and produces a minimal typed value per variant (nullary arm returns `smtpUtf8Param()`; all others use a fixed canonical payload) | `makeSetErrorInvalidProperties` / `makeSetErrorAlreadyExists` (per-variant naming for case-object factories) | `mfixtures.nim:302-313` |
| `makeFullSubmissionParams()` populated with one of each of the 11 well-known variants plus one `spkExtension` | `makeFullEmailBlueprint` (composite populated factory) | `mfixtures.nim:1154` |
| `makeSubmissionAddress(mailbox = makeRFC5321Mailbox())`, `makeFullSubmissionAddress()` (full parameterised via `makeFullSubmissionParams()`) | `makeEmailAddress` / `makeFullEmailAddress` | `mfixtures.nim:~400` |
| `makeNullReversePath()` (infallible wrapper over `nullReversePath()`), `makeMailboxReversePath(addr = makeSubmissionAddress())` | No direct precedent — wraps the shipped infallible ctor | (new row) |
| `makeEnvelope(mailFrom = makeMailboxReversePath(), rcptTo = @[makeSubmissionAddress()])`, `makeFullEnvelope()` | `makeFullEmailBlueprint` composite style | `mfixtures.nim:1154` |
| `makeNonEmptyRcptList(items = @[makeSubmissionAddress()])` | `makeNonEmptyMailboxIdSet(ids)` | `mfixtures.nim:1069` |
| `makeEmailSubmission[S: static UndoStatus](...)` — generic fixture returning `EmailSubmission[S]`; callers pass `usPending`/`usFinal`/`usCanceled` | No direct precedent — phantom-parameter-generic factory | (new row; genuinely novel pattern) |
| `makeAnyEmailSubmission(state: UndoStatus)` — returns `AnyEmailSubmission` with the branch matching `state` populated | Per-variant case-object factory | `mfixtures.nim:302-313` |
| `makeEmailSubmissionBlueprint(identityId, emailId, envelope = Opt.none(Envelope))`, `makeFullEmailSubmissionBlueprint()` (with envelope + params) | `makeEmailBlueprint` / `makeFullEmailBlueprint` | `mfixtures.nim:1148, 1154` |
| `makeDeliveryStatus(smtpReply, delivered, displayed)`, `makeSmtpReply(raw = "250 OK")` | Composite typed-record factory | `mfixtures.nim:211-214` |
| `makeDeliveryStatusMap(entries: openArray[(RFC5321Mailbox, DeliveryStatus)])` | `makeNonEmptyMailboxIdSet(ids)` (distinct-table wrapper) | `mfixtures.nim:1069` |
| `makeIdOrCreationRefDirect(id)`, `makeIdOrCreationRefCreation(cid)` | Per-variant case-object factory | `mfixtures.nim:302-313` |
| `makeEmailSubmissionHandles(submissionMcid, emailSetMcid)` | `makeEmailCopyHandles` (shipped in F1 — `mfixtures.nim:~1200`) | `mfixtures.nim:~1200` |
| `genRFC5321Mailbox(rng, trial)` — edge-bias trial 0 = plain `Dot-string` + `Domain`; 1 = IPv4-literal; 2 = IPv6-literal; 3 = `Quoted-string` local; 4 = General-address-literal; random from 5 | `genKeyword(rng, trial)` (edge-biased RFC-grammar generator) | `mproperty.nim:~2000` |
| `genInvalidRFC5321Mailbox(rng, trial)` — trailing-dot, unclosed-quote, bracketless-IPv6, overlong local-part | `genInvalidKeyword(rng, trial)` | `mproperty.nim:~2100` |
| `genRFC5321Keyword(rng, trial)`, `genSubmissionParam(rng, trial)`, `genSubmissionParams(rng, trial)` | `genSetError(rng)` (variant enumeration with edge bias) | `mproperty.nim:628` |
| `genUndoStatus(rng)` — closed enum; 3 values with equal-weight sampling | `genMethodErrorType(rng)` (catch-all-less closed enum — but `UndoStatus` is itself closed per G3) | `mproperty.nim:~1500` |
| `genDeliveredState(rng, trial)`, `genDisplayedState(rng, trial)` — include `dsOther` / `dpOther` raw-backing adversarial strings at trials ≥ 5 | `genMethodErrorType(rng)` (enum with catch-all) | `mproperty.nim:~1500` |
| `genSmtpReply(rng, trial)` — digit-class edge-bias per property group I | `genBlueprintErrorTrigger` (J-11 trigger-builder pattern) | `mproperty.nim:2717` |
| `genEmailSubmission[S: static UndoStatus](rng, trial)` — generic generator for the phantom-typed entity | `genEmailBlueprint(rng, trial)` (trial-biased composition J-10) | `mproperty.nim:2473` |
| `genAnyEmailSubmission(rng, trial)` — trials 0/1/2 force `usPending`/`usFinal`/`usCanceled`; random from trial 3 | `genEmailBlueprint(rng, trial)` | `mproperty.nim:2473` |
| `genEmailSubmissionBlueprint(rng, trial)`, `genEmailSubmissionUpdate(rng, trial)`, `genEmailSubmissionFilterCondition(rng, trial)` | `genEmailBlueprint(rng, trial)` | `mproperty.nim:2473` |
| `assertPhantomVariantEq(actual: AnyEmailSubmission, expected: AnyEmailSubmission)` — asserts `state` field equality plus branch-dispatched payload equality | `setErrorEq` (case-object arm-dispatch equality helper) | `mfixtures.nim:707` |
| `assertDeliveryStatusMapEq(actual, expected: DeliveryStatusMap)` — ordered-table equality honouring insertion order | `nonEmptyMailboxIdSetEq` (distinct-table equality) | `validation.nim:83` pattern |
| `assertSubmissionParamKeyEq(a, b: SubmissionParamKey)` — identity across the 12-kind matrix | `assertSetOkEq` (variant-dispatch equality wrapper) | `massertions.nim:~200` |
| `assertIdOrCreationRefWire(v: IdOrCreationRef, expected: string)` — wire-form pin; `directRef(id)` → `$id`; `creationRef(cid)` → `"#" & $cid` | `assertJsonFieldEq` (wire-shape pin) | `massertions.nim:~150` |

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
| `anyEmailSubmissionEq` | **NEEDED** | `AnyEmailSubmission` is a case object with three branches; Nim requires an explicit arm-dispatch `==` for case objects (derived `==` does not compile per the codebase-wide `nim-type-safety.md` rule). Shipped as `assertPhantomVariantEq` wrapper. |
| `emailSubmissionEq[S]` | **REDUNDANT** | Plain object; derived `==` is structural across all fields (`Id`, `Opt[Envelope]`, `UTCDate`, `Opt[DeliveryStatusMap]`, `seq[BlobId]`). Phantom parameter `S` does not affect equality. |
| `submissionParamEq` | **NEEDED** | `SubmissionParam` is a case object; requires arm-dispatch. |
| `submissionParamKeyEq` | **NEEDED-trivial** | `SubmissionParamKey` is a case object with one-arm dispatch (`spkExtension` carries `extName`; all others are identity by `kind` alone). One-line implementation. |
| `submissionParamsEq` | **NEEDED-trivial** | `distinct OrderedTable[SubmissionParamKey, SubmissionParam]`; borrow `==` via `defineOrderedTableDistinctOps` (or analogous template), delegating element equality to `submissionParamEq`. |
| `envelopeEq` | **REDUNDANT** | Plain object; `ReversePath` + `NonEmptyRcptList` both derive structurally through their constituent plain-object fields. |
| `reversePathEq` | **NEEDED-trivial** | Case object with two arms; one-line arm-dispatch. |
| `submissionAddressEq` | **REDUNDANT** | Plain object; `RFC5321Mailbox` + `Opt[SubmissionParams]` both have `==`. |
| `deliveryStatusMapEq` | **NEEDED-trivial** | `distinct Table[RFC5321Mailbox, DeliveryStatus]`; borrowed `==` honouring insertion order. |
| `deliveryStatusEq` | **REDUNDANT** | Plain object; all three fields (`SmtpReply`, `ParsedDeliveredState`, `ParsedDisplayedState`) have derivable `==` (the `Parsed*` wrappers are plain objects). |
| `smtpReplyEq` | **REDUNDANT** | `distinct string`; `{.borrow.}` `==` shipped (`submission_status.nim`). |
| `idOrCreationRefEq` | **NEEDED-trivial** | Case object with two arms. One-line. |
| `emailSubmissionBlueprintEq` | **REDUNDANT** | Plain object with three fields; derived `==` is structural. Shipped test `inequalityOnIdentity` at `temail_submission_blueprint.nim:85-91` relies on this. |
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
| §7 ¶3 | `identityId` MUST reference a valid Identity in the account | `Id` (referential; server-authoritative) | `tserde_email_submission.nim` blueprint round-trip — client cannot enforce server-side referential integrity; pin only the structural `Id` shape |
| §7 ¶3 | `emailId` MUST reference a valid Email in the account | `Id` | Same as above |
| §7 ¶3 | `threadId` is immutable, server-set | Not in `EmailSubmissionBlueprint`; only on read model | `temail_submission.nim` blueprint-construction blocks pin absence; `tserde_email_submission.nim` pins presence on the read-model round-trip |
| §7 ¶4 | `envelope` is immutable; if null, server synthesises from Email headers | `Opt[Envelope]` on blueprint (G14); `Opt[Envelope]` on entity | `tserde_email_submission.nim` `blueprintOptNoneEnvelopePassesThrough`; `temail_submission_blueprint.nim` `defaultEnvelopeIsNone` (shipped, line 79) |
| §7 ¶5 | `envelope.mailFrom` cardinality: exactly 1; MAY be empty string; parameters permitted on null path | `ReversePath` (`rpkNullPath + Opt[SubmissionParams]` or `rpkMailbox`) (G32) | `tserde_submission_envelope.nim` `nullReversePathWireShape` (shipped); `envelopeNullMailFromWithParams` (§8.2.3) |
| §7 ¶5 | `envelope.rcptTo` cardinality: 1..N | `NonEmptyRcptList` (G7) | `tserde_submission_envelope.nim` `emptyRcptToIsRejected` (shipped, line 110) |
| §7 ¶5 | `envelope.Address.email` is RFC 5321 Mailbox | `RFC5321Mailbox` (G6) | `tsubmission_mailbox.nim` (TO-ADD); property group A |
| §7 ¶5 | `envelope.Address.parameters` is `Object \| null` | `Opt[SubmissionParams]` on `SubmissionAddress` (G34) | `tserde_submission_envelope.nim` `parametersOptNoneDistinctFromEmptyObject` (TO-ADD appended block) |
| §7 ¶5 | `envelope.Address.parameters` keys are RFC 5321 esmtp-keywords | `SubmissionParamKey` + `RFC5321Keyword` (G8, G8a) | `tsubmission_params.nim` (TO-ADD) `paramKey` derivation block; property group D |
| §7 ¶7 | `undoStatus` values: "pending", "final", "canceled" | `UndoStatus` enum (closed; phantom parameter) (G3) | `tserde_submission_status.nim` `undoStatusUnknownIsRejected` (TO-ADD); `anyUndoStatusUnknownValue` in `tadversarial_mail_g.nim` Block 4 |
| §7 ¶7 | Only transition: "pending" → "canceled" via client update | `cancelUpdate(s: EmailSubmission[usPending])` typed arrow (G4) | `temail_submission.nim` (TO-ADD) `static:` block `phantomArrowStaticRejectsFinalAndCanceled` — the load-bearing compile-time pin |
| §7 ¶8 | `deliveryStatus` is per-recipient, keyed on email address | `DeliveryStatusMap` (distinct Table keyed on `RFC5321Mailbox`) (G9) | `tsubmission_status.nim` (TO-ADD) `deliveryStatusMapCountDelivered` etc. |
| §7 ¶8 | `delivered` values: "queued", "yes", "no", "unknown" | `DeliveredState` enum + `dsOther` catch-all (G10) | `tsubmission_status.nim` per-variant round-trip; property group H |
| §7 ¶8 | `displayed` values: "unknown", "yes" | `DisplayedState` enum + `dpOther` catch-all (G11) | Symmetric with above |
| §7 ¶8 | `smtpReply` is structured SMTP reply text | `SmtpReply` (distinct string, validated) (G12) | `tsubmission_status.nim` happy-path blocks; property group I; adversarial block 5 |
| §7 ¶9 | `dsnBlobIds`, `mdnBlobIds` are server-set arrays | `seq[BlobId]` on read model only | `tserde_email_submission.nim` entity round-trip blocks |
| §7.5 ¶1 | Only `undoStatus` updatable post-create | `EmailSubmissionUpdate` single variant (G16) | `temail_submission_update.nim` (TO-ADD) — pins single-variant shape |
| §7.5 ¶3 | `onSuccessUpdateEmail` applies PatchObject to Email on success | `NonEmptyOnSuccessUpdateEmail` = `distinct Table[IdOrCreationRef, EmailUpdateSet]` (G22, G35, + shipped NonEmpty wrapper per implementation reality note) | `tonsuccess_extras.nim` (shipped) ; wire-shape serde block E |
| §7.5 ¶3 | `onSuccessDestroyEmail` destroys Email on success | `NonEmptyOnSuccessDestroyEmail` = `distinct seq[IdOrCreationRef]` (G22, G35) | `tonsuccess_extras.nim` (shipped); wire-shape serde block F |
| §7.5 ¶5 | SetError `invalidEmail` includes problematic property names | Existing `setInvalidEmail` + `invalidEmailPropertyNames` accessor (G23) | `tmail_method_errors.nim` append; existence in `trfc_8620.nim` (shipped) |
| §7.5 ¶5 | SetError `tooManyRecipients` includes max count | Existing `setTooManyRecipients` + `maxRecipientCount` accessor (G23) | Same |
| §7.5 ¶5 | SetError `noRecipients` when rcptTo empty | Existing `setNoRecipients` (G23) | Same |
| §7.5 ¶5 | SetError `invalidRecipients` includes bad addresses | Existing `setInvalidRecipients` + `invalidRecipients` accessor (G23) | Same |
| §7.5 ¶5 | SetError `forbiddenMailFrom` when SMTP MAIL FROM disallowed | Existing `setForbiddenMailFrom` (G23) | Same |
| §7.5 ¶5 | SetError `forbiddenFrom` when RFC 5322 From disallowed | Existing `setForbiddenFrom` (G23) | Same |
| §7.5 ¶5 | SetError `forbiddenToSend` when user lacks send permission | Existing `setForbiddenToSend` (G23) | Same |
| §7.5 ¶6 | SetError `cannotUnsend` when cancel fails | Existing `setCannotUnsend` (G23) | `tmail_method_errors.nim` append `emailSubmissionSetCannotUnsendOnUpdate` (the single NEW applicability test per §8.8) |
| §1.3.2 | Capability `maxDelayedSend` is `UnsignedInt` seconds | Existing `SubmissionCapabilities.maxDelayedSend` | `tserde_mail_capabilities.nim` (shipped) |
| §1.3.2 | Capability `submissionExtensions` is EHLO-name → args map | `SubmissionExtensionMap` (distinct OrderedTable) (G25) | `tserde_mail_capabilities.nim` append — distinct-wrapper round-trip + case-insensitive key (§8.4) |

The matrix is a **living artefact**: any new §7 promise (added under
G40+ architecture amendments or later G parts) MUST add a row here
before the implementation merges. The matrix is the single artefact
that proves test-spec adequacy for RFC §7 constraints by inspection.

---

### 8.11. Verification commands

Implementation PR verification sequence:

- `just build` — shared library compiles; no new warnings.
- `just test` — the fast suite runs green. **Note:** per precedent
  from `tadversarial_mail_f.nim` and `tprop_mail_e.nim`, the new files
  `tests/property/tprop_mail_g.nim` and `tests/stress/tadversarial_mail_g.nim`
  will be added to `tests/testament_skip.txt` at creation time. They
  run under `just test-full`, not the fast suite. Agent validation
  workflows should use `just test` for quick iteration and
  `just test-full` for final verification.
- `just test-full` — full suite including property and stress tiers.
- `just analyse` — nimalyzer passes without new suppressions.
- `just fmt-check` — nph formatting unchanged.
- `just ci` — full pipeline green (reuse + fmt-check + lint + analyse + test).
- Single-file invocation example: `testament pat tests/unit/mail/temail_submission.nim`
  (works per-file once a test is failing in the suite; preferred over
  rerunning the full suite during iteration).

The compile-only smoke (`tests/compile/tcompile_mail_g_public_surface.nim`,
**SHIPPED** — see §8.2.2) fails loudly at the `static:` block if any new
public symbol is not re-exported through `src/jmap_client.nim`'s
cascade. Variant-kind exhaustiveness is witnessed by the internal
production `case` sites in `src/jmap_client/mail/email_submission.nim`,
`submission_param.nim`, `serde_email_submission.nim`, and
`serde_submission_envelope.nim` on every build — no dedicated probe
needed. The `cancelUpdate` phantom-typed arrow's compile-time rejection
is pinned in `temail_submission.nim`'s `static:` block (TO-ADD,
§8.3) — this is the single most important compile-time test in G2.

Property tests in `tprop_mail_g.nim` (TO-ADD) cover the RFC 5321 Mailbox
totality (A), strict/lenient coverage (B), `SubmissionParams`
insertion-order round-trip (C), `SubmissionParamKey` identity algebra
(D), `AnyEmailSubmission` round-trip (E), `cancelUpdate` value-level
invariant (F), `NonEmptyEmailSubmissionUpdates` duplicate-Id (G),
`ParsedDeliveredState.rawBacking` preservation (H), and `parseSmtpReply`
Reply-code boundary (I). Coverage matrix §8.13 is the single inspection
point for "is every G1 decision pinned by a test?" — the **SHIPPED**
tags in that table are the authoritative list of what is already green
against the G1 implementation.

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
| G1 | Module organisation across 5 L1 + 3 L2 files | `tcompile_mail_g_public_surface.nim` (SHIPPED) | Symbol re-export cascade validates the split mechanically; no dedicated block |
| G2 | `EmailSubmission[S: static UndoStatus]` phantom-typed entity + `AnyEmailSubmission` wrapper | `temail_submission.nim` (TO-ADD) | `toAnyPendingBranchPreserved`, `toAnyFinalBranchPreserved`, `toAnyCanceledBranchPreserved`, `anyEmailSubmissionPendingRoundTrip` (serde), property group E |
| G3 | `[S: static UndoStatus]` generic as DataKinds encoding; enum IS phantom | `temail_submission.nim` `static:` block | `phantomArrowStaticRejectsFinalAndCanceled` — load-bearing compile-time pin; also `anyUndoStatusUnknownValue` in adversarial block 4 (closed-enum commitment) |
| G4 | `cancelUpdate(s: EmailSubmission[usPending])` typed arrow at L1 | `temail_submission.nim` | `cancelUpdateProducesSetUndoStatusToCanceled`; property group F |
| G6 | Distinct `RFC5321Mailbox` + `SubmissionAddress` | `tsubmission_mailbox.nim` (TO-ADD); property group A | 8 grammar blocks; adversarial block 1 |
| G7 | `NonEmptyRcptList` strict/lenient parser pair | `tserde_submission_envelope.nim` (shipped `emptyRcptToIsRejected`); property group B | Block `envelopeDuplicateRcptToStrict` / `envelopeDuplicateRcptToLenient` in adversarial block 3 |
| G8 | Typed sealed sum + extension arm for `SubmissionParam` | `tsubmission_params.nim` (TO-ADD) | 12 per-kind blocks per §8.7 matrix |
| G8a | `distinct OrderedTable[SubmissionParamKey, SubmissionParam]` | `tsubmission_params.nim`; property groups C, D | `paramKey` derivation blocks |
| G8b | 11 typed variants + extension arm | `tsubmission_params.nim` | §8.7 matrix (one block per row) |
| G8c | Per-parameter typed payloads | `tsubmission_params.nim` | Per-variant blocks |
| G9 | `distinct Table[RFC5321Mailbox, DeliveryStatus]` (`DeliveryStatusMap`) | `tsubmission_status.nim` (TO-ADD) | `deliveryStatusMap*` blocks; `tserde_submission_status.nim` round-trip |
| G10 | `DeliveredState` + `dsOther` catch-all + `ParsedDeliveredState` | `tsubmission_status.nim`; property group H | Per-variant round-trip blocks; raw-backing preservation |
| G11 | `DisplayedState` + `dpOther` catch-all | Same pattern as G10 | `displayedState*` blocks |
| G12 | `distinct SmtpReply` + smart ctor | `tsubmission_status.nim`; property group I; adversarial block 5 | Happy + 14 rejection rows |
| G13 | `EmailSubmissionBlueprint` naming | `temail_submission_blueprint.nim` (shipped) | `minimalBlueprint` + all 7 shipped blocks |
| G14 | `Opt[Envelope]`; `None` = server synthesises | `temail_submission_blueprint.nim` (shipped `defaultEnvelopeIsNone` at line 79) | SHIPPED |
| G15 | Accumulating-error `Blueprint` smart ctor | `temail_submission_blueprint.nim` (TO-ADD append) | `blueprintAccumulatesBothIdErrors` |
| G16 | Single-variant `EmailSubmissionUpdate` | `temail_submission_update.nim` (TO-ADD) | `setUndoStatusToCanceledValueShape` |
| G17 | `NonEmptyEmailSubmissionUpdates` | `temail_submission_update.nim`; property group G | `parseUpdatesRejectsEmpty`, `parseUpdatesRejectsDuplicateId` |
| G18 | Typed `EmailSubmissionFilterCondition` with `NonEmptyIdSeq` | `tserde_email_submission.nim` (TO-ADD) | `filterConditionAllFieldsPopulated`, `filterConditionOnlyUndoStatus` |
| G19 | `EmailSubmissionSortProperty` enum + `esspOther` catch-all | `tserde_email_submission.nim` | `comparatorSentAtTokenNotSendAt` — pins the wire-token vs field-name mismatch |
| G20 | `addEmailSubmissionAndEmailSet` AND-connector naming | `tmail_builders.nim` §O (SHIPPED wire anchor) | SHIPPED |
| G21 | Specific `EmailSubmissionHandles` (no generic) | `tmail_builders.nim` §O; §8.6 matrix | `getBoth*` blocks; compile test symbol pin |
| G22 | Typed `EmailUpdateSet` values with `IdOrCreationRef` keys | `tonsuccess_extras.nim` (SHIPPED `toJsonNonEmptyOnSuccessUpdateEmail*` blocks) | SHIPPED |
| G23 | No new `SetError` variants; reuse 8 + `tooLarge` | `trfc_8620.nim` (SHIPPED `rfc8621_submissionErrorsClassified`); `tmail_method_errors.nim` append | Existence SHIPPED; applicability §8.8 |
| G24 | No new payload-less accessors | Structural decision; no executable test | — (tagged "structural") |
| G25 | `SubmissionExtensionMap` distinct wrapper | `tserde_mail_capabilities.nim` append | `submissionExtensionMapRoundTripPreservesOrder`, `...CaseInsensitiveKey`, `...ParsesLegacyWireShape` |
| G26 | Serde error rail via `SerdeViolation` + `JsonPath` | Every `tserde_*.nim` (TO-ADD) block uses `assertSvKind` / `assertSvPath` per `massertions.nim` | Pattern enforced across all serde test files |
| G27 | `fromJson` synthesises `Opt.none` when wire is null | `tserde_email_submission.nim` | `blueprintOptNoneEnvelopePassesThrough` |
| G32 | `ReversePath` sum with nullable params | `tserde_submission_envelope.nim` (shipped `nullReversePathWireShape`); `envelopeNullMailFromWithParams` in adversarial block 3 | SHIPPED + TO-ADD |
| G33 | `ReversePath` at `Envelope.mailFrom` field (not on `SubmissionAddress`) | `tserde_submission_envelope.nim` | `reversePathNullWithParamsRoundTrip`, `reversePathMailboxWithoutParamsRoundTrip` |
| G34 | `Opt[SubmissionParams]` nullability | `tserde_submission_envelope.nim` | `parametersOptNoneDistinctFromEmptyObject` |
| G35 | `IdOrCreationRef` sum for `onSuccess*` keys | `tonsuccess_extras.nim` (SHIPPED `parseNonEmptyOnSuccess*AcceptsArmDistinct*`); §8.3 appends | SHIPPED + TO-ADD `idOrCreationRefVsReferencableAreDistinctTypes` |
| G36 | `IdOrCreationRef` vs `Referencable[T]` separate types | `tonsuccess_extras.nim` append | `idOrCreationRefVsReferencableAreDistinctTypes` compile-time pin |
| G37 | `Opt[NonEmptyIdSeq]` filter list rejects empty | `tserde_email_submission.nim` | `filterConditionRejectsEmptyIdSeq` |
| G38 | Pattern A sealing on `EmailSubmissionBlueprint` | `temail_submission_blueprint.nim` (shipped `sealingContract` at line 46) | SHIPPED |
| G39 | `SetResponse[EmailSubmissionCreatedItem]` type alias | `tcompile_mail_g_public_surface.nim` (shipped — `EmailSubmissionSetResponse` symbol pin); `tserde_email_submission.nim` | SHIPPED + TO-ADD entity-level round-trip |

The matrix shows full coverage across 37 G-decisions plus the
implementation-reality divergences (`NonEmptyOnSuccessUpdateEmail` /
`NonEmptyOnSuccessDestroyEmail` NonEmpty wrappers, `toAny`
phantom-boundary helpers, 96-assertion compile test). Where a row is
tagged `— (tagged "structural")`, the decision has no executable test
surface: adopting or rejecting it is visible in the codebase by
inspection, not by test.

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
| `fromJson` absence pins for creation-only types | Shipped `serde_email_submission.nim` simply does not declare `fromJson` for `EmailSubmissionBlueprint`, `EmailSubmissionFilterCondition`, `EmailSubmissionComparator`, `IdOrCreationRef`. The `grep -n 'fromJson' src/jmap_client/mail/serde_email_submission.nim` check is the primary verification, matching F2 §8.2.2's position. |
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
