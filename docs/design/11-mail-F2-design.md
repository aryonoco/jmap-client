# RFC 8621 JMAP Mail — Design F2: Email Write Path — Test Specification

Companion test specification for [`11-mail-F1-design.md`](./11-mail-F1-design.md).
The section number below is kept at `8` so that cross-references from
F1 (§1–§7 and §9) into this document remain valid without rewriting.
See F1 for the full context (scope, typed update algebras, response
surface, builders, and the Decision Traceability Matrix).

---

## 8. Test Specification

### 8.1. Testing strategy

Part F mirrors Part E's test category shape (F17):

1. **Unit** — per-type smart-constructor invariants and serde
   round-trip for every new type. Includes embedded `assertNotCompiles`
   scenarios where type-level guarantees warrant defence.
2. **Serde** — `toJson`/`fromJson` output shape per field, variant, and
   RFC constraint, plus the typed-algebra → wire-patch translation.
3. **Property-based** — a single `tprop_mail_f.nim` file covering
   RFC 6901 escape-boundary bijectivity, totality of accumulating
   constructors, the `moveToMailbox`/`setMailboxIds` equivalence
   quantified over `Id`, the duplicate-key invariant on
   `NonEmptyEmailImportMap`, and the serde post-condition on
   `EmailUpdateSet`. The previous "conflict-class equivalence
   representatives" property is **demoted** to unit enumeration
   (§8.2.1 group A removed; rationale in that section).
4. **Adversarial** — a single `tadversarial_mail_f.nim` file covering
   malformed server responses (per the matrix in §8.9),
   `SetError.extras` adversarial content, conflict-algebra corner
   cases, accumulating-constructor scale invariants (per §8.10),
   cross-response coherence anomalies (§8.2.3 "Cross-response
   coherence"), JSON-structural attacks (§8.2.3 "JSON-structural
   attack surface"), and the `cast`-bypass policy pin
   (§8.2.3 "Cast-bypass behaviour").
5. **Compile-time reachability** — a single `tmail_f_reexport.nim`
   file (action: `"compile"`) proving every new public symbol is
   reachable through the top-level `jmap_client` re-export chain, that
   `PatchObject` is **not** publicly visible (F19 enforcement, §8.5.1),
   that every new variant-kind enum is exhaustive under `case`, and
   that every creation-side type is `toJson`-only (no `fromJson` in
   scope — F1 §1.6 asymmetric serde discipline; §8.2.2 block 4).

**File-naming note.** Part E's adversarial stress file is
`tests/stress/tadversarial_blueprint.nim` (per-concept, not
part-lettered). Part F deliberately deviates to
`tadversarial_mail_f.nim` to mirror the property-test convention
(`tprop_mail_f.nim` / `tprop_mail_e.nim`) — by Part F, the
part-lettered scheme has stabilised across two property files and
one compliance file, and warrants the third instance for the
adversarial slot. The Part E adversarial file is the structural
precedent (`tests/stress/tadversarial_blueprint.nim`), referenced
explicitly by §8.10 below.

Test-infrastructure additions (§8.6) follow Part E's 7-step fixture
protocol (`tests/mfixtures.nim:7-14`) and naming convention
(`make<Type>` minimal / `makeFull<Type>` populated, exemplified by
`makeEmailBlueprint` at `mfixtures.nim:1148` and
`makeFullEmailBlueprint` at `mfixtures.nim:1154`). Reuse mapping
between every new test-infrastructure addition and its closest
existing precedent is enumerated in §8.6.1. **No new test-support
modules are introduced**: typed-update factories and equality helpers
land in `mfixtures.nim` alongside `setErrorEq` (`mfixtures.nim:707`)
and the `make*Blueprint` family; generators land in `mproperty.nim`
alongside `genEmailBlueprint`. Fragmenting the support layer for one
feature is explicitly disallowed.

### 8.2. New test files — part-lettered

Following Part E's convention (F17), the lettered-by-part files cover
test concerns whose scope spans multiple types within the Part.

#### 8.2.1. `tests/property/tprop_mail_f.nim`

Five property groups, calibrated against the trial-count cost model
(§8.6.3) and the Part E precedent (`tprop_mail_e.nim:64`,
property 85). The previous "empty-rejection" and "variant-equality"
groups have been removed as enumeration-disguised-as-property
antipatterns — those finite cases migrate to the unit file
(§8.3 `temail_update_set.nim` and `temail_update.nim` respectively).
Property group A (conflict-class detection) is **also removed**:
the variant-pair shape product (§8.7) is finite and exhaustively
enumerated in §8.3; payload variation does not affect target-path
equality (the discriminator the algorithm checks), so quantifying
payload over `DefaultTrials` re-runs the same logical check 500
times against semantically equivalent inputs. The cost-vs-coverage
ratio is poor; conflict detection is a unit-tier concern.

| Group | Property | Tier | Notes |
|-------|----------|------|-------|
| B | `initEmailUpdateSet` totality — for all `rng`-generated `openArray[EmailUpdate]`, the constructor returns `Ok` xor `Err` (never panics, never blocks). Edge-bias trial 0 to `@[]` to cover the empty case via the totality probe. | `DefaultTrials` (500) | Replaces the previous "empty rejection" group, which was a single fixed input run 500 times. |
| C | `NonEmptyEmailImportMap` duplicate-key invariant — for all maps with at least one duplicated `CreationId` (≥ 2 occurrences), the constructor accumulates `≥ 1` violation. Quantifies over the duplicate's position, total map size, and value content. **Edge-bias schedule:** trial 0 = duplicate at positions (0, 1) (early-bound); trial 1 = duplicate at positions (n−2, n−1) (late-bound — guards against an `i > 0` early-bail bug); trial 2 = three-occurrence duplicate; trial 3 = many-position duplicate cluster. Random sampling for trials ≥ 4. | `DefaultTrials` (500) | The single empty-input case migrates to the unit file. |
| D | RFC 6901 JSON Pointer escape **bijectivity** — for distinct keywords `k1, k2` (sampled from `genKeywordEscapeAdversarialPair`, see §8.6.1), `jsonPointerEscape($k1) ≠ jsonPointerEscape($k2)`. Catches order-swapped `replace` regressions that would collapse `~/` and `~01` to the same wire form. **Mandatory edge-bias schedule** (trials 0–2 fixed, then random): trial 0 = pair `("a/b", "a~1b")` (canonical adversary); trial 1 = pair `("~", "~0")`; trial 2 = pair `("/", "~1")`. These three pairs are the documented collision adversaries against a buggy swapped-replace order; random sampling rarely hits them. | `DefaultTrials` (500) | NEW group. Replaces the deleted variant-equality group. |
| E | `toJson(EmailUpdateSet)` post-condition — for all valid `EmailUpdateSet` constructed via `initEmailUpdateSet` on a non-conflicting input (sampled from `genEmailUpdateSet`), the emitted JSON object has all-distinct keys and every `(key, value)` pair is RFC 8620 §5.3-shaped. Pins the smart-constructor invariant transitively through serde. | `DefaultTrials` (500) | NEW group. |
| F | `moveToMailbox(id) ≡ setMailboxIds(parseNonEmptyMailboxIdSet(@[id]).get())` — for all `genId`-generated `id`, the two `EmailUpdate` values are `emailUpdateEq`. Pins F1 §3.2.3.1's structural-equivalence promise across the full `Id` charset, not just the one fixed value the §8.3 unit test exercises. | `QuickTrials` (200) | NEW group. Predicate is cheap; quick tier suffices. |

The previous compound-handle short-circuit concern migrates to a
table-driven enumeration in `tests/protocol/tmail_builders.nim`
(§8.4) — a single fixed response shape per variant, with the variant
set finite, makes a property test redundant. The implementation
uses the native `for variant in MethodErrorType:` idiom (precedent:
`tests/unit/terrors.nim:428`); see §8.6.1 for the rationale on
preferring native enum iteration over a wrapper template.

#### 8.2.2. `tests/compliance/tmail_f_reexport.nim`

Compile-time smoke test (`action: "compile"`). Pattern follows
`tests/compliance/tmail_e_reexport.nim`. Four sub-blocks:

1. **Symbol reachability** — every new public symbol is reachable
   through the top-level `import jmap_client` re-export chain.
   Covered symbols: `EmailUpdate`, `EmailUpdateVariantKind`,
   `EmailUpdateSet`, `MailboxUpdate`, `MailboxUpdateVariantKind`,
   `MailboxUpdateSet`, `VacationResponseUpdate`,
   `VacationResponseUpdateVariantKind`, `VacationResponseUpdateSet`,
   `EmailCreatedItem`, `UpdatedEntry`, `UpdatedEntryKind`,
   `EmailSetResponse`, `EmailCopyResponse`, `EmailImportResponse`,
   `EmailCopyItem`, `EmailImportItem`, `NonEmptyEmailImportMap`,
   `EmailCopyHandles`, `EmailCopyResults`; all six protocol-primitive
   plus five domain-named `EmailUpdate` constructors; all five
   `MailboxUpdate` and six `VacationResponseUpdate` constructors;
   the three `init*UpdateSet` smart constructors;
   `getBoth(EmailCopyHandles)`. Trivial newtype-wrapper assertions
   (`distinct seq` re-exports for which the only behaviour is
   "exists") are intentionally omitted in favour of accessor-level
   UFCS exercise per the `tmail_e_reexport.nim`
   `touchEmailBlueprintAccessors` precedent.
2. **`PatchObject` demotion enforcement (F19)** — an
   `assertNotCompiles` block placed immediately after
   `import jmap_client`, before the reachability section:
   `assertNotCompiles((let _: PatchObject = default(PatchObject)))`
   plus `assertNotCompiles(jmap_client.emptyPatch())`. Pins the
   `*` removal at the public boundary so an accidental re-export
   fails CI loudly.
3. **Variant-kind exhaustiveness probes** — three procs that take
   each new variant-kind discriminator and `case` over every
   constructor without an `else`. The compiler refuses to build if
   any variant is unhandled, guarding against silent variant
   forgetting in future parts. Covers `EmailUpdateVariantKind`
   (6 variants), `MailboxUpdateVariantKind` (5 variants),
   `VacationResponseUpdateVariantKind` (6 variants),
   `UpdatedEntryKind` (2 variants).
4. **Asymmetric serde discipline pin (F1 §1.6)** — F1 §1.6 commits
   creation models to **`toJson`-only** (no `fromJson`). One
   `assertNotCompiles` per creation type pins that no `fromJson`
   overload is reachable through the public re-export surface:
   - `emailUpdateHasNoFromJson` —
     `assertNotCompiles((let _ = EmailUpdate.fromJson(newJObject())))`
   - `emailUpdateSetHasNoFromJson` —
     `assertNotCompiles((let _ = EmailUpdateSet.fromJson(newJObject())))`
   - `emailCopyItemHasNoFromJson` —
     `assertNotCompiles((let _ = EmailCopyItem.fromJson(newJObject())))`
   - `emailImportItemHasNoFromJson` —
     `assertNotCompiles((let _ = EmailImportItem.fromJson(newJObject())))`
   - `nonEmptyEmailImportMapHasNoFromJson` —
     `assertNotCompiles((let _ = NonEmptyEmailImportMap.fromJson(newJObject())))`
   Pins F1 §1.6's "client → server only" Postel application — these
   types should never appear on a server-to-client decode path.
   `MailboxUpdate*` and `VacationResponseUpdate*` are creation
   models for their respective `/set` methods and receive identical
   pins in this block (one `assertNotCompiles` per type).

#### 8.2.3. `tests/stress/tadversarial_mail_f.nim`

Adversarial scenarios. Organised into seven blocks corresponding to
matrices §8.9 (response-decode), §8.10 (scale invariants), §8.7
(conflict-algebra corner cases), the SetError-integration block,
and three cross-cutting blocks (cross-response coherence,
JSON-structural attack surface, and cast-bypass behaviour).

**Response-decode adversarial** — full enumeration in §8.9. Summary:

- Malformed `created` / `notCreated` map keys (invalid `CreationId`,
  invalid `Id`).
- `EmailCreatedItem` missing fields, wrong types, extra unknown
  fields (Postel: ignore unknowns).
- `UpdatedEntry` non-object/non-null kinds (string, number, array,
  bool) → `Err` per F1 §2.3.
- `UpdatedEntry` `null` vs `{}` distinction preserved (pins the F1
  §2.3 "library does NOT collapse them" promise) and round-trip-
  preserving.
- `EmailImportResponse.created: null` accepted as empty
  `createResults` per RFC §4.8.
- `EmailSetResponse.updated` outer three-state distinction
  (`absent` / `null` / `{}`).
- `notDestroyed` / `updated` map with non-`Id`-charset key.
- `oldState` `JNull`, `newState` `JInt`, `accountId` `JNull`
  required-field cases.

**`SetError.extras` adversarial** — extends the Part A in-vitro
coverage in `tests/unit/mail/tmail_errors.nim` to the **integration**
path through Email-method `createResults`:

- `notFoundBlobIds` containing strings that fail the `Id` charset
  (RFC 8620 §1.2 `[A-Za-z0-9_-]`) → `Opt.none` short-circuit.
- `notFoundBlobIds` containing duplicates → preserved (not silently
  collapsed); a client retrying based on the list must see every
  occurrence.
- `invalidRecipientAddresses` containing extremely long strings
  (mirrors `tests/stress/tadversarial.nim` `breadth10kSiblings`,
  scenario 99b, as the unbounded-element-stress precedent).
- `extras` containing extra unknown keys alongside known ones —
  forward-compat: known accessor returns expected value despite the
  noise.
- `maxSize` value at the `getBiggestInt` → `parseUnsignedInt`
  boundary (≥ 2^53−1).
- Extras reachable from each Part F method's `createResults` `Err`
  arm: `emailSetExtrasReachableFromCreateResults`,
  `emailCopyExtrasReachableFromCreateResults`,
  `emailImportExtrasReachableFromCreateResults` (one named test per
  method; see §8.12 row for §7.1).

**Conflict-algebra corner cases** — extends §8.7's enumeration with
adversarial-flavoured cases:

- `euSetKeywords(empty)` alongside `euAddKeyword(k)` — Class 3
  regardless of `setKeywords` payload emptiness; the discriminator
  is the target path.
- `euSetKeywords(non-empty)` alongside `euAddKeyword(k)` — same
  Class 3 behaviour expected; pins the payload-irrelevance invariant.
- `euSetMailboxIds(ids)` alongside `euAddToMailbox(id1)` where
  `id1 ∈ ids` — Class 3, not Class 1; the discriminator is again
  the target path.
- Class 2 enumerated across the five IANA keywords (`kwSeen`,
  `kwFlagged`, `kwDraft`, `kwAnswered`, `kwForwarded`) plus a custom
  keyword containing `/` and one containing `~`. The
  `genInvalidEmailUpdateSet(rng, trial, class)` generator
  edge-biases toward each IANA keyword in early trials per the J-11
  trigger-builder pattern (`mproperty.nim:2717`).

**Scale invariants** — full enumeration in §8.10. Summary:

- `EmailUpdateSet` with 1000+ entries and a Class 1 conflict at the
  late position 998 (single-pass algorithm doesn't bail after a
  prefix).
- Three classes of conflicts staggered at positions 0, 500, 999 —
  exactly three accumulated violations.
- `NonEmptyEmailImportMap` with 10 000 entries and a duplicate key
  at position 9999.
- `EmailUpdateSet` with N = 10 000 conflicting entries paired against
  entry 0 — exactly N − 1 accumulated violations; capacity bounded.

**`getBoth(EmailCopyHandles)` adversarial** (cross-references §8.4):

- Implicit destroy present with method-call-id mismatch (server
  routing error) — second `?` short-circuits with `serverFail`.
- Implicit destroy present with its own `MethodError` (e.g.,
  `fromAccountNotFound`) — `getBoth` surfaces that error correctly
  on the Err rail.
- Both responses present but copy `createResults` empty — destroy
  still extracted.

**Cross-response coherence** — pins decode behaviour when individual
fields are well-formed in isolation but the response as a whole is
internally inconsistent. Sourced from real-world Cyrus and Stalwart
edge cases plus JMAP RFC 8620 §3.4 state-handling commentary:

- `coherenceOldStateNewStateEqual` — `oldState == newState` while
  `created`, `updated`, or `destroyed` are non-empty. Documented as
  **accepted** (the library does not enforce server invariants); if
  callers need this check they apply it explicitly. Pin documents
  the non-rejection.
- `coherenceOldStateNewStateNullPair` — both `oldState` and
  `newState` `Opt.none` while `created` is non-empty. Accepted; the
  state pair is independently optional per RFC §5.5.
- `coherenceAccountIdMismatchAcrossInvocations` — within a multi-
  invocation response, two invocations sharing a method-call-id
  carry different `accountId` values. `getBoth` surfaces the
  mismatch as `Err` with a structured `clientError` describing the
  divergence (NOT `serverFail` — it is a client-side detection).
- `coherenceUpdatedSameKeyTwice` — the wire `updated` map cannot
  contain duplicate keys (JSON object semantics), but a permissive
  decoder might silently drop or overwrite. Pin: the parser MUST
  use `getOrDefault`-then-fail discipline so a malformed-but-
  parseable input surfaces as `Err`.
- `coherenceCreatedAndNotCreatedShareKey` — server emits the same
  `CreationId` in both `created` and `notCreated` (illegal but
  observed). Pin: deterministic precedence — `notCreated` wins
  (the more conservative outcome); merged `createResults` carries
  the `Err(SetError)` value, not the success.

**JSON-structural attack surface** — pins behaviour for inputs
constructed to exploit `std/json` quirks rather than RFC 8621
semantics. These tests run against the entire Part F decode surface
(`Email/set`, `Email/copy`, `Email/import` responses):

- `structuralBomPrefix` — input prefixed with UTF-8 BOM
  (`0xEF 0xBB 0xBF`). Pin: rejected with `Err` (the BOM is not
  RFC 8259-compliant JSON whitespace).
- `structuralNanInfinity` — `"size": NaN` and `"size": Infinity`
  literals (extension JSON, not strict). Pin: rejected via
  `parseUnsignedInt` rail; surfaces as `Err`.
- `structuralDuplicateKeysInObject` — `{"id": "a", "id": "b"}`
  (RFC 8259 says behaviour is undefined; std/json takes last).
  Pin: documented behaviour (last-wins) is locked into a test so
  any future `std/json` change surfaces immediately.
- `structuralDeepNesting` — `created` value with 1000-level nested
  unknown sub-objects. Pin: ignored (Postel) without stack overflow;
  deep recursion guard exercised.
- `structuralLargeStringSize` — `id` value 1 MB long (well past
  the 255-octet `Id` limit). Pin: smart-constructor `Err` is
  reached without intermediate allocation pathology.
- `structuralEmptyKey` — `{"": {...}}` as a `created` entry. Pin:
  `Err` via the `parseCreationId` rail (empty `CreationId`
  rejected).
- `structuralUnicodeNoncharacters` — keyword text containing
  `U+FFFE` / `U+FFFF` / surrogate-half escapes. Pin: round-trip
  preserved if `parseKeyword` accepts; otherwise `Err`. Test
  documents whichever path is taken.

**Cast-bypass behaviour** — F1 §3.2.4 commits to "no path through
the public surface produces a malformed `EmailUpdateSet`". The
escape hatch is a deliberate `cast[EmailUpdateSet](malformedSeq)`,
which Nim's type system cannot prevent. The pin documents what the
library does NOT promise:

- `castBypassDocumentsNoPostHocValidation` —
  `cast[EmailUpdateSet](@[euAddKeyword(k), euAddKeyword(k)])` (a
  Class 1 violation) is accepted by `toJson` and emits structurally
  malformed wire JSON. The test asserts the malformed output is
  produced (negative assertion: no runtime check fires) and pins
  the documented contract that callers using `cast` opt out of the
  invariant guarantee. The test docstring explicitly states this
  is a **negative-pin** test — the library deliberately does NOT
  add a runtime check, since the cost of post-hoc validation on
  every `toJson` would penalise the well-typed path. F1 §3.2.4
  links to this test by name.
- `castBypassEmptyAccepted` —
  `cast[EmailUpdateSet](newSeq[EmailUpdate]())` (empty — would be
  rejected by `initEmailUpdateSet`) is accepted by `toJson` and
  emits `{}`. Same negative-pin shape as above.

Generators for cast-bypass cases live in `mproperty.nim` as
`genEmailUpdateSetCastBypass(rng, trial)` (per §8.6.1) — they are
NOT used by property groups in §8.2.1 because the property would
trivially fail; they are only used by `tadversarial_mail_f.nim`.

### 8.3. New per-concept test files

Unit — `tests/unit/mail/`:

| File | Concerns |
|------|----------|
| `temail_update.nim` | (1) Six protocol-primitive constructors emit the correct payload (kind discriminator is implicit in the constructor literal — explicit `kind == ...` tautology omitted). (2) Five domain-named convenience constructors are structurally `emailUpdateEq`-equal to their primitive counterparts: `markRead() ≡ addKeyword(kwSeen)`, `markUnread() ≡ removeKeyword(kwSeen)`, `markFlagged() ≡ addKeyword(kwFlagged)`, `markUnflagged() ≡ removeKeyword(kwFlagged)`, `moveToMailbox(id) ≡ setMailboxIds(parseNonEmptyMailboxIdSet(@[id]).get())`. (3) Negative cases pinning equality non-degeneracy: `moveToMailbox(id1) ≠ moveToMailbox(id2)` for distinct ids; `addKeyword(k1) ≠ addKeyword(k2)` for distinct keywords. |
| `temail_update_set.nim` | (1) Empty input rejected — single-shot `emptyInputRejected` (was prop group B; F22). (2) Class 1 enumerated by §8.7.1 — six named tests, one per shape. (3) Class 2 enumerated by §8.7.2 — two named tests (`class2KeywordOpposite`, `class2MailboxOpposite`). (4) Class 3 enumerated by §8.7.3 — four named tests (`class3{Add,Remove}{Keyword,Mailbox}VsSet`). (5) Class 1+2 overlap pin — `class1And2Overlap` asserts exactly 1 error is emitted with `classification == Class2OppositeOperations` (the committed tighter-classification policy, §8.7.2). (6) Independent cases (§8.7.4) — four mandatory positive tests: `independentSetKeywordsAndSetMailboxIds`, `independentTwoDifferentKeywordsAdded`, `independentKeywordAddAndMailboxAdd`, `independentMailboxAddAndDifferentMailboxRemove`. (7) Accumulation arithmetic — `accumulateMixedClasses` (1×Class 1 + 1×Class 2 + 1×Class 3 → exactly 3 errors via `assertUpdateSetErrCount`); `accumulateOneClassThree` (3× Class 3 → exactly 3 errors); `accumulateEmptyAlone` (empty → exactly 1 error). |
| `tnon_empty_email_import_map.nim` | (1) `nonEmptyImportMapEmptyRejected`. (2) `nonEmptyImportMapDuplicateCreationIdRejected`. (3) `nonEmptyImportMapDuplicateAndEmptyAccumulatedSeparately` — the empty case and the duplicate case cannot co-occur on a single input (empty has no duplicates); this test exercises the two invariants as independent failures in the same test file, pinning the error-rail shape is identical. (4) `nonEmptyImportMapPreservesInsertionOrder` — construct from `@[("c1",_), ("c2",_), ("c3",_)]`; iterate via `pairs`; assert order is `c1, c2, c3`. Repeat with shuffled input `@[("c3",_), ("c1",_), ("c2",_)]`; assert iteration order matches input. (5) `nonEmptyImportMapDeterministicErrorOrder` — supply input containing two duplicate pairs at disjoint positions; assert errors emit in input-encounter order. Trivial "valid input → Ok" smoke is folded into (4) — the order-preservation case implicitly asserts construction succeeds with expected `len` and per-`CreationId` accessibility. |
| `temail_copy_item.nim` | (1) `copyItemTypeRejectsEmptyMailboxIdSet` — `assertNotCompiles(EmailCopyItem(id: id1, mailboxIds: Opt.some(initMailboxIdSet(@[]))))`. Pins F1 §6.1's "the override slot rejects empty sets at the type level". (2) `copyItemTypeRejectsNonEmptyMailboxIdSetWrongDistinct` — `assertNotCompiles(initEmailCopyItem(id = id1, mailboxIds = Opt.some(initMailboxIdSet(@[id1]))))`. Pins that even a *non-empty* `MailboxIdSet` is the wrong distinct type for the override slot — it must be a `NonEmptyMailboxIdSet`. The (1)/(2) pair separates the empty-rejection axis from the distinct-type axis. The serde row in `tserde_email_copy.nim` covers full-override and minimal-construction wire output (§8.3 serde table); the redundant in-vitro field-readback assertions and the `parseNonEmptyMailboxIdSet(@[])` runtime check (already pinned in `tnon_empty_mailbox_id_set.nim`) have been removed. |
| `temail_import_item.nim` | (1) `importItemRejectsOptNoneMailboxIds` — `assertNotCompiles(initEmailImportItem(blobId = b, mailboxIds = Opt.none(NonEmptyMailboxIdSet)))`; pins that `mailboxIds` is required (no `Opt.none` form for this field). (2) `importItemKeywordsRoundTripThreeStates` — exercises `Opt.none` / `Opt.some(initKeywordSet(@[]))` / `Opt.some(non-empty)` for the `keywords` slot. Wire collapses the first two into a single omission (`Opt.some(empty)` may or may not serialise as `{}` — the test asserts whichever convention the serde uses and pins it), but the type distinguishes them at construction time. Trivial "minimal construction returns object" case removed — folded into (1) and (2). |
| `tvacation.nim` | NEW unit file (the existing `tserde_vacation.nim` is serde-only; no unit counterpart currently exists). (1) `vacationResponseSixFieldsConstructed` — smart-constructor behaviour for all six fields on `VacationResponse`. (2) Six named tests covering `VacationResponseUpdate` variant construction, one per variant (`vacationResponseUpdateSetIsEnabled`, `vacationResponseUpdateSetFromDate`, `vacationResponseUpdateSetToDate`, `vacationResponseUpdateSetSubject`, `vacationResponseUpdateSetTextBody`, `vacationResponseUpdateSetHtmlBody`). (3) `vacationResponseUpdateSetEmptyRejected`. (4) Six duplicate-target tests, one per `VacationResponseUpdateVariantKind` variant (`vacationResponseUpdateSetDuplicateSetIsEnabled`, `vacationResponseUpdateSetDuplicateSetFromDate`, `vacationResponseUpdateSetDuplicateSetToDate`, `vacationResponseUpdateSetDuplicateSetSubject`, `vacationResponseUpdateSetDuplicateSetTextBody`, `vacationResponseUpdateSetDuplicateSetHtmlBody`). Native `for variant in VacationResponseUpdateVariantKind:` iteration (precedent: `tests/unit/terrors.nim:428`) is acceptable for (4). |
| `tkeyword.nim` (append) | (1) `keywordWithTildeAccepted` — `parseKeyword("$has~tilde")`. (2) `keywordWithSlashAccepted` — `parseKeyword("$has/slash")`. (3) `keywordWithBothAccepted` — `parseKeyword("$~/")`. Pins F1 §3.2.5's spec-faithful Postel commitment — RFC 8621 §4.1.1's keyword charset includes `~` and `/`. Required upstream of §8.8's escape-boundary tests; without it those tests cannot construct their inputs. |

Serde — `tests/serde/mail/`:

| File | Concerns |
|------|----------|
| `tserde_email_update.nim` | (a) `toJson(EmailUpdate)` emits the correct `(key, value)` pair for each variant — six cases. (b) `toJson(EmailUpdateSet)` flattens to a JSON object with distinct keys (type-level guarantee, verified at wire). (c) `moveToMailbox(id)` wire output: positive (`("mailboxIds", { string(id): true })`) and negative (`key != "mailboxIds/" & string(id)`) — pins F21 against `euAddToMailbox` regression. (d) RFC 6901 escape-boundary unit tests — full enumeration in §8.8 table (six named cases). |
| `tserde_email_import.nim` | `toJson(EmailImportItem)` emits the four required fields; `Opt.none` variants omit keys, `Opt.some` emits them. `toJson(NonEmptyEmailImportMap)` emits the correct top-level object with `CreationId` keys. `EmailImportResponse.fromJson` parses well-formed responses, including `created: null` (per RFC §4.8) and `created: {}` (empty) as distinct accepted shapes; malformed responses surface as `Err` on the Result rail. |
| `tserde_email_copy.nim` | `toJson(EmailCopyItem)` — minimal (id only) emits `{}` for overrides; full override emits the three override keys; `Opt.none` overrides are omitted. `EmailCopyResponse.fromJson` parses three shapes: `created`-only, `notCreated`-only (asserts `notCreated` populates `Err(SetError)` entries in `createResults` at the correct `CreationId`), and combined. Type-level: `assertNotCompiles((let r: EmailCopyResponse = default(EmailCopyResponse); discard r.updated))` — pins F1 §2.2's "EmailCopyResponse omits /set-specific fields". |
| `tserde_email_set_response.nim` | `EmailSetResponse.fromJson` parses the eight-field shape (`accountId`, `oldState`, `newState`, `createResults`, `updated`, `destroyed`, `notUpdated`, `notDestroyed`); the `createResults` merge layer correctly reconstructs the merged table from wire `created`/`notCreated` maps; `EmailCreatedItem.fromJson` rejects missing-field shapes (consolidated from `tadversarial_mail_f.nim` per C5 deduplication — §8.9 row keeps the malformed-shape coverage; this file focuses on happy-path shape pinning). `updated` outer three-state coverage: absent → `Opt.none`; `null` → `Opt.none`; `{}` → `Opt.some(emptyTable)`. `destroyed` three-state coverage: absent / empty-array / two-element. `UpdatedEntry` distinctness pins (`null` vs `{}`) per §8.9 response-decode matrix. |

### 8.4. Existing-file appends

`tests/protocol/tmail_builders.nim` — append cases (one test per
bullet):

- `addEmailSetFullInvocation` — builds an invocation with the correct
  method name, args shape, and capability URI; phantom-typed response
  handle carries `EmailSetResponse`; `create`/`update`/`destroy`
  parameters serialise correctly when all three are `Opt.some`.
- `addEmailSetMinimalAccountIdOnly` — all of `create`, `update`,
  `destroy`, `ifInState` `Opt.none`; wire JSON contains `accountId`
  only and no other operation keys (pins F1 §4.1's "bare invocation"
  affordance).
- `addEmailSetIfInStateEmitted` — `ifInState: Opt.some(state)` emits
  `"ifInState": "<state>"`; negative counterpart
  `addEmailSetIfInStateOmittedWhenNone` — `ifInState: Opt.none`
  emits no key (no `null`).
- `addEmailCopyPhantomType` — phantom-typed handle carries
  `EmailCopyResponse`; no `onSuccessDestroyOriginal` key emitted
  (the simple overload never sets it).
- `addEmailCopyIfInStateEmittedWithCopySemantics` — `ifInState: Opt.some`
  on the `Email/copy` arg surface (NOT `destroyFromIfInState`).
- `addEmailCopyAndDestroyEmitsTrue` — `onSuccessDestroyOriginal: true`
  emitted; return shape is `(RequestBuilder, EmailCopyHandles)`.
- `addEmailCopyAndDestroyDestroyFromIfInStateSome` — wire JSON
  contains `"destroyFromIfInState": "<state>"`.
- `addEmailCopyAndDestroyDestroyFromIfInStateNone` — wire JSON does
  **not** contain a `destroyFromIfInState` key (negative assertion:
  `Opt.none` omits, never emits `null`).
- `addEmailCopyAndDestroyAllStateParamsSome` — `ifFromInState`,
  `ifInState`, `destroyFromIfInState` all `Opt.some` simultaneously;
  all three appear in the serialised arguments without aliasing or
  silent drop.
- `getBothCopyAndDestroyHappyPath` — both invocations present under
  shared method-call-id; extracts `EmailCopyResults` with both fields
  populated; `accountId`/`newState` survive intact across both.
- `getBothShortCircuitOnCopyError` — table-driven across the seven
  applicable `MethodErrorType` variants (`metStateMismatch`,
  `metFromAccountNotFound`, `metFromAccountNotSupportedByMethod`,
  `metServerFail`, `metForbidden`, `metAccountNotFound`,
  `metAccountReadOnly`) using the native `for variant in
  MethodErrorType:` idiom (precedent: `tests/unit/terrors.nim:428`).
  Mirrors `getBothQueryGetMethodError` at `tconvenience.nim:154`.
- `getBothShortCircuitOnDestroyMissing` — implicit destroy
  invocation absent; second `?` returns
  `Err(MethodError{rawType: "serverFail"})` per F12.
- `getBothShortCircuitOnDestroyError` — copy succeeded; destroy
  invocation present but with its own method-error; `getBoth`
  surfaces destroy's error on the Err rail.
- `addMailboxSetMigratedTypedUpdate` — empty `MailboxUpdateSet`
  rejected at construction time (not at builder time); a valid
  `MailboxUpdateSet` passes through and serialises to
  PatchObject-shaped JSON at the wire.

`tests/protocol/tmail_methods.nim` — append cases (one test per
bullet):

- `addEmailImportPhantomTyped` — phantom-typed handle carries
  `EmailImportResponse`; `emails: NonEmptyEmailImportMap` parameter
  serialises to the correct top-level `emails` key.
- `addEmailImportIfInStateSomePassthrough` — `ifInState: Opt.some`
  emits `"ifInState": "<state>"`; `Opt.none` counterpart
  `addEmailImportIfInStateNoneOmitted` — no key emitted.
- `addVacationResponseSetMigratedTypedUpdate` — `singleton` id
  hardcoded internally; `update: VacationResponseUpdateSet` parameter
  serialises to the correct wire patch; `ifInState` parameter
  passes through unchanged.
- `addVacationResponseSetEmptyRejectedAtConstruction` — empty input
  is rejected by `initVacationResponseUpdateSet`, not by the
  builder (same separation of concerns as `addMailboxSet`).

`tests/protocol/tmail_method_errors.nim` (NEW file) — method-level
error decode coverage, per §8.11 matrix:

- `Email/set` + `requestTooLarge` →
  `MethodError{errorType: metRequestTooLarge}` on outer rail.
- `Email/set` + `stateMismatch` → `metStateMismatch`.
- `Email/copy` + `fromAccountNotFound` → `metFromAccountNotFound`.
- `Email/copy` + `fromAccountNotSupportedByMethod` →
  `metFromAccountNotSupportedByMethod`.
- `Email/copy` + `stateMismatch` → `metStateMismatch`.
- `Email/import` + `stateMismatch` → `metStateMismatch`.
- `Email/import` + `requestTooLarge` → `metRequestTooLarge`.

Plus the generic-`SetError` applicability matrix per §8.11 (one
named test per `✓` cell; one negative `singleton` test per `✗`
cell).

`tests/unit/mail/tmailbox.nim` — append cases for `MailboxUpdate`
(five variants, each with total constructor) and `MailboxUpdateSet`.
The duplicate-target-property class is enumerated explicitly: one
named test per `MailboxUpdateVariantKind` variant (`muSetName`,
`muSetParentId`, `muSetRole`, `muSetSortOrder`, `muSetIsSubscribed`)
— five tests covering the variant fold.

`tests/serde/mail/tserde_mailbox.nim` — append cases for
`toJson(MailboxUpdate)` (five variants) and `toJson(MailboxUpdateSet)`
(flattening to top-level JSON object, one key per variant).
Critical nullable-wire cases:

- `setRoleNoneEmitsJsonNull` — `setRole(Opt.none(MailboxRole)).toJson()
  == ("role", newJNull())`. Pins `Opt.none → JSON null` mapping
  (clear-role wire semantic); negative: NOT key-absent.
- `setRoleSomeEmitsString` — `setRole(Opt.some(roleInbox)).toJson()
  == ("role", %"inbox")`.
- `setParentIdNoneEmitsJsonNull` —
  `setParentId(Opt.none(Id)).toJson() == ("parentId", newJNull())`.
  Pins reparent-to-top-level wire semantic.
- `setParentIdSomeEmitsString` —
  `setParentId(Opt.some(id1)).toJson() == ("parentId", %string(id1))`.

`tests/unit/mail/tvacation.nim` — append cases for
`VacationResponseUpdate` (six variants) and
`VacationResponseUpdateSet` duplicate-target enumeration: six named
tests, one per `VacationResponseUpdateVariantKind` variant.

`tests/serde/mail/tserde_vacation.nim` — append cases for
`toJson(VacationResponseUpdate)` (six variants) and
`toJson(VacationResponseUpdateSet)` (flattening). Nullable-wire
pins for `vruSetFromDate`, `vruSetToDate`, `vruSetSubject`,
`vruSetTextBody`, `vruSetHtmlBody` (each: `Opt.none → JSON null`,
`Opt.some → value`).

### 8.5. PatchObject migration strategy

Exactly seventeen test files reference `PatchObject` (105 total
occurrences). Two migration strategies apply:

1. **Strategy 1 — typed algebra rewrite.** The test's purpose is to
   exercise a public mail surface; the `PatchObject` reference is
   incidental setup. Rewrite setup to construct typed update-sets
   via the public smart constructors, then assert against the typed
   algebra. Core `PatchObject` serde becomes transitively covered.
2. **Strategy 2 — `{.all.}` escape hatch.** The test's purpose is
   core-internal verification of `PatchObject` itself as an RFC 8620
   §5.3 wire primitive. Retain internal-symbol access via
   `import jmap_client/framework {.all.}` so the test continues to
   see the (now-private) `PatchObject` symbol.

The strategy allocation is committed here — no per-file decision is
deferred to the implementation PR:

| File | Occurrences | Strategy | Rationale |
|------|-------------|----------|-----------|
| `tests/protocol/tmail_methods.nim` | 2 | **1** | Mail-method builder tests; `addVacationResponseSet` migrates to `VacationResponseUpdateSet`. |
| `tests/protocol/tmethods.nim` | 3 | **1** | Generic `/set` builder tests; the mail-shaped ones migrate to typed algebras. Non-mail `/set` cases (Mailbox/set remainder, Identity/set) continue on the generic path — those keep `SetRequest[T]` wrappers that happen to carry `PatchObject` internally, so strategy 1 applies to the PatchObject-touching tests only. |
| `tests/protocol/tbuilder.nim` | 2 | **1** | Same reasoning as `tmethods.nim`. |
| `tests/mproperty.nim` | 3 | **1** | The three occurrences are in `genPatchObject` (generator) and `genPatchPath` (path generator). If no strategy-2 file requires them (see below), delete both generators post-migration. |
| `tests/unit/tframework.nim` | 6 | **2** | Direct unit test of `PatchObject` invariants (path non-empty, set-or-delete ops, RFC 6901). Core-internal by construction. |
| `tests/serde/tserde_framework.nim` | 24 | **2** | Highest-count file — direct serde of `PatchObject`. Core-internal wire-format test. |
| `tests/property/tprop_framework.nim` | 7 | **2** | Property tests on `PatchObject` serde round-trip. Core-internal. |
| `tests/serde/tserde_type_safety.nim` | 8 | **2** | Type-level guarantees on `PatchObject` construction/access. Core-internal. |
| `tests/serde/tserde_properties.nim` | 7 | **2** | Property tests for core framework serde. Core-internal. |
| `tests/property/tprop_serde.nim` | 9 | **2** | Property tests for framework serde round-trip. Core-internal. |
| `tests/stress/tadversarial.nim` | 3 | **2** | Adversarial RFC 6901 tilde-encoding tests on `PatchObject` (§8.8 Layer 1 baseline). Explicitly core-internal by design. |
| `tests/serde/tserde_adversarial.nim` | 15 | **2** | Adversarial serde cases for `PatchObject`. Core-internal. |
| `tests/compliance/trfc_8620.nim` | 3 | **2** | RFC 8620 §5.3 compliance tests — `PatchObject` IS the spec primitive under test. Core-internal by definition. |
| `tests/compliance/tregression.nim` | 2 | **2** | Pinned regressions on historic `PatchObject` bugs. Core-internal. |
| `tests/stress/tstress.nim` | 7 | **2** | Stress tests of `PatchObject` under large inputs. Core-internal. |
| `tests/serde/tserialisation.nim` | 1 | **2** | Single reference; core-internal. |
| `tests/property/tprop_session.nim` | 3 | **2** | Quick totality property on `PatchObject.getKey` — core-internal. |

**Count:** Strategy 1 applies to 4 files; Strategy 2 to 13. The
`{.all.}` escape hatch is legitimately load-bearing — 13 of 17 files
exist to verify the internal RFC-5.3 primitive, not the mail surface.
Demotion is about API ergonomics (F19: no consumer should see
`PatchObject`), not about removing its tests.

**Generator fate (crystalising §8.5.2).** Strategy-2 files adopt
`{.all.}`, so `genPatchObject` and `genPatchPath` remain callable
from the 13 strategy-2 files. However, they are demoted from the
shared-generator API: relocated to a module-private helper within
`tests/property/tprop_framework.nim` (the highest-value consumer)
and re-exported via `{.all.}` to the other strategy-2 files that
need them. The 4 strategy-1 files lose the dependency entirely.

#### 8.5.1. Compile-time enforcement of the demotion

The migration is gated by a compile-time test in
`tests/compliance/tmail_f_reexport.nim` (§8.2.2 block 2): an
`assertNotCompiles((let _: PatchObject = default(PatchObject)))`
block immediately after `import jmap_client`, plus
`assertNotCompiles(jmap_client.emptyPatch())`. This prevents an
accidental re-addition of the `*` export from slipping through code
review — the type system catches what eyes might miss.

#### 8.5.2. Generator and fixture migration debt

Three pieces of test infrastructure require post-migration assessment:

- `genPatchObject` (`tests/mproperty.nim:774`) — 13 call sites use
  strategy 2 (see §8.5 table), so the generator is retained but
  **relocated to `tests/property/tprop_framework.nim`** as a
  module-private helper, and consumed by sibling strategy-2 files
  via their own `{.all.}` import of `framework`. The `mproperty.nim`
  public slot is removed.
- `genPatchPath` (`tests/mproperty.nim:476`) — same relocation.
- `makeSetResponseJson` (`tests/mfixtures.nim:890`) — remains valid
  for `Mailbox/set` and `Identity/set` (which continue on the generic
  `SetResponse[T]` path), but **must not** be used for `Email/set`
  testing post-migration. Replace with the typed `makeEmailSetResponse`
  factory (§8.6.1).

Generator relocation and `{.all.}` additions are recorded in the
implementation PR's commit messages so the migration log is
greppable from `git log` and cross-checkable against the §8.5 table.

### 8.6. Test infrastructure additions

#### 8.6.1. Reuse-mapping table

Each new factory / generator / template / equality helper lists its
closest existing precedent so the implementation PR follows the
established pattern rather than reinventing it.

| New item | Closest existing precedent | Path:Line |
|----------|---------------------------|-----------|
| `makeAddKeyword(k)`, `makeRemoveKeyword(k)`, `makeSetKeywords(ks)`, `makeAddToMailbox(id)`, `makeRemoveFromMailbox(id)`, `makeSetMailboxIds(ids)` (six per-variant factories — NOT a single polymorphic `makeEmailUpdate(kind, ...)`) | `makeSetErrorInvalidProperties` / `makeSetErrorAlreadyExists` (per-variant naming) | `mfixtures.nim:302-313` |
| `makeMarkRead()`, `makeMarkUnread()`, `makeMarkFlagged()`, `makeMarkUnflagged()`, `makeMoveToMailbox(id)` (five per-convenience factories) | Same as above | `mfixtures.nim:302-313` |
| `makeEmailUpdateSet(updates)` (one-line wrapper over `init…(…).get()`) | `makeNonEmptyMailboxIdSet(ids)` | `mfixtures.nim:1069` |
| `makeMailboxUpdate*` (five per-variant), `makeVacationResponseUpdate*` (six per-variant) | `mfixtures.nim:302-313` (per-variant) | `mfixtures.nim:302-313` |
| `makeMailboxUpdateSet(updates)`, `makeVacationResponseUpdateSet(updates)` | `mfixtures.nim:1069` | `mfixtures.nim:1069` |
| `makeEmailCopyItem(id, ...)`, `makeFullEmailCopyItem(...)` | `makeEmailBlueprint` / `makeFullEmailBlueprint` | `mfixtures.nim:1148, 1154` |
| `makeEmailImportItem(blobId, mailboxIds, ...)`, `makeFullEmailImportItem(...)` | `makeEmailBlueprint` / `makeFullEmailBlueprint` | `mfixtures.nim:1148, 1154` |
| `makeNonEmptyEmailImportMap(entries)` | `makeNonEmptyMailboxIdSet(ids)` | `mfixtures.nim:1069` |
| `makeEmailCreatedItem(id, blobId, threadId, size)` | Plain object literal — no precedent helper needed; included for fixture-naming consistency | (n/a) |
| `makeEmailSetResponse`, `makeEmailCopyResponse`, `makeEmailImportResponse` (full + minimal variants — typed records, NOT JsonNode) | `makeMethodError` / `makeRequestError` (typed-record factories; explicitly distinct from the JsonNode-returning `makeSetResponseJson` at `mfixtures.nim:890`, which remains valid for `Mailbox/set` and `Identity/set` only — see §8.5.2) | `mfixtures.nim:211-214` |
| `makeEmailCopyHandles(copyMcid, destroyMcid)` | `makeResultReference(mcid, name, path)` | `mfixtures.nim:199` |
| `genEmailUpdate(rng, trial)` (edge-biased per-variant) | `genSetError(rng)` (variant enumeration with edge bias) | `mproperty.nim:628` |
| `genEmailUpdateSet(rng, trial)` (composes `genEmailUpdate` plus edge-biased conflict injection) | `genEmailBlueprint(rng, trial)` (trial-biased composition J-10) | `mproperty.nim:2473` |
| `genInvalidEmailUpdateSet(rng, trial, class)` (targeted conflict injection per Class 1/2/3) | `genBlueprintErrorTrigger(rng, trial)` (trigger-builder pattern J-11; typed parameter selects which constraint fires; early trials enumerate each class once via bijection) | `mproperty.nim:2717` |
| `EmailUpdateSetTriggerArgs` (args-packet for injection) | `BlueprintTriggerArgs` (J-11 args-packet pattern) | `mproperty.nim:2547` |
| `genEmailCopyItem`, `genEmailImportItem` | Standard composition; no special precedent | (n/a) |
| `genNonEmptyEmailImportMap(rng, trial)` (early-trial cardinality boundary bias) | `genNonEmptyMailboxIdSet(rng, trial)` (J-5) | `mproperty.nim:2209` |

**Mandatory edge-bias schedules.** The three non-trivial generators
above ship with fixed low-trial enumerations so property failures
surface in the first handful of trials rather than being buried in
random sampling:

- `genEmailUpdate(rng, trial)` — trials 0..5 enumerate the six
  primitive `EmailUpdateVariantKind` variants in declaration order
  (`euAddKeyword`, `euRemoveKeyword`, `euSetKeywords`,
  `euAddToMailbox`, `euRemoveFromMailbox`, `euSetMailboxIds`).
  Trials 6..10 enumerate the five convenience constructors. Trial
  11 is `euSetKeywords` with empty `KeywordSet`. Trial 12 is
  `euSetKeywords` with the full IANA system-keyword set
  (`kwSeen, kwFlagged, kwDraft, kwAnswered, kwForwarded`). Trials
  ≥ 13 are random.
- `genEmailUpdateSet(rng, trial)` — trial 0 = single-element valid
  set; trial 1 = two-element valid set with disjoint variants;
  trial 2 = Class 1 injection (duplicate target); trial 3 = Class
  2 injection (opposite operations); trial 4 = Class 3 injection;
  trial 5 = all three classes staggered (per §8.10
  `emailUpdateSetThreeClassesStaggered`); trial 6 = empty input
  (edge case; the generator returns this shape knowing the caller
  will test the `initEmailUpdateSet` rejection). Trials ≥ 7 are
  random.
- `genNonEmptyEmailImportMap(rng, trial)` — trial 0 = single-entry
  map (minimum valid); trial 1 = duplicate-`CreationId` at
  positions (0, 1); trial 2 = duplicate at positions (n−2, n−1)
  for n ≥ 4; trial 3 = three-occurrence duplicate; trial 4 = empty
  input (edge case; caller tests rejection); trial 5 = single
  `CreationId` mapped three times (degenerate duplicate). Trials
  ≥ 6 are random. Per J-5, the generator's **non-empty** path and
  **empty** edge-case path share one entry point, saving a separate
  generator per cardinality tier.
| `assertUpdateSetErr(expr, violations: set[EmailUpdateSetViolation])` | `assertBlueprintErr` (L-1) | `massertions.nim:139` |
| `assertUpdateSetErrCount(expr, n: int)` (NEW; exact-count counterpart to L-3) | `assertBlueprintErrCount` | `massertions.nim:170` |
| `assertCopyHandleShortCircuit(resp, handles, expected: MethodErrorType)` (renamed from `assertCompoundHandleShortCircuit` per Part E `assert<Entity><Property>` naming convention) | `getBothQueryGetMethodError` block | `tconvenience.nim:154` |
| `genJsonNodeAdversarial(rng, trial)` (NEW; generates JNull/JInt/JBool/JArray/JObject-with-wrong-keys for adversarial response-decode) | `genSetErrorAdversarialExtras` (trial-biased extras attack) | (new in `mproperty.nim`) |
| `genEmailUpdateSetCastBypass(rng, trial)` (NEW; generates `cast[EmailUpdateSet]`-shaped malformed sequences for §8.2.3 "Cast-bypass behaviour") | `genBlueprintErrorTrigger` (J-11 targeted-invariant) | `mproperty.nim:2717` |
| `genKeywordEscapeAdversarialPair(rng, trial)` (NEW; generates adversarial keyword pairs that collide under a swapped-replace-order bug — `("a/b", "a~1b")`, `("~", "~0")`, `("/", "~1")`) | `genBlueprintErrorTrigger` (trial-biased enumeration) | `mproperty.nim:2717` |

**Native enum iteration over `forAllVariants` combinator.** Where
§8.4 and §8.11 exercise every `MethodErrorType` or `SetErrorType`
variant, the idiom is the native `for variant in T:` loop
(precedent: `tests/unit/terrors.nim:428` iterates `for variant in
MethodErrorType:`). No `forAllVariants[T]` combinator is introduced —
it would add a macro layer over the standard-library iteration that
already compiles to the same thing, and test readers are better
served by the direct idiom. The `for variant in T:` pattern is
mandated for the §8.4 `getBothShortCircuitOnCopyError`, §8.11
SetError matrix cells, and the per-variant duplicate-target folds
in §8.3 (`tvacation.nim`, `tmailbox.nim`).

#### 8.6.2. Equality-helper classification

Nim's compiler-derived `==` on case objects and plain objects is
structural for fields whose types themselves carry `==`. Only one
mail type, `KeywordSet`, deliberately omits borrowed `==` (via
`defineHashSetDistinctOps` at `validation.nim:56` — the base
template omits `==` for read-only model sets; see that template's
docstring for the domain rationale). `NonEmptyMailboxIdSet` uses
`defineNonEmptyHashSetDistinctOps` (`validation.nim:72`), which
**does** borrow `==` (line 83) — creation-context sets opt into
the richer op set. Custom helpers are needed only where derived
equality cannot reach `KeywordSet`.

| Helper | Classification | Rationale |
|--------|----------------|-----------|
| `emailUpdateEq` | **NEEDED** | The `euSetKeywords(KeywordSet)` branch lacks a borrowed `==` on the payload. The `euSetMailboxIds(NonEmptyMailboxIdSet)` branch works via derived equality (line 83), but the case-object as a whole cannot have derived `==` unless all branches do. Custom case-fold required; the fold for `euSetMailboxIds` can delegate to derived `==`. |
| `emailUpdateSetEq` | **NEEDED** | `distinct seq[EmailUpdate]`; element equality depends on `emailUpdateEq` above. Defines borrowed seq equality plus per-element fold. |
| `mailboxUpdateEq` | **REDUNDANT** | All branch fields (`string`, `Opt[Id]`, `Opt[MailboxRole]`, `UnsignedInt`, `bool`) have borrowed/structural `==`. Use derived `==` directly. |
| `mailboxUpdateSetEq` | **NEEDED-trivial** | One-line borrowed `==` via `defineXxxDistinctOps` for the `distinct seq[MailboxUpdate]` wrapper; no custom comparator needed beyond the derived element `==`. |
| `vacationResponseUpdateEq` | **REDUNDANT** | Same analysis as `mailboxUpdateEq`. |
| `vacationResponseUpdateSetEq` | **NEEDED-trivial** | Same as `mailboxUpdateSetEq`. |
| `emailCopyItemEq` | **NEEDED** | The `Opt[KeywordSet]` field blocks derived equality; `Opt[NonEmptyMailboxIdSet]` works via borrowed inner `==` (line 83). Custom helper folds through the keywords field only. |
| `emailImportItemEq` | **NEEDED** | Same analysis as `emailCopyItemEq` — `Opt[KeywordSet]` blocks derived, `NonEmptyMailboxIdSet` (non-Opt) works. |
| `emailCreatedItemEq` | **REDUNDANT** | All four fields are `Id` or `UnsignedInt`. Plain object, derived `==` is structural. |
| `emailSetResponseEq` | **REDUNDANT** | Decomposes through `Result[EmailCreatedItem, SetError]` (nim-results structural `==`), `EmailCreatedItem` (derived), `SetError` (case-object derived; `extras: Opt[JsonNode]` uses `std/json`'s structural `==`). The existing `setErrorEq` (`mfixtures.nim:707`) encodes a stricter case-branch-fold policy — if specific tests need that policy, define a thin `emailSetResponseEqWith(setErrorEq)` overload locally. **Default policy:** use derived `==`. |
| `emailCopyResponseEq` | **REDUNDANT** | Same as `emailSetResponseEq`. |
| `emailImportResponseEq` | **REDUNDANT** | Same as `emailSetResponseEq`. |
| `updatedEntryEq` | **NEEDED-trivial** | Case object with `changedProperties: JsonNode`. Derived `==` works via `std/json`'s structural `==`; defined as a one-line alias for naming consistency with the other helpers. |
| `nonEmptyMailboxIdSetEq` | **NOT-ADDED** | Reuses borrowed `==` (`validation.nim:83`). No helper exists; tests use `==` directly. Pin to this classification prevents future drift — if a reviewer proposes adding one, the reviewer must also justify why borrowed equality is insufficient for the specific test. |

#### 8.6.3. Property trial-count calibration

Trial counts are calibrated against the cost model established by
commit `3514fe4` ("tests/mail/e: rebalance property trial counts to
match cost model") and the tier definitions in
`tests/mproperty.nim:41-58`:

| Tier | Trials | Per-trial budget | Use case |
|------|--------|------------------|----------|
| `QuickTrials` | 200 | ~25-50 ms | Smoke-level invariants where divergence surfaces in first handful of trials |
| `DefaultTrials` | 500 | ~5-25 ms | Standard pure-Nim properties |
| `ThoroughTrials` | 2000 | ~1-5 ms | Large input spaces |
| `CrossProcessTrials` | 100 | ~100 ms | Cross-process structural equality |

Per-property assignment for §8.2.1's groups (group A was deleted;
group F was added — see §8.2.1):

| Group | Per-trial cost estimate | Tier |
|-------|------------------------|------|
| B — totality | ~3 ms (random openArray + constructor) | `DefaultTrials` |
| C — duplicate-key | ~3 ms | `DefaultTrials` |
| D — pointer escape bijectivity | ~1 ms | `DefaultTrials` |
| E — `toJson(EmailUpdateSet)` post-condition | ~3 ms | `DefaultTrials` |
| F — `moveToMailbox` ≡ `setMailboxIds` | ~0.5 ms (two constructors + one eq) | `QuickTrials` |

Group F lands at `QuickTrials` (200) because the predicate is cheap
and any divergence surfaces in the first handful of trials — the
`Id`-charset coverage gained from 500 trials vs 200 is marginal for
a structural-equivalence pin.

**`CrossProcessTrials` applicability.** `CrossProcessTrials` (100)
exists for tests that `exec` a sibling process and compare byte
output. Part F adds **none** — the `distinct seq[EmailUpdate]`
design means `toJson` output is a function of input alone, with no
hash-seed input path. The tier definition is retained in
`mproperty.nim:41-58` but Part F groups do not consume it.

**Smart-constructor unit tests** (§8.3 files) use direct fixed
inputs and do NOT consume the property tier budget at all — they
are unit tests. Where a smart constructor exhibits a variant-axis
fold (e.g., six variants of `EmailUpdateVariantKind`), the test
uses native `for variant in T:` iteration without a property-test
trial loop. Classifying these as "QuickTrials property tests" would
misuse the tier system.

Pinning trial counts at design time avoids the Part E rebalancing
fire-drill that motivated commit `3514fe4`. Tier values are
authoritative in `tests/mproperty.nim:41-58`; the table here
documents intent — actual numbers track the file.

#### 8.6.4. New `massertions.nim` template

```nim
template assertUpdateSetErrCount*(expr: untyped, n: int) =
  ## Exact-count assertion on the accumulated error rail for
  ## EmailUpdateSet (and analogous typed update sets). Mirrors
  ## assertBlueprintErrCount (L-3) for accumulating constructors.
  let res = expr
  assertErr res
  let actual = res.error.len
  doAssert actual == n,
    "expected " & $n & " errors, got " & $actual
```

Required by §8.10's scale invariants and §8.3's `accumulate*` unit
tests. Without it, exact-count checks must inline the comparison,
breaking consistency with the established assertion-helper pattern.

### 8.7. Conflict-pair equivalence-class enumeration tables

The Class 1/2/3 unit tests in `temail_update_set.nim` enumerate the
following equivalence-class representatives. F2 commits to
**explicit enumeration** rather than representative-by-prose — the
implementation cannot pass the tests by exercising one example per
class. (The previously proposed property group A quantified over
these same shapes at `DefaultTrials` tier, but the finite shape
product made the property redundant against the unit enumeration;
§8.2.1's rationale explains the removal.)

#### 8.7.1. Class 1 — duplicate target path (6 shapes)

| # | Variant A | Variant B | Shared target |
|---|-----------|-----------|---------------|
| 1 | `euAddKeyword(k)` | `euAddKeyword(k)` | `keywords/{k}` |
| 2 | `euRemoveKeyword(k)` | `euRemoveKeyword(k)` | `keywords/{k}` |
| 3 | `euSetKeywords(ks1)` | `euSetKeywords(ks2)` | `keywords` |
| 4 | `euAddToMailbox(id)` | `euAddToMailbox(id)` | `mailboxIds/{id}` |
| 5 | `euRemoveFromMailbox(id)` | `euRemoveFromMailbox(id)` | `mailboxIds/{id}` |
| 6 | `euSetMailboxIds(ids1)` | `euSetMailboxIds(ids2)` | `mailboxIds` |

#### 8.7.2. Class 2 — opposite operations on same sub-path (2 shapes)

| # | Variant A | Variant B | Sub-path |
|---|-----------|-----------|----------|
| 1 | `euAddKeyword(k)` | `euRemoveKeyword(k)` | `keywords/{k}` |
| 2 | `euAddToMailbox(id)` | `euRemoveFromMailbox(id)` | `mailboxIds/{id}` |

Both Class 2 shapes also collide on target path (Class 1 condition).
F1 §3.2.4's narrative treats them as Class 2 examples.

**Overlap policy — committed.** The implementation emits **Class 2
only** for these overlap shapes (the tighter, more-informative
classification). Rationale: Class 2 strictly implies Class 1 for
these shape pairs (same sub-path plus opposite operation is a
superset condition), so reporting both errors would produce
redundant output that a consumer must deduplicate. The `class1And2Overlap`
unit test asserts:

```
let es = initEmailUpdateSet(@[
  euAddKeyword(kwSeen),
  euRemoveKeyword(kwSeen)
])
doAssert es.isErr
doAssert es.error.len == 1
doAssert es.error[0].classification == Class2OppositeOperations
```

Choosing "emit tighter" (Class 2) matches the RFC 6902 JSON Patch
convention where `replace` dominates `add + remove` for the same
path — the tighter op is the canonical description.

#### 8.7.3. Class 3 — sub-path operation alongside full-replace on same parent (4 shapes)

| # | Sub-path variant | Full-replace variant | Parent |
|---|------------------|----------------------|--------|
| 1 | `euAddKeyword(k)` | `euSetKeywords(ks)` | `keywords` |
| 2 | `euRemoveKeyword(k)` | `euSetKeywords(ks)` | `keywords` |
| 3 | `euAddToMailbox(id)` | `euSetMailboxIds(ids)` | `mailboxIds` |
| 4 | `euRemoveFromMailbox(id)` | `euSetMailboxIds(ids)` | `mailboxIds` |

The Class 3 discriminator is the **target path**, not the payload.
Adversarial cases (§8.2.3 "Conflict-algebra corner cases") pin both
empty-`euSetKeywords` and non-empty-`euSetKeywords` payloads as
equivalent Class 3 violations.

#### 8.7.4. Independent (NOT conflicts) — 4 shapes

| # | Variant A | Variant B | Why independent |
|---|-----------|-----------|-----------------|
| 1 | `euSetKeywords(ks)` | `euSetMailboxIds(ids)` | Different parent paths; both full-replace on independent fields |
| 2 | `euAddKeyword(k1)` | `euAddKeyword(k2)` (`k1 ≠ k2`) | Different sub-paths |
| 3 | `euAddKeyword(k)` | `euAddToMailbox(id)` | Different parent paths entirely |
| 4 | `euAddToMailbox(id1)` | `euRemoveFromMailbox(id2)` (`id1 ≠ id2`) | Different sub-paths under the same parent — Class 2 only applies when the sub-path is *identical* |

These shapes are **mandatory positive** test cases — without them, an
over-eager Class 1 detector that hashes by parent path alone (shape 1
/ 3), a Class 1 detector that ignores the keyword discriminator
(shape 2), or a Class 2 detector that fires on "opposite op under
same parent" without checking sub-path equality (shape 4) would pass
all the negative tests (false confidence). Shape 4 is the symmetric
counterpart on the mailbox axis to shape 2 on the keyword axis — the
addition closes the diagonal.

### 8.8. RFC 6901 escape-boundary test matrix

Pins F1 §3.2.5's `jsonPointerEscape` contract. Table-driven cases in
`tests/serde/mail/tserde_email_update.nim`; bijectivity quantified
in property group D (§8.2.1).

| Test name | Input keyword | Expected wire-key fragment | Attack pinned |
|-----------|---------------|----------------------------|---------------|
| `escNoMetachars` | `"$seen"` | `"keywords/$seen"` | Baseline: `$` does not trigger escape |
| `escTildeOnly` | `"a~b"` | `"keywords/a~0b"` | `~ → ~0` |
| `escSlashOnly` | `"a/b"` | `"keywords/a~1b"` | `/ → ~1` |
| `escTildeAndSlash` | `"a~/b"` | `"keywords/a~0~1b"` | Escape order: `~` before `/`, not after |
| `escAllMeta` | `"~/~/"` | `"keywords/~0~1~0~1"` | All-metacharacter input |
| `escOrderMatters` | `"~/"` | `"keywords/~0~1"` (NOT `~01`) | Direct order pin: swapped-`replace` regression |
| `escSingleTilde` | `"~"` | `"keywords/~0"` | Single-char minimum for tilde |
| `escSingleSlash` | `"/"` | `"keywords/~1"` | Single-char minimum for slash |
| `escEmbeddedTildeZero` | `"a~0b"` | `"keywords/a~00b"` | Input contains literal `~0` — must escape to `~00` (the `~` is escaped, the `0` is passed through). Collision adversary against a decoder that round-trips to `"a\0b"`. |
| `escEmbeddedTildeOne` | `"a~1b"` | `"keywords/a~01b"` | Input contains literal `~1`; same collision adversary for the `/` form. Shares the adversary class with property group D. |
| `escDoubleTilde` | `"~~"` | `"keywords/~0~0"` | Consecutive tildes — naive `for c in s` + accumulating buffer handles correctly; a `replace-all-tildes-then-replace-all-slashes` pipeline also handles this but fails `escOrderMatters`. |
| `escDoubleSlash` | `"//"` | `"keywords/~1~1"` | Consecutive slashes; no interaction with tilde. |
| `escTrailingTilde` | `"abc~"` | `"keywords/abc~0"` | Terminal-position tilde — catches off-by-one in a length-bounded loop. |
| `escLeadingTilde` | `"~abc"` | `"keywords/~0abc"` | Leading-position tilde — catches `if i > 0` bug. |
| `escUtf8Keyword` | `"$日本語"` (JIS kanji) | `"keywords/$日本語"` (verbatim UTF-8 bytes) | Non-ASCII pass-through — the escape is byte-level and affects only ASCII `~` / `/`. Pins that the escape function is UTF-8-safe. |

Property group D in §8.2.1 quantifies the bijectivity invariant:
distinct keywords escape to distinct wire keys. The pair
`("a/b", "a~1b")` is the canonical adversarial input — under a
buggy swapped-replace order they would both produce `"a~1b"`,
silently corrupting one update.

The upstream `parseKeyword` acceptance of `~` and `/` is pinned in
`tests/unit/mail/tkeyword.nim` (§8.3) — without it the escape tests
above are unreachable in practice.

The Layer 1 baseline (`PatchObject` stores keys verbatim, performs
no encoding) is established by `tests/stress/tadversarial.nim`
blocks `patchJsonPointerTilde0Encoding` /
`patchJsonPointerTilde1Encoding` / `patchObjectRfc6901TildeZero` /
`patchObjectRfc6901TildeOne`. The §8.8 tests above verify the
**Layer 2** guarantee that `toJson(EmailUpdate)` supplies the
encoding the lower layer omits.

### 8.9. Adversarial response-decode matrix

Pins per-field attacks for `EmailSetResponse.fromJson`,
`EmailCopyResponse.fromJson`, and `EmailImportResponse.fromJson` in
`tests/stress/tadversarial_mail_f.nim`. Each row is one named test.

| Field | Attack variant | Expected outcome |
|-------|----------------|------------------|
| `created` (top-level) | `JArray` instead of `JObject` | `Err` (wrong JSON kind) |
| `created` | `JNull` (Email/import wire case per RFC §4.8) | `Ok` with empty `createResults` |
| `created` entry key | `"#badkey"` (invalid `CreationId`) | `Err` or synthetic `SetError` on `createResults` |
| `created` entry value | `JString` instead of `JObject` | Synthetic `SetError` in `createResults` |
| `created` entry value | Missing `"size"` field | Synthetic `SetError` in `createResults` |
| `created` entry value | `"size": "string"` (wrong type) | Synthetic `SetError` in `createResults` |
| `created` entry value | `"id": 42` (integer where Id expected) | Synthetic `SetError` in `createResults` |
| `created` entry value | Extra unknown fields alongside the four required | Accepted; unknown fields ignored (Postel) |
| `updated` entry value | `JString` (not `JNull` or `JObject`) | `Err` on the containing Result rail |
| `updated` entry value | `JNumber` (not `JNull` or `JObject`) | `Err` on the containing Result rail |
| `updated` entry value | `JArray` (not `JNull` or `JObject`) | `Err` on the containing Result rail |
| `updated` entry value | `JBool` (not `JNull` or `JObject`) | `Err` on the containing Result rail |
| `updated` entry value | `JNull` | `Ok`: `UpdatedEntry(kind: uekUnchanged)` |
| `updated` entry value | `{}` (empty `JObject`) | `Ok`: `UpdatedEntry(kind: uekChanged, changedProperties: %*{})` — distinct from `JNull` per F1 §2.3 |
| `updated` round-trip | re-encode `uekUnchanged` → `null`; re-encode `uekChanged({})` → `{}` | Wire form preserved (no collapse) |
| `updated` map key | `"!!invalid!!"` (non-Id charset) | `Err` (invalid `Id` key) |
| `updated` (top-level) | absent | `Opt.none` |
| `updated` (top-level) | `null` | `Opt.none` |
| `updated` (top-level) | `{}` | `Opt.some(emptyTable)` |
| `notDestroyed` map key | `""` (empty string, fails `Id` charset) | `Err` |
| `notDestroyed` map key | `"!!"` (invalid `Id`) | `Err` |
| `destroyed` | `JNull` | `Opt.none` |
| `destroyed` | absent | `Opt.none` |
| `destroyed` | `[]` (empty array) | `Opt.some(@[])` |
| `destroyed` | `["id1", "id2"]` | `Opt.some(@[id1, id2])` |
| `destroyed` | `JObject` instead of `JArray` | `Err` (wrong JSON kind) |
| `oldState` | `JNull` (field present as null) | `Opt.none` |
| `accountId` | `JNull` (required field) | `Err` |
| `newState` | `JInt` instead of `JString` | `Err` |
| `notCreated` | `JArray` instead of `JObject` | `Err` (wrong JSON kind) |
| `notCreated` | `JNull` | `Opt.none` / empty (document which shape the parser chooses and pin) |
| `notCreated` entry key | `"#badkey"` (invalid `CreationId`) | `Err` |
| `notCreated` entry value | Missing `type` field on SetError | `Err` |
| `notCreated` entry value | `type: "forbidden"` with no `description` | `Ok` (description is optional) |
| `notCreated` entry value | `type: "customServerExtension"` (unrecognised type) | `Ok` with `errorType = setUnknown`, `rawType = "customServerExtension"` (lossless round-trip) |
| `notCreated` entry value | `type: "invalidProperties"` with `properties: "string-not-array"` | `Err` (type coercion refused) |
| `notCreated` entry value | `type: "invalidProperties"` with `properties: []` (empty array) | `Ok` — empty `properties` is valid |
| `notCreated` entry value | SetError `description` with embedded NUL | `Ok` with description verbatim (documents no byte filtering) |
| `notUpdated` | `JArray` instead of `JObject` | `Err` |
| `notUpdated` entry key | `""` (empty Id) | `Err` |
| `notUpdated` and `notDestroyed` present with same key | same | Both surface separately; no cross-map dedup (each map tests an independent failure mode) |
| Cross-slot | `created` and `notCreated` share the same `CreationId` | deterministic precedence: `notCreated` wins (conservative — see §8.2.3 "Cross-response coherence"). |
| `updated` entry value | `{"id": 42}` (well-formed `JObject` with wrong payload type) | `Ok`: `UpdatedEntry(kind: uekChanged, changedProperties: %*{"id": 42})` — this layer is shape-faithful, domain validation happens on access |
| `updated` entry value round-trip | `{}` (explicit empty object — distinct from `null`) | `uekChanged({})`, re-encoding produces `{}` not `null` |
| `MDN/send` response shape (forward-compat) | response contains unknown top-level field | Ignored (Postel) |
| `accountId` | wrong type (`JBool`) | `Err` |
| `oldState` | wrong type (`JInt`) | `Err` |
| Wrong-slot attack | Server serves `EmailCopyResponse` shape under the method call ID expected for `Email/set` | `Err` during decode — the typed `fromJson` refuses the foreign shape (tests shape-discrimination) |
| `EmailImportResponse` | `created: { "c1": {...}, "c2": null }` (one entry value is null) | synthesises a `SetError` for that entry in `createResults` |
| Top-level | entire response body is `JNull` | `Err` on outer rail |
| Top-level | entire response body is `JArray` | `Err` on outer rail |
| Top-level | empty `JObject` `{}` | `Err` (required `accountId` missing) |
| Top-level | contains extra keys (`"foo": 42`) alongside required fields | `Ok` (Postel; unknown top-level ignored) |
| Nested unknown | `createResults` entry with `{ "id": "x", "blobId": "y", "threadId": "z", "size": 0, "unknown": "extra" }` | `Ok` — Postel; per-entry unknown ignored (pins that the Postel property applies at every decode tier, not just top level) |

### 8.10. Accumulating constructor scale invariants

Pins F1 §3.2.4's "single pass" plus "one error per detected conflict"
commitments under stress. Lives in `tests/stress/tadversarial_mail_f.nim`.
Mirrors `tests/stress/tadversarial_blueprint.nim` scenarios 101a /
101b (error-accumulation stress) and `tests/stress/tadversarial.nim`
`stressResponseMethodResponses100k` (unbounded-collection stress).

| Test name | Constructor | Input shape | Expected outcome |
|-----------|-------------|-------------|------------------|
| `emailUpdateSet10kClass1Anchored` | `initEmailUpdateSet` | 10 001 entries; entries 1..10 000 share target path with entry 0 (all pair-conflicts resolve to entry 0) | `Err` with exactly 10 000 `ValidationError`s; capacity bound `≤ 2 × 10 000`; **wall-clock bound: ≤ 500 ms on CI hardware** (pins the `O(n)` invariant — a naive `O(n²)` algorithm would blow this tenfold) |
| `emailUpdateSet10kClass1NoAnchor` | `initEmailUpdateSet` | 10 000 entries, all sharing a single target path; no privileged "entry 0" (every entry conflicts with every other entry) | `Err` with exactly 9999 `ValidationError`s (one per pair after entry 0, NOT C(10000, 2)); pins that the conflict-detection counts in-order pairs once, not the combinatorial number |
| `emailUpdateSetThreeClassesStaggered` | `initEmailUpdateSet` | n = 1000 entries; Class 1 conflict at pos 0, Class 2 at pos 500, Class 3 at pos 999 | `Err` with exactly 3 `ValidationError`s |
| `emailUpdateSetLatePositionConflict` | `initEmailUpdateSet` | 1000 entries; Class 1 conflict introduced at position 998 only | `Err` with exactly 1 `ValidationError` (single-pass algorithm doesn't bail after a fixed prefix) |
| `emailUpdateSet100kWallClock` | `initEmailUpdateSet` | 100 000 valid entries, no conflicts | `Ok`; **wall-clock bound: ≤ 5 s on CI hardware**. Pins the linear-scaling contract. Mirrors `tadversarial.nim:stressResponseMethodResponses100k` (the 100k scale precedent for response-side tests). Tagged `stress-only` — excluded from default `just test` run, gated on `just stress`. |
| `nonEmptyImportMap10kWithDupAtEnd` | `initNonEmptyEmailImportMap` | 10 000 entries; duplicate `CreationId` at position 9999 | `Err` with the duplicate violation; capacity bounded; mirrors `tadversarial_blueprint.nim:bodyPartDupTenThousand` (scenario 101a) |
| `nonEmptyImportMapEmptyAndDupSeparately` | `initNonEmptyEmailImportMap` | shape forcing each invariant independently (the empty case and the duplicate case cannot co-occur for the same input — empty has no duplicates) | Each invariant fires in its own input shape; unified accumulating-Err shape |

**Cross-process determinism note.** `EmailUpdateSet`'s
`distinct seq[EmailUpdate]` design (rather than `Table`) gives
`toJson(EmailUpdateSet)` byte-deterministic output across processes —
no hash-seed nondeterminism. The serialisation tests in §8.8 plus
property group E (§8.2.1) implicitly verify this; an explicit
cross-process probe (analogous to
`tadversarial_blueprint.nim:crossProcessByteDeterminism` scenario
102c) is **not** added because the type design eliminates the
failure mode rather than mitigating it. (The neighbouring scenario
`topLevelDupCeilingAtEleven` at `tadversarial_blueprint.nim:311`
exercises a different invariant — duplicate-count ceiling — and is
the model for `nonEmptyImportMap10kWithDupAtEnd` above, which
mirrors `bodyPartDupTenThousand` at `tadversarial_blueprint.nim:281`
scenario 101a.) If a future change moves `EmailUpdateSet` to a
`Table`, the explicit cross-process probe must be added.

### 8.11. Generic SetError applicability matrix test plan

Pins F1 §7.2 table 2 — eight generic `SetError` variants × three
methods × the operations each method supports. Lives in
`tests/protocol/tmail_method_errors.nim` (§8.4 NEW file).

| `SetError` variant | RFC operation scope | Email/set | Email/copy | Email/import |
|--------------------|---------------------|-----------|------------|--------------|
| `forbidden` | create; update; destroy | ✓ | ✓ (create) | ✓ (create) |
| `overQuota` | create; update | ✓ | ✓ (create) | ✓ (create) |
| `tooLarge` | create; update | ✓ | ✓ (create) | ✓ (create) |
| `rateLimit` | create | ✓ (create) | ✓ (create) | ✓ (create) |
| `notFound` | update; destroy | ✓ (update) | ✓ (RFC §4.7 grants create-side `notFound` for missing blobId) | — |
| `invalidPatch` | update | ✓ (update only) | — | — |
| `willDestroy` | update | ✓ (update only) | — | — |
| `invalidProperties` | create; update | ✓ | ✓ (create) | ✓ (create) |
| `singleton` | create; destroy | ✗ negative-test | ✗ negative-test | ✗ negative-test |

Each `✓` cell is one named test per method × operation combination
that synthesises the corresponding wire `SetError` in the
appropriate response slot (`notCreated`, `notUpdated`,
`notDestroyed`) and verifies the typed `SetError` surfaces correctly
through the typed response decode. For `SetError` variants whose
scope covers multiple operations (e.g., `forbidden` over create +
update + destroy in `Email/set`), the expansion is one named test
per operation — `emailSetForbiddenOnCreate`,
`emailSetForbiddenOnUpdate`, `emailSetForbiddenOnDestroy` — not a
single test covering all three. Each `✗ negative-test` cell
verifies that the variant **parses** (Postel robustness — a buggy
or future-extension server might emit it) but documents that no
Part F method is expected to emit it.

**Native enum iteration is mandatory.** The implementation MUST
fold via `for kind in SetErrorType:` (precedent: `terrors.nim:428`).
No helper combinator is introduced — the explicit loop makes the
variant set visible at the call site and the compiler enforces
exhaustiveness via `case` expressions inside the loop body.

### 8.12. Coverage matrix — F1 promises to test cases

Mechanical mapping between F1 commitments and the test cases that
pin them. Surfaces holes by inspection — every F1 § that makes a
behavioural promise has at least one row.

| F1 § | Promise | Test file | Test name |
|------|---------|-----------|-----------|
| §1.5.3 | `PatchObject` demoted from public API | `tests/compliance/tmail_f_reexport.nim` | `patchObjectNotPubliclyVisible` (compile-time, §8.5.1) |
| §1.6 | `EmailUpdate` is `toJson`-only (no `fromJson`) | `tests/compliance/tmail_f_reexport.nim` | `emailUpdateHasNoFromJson` (§8.2.2 block 4) |
| §1.6 | `EmailUpdateSet` is `toJson`-only | `tests/compliance/tmail_f_reexport.nim` | `emailUpdateSetHasNoFromJson` |
| §1.6 | `EmailCopyItem` is `toJson`-only | `tests/compliance/tmail_f_reexport.nim` | `emailCopyItemHasNoFromJson` |
| §1.6 | `EmailImportItem` is `toJson`-only | `tests/compliance/tmail_f_reexport.nim` | `emailImportItemHasNoFromJson` |
| §1.6 | `NonEmptyEmailImportMap` is `toJson`-only | `tests/compliance/tmail_f_reexport.nim` | `nonEmptyEmailImportMapHasNoFromJson` |
| §2.1 | `EmailCreatedItem` refuses partial construction | `tests/serde/mail/tserde_email_set_response.nim` | `emailCreatedItemMissingSizeRejected` |
| §2.2 | `EmailCopyResponse` has no `updated`/`destroyed` fields | `tests/serde/mail/tserde_email_copy.nim` | `emailCopyResponseHasNoUpdatedField` (compile-time) |
| §2.3 | `UpdatedEntry` distinguishes `{}` from `null` | `tests/serde/mail/tserde_email_set_response.nim` | `updatedEntryNullVsEmptyDistinct` |
| §2.3 | `UpdatedEntry` rejects non-object/non-null kinds | `tests/stress/tadversarial_mail_f.nim` (per §8.9 rows) | `updatedEntryRejectsString`, `updatedEntryRejectsNumber`, `updatedEntryRejectsArray`, `updatedEntryRejectsBool` |
| §2.3 | `UpdatedEntry` round-trip preserves `null` vs `{}` | `tests/stress/tadversarial_mail_f.nim` | `updatedEntryRoundTripPreservesDistinction` |
| §2.5 | `EmailSetResponse.updated` three-state (absent/null/{}) | `tests/serde/mail/tserde_email_set_response.nim` | `updatedTopLevelAbsent`, `updatedTopLevelNull`, `updatedTopLevelEmptyObject` |
| §2.5 | `EmailSetResponse.destroyed` three-state | `tests/serde/mail/tserde_email_set_response.nim` | `destroyedAbsent`, `destroyedEmptyArray`, `destroyedTwoElement` |
| §3.2.1 | `EmailUpdateVariantKind` exhaustive case | `tests/compliance/tmail_f_reexport.nim` | `emailUpdateVariantKindExhaustiveCaseCompiles` |
| §3.2.1 | Six primitive + five convenience constructors | `tests/unit/mail/temail_update.nim` | per `temail_update.nim` (1) and (2) — 11 named tests, see §8.3 row |
| §3.2.3.1 | `moveToMailbox` emits `euSetMailboxIds`, NOT `euAddToMailbox` | `tests/serde/mail/tserde_email_update.nim` | `moveToMailboxWireIsSetMailboxIds` (positive + negative pair) |
| §3.2.3.1 | `moveToMailbox(id) ≡ setMailboxIds(...)` quantified over `Id` | `tests/property/tprop_mail_f.nim` | property group F |
| §3.2.4 Class 1 | All 6 duplicate-target shapes rejected | `tests/unit/mail/temail_update_set.nim` | per §8.7.1 (6 named tests, one per row) |
| §3.2.4 Class 2 | Both opposite-op shapes rejected | `tests/unit/mail/temail_update_set.nim` | `class2KeywordOpposite`, `class2MailboxOpposite` |
| §3.2.4 Class 3 | All 4 sub-path × full-replace shapes rejected | `tests/unit/mail/temail_update_set.nim` | per §8.7.3 (4 named tests) |
| §3.2.4 Class 3 | Payload-irrelevance (empty vs non-empty setKeywords) | `tests/stress/tadversarial_mail_f.nim` | `class3PayloadIrrelevantEmptySetKeywords`, `class3PayloadIrrelevantNonEmptySetKeywords` |
| §3.2.4 Independent | 4 accepted combinations | `tests/unit/mail/temail_update_set.nim` | per §8.7.4 (4 mandatory positive tests) |
| §3.2.4 Accumulation | One `ValidationError` per detected conflict | `tests/unit/mail/temail_update_set.nim` | `accumulateMixedClasses` (exact-3 via `assertUpdateSetErrCount`); `accumulateOneClassThree`; `accumulateEmptyAlone` |
| §3.2.4 Class 1+2 overlap | Pin reported class = Class 2 (committed policy) | `tests/unit/mail/temail_update_set.nim` | `class1And2Overlap` |
| §3.2.4 | Single-pass algorithm doesn't bail after fixed prefix | `tests/stress/tadversarial_mail_f.nim` | `emailUpdateSetLatePositionConflict` |
| §3.2.4 | Scale — anchored & unanchored conflict patterns | `tests/stress/tadversarial_mail_f.nim` | `emailUpdateSet10kClass1Anchored`, `emailUpdateSet10kClass1NoAnchor`, `emailUpdateSet100kWallClock` |
| §3.2.4 | Cast-bypass does NOT add post-hoc validation | `tests/stress/tadversarial_mail_f.nim` | `castBypassDocumentsNoPostHocValidation`, `castBypassEmptyAccepted` |
| §3.2.5 | RFC 6901 `~ → ~0`, `/ → ~1`, escape order matters | `tests/serde/mail/tserde_email_update.nim` | per §8.8 (15 named tests including new rows `escEmbeddedTildeZero`, `escEmbeddedTildeOne`, `escDoubleTilde`, `escDoubleSlash`, `escTrailingTilde`, `escLeadingTilde`, `escSingleTilde`, `escSingleSlash`, `escUtf8Keyword`) |
| §3.2.5 | Pointer escape bijectivity | `tests/property/tprop_mail_f.nim` | property group D |
| §3.2.5 | `Keyword` charset includes `~` and `/` | `tests/unit/mail/tkeyword.nim` | `keywordWithTildeAccepted`, `keywordWithSlashAccepted`, `keywordWithBothAccepted` |
| §3.3 | `MailboxUpdateSet` duplicate-target rejection (5 variants) | `tests/unit/mail/tmailbox.nim` | per-variant fold (5 named tests, native `for variant in MailboxUpdateVariantKind:`) |
| §3.3 | `setRole(Opt.none) → JSON null` (clear-role) | `tests/serde/mail/tserde_mailbox.nim` | `setRoleNoneEmitsJsonNull` |
| §3.3 | `setRole(Opt.some(role)) → JSON string` | `tests/serde/mail/tserde_mailbox.nim` | `setRoleSomeEmitsString` |
| §3.3 | `setParentId(Opt.none) → JSON null` (reparent-to-top) | `tests/serde/mail/tserde_mailbox.nim` | `setParentIdNoneEmitsJsonNull` |
| §3.3 | `setParentId(Opt.some(id)) → JSON string` | `tests/serde/mail/tserde_mailbox.nim` | `setParentIdSomeEmitsString` |
| §3.4 | `VacationResponseUpdateSet` duplicate-target rejection (6 variants) | `tests/unit/mail/tvacation.nim` | per-variant fold (6 named tests per §8.3 `tvacation.nim` (4)) |
| §3.4 | `VacationResponseUpdate` nullable-field wire behaviour | `tests/serde/mail/tserde_vacation.nim` | `vruSetFromDateNoneEmitsNull`, `vruSetToDateNoneEmitsNull`, `vruSetSubjectNoneEmitsNull`, `vruSetTextBodyNoneEmitsNull`, `vruSetHtmlBodyNoneEmitsNull` (per-field Opt.none pin) |
| §4.1 | `addEmailSet` full invocation | `tests/protocol/tmail_builders.nim` | `addEmailSetFullInvocation` |
| §4.1 | `addEmailSet` minimal (all `Opt.none`) | `tests/protocol/tmail_builders.nim` | `addEmailSetMinimalAccountIdOnly` |
| §4.1 | `addEmailSet` `ifInState` wire semantics | `tests/protocol/tmail_builders.nim` | `addEmailSetIfInStateEmitted`, `addEmailSetIfInStateOmittedWhenNone` |
| §4.2 | `addEmailImport` phantom-typed response | `tests/protocol/tmail_methods.nim` | `addEmailImportPhantomTyped` |
| §4.2 | `addEmailImport` `ifInState` pass-through | `tests/protocol/tmail_methods.nim` | `addEmailImportIfInStateSomePassthrough`, `addEmailImportIfInStateNoneOmitted` |
| §5.3 | `addEmailCopyAndDestroy` emits `onSuccessDestroyOriginal: true`; all three state params | `tests/protocol/tmail_builders.nim` | `addEmailCopyAndDestroyEmitsTrue`, `addEmailCopyAndDestroyDestroyFromIfInStateSome`, `addEmailCopyAndDestroyDestroyFromIfInStateNone`, `addEmailCopyAndDestroyAllStateParamsSome` |
| §5.3 | `addEmailCopy` (simple) has no `onSuccessDestroyOriginal` | `tests/protocol/tmail_builders.nim` | `addEmailCopyPhantomType`, `addEmailCopyIfInStateEmittedWithCopySemantics` |
| §5.4 | `getBoth` happy path + short-circuits (copy error, destroy missing, destroy error) | `tests/protocol/tmail_builders.nim` | `getBothCopyAndDestroyHappyPath`, `getBothShortCircuitOnCopyError` (table-driven via `for variant in MethodErrorType:`), `getBothShortCircuitOnDestroyMissing`, `getBothShortCircuitOnDestroyError` |
| §5.4 | `getBoth` adversarial (method-call-id mismatch, empty createResults) | `tests/stress/tadversarial_mail_f.nim` | (three adversarial scenarios enumerated in §8.2.3 "`getBoth(EmailCopyHandles)` adversarial") |
| §6.2 | `NonEmptyEmailImportMap` preserves insertion order | `tests/unit/mail/tnon_empty_email_import_map.nim` | `nonEmptyImportMapPreservesInsertionOrder` |
| §6.2 | Order-deterministic error messages | `tests/unit/mail/tnon_empty_email_import_map.nim` | `nonEmptyImportMapDeterministicErrorOrder` |
| §6.2 | Empty & duplicate invariants both accumulated | `tests/unit/mail/tnon_empty_email_import_map.nim` | `nonEmptyImportMapEmptyRejected`, `nonEmptyImportMapDuplicateCreationIdRejected`, `nonEmptyImportMapDuplicateAndEmptyAccumulatedSeparately` |
| §6.2 | Scale — 10k entries with duplicate at end | `tests/stress/tadversarial_mail_f.nim` | `nonEmptyImportMap10kWithDupAtEnd` |
| §6.1 | `EmailCopyItem` mailbox-override type-level rejection | `tests/unit/mail/temail_copy_item.nim` | `copyItemTypeRejectsEmptyMailboxIdSet`, `copyItemTypeRejectsNonEmptyMailboxIdSetWrongDistinct` |
| §6.1 | `EmailCopyItem` serde (minimal / full override) | `tests/serde/mail/tserde_email_copy.nim` | `emailCopyItemMinimalEmitsEmpty`, `emailCopyItemFullOverrideEmitsThreeKeys` |
| §6.3 | `EmailImportItem` required `mailboxIds`, optional `keywords` | `tests/unit/mail/temail_import_item.nim` | `importItemRejectsOptNoneMailboxIds`, `importItemKeywordsRoundTripThreeStates` |
| §7.1 | `SetError.extras` extractors work via Email-method `createResults` | `tests/stress/tadversarial_mail_f.nim` | `emailSetExtrasReachableFromCreateResults`, `emailCopyExtrasReachableFromCreateResults`, `emailImportExtrasReachableFromCreateResults` |
| §7.2 | Generic `SetError` applicability matrix | `tests/protocol/tmail_method_errors.nim` | per §8.11 cell (one named test per method × operation for ✓ cells, one `singleton` negative test per method for ✗ cell) |
| §7.4 | Method-level errors per method (3 × ≤ 7) | `tests/protocol/tmail_method_errors.nim` | per §8.4 `tmail_method_errors.nim` list (7 named tests) |
| §7.5 | Adversarial `SetError.extras` via integration path | `tests/stress/tadversarial_mail_f.nim` | (five cases enumerated in §8.2.3 "SetError.extras adversarial") |
| §8 (meta) | Cross-response coherence anomalies | `tests/stress/tadversarial_mail_f.nim` | `coherenceOldStateNewStateEqual`, `coherenceOldStateNewStateNullPair`, `coherenceAccountIdMismatchAcrossInvocations`, `coherenceUpdatedSameKeyTwice`, `coherenceCreatedAndNotCreatedShareKey` |
| §8 (meta) | JSON-structural attack surface | `tests/stress/tadversarial_mail_f.nim` | `structuralBomPrefix`, `structuralNanInfinity`, `structuralDuplicateKeysInObject`, `structuralDeepNesting`, `structuralLargeStringSize`, `structuralEmptyKey`, `structuralUnicodeNoncharacters` |

The matrix is a **living artefact**: any new F1 promise (added under
F20 architecture amendments or later parts) MUST add a row here
before the implementation merges. The matrix is the single artefact
that proves test-spec adequacy by inspection.

### 8.13. Verification commands

Implementation PR verification sequence:

- `just build` — shared library compiles; no new warnings.
- `just test` — every test file above runs green.
- `just analyse` — nimalyzer passes without new suppressions.
- `just fmt-check` — nph formatting unchanged.
- `just ci` — full pipeline green.

The compile-time reachability smoke (`tmail_f_reexport.nim` with
`action: "compile"`) fails loudly if any new public symbol is not
re-exported through `jmap_client.nim`, OR if `PatchObject` becomes
publicly visible again (§8.5.1 enforcement gate), OR if any
variant-kind discriminator gains a variant that an existing `case`
fails to handle (§8.2.2 block 3), OR if any creation-model type
gains a reachable `fromJson` overload (§8.2.2 block 4). Property
tests in `tprop_mail_f.nim` cover the accumulating-constructor
totality (B), the duplicate-key invariant for
`NonEmptyEmailImportMap` (C), the RFC 6901 escape bijectivity (D),
the `toJson(EmailUpdateSet)` post-condition (E), and the
`moveToMailbox ≡ setMailboxIds` quantification (F). Coverage matrix
§8.12 is the single inspection point for "is every F1 promise
pinned by a test?"

---

*End of Part F2 design document.*
