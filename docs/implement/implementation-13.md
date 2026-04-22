# Mail Part G Implementation Plan (G2 test-side only)

Part G's source-side (G1) has already shipped per
`docs/implement/implementation-12.md`. This plan turns the companion
test specification (`docs/design/12-mail-G2-design.md`) into ordered
build steps. G2 pins every G1 promise — phantom-typed
`EmailSubmission[S: static UndoStatus]`, the existential
`AnyEmailSubmission` wrapper, the 12-variant `SubmissionParam` algebra,
RFC 5321 Mailbox grammar, the cross-entity `EmailSubmissionHandles`
`getBoth` — through unit, serde, protocol, property, and adversarial
test layers.

**Scope note.** Test material only — no source code changes. Some
material is **SHIPPED** against the G1 landing (compile-only smoke
`tests/compile/tcompile_mail_g_public_surface.nim`, plus
`temail_submission_blueprint.nim` 92L, `tonsuccess_extras.nim` 124L,
`tserde_submission_envelope.nim` 119L, and several protocol /
compliance / capability blocks — see G2 §8.2 state-of-play table and
the `SHIPPED` rows in §8.13 coverage matrix); this plan covers the
TO-ADD work plus the §8.10 and §8.13 audit walk. Where G2 says
SHIPPED, the engineer MUST NOT re-implement — extend or leave alone.

7 phases, one commit each. Every phase passes `just ci` before
committing. Cross-cutting conventions from G2 §8.1 apply to every new
block:

- Test idiom is `block <name>:` + `assertOk` / `assertErr` / `assertEq` /
  `assertLen` / `assertSvKind` / `assertSvPath` from
  `tests/massertions.nim`, plus raw `doAssert` for inline checks. No
  `std/unittest`, no `suite` wrappers. Canonical precedents:
  `tests/unit/mail/temail_submission_blueprint.nim:20-92` and
  `tests/unit/mail/tonsuccess_extras.nim:25-124` (both shipped with G1).
- `ValidationError` is three plain strings (`typeName`, `message`,
  `value`). There is no enum classifier — tests discriminate failures
  via literal `error[i].message` checks (G2 §8.3 error-rail shape).
  Three rows in §8.3 (`NonEmptyEmailSubmissionUpdates`, `NonEmptyIdSeq`,
  per-field `EmailSubmissionBlueprint`) require a grep-then-lock step:
  run `grep -n 'validationError\|ValidationError(' src/jmap_client/mail/email_submission.nim`
  first, pin the literal string in the block assertion — do not invent.
- Enum folds use native `for variant in T:` (e.g.
  `for kind in SetErrorType:` — precedent `tests/unit/terrors.nim:428`,
  per G2 §8.8 mandatory note). No combinator abstractions.
- **No new test-support modules.** Per G2 §8.9, factories / generators
  / equality helpers land in the three existing files
  (`mfixtures.nim`, `mproperty.nim`, `massertions.nim`). Fragmenting
  the support layer for one feature is explicitly disallowed.
- `tests/property/tprop_mail_g.nim` and
  `tests/stress/tadversarial_mail_g.nim` land in
  `tests/testament_skip.txt` in the non-joinable section (precedents:
  `tests/property/tprop_mail_e.nim`,
  `tests/stress/tadversarial_mail_f.nim`). They run under
  `just test-full`, not `just test`.
- `AnyEmailSubmission` construction in tests uses the shipped `toAny`
  family (three overloads, per G1 implementation reality note G2 §8
  item 3), not brace-literal case-object construction.

Phase ordering respects test dependency chains: fixtures + generators
+ equality helpers first (every later phase consumes them); then unit
(smart-constructor pins, phantom-type `static:` block, and
`IdOrCreationRef` vs `Referencable[T]` distinction); then serde /
protocol (which reuse the typed updates from unit); then property /
adversarial that layer on top; then the coverage matrix audit.

---

## Phase 1: Test infrastructure

Foundational additions to the three existing test-support modules per
G2 §8.9. All entries in §8.9.1's reuse-mapping table are NET-NEW —
`mfixtures.nim`, `mproperty.nim`, and `massertions.nim` contain zero
submission-type factories, generators, or assertion helpers as of G1
landing.

- **Step 1:** Extend `tests/mfixtures.nim` per G2 §8.9.1's reuse-mapping
  table: per-type factories covering the RFC 5321 atoms
  (`makeRFC5321Mailbox`, `makeFullRFC5321Mailbox`, `makeRFC5321Keyword`,
  `makeOrcptAddrType`), the parameter algebra (`makeSubmissionParam`
  per-kind dispatch, `makeFullSubmissionParams`, `makeSubmissionAddress`,
  `makeFullSubmissionAddress`, `makeNullReversePath`,
  `makeMailboxReversePath`, `makeEnvelope`, `makeFullEnvelope`,
  `makeNonEmptyRcptList`), the phantom-typed entity family
  (`makeEmailSubmission[S: static UndoStatus]`,
  `makeAnyEmailSubmission`, `makeEmailSubmissionBlueprint`,
  `makeFullEmailSubmissionBlueprint`), the status-type family
  (`makeDeliveryStatus`, `makeSmtpReply`, `makeDeliveryStatusMap`),
  the reference types (`makeIdOrCreationRefDirect`,
  `makeIdOrCreationRefCreation`), and the compound handles
  (`makeEmailSubmissionHandles`). Each factory's precedent line number
  is enumerated in §8.9.1; follow the 7-step fixture protocol already
  documented at `mfixtures.nim:7-14`.
- **Step 2:** Extend `tests/mproperty.nim` with the generators per G2
  §8.9.1: `genRFC5321Mailbox`, `genInvalidRFC5321Mailbox`,
  `genRFC5321Keyword`, `genSubmissionParam`, `genSubmissionParams`,
  `genUndoStatus`, `genDeliveredState`, `genDisplayedState`,
  `genSmtpReply`, `genEmailSubmission[S: static UndoStatus]`,
  `genAnyEmailSubmission`, `genEmailSubmissionBlueprint`,
  `genEmailSubmissionUpdate`, `genEmailSubmissionFilterCondition`.
  Implement the mandatory edge-bias schedules documented in G2 §8.9.1:
  `genRFC5321Mailbox` trials 0–7 enumerate the five canonical grammar
  shapes plus two overlong-boundary and one unicode-label adversary;
  `genSubmissionParam` trials 0–11 enumerate the 12 kinds in
  declaration order, trials 12–14 pin the `spkExtension`
  case-insensitive adversary and both `spkNotify` mutual-exclusion
  cases; `genAnyEmailSubmission` trials 0/1/2 force
  `usPending`/`usFinal`/`usCanceled` respectively. Random sampling
  only begins after the documented edge-bias window.
- **Step 3:** Add equality helpers per G2 §8.9.2 classification. Three
  NEEDED helpers land as full implementations; eight NEEDED-trivial
  one-liners land alongside them. Write in `mfixtures.nim` alongside
  the shipped `setErrorEq` (line 707) — precedent; not in
  `massertions.nim` per §8.9:
  - `anyEmailSubmissionEq` (case-object arm-dispatch over three
    branches; precedent `setErrorEq`).
  - `submissionParamEq` (case-object arm-dispatch over 12 kinds).
  - `submissionParamKeyEq` (one-arm case object — `spkExtension`
    carries `extName`).
  - Eight NEEDED-trivial borrows / delegations: `submissionParamsEq`,
    `reversePathEq`, `deliveryStatusMapEq`, `idOrCreationRefEq`,
    `nonEmptyOnSuccessUpdateEmailEq`, plus three wrapper exporters for
    `assertPhantomVariantEq`, `assertDeliveryStatusMapEq`,
    `assertSubmissionParamKeyEq` per G2 §8.9.1. The wire-shape pin
    `assertIdOrCreationRefWire` lands in `tests/massertions.nim`
    (precedent: `assertJsonFieldEq` at `massertions.nim:~150`) because
    it shapes an assertion over a `JsonNode`, not an equality check.

### CI gate

Run `just ci` before committing.

---

## Phase 2: Unit tests

Per-type smart-constructor invariants per G2 §8.3 unit rows, plus the
single most load-bearing compile-time test in G2 — the phantom-type
`static:` block in `temail_submission.nim` that proves
`cancelUpdate(EmailSubmission[usFinal])` and
`cancelUpdate(EmailSubmission[usCanceled])` fail to compile. A
regression there silently collapses the typed-transition arrow to a
runtime check.

- **Step 4:** Create `tests/unit/mail/temail_submission.nim` (~250L)
  per G2 §8.3: three `toAny` per-phantom-variant smoke blocks
  (`toAnyPendingBranchPreserved`, `toAnyFinalBranchPreserved`,
  `toAnyCanceledBranchPreserved`); value-level
  `cancelUpdateProducesSetUndoStatusToCanceled`; the load-bearing
  `static:` block `phantomArrowStaticRejectsFinalAndCanceled` with
  `assertNotCompiles` on both `usFinal` and `usCanceled`; the runtime
  companion block `existentialWrongBranchAccessRaisesFieldDefect` per
  the §8.5 state-transition matrix.
- **Step 5:** Create `tests/unit/mail/temail_submission_update.nim`
  (~120L) per G2 §8.3: `setUndoStatusToCanceledValueShape`,
  `parseUpdatesRejectsEmpty`, `parseUpdatesRejectsDuplicateId`,
  `parseUpdatesHappyPathSingleEntry`. The two rejection blocks pin
  literal `error[0].message` strings read from `email_submission.nim`
  via grep-first per the cross-cutting rule.
- **Step 6:** Create `tests/unit/mail/tsubmission_params.nim` (~400L)
  per G2 §8.7 matrix: one `block` per row of the 12-variant matrix
  (each with a valid representative + an invalid-boundary
  representative); the NOTIFY mutual-exclusion rule at unit tier;
  `SubmissionParamKey` identity enumeration across the 12-kind ×
  extension-name matrix; `paramKey` derivation totality; three fixed
  insertion sequences checked against `SubmissionParams` `toJson`
  insertion-order output.
- **Step 7:** Create `tests/unit/mail/tsubmission_mailbox.nim` (~300L)
  per G2 §8.3: `RFC5321Mailbox` strict parser across a 4 × 4 grid
  (4 local-part shapes × 4 domain-form shapes, one representative
  each); strict/lenient divergence cases (lenient-accepts-more
  representatives); `parseRFC5321Keyword` case-insensitive equality;
  `parseOrcptAddrType` byte-equal equality (distinct from
  `RFC5321Keyword` per G6). Block names per §8.3 row
  (`mailboxDotStringPlainDomain` etc.).
- **Step 8:** Create `tests/unit/mail/tsubmission_status.nim` (~200L)
  per G2 §8.3: per-variant round-trip for `DeliveredState` (4 RFC
  variants + `dsOther` raw-backing); `DisplayedState` (3 variants +
  `dpOther`); `SmtpReply` unit-tier digit-class happy path (200 / 550 /
  multi-line); `DeliveryStatus` composite construction;
  `DeliveryStatusMap` `countDelivered` / `anyFailed` on three
  hand-constructed maps.
- **Step 9:** Append to `tests/unit/mail/temail_submission_blueprint.nim`
  after line 92 per G2 §8.3: per-field rejection matrix
  (`blueprintInvalidIdentityId`, `blueprintInvalidEmailId`,
  `blueprintAccumulatesBothIdErrors`,
  `blueprintPatternASealExplicitRawField`). The
  `AccumulatesBothIdErrors` block pins the accumulating-error rail
  (two violations surface in one parse call, not short-circuit on the
  first). The sealing block is an `assertNotCompiles` record-literal
  sidestep probe for G38 Pattern A.
- **Step 10:** Append to `tests/unit/mail/tonsuccess_extras.nim` after
  line 124 per G2 §8.3: `IdOrCreationRef` vs `Referencable[T]`
  distinction — `idOrCreationRefWireDirectIsBareString`,
  `idOrCreationRefWireCreationHasHashPrefix`,
  `idOrCreationRefVsReferencableAreDistinctTypes` (compile-time
  `assertNotCompiles` that `directRef(id)` does not typecheck as
  `Referencable[seq[Id]]`).

### CI gate

Run `just ci` before committing.

---

## Phase 3: Serde tests

`toJson` / `fromJson` shape pinning per G2 §8.3 serde rows. `fromJson`
is **absent** for creation/filter/sort/ref types by G22/G26 contract
(client → server only); the serde test for `EmailSubmissionBlueprint`
pins absence by construction (no `fromJson` probe) and relies on the
cross-cutting grep check in Phase 7 for enforcement.

- **Step 11:** Create `tests/serde/mail/tserde_submission_status.nim`
  (~200L) per G2 §8.3: `UndoStatus` per-variant round-trip plus
  `undoStatusUnknownIsRejected` (pins G3's closed-enum commitment —
  `"deferred"` must `Err`, no silent `usOther` fallback);
  `DeliveryStatus` composite round-trip preserving
  `ParsedDeliveredState` raw-backing; `DeliveryStatusMap` round-trip
  preserving insertion order per distinct-table serde.
- **Step 12:** Create `tests/serde/mail/tserde_email_submission.nim`
  (~350L) per G2 §8.3: three-variant `AnyEmailSubmission` dispatch
  round-trip (`anyEmailSubmissionPendingRoundTrip`,
  `anyEmailSubmissionFinalRoundTrip`,
  `anyEmailSubmissionCanceledRoundTrip`) — wire `undoStatus` drives
  `fromJson` dispatch; `blueprintToJsonOnlyNoFromJson` (construct,
  serialise, do not deserialise); `EmailSubmissionFilterCondition`
  `toJson`-only with representative field combinations including
  `filterConditionAllFieldsPopulated`, `filterConditionOnlyUndoStatus`;
  `EmailSubmissionComparator` `comparatorSentAtTokenNotSendAt` (G19
  wire-token vs field-name mismatch — single most subtle serde pin in
  Part G); `IdOrCreationRef` `toJson`-only both arms
  (`idOrCreationRefDirectWire`, `idOrCreationRefCreationWire`);
  `filterConditionRejectsEmptyIdSeq` (G37 `Opt[NonEmptyIdSeq]`).
- **Step 13:** Append to
  `tests/serde/mail/tserde_submission_envelope.nim` after line 119 per
  G2 §8.3: six additional parameter-family round-trips
  (`D. ENVID + RET`, `E. HOLDFOR + HOLDUNTIL`,
  `F. BY + MT-PRIORITY + SMTPUTF8`); `ReversePath` arms
  (`G. reversePathNullWithParamsRoundTrip`,
  `H. reversePathMailboxWithoutParamsRoundTrip`);
  `I. parametersOptNoneDistinctFromEmptyObject` (G34
  `Opt.none(SubmissionParams)` → `"parameters": null` vs
  `Opt.some(emptyParams)` → `"parameters": {}`).

### CI gate

Run `just ci` before committing.

---

## Phase 4: Protocol tests

Builder- and method-level wire pinning per G2 §8.4, the method-level
error matrix per G2 §8.8, the entity-registration block per §8.4, the
capability append per §8.4, and the RFC compliance append per §8.4.
All protocol tests consume fixtures from Phase 1 and typed updates
from Phase 2 — no new constructors appear in the protocol layer.

- **Step 14:** Append to `tests/protocol/tmail_builders.nim` after the
  shipped §O block (line 766) per G2 §8.4: five simple-builder blocks
  `P. addEmailSubmissionGetInvocation`,
  `Q. addEmailSubmissionChangesInvocation`,
  `R. addEmailSubmissionQueryInvocation`,
  `S. addEmailSubmissionQueryChangesInvocation`,
  `T. addEmailSubmissionSetSimpleInvocation`; then six §O-extension
  cross-entity `getBoth` blocks realising the G2 §8.6 matrix rows 1–6
  as unit-tier representatives (`O.2 getBothBothSucceed`,
  `O.3 getBothInnerMethodError`, `O.4 getBothInnerAbsent`,
  `O.5 getBothInnerMcIdMismatch`, `O.6 getBothOuterNotCreatedSole`,
  `O.7 getBothOuterIfInStateMismatch`). Each block fixes a single
  method-level response shape and asserts the `getBoth` outcome.
- **Step 15:** Append to `tests/protocol/tmail_entities.nim` per G2
  §8.4: one block
  `emailSubmissionEntityRegisteredWithSubmissionCapability` anchoring
  the capability URI (`urn:ietf:params:jmap:submission`), method
  namespace (`EmailSubmission/*`), and
  `toJson(EmailSubmissionFilterCondition)` surface. Mirrors the
  existing `Mailbox` / `Email` / `Identity` entity blocks.
- **Step 16:** Append to `tests/protocol/tmail_method_errors.nim` per
  G2 §8.4 plus the §8.8 applicability matrix: one block
  `emailSubmissionSetMethodErrorSurface` covering submission-specific
  `MethodError` variants; per-method × per-variant `SetError`
  applicability blocks (one `block` per ✓ cell of §8.8's 9-row
  matrix — 8 applicable to `/set create` plus the 1 net-new
  `emailSubmissionSetCannotUnsendOnUpdate` applying to `/set update`);
  one negative singleton block per ✗ cell. The enum fold MUST use
  `for kind in SetErrorType:` per §8.8 mandatory note.
- **Step 17:** Append to
  `tests/serde/mail/tserde_mail_capabilities.nim` after the shipped
  section per G2 §8.4: three blocks anchoring the G25 amendment —
  `W. submissionExtensionMapRoundTripPreservesOrder`,
  `X. submissionExtensionMapCaseInsensitiveKey` (exercise the
  `RFC5321Keyword` case-fold equality; `"X-FOO"` and `"x-foo"` collide
  as the same key), `Y. submissionExtensionMapParsesLegacyWireShape`
  (migration pin — the wire is unchanged; legacy JSON still parses).
- **Step 18:** Append to `tests/compliance/trfc_8620.nim` per G2 §8.4:
  one block `rfc8621Section7ConstraintTableCompileTimeAnchor` — a
  `static:` assertion per row of the 27-row RFC 8621 §7 constraint
  table (G1 §1.4 / G2 §8.10) that the Nim type named for each
  constraint is reachable and of the documented shape. The shipped
  `rfc8621_submissionErrorsClassified` block already pins the
  8-variant SetError surface (G23); this new block pins every other
  row. Mirrors F's compliance append.

### CI gate

Run `just ci` before committing.

---

## Phase 5: Property tests

One new file with nine property groups per G2 §8.2.1. Trial tiers
follow the cost model in §8.9.3 — group F (`cancelUpdate` value
invariant) is `QuickTrials (200)` because the predicate is cheap and
the type-level enforcement is the `temail_submission.nim` `static:`
block; every other group is `DefaultTrials (500)`. Mandatory edge-bias
schedules documented per-group in §8.2.1 MUST be implemented as trial
0 / trial 1 / ... fixed inputs ahead of random sampling.

- **Step 19:** Create `tests/property/tprop_mail_g.nim` per G2 §8.2.1
  with nine groups A through I:
  - **Group A** — `parseRFC5321Mailbox` totality over random byte
    sequences (length 0..512). Edge-bias trials 0–6 enumerate the
    canonical + adversarial mailbox shapes (canonical, empty, bare
    `@`, IPv4-literal, IPv6-literal, Quoted-string local, General
    address-literal). Tier: `DefaultTrials`.
  - **Group B** — strict/lenient coverage: every strict-accepted
    input is lenient-accepted; the relationship is a proper superset,
    not equality. Tier: `DefaultTrials`.
  - **Group C** — `SubmissionParams` insertion-order round-trip —
    `parseSubmissionParams(seq).toJson` preserves the input seq's key
    order. Edge-bias trials 0–4 enumerate empty, single, all-11
    declaration-order, all-11 + extension, and reverse-declaration-
    order shapes. Tier: `DefaultTrials`.
  - **Group D** — `SubmissionParamKey` identity algebra:
    `paramKey(p1) == paramKey(p2)` iff kinds match AND (for
    `spkExtension`) extension names match byte-wise. Edge-bias trials
    0..143 enumerate `SubmissionParamKind × SubmissionParamKind` (12²);
    trials 144–160 pin the extension-name case-insensitivity
    adversaries. Tier: `DefaultTrials`.
  - **Group E** — `AnyEmailSubmission` round-trip preserving
    `x.state` AND phantom-branch payload. Edge-bias trials 0/1/2 force
    `usPending`/`usFinal`/`usCanceled`. Equality checked via
    `assertPhantomVariantEq`. Tier: `DefaultTrials`.
  - **Group F** — `cancelUpdate` value-level invariant: for every
    `EmailSubmission[usPending]`, the returned update has
    `kind == esuSetUndoStatusToCanceled`. Tier: `QuickTrials` — do
    not promote (the load-bearing enforcement is the compile-time
    `assertNotCompiles` in `temail_submission.nim`).
  - **Group G** — `NonEmptyEmailSubmissionUpdates` duplicate-`Id`
    invariant. Edge-bias trials 0–3 cover early-bound / late-bound /
    three-occurrence / many-position-cluster shapes (late-bound guards
    against an `i > 0` early-bail bug). Mirrors F2's
    `NonEmptyEmailImportMap` Group C. Tier: `DefaultTrials`.
  - **Group H** — `ParsedDeliveredState.rawBacking` round-trip
    preservation for unknown values; symmetric coverage for
    `DisplayedState`/`ParsedDisplayedState`. Edge-bias trials 0–3
    enumerate the four RFC-defined `DeliveredState` values; trial 4
    covers one `DisplayedState`; trials 5–6 pin unknown-value
    catch-all handling via `dsOther` / `dpOther`. Tier: `DefaultTrials`.
  - **Group I** — `parseSmtpReply` Reply-code digit-boundary scan
    per RFC 5321 §4.2. Edge-bias trials 0–8 enumerate the digit-range
    endpoints (d1 low/high, d2 high, d3 high, bare code, multi-line
    happy, multi-line bad). Tier: `DefaultTrials`.
- Add `tests/property/tprop_mail_g.nim` to `tests/testament_skip.txt`
  in the non-joinable section (precedent `tprop_mail_e.nim`).

### CI gate

Run `just ci` before committing. Note that `just test` will skip this
file — verify green via `just test-full` or per-file
`testament pat tests/property/tprop_mail_g.nim`.

---

## Phase 6: Adversarial / stress tests

One new file with the six adversarial scenario blocks from G2 §8.2.3
plus the §8.12 scale-invariant block group. Consumes the
`genInvalidRFC5321Mailbox`, `genSubmissionParam`, and
`genAnyEmailSubmission` generators from Phase 1. Does NOT re-cover
JSON-structural attacks (BOM / NaN / deep-nesting / duplicate keys /
1 MB strings / cast-bypass) — `tests/stress/tadversarial_mail_f.nim`
already exercises the `std/json` boundary and G1 introduces no new
parser pathway; reference F by name per §8.14 and inherit.

- **Step 20:** Create `tests/stress/tadversarial_mail_g.nim` covering
  the six §8.2.3 blocks plus §8.12 scale invariants:
  - **Block 1 — RFC 5321 Mailbox adversarial.** 8 named tests per the
    §8.2.3 Block 1 table: `mailboxTrailingDotLocal`,
    `mailboxUnclosedQuoted`, `mailboxBracketlessIPv6`,
    `mailboxOverlongLocalPart`, `mailboxOverlongDomain`,
    `mailboxGeneralLiteralStandardizedTagTrailingHyphen` (the
    load-bearing contrast test between `RFC5321Keyword` and the
    embedded Standardized-tag), `mailboxControlChar`, `mailboxEmpty`.
  - **Block 2 — `SubmissionParam` wire adversarial.** 10 named tests
    per §8.2.3 Block 2 including `paramRetUnknownValue`,
    `paramNotifyNeverWithOthers`, `paramNotifyEmptyFlags`,
    `paramHoldForNegative`, `paramMtPriorityBelowRange`,
    `paramMtPriorityAboveRange`, `paramSizeAt2Pow53Boundary`,
    `paramSizeAbove2Pow53`, `paramEnvidXtextEncoded`,
    `paramDuplicateKey`.
  - **Block 3 — `Envelope` serde coherence.** 7 named tests per §8.2.3
    Block 3 including `envelopeNullMailFromWithParams`,
    `envelopeNullMailFromNoParams`, `envelopeMalformedMailFrom`,
    `envelopeEmptyRcptTo` (complements shipped `emptyRcptToIsRejected`),
    `envelopeDuplicateRcptToLenient`, `envelopeDuplicateRcptToStrict`,
    `envelopeOptNoneVsEmptyParams`.
  - **Block 4 — `AnyEmailSubmission` dispatch adversarial.** 6 named
    tests per §8.2.3 Block 4 pinning the G3 closed-enum commitment:
    `anyMissingUndoStatus`, `anyUndoStatusWrongKindInt`,
    `anyUndoStatusWrongKindNull`, `anyUndoStatusUnknownValue`
    (`"deferred"` must `Err`, NOT silent `usOther`),
    `anyUndoStatusCaseMismatch`, `anyDispatchRoundTripPerVariant`.
  - **Block 5 — `SmtpReply` grammar adversarial.** 14 named tests per
    §8.2.3 Block 5 covering the full Reply-code digit-range and
    continuation grammar. Literal messages from
    `submission_status.nim:134–152` — grep-first, then lock.
  - **Block 6 — `getBoth(EmailSubmissionHandles)` cross-entity.** 7
    named tests per §8.2.3 Block 6 with full wire `Response` fixtures:
    `getBothBothSucceed`, `getBothInnerMethodError`,
    `getBothInnerAbsent`, `getBothInnerMcIdMismatch`,
    `getBothOuterNotCreatedSole`, `getBothOuterIfInStateMismatch`,
    `getBothCreationRefNotInCreateMap`. Rows 3 and 4 are the
    structurally novel scenarios without an F2 analogue — inner
    response absent and inner methodCallId mismatch — and document
    the client-side coherence checks.
  - **§8.12 scale invariants** — three blocks:
    `nonEmptyEmailSubmissionUpdates10kWithDupAtEnd` (10 000 entries,
    duplicate at position 9999; capacity bounded by ≤ 2 × 10 000),
    `submissionParams1kExtensionEntries` (linear-scaling pin,
    ≤ 500 ms wall-clock on CI), `nonEmptyRcptList1kWithDupAt999`
    (single-pass algorithm does not bail on prefix).
  - Close the file with a reference pointer to
    `tests/stress/tadversarial_mail_f.nim` for JSON-structural attacks
    (per §8.14 exclusion rationale) — do not re-cover.
- Add `tests/stress/tadversarial_mail_g.nim` to
  `tests/testament_skip.txt` in the non-joinable section (precedent
  `tadversarial_mail_f.nim`).

### CI gate

Run `just ci` before committing. Note that `just test` will skip this
file — verify green via `just test-full` or per-file
`testament pat tests/stress/tadversarial_mail_g.nim`.

---

## Phase 7: Coverage matrix audit and verification

Structural inspection step plus the canonical run-list. No new test
files produced here — Phase 7 only proves the prior phases closed
every G1 promise.

- **Step 21:** Walk the **two** living matrices row-by-row and verify
  every G1 promise has a corresponding test file + test name in either
  **SHIPPED** or TO-ADD state — and that every TO-ADD row produced in
  Phases 2–6 now actually exists at the named location under the named
  block identifier:
  - G2 §8.10 — RFC 8621 §7 constraint traceability matrix (27 rows).
    Single inspection point for "is every RFC §7 constraint pinned by
    a test?".
  - G2 §8.13 — G1 decision coverage matrix (37 G-decisions plus
    implementation-reality divergences). Single inspection point for
    "is every G1 decision pinned by a test?".
  Both matrices are explicitly **living artefacts** per G2 §8.10 and
  §8.13 closing notes; any new gap discovered during implementation
  MUST be amended into the design doc inline before the implementation
  merges. Step 21 is structural only — no new test code is written
  here.
- **Step 22:** Verification commands per G2 §8.11, in sequence:
  - `just build` — shared library compiles; no new warnings.
  - `just test` — fast suite runs green (compile-only smoke
    `tcompile_mail_g_public_surface.nim` already shipped; all appended
    blocks in shipped files plus the newly-created unit / serde /
    protocol files pass).
  - `just test-full` — the property file `tprop_mail_g.nim` and
    adversarial file `tadversarial_mail_g.nim` run green (they are
    `testament_skip.txt`-gated; this is their canonical run surface).
  - `just analyse` — nimalyzer passes without new suppressions.
  - `just fmt-check` — nph formatting unchanged.
  - `just ci` — full pipeline green.
  - `grep -n 'fromJson' src/jmap_client/mail/serde_email_submission.nim`
    — primary verification for the toJson-only contract on
    `EmailSubmissionBlueprint`, `EmailSubmissionFilterCondition`,
    `EmailSubmissionComparator`, and `IdOrCreationRef` (G22/G26
    contract). Any future `fromJson` addition to those types would
    show up and force an explicit review.
  - Single-file iteration during debugging:
    `testament pat tests/<category>/<file>.nim`.

### CI gate

Run `just ci` before committing. Steps 21 and 22 are prerequisites
for the Phase 7 commit — failures there block the commit just like
test failures.

---

*End of Part G (G2 test-side) implementation plan.*
