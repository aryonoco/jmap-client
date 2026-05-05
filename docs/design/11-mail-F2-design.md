# RFC 8621 JMAP Mail — Design F2: Email Write Path — Test Specification

Companion test specification for [`11-mail-F1-design.md`](./11-mail-F1-design.md).
The section number below is kept at `8` so cross-references from F1
(§1–§7 and §9) into this document stay valid.

This document is the living test specification for Part F. The source
under `src/jmap_client/mail/` and the tests under `tests/**/mail/`,
`tests/protocol/`, `tests/property/`, `tests/compile/`, and
`tests/stress/` are the source of truth; this document describes what
those files pin. Any disagreement is resolved by editing this document
to match the code.

---

## 8. Test Specification

### 8.1. Testing strategy

Part F mirrors Part E's test category shape:

1. **Unit** — per-type smart-constructor invariants and serde
   round-trip for every Part F type. Includes `assertNotCompiles`
   gates where type-level guarantees warrant defence.
2. **Serde** — `toJson`/`fromJson` output shape per field, variant,
   and RFC constraint, plus the typed-update-algebra → wire-patch
   translation.
3. **Property-based** — `tests/property/tprop_mail_f.nim` covering
   accumulating-constructor totality, duplicate-key invariants,
   RFC 6901 escape bijectivity, the `toJson(EmailUpdateSet)`
   post-condition, and the `moveToMailbox` ≡ `setMailboxIds`
   equivalence.
4. **Adversarial / stress** — `tests/stress/tadversarial_mail_f.nim`
   covering malformed-response decode, conflict-algebra corner
   cases, accumulating-constructor scale invariants, cross-response
   coherence, JSON-structural attacks, `SetError.extras` integration,
   `getBoth(EmailCopyHandles)` failure surface, and the cast-bypass
   policy pin.
5. **Compile-time reachability** —
   `tests/compile/tcompile_mail_f_public_surface.nim` (action:
   `"compile"` via the ambient `{.push raises: [].}`; the `static:`
   block compiles but has no runtime effect) proves every Part F
   public symbol is reachable through the top-level `jmap_client`
   re-export chain.

**Generic /set response surface.** `Email/set` and `Email/copy`
responses use the generic `SetResponse[EmailCreatedItem]` and
`CopyResponse[EmailCreatedItem]` from `src/jmap_client/methods.nim`,
not bespoke per-entity records. The merged
`createResults: Table[CreationId, Result[EmailCreatedItem, SetError]]`,
`updateResults: Table[Id, Result[Opt[JsonNode], SetError]]`, and
`destroyResults: Table[Id, Result[void, SetError]]` collapse the wire's
parallel `created`/`notCreated`, `updated`/`notUpdated`, and
`destroyed`/`notDestroyed` maps into single `Result`-typed tables. The
inner `Opt[JsonNode]` on `updateResults` preserves the RFC 8620 §5.3
`PatchObject|null` distinction: `Opt.none(JsonNode)` ↔ wire `null`
(server made no observable changes), `Opt.some(node)` ↔ wire object
(changed-property map). `EmailImportResponse` stays bespoke — RFC 8621
§4.8 imports have no `update`/`destroy` branches and there is no
generic `ImportResponse[T]`.

**File-naming.** Property and adversarial files follow the per-part
naming `tprop_mail_f.nim` / `tadversarial_mail_f.nim`. The compile
file is `tcompile_mail_f_public_surface.nim`.

**Test idiom.** Tests use `block <name>:` plus
`assertOk` / `assertOkEq` / `assertErr` / `assertErrFields` /
`assertErrType` / `assertEq` / `assertLen` / `assertLe` /
`assertSome` / `assertSomeEq` / `assertNone` / `assertNotCompiles` /
`assertJsonFieldEq` / `assertJsonKeyAbsent` / `assertSvKind` from
`tests/massertions.nim`, plus raw `doAssert` for inline checks. No
`std/unittest` `test "name":` blocks, no `suite` wrappers.

Test-infrastructure additions follow the `make<Type>` /
`makeFull<Type>` precedent in `tests/mfixtures.nim` and the
`gen<Type>` / `genInvalid<Type>` precedent in
`tests/mproperty.nim`. No new test-support modules are introduced
— typed-update factories, equality helpers, and generators land in
the existing modules alongside their Part E precedents.

### 8.2. Part-lettered test files

#### 8.2.1. `tests/property/tprop_mail_f.nim`

Five property groups:

| Group | Property | Tier | Generator |
|-------|----------|------|-----------|
| B | `initEmailUpdateSet` totality — for every `openArray[EmailUpdate]` the constructor returns `Ok` xor `Err`, never panics. Edge-bias: trial 0 = `@[]` (totality probe via F22 empty rejection); trials 1–4 = Class 1 / 2 / 3 / mixed via `genInvalidEmailUpdateSet`; trials ≥ 5 = random mix of valid (`genEmailUpdate`) and invalid shapes. | `DefaultTrials` (500) | `genEmailUpdate`, `genInvalidEmailUpdateSet` |
| C | `NonEmptyEmailImportMap` duplicate-key invariant — for inputs with ≥ 1 duplicated `CreationId`, the constructor accumulates ≥ 1 violation. Edge-bias: trials 0..3 → generator trials 1, 2, 3, 5 (early-bound, late-bound, three-occurrence, cluster); trials ≥ 4 → random. The all-unique case is vacuously skipped. | `DefaultTrials` (500) | `genNonEmptyEmailImportMap` |
| D | RFC 6901 JSON Pointer escape bijectivity — for distinct keywords `k1, k2`, `jsonPointerEscape(k1) ≠ jsonPointerEscape(k2)`. Mandatory edge-bias: trial 0 = pair `("a/b", "a~1b")`; trial 1 = `("~", "~0")`; trial 2 = `("/", "~1")`. These three pairs are the documented collision adversaries against a swapped-replace-order regression. | `DefaultTrials` (500) | `genKeywordEscapeAdversarialPair` |
| E | `toJson(EmailUpdateSet)` shape post-condition — for every valid `EmailUpdateSet`, the emitted `JsonNode` is a `JObject` whose key count equals the input update count (transitively pinning `initEmailUpdateSet`'s Class 1 rejection through serde) and every (key, value) pair conforms to RFC 8620 §5.3 (`"keywords"` / `"mailboxIds"` carry `JObject`; `"keywords/<…>"` / `"mailboxIds/<…>"` carry `JBool` or `JNull`). | `DefaultTrials` (500) | `genEmailUpdateSet` |
| F | `moveToMailbox(id) ≡ setMailboxIds(parseNonEmptyMailboxIdSet(@[id]).get())` quantified over the full `Id` charset `[A-Za-z0-9_-]`. Both produce `kind == euSetMailboxIds`; equivalence then reduces to the borrowed `==` on `NonEmptyMailboxIdSet`. | `QuickTrials` (200) | `genValidIdStrict` |

Property D drives through the public `jsonPointerEscape*` exported
from `src/jmap_client/serde.nim` — the helper is a general infrastructure
primitive, not a mail-specific internal.

`jsonPointerEscape` is also reachable indirectly through every
`toJson(EmailUpdate)` keyword arm. The escape lives in `serde.nim`
because the same RFC 6901 contract applies to any future JSON
Pointer-keyed serialisation.

#### 8.2.2. `tests/compile/tcompile_mail_f_public_surface.nim`

Compile-only smoke test. A single top-level `import jmap_client`
plus a `static:` block of `declared(<symbol>)` assertions covering
every Part F public symbol: 18 types (`EmailUpdate`,
`EmailUpdateVariantKind`, `EmailUpdateSet`, `EmailCreatedItem`,
`SetResponse`, `CopyResponse`, `EmailImportResponse`, `EmailCopyItem`,
`EmailImportItem`, `NonEmptyEmailImportMap`, `MailboxUpdate`,
`MailboxUpdateVariantKind`, `MailboxUpdateSet`, `VacationResponseUpdate`,
`VacationResponseUpdateVariantKind`, `VacationResponseUpdateSet`,
`EmailCopyHandles`, `EmailCopyResults`); the six protocol-primitive
Email update ctors plus the five domain-named convenience ctors; six
set / map ctors (`initEmailUpdateSet`, `initEmailCopyItem`,
`initEmailImportItem`, `initNonEmptyEmailImportMap`,
`initMailboxUpdateSet`, `initVacationResponseUpdateSet`); the five
Mailbox update ctors and six VacationResponse update ctors; five
builder / dispatch procs (`addEmailSet`, `addEmailCopy`,
`addEmailCopyAndDestroy`, `addEmailImport`, `getBoth`); the
`mnEmailImport` method-name enum variant; the `importMethodName`
entity resolver; the `/set` widening symbols (`NonEmptyEmailUpdates`,
`NonEmptyMailboxUpdates`, `parseNonEmptyEmailUpdates`,
`parseNonEmptyMailboxUpdates`, `createType`, `updateType`,
`setResponseType`, `registerSettableEntity`, `addSet`); the
`/changes` widening symbols (`changesResponseType`,
`MailboxChangesResponse`); the `/copy` widening symbols
(`copyItemType`, `copyResponseType`); and the
`EmailBodyFetchOptions.toExtras` resolver. A trailing Identity
`/set` widening section covers the Part E Identity update surface
(`IdentityUpdate`, `IdentityUpdateVariantKind`, `IdentityUpdateSet`,
`NonEmptyIdentityUpdates`, `initIdentityUpdateSet`,
`parseNonEmptyIdentityUpdates`, `addIdentityGet`,
`addIdentityChanges`, `addIdentitySet`, `setReplyTo`,
`setTextSignature`, `setHtmlSignature`) — co-located here because
Identity rides the same widening pattern Part F establishes, so the
re-export invariant is identical.

A single runtime-scope `doAssert $mnEmailImport == "Email/import"`
pins the imported module against Nim's `UnusedImport` check.

**Why `declared()` and not `compiles()`.** `declared()` sidesteps
overload-resolution ambiguity on generically-named constructors
(`setName`, `setRole`, `setSubject`, …) that a naïve
`compiles(let x: EmailUpdate = setName("x"))` probe would snag on.
`declared()` asks only "is this identifier visible at this site?",
which is exactly the re-export invariant under test.

**Symbols deliberately not asserted:** `EmailSetResponse` /
`EmailCopyResponse` / `UpdatedEntry` / `UpdatedEntryKind` are not
declared types — `Email/set` and `Email/copy` route through the
generic `SetResponse[EmailCreatedItem]` and
`CopyResponse[EmailCreatedItem]` instantiations from
`methods.nim`. Variant-kind exhaustiveness is witnessed by the
production `case` sites (`shape`, `classify`, `toValidationError` in
`email_update.nim`; the per-update `toJson` arms in
`serde_email_update.nim`, `serde_mailbox.nim`, `serde_vacation.nim`)
on every build, so a dedicated probe would add no coverage the
production code does not already provide.

#### 8.2.3. `tests/stress/tadversarial_mail_f.nim`

Eight adversarial / stress groups (`joinable: false` so wall-clock
tests run in isolation):

**Block 1 — Response-decode adversarial** (per the §8.7 matrix). Three
sub-groups: `emailSetResponseAdversarialGroup`,
`emailCopyResponseAdversarialGroup`,
`emailImportResponseAdversarialGroup`. The lenient/strict split
follows a single principle: strict where a typed return forces parsing,
lenient where the return is a passthrough.

- Top-level merge maps (`mergeCreatedResults` /
  `mergeUpdateResults` / `mergeDestroyResults`) silently drop
  wrong-kind values — Postel on receive yields Ok with an empty
  merged table.
- Inner success-rail values whose return type is `Opt[JsonNode]`
  (`updateResults`) are lenient; the raw node passes through verbatim
  as `ok(Opt.some(v))` regardless of JSON kind. RFC 8620 §5.3
  specifies `PatchObject|null` for this slot, but the library defers
  the structural check to callers who know their entity.
- Inner error-rail values are strict — `SetError.fromJson` must
  produce a typed sum, so non-object / missing-`type` entries
  propagate `Err` via `?`.
- Inner success-rail values where a typed `T` is produced
  (`created` → `EmailCreatedItem`) are strict — `T.fromJson`
  cannot invent a typed record from a `JString`.
- `destroyed` element strictness comes from `parseIdFromServer`'s
  non-empty / no-control-character invariants.
- `accountId: null` and `accountId: true` are required-field
  type errors — `fromJson` returns `Err`.
- `oldState`, `newState`: K0 lenient parsers — wrong type, null, or
  invalid content all yield `Opt.none` rather than `Err`. Mirrors
  Stalwart 0.15.5's empirical omission of `newState` on failure-only
  responses.

**Block 2 — `SetError.extras` integration via `createResults`** (§7.1).
One outer `setErrorExtrasIntegrationGroup` block containing three named
inner blocks, one per Part F response type
(`emailSetExtrasReachableFromCreateResults`,
`emailCopyExtrasReachableFromCreateResults`,
`emailImportExtrasReachableFromCreateResults`). Each fires five
adversarial rows: unknown-key preservation alongside known keys, very-
long string field reached without panic, boundary numeric value
(`2^53−1`) admitted through, duplicate array entries preserved (std/
json silent-accept), and lossless `rawType` even when `errorType`
falls back to `setUnknown`.

**Block 3 — Conflict-algebra corner cases**
(`conflictAlgebraCornerCasesGroup`):

- `class3PayloadIrrelevantEmptySetKeywords` — empty `setKeywords` +
  sub-path `addKeyword` on `keywords` parent → Class 3.
- `class3PayloadIrrelevantNonEmptySetKeywords` — non-empty
  `setKeywords` + sub-path → still Class 3; payload doesn't enter
  the detection algebra.
- `class3MailboxSubpathWithFullReplace` — same shape on
  `mailboxIds` parent.
- `class2KeywordsIANAEnumerated` — fold Class 2 over the five IANA
  keywords (`kwSeen, kwFlagged, kwDraft, kwAnswered, kwForwarded`)
  plus two pointer-escape adversarial custom keywords (`a/b`,
  `a~b`).

**Block 4 — `getBoth(EmailCopyHandles)` adversarial**
(`getBothAdversarialGroup`):

- `getBothImplicitDestroyMethodCallIdMismatch` — destroy
  invocation present at a different call-id; `NameBoundHandle`
  filter rejects, surfaces synthetic `serverFail`.
- `getBothImplicitDestroyMethodError` — pins a known design
  limitation: the `NameBoundHandle` for the implicit destroy
  filters by method-name `Email/set`, but a server `error`
  invocation has wire name literally `"error"`. The error
  invocation is therefore unreachable through the destroy handle's
  dispatch, and `extractInvocationByName` surfaces a synthetic
  `serverFail / no Email/set response` instead of the typed
  destroy-side error. Destroy-side server errors are OPAQUE under
  the current `getBoth` semantics.
- `getBothCopyMethodError` — symmetric half: when the COPY
  invocation is `error`, `ResponseHandle` dispatch
  (`extractInvocation`, no name filter) parses the `MethodError`
  payload and surfaces it on the `Result` rail with the server-
  supplied `errorType` preserved.

**Block 5 — Cross-response coherence** (`crossResponseCoherenceGroup`).
The library deliberately does not enforce server-side invariants —
detection is the caller's responsibility. These tests pin that hands-
off stance:

- `coherenceOldStateNewStateEqual` — `oldState == newState` while
  `created` is non-empty is admissible.
- `coherenceOldStateNewStateNullPair` — `oldState` absent or null
  while `newState` is set is admissible (RFC 8620 §5.5).
- `coherenceAccountIdMismatchAcrossInvocations` — two invocations
  in one envelope carrying divergent `accountId` values are
  admissible at the envelope level; the test extracts both arguments
  and asserts the divergence is preserved for caller-side detection.
- `coherenceUpdatedSameKeyTwice` — `std/json parseJson` silently
  accepts duplicate object keys and keeps the last; the second
  `"e1": {}` wins over the first `"e1": null`, so the decoded entry
  is `ok(Opt.some(JObject))`.
- `coherenceCreatedAndNotCreatedShareKey` — same `CreationId` in
  both `created` and `notCreated`. `mergeCreatedResults` processes
  `created` first, then `notCreated` overwrites — `notCreated`
  wins deterministically.

**Block 6 — JSON-structural attack surface**
(`jsonStructuralAttackGroup`):

- `structuralBomPrefix` — UTF-8 BOM prefix; `parseJson` either
  tolerates as whitespace (decode succeeds) or rejects with
  `JsonParsingError`. Either branch is acceptable as a
  behavioural pin — the input must survive or reject
  deterministically, not silently corrupt.
- `structuralNanInfinity` — `NaN` / `Infinity` are JavaScript
  extensions; `parseJson` raises `JsonParsingError`.
- `structuralDuplicateKeysInObject` — `std/json` silently keeps
  the LAST duplicate key. Pin so a future parser change breaks
  this test and prompts deliberate handling.
- `structuralDeepNesting` — 500-level nested `JObject` under an
  unknown top-level key; Postel ignores it without stack overflow.
- `structuralLargeStringSize` — 1 MB id in `destroyed`; rejected
  by `parseIdFromServer`'s 255-octet cap.
- `structuralEmptyKey` — empty `CreationId` rejected by
  `parseCreationId`'s non-empty constraint.
- `structuralUnicodeNoncharacters` — `U+FFFE` byte sequence
  through `parseKeyword`; total assertion (`r.isOk or r.isErr`)
  pins that the parser does not panic on the byte sequence
  regardless of which charset branch the impl currently takes.

**Block 7 — Cast-bypass negative pins** (`castBypassGroup`).
`EmailUpdateSet` is `distinct seq[EmailUpdate]`. Callers can bypass
the smart constructor via `cast[EmailUpdateSet](raw)`; F1 §3.2.4
deliberately refuses to add runtime validation on `toJson` to avoid
penalising the well-typed construction path. These tests document
the silent acceptance of cast-constructed malformed sets — they
are negative pins, not contracts.

- `castBypassDocumentsNoPostHocValidation` — Class 1 violation
  (two identical `addKeyword` updates) emitted without complaint;
  no runtime validation fires.
- `castBypassEmptyAccepted` — empty `seq` accepted; `toJson`
  emits `{}`.

**Block 8 — Scale invariants** (`scaleInvariantsGroup`):

- `emailUpdateSet10kClass1Anchored` — 10 001 `addKeyword(k)`
  entries (entry 0 is the anchor, 1..10 000 each conflict with 0)
  → exactly 10 000 `ValidationError`s; wall-clock ≤ 0.5 s pins
  `O(n)` (an `O(n²)` algorithm would blow this tenfold).
- `emailUpdateSet10kClass1NoAnchor` — 10 000 identical entries.
  Detection compares each later entry against the FIRST
  occurrence — NOT `C(10 000, 2)`. So 9 999 conflicts accumulate.
- `emailUpdateSetThreeClassesStaggered` — 1 000 entries, three
  conflicts injected at positions 0/1, 499/500, 998/999 → exactly
  three errors, one per class.
- `emailUpdateSetLatePositionConflict` — 1 000 entries with
  conflict only at position 998/999; pins the single-pass
  algorithm doesn't bail after a clean prefix.
- `emailUpdateSet100kWallClock` — 100 000 unique entries → `Ok`;
  wall-clock ≤ 5 s pins linear scaling. Excluded from default
  `just test` via `tests/testament_skip.txt`.
- `nonEmptyImportMap10kWithDupAtEnd` — 10 000 entries with
  duplicate at position 9 999 → exactly one violation.
- `nonEmptyImportMapEmptyAndDupSeparately` — empty and duplicate
  invariants exercised in independent passes (they cannot co-occur
  in the same `openArray`).
- `getBothCopyCreateResultsEmpty` — both invocations present with
  empty `createResults`; `getBoth` returns `Ok(EmailCopyResults)`
  with both fields populated.

**Cross-process determinism.** `EmailUpdateSet`'s
`distinct seq[EmailUpdate]` design (rather than `Table`) makes
`toJson(EmailUpdateSet)` byte-deterministic across processes — no
hash-seed nondeterminism. Property group E (§8.2.1) implicitly
verifies this; an explicit cross-process probe is unnecessary because
the type design eliminates the failure mode. If a future change
moved `EmailUpdateSet` to `Table`, that probe would have to be
added.

### 8.3. Per-concept test files

**Error-rail shape.** `ValidationError` has exactly three fields:
`typeName: string`, `message: string`, `value: string`. Tests
discriminate via the `message` literal string. The authoritative
messages, sourced from
`src/jmap_client/mail/email_update.nim`,
`src/jmap_client/mail/email.nim`,
`src/jmap_client/mail/mailbox.nim`, and
`src/jmap_client/mail/vacation.nim`:

| Type | Invariant | `message` | `value` |
|------|-----------|-----------|---------|
| `EmailUpdateSet` | Empty input | `"must contain at least one update"` | `""` |
| `EmailUpdateSet` | Class 1 (duplicate target path) | `"duplicate target path"` | target path, e.g. `"keywords/$seen"` |
| `EmailUpdateSet` | Class 2 (opposite ops on same sub-path) | `"opposite operations on same sub-path"` | sub-path |
| `EmailUpdateSet` | Class 3 (sub-path + full-replace on same parent) | `"sub-path operation alongside full-replace on same parent"` | parent property, e.g. `"keywords"` |
| `MailboxUpdateSet` | Empty | `"must contain at least one update"` | `""` |
| `MailboxUpdateSet` | Duplicate target property | `"duplicate target property"` | symbolic kind, e.g. `"muSetName"` |
| `VacationResponseUpdateSet` | Empty | `"must contain at least one update"` | `""` |
| `VacationResponseUpdateSet` | Duplicate target property | `"duplicate target property"` | symbolic kind, e.g. `"vruSetIsEnabled"` |
| `NonEmptyEmailImportMap` | Empty | `"must contain at least one entry"` | `""` |
| `NonEmptyEmailImportMap` | Duplicate `CreationId` | `"duplicate CreationId"` | duplicated CreationId text, e.g. `"c1"` |
| `NonEmptyMailboxUpdates` | Empty | `"must contain at least one entry"` | `""` |
| `NonEmptyMailboxUpdates` | Duplicate Id | `"duplicate mailbox id"` | duplicated Id text |
| `NonEmptyEmailUpdates` | Empty | `"must contain at least one entry"` | `""` |
| `NonEmptyEmailUpdates` | Duplicate Id | `"duplicate email id"` | duplicated Id text |

**Uniqueness-collapsing contract.** Five of the six set-style smart
constructors use `validateUniqueByIt`
(`src/jmap_client/validation.nim`), which reports each repeated key
**exactly once regardless of occurrence count**. Three duplicates of
the same key yield one error, not two. This applies to
`MailboxUpdateSet`, `VacationResponseUpdateSet`,
`NonEmptyEmailImportMap`, `NonEmptyMailboxUpdates`, and
`NonEmptyEmailUpdates`. `EmailUpdateSet` uses a different path-based
detector (`samePathConflicts` in `email_update.nim`) that emits one
conflict per same-path occurrence AFTER the first; N occurrences at
a single target path yield N − 1 Class 1 conflicts. Tests calibrate
their exact-count assertions accordingly (see §8.8).

#### Unit — `tests/unit/mail/`

| File | Concerns |
|------|----------|
| `temail.nim` — section C `initNonEmptyEmailImportMap` blocks | Five blocks: `initNonEmptyEmailImportMapEmpty` (empty → one `"must contain at least one entry"` error); `...SingleValid`; `...TwoSameCreationId` (duplicate → one error with `value == "c1"`); `...ThreeSameCreationId` (uniqueness-collapsing at N = 3 → one error); `...TwoDistinctRepeated` (four entries forming two distinct duplicate pairs → exactly two errors, set-membership-verified so the test does not depend on error ordering). Plus the `isLeafTrue` / `isLeafFalseForMultipart` blocks pinning the body-part predicate. |
| `temail_update.nim` | Section A — six per-primitive constructor blocks (`addKeywordConstructsCorrectKind` … `setMailboxIdsConstructsCorrectKind`) each asserting `u.kind` plus the variant-payload field. Section B — five convenience-equivalence blocks (`markReadEqualsAddKeywordSeen`, `markUnreadEqualsRemoveKeywordSeen`, `markFlaggedEqualsAddKeywordFlagged`, `markUnflaggedEqualsRemoveKeywordFlagged`, `moveToMailboxEqualsSetMailboxIdsSingleton`). Section C — two negative-discrimination blocks (`moveToMailboxDistinctIds`, `addKeywordDistinctKeywords`) verifying distinct payloads stay distinct. Comparisons use field-wise `assertEq` over `kind` plus a payload field; auto-generated case-object `==` is not available (parallel `fields` iterator restriction). |
| `temail_update_set.nim` | Section A — `emailUpdateSetEmpty` (F22). Section B — six Class 1 blocks (`class1TwoAddKeyword` … `class1TwoSetMailboxIds`) covering each shape in §8.4.1. Section C — two Class 2 blocks (`class2KeywordOpposite`, `class2MailboxOpposite`). Section D — four Class 3 blocks (`class3AddKeywordSetKeywords`, `class3RemoveKeywordSetKeywords`, `class3AddToMailboxSetMailboxIds`, `class3RemoveFromMailboxSetMailboxIds`). Section E — `class1And2Overlap` pinning the Class 2-wins policy from §8.4.2. Section F — four `assertOk` blocks for the §8.4.4 independent shapes. Section G — `accumulateMixedClasses` (one of each class on independent parents → 3 errors); `accumulateClass3TwoDistinctParents` (two parent paths → exactly 2 Class 3 emissions). Section F-bis (re-used letter) — two `parseNonEmptyEmailUpdates` blocks: empty rejection and duplicate-Id rejection. |
| `temail_copy_item.nim` | Section A — type-level rejection: `copyItemTypeRejectsEmptyMailboxIdSet` (empty `MailboxIdSet` literal fails the distinct-type gate); `copyItemTypeRejectsNonEmptyMailboxIdSetWrongDistinct` (populated `MailboxIdSet` is the wrong distinct — the override slot demands `NonEmptyMailboxIdSet`). Section B — structural readback: `copyItemIdOnlyRoundTrip` (assert every override is `Opt.none`) and `copyItemAllOverridesPopulated` (every override populated; readback through `assertEq` / `assertSomeEq`). |
| `temail_import_item.nim` | Section A — `importItemRejectsOptNoneMailboxIds` (mailboxIds is non-Opt `NonEmptyMailboxIdSet`; passing an `Opt` wrapper is a compile error). Section B — `importItemMinimalConstruction`. Section C — `importItemKeywordsThreeStates` exercising `Opt.none` / `Opt.some(empty)` / `Opt.some(non-empty)` at the value layer; serde collapse of the first two is pinned in `tserde_email_import.nim`. |
| `tmailbox.nim` — sections A–F | Pre-existing parts A (`parseMailboxRole`), B (`MailboxIdSet`), C (`MailboxCreate`), D (`NonEmptyMailboxIdSet`). Part F additions: section E `initMailboxUpdateSet` — five blocks (`initMailboxUpdateSetEmpty`, `...SingleValid`, `...TwoSameKind` with `value == "muSetName"`, `...ThreeSameKind` (uniqueness collapse), `...TwoDistinctRepeated` (set-membership-verified two errors). Section F per-variant setter shape — six blocks covering the five `MailboxUpdateVariantKind` variants plus the `Opt[Id]` Some/None split for `setParentId`. Section F-bis — two `parseNonEmptyMailboxUpdates` blocks: empty rejection and duplicate-Id rejection. |
| `tvacation.nim` | Section A — three setter shape blocks sampling the three payload axes (`bool`, `Opt[UTCDate]`, `Opt[string]`): `setIsEnabledConstructsCorrectKind`, `setFromDateConstructsCorrectKind`, `setSubjectClearsWhenNone`. Section B — five `initVacationResponseUpdateSet` blocks (`...Empty`, `...SingleValid`, `...TwoSameKind` with `value == "vruSetIsEnabled"`, `...ThreeSameKind`, `...TwoDistinctRepeated`). Section C — three remaining-setter shape blocks (`setToDateConstructsCorrectKind`, `setTextBodyClearsWhenNone`, `setHtmlBodyConstructsCorrectKind`). |
| `tkeyword.nim` — section A appendix | Three blocks pinning F1 §3.2.5's spec-faithful Postel commitment (`parseKeyword` admits `~` and `/` per RFC 8621 §4.1.1's keyword charset): `keywordWithTildeAccepted`, `keywordWithSlashAccepted`, `keywordWithBothAccepted`. Required upstream of the §8.5 escape-boundary serde tests. |

#### Serde — `tests/serde/mail/`

| File | Concerns |
|------|----------|
| `tserde_email_update.nim` | Section A — six `toJson(EmailUpdate)` per-variant tuple blocks (`addKeywordEmitsTuple` … `setMailboxIdsEmitsTuple`). `toJson(EmailUpdate)` returns `(string, JsonNode)`; tests destructure and assert each component. Section B — `emailUpdateSetFlattensTuple` (flatten to `JObject` with one key per validated entry). Section C — `moveToMailboxWireIsSetMailboxIds` (positive: `key == "mailboxIds"`, value object contains `$id` key with `JBool(true)`); `moveToMailboxNotAddToMailbox` (negative: key ≠ `"mailboxIds/" & $id`). Section D — fifteen RFC 6901 escape-boundary blocks per the §8.5 matrix, each driving through `makeAddKeyword(parseKeyword(raw).get()).toJson()` so the public `jsonPointerEscape` is exercised via the wire contract. |
| `tserde_email_copy.nim` | Section A — `emailCopyItemMinimalEmitsIdOnly` (one wire key); `emailCopyItemFullOverrideEmitsThreeKeys` (all overrides populated → four wire keys including `id`); `emailCopyItemOptNoneOmitsKeys` (Opt.none overrides omit, never emit `null` — RFC 8621 §4.7 distinguishes "preserve source" from "set to null"). Section B — `CopyResponse[EmailCreatedItem].fromJson` three shapes: `created`-only, `notCreated`-only (with merged `createResults` populating an `Err(SetError)` entry), combined. Section C — `emailCopyResponseRequiresFromAccountId` (`fromAccountId` mandatory; absent → Err). Section D — `emailCopyResponseHasNoUpdatedField` (`assertNotCompiles` block pinning that `CopyResponse[EmailCreatedItem]` has no `updated`/`destroyed` field — those belong to `/set` only). |
| `tserde_email_import.nim` | Section A — six `toJson(EmailImportItem)` blocks: `importItemBlobIdAlwaysEmitted`, `importItemMailboxIdsAlwaysEmitted`, `importItemKeywordsOmittedWhenNone`, `importItemKeywordsEmittedWhenSome` (uses `Opt.some(non-empty)`), `importItemReceivedAtOmittedWhenNone`, `importItemReceivedAtEmittedWhenSome`. The `Opt.some(empty)` keyword case is exercised at the value layer in `temail_import_item.nim::importItemKeywordsThreeStates`; the wire-side collapse to "omit" lives in `serde_email.nim`'s `for ks in item.keywords: if ks.len > 0: ...` guard and is not pinned by a dedicated serde block. Section B — `nonEmptyEmailImportMapEmitsCreationIdKeys`. Section C — five `EmailImportResponse.fromJson` blocks: `created` as object / null (RFC §4.8 — null treated as absent) / empty object; malformed (`accountId: nil`) surfaces Err; missing `newState` is lenient (Stalwart 0.15.5 empirically omits `newState` on failure-only responses). |
| `tserde_email_set_response.nim` | Section A — `setResponseEmailEnvelopeShape` (the merged six-field record: `accountId`, `oldState`, `newState`, `createResults`, `updateResults`, `destroyResults`). `setResponseEmailMergeCreateResults` pins the create-side merge. Section B — `EmailCreatedItem.fromJson`: `emailCreatedItemMinimalConstruction` and `emailCreatedItemMissingSizeRejected` (per RFC 8621 §§4.6/4.7/4.8 the server MUST emit all four fields; absence is malformed and rejected with `svkMissingField`). Section C — `updated` three-state inside the merged map: top-level absent → empty `updateResults`; `updated: {}` → empty (Decision 3.9B collapses absent and empty-object at the map level, matching RFC 8620 §5.3 semantics); inner `null` vs `{}` distinction preserved as `ok(Opt.none(JsonNode))` vs `ok(Opt.some(emptyJObject))`. Section D — `destroyed` three-state: absent / empty array / two-element array. Section E — `setResponseEmailRoundTrip`: construct, `toJson`, `fromJson`, assert field-wise equality of the reconstructed record. |
| `tserde_mailbox.nim` — section F appendix | Pre-existing sections cover `MailboxRole`, `MailboxIdSet`, `Mailbox`, `MailboxCreate`. Part F additions: section F per-variant `MailboxUpdate` serde — `setNameTuple` (`("name", %"Renamed")`); `setParentIdNoneEmitsJsonNull` (reparent-to-top wire semantic); `setParentIdSomeEmitsString`; `setRoleNoneEmitsJsonNull` (clear-role wire semantic); `setRoleSomeEmitsString`; `mailboxUpdateSetFlattensTuple`; `mailboxUpdateSetRoundTripsWireOrder` (re-stringify / re-parse round-trip guards against accidental key-order mangling). |
| `tserde_vacation.nim` — section F appendix | Pre-existing sections cover `VacationResponse` `fromJson` / round-trip / type constraints / `toJson`. Part F additions: section F per-variant `VacationResponseUpdate` serde — eleven blocks covering all six variants × {None, Some} payload pairs (`setIsEnabledTuple`, `vruSetFromDate{None,Some}EmitsString`, `vruSetToDate{None,Some}`, `vruSetSubject{None,Some}`, `vruSetTextBody{None,Some}`, `vruSetHtmlBody{None,Some}`); plus `vacationResponseUpdateSetFlattensTuple` pinning the Opt.none → wire null contract. |

#### Protocol — `tests/protocol/`

| File | Concerns |
|------|----------|
| `tmail_builders.nim` — sections J–N | Section J `addEmailSet` — five blocks: `addEmailSetFullInvocation` with `create`/`update`/`destroy`/`ifInState` populated; `addEmailSetMinimalAccountIdOnly` (no operation keys when all are `Opt.none`); `addEmailSetIfInStateEmitted` / `addEmailSetIfInStateOmittedWhenNone` (positive/negative pair); `addEmailSetTypedUpdate` constructs the typed update via `parseNonEmptyEmailUpdates(@[(id, initEmailUpdateSet(@[markRead()]).get())]).get()` and asserts `args.update.<id>.{"keywords/$seen"}` on the wire — pinning the typed algebra threading through `toJson(NonEmptyEmailUpdates)` at the builder boundary. Section K `addEmailCopy` (simple) — `addEmailCopyPhantomType` and `addEmailCopyIfInStateEmittedWithCopySemantics`. Section L `addEmailCopyAndDestroy` — four blocks (`addEmailCopyAndDestroyEmitsTrue` asserts `onSuccessDestroyOriginal: true`, `handles.implicit.methodName == mnEmailSet`, and `handles.implicit.callId == handles.primary.callId()`; `...DestroyFromIfInStateSome` / `...None`; `...AllStateParamsSome` (all three of `ifFromInState`, `ifInState`, `destroyFromIfInState` populated). Section M `getBoth` dispatch — `getBothCopyAndDestroyHappyPath`; `getBothShortCircuitOnCopyError` (table-driven over the seven applicable `MethodErrorType` variants via `for variant in MethodErrorType:` filtered by a `const applicable = {...}` set); `getBothShortCircuitOnDestroyMissing` (no Email/set invocation at the shared cid → `serverFail` with description `"no Email/set response for call ID <cid>"`); `getBothShortCircuitOnDestroyError` (pins the destroy-name-filter design limitation: server `error` invocations have wire name `"error"`, not `"Email/set"`, so they are unreachable through the destroy handle — see §8.2.3 Block 4 for the rationale). Section N `addMailboxSet` typed-update — `addMailboxSetTypedUpdate` (typed `MailboxUpdateSet` flowing through `parseNonEmptyMailboxUpdates` to `toJson(NonEmptyMailboxUpdates)`); `addMailboxSetEmptyUpdateSetRejectedAtConstruction` (empty input rejected at the `initMailboxUpdateSet` level; the builder is never invoked with an empty set). The pre-existing `mailboxChangesResponse*` and `addMailboxQuery*` blocks live in sections A–D and are out of Part F scope. |
| `tmail_methods.nim` — sections B, E | Section B `VacationResponse/set` — seven blocks (`vacationSetInvocationName`, `...Capability`, `...SingletonInUpdate`, `...OmitsCreateDestroy`, `...WithIfInState`, `...OmitsIfInStateWhenNone`, `...PatchValues`). The typed update is exercised throughout via `let minimalVacUpdate = initVacationResponseUpdateSet(@[setIsEnabled(true)]).get()` and the builder signature `addVacationResponseSet(b, accountId, update: VacationResponseUpdateSet, ifInState)`. Section E `addEmailImport` — four blocks: `addEmailImportInvocationName` (invocation name `Email/import`, capability `urn:ietf:params:jmap:mail`, phantom-typed handle `ResponseHandle[EmailImportResponse]`); `addEmailImportEmailsPassthrough` (typed `NonEmptyEmailImportMap` flattens to wire via `toJson(NonEmptyEmailImportMap)` at the builder boundary); `addEmailImportIfInStateSomePassthrough`; `addEmailImportIfInStateNoneOmitted` (omit, never emit JSON null). |
| `tmail_method_errors.nim` | Section A — seven method-level error blocks per F1 §7.4 (`emailSetRequestTooLarge`, `emailSetStateMismatch`, `emailCopyFromAccountNotFound`, `emailCopyFromAccountNotSupportedByMethod`, `emailCopyStateMismatch`, `emailImportStateMismatch`, `emailImportRequestTooLarge`). Section B — generic `SetError` applicability matrix per F1 §7.2: forbidden (5 cells), overQuota (4), tooLarge (4), rateLimit (3), notFound (3), invalidPatch (1), willDestroy (1), invalidProperties (4). Each `✓` cell decodes wire JSON with one typed `SetError` in the appropriate slot (`notCreated`/`notUpdated`/`notDestroyed`) and asserts the typed `errorType` discriminator. Section C — three `singleton` negative cells (Postel parses but no Part F builder emits): `emailSetSingletonParsesButNotEmittable`, `emailCopySingletonParsesButNotEmittable`, `emailImportSingletonParsesButNotEmittable`. Section D — `setErrorApplicabilityExhaustiveFold` folds over every `SetErrorType` variant via `for variant in SetErrorType:`. Adding a variant forces a compile error here until coverage is added to A/B/C. Sections E/F cover `EmailSubmissionSetResponse` per Part G2 (out of Part F scope but co-located). |

The `tmail_methods.nim` `B`-block typed-update threading and the
`tmail_builders.nim` `J.5` / `N.1` typed-update threading collectively
pin that `VacationResponseUpdateSet`, `NonEmptyEmailUpdates`, and
`NonEmptyMailboxUpdates` all flatten correctly at the builder
boundary.

### 8.4. Conflict-pair equivalence-class enumeration tables

The Class 1/2/3 unit tests in `temail_update_set.nim` enumerate the
following equivalence-class representatives. The implementation
cannot pass the tests by exercising one example per class — each
shape is named explicitly.

#### 8.4.1. Class 1 — duplicate target path (6 shapes)

| # | Variant A | Variant B | Shared target |
|---|-----------|-----------|---------------|
| 1 | `euAddKeyword(k)` | `euAddKeyword(k)` | `keywords/{k}` |
| 2 | `euRemoveKeyword(k)` | `euRemoveKeyword(k)` | `keywords/{k}` |
| 3 | `euSetKeywords(ks1)` | `euSetKeywords(ks2)` | `keywords` |
| 4 | `euAddToMailbox(id)` | `euAddToMailbox(id)` | `mailboxIds/{id}` |
| 5 | `euRemoveFromMailbox(id)` | `euRemoveFromMailbox(id)` | `mailboxIds/{id}` |
| 6 | `euSetMailboxIds(ids1)` | `euSetMailboxIds(ids2)` | `mailboxIds` |

#### 8.4.2. Class 2 — opposite operations on same sub-path (2 shapes)

| # | Variant A | Variant B | Sub-path |
|---|-----------|-----------|----------|
| 1 | `euAddKeyword(k)` | `euRemoveKeyword(k)` | `keywords/{k}` |
| 2 | `euAddToMailbox(id)` | `euRemoveFromMailbox(id)` | `mailboxIds/{id}` |

**Overlap policy.** Both Class 2 shapes also collide on target path
(Class 1 condition). The implementation emits **Class 2 only** for
these overlap shapes. `samePathConflicts`
(`src/jmap_client/mail/email_update.nim`) branches the decision
cleanly: if the two updates at the same path have `kind == op.kind`
the emitted conflict is `ckDuplicatePath` (Class 1); if the kinds
differ, the emitted conflict is `ckOppositeOps` (Class 2). The two
paths are mutually exclusive — never both. Class 2 strictly implies
Class 1 for these shape pairs, so reporting both would produce
redundant output a consumer must deduplicate.

The `class1And2Overlap` block reads:

```nim
let seen = parseKeyword("$seen").get()
let res = initEmailUpdateSet(@[addKeyword(seen), removeKeyword(seen)])
assertErr res
assertLen res.error, 1
assertEq res.error[0].typeName, "EmailUpdateSet"
assertEq res.error[0].message, "opposite operations on same sub-path"
assertEq res.error[0].value, "keywords/$seen"
```

`ValidationError` carries no `classification` enum field;
discrimination between Class 1 / 2 / 3 is done at the wire error-
message text layer.

Choosing "emit tighter" matches the RFC 6902 JSON Patch convention
where `replace` dominates `add + remove` for the same path — the
tighter op is the canonical description.

#### 8.4.3. Class 3 — sub-path operation alongside full-replace on same parent (4 shapes)

| # | Sub-path variant | Full-replace variant | Parent |
|---|------------------|----------------------|--------|
| 1 | `euAddKeyword(k)` | `euSetKeywords(ks)` | `keywords` |
| 2 | `euRemoveKeyword(k)` | `euSetKeywords(ks)` | `keywords` |
| 3 | `euAddToMailbox(id)` | `euSetMailboxIds(ids)` | `mailboxIds` |
| 4 | `euRemoveFromMailbox(id)` | `euSetMailboxIds(ids)` | `mailboxIds` |

The Class 3 discriminator is the **target path**, not the payload.
Adversarial cases (§8.2.3 Block 3) pin both empty-`euSetKeywords`
and non-empty-`euSetKeywords` payloads as equivalent Class 3
violations.

#### 8.4.4. Independent (NOT conflicts) — 4 shapes

| # | Variant A | Variant B | Why independent |
|---|-----------|-----------|-----------------|
| 1 | `euSetKeywords(ks)` | `euSetMailboxIds(ids)` | Different parent paths; both full-replace on independent fields |
| 2 | `euAddKeyword(k1)` | `euAddKeyword(k2)` (`k1 ≠ k2`) | Different sub-paths |
| 3 | `euAddKeyword(k)` | `euAddToMailbox(id)` | Different parent paths entirely |
| 4 | `euAddToMailbox(id1)` | `euRemoveFromMailbox(id2)` (`id1 ≠ id2`) | Different sub-paths under the same parent — Class 2 only applies when the sub-path is *identical* |

These are mandatory positive `assertOk` blocks. Without them, an
over-eager Class 1 detector that hashes by parent path alone
(shape 1 / 3), a Class 1 detector that ignores the keyword
discriminator (shape 2), or a Class 2 detector that fires on
"opposite op under same parent" without checking sub-path equality
(shape 4) would pass all the negative tests (false confidence).
Shape 4 is the symmetric counterpart on the mailbox axis to shape
2 on the keyword axis — the addition closes the diagonal.

### 8.5. RFC 6901 escape-boundary test matrix

`tests/serde/mail/tserde_email_update.nim` section D drives the public
`jsonPointerEscape*` (in `src/jmap_client/serde.nim`) through the
`toJson(EmailUpdate)` keyword arms. Each block constructs an input
via `parseKeyword(raw).get()` (or `parseKeywordFromServer` for the
non-ASCII case), threads it through `makeAddKeyword(...)` and
`.toJson()`, and asserts the `(string, JsonNode)` tuple components
separately.

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
| `escEmbeddedTildeZero` | `"a~0b"` | `"keywords/a~00b"` | Input contains literal `~0` — must escape to `~00` (the `~` is escaped, the `0` passed through). Collision adversary against a decoder that round-trips to `"a\0b"`. |
| `escEmbeddedTildeOne` | `"a~1b"` | `"keywords/a~01b"` | Input contains literal `~1`; same collision-adversary class. |
| `escDoubleTilde` | `"~~"` | `"keywords/~0~0"` | Consecutive tildes — naive `for c in s` + accumulating buffer handles correctly. |
| `escDoubleSlash` | `"//"` | `"keywords/~1~1"` | Consecutive slashes; no interaction with tilde. |
| `escTrailingTilde` | `"abc~"` | `"keywords/abc~0"` | Terminal-position tilde — catches off-by-one in a length-bounded loop. |
| `escLeadingTilde` | `"~abc"` | `"keywords/~0abc"` | Leading-position tilde — catches `if i > 0` bug. |
| `escUtf8Keyword` | `"$日本語"` (via `parseKeywordFromServer`) | `"keywords/$日本語"` (verbatim UTF-8 bytes) | Non-ASCII pass-through — the escape is byte-level and affects only ASCII `~` / `/`. Pins that the escape function is UTF-8-safe. |

`jsonPointerEscape` is `s.replace("~", "~0").replace("/", "~1")`
(with `~` first by RFC 6901 §3 mandate). Property group D
(§8.2.1) quantifies the bijectivity invariant: distinct keywords escape
to distinct wire keys. The pair `("a/b", "a~1b")` is the canonical
adversarial input — under a buggy swapped-replace order they would
both produce `"a~1b"`, silently corrupting one update.

The upstream `parseKeyword` acceptance of `~` and `/` is pinned in
`tests/unit/mail/tkeyword.nim` (§8.3) — without it the escape tests
above are unreachable in practice.

### 8.6. Test infrastructure

#### 8.6.1. Factories — `tests/mfixtures.nim`

| Module section | Factories |
|----------------|-----------|
| Section A — `EmailUpdate` variants | `makeAddKeyword(k = kwSeen)`, `makeRemoveKeyword(k = kwSeen)`, `makeSetKeywords(ks = initKeywordSet([kwSeen]))`, `makeAddToMailbox(id = makeId("mbx1"))`, `makeRemoveFromMailbox(id)`, `makeSetMailboxIds(ids = makeNonEmptyMailboxIdSet())`. |
| Section A bis — convenience constructors | `makeMarkRead`, `makeMarkUnread`, `makeMarkFlagged`, `makeMarkUnflagged`, `makeMoveToMailbox(id)`. |
| Section B — update-set builders | `makeEmailUpdateSet(updates = @[makeAddKeyword()])`, `makeMailboxUpdateSet(updates = @[makeSetName()])`, `makeVacationResponseUpdateSet(updates = @[makeSetIsEnabled()])`. Each one-line wraps `init…(…).get()`. |
| Section C — `MailboxUpdate` variants | `makeSetName(name = "Inbox")`, `makeSetParentId(parentId = Opt.none(Id))`, `makeSetRole(role = Opt.none(MailboxRole))`, `makeSetSortOrder(sortOrder)`, `makeSetIsSubscribed(isSubscribed = true)`. |
| Section D — `VacationResponseUpdate` variants | `makeSetIsEnabled(isEnabled = true)`, `makeSetFromDate(fromDate = Opt.none(UTCDate))`, `makeSetToDate`, `makeSetSubject`, `makeSetTextBody`, `makeSetHtmlBody`. |
| Section E — `EmailCopyItem` | `makeEmailCopyItem(id = makeId("src1"), mailboxIds = Opt.none, …)`, `makeFullEmailCopyItem(...)` (every override populated). |
| Section F — `EmailImportItem` | `makeEmailImportItem(blobId = makeBlobId("blob1"), mailboxIds = makeNonEmptyMailboxIdSet(), …)`, `makeFullEmailImportItem`. |
| Section G — `NonEmptyEmailImportMap` | `makeNonEmptyEmailImportMap(items)` — `init…(items).get()`. |
| Section H — write responses | `makeEmailSetResponse(...)` returns `SetResponse[EmailCreatedItem]`; `makeEmailCopyResponse(...)` returns `CopyResponse[EmailCreatedItem]`; `makeEmailImportResponse(...)` returns `EmailImportResponse`. Each takes typed records (default args produce a minimal happy-path response) — not `JsonNode`. |
| Section I — `EmailCopyHandles` | `makeEmailCopyHandles(sharedCallId = makeMcid("c0"))` — both handles share one `MethodCallId` per RFC 8620 §5.4. The `implicit` field is a `NameBoundHandle[SetResponse[EmailCreatedItem]]` carrying `methodName: mnEmailSet`. |
| Section J — whole-container update wrappers | `makeNonEmptyMailboxUpdates(items: varargs[(Id, MailboxUpdateSet)])` and `makeNonEmptyEmailUpdates(items: varargs[(Id, EmailUpdateSet)])` — both `parse…(@items).get()`. |

#### 8.6.2. Equality helpers — `tests/mfixtures.nim`

Nim's compiler-derived `==` on case objects raises a "parallel
`fields` iterator does not work for case objects" error, so case
objects need explicit arm-dispatched `==`. `KeywordSet` deliberately
omits borrowed `==` (Decision B3 — read-model sets are queried, never
compared as wholes); `NonEmptyMailboxIdSet` borrows `==`.

| Helper | Use |
|--------|-----|
| `keywordSetEq(a, b)` | Casts through `HashSet[Keyword]` to dispatch via the borrowed `Keyword.==`. Required by `emailUpdateEq`. |
| `emailUpdateEq(a, b)` | Arm-dispatched: keyword arms use `Keyword.==`; `euSetKeywords` uses `keywordSetEq`; mailbox-id arms use `Id.==`; `euSetMailboxIds` uses the borrowed `NonEmptyMailboxIdSet.==`. |
| `emailUpdateSetEq(a, b)` | Manual element-wise comparison through `emailUpdateEq` over the underlying `seq[EmailUpdate]`. |
| `setErrorEq(a, b)` | Pre-existing helper covering `SetError` arm-dispatched equality (`mfixtures.nim:717`). |
| `nonEmptyMailboxIdSetEq(a, b)` | Pre-existing helper (`mfixtures.nim:1417`); cast through the underlying `HashSet[Id]`. |
| `anyEmailSubmissionEq` etc. | Part G helpers; not Part F-specific. |

`MailboxUpdate`, `VacationResponseUpdate`, `EmailCreatedItem`,
`EmailCopyItem`, `EmailImportItem`, and the response types do NOT
need custom equality helpers at the value layer — tests compare
field-wise via `assertEq` (`u.kind` plus a payload field) rather
than whole-object `==`. This avoids invoking the case-object
auto-`==` restriction in test code.

#### 8.6.3. Generators — `tests/mproperty.nim`

| Generator | Edge-bias schedule |
|-----------|-------------------|
| `genEmailUpdate(rng, trial)` | Trials 0–5 enumerate the six `EmailUpdateVariantKind` variants in declaration order. Trials 6–10 enumerate the five convenience constructors. Trial 11 = `setKeywords(initKeywordSet([]))` (empty). Trial 12 = `setKeywords(initKeywordSet(IANA-system-keyword-set))`. Trials ≥ 13 = random. |
| `genEmailUpdateSet(rng, trial)` | Trial 0 = single `addKeyword(kwSeen)`. Trial 1 = two-element disjoint set. Trials ≥ 2 = random size 1..8 with retry-on-conflict (max 16); fall back to single-element set on pathological seeds. Generates only valid (non-empty, conflict-free) sets. |
| `genInvalidEmailUpdateSet(rng, trial)` | Trial 0 = `@[]` (F22). Trial 1 = Class 1. Trial 2 = Class 2. Trial 3 = Class 3. Trial 4 = all three classes mixed. Trials ≥ 5 = random class injection. |
| `genNonEmptyEmailImportMap(rng, trial)` | Trial 0 = single entry. Trial 1 = early-bound duplicate. Trial 2 = late-bound duplicate. Trial 3 = three-occurrence duplicate. Trial 4 = empty (caller tests rejection). Trial 5 = many-position cluster. Trials ≥ 6 = random 1..8 entries, coin-flip duplicate injection. |
| `genJsonNodeAdversarial(rng, trial)` | Random pick across `JNull`, `JInt`, `JBool`, `JArray`-with-nulls, `JObject`-with-unknown-keys, empty `JObject`. No mandatory schedule. |
| `genEmailUpdateSetCastBypass(rng, trial)` | Trial 0 = `@[]` (would be rejected by `initEmailUpdateSet`). Trial 1 = Class 1 duplicate. Trial 2 = Class 2 opposite. Trial 3 = oversized 64-element seq. Trials ≥ 4 = random invalid via `genInvalidEmailUpdateSet`. Used only by `tadversarial_mail_f.nim` Block 7 — never by property groups (the property would trivially fail). |
| `genKeywordEscapeAdversarialPair(rng, trial)` | Trial 0 = `("a/b", "a~1b")` (canonical collision adversary). Trial 1 = `("~", "~0")`. Trial 2 = `("/", "~1")`. Trials ≥ 3 = random pair from the keyword charset (generators do NOT emit `~` or `/`, so random pairs exercise the harness without meaningfully probing the escape). |

Property tier definitions are in `tests/mproperty.nim`. Tier
assignments per §8.2.1: groups B/C/D/E land at `DefaultTrials` (500
trials, ~5–25 ms/trial); group F lands at `QuickTrials` (200 trials,
~25–50 ms/trial) — the predicate is cheap (two constructors + one
`==`) and divergence surfaces in the first handful of trials.

`CrossProcessTrials` (100, byte-level cross-process) is unused by
Part F. The `distinct seq[EmailUpdate]` design eliminates hash-seed
nondeterminism in `toJson(EmailUpdateSet)` — the type design rules
out the failure mode rather than mitigating it at the test level.

#### 8.6.4. Native enum iteration

Where §8.3 (`getBothShortCircuitOnCopyError`) and §8.9 (the `SetError`
applicability matrix via `setErrorApplicabilityExhaustiveFold`) fold
over every variant of an enum, the idiom is the native
`for variant in T:` loop. Two body shapes are in use, picked by
whether the enum is fully or partially in scope:

- **Inner `case`** (full-coverage exhaustiveness probe). Used by
  `setErrorApplicabilityExhaustiveFold` over `SetErrorType` and the
  symmetric submission probe. Adding a variant forces a compile error
  at the `case` until the new row is acknowledged. Precedent:
  `tests/unit/terrors.nim`.
- **`const applicable = {...}` + `notin` filter**. Used by
  `getBothShortCircuitOnCopyError` over `MethodErrorType`, where only
  the seven Email/copy-applicable variants are meaningful (RFC 8621
  §4.7); irrelevant variants are skipped via `if variant notin
  applicable: continue`.

No `forAllVariants[T]` combinator is introduced — the explicit loop
makes the variant set visible at the call site, and either body
shape preserves the "every variant accounted for" invariant (the
`case` does so by exhaustiveness; the `applicable` set does so by
review of the literal set elements alongside the test).

### 8.7. Adversarial response-decode matrix

`tests/stress/tadversarial_mail_f.nim` Block 1 pins per-field attacks
for `SetResponse[EmailCreatedItem].fromJson`,
`CopyResponse[EmailCreatedItem].fromJson`, and
`EmailImportResponse.fromJson`. Each row is one named block.

| Field | Attack variant | Outcome |
|-------|----------------|---------|
| `created` (top-level) | `JArray` instead of `JObject` | Lenient: `Ok` with empty merged `createResults` (Postel via `mergeCreatedResults`) |
| `created` (top-level) | `JNull` (Email/import wire shape per RFC §4.8) | `Ok` with empty `createResults` |
| `created` (top-level) | `JString` | Lenient: `Ok` with empty merged `createResults` |
| `created` entry key | `"#badkey"` (invalid `CreationId`) | `Err` (parser rejects invalid creation-id) |
| `created` entry key | `""` (empty string) | `Err` |
| `created` entry value | `JString` | `Err` (`EmailCreatedItem.fromJson` rejects non-`JObject`) |
| `created` entry value | Missing `"size"` | `Err` (svkMissingField) |
| `created` entry value | `"size": "string"` | `Err` (type coercion refused) |
| `created` entry value | `"id": 42` | `Err` |
| `created` entry value | Extra unknown fields | `Ok` (Postel; unknown nested fields ignored) |
| `updated` entry value | `JString` | Passthrough `Ok` with `updateResults[id].get().get().kind == JString` |
| `updated` entry value | `JNumber` | Passthrough `Ok` with `kind == JInt` |
| `updated` entry value | `JArray` | Passthrough `Ok` with `kind == JArray` |
| `updated` entry value | `JBool` | Passthrough `Ok` with `kind == JBool` |
| `updated` entry value | `JNull` | `Ok` with `updateResults[id].get().isNone` |
| `updated` entry value | `JObject` (empty) | `Ok` with `updateResults[id].get().get().kind == JObject` and `len == 0` |
| `updated` round-trip | round-trip of null vs `{}` | Wire form preserved through `Opt.none → JNull`, `Opt.some(n) → n` |
| `updated` map key | `"bad"` (control character) | `Err` (parseIdFromServer rejects control chars) |
| `updated` (top-level) | absent | `Ok` with empty `updateResults` |
| `updated` (top-level) | `null` | `Ok` with empty `updateResults` |
| `updated` (top-level) | `{}` | `Ok` with empty `updateResults` (Decision 3.9B collapses absent / null / empty-object at the merged-map level) |
| `updated` (top-level) | `JArray` | Lenient: `Ok` with empty `updateResults` |
| `notUpdated` (top-level) | `JArray` | Lenient: `Ok` with empty `updateResults` |
| `notUpdated` entry key | `""` (empty string) | `Err` |
| `notUpdated` and `notDestroyed` | same Id in both | Both surface separately on the Err rail of `updateResults[id]` and `destroyResults[id]`; no cross-map dedup |
| `destroyed` | `JNull` | Lenient: `Ok` with empty `destroyResults` |
| `destroyed` | absent | `Ok` with empty `destroyResults` |
| `destroyed` | `[]` | `Ok` with empty `destroyResults` |
| `destroyed` | `["id1", "id2"]` | `Ok` with two `destroyResults` Ok entries |
| `destroyed` | `JObject` (wrong kind) | Lenient: `Ok` with empty `destroyResults` |
| `oldState` | `JNull` | `Ok` with `oldState.isNone` |
| `oldState` | wrong type (`JInt`) | K0-lenient: `Ok` with `oldState.isNone` |
| `accountId` | `JNull` | `Err` |
| `accountId` | wrong type (`JBool`) | `Err` |
| `newState` | `JInt` | K0-lenient: `Ok` with `newState.isNone` |
| `notCreated` (top-level) | `JArray` | Lenient: `Ok` with empty `createResults` |
| `notCreated` (top-level) | `JNull` | `Ok` with empty `createResults` |
| `notCreated` entry key | `"#bad"` | `Err` |
| `notCreated` entry value | Missing `type` | `Err` (`SetError.fromJson` requires the `type` field) |
| `notCreated` entry value | `type: "forbidden"`, no `description` | `Ok` (description is optional) |
| `notCreated` entry value | `type: "customServerExtension"` | `Ok` with `errorType == setUnknown`, `rawType == "customServerExtension"` (lossless round-trip) |
| `notCreated` entry value | `type: "invalidProperties"`, `properties: 42` | `Ok` with `errorType == setUnknown` and `rawType == "invalidProperties"` (defensive `setError` map downgrades on payload parse failure; lossless `rawType`) |
| `notCreated` entry value | `type: "invalidProperties"`, `properties: []` | `Ok` with `errorType == setInvalidProperties` (empty array valid) |
| `notCreated` entry value | description with embedded NUL | `Ok` (no byte filtering on `description`) |
| Cross-slot | `created` and `notCreated` share the same `CreationId` | `Ok`; `notCreated` wins deterministically — `mergeCreatedResults` processes `created` first, then `notCreated` overwrites |
| Top-level | entire body is `JNull` | `Err` |
| Top-level | entire body is `JArray` | `Err` |
| Top-level | empty `JObject` | `Err` (required `accountId` missing) |
| Top-level | extra keys (`"foo": 42`) | `Ok` (Postel) |
| Nested unknown | `created` entry with extra `unknown` key | `Ok` (Postel applies at every decode tier) |
| Nested unknown (deep) | `created` with deeply-nested unknown sub-object | `Ok` |
| `EmailCopyResponse` | `fromAccountId` missing | `Err` |
| `EmailCopyResponse` | `fromAccountId` wrong type | `Err` |
| `EmailImportResponse` | `accountId` missing | `Err` |
| `EmailImportResponse` | `created: null` (RFC §4.8) | `Ok` with empty `createResults` |
| `EmailImportResponse` | `created: { "k0": null }` | `Err` (`EmailCreatedItem.fromJson` rejects non-`JObject`) |
| `EmailImportResponse` | unknown top-level field (`mdnSendStatus`) | `Ok` (Postel) |
| `EmailImportResponse` | `newState` absent | `Ok` with `newState.isNone` (K0 lenient — Stalwart 0.15.5 empirically omits it on failure-only responses) |

### 8.8. Accumulating constructor scale invariants

Pins F1 §3.2.4's "single pass" plus "one error per detected
conflict" commitments under stress. Lives in
`tests/stress/tadversarial_mail_f.nim` Block 8.

| Test name | Constructor | Input shape | Outcome |
|-----------|-------------|-------------|---------|
| `emailUpdateSet10kClass1Anchored` | `initEmailUpdateSet` | 10 001 entries; entries 1..10 000 share target path with entry 0 | `Err` with exactly 10 000 `ValidationError`s; wall-clock ≤ 0.5 s on CI hardware (pins `O(n)` invariant — an `O(n²)` algorithm would blow this tenfold) |
| `emailUpdateSet10kClass1NoAnchor` | `initEmailUpdateSet` | 10 000 identical entries; no privileged anchor | `Err` with exactly 9 999 `ValidationError`s (one per entry after the first; NOT `C(10 000, 2)`) — pins that the conflict detector compares against the FIRST occurrence, not pair-wise |
| `emailUpdateSetThreeClassesStaggered` | `initEmailUpdateSet` | n = 1 000 entries; Class 1 at pos 0/1, Class 2 at pos 499/500, Class 3 at pos 998/999 | `Err` with exactly 3 `ValidationError`s |
| `emailUpdateSetLatePositionConflict` | `initEmailUpdateSet` | 1 000 entries; conflict only at position 998/999 | `Err` with exactly 1 `ValidationError` (single-pass algorithm doesn't bail after a fixed prefix) |
| `emailUpdateSet100kWallClock` | `initEmailUpdateSet` | 100 000 unique entries, no conflicts | `Ok`; wall-clock ≤ 5 s on CI hardware. Pins linear scaling. Excluded from default `just test` via `tests/testament_skip.txt`. |
| `nonEmptyImportMap10kWithDupAtEnd` | `initNonEmptyEmailImportMap` | 10 000 entries with duplicate `CreationId` at position 9 999 | `Err` with exactly 1 violation; capacity bounded |
| `nonEmptyImportMapEmptyAndDupSeparately` | `initNonEmptyEmailImportMap` | empty / duplicate exercised in independent passes | Each invariant fires in its own input shape (the two cannot co-occur for the same input) |
| `getBothCopyCreateResultsEmpty` | `getBoth` | Both invocations well-formed with empty `createResults` | `Ok(EmailCopyResults)` with both fields populated |

### 8.9. Generic `SetError` applicability matrix test plan

Pins F1 §7.2 — eight generic `SetError` variants × three Part F
methods × the operations each method supports. Lives in
`tests/protocol/tmail_method_errors.nim` sections B/C/D.

| `SetError` variant | RFC operation scope | Email/set | Email/copy | Email/import |
|--------------------|---------------------|-----------|------------|--------------|
| `forbidden` | create; update; destroy | ✓ ✓ ✓ | ✓ (create) | ✓ (create) |
| `overQuota` | create; update | ✓ ✓ | ✓ (create) | ✓ (create) |
| `tooLarge` | create; update | ✓ ✓ | ✓ (create) | ✓ (create) |
| `rateLimit` | create | ✓ (create) | ✓ (create) | ✓ (create) |
| `notFound` | update; destroy | ✓ (update) ✓ (destroy) | ✓ (RFC §4.7 grants create-side `notFound` for missing `blobId`) | — |
| `invalidPatch` | update | ✓ (update only) | — | — |
| `willDestroy` | update | ✓ (update only) | — | — |
| `invalidProperties` | create; update | ✓ ✓ | ✓ (create) | ✓ (create) |
| `singleton` | (RFC defines for /set create + destroy) | ✗ negative-test | ✗ negative-test | ✗ negative-test |

Each `✓` cell is one named test per (method × operation) pair that
synthesises the corresponding wire `SetError` in the appropriate
response slot (`notCreated`, `notUpdated`, `notDestroyed`) and
verifies the typed `SetError` surfaces correctly through the typed
response decode. Where a variant covers multiple operations on one
method (e.g., `forbidden` over create + update + destroy in
Email/set), the expansion is one named test per operation —
`emailSetForbiddenOnCreate`, `emailSetForbiddenOnUpdate`,
`emailSetForbiddenOnDestroy` — not a single test covering all three.

The ✗ cells (`emailSetSingletonParsesButNotEmittable`,
`emailCopySingletonParsesButNotEmittable`,
`emailImportSingletonParsesButNotEmittable`) verify that the variant
**parses** (Postel robustness — a buggy or future-extension server
might emit it) but document that no Part F builder is expected to
emit it.

The `setErrorApplicabilityExhaustiveFold` block folds over every
`SetErrorType` variant via `for variant in SetErrorType:` and
explicitly accounts for variants outside the Part F matrix
(`setAlreadyExists` → tmailbox; `setMailboxHasChild`/`...HasEmail`
→ tmailbox; `setBlobNotFound`/`setTooManyKeywords`/`...Mailboxes`/
`setInvalidEmail` → tmail_errors; submission-specific variants →
tmail_errors; `setUnknown` → tserde_errors). Adding a new variant
forces a compile error here until its coverage row is added.

### 8.10. Coverage matrix — F1 promises to test cases

Mechanical mapping between F1 commitments and the test cases that
pin them. Surfaces holes by inspection — every F1 § that makes a
behavioural promise has at least one row.

| F1 § | Promise | Test file | Test name / evidence |
|------|---------|-----------|----------------------|
| §1.6 | Creation types have no public `fromJson` | `grep -L 'fromJson' src/jmap_client/mail/serde_email_update.nim` + analogous | Mechanical grep across the four creation-side serde modules. |
| §2.1 | `EmailCreatedItem` refuses partial construction | `tests/serde/mail/tserde_email_set_response.nim` | `emailCreatedItemMissingSizeRejected` |
| §2.2 | `CopyResponse[EmailCreatedItem]` has no `updated`/`destroyed` fields | `tests/serde/mail/tserde_email_copy.nim` | `emailCopyResponseHasNoUpdatedField` (`assertNotCompiles` block) |
| §2.3 | Inner null vs `{}` distinction preserved on `updateResults` | `tests/serde/mail/tserde_email_set_response.nim` | `updatedEntryNullVsEmptyObjectDistinct` (Ok/Opt.none vs Ok/Opt.some(empty JObject)) |
| §2.3 | Inner null vs `{}` round-trip preserved | `tests/stress/tadversarial_mail_f.nim` | `updatedEntryRoundTripPreservesDistinction` |
| §2.5 | `updateResults` collapses top-level absent / null / `{}` to empty | `tests/serde/mail/tserde_email_set_response.nim` + `tests/stress/tadversarial_mail_f.nim` | `updatedTopLevelAbsentProducesEmpty`, `updatedTopLevelEmptyObjectProducesEmpty`, `updatedTopLevelNull`, `updatedTopLevelAsArray` |
| §2.5 | `destroyResults` three-state | `tests/serde/mail/tserde_email_set_response.nim` | `destroyedAbsentProducesEmpty`, `destroyedEmptyArrayProducesEmpty`, `destroyedTwoElementProducesTwoOks` |
| §3.2.1 | `EmailUpdateVariantKind` exhaustiveness witnessed | Production code — `shape` / `classify` / `toValidationError` / `toJson(EmailUpdate)` each `case` over every variant with no `else` | Compiler-enforced at every build; no dedicated test required |
| §3.2.1 | Six primitive + five convenience constructors declared | `tests/compile/tcompile_mail_f_public_surface.nim` | `declared(addKeyword)` … `declared(moveToMailbox)` |
| §3.2.3.1 | `moveToMailbox` emits `euSetMailboxIds`, NOT `euAddToMailbox` | `tests/serde/mail/tserde_email_update.nim` | `moveToMailboxWireIsSetMailboxIds` (positive); `moveToMailboxNotAddToMailbox` (negative) |
| §3.2.3.1 | `moveToMailbox(id) ≡ setMailboxIds(...)` quantified over `Id` | `tests/property/tprop_mail_f.nim` | property group F |
| §3.2.4 Class 1 | All 6 duplicate-target shapes rejected | `tests/unit/mail/temail_update_set.nim` | `class1TwoAddKeyword`, `class1TwoRemoveKeyword`, `class1TwoSetKeywords`, `class1TwoAddToMailbox`, `class1TwoRemoveFromMailbox`, `class1TwoSetMailboxIds` |
| §3.2.4 Class 2 | Both opposite-op shapes rejected | `tests/unit/mail/temail_update_set.nim` | `class2KeywordOpposite`, `class2MailboxOpposite` |
| §3.2.4 Class 3 | All 4 sub-path × full-replace shapes rejected | `tests/unit/mail/temail_update_set.nim` | `class3AddKeywordSetKeywords`, `class3RemoveKeywordSetKeywords`, `class3AddToMailboxSetMailboxIds`, `class3RemoveFromMailboxSetMailboxIds` |
| §3.2.4 Class 3 | Payload-irrelevance (empty vs non-empty `setKeywords`) | `tests/stress/tadversarial_mail_f.nim` | `class3PayloadIrrelevantEmptySetKeywords`, `class3PayloadIrrelevantNonEmptySetKeywords` |
| §3.2.4 Independent | 4 accepted combinations | `tests/unit/mail/temail_update_set.nim` | `independentSetKeywordsSetMailboxIds`, `independentDistinctAddKeywords`, `independentAddKeywordAddToMailbox`, `independentDistinctMailboxOpposite` |
| §3.2.4 Accumulation | One `ValidationError` per detected conflict | `tests/unit/mail/temail_update_set.nim` | `accumulateMixedClasses` (3 errors); `accumulateClass3TwoDistinctParents` (2 errors); `emailUpdateSetEmpty` |
| §3.2.4 Class 1+2 overlap | Class 2 wins (committed policy) | `tests/unit/mail/temail_update_set.nim` | `class1And2Overlap` |
| §3.2.4 | Single-pass algorithm doesn't bail after fixed prefix | `tests/stress/tadversarial_mail_f.nim` | `emailUpdateSetLatePositionConflict` |
| §3.2.4 | Scale — anchored & unanchored conflict patterns | `tests/stress/tadversarial_mail_f.nim` | `emailUpdateSet10kClass1Anchored`, `emailUpdateSet10kClass1NoAnchor`, `emailUpdateSet100kWallClock` |
| §3.2.4 | Cast-bypass does NOT add post-hoc validation | `tests/stress/tadversarial_mail_f.nim` | `castBypassDocumentsNoPostHocValidation`, `castBypassEmptyAccepted` |
| §3.2.4 | Totality of `initEmailUpdateSet` over arbitrary input | `tests/property/tprop_mail_f.nim` | property group B |
| §3.2.4 | Wire post-condition: `toJson(EmailUpdateSet)` shape | `tests/property/tprop_mail_f.nim` | property group E |
| §3.2.5 | RFC 6901 `~ → ~0`, `/ → ~1`, escape order matters | `tests/serde/mail/tserde_email_update.nim` | per §8.5 (15 named blocks) |
| §3.2.5 | Pointer escape bijectivity | `tests/property/tprop_mail_f.nim` | property group D |
| §3.2.5 | `Keyword` charset includes `~` and `/` | `tests/unit/mail/tkeyword.nim` | `keywordWithTildeAccepted`, `keywordWithSlashAccepted`, `keywordWithBothAccepted` |
| §3.3 | `MailboxUpdateSet` duplicate-target rejection | `tests/unit/mail/tmailbox.nim` | `initMailboxUpdateSetEmpty`, `...SingleValid`, `...TwoSameKind`, `...ThreeSameKind`, `...TwoDistinctRepeated` |
| §3.3 | `MailboxUpdate` per-variant setter shape | `tests/unit/mail/tmailbox.nim` | `setNameConstructsCorrectKind`, `setParentIdNoneConstructsCorrectKind`, `setParentIdSomeConstructsCorrectKind`, `setRoleConstructsCorrectKind`, `setSortOrderConstructsCorrectKind`, `setIsSubscribedConstructsCorrectKind` |
| §3.3 | `setRole(Opt.none) → JSON null` (clear-role) | `tests/serde/mail/tserde_mailbox.nim` | `setRoleNoneEmitsJsonNull` |
| §3.3 | `setRole(Opt.some(role)) → JSON string` | `tests/serde/mail/tserde_mailbox.nim` | `setRoleSomeEmitsString` |
| §3.3 | `setParentId(Opt.none) → JSON null` (reparent-to-top) | `tests/serde/mail/tserde_mailbox.nim` | `setParentIdNoneEmitsJsonNull` |
| §3.3 | `setParentId(Opt.some(id)) → JSON string` | `tests/serde/mail/tserde_mailbox.nim` | `setParentIdSomeEmitsString` |
| §3.4 | `VacationResponseUpdateSet` duplicate-target rejection | `tests/unit/mail/tvacation.nim` | `initVacationResponseUpdateSetEmpty`, `...SingleValid`, `...TwoSameKind`, `...ThreeSameKind`, `...TwoDistinctRepeated` |
| §3.4 | `VacationResponseUpdate` setter shape across 6 variants | `tests/unit/mail/tvacation.nim` | sections A and C cover all six variants × payload-axis representatives |
| §3.4 | `VacationResponseUpdate` nullable-field wire behaviour | `tests/serde/mail/tserde_vacation.nim` | `vruSetFromDate{None,Some}`, `vruSetToDate{None,Some}`, `vruSetSubject{None,Some}`, `vruSetTextBody{None,Some}`, `vruSetHtmlBody{None,Some}` |
| §4.1 | `addEmailSet` full invocation | `tests/protocol/tmail_builders.nim` | `addEmailSetFullInvocation` |
| §4.1 | `addEmailSet` minimal (all `Opt.none`) | `tests/protocol/tmail_builders.nim` | `addEmailSetMinimalAccountIdOnly` |
| §4.1 | `addEmailSet` `ifInState` wire semantics | `tests/protocol/tmail_builders.nim` | `addEmailSetIfInStateEmitted`, `addEmailSetIfInStateOmittedWhenNone` |
| §4.1 | `addEmailSet` typed `update: NonEmptyEmailUpdates` flows through | `tests/protocol/tmail_builders.nim` | `addEmailSetTypedUpdate` (pins `toJson(NonEmptyEmailUpdates)` threading) |
| §4.2 | `addEmailImport` invocation + capability + phantom-typed response | `tests/protocol/tmail_methods.nim` | `addEmailImportInvocationName` |
| §4.2 | `addEmailImport` `emails: NonEmptyEmailImportMap` flows through | `tests/protocol/tmail_methods.nim` | `addEmailImportEmailsPassthrough` |
| §4.2 | `addEmailImport` `ifInState` pass-through | `tests/protocol/tmail_methods.nim` | `addEmailImportIfInStateSomePassthrough`, `addEmailImportIfInStateNoneOmitted` |
| §5.3 | `addEmailCopyAndDestroy` emits `onSuccessDestroyOriginal: true`; all three state params | `tests/protocol/tmail_builders.nim` | `addEmailCopyAndDestroyEmitsTrue`, `...DestroyFromIfInStateSome`, `...DestroyFromIfInStateNone`, `...AllStateParamsSome` |
| §5.3 | `addEmailCopyAndDestroy` destroy handle carries `NameBoundHandle` with `methodName: mnEmailSet`; primary/implicit share call-id | `tests/protocol/tmail_builders.nim` | `addEmailCopyAndDestroyEmitsTrue` (asserts `handles.implicit.methodName == mnEmailSet` and `handles.implicit.callId == handles.primary.callId()`) |
| §5.3 | `addEmailCopy` (simple) has no `onSuccessDestroyOriginal` | `tests/protocol/tmail_builders.nim` | `addEmailCopyPhantomType`, `addEmailCopyIfInStateEmittedWithCopySemantics` |
| §5.4 | `getBoth` happy path | `tests/protocol/tmail_builders.nim` | `getBothCopyAndDestroyHappyPath` |
| §5.4 | `getBoth` short-circuits on copy `MethodError` | `tests/protocol/tmail_builders.nim` | `getBothShortCircuitOnCopyError` (table-driven via `for variant in MethodErrorType:`) |
| §5.4 | `getBoth` short-circuits when destroy invocation absent | `tests/protocol/tmail_builders.nim` | `getBothShortCircuitOnDestroyMissing` (`serverFail`, description `"no Email/set response for call ID c0"`) |
| §5.4 | `getBoth` destroy-side errors are OPAQUE under name-filter | `tests/protocol/tmail_builders.nim` + `tests/stress/tadversarial_mail_f.nim` | `getBothShortCircuitOnDestroyError` and `getBothImplicitDestroyMethodError` (synthetic `serverFail / no Email/set response`) |
| §5.4 | `getBoth` adversarial method-call-id mismatch and copy-side `MethodError` | `tests/stress/tadversarial_mail_f.nim` | `getBothImplicitDestroyMethodCallIdMismatch`, `getBothCopyMethodError` |
| §6.1 | `EmailCopyItem` mailbox-override type-level rejection | `tests/unit/mail/temail_copy_item.nim` | `copyItemTypeRejectsEmptyMailboxIdSet`, `copyItemTypeRejectsNonEmptyMailboxIdSetWrongDistinct` |
| §6.1 | `EmailCopyItem` serde (minimal / full override) | `tests/serde/mail/tserde_email_copy.nim` | `emailCopyItemMinimalEmitsIdOnly`, `emailCopyItemFullOverrideEmitsThreeKeys`, `emailCopyItemOptNoneOmitsKeys` |
| §6.2 | `NonEmptyEmailImportMap` invariants | `tests/unit/mail/temail.nim` | five `initNonEmptyEmailImportMap*` blocks |
| §6.2 | Scale — 10 k entries with duplicate at end | `tests/stress/tadversarial_mail_f.nim` | `nonEmptyImportMap10kWithDupAtEnd` |
| §6.3 | `EmailImportItem` required `mailboxIds`, optional `keywords` | `tests/unit/mail/temail_import_item.nim` | `importItemRejectsOptNoneMailboxIds`, `importItemMinimalConstruction`, `importItemKeywordsThreeStates` |
| §7.1 | `SetError.extras` extractors work via Email-method `createResults` | `tests/stress/tadversarial_mail_f.nim` | `emailSetExtrasReachableFromCreateResults`, `emailCopyExtrasReachableFromCreateResults`, `emailImportExtrasReachableFromCreateResults` |
| §7.2 | Generic `SetError` applicability matrix | `tests/protocol/tmail_method_errors.nim` | per §8.9 cell |
| §7.4 | Method-level errors per method | `tests/protocol/tmail_method_errors.nim` | seven blocks: `emailSetRequestTooLarge`, `emailSetStateMismatch`, `emailCopyFromAccountNotFound`, `emailCopyFromAccountNotSupportedByMethod`, `emailCopyStateMismatch`, `emailImportStateMismatch`, `emailImportRequestTooLarge` |
| §7.5 | Adversarial `SetError.extras` via integration path | `tests/stress/tadversarial_mail_f.nim` | five-row coverage in each of the three `…ExtrasReachableFromCreateResults` blocks |
| §8 (meta) | Cross-response coherence anomalies | `tests/stress/tadversarial_mail_f.nim` | `coherenceOldStateNewStateEqual`, `coherenceOldStateNewStateNullPair`, `coherenceAccountIdMismatchAcrossInvocations`, `coherenceUpdatedSameKeyTwice`, `coherenceCreatedAndNotCreatedShareKey` |
| §8 (meta) | JSON-structural attack surface | `tests/stress/tadversarial_mail_f.nim` | `structuralBomPrefix`, `structuralNanInfinity`, `structuralDuplicateKeysInObject`, `structuralDeepNesting`, `structuralLargeStringSize`, `structuralEmptyKey`, `structuralUnicodeNoncharacters` |

The matrix is a **living artefact**: any new F1 promise (added under
F20 architecture amendments or later parts) MUST add a row here
before the implementation merges. The matrix is the single artefact
that proves test-spec adequacy by inspection.

### 8.11. Verification commands

Implementation PR verification sequence:

- `just build` — shared library compiles; no new warnings.
- `just test` — every test file above runs green.
- `just analyse` — nimalyzer passes without new suppressions.
- `just fmt-check` — nph formatting unchanged.
- `just ci` — full pipeline green.

The compile-only smoke (`tests/compile/tcompile_mail_f_public_surface.nim`,
§8.2.2) fails loudly at the `static:` block if any Part F public
symbol is not re-exported through `src/jmap_client.nim`'s cascade.
Variant-kind exhaustiveness is witnessed by the production `case`
sites in `src/jmap_client/mail/email_update.nim` on every build (no
dedicated probe needed — see §8.2.2).

The 100k wall-clock test (`emailUpdateSet100kWallClock`) is
excluded from default `just test` via `tests/testament_skip.txt`
and runs under `just stress` or the full CI cycle.

Property tests in `tprop_mail_f.nim` cover the accumulating-
constructor totality (B), the duplicate-key invariant for
`NonEmptyEmailImportMap` (C), the RFC 6901 escape bijectivity (D),
the `toJson(EmailUpdateSet)` post-condition (E), and the
`moveToMailbox ≡ setMailboxIds` quantification (F). Coverage matrix
§8.10 is the single inspection point for "is every F1 promise pinned
by a test?".

---

*End of Part F2 design document.*
