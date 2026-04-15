# Mail Part F Implementation Plan (F2 test-side only)

Part F's source-side (F1) has already shipped per
`docs/implement/implementation-10.md`. This plan turns the companion
test specification (`docs/design/11-mail-F2-design.md`) into ordered
build steps. F2 pins every F1 promise through unit, serde, protocol,
property, and adversarial test layers; the compile-only smoke file is
already shipped (see F2 §8.2.2).

**Scope note.** Test material only — no source code changes. Some
material is **SHIPPED** against the F1 landing (see F2 §8.2 state-of-
play table and the `SHIPPED` rows in F2 §8.12 coverage matrix); this
plan covers the TO-ADD work plus the §8.12 audit walk. Where F2 says
SHIPPED, the engineer MUST NOT re-implement — extend or leave alone.

7 phases, one commit each. Every phase passes `just ci` before
committing. Cross-cutting conventions from F2 §8.1 apply to every new
block:

- Test idiom is `block <name>:` + `assertOk` / `assertErr` / `assertEq`
  / `assertLen` from `tests/massertions.nim`, plus raw `doAssert` for
  inline checks. No `std/unittest`, no `suite` wrappers. Canonical
  precedents: `tests/unit/mail/temail.nim:59-125` and
  `tests/unit/mail/tmailbox.nim:124-176` (both shipped as part of F1).
- `ValidationError` is three plain strings (`typeName`, `message`,
  `value`). There is no enum classifier — tests discriminate failures
  via literal `error[0].message` checks (F2 §8.3 error-rail shape note).
- Enum folds use native `for variant in T:` (e.g.
  `for kind in SetErrorType:`) per F2 §8.6.1. No `forAllVariants`
  combinator — precedent is `tests/unit/terrors.nim:428`.
- `PatchObject` is **removed** from `src/jmap_client/framework.nim`
  entirely (not merely demoted — F2 §8.5 explains the divergence from
  F1 prose). The CI grep gate in Phase 7 keeps it out.

Phase ordering respects test dependency chains: fixtures + generators
first (every later phase consumes them), then unit (smart-constructor
pins the serde layer reuses as inputs), then serde / protocol, then
property / adversarial that layer on top.

---

## Phase 1: Test infrastructure

Foundational additions to the two existing test-support modules per
F2 §8.6. Both modules follow the inline-if-used-<3-times rule (F2
§8.6); both extensions are mandatory rather than advisory because
later phases reference the new factories by name. No new support
modules — F2 §8.1 explicitly forbids fragmenting the support layer.

- **Step 1:** Extend `tests/mfixtures.nim` per F2 §8.6.1's reuse-mapping
  table: per-variant `EmailUpdate` / `MailboxUpdate` /
  `VacationResponseUpdate` factories, set-builders
  (`makeEmailUpdateSet`, `makeMailboxUpdateSet`,
  `makeVacationResponseUpdateSet`), `makeEmailCopyItem` /
  `makeFullEmailCopyItem` / `makeEmailImportItem` /
  `makeFullEmailImportItem`, `makeNonEmptyEmailImportMap`, response
  builders (`makeEmailSetResponse`, `makeEmailCopyResponse`,
  `makeEmailImportResponse`), and the `makeEmailCopyHandles` compound-
  handle builder. Each factory's precedent line number is enumerated
  in §8.6.1; follow the 7-step fixture protocol already documented at
  `mfixtures.nim:7-14`.
- **Step 2:** Extend `tests/mproperty.nim` with `genEmailUpdate`,
  `genEmailUpdateSet`, `genInvalidEmailUpdateSet`,
  `genNonEmptyEmailImportMap`, `genJsonNodeAdversarial`,
  `genEmailUpdateSetCastBypass`, `genKeywordEscapeAdversarialPair` per
  F2 §8.6.1. Implement the mandatory edge-bias schedules documented
  alongside each generator in §8.2.1 (trial 0 / trial 1 / trial 2 are
  fixed adversarial inputs; random sampling only from trial ≥ 3).
  Pair-based generators (group D) share `genKeywordEscapeAdversarialPair`.

### CI gate

Run `just ci` before committing.

---

## Phase 2: Unit tests

Per-type smart-constructor invariants per F2 §8.3 (unit row). Phase 2
also covers the `tkeyword` charset precondition that the §8.8 escape-
boundary tests (Phase 3) transitively rely on — without it the
adversarial inputs cannot be constructed.

- **Step 3:** Append three `parseKeyword` charset blocks —
  `keywordWithTildeAccepted`, `keywordWithSlashAccepted`,
  `keywordWithBothAccepted` — to `tests/unit/mail/tkeyword.nim` per F2
  §8.3. Precondition for §8.8: every escape-boundary test constructs
  its adversarial `Keyword` via `parseKeyword("<raw>").get()`, so if
  the charset rejects `~` or `/` the downstream tests die in fixture.
- **Step 4:** Create `tests/unit/mail/temail_update.nim` per F2 §8.3:
  six protocol-primitive constructor-shape blocks (one per
  `EmailUpdateVariantKind`), five convenience-equivalence blocks
  (`markRead` / `markUnread` / `markFlagged` / `markUnflagged` /
  `moveToMailbox`), two negative-discrimination blocks separating
  `moveToMailbox` from `addToMailbox` at the variant-kind level. No
  custom `emailUpdateEq` helper — Nim's derived `==` covers every
  payload type used per F2 §8.3 note on equality.
- **Step 5:** Create `tests/unit/mail/temail_update_set.nim` per F2
  §8.3 plus the §8.7 shape enumeration: empty-input rejection
  (F22), Class 1 — six duplicate-target shapes (§8.7.1), Class 2 —
  two opposite-op shapes (§8.7.2), Class 3 — four sub-path ×
  full-replace shapes (§8.7.3), the four mandatory positive
  `assertOk` independent-case blocks (§8.7.4), the Class 1+2 overlap
  block (Class 2 wins the committed policy per F2 §8.12 row), and
  accumulation blocks (`accumulateMixedClasses` with inline
  `assertLen res.error, 3`; `accumulateThreeClass3`). Each negative
  block asserts against the literal `error[0].message` string.
- **Step 6:** Create `tests/unit/mail/temail_copy_item.nim` per F2
  §8.3: two `assertNotCompiles` type-rejection pins
  (`copyItemTypeRejectsEmptyMailboxIdSet` and
  `copyItemTypeRejectsNonEmptyMailboxIdSetWrongDistinct`) separating
  the empty-axis from the distinct-type-axis, plus minimal and
  full-override structural readback blocks.
- **Step 7:** Create `tests/unit/mail/temail_import_item.nim` per F2
  §8.3: `importItemRejectsOptNoneMailboxIds` (`assertNotCompiles` on
  `Opt.none` `mailboxIds` — the field is non-`Opt` per F1 §6.1),
  minimal block, and `importItemKeywordsThreeStates` (absent /
  empty-set / non-empty) block.
- **Step 8:** Extend `tests/unit/mail/tmailbox.nim` with the six per-
  variant `MailboxUpdate` setter-shape blocks per F2 §8.3 — the
  set-level group is already SHIPPED at `tmailbox.nim:124-176` so the
  append is strictly additive. Extend `tests/unit/mail/tvacation.nim`
  with the full six-variant `VacationResponseUpdate` fold per F2
  §8.3 — sections A and B (`initVacationResponseUpdateSet*` blocks)
  are already SHIPPED at `tvacation.nim:37-88`. In both files, do
  not touch the SHIPPED ranges.

### CI gate

Run `just ci` before committing.

---

## Phase 3: Serde tests

`toJson` / `fromJson` shape pinning per F2 §8.3 (serde rows). All
RFC 6901 escape-boundary cases from F2 §8.8 drive through the public
`toJson(EmailUpdate)` entry because `jsonPointerEscape` is module-
private — Phase 2's Step 3 precondition is what lets the adversarial
inputs reach that entry.

- **Step 9:** Create `tests/serde/mail/tserde_email_update.nim` per F2
  §8.3 serde row plus §8.8: six `toJson(EmailUpdate)` variant blocks
  (return shape is the `(string, JsonNode)` tuple),
  `toJson(EmailUpdateSet)` flatten block, `moveToMailbox` positive
  + negative wire pins (F21: emits `euSetMailboxIds`, not
  `euAddToMailbox`), and the 15 RFC 6901 escape-boundary blocks
  enumerated in F2 §8.8's table.
- **Step 10:** Create `tests/serde/mail/tserde_email_set_response.nim`
  per F2 §8.3: `EmailSetResponse.fromJson` eight-field shape,
  `createResults` merge via `mergeCreatedResults`, the consolidated
  `EmailCreatedItem` missing-field rejection blocks (per F2's C5
  dedup — these live here, not in a separate unit file), the outer
  `updated` three-state (absent / null / empty object), the
  `destroyed` three-state (absent / empty array / two-element
  array), the `UpdatedEntry` null-vs-empty-object distinctness
  block, and a `toJson` round-trip block.
- **Step 11:** Create `tests/serde/mail/tserde_email_copy.nim` per F2
  §8.3: `toJson(EmailCopyItem)` minimal vs full-override (three-key)
  blocks, `EmailCopyResponse.fromJson` three shapes
  (`created`-only / `notCreated`-only / combined), the
  `fromAccountId` required-field block, and the `assertNotCompiles`
  pin on `r.updated` access per F2 §8.12 row (`EmailCopyResponse`
  has no `updated` / `destroyed` fields).
- **Step 12:** Create `tests/serde/mail/tserde_email_import.nim` per
  F2 §8.3: `toJson(EmailImportItem)` optional-key collapse
  (`Opt.none` and `Opt.some(empty KeywordSet)` both omit `keywords`
  per F1 §6.1), `toJson(NonEmptyEmailImportMap)` shape, and
  `EmailImportResponse.fromJson` `created: null` and `created: {}`
  parity per RFC §4.8.
- **Step 13:** Append to `tests/serde/mail/tserde_mailbox.nim` per F2
  §8.3: `toJson(MailboxUpdate)` five variants,
  `toJson(MailboxUpdateSet)` flatten, plus the four nullable wire
  pins `setRoleNoneEmitsJsonNull`, `setRoleSomeEmitsString`,
  `setParentIdNoneEmitsJsonNull`, `setParentIdSomeEmitsString`.
- **Step 14:** Append to `tests/serde/mail/tserde_vacation.nim` per
  F2 §8.3: `toJson(VacationResponseUpdate)` six variants,
  `toJson(VacationResponseUpdateSet)` flatten, plus the five
  nullable wire pins (`vruSetFromDateNoneEmitsNull`,
  `vruSetToDateNoneEmitsNull`, `vruSetSubjectNoneEmitsNull`,
  `vruSetTextBodyNoneEmitsNull`, `vruSetHtmlBodyNoneEmitsNull`) for
  each `Opt`-bearing setter.

### CI gate

Run `just ci` before committing.

---

## Phase 4: Protocol tests

Builder- and method-level wire pinning per F2 §8.4 plus the method-
level error matrix per F2 §8.11. Phase 4 consumes the fixtures from
Phase 1 and the typed updates from Phase 2 — no new constructors
appear in the protocol layer.

- **Step 15:** Append the builder block group to
  `tests/protocol/tmail_builders.nim` per F2 §8.4 — 16 named blocks
  covering `addEmailSet` (full invocation / minimal / `ifInState`
  wire semantics / typed-update passthrough), `addEmailCopy` simple
  overload (phantom type / `ifInState` with copy semantics),
  `addEmailCopyAndDestroy` compound overload (emits
  `onSuccessDestroyOriginal: true` / three destroy-state params /
  all-state params), `getBoth` (happy path / short-circuits), and
  the typed-update migration of `addMailboxSet`. Two required pins
  inside this group: `handles.destroy.methodName == mnEmailSet` and
  `handles.destroy.callId == handles.copy.callId()` (F2 §8.12
  §5.3 row); `getBothShortCircuitOnCopyError` is table-driven via
  `for variant in MethodErrorType:` across the seven applicable
  variants.
- **Step 16:** Append the `addEmailImport*` block group to
  `tests/protocol/tmail_methods.nim` per F2 §8.4 — four named blocks
  covering invocation name, capability, `emails: NonEmptyEmailImportMap`
  passthrough, and the `ifInState` Some / None pair. The §B
  `VacationResponse/set` block group is already SHIPPED in the same
  file — leave it alone.
- **Step 17:** Create `tests/protocol/tmail_method_errors.nim` per F2
  §8.4 plus the §8.11 applicability matrix: seven method-level error
  blocks (one per RFC-listed method × error combination), plus the
  generic `SetError` matrix — one named test per ✓ cell
  (one per method × operation, not per method) and one negative
  `singleton` test per ✗ cell. The enum fold MUST use
  `for kind in SetErrorType:` per F2 §8.11 mandatory note.

### CI gate

Run `just ci` before committing.

---

## Phase 5: Property tests

One new file with the five property groups per F2 §8.2.1. Trial tiers
follow the cost model in F2 §8.6.3; mandatory edge-bias schedules are
documented per-group in §8.2.1 and MUST be implemented as trial 0 /
trial 1 / trial 2 fixed inputs ahead of random sampling.

- **Step 18:** Create `tests/property/tprop_mail_f.nim` per F2 §8.2.1
  with five groups:
  - **Group B** — `initEmailUpdateSet` totality. Tier:
    `DefaultTrials` (500). Edge-bias trial 0 pins `@[]` via the
    totality probe.
  - **Group C** — `NonEmptyEmailImportMap` duplicate-key invariant.
    Tier: `DefaultTrials`. Edge-bias trials 0–3 cover early-bound /
    late-bound / three-occurrence / many-position-cluster shapes.
  - **Group D** — RFC 6901 escape bijectivity over
    `genKeywordEscapeAdversarialPair`. Tier: `DefaultTrials`.
    Edge-bias trials 0–2 fixed at `("a/b", "a~1b")`, `("~", "~0")`,
    `("/", "~1")` — the documented collision adversaries that
    random sampling rarely hits.
  - **Group E** — `toJson(EmailUpdateSet)` post-condition: all-
    distinct keys, every `(key, value)` RFC 8620 §5.3-shaped.
    Tier: `DefaultTrials`.
  - **Group F** — `moveToMailbox(id) ≡ setMailboxIds(...)`
    quantified over the full `Id` charset. Tier: `QuickTrials`
    (200) — cheap predicate per F2 §8.6.3.

### CI gate

Run `just ci` before committing.

---

## Phase 6: Adversarial / stress tests

One new file with the seven scenario blocks from F2 §8.2.3 plus the
§8.10 scale-invariant block group. Consumes `genJsonNodeAdversarial`
and `genEmailUpdateSetCastBypass` from Phase 1.

- **Step 19:** Create `tests/stress/tadversarial_mail_f.nim` covering
  the seven §8.2.3 blocks:
  - Response-decode adversarial (per the §8.9 matrix; approximately
    50 named tests across `EmailSetResponse`, `EmailCopyResponse`,
    and `EmailImportResponse`).
  - `SetError.extras` adversarial integration path — five cases,
    including the three `*ExtrasReachableFromCreateResults` named
    tests (per F2 §8.12 §7.1 row).
  - Conflict-algebra corner cases — Class 3 payload-irrelevance
    pair (`class3PayloadIrrelevantEmptySetKeywords`,
    `class3PayloadIrrelevantNonEmptySetKeywords`) plus the IANA
    keyword fold.
  - `getBoth(EmailCopyHandles)` adversarial — three scenarios (per
    F2 §8.12 §5.4 row: method-call-id mismatch, empty
    createResults, and the third enumerated in §8.2.3).
  - Cross-response coherence — five named blocks
    (`coherenceOldStateNewStateEqual`,
    `coherenceOldStateNewStateNullPair`,
    `coherenceAccountIdMismatchAcrossInvocations`,
    `coherenceUpdatedSameKeyTwice`,
    `coherenceCreatedAndNotCreatedShareKey`).
  - JSON-structural attack surface — seven named blocks
    (`structuralBomPrefix`, `structuralNanInfinity`,
    `structuralDuplicateKeysInObject`, `structuralDeepNesting`,
    `structuralLargeStringSize`, `structuralEmptyKey`,
    `structuralUnicodeNoncharacters`).
  - Cast-bypass behaviour — two negative-pin blocks
    (`castBypassDocumentsNoPostHocValidation`,
    `castBypassEmptyAccepted`) per F2 §8.12 §3.2.4 row.
- **Step 20:** Add the §8.10 scale-invariant block group to the same
  `tadversarial_mail_f.nim` file — seven named tests:
  `emailUpdateSet10kClass1Anchored` (≤ 500 ms wall-clock bound),
  `emailUpdateSet10kClass1NoAnchor` (in-order pair counting),
  `emailUpdateSetThreeClassesStaggered`,
  `emailUpdateSetLatePositionConflict` (pins the single-pass
  algorithm against a late-position conflict), `emailUpdateSet100kWallClock`
  (stress-only tag, ≤ 5 s bound, excluded from default `just test`
  run), `nonEmptyImportMap10kWithDupAtEnd`,
  `nonEmptyImportMapEmptyAndDupSeparately`. Mirror
  `tadversarial_blueprint.nim:bodyPartDupTenThousand` and
  `tadversarial_blueprint.nim:stressResponseMethodResponses100k`
  per F2 §8.10 precedent references.

### CI gate

Run `just ci` before committing.

---

## Phase 7: Coverage matrix audit and verification

Structural inspection step plus the canonical run-list. No new test
files produced here — Phase 7 only proves the prior phases closed
every F1 promise.

- **Step 21:** Walk F2 §8.12 row-by-row and verify every F1 §
  promise has a corresponding test file + test name in either
  **SHIPPED** or TO-ADD state — and that every TO-ADD row produced
  in Phases 2–6 now actually exists at the named location under the
  named block identifier. The matrix is explicitly a **living
  artefact** per F2 §8.12 closing note; any new gap discovered
  during implementation MUST be amended into §8.12 inline before the
  implementation merges. Step 21 is structural only — no new test
  code is written here.
- **Step 22:** Verification commands per F2 §8.13, in sequence:
  - `just build` — shared library compiles; no new warnings.
  - `just test` — every new test file runs green (compile-only
    smoke already shipped; five new files plus six appended files
    all pass).
  - `just analyse` — nimalyzer passes without new suppressions.
  - `just fmt-check` — nph formatting unchanged.
  - `just ci` — full pipeline green.
  - `! grep -r 'PatchObject' src/` — the mechanical regression
    check per F2 §8.5 and §8.13. `PatchObject` is gone from the
    codebase entirely and must stay gone; a positive grep fails
    the check.

### CI gate

Run `just ci` before committing. Steps 21 and 22 are prerequisites
for the Phase 7 commit — failures there block the commit just like
test failures.

---

*End of Part F (F2 test-side) implementation plan.*
