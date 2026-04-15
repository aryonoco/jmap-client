# RFC 8621 JMAP Mail — Design F2: Email Write Path — Test Specification

Companion test specification for [`11-mail-F1-design.md`](./11-mail-F1-design.md).
The section number below is kept at `8` so that cross-references from
F1 (§1–§7 and §9) into this document remain valid without rewriting.
See F1 for the full context (scope, typed update algebras, response
surface, builders, and the Decision Traceability Matrix).

This document was realigned with the actual Part F implementation
after the F1 source code landed. Where F1's prose and the shipped
code disagree, **the shipped code is authoritative** and this document
specifies the tests against it. The per-section "Implementation
reality" notes flag the places where the test shape differs from
what F1 prose would have suggested.

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
5. **Compile-time reachability** — the shipped file is
   `tests/compile/tcompile_mail_f_public_surface.nim` (action:
   `"compile"` via the ambient `{.push raises: [].}`; the `static:`
   block compiles but has no runtime effect). It proves every new
   public symbol is reachable through the top-level `jmap_client`
   re-export chain. See §8.2.2 for the shape.

   **Implementation reality — divergence from F1 prose.** F1 §1.5.1
   and §1.5.3 describe `PatchObject` being *demoted* (the `*` export
   dropped but the type still existing internally). The shipped
   implementation goes one step further: `PatchObject` is **removed
   entirely** from `src/jmap_client/framework.nim`. All mail update
   paths flow through the three typed algebras directly; no wire-
   patch primitive is carried in-tree. Consequently the previously
   planned `assertNotCompiles((let _: PatchObject = default(PatchObject)))`
   gate plus `assertNotCompiles(jmap_client.emptyPatch())` gate
   would be trivially true against a non-existent symbol and carry
   no information; they are **not** in the shipped compile test.
   Variant-kind exhaustiveness probes and `fromJson`-absence pins
   also do not appear in the shipped compile test — the `declared()`
   approach (see §8.2.2) already catches symbol regressions at the
   re-export boundary, and variant-forgetting is caught by the
   compiler's default exhaustiveness check on every internal `case`
   site (e.g., `email_update.nim:163-169` `shape`, `email_update.nim:171-185`
   `classify`, `email_update.nim:226-242` `toValidationError`).

**File-naming note.** Part E's adversarial stress file is
`tests/stress/tadversarial_blueprint.nim` (per-concept, not
part-lettered). Part F deliberately deviates to
`tadversarial_mail_f.nim` to mirror the property-test convention
(`tprop_mail_f.nim` / `tprop_mail_e.nim`) — by Part F, the
part-lettered scheme has stabilised across two property files and
warrants the third instance for the adversarial slot. The Part E
adversarial file is the structural precedent
(`tests/stress/tadversarial_blueprint.nim`), referenced explicitly
by §8.10 below.

**Test-idiom note.** The shipped test style across all new files in
this part is `block <name>:` + `assertOk`/`assertErr`/`assertEq`/
`assertLen` from `tests/massertions.nim` plus raw `doAssert` for
inline checks. No `std/unittest` `test "name":` blocks, no `suite`
wrappers. The canonical precedent for the style is
`tests/unit/mail/temail.nim` (already extended for Part F with the
`initNonEmptyEmailImportMap*` blocks at lines 59–125) and
`tests/unit/mail/tmailbox.nim` (already extended for Part F with the
`initMailboxUpdateSet*` blocks at lines 124–176). Prescriptions in
§8.3 and §8.4 below name proposed `block` identifiers directly, not
unittest-style titles.

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

**State of play (as of the F1 implementation landing):**

| File | Status |
|------|--------|
| `tests/property/tprop_mail_f.nim` | **Not yet created** — all five property groups in §8.2.1 are still to be written. |
| `tests/compile/tcompile_mail_f_public_surface.nim` | **Shipped** — 49 `declared()` assertions covering every F1 public symbol. See §8.2.2 for the actual shape and the enhancements still to layer on. |
| `tests/stress/tadversarial_mail_f.nim` | **Not yet created** — the adversarial-scenario blocks in §8.2.3 are still to be written. |

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

#### 8.2.2. `tests/compile/tcompile_mail_f_public_surface.nim`

Compile-only smoke test. Shipped shape: a single top-level
`import jmap_client` plus a `static:` block containing 49
`declared(<symbol>)` assertions, one per new public symbol (types,
variant-kind enums, primitive+convenience ctors, set-ctors, builder
procs, method-name enum variant, entity resolver constant). A
single runtime-scope `doAssert $mnEmailImport == "Email/import"`
pins the imported module against Nim's `UnusedImport` check.

**Why `declared()` and not `compiles()`.** `declared()` sidesteps
overload-resolution ambiguity on generically-named constructors
(`setName`, `setRole`, `setSubject`, …) that a naïve
`compiles(let x: EmailUpdate = setName("x"))` probe would snag on.
`declared()` asks only "is this identifier visible at this site?",
which is exactly the re-export invariant under test. The shipped
file documents this choice in its opening docstring.

**Covered symbols (authoritative list, from the shipped file):**

- **Types (20):** `EmailUpdate`, `EmailUpdateVariantKind`,
  `EmailUpdateSet`, `EmailCreatedItem`, `UpdatedEntry`,
  `UpdatedEntryKind`, `EmailSetResponse`, `EmailCopyResponse`,
  `EmailImportResponse`, `EmailCopyItem`, `EmailImportItem`,
  `NonEmptyEmailImportMap`, `MailboxUpdate`,
  `MailboxUpdateVariantKind`, `MailboxUpdateSet`,
  `VacationResponseUpdate`, `VacationResponseUpdateVariantKind`,
  `VacationResponseUpdateSet`, `EmailCopyHandles`,
  `EmailCopyResults`.
- **Protocol-primitive EmailUpdate ctors (6):** `addKeyword`,
  `removeKeyword`, `setKeywords`, `addToMailbox`,
  `removeFromMailbox`, `setMailboxIds`.
- **Domain-named EmailUpdate ctors (5):** `markRead`, `markUnread`,
  `markFlagged`, `markUnflagged`, `moveToMailbox`.
- **Set/map ctors (6):** `initEmailUpdateSet`, `initEmailCopyItem`,
  `initEmailImportItem`, `initNonEmptyEmailImportMap`,
  `initMailboxUpdateSet`, `initVacationResponseUpdateSet`.
- **MailboxUpdate ctors (5):** `setName`, `setParentId`, `setRole`,
  `setSortOrder`, `setIsSubscribed`.
- **VacationResponseUpdate ctors (6):** `setIsEnabled`,
  `setFromDate`, `setToDate`, `setSubject`, `setTextBody`,
  `setHtmlBody`.
- **Methods/builders (5):** `addEmailSet`, `addEmailCopy`,
  `addEmailCopyAndDestroy`, `addEmailImport`, `getBoth`.
- **Enum variant (1):** `mnEmailImport`.
- **Entity resolver (1):** `importMethodName`.

**What the shipped file deliberately does NOT do:**

- **No `PatchObject`-demotion `assertNotCompiles` gate.**
  `PatchObject` is **removed entirely** from
  `src/jmap_client/framework.nim`; an `assertNotCompiles` against a
  type that does not exist is trivially true and carries no
  information. `git log -Sframework.nim -- 'PatchObject'` is the
  durable record of the removal.
- **No variant-kind exhaustiveness probes.** Internal `case` sites
  in `email_update.nim` (`shape`, `classify`, `toValidationError`)
  and in the three `toJson(…Update)` sites already force the
  compiler to witness every variant. A dedicated probe would add
  no coverage the production code does not already provide.
- **No asymmetric `fromJson`-absence pins.** The creation types
  (`EmailUpdate`, `EmailUpdateSet`, `EmailCopyItem`,
  `EmailImportItem`, `NonEmptyEmailImportMap`, `MailboxUpdate`,
  `MailboxUpdateSet`, `VacationResponseUpdate`,
  `VacationResponseUpdateSet`) have no `fromJson` defined at their
  declaration sites in `serde_email_update.nim`, `serde_email.nim`,
  `serde_mailbox.nim`, `serde_vacation.nim`; `grep -n 'fromJson'`
  across those files is the primary check. Note that the three
  **response** types (`EmailSetResponse`, `EmailCopyResponse`,
  `EmailImportResponse`) DO have `fromJson` — they flow server →
  client, so two-way serde is correct and a blanket "no `fromJson`
  for anything new in F" pin would be wrong.

**Optional enhancement — if reviewer strictness demands it.** A
subsequent PR could add per-creation-type pins in the form:

```nim
static:
  doAssert not compiles(EmailUpdate.fromJson(newJObject()))
  doAssert not compiles(EmailUpdateSet.fromJson(newJObject()))
  ...
```

Placed at the end of the `static:` block, each assertion documents
one type's toJson-only contract at compile time without the
false-positive risk of `assertNotCompiles` (which also fails on
unrelated compile errors). This is **not** in the shipped file; it
is a potential later addition if the `grep`-level check proves
insufficient in practice.

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
  `cast[EmailUpdateSet](@[addKeyword(k), addKeyword(k)])` (a Class 1
  violation) is accepted by `toJson` and emits structurally malformed
  wire JSON. The test asserts the malformed output is produced
  (negative assertion: no runtime check fires) and pins the
  documented contract that callers using `cast` opt out of the
  invariant guarantee. The test docstring explicitly states this is
  a **negative-pin** test — the library deliberately does NOT add a
  runtime check, since the cost of post-hoc validation on every
  `toJson` would penalise the well-typed path. F1 §3.2.4 links to
  this test by name. The constructor names are the protocol-primitive
  public symbols (`addKeyword`, …), not the `eu*` variant-kind
  identifiers, which are discriminators, not ctors.
- `castBypassEmptyAccepted` —
  `cast[EmailUpdateSet](newSeq[EmailUpdate]())` (empty — would be
  rejected by `initEmailUpdateSet`) is accepted by `toJson` and
  emits `{}`. Same negative-pin shape as above.

Generators for cast-bypass cases live in `mproperty.nim` as
`genEmailUpdateSetCastBypass(rng, trial)` (per §8.6.1) — they are
NOT used by property groups in §8.2.1 because the property would
trivially fail; they are only used by `tadversarial_mail_f.nim`.

### 8.3. New per-concept test files

**State-of-play key.** Each row below is tagged:
- **SHIPPED** — the blocks already exist in the cited file after the F1 implementation merge. Reproduced here verbatim so this document is a single source of truth.
- **TO-ADD** — blocks still to be written in the cited file (creating the file first if it does not exist).

**Error-rail shape (applies to every TO-ADD below unless noted).** The
shipped `ValidationError` record has exactly three fields:
`typeName: string`, `message: string`, `value: string`. There is
**no** `classification` field, `kind` enum, or similar typed
discriminator on `ValidationError`; all prior F2 drafts that
referenced `error[0].classification == Class2OppositeOperations`
(or any enum-valued classifier) are fictional and have been
rewritten to check `error[0].message` against the literal message
string the production code emits. The authoritative messages, per
the shipped implementation, are:

| Type | Invariant | `message` | `value` |
|------|-----------|-----------|---------|
| `EmailUpdateSet` | Empty input | `"must contain at least one update"` | `""` |
| `EmailUpdateSet` | Class 1 (duplicate target path) | `"duplicate target path"` | target path, e.g. `"keywords/$seen"` |
| `EmailUpdateSet` | Class 2 (opposite operations) | `"opposite operations on same sub-path"` | sub-path |
| `EmailUpdateSet` | Class 3 (sub-path + full-replace) | `"sub-path operation alongside full-replace on same parent"` | parent property, e.g. `"keywords"` |
| `MailboxUpdateSet` | Empty | `"must contain at least one update"` | `""` |
| `MailboxUpdateSet` | Duplicate target property | `"duplicate target property"` | symbolic kind, e.g. `"muSetName"` |
| `VacationResponseUpdateSet` | Empty | `"must contain at least one update"` | `""` |
| `VacationResponseUpdateSet` | Duplicate target property | `"duplicate target property"` | symbolic kind, e.g. `"vruSetIsEnabled"` |
| `NonEmptyEmailImportMap` | Empty | `"must contain at least one entry"` | `""` |
| `NonEmptyEmailImportMap` | Duplicate `CreationId` | `"duplicate CreationId"` | the duplicated CreationId text, e.g. `"c1"` |

Note the singular case where `NonEmptyEmailImportMap` uses the
word "entry" rather than "update" — import payloads are not
updates, so the shared `validateUniqueByIt` helper is invoked with
a different `emptyMsg` string at the call site
(`email.nim:399-405`).

**Uniqueness-collapsing contract.** Three of the four set-style
smart constructors use `validateUniqueByIt`
(`validation.nim:130-151`), which reports **each repeated key
exactly once regardless of occurrence count**. Three duplicates of
the same key yield **one** error, not two. This applies to
`MailboxUpdateSet`, `VacationResponseUpdateSet`, and
`NonEmptyEmailImportMap`. `EmailUpdateSet` uses a different path-
based detector (`samePathConflicts`, `email_update.nim:204-224`)
that emits one conflict per same-path occurrence AFTER the first;
N occurrences at a single target path therefore yield N − 1
Class 1 conflicts. Tests must calibrate their exact-count
assertions accordingly (see §8.10).

Unit — `tests/unit/mail/`:

| File | Concerns |
|------|----------|
| `temail.nim` — §C `initNonEmptyEmailImportMap` block group at lines 59–125 | **SHIPPED.** Five `block`s: (1) `initNonEmptyEmailImportMapEmpty` — empty input → one `typeName: "NonEmptyEmailImportMap"`, `message: "must contain at least one entry"`, `value: ""` error. (2) `initNonEmptyEmailImportMapSingleValid` — single valid entry → `Ok`. (3) `initNonEmptyEmailImportMapTwoSameCreationId` — two entries sharing a CreationId → one error with `value == "c1"`. (4) `initNonEmptyEmailImportMapThreeSameCreationId` — three entries sharing a CreationId → one error (pins the uniqueness-collapsing contract at N = 3). (5) `initNonEmptyEmailImportMapTwoDistinctRepeated` — four entries forming two distinct duplicate pairs → exactly two errors, one per distinct repeated key, verified via set-membership so the test does not depend on error ordering. Order-preservation, happy-path smoke, and `pairs`-iteration visibility are NOT independently tested in the shipped file — the single-valid block plus the wire-level serde tests (§8.3 serde row) are the implicit order/structural checks. |
| `tmailbox.nim` — §E `initMailboxUpdateSet` block group at lines 124–176 | **SHIPPED.** Five `block`s: (1) `initMailboxUpdateSetEmpty` — one error with `message: "must contain at least one update"`. (2) `initMailboxUpdateSetSingleValid`. (3) `initMailboxUpdateSetTwoSameKind` — two `setName` → one error with `value: "muSetName"`. (4) `initMailboxUpdateSetThreeSameKind` — three `setName` → one error (uniqueness-collapse at N = 3). (5) `initMailboxUpdateSetTwoDistinctRepeated` — four entries forming two distinct duplicate pairs (`setName` ×2 + `setParentId` ×2) → exactly two errors, set-membership-verified. The per-variant fold across the five `MailboxUpdateVariantKind` values is **deliberately not** in the shipped scope: (2)–(5) sample `muSetName` and `muSetParentId` as representatives of the value-axes that could behave differently (`string` payload, `Opt[Id]` payload). A future follow-up PR could add `initMailboxUpdateSetDuplicateSetRole` / `...SortOrder` / `...IsSubscribed` for exhaustion. |
| `tvacation.nim` — §A/B block groups at lines 17–88 | **SHIPPED.** Section A — three setter-shape blocks: (1) `setIsEnabledConstructsCorrectKind`, (2) `setFromDateConstructsCorrectKind`, (3) `setSubjectClearsWhenNone`. These sample the three distinct payload shapes (`bool`, `Opt[UTCDate]`, `Opt[string]`) without enumerating all six setters. Section B — five set-level blocks mirroring `tmailbox.nim`: `initVacationResponseUpdateSetEmpty` / `SingleValid` / `TwoSameKind` / `ThreeSameKind` / `TwoDistinctRepeated`, with `value: "vruSetIsEnabled"` / `"vruSetSubject"` as the duplicate-kind tokens. Same "no exhaustive fold" posture as `tmailbox.nim`. |
| `temail_update.nim` | **TO-ADD.** New file. (1) `addKeywordConstructsCorrectKind` through `setMailboxIdsConstructsCorrectKind` — six blocks, one per protocol-primitive, asserting `u.kind` + the variant payload field. (2) Five convenience-equivalence blocks: `markReadEqualsAddKeywordSeen`, `markUnreadEqualsRemoveKeywordSeen`, `markFlaggedEqualsAddKeywordFlagged`, `markUnflaggedEqualsRemoveKeywordFlagged`, `moveToMailboxEqualsSetMailboxIdsSingleton`. Each asserts `kind` match plus structural payload match — no `emailUpdateEq` helper is prescribed because Nim's derived `==` handles every payload type used by these branches (`Keyword` via `defineStringDistinctOps`, `NonEmptyMailboxIdSet` via `defineNonEmptyHashSetDistinctOps` borrowing `==`, and `KeywordSet` is NOT exercised by the convenience constructors, so the equality gap on `KeywordSet` never fires in this file). (3) Negative-discrimination blocks: `moveToMailboxDistinctIds` (construct two with distinct `Id`, assert `kind` matches and `mailboxes` differ); `addKeywordDistinctKeywords`. |
| `temail_update_set.nim` | **TO-ADD.** New file. Structure mirrors `temail.nim`'s C-block idiom. (1) `emailUpdateSetEmpty` — one error with `typeName == "EmailUpdateSet"`, `message == "must contain at least one update"`, `value == ""`. (2) Class 1 — six blocks, one per shape in §8.7.1; each asserts `assertLen res.error, 1`, `error[0].message == "duplicate target path"`, and `error[0].value` is the expected target-path string. (3) Class 2 — two blocks (`class2KeywordOpposite`, `class2MailboxOpposite`); assertion pattern same, but `message == "opposite operations on same sub-path"`. (4) Class 3 — four blocks per §8.7.3; assertion pattern same, `message == "sub-path operation alongside full-replace on same parent"`, `value == "keywords"` / `"mailboxIds"`. (5) Class 1+2 overlap — `class1And2Overlap`: feed `@[addKeyword(kwSeen), removeKeyword(kwSeen)]`, assert `assertLen res.error, 1` (not 2), `error[0].message == "opposite operations on same sub-path"` (Class 2 wins — the shipped `samePathConflicts` loop emits `ckOppositeOps` when kinds differ, `ckDuplicatePath` when kinds match, never both for the same path). (6) Independent cases (§8.7.4) — four mandatory positive `assertOk` blocks. (7) Accumulation — `accumulateMixedClasses` (one Class 1 + one Class 2 + one Class 3 → `assertLen res.error, 3`); `accumulateThreeClass3` (three distinct Class 3 violations on `keywords` and `mailboxIds` parents → exact count check). Empty-alone is already covered by (1). |
| `temail_copy_item.nim` | **TO-ADD.** New file. (1) `copyItemTypeRejectsEmptyMailboxIdSet` — `assertNotCompiles(EmailCopyItem(id: id1, mailboxIds: Opt.some(initMailboxIdSet(@[]))))`. Pins F1 §6.1 "the override slot rejects empty sets at the type level" — the override field is typed `Opt[NonEmptyMailboxIdSet]`, so any `MailboxIdSet` literal (empty or not) is a compile error. (2) `copyItemTypeRejectsNonEmptyMailboxIdSetWrongDistinct` — `assertNotCompiles(initEmailCopyItem(id = id1, mailboxIds = Opt.some(initMailboxIdSet(@[id1]))))`. Pins that `MailboxIdSet` is the wrong distinct — the override slot demands `NonEmptyMailboxIdSet`. The (1)/(2) pair separates the empty-rejection axis from the distinct-type axis. (3) `copyItemIdOnlyRoundTrip` — `let ci = initEmailCopyItem(id = id1)`; assert every override field is `Opt.none`. (4) `copyItemAllOverridesPopulated` — construct with `Opt.some` in every override field and assert structural readback. Serde shape pinning is delegated to §8.3 serde row. |
| `temail_import_item.nim` | **TO-ADD.** New file. (1) `importItemRejectsOptNoneMailboxIds` — `assertNotCompiles(initEmailImportItem(blobId = b, mailboxIds = Opt.none(NonEmptyMailboxIdSet)))`. Pins that `mailboxIds` is required (non-Opt `NonEmptyMailboxIdSet`). (2) `importItemMinimalConstruction` — `let i = initEmailImportItem(b, mbxs)`; assert `i.keywords.isNone and i.receivedAt.isNone`. (3) `importItemKeywordsThreeStates` — exercise the three `Opt.none` / `Opt.some(initKeywordSet(@[]))` / `Opt.some(non-empty)` forms. Wire-level collapse of the first two is delegated to §8.3 serde row. |
| `tkeyword.nim` (append new section) | **TO-ADD.** New section appending to the existing file. Three blocks: `keywordWithTildeAccepted` (`parseKeyword("$has~tilde")`), `keywordWithSlashAccepted` (`parseKeyword("$has/slash")`), `keywordWithBothAccepted` (`parseKeyword("$~/")`). Pins F1 §3.2.5's spec-faithful Postel commitment — RFC 8621 §4.1.1's keyword charset includes `~` and `/`. Required upstream of §8.8's escape-boundary serde tests; without it those tests cannot construct the adversarial inputs. |

Serde — `tests/serde/mail/` (all **TO-ADD** unless marked):

| File | Concerns |
|------|----------|
| `tserde_email_update.nim` | **TO-ADD** (new file). (a) `toJson(EmailUpdate)` returns a `(string, JsonNode)` tuple — the shipped signature is `func toJson*(u: EmailUpdate): (string, JsonNode)` at `serde_email_update.nim:28`, not a bare `JsonNode`. Six blocks, one per variant: `addKeyword` emits `("keywords/" & escaped, newJBool(true))`; `removeKeyword` emits `("keywords/" & escaped, newJNull())`; `setKeywords` emits `("keywords", keywords.toJson())`; `addToMailbox` / `removeFromMailbox` / `setMailboxIds` follow the analogous pattern with `mailboxIds` as parent. (b) `toJson(EmailUpdateSet)` flattens to a `JsonNode` with distinct keys (the shipped iteration at `serde_email_update.nim:48-57` uses `for u in seq[EmailUpdate](us)` over the validated set). (c) `moveToMailbox(id)` wire output: positive (`key == "mailboxIds"`, value is an object with `string(id)` key) and negative (`key != "mailboxIds/" & string(id)`) — pins F21 against `addToMailbox` regression. (d) RFC 6901 escape-boundary blocks — full enumeration in §8.8 table. Since `jsonPointerEscape` is **not exported** (no `*` at `serde_email_update.nim:22`), every escape-boundary assertion drives through `toJson(addKeyword(parseKeyword(k).get()))` and inspects the tuple `.0` string. |
| `tserde_email_import.nim` | **TO-ADD** (new file). `toJson(EmailImportItem)` emits `blobId` and `mailboxIds` always; omits `keywords`/`receivedAt` when `Opt.none`, emits them when `Opt.some`. `toJson(NonEmptyEmailImportMap)` emits the correct top-level object with `CreationId` keys. `EmailImportResponse.fromJson` parses well-formed responses, including `created: null` (per RFC §4.8) and `created: {}` (empty) as distinct accepted shapes that both decode to an empty `createResults` table. Malformed responses surface as `Err(ValidationError)` on the Result rail. |
| `tserde_email_copy.nim` | **TO-ADD** (new file). `toJson(EmailCopyItem)` — minimal (`initEmailCopyItem(id)` alone) emits only the `id` key; full override emits the three override keys; `Opt.none` overrides omit their keys. `EmailCopyResponse.fromJson` parses three shapes: `created`-only, `notCreated`-only (asserts `notCreated` populates `Err(SetError)` entries in `createResults` at the correct `CreationId`), and combined. The `fromAccountId` field is required (assert `Err` on absence). Type-level: `assertNotCompiles((let r: EmailCopyResponse = default(EmailCopyResponse); discard r.updated))` — pins F1 §2.2's "EmailCopyResponse omits /set-specific fields". |
| `tserde_email_set_response.nim` | **TO-ADD** (new file). `EmailSetResponse.fromJson` parses the eight-field shape (`accountId`, `oldState`, `newState`, `createResults`, `updated`, `destroyed`, `notUpdated`, `notDestroyed`); the `createResults` merge layer correctly reconstructs the merged table from wire `created`/`notCreated` maps (helper name: `mergeCreatedResults`, used at `serde_email.nim:847`); `EmailCreatedItem.fromJson` rejects missing-field shapes (consolidated here per C5 deduplication — the broader malformed-shape coverage is in `tadversarial_mail_f.nim` §8.9; this file focuses on happy-path shape pinning). `updated` outer three-state coverage: absent → `Opt.none`; `null` → `Opt.none`; `{}` → `Opt.some(emptyTable)`. `destroyed` three-state coverage: absent / empty-array / two-element. `UpdatedEntry` distinctness pins (`null` → `uekUnchanged`; `{}` → `uekChanged(JObject{})`) per §8.9 response-decode matrix. `toJson(EmailSetResponse)` round-trip: construct a response, toJson, fromJson, assert equality of the reconstructed record (or equivalent field-wise pins if deep `==` on `Result[EmailCreatedItem, SetError]` is awkward — use per-field `assertEq` on `accountId`, `newState`, etc., plus a per-CreationId iteration over `createResults`). |

### 8.4. Existing-file appends

`tests/protocol/tmail_builders.nim` — **all TO-ADD**; no F1-specific
block exists in the shipped file for `addEmailSet`, `addEmailCopy`,
`addEmailCopyAndDestroy`, or `getBoth`. The `addMailboxSet` blocks
at lines 252–293 pre-date the Part F migration; since the builder
signature has migrated to `Opt[Table[Id, MailboxUpdateSet]]`, those
blocks continue to compile (no `update` value was supplied) but do
not exercise the new typed path. The prescribed appends:

- `addEmailSetFullInvocation` — builds an invocation with the correct
  method name (`mnEmailSet`), args shape, and capability URI
  (`"urn:ietf:params:jmap:mail"`); phantom-typed response handle
  carries `EmailSetResponse`; `create`/`update`/`destroy`
  parameters serialise correctly when all three are `Opt.some`.
- `addEmailSetMinimalAccountIdOnly` — all of `create`, `update`,
  `destroy`, `ifInState` `Opt.none`; wire JSON contains `accountId`
  only and no other operation keys (pins F1 §4.1's "bare invocation"
  affordance).
- `addEmailSetIfInStateEmitted` — `ifInState: Opt.some(state)` emits
  `"ifInState": "<state>"`; negative counterpart
  `addEmailSetIfInStateOmittedWhenNone` — `ifInState: Opt.none`
  emits no key (no `null`).
- `addEmailSetTypedUpdate` — construct a valid `EmailUpdateSet` via
  `initEmailUpdateSet(@[markRead()]).get()`, pass through the builder
  with `update: Opt.some(tbl)` (where `tbl` is a
  `Table[Id, EmailUpdateSet]` with one entry), inspect
  `args["update"][string(id)]["keywords/$seen"]` on the wire and
  assert `getBool(false) == true`. Pins that the typed algebra
  flattens through `toJson(EmailUpdateSet)` at the builder boundary.
- `addEmailCopyPhantomType` — phantom-typed handle carries
  `EmailCopyResponse`; no `onSuccessDestroyOriginal` key emitted
  (the simple overload never sets it).
- `addEmailCopyIfInStateEmittedWithCopySemantics` — `ifInState: Opt.some`
  on the `Email/copy` arg surface (NOT `destroyFromIfInState`).
- `addEmailCopyAndDestroyEmitsTrue` — `onSuccessDestroyOriginal: true`
  emitted; return shape is `(RequestBuilder, EmailCopyHandles)`. The
  `EmailCopyHandles.destroy` field is of type
  `NameBoundHandle[EmailSetResponse]` — not `ResponseHandle`. This
  is an RFC 8620 §5.4 dispatch refinement: the implicit Email/set
  response shares a call-id with the parent Email/copy, so the
  destroy handle carries `methodName: mnEmailSet` to disambiguate.
  The block should include an assertion that
  `handles.destroy.methodName == mnEmailSet` and that
  `handles.destroy.callId == handles.copy.callId()`.
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
  shared method-call-id (the first with `name == "Email/copy"`, the
  second with `name == "Email/set"`); `getBoth` returns
  `Ok(EmailCopyResults)` with both fields populated;
  `accountId`/`newState` survive intact across both. The internal
  dispatch sequence is `resp.get(handles.copy)` (uses the default
  `ResponseHandle` overload at `dispatch.nim:185`) followed by
  `resp.get(handles.destroy)` (uses the `NameBoundHandle` overload
  at `dispatch.nim:219` which call-id AND method-name filters).
  F1 §5.4's earlier `resp.extract(…)` phrasing was superseded
  during implementation; the shipped API uses `get`.
- `getBothShortCircuitOnCopyError` — table-driven across the seven
  applicable `MethodErrorType` variants (`metStateMismatch`,
  `metFromAccountNotFound`, `metFromAccountNotSupportedByMethod`,
  `metServerFail`, `metForbidden`, `metAccountNotFound`,
  `metAccountReadOnly`) using the native `for variant in
  MethodErrorType:` idiom (precedent: `tests/unit/terrors.nim:428`).
  Mirrors `getBothQueryGetMethodError` at `tconvenience.nim`.
- `getBothShortCircuitOnDestroyMissing` — copy invocation present,
  implicit destroy invocation absent (zero invocations with
  `name == "Email/set"` sharing the call-id); second `?` in
  `getBoth` body returns `Err(MethodError{rawType: "serverFail"})`
  carrying the description
  `"no Email/set response for call ID <cid>"` (see
  `dispatch.nim:161-167`). Pin F12.
- `getBothShortCircuitOnDestroyError` — copy succeeded; destroy
  invocation present but with `name == "error"` and a typed
  MethodError payload; `getBoth` surfaces destroy's error on the
  Err rail with the server-provided `errorType`.
- `addMailboxSetTypedUpdate` — construct a valid `MailboxUpdateSet`
  via `initMailboxUpdateSet(@[setName("Renamed")]).get()`, wrap in a
  `Table[Id, MailboxUpdateSet]`, pass via
  `update: Opt.some(tbl)`, and assert the wire `args["update"]
  [string(id)]["name"].getStr("") == "Renamed"`. Pins that
  `addMailboxSet`'s migrated signature (mail_builders.nim:200-235)
  routes through `toJson(MailboxUpdateSet)` correctly.
- `addMailboxSetEmptyUpdateSetRejectedAtConstruction` —
  `initMailboxUpdateSet(@[])` returns `Err`, so the builder is never
  invoked with an empty set. Construct-level pin; no builder call.

`tests/protocol/tmail_methods.nim` — **PARTIALLY SHIPPED.** The
shipped `B. VacationResponse/set` group at lines 89–151 covers
`vacationSetInvocationName`, `vacationSetCapability`,
`vacationSetSingletonInUpdate`, `vacationSetOmitsCreateDestroy`,
`vacationSetWithIfInState`, `vacationSetOmitsIfInStateWhenNone`, and
`vacationSetPatchValues` — the typed-update migration is exercised
throughout via `minimalVacUpdate = initVacationResponseUpdateSet(
@[setIsEnabled(true)]).get()`. `addEmailImport` blocks are
**TO-ADD**:

- `addEmailImportInvocationName` — invocation name is `Email/import`;
  capability is `"urn:ietf:params:jmap:mail"`; phantom-typed handle
  carries `EmailImportResponse`.
- `addEmailImportEmailsPassthrough` — construct a
  `NonEmptyEmailImportMap` with one entry via
  `initNonEmptyEmailImportMap(@[(cid, item)]).get()`; assert
  `args["emails"][string(cid)]["blobId"].getStr("")` matches the
  input blob id.
- `addEmailImportIfInStateSomePassthrough` — `ifInState: Opt.some`
  emits `"ifInState": "<state>"`.
- `addEmailImportIfInStateNoneOmitted` — no key emitted when
  `Opt.none` (no `null`).

`addVacationResponseSetEmptyRejectedAtConstruction` is **not added**
at the builder-test layer because the builder signature
(mail_methods.nim:54-72) demands `update: VacationResponseUpdateSet`
(non-Opt); the empty-rejection invariant lives entirely on the
smart constructor and is already tested at
`tests/unit/mail/tvacation.nim:37-43`. Adding a duplicate at the
builder layer would exercise the same failure at two layers and
violate DRY.

`tests/protocol/tmail_method_errors.nim` (**TO-ADD** new file) —
method-level error decode coverage, per §8.11 matrix:

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

`tests/unit/mail/tmailbox.nim` — **PARTIALLY SHIPPED.** The §E
block group at lines 124–176 covers the set-level invariants for
`MailboxUpdateSet`. What remains **TO-ADD** is per-variant setter
shape coverage on `MailboxUpdate` itself: five blocks
(`setNameConstructsCorrectKind`,
`setParentIdNoneConstructsCorrectKind`,
`setParentIdSomeConstructsCorrectKind`,
`setRoleConstructsCorrectKind`,
`setSortOrderConstructsCorrectKind`,
`setIsSubscribedConstructsCorrectKind`) — six in total, accounting
for the `Opt[Id]` payload requiring both Some/None cases. Pattern
mirrors the three shipped `VacationResponseUpdate` setter blocks in
`tvacation.nim:19-33`.

`tests/serde/mail/tserde_mailbox.nim` — **TO-ADD** append cases for
`toJson(MailboxUpdate)` (five variants) and
`toJson(MailboxUpdateSet)` (flattening to a top-level JSON object,
one key per variant — analogous to `toJson(EmailUpdateSet)` but
whole-value-replace only). Critical nullable-wire cases:

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

`tests/unit/mail/tvacation.nim` — **PARTIALLY SHIPPED.** See §8.3
row. The three shipped setter blocks
(`setIsEnabledConstructsCorrectKind`,
`setFromDateConstructsCorrectKind`, `setSubjectClearsWhenNone`)
sample the three payload-shape axes (`bool`, `Opt[UTCDate]`,
`Opt[string]`). **TO-ADD** is exhaustion across all six
`VacationResponseUpdateVariantKind` variants for coverage
completeness plus the serde-wire duplicate-target tests if
reviewers demand full variant-fold symmetry with
`tmailbox.nim`'s `initMailboxUpdateSet` scope.

`tests/serde/mail/tserde_vacation.nim` — **TO-ADD** append cases
for `toJson(VacationResponseUpdate)` (six variants) and
`toJson(VacationResponseUpdateSet)` (flattening). Nullable-wire
pins for `vruSetFromDate`, `vruSetToDate`, `vruSetSubject`,
`vruSetTextBody`, `vruSetHtmlBody` (each: `Opt.none → JSON null`,
`Opt.some → value`). Note: `toJson(VacationResponseUpdate)` has the
same `(string, JsonNode)` tuple return shape as
`toJson(MailboxUpdate)`; blocks assert tuple components separately
with `assertEq pair[0], "expectedKey"` + `assertEq pair[1], expectedNode`.

### 8.5. PatchObject migration (historical)

**Implementation reality — fully superseded by the F1 landing.**
F1 §1.5 prescribed demoting `PatchObject` (drop the `*` export,
keep the type internal). The shipped implementation went one step
further and **removed `PatchObject` from the codebase entirely**:

```text
$ grep -r 'PatchObject' src/ tests/
(no matches)
```

`src/jmap_client/framework.nim` no longer declares `PatchObject`;
none of the seventeen test files previously enumerated in this
section still reference it. The entire migration table in the
prior draft of this section is therefore obsolete — every
strategy-1 and strategy-2 allocation has been superseded by
outright removal. `git log --follow -- src/jmap_client/framework.nim`
plus `git log -S PatchObject` are the durable audit trails.

**Gate for regression.** Because the symbol no longer exists, an
`assertNotCompiles((let _: PatchObject = default(PatchObject)))`
gate would be trivially true and carry no information. The
equivalent regression protection is that any reintroduction of the
type would have to surface as a new `src/` file change reviewed on
its own merits; a grep in CI (`! grep -r 'PatchObject' src/`) is
the minimal mechanical check. Consistent with F19's "wrong-thing
hard" principle, but pushed one level further: the wrong thing is
not merely hard, it is impossible without re-landing the removed
type.

#### 8.5.1. Generator and fixture migration debt — RESOLVED

The `genPatchObject`, `genPatchPath`, and `makeSetResponseJson`
items were flagged for post-migration relocation in the earlier
draft of §8.5.2. With `PatchObject` absent entirely:

- `genPatchObject` and `genPatchPath` do not exist in the shipped
  `tests/mproperty.nim`. If a future part needs a wire-patch
  generator, it must be reintroduced scoped to its consumer.
- `makeSetResponseJson` (if it existed) is not required by any
  Part F test — every Email-side response test uses the typed
  factories prescribed in §8.6.1.

### 8.6. Test infrastructure additions

**Shipped state as of the F1 code merge:**

- `tests/mfixtures.nim` — contains **zero** F1-type factories
  (`makeEmailUpdate*`, `makeEmailCopyItem`, etc.). The three shipped
  test files that exercise F1 types (`temail.nim`, `tmailbox.nim`,
  `tvacation.nim`) construct their fixtures inline using the public
  smart constructors (`parseCreationId`, `parseId`,
  `parseNonEmptyMailboxIdSet`, `initEmailImportItem`,
  `initMailboxUpdateSet`, `initVacationResponseUpdateSet`). Whether
  the TO-ADD files below introduce `make*` factories is a scale-
  threshold decision: when a construction recipe is repeated across
  three or more `block`s, extract it; otherwise inline.
- `tests/mproperty.nim` — contains **zero** F1-type generators. The
  property file (§8.2.1) is not yet written; when it is, generators
  land there alongside the existing `genEmailBlueprint` family.
- `tests/massertions.nim` — contains the generic `assertOk`,
  `assertErr`, `assertEq`, `assertLen`, `assertNone`, `assertSomeEq`
  helpers used by the shipped F1 test blocks. No F1-specific
  assertion template is yet required: the shipped tests use
  combinations of the generic helpers (e.g., `assertErr res` +
  `assertLen res.error, 1` + `assertEq res.error[0].message, "..."`)
  for the exact-count pattern that the earlier draft of §8.6.4
  packaged into `assertUpdateSetErrCount`.

#### 8.6.1. Reuse-mapping table

Each new factory / generator / template lists its closest existing
precedent so the implementation PR follows the established pattern
rather than reinventing it. The table is advisory — some rows may
not need materialising at all if callers prefer inline construction
(see preceding paragraph).

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
| `assertUpdateSetErrCount(expr, n: int)` (optional; exact-count counterpart to L-3) | `assertBlueprintErrCount` | `massertions.nim` |
| `genJsonNodeAdversarial(rng, trial)` (NEW; generates JNull/JInt/JBool/JArray/JObject-with-wrong-keys for adversarial response-decode) | `genSetErrorAdversarialExtras` (trial-biased extras attack) | (new in `mproperty.nim`) |
| `genEmailUpdateSetCastBypass(rng, trial)` (NEW; generates `cast[EmailUpdateSet]`-shaped malformed sequences for §8.2.3 "Cast-bypass behaviour") | `genBlueprintErrorTrigger` (J-11 targeted-invariant) | `mproperty.nim` |
| `genKeywordEscapeAdversarialPair(rng, trial)` (NEW; generates adversarial keyword pairs that collide under a swapped-replace-order bug — `("a/b", "a~1b")`, `("~", "~0")`, `("/", "~1")`) | `genBlueprintErrorTrigger` (trial-biased enumeration) | `mproperty.nim` |

The previously listed `assertUpdateSetErr(…, violations: set[EmailUpdateSetViolation])`
row has been **removed**. `EmailUpdateSetViolation` was a fictional
enum in an earlier draft of F2; the shipped `ValidationError` shape
is three plain strings (§8.3), and tests discriminate via
`error[0].message == "..."` literals. A dedicated assertion helper
that consumed a hypothetical violation-set enum would require
synthesising an enum the production code does not emit.

The previously listed `assertCopyHandleShortCircuit(resp, handles, expected: MethodErrorType)`
helper is also **removed**. Short-circuit tests drive through the
shipped `getBoth(EmailCopyHandles)` directly per §8.4, using
`assertErr` + `assertEq err.errorType, <variant>` inline — the
helper would paper over the two-`?` structure that the test is
intended to exercise.

**Native enum iteration over `forAllVariants` combinator.** Where
§8.4 and §8.11 exercise every `MethodErrorType` or `SetErrorType`
variant, the idiom is the native `for variant in T:` loop
(precedent: `tests/unit/terrors.nim:428` iterates `for variant in
MethodErrorType:`). No `forAllVariants[T]` combinator is introduced —
it would add a macro layer over the standard-library iteration that
already compiles to the same thing, and test readers are better
served by the direct idiom. The pattern is specifically mandated
for the §8.4 `getBothShortCircuitOnCopyError` and §8.11 SetError
matrix cells. It is **not** mandated for the duplicate-target
coverage in `tvacation.nim` and `tmailbox.nim` — the shipped
blocks there (lines 124–176 and 37–88 respectively) sample a
representative pair of variants (`muSetName`/`muSetParentId`,
`vruSetIsEnabled`/`vruSetSubject`) rather than folding over the
full enum. Full-enum exhaustion is optional per-variant expansion
if reviewers demand it.

#### 8.6.2. Equality-helper classification

**Shipped state.** The Part F unit tests currently ship **no
custom equality helpers**. All comparisons are done field-wise via
`assertEq` against payload fields directly (see
`tests/unit/mail/tvacation.nim:19-33` for the setter-shape checks
— each block asserts `u.kind` + a specific payload field, no
whole-object `==`). The classification table below remains valid
as a guide if later TO-ADD tests hit a genuine case where
field-wise becomes verbose; at the shipped scale the inline style
is the strict winner.

Nim's compiler-derived `==` on case objects and plain objects is
structural for fields whose types themselves carry `==`. Only one
mail type, `KeywordSet`, deliberately omits borrowed `==` (via
`defineHashSetDistinctOps` at `validation.nim` — the base
template omits `==` for read-only model sets; see that template's
docstring for the domain rationale). `NonEmptyMailboxIdSet` uses
`defineNonEmptyHashSetDistinctOps`, which **does** borrow `==` —
creation-context sets opt into the richer op set. Custom helpers
are only ever needed where derived equality cannot reach
`KeywordSet`.

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

#### 8.6.4. Optional `massertions.nim` template

The shipped F1 tests inline the exact-count pattern via
`assertErr res` + `assertLen res.error, <n>` (see
`tests/unit/mail/tmailbox.nim:142-148` and analogous sites), which
reads cleanly and requires no new helper. A packaged
`assertUpdateSetErrCount` template may be added if reviewers find
the inline pattern noisy at the scale the §8.10 stress blocks
reach, but it is **not required**:

```nim
template assertUpdateSetErrCount*(expr: untyped, n: int) =
  ## Optional — exact-count assertion on the accumulated error rail.
  ## The shipped style uses inline ``assertLen res.error, n``.
  let res = expr
  assertErr res
  assertLen res.error, n
```

If added, the precedent is `assertBlueprintErrCount` in the Part E
scope. The decision can be deferred until §8.10 adopts its final
shape — nothing in the shipped `tests/massertions.nim` currently
blocks the inline pattern.

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

**Overlap policy — committed, aligned to shipped code.** The
implementation emits **Class 2 only** for these overlap shapes
(the tighter, more-informative classification). The shipped
`samePathConflicts` at `src/jmap_client/mail/email_update.nim:204-224`
branches the decision cleanly: if the two updates at the same path
have `kind == op.kind` the emitted conflict is `ckDuplicatePath`
(Class 1); if the kinds differ, the emitted conflict is
`ckOppositeOps` (Class 2). The two paths are mutually exclusive —
never both. Rationale: Class 2 strictly implies Class 1 for these
shape pairs (same sub-path plus opposite operation is a superset
condition), so reporting both would produce redundant output a
consumer must deduplicate.

**`class1And2Overlap` block — shape.** `ValidationError` (declared
in `src/jmap_client/validation.nim`) has **three fields**:
`typeName: string`, `message: string`, `value: string`. There is no
`classification` enum field; discrimination between Class 1 / 2 / 3
is done at the wire error-message text layer. The unit assertion
therefore reads:

```nim
let seen = parseKeyword("$seen").get()
let es = initEmailUpdateSet(@[
  addKeyword(seen),
  removeKeyword(seen),
])
assertErr es
assertLen es.error, 1
assertEq es.error[0].typeName, "EmailUpdateSet"
assertEq es.error[0].message, "opposite operations on same sub-path"
assertEq es.error[0].value, "keywords/$seen"
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

Pins F1 §3.2.5's `jsonPointerEscape` contract. Table-driven cases
in `tests/serde/mail/tserde_email_update.nim` (TO-ADD);
bijectivity quantified in property group D (§8.2.1).

**Implementation reality — `jsonPointerEscape` is private.** The
helper at `src/jmap_client/mail/serde_email_update.nim:22` has no
`*` export marker: it is called only from within that same module
by the six-branch `toJson(EmailUpdate)` at lines 28–46. Tests
therefore cannot import `jsonPointerEscape` directly; each block
drives through the public `toJson(EmailUpdate)` path, supplying an
input via `addKeyword(parseKeyword("<raw>").get())` (or
`removeKeyword(...)` / `setKeywords(...)` as appropriate) and
asserting the `.0` (string) component of the returned tuple. This
keeps the escape helper legitimately module-private per F1's "one
source of truth" rule — the only reader of `jsonPointerEscape` is
the six-branch dispatcher adjacent to it.

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

With `PatchObject` absent from the codebase (§8.5), the earlier
"Layer 1 baseline" framing (in which a raw wire-patch type stored
keys verbatim and escaping lived entirely in the serde layer above
it) no longer applies. Escaping is now an internal detail of the
single `toJson(EmailUpdate)` boundary at
`src/jmap_client/mail/serde_email_update.nim:22-46`; the §8.8
blocks collectively establish the entire encoding contract at that
one site.

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
`tests/protocol/tmail_method_errors.nim` (**TO-ADD** new file, per
§8.4).

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

| F1 § | Promise | Test file | Test name / evidence |
|------|---------|-----------|----------------------|
| §1.5.3 | `PatchObject` absent from public API | `! grep -r PatchObject src/` in CI | Mechanical grep; §8.5 explains why an `assertNotCompiles`-style gate would be trivially true. |
| §1.6 | Creation types have no public `fromJson` | `grep -L 'fromJson' src/jmap_client/mail/serde_email_update.nim` + analogous | Mechanical grep across the four creation-side serde modules. Optional compile-time pin described in §8.2.2 "Optional enhancement". |
| §2.1 | `EmailCreatedItem` refuses partial construction | `tests/serde/mail/tserde_email_set_response.nim` (TO-ADD) | `emailCreatedItemMissingSizeRejected` |
| §2.2 | `EmailCopyResponse` has no `updated`/`destroyed` fields | `tests/serde/mail/tserde_email_copy.nim` (TO-ADD) | `emailCopyResponseHasNoUpdatedField` (`assertNotCompiles` block) |
| §2.3 | `UpdatedEntry` distinguishes `{}` from `null` | `tests/serde/mail/tserde_email_set_response.nim` (TO-ADD) | `updatedEntryNullVsEmptyDistinct` |
| §2.3 | `UpdatedEntry` rejects non-object/non-null kinds | `tests/stress/tadversarial_mail_f.nim` (per §8.9 rows) | `updatedEntryRejectsString`, `updatedEntryRejectsNumber`, `updatedEntryRejectsArray`, `updatedEntryRejectsBool` |
| §2.3 | `UpdatedEntry` round-trip preserves `null` vs `{}` | `tests/stress/tadversarial_mail_f.nim` | `updatedEntryRoundTripPreservesDistinction` |
| §2.5 | `EmailSetResponse.updated` three-state (absent/null/{}) | `tests/serde/mail/tserde_email_set_response.nim` | `updatedTopLevelAbsent`, `updatedTopLevelNull`, `updatedTopLevelEmptyObject` |
| §2.5 | `EmailSetResponse.destroyed` three-state | `tests/serde/mail/tserde_email_set_response.nim` | `destroyedAbsent`, `destroyedEmptyArray`, `destroyedTwoElement` |
| §3.2.1 | `EmailUpdateVariantKind` exhaustiveness witnessed | Production code — `shape` / `classify` / `toValidationError` / `toJson(EmailUpdate)` each `case` over every variant with no `else` (`email_update.nim:163-242`, `serde_email_update.nim:28-46`) | Compiler-enforced at every build; no dedicated test required. |
| §3.2.1 | Six primitive + five convenience constructors — all declared | `tests/compile/tcompile_mail_f_public_surface.nim:42-54` | **SHIPPED.** `declared()` assertions for each constructor name; any removal breaks the compile-only file. Shape / payload behaviour covered by `temail_update.nim` (TO-ADD, §8.3 row). |
| §3.2.3.1 | `moveToMailbox` emits `euSetMailboxIds`, NOT `euAddToMailbox` | `tests/serde/mail/tserde_email_update.nim` (TO-ADD) | `moveToMailboxWireIsSetMailboxIds` (positive + negative pair) |
| §3.2.3.1 | `moveToMailbox(id) ≡ setMailboxIds(...)` quantified over `Id` | `tests/property/tprop_mail_f.nim` (TO-ADD) | property group F |
| §3.2.4 Class 1 | All 6 duplicate-target shapes rejected | `tests/unit/mail/temail_update_set.nim` (TO-ADD) | per §8.7.1 (6 named blocks, one per row); each asserts `error[0].message == "duplicate target path"` |
| §3.2.4 Class 2 | Both opposite-op shapes rejected | `tests/unit/mail/temail_update_set.nim` | `class2KeywordOpposite`, `class2MailboxOpposite`; each asserts `error[0].message == "opposite operations on same sub-path"` |
| §3.2.4 Class 3 | All 4 sub-path × full-replace shapes rejected | `tests/unit/mail/temail_update_set.nim` | per §8.7.3 (4 named blocks); each asserts `error[0].message == "sub-path operation alongside full-replace on same parent"` |
| §3.2.4 Class 3 | Payload-irrelevance (empty vs non-empty setKeywords) | `tests/stress/tadversarial_mail_f.nim` (TO-ADD) | `class3PayloadIrrelevantEmptySetKeywords`, `class3PayloadIrrelevantNonEmptySetKeywords` |
| §3.2.4 Independent | 4 accepted combinations | `tests/unit/mail/temail_update_set.nim` | per §8.7.4 (4 mandatory positive `assertOk` blocks) |
| §3.2.4 Accumulation | One `ValidationError` per detected conflict | `tests/unit/mail/temail_update_set.nim` | `accumulateMixedClasses` (inline `assertLen res.error, 3`); `accumulateThreeClass3`; `accumulateEmptyAlone` (folds into the empty block) |
| §3.2.4 Class 1+2 overlap | Pin reported class = Class 2 (committed policy) | `tests/unit/mail/temail_update_set.nim` | `class1And2Overlap`; asserts `error[0].message == "opposite operations on same sub-path"` (no `classification` field exists on `ValidationError` — the `message` string is the discriminator) |
| §3.2.4 | Single-pass algorithm doesn't bail after fixed prefix | `tests/stress/tadversarial_mail_f.nim` (TO-ADD) | `emailUpdateSetLatePositionConflict` |
| §3.2.4 | Scale — anchored & unanchored conflict patterns | `tests/stress/tadversarial_mail_f.nim` | `emailUpdateSet10kClass1Anchored`, `emailUpdateSet10kClass1NoAnchor`, `emailUpdateSet100kWallClock` |
| §3.2.4 | Cast-bypass does NOT add post-hoc validation | `tests/stress/tadversarial_mail_f.nim` | `castBypassDocumentsNoPostHocValidation`, `castBypassEmptyAccepted` |
| §3.2.5 | RFC 6901 `~ → ~0`, `/ → ~1`, escape order matters | `tests/serde/mail/tserde_email_update.nim` (TO-ADD) | per §8.8 (15 named blocks driven through `toJson(addKeyword(parseKeyword("<raw>").get()))` since `jsonPointerEscape` is module-private) |
| §3.2.5 | Pointer escape bijectivity | `tests/property/tprop_mail_f.nim` (TO-ADD) | property group D |
| §3.2.5 | `Keyword` charset includes `~` and `/` | `tests/unit/mail/tkeyword.nim` append | `keywordWithTildeAccepted`, `keywordWithSlashAccepted`, `keywordWithBothAccepted` (TO-ADD) |
| §3.3 | `MailboxUpdateSet` duplicate-target rejection | `tests/unit/mail/tmailbox.nim:124-176` | **SHIPPED.** Five blocks: `initMailboxUpdateSetEmpty`, `...SingleValid`, `...TwoSameKind`, `...ThreeSameKind`, `...TwoDistinctRepeated`. Per-variant fold across all five `MailboxUpdateVariantKind` values is TO-ADD. |
| §3.3 | `setRole(Opt.none) → JSON null` (clear-role) | `tests/serde/mail/tserde_mailbox.nim` (TO-ADD) | `setRoleNoneEmitsJsonNull` |
| §3.3 | `setRole(Opt.some(role)) → JSON string` | `tests/serde/mail/tserde_mailbox.nim` | `setRoleSomeEmitsString` |
| §3.3 | `setParentId(Opt.none) → JSON null` (reparent-to-top) | `tests/serde/mail/tserde_mailbox.nim` | `setParentIdNoneEmitsJsonNull` |
| §3.3 | `setParentId(Opt.some(id)) → JSON string` | `tests/serde/mail/tserde_mailbox.nim` | `setParentIdSomeEmitsString` |
| §3.4 | `VacationResponseUpdateSet` duplicate-target rejection | `tests/unit/mail/tvacation.nim:37-88` | **SHIPPED.** Five blocks: `initVacationResponseUpdateSetEmpty`, `...SingleValid`, `...TwoSameKind`, `...ThreeSameKind`, `...TwoDistinctRepeated`. Full six-variant fold is TO-ADD. |
| §3.4 | `VacationResponseUpdate` nullable-field wire behaviour | `tests/serde/mail/tserde_vacation.nim` (TO-ADD) | `vruSetFromDateNoneEmitsNull`, `vruSetToDateNoneEmitsNull`, `vruSetSubjectNoneEmitsNull`, `vruSetTextBodyNoneEmitsNull`, `vruSetHtmlBodyNoneEmitsNull` (per-field Opt.none pin) |
| §4.1 | `addEmailSet` full invocation | `tests/protocol/tmail_builders.nim` append (TO-ADD) | `addEmailSetFullInvocation` |
| §4.1 | `addEmailSet` minimal (all `Opt.none`) | `tests/protocol/tmail_builders.nim` append | `addEmailSetMinimalAccountIdOnly` |
| §4.1 | `addEmailSet` `ifInState` wire semantics | `tests/protocol/tmail_builders.nim` append | `addEmailSetIfInStateEmitted`, `addEmailSetIfInStateOmittedWhenNone` |
| §4.1 | `addEmailSet` typed-update flows through | `tests/protocol/tmail_builders.nim` append | `addEmailSetTypedUpdate` (pins `toJson(EmailUpdateSet)` threading) |
| §4.2 | `addEmailImport` invocation + capability + phantom-typed response | `tests/protocol/tmail_methods.nim` append (TO-ADD) | `addEmailImportInvocationName` |
| §4.2 | `addEmailImport` `emails: NonEmptyEmailImportMap` flows through | `tests/protocol/tmail_methods.nim` append | `addEmailImportEmailsPassthrough` |
| §4.2 | `addEmailImport` `ifInState` pass-through | `tests/protocol/tmail_methods.nim` append | `addEmailImportIfInStateSomePassthrough`, `addEmailImportIfInStateNoneOmitted` |
| §5.3 | `addEmailCopyAndDestroy` emits `onSuccessDestroyOriginal: true`; all three state params | `tests/protocol/tmail_builders.nim` append | `addEmailCopyAndDestroyEmitsTrue`, `addEmailCopyAndDestroyDestroyFromIfInStateSome`, `addEmailCopyAndDestroyDestroyFromIfInStateNone`, `addEmailCopyAndDestroyAllStateParamsSome` |
| §5.3 | `addEmailCopyAndDestroy` destroy handle carries `NameBoundHandle` with `methodName: mnEmailSet` | `tests/protocol/tmail_builders.nim` append | `addEmailCopyAndDestroyEmitsTrue` assertion on `handles.destroy.methodName == mnEmailSet` and `handles.destroy.callId == handles.copy.callId()` |
| §5.3 | `addEmailCopy` (simple) has no `onSuccessDestroyOriginal` | `tests/protocol/tmail_builders.nim` append | `addEmailCopyPhantomType`, `addEmailCopyIfInStateEmittedWithCopySemantics` |
| §5.4 | `getBoth` happy path + short-circuits (copy error, destroy missing, destroy error) | `tests/protocol/tmail_builders.nim` append | `getBothCopyAndDestroyHappyPath`, `getBothShortCircuitOnCopyError` (table-driven via `for variant in MethodErrorType:`), `getBothShortCircuitOnDestroyMissing`, `getBothShortCircuitOnDestroyError`. Internal dispatch: `resp.get(handles.copy)` + `resp.get(handles.destroy)` per the shipped `getBoth` body in `mail_builders.nim:456-466`. |
| §5.4 | `getBoth` adversarial (method-call-id mismatch, empty createResults) | `tests/stress/tadversarial_mail_f.nim` | (three adversarial scenarios enumerated in §8.2.3 "`getBoth(EmailCopyHandles)` adversarial") |
| §6.2 | `NonEmptyEmailImportMap` invariants | `tests/unit/mail/temail.nim:59-125` | **SHIPPED.** Five blocks (see §8.3 row). The earlier-drafted `nonEmptyImportMapPreservesInsertionOrder` and `nonEmptyImportMapDeterministicErrorOrder` blocks are **not in the shipped file** — the shipped `initNonEmptyEmailImportMapTwoDistinctRepeated` uses set-membership verification so it does not depend on error ordering, sidestepping the deterministic-order concern entirely. |
| §6.2 | Scale — 10k entries with duplicate at end | `tests/stress/tadversarial_mail_f.nim` (TO-ADD) | `nonEmptyImportMap10kWithDupAtEnd` |
| §6.1 | `EmailCopyItem` mailbox-override type-level rejection | `tests/unit/mail/temail_copy_item.nim` (TO-ADD) | `copyItemTypeRejectsEmptyMailboxIdSet`, `copyItemTypeRejectsNonEmptyMailboxIdSetWrongDistinct` |
| §6.1 | `EmailCopyItem` serde (minimal / full override) | `tests/serde/mail/tserde_email_copy.nim` (TO-ADD) | `emailCopyItemMinimalEmitsIdOnly`, `emailCopyItemFullOverrideEmitsThreeKeys` |
| §6.3 | `EmailImportItem` required `mailboxIds`, optional `keywords` | `tests/unit/mail/temail_import_item.nim` (TO-ADD) | `importItemRejectsOptNoneMailboxIds`, `importItemKeywordsThreeStates` |
| §7.1 | `SetError.extras` extractors work via Email-method `createResults` | `tests/stress/tadversarial_mail_f.nim` | `emailSetExtrasReachableFromCreateResults`, `emailCopyExtrasReachableFromCreateResults`, `emailImportExtrasReachableFromCreateResults` |
| §7.2 | Generic `SetError` applicability matrix | `tests/protocol/tmail_method_errors.nim` (TO-ADD) | per §8.11 cell (one named test per method × operation for ✓ cells, one `singleton` negative test per method for ✗ cell) |
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

The compile-only smoke (`tests/compile/tcompile_mail_f_public_surface.nim`,
**SHIPPED** — see §8.2.2) fails loudly at the `static:` block if
any new public symbol is not re-exported through
`src/jmap_client.nim`'s cascade. Variant-kind exhaustiveness is
witnessed by the internal production `case` sites in
`src/jmap_client/mail/email_update.nim` on every build (no
dedicated probe needed — see §8.2.2). `PatchObject` regression is
prevented by the symbol's outright absence (§8.5) — a CI grep
(`! grep -r 'PatchObject' src/`) is the minimal mechanical check.

Property tests in `tprop_mail_f.nim` (TO-ADD) will cover the
accumulating-constructor totality (B), the duplicate-key invariant
for `NonEmptyEmailImportMap` (C), the RFC 6901 escape bijectivity
(D), the `toJson(EmailUpdateSet)` post-condition (E), and the
`moveToMailbox ≡ setMailboxIds` quantification (F). Coverage
matrix §8.12 is the single inspection point for "is every F1
promise pinned by a test?" — the **SHIPPED** tags in that table
are the authoritative list of what is already green against the
F1 implementation.

---

*End of Part F2 design document.*
