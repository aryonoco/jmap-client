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

1. **Unit** — per-type smart-constructor invariants and serde round-trip
   for every new type. Includes embedded `assertNotCompiles` scenarios
   where type-level guarantees warrant defence.
2. **Serde** — `toJson`/`fromJson` output shape per field, variant, and
   RFC constraint, plus the typed-algebra → wire-patch translation.
3. **Property-based** — a single `tprop_mail_f.nim` file covering
   conflict-class exhaustiveness, variant-equality, and compound-handle
   short-circuit properties.
4. **Adversarial** — a single `tadversarial_mail_f.nim` file covering
   malformed server responses, `SetError.extras` field-type
   adversarial content, and conflict-algebra corner cases.
5. **Compile-time reachability** — a single `tmail_f_reexport.nim`
   file (action: `"compile"`) proving every new public symbol is
   reachable through the top-level `jmap_client` re-export chain.

Test-infrastructure additions (`mfixtures.nim` factories,
`mproperty.nim` generators, `massertions.nim` assertion templates,
equality helpers) are described at a summary level in §8.6. Full
per-factory enumeration is left to the implementation PR —
Part E established the 7-step fixture-protocol and the naming
convention; Part F follows both mechanically without restating.

### 8.2. New test files — part-lettered

Following Part E's convention (F17) for tests whose scope spans multiple
types within the Part, the lettered-by-part files are:

| File | Concerns |
|------|----------|
| `tests/property/tprop_mail_f.nim` | Five property groups: (A) `EmailUpdateSet` conflict detection — exhaustive enumeration of Classes 1/2/3 (§3.2.4) with accumulating-error-report verification; (B) `EmailUpdateSet` empty-input rejection (F22) as a universal property; (C) `NonEmptyEmailImportMap` invariants — empty map rejected, duplicate CreationId rejected, both accumulated in a single pass; (D) `EmailUpdate` variant-equality — `markRead() == addKeyword(kwSeen)` and the other four domain/protocol equivalences; (E) Compound-handle short-circuit — `getBoth(EmailCopyHandles)` on a method-errored copy response returns the copy's `MethodError` on the err-rail without inspecting `destroy`. |
| `tests/compliance/tmail_f_reexport.nim` | Compile-time smoke test (`action: "compile"`). Proves every new public symbol is reachable through the top-level `import jmap_client` re-export chain. Covered symbols: `EmailUpdate`, `EmailUpdateVariantKind`, `EmailUpdateSet`, `MailboxUpdate`, `MailboxUpdateSet`, `VacationResponseUpdate`, `VacationResponseUpdateSet`, `EmailCreatedItem`, `EmailSetResponse`, `EmailCopyResponse`, `EmailImportResponse`, `EmailCopyItem`, `EmailImportItem`, `NonEmptyEmailImportMap`, `EmailCopyHandles`, `EmailCopyResults`, plus all six protocol-primitive + five domain-named EmailUpdate constructors, all three update-set smart constructors, and `getBoth(EmailCopyHandles)`. Pattern follows `tests/compliance/tmail_e_reexport.nim`. |
| `tests/stress/tadversarial_mail_f.nim` | Adversarial scenarios. Malformed server responses: non-object `created` entries, missing `EmailCreatedItem` fields (`id`, `blobId`, `threadId`, `size`), wrong types (string `size`, integer `id`), extra unknown fields. Malformed `SetError.extras` content: non-array `notFoundBlobIds`, non-integer `maxSize`, non-string elements in `invalidRecipientAddresses`. Conflict-algebra corner cases: `euSetKeywords(empty)` alongside `euAddKeyword(k)` (Class 3 regardless of set emptiness — the discriminator is the target path, not the payload); `euSetMailboxIds(ids)` alongside `euAddToMailbox(id1)` where `id1 in ids` (still Class 3, not Class 1). |

### 8.3. New per-concept test files

Unit — `tests/unit/mail/`:

| File | Concerns |
|------|----------|
| `temail_update.nim` | `EmailUpdate` variant construction; six protocol-primitive constructors produce correct `kind` + payload; five domain-named constructors produce structurally-equal values to their primitive counterparts (variant equality, not pointer identity); `moveToMailbox(id)` emits `euSetMailboxIds` with a one-element `NonEmptyMailboxIdSet` (F21 wire-semantics verification). |
| `temail_update_set.nim` | `initEmailUpdateSet` behaviour: (1) empty input rejected (F22); (2) Class 1 duplicate target path rejected (each target path variant); (3) Class 2 opposite ops rejected; (4) Class 3 sub-path + full-replace rejected; (5) independent cases (§3.2.4's accepted combinations) pass; (6) accumulation — multiple simultaneous violations produce multiple `ValidationError` entries. |
| `tnon_empty_email_import_map.nim` | `initNonEmptyEmailImportMap` behaviour: (1) empty input rejected; (2) duplicate CreationId rejected; (3) both accumulated in a single failing call; (4) valid input produces a `NonEmptyEmailImportMap`. |
| `temail_copy_item.nim` | `initEmailCopyItem` behaviour: (1) minimal construction (id only) returns an `EmailCopyItem` with three `Opt.none` overrides; (2) full override construction (all three Opt fields populated) produces a value with all three `Opt.some`; (3) `mailboxIds` typed `Opt[NonEmptyMailboxIdSet]` — `Opt.some(emptySet)` is unconstructible at the type level (verified via `assertNotCompiles`). |
| `temail_import_item.nim` | `initEmailImportItem` behaviour: (1) minimal construction returns an `EmailImportItem` with two `Opt.none` fields; (2) `mailboxIds` typed non-`Opt` `NonEmptyMailboxIdSet` — no `Opt.none` form exists for the required field; (3) `keywords` round-trips through `Opt.none` / `Opt.some(empty)` / `Opt.some(non-empty)`. |
| `tvacation.nim` | **NEW unit file** (the existing `tserde_vacation.nim` is serde-only; no unit counterpart currently exists). Covers `VacationResponse` smart-constructor behaviour for all six fields; `VacationResponseUpdate` variant construction; `initVacationResponseUpdateSet` rejection of empty input + duplicate target properties. |

Serde — `tests/serde/mail/`:

| File | Concerns |
|------|----------|
| `tserde_email_update.nim` | `toJson(EmailUpdate)` emits the correct `(key, value)` pair for each variant (six cases); `toJson(EmailUpdateSet)` flattens to a JSON object with distinct keys; no keys with duplicate paths appear (type-level guarantee, verified at wire). |
| `tserde_email_import.nim` | `toJson(EmailImportItem)` emits the four required fields correctly, with `Opt.none` variants omitting their keys and `Opt.some` emitting them; `toJson(NonEmptyEmailImportMap)` emits the correct top-level object with CreationId keys; `EmailImportResponse.fromJson` parses a well-formed server response into the typed `createResults` merge shape; malformed responses surface as `Err` on the Result rail. |
| `tserde_email_copy.nim` | `toJson(EmailCopyItem)` — minimal (id only) emits `{}` for overrides (architecture §11.10 precedent); full override emits the three override keys; `Opt.none` overrides are omitted. `EmailCopyResponse.fromJson` parses the two-state, `createResults`-only shape. |
| `tserde_email_set_response.nim` | `EmailSetResponse.fromJson` parses the six-field shape (`accountId`, `oldState`, `newState`, `createResults`, `updated`, `destroyed`, `notUpdated`, `notDestroyed`); the `createResults` merge layer correctly reconstructs the merged table from wire `created`/`notCreated` maps; `EmailCreatedItem.fromJson` rejects missing-field shapes. |

### 8.4. Existing-file appends

`tests/protocol/tmail_builders.nim` — append cases for:
- `addEmailSet` — builds an invocation with the correct method name, args shape, and capability URI; phantom-typed response handle carries `EmailSetResponse`; `create`/`update`/`destroy` parameters serialise correctly.
- `addEmailCopy` — builds an invocation; phantom-typed handle carries `EmailCopyResponse`; no `onSuccessDestroyOriginal` key emitted (simple overload never sets it).
- `addEmailCopyAndDestroy` — builds an invocation with `onSuccessDestroyOriginal: true` emitted; return shape is `(RequestBuilder, EmailCopyHandles)`; `destroyFromIfInState` parameter serialises correctly when set.
- `getBoth(EmailCopyHandles)` — on a response where both sub-responses present, extracts `EmailCopyResults` with both fields populated; on a response where the implicit destroy is absent (serverFail synthesis), short-circuits on the destroy with `Err(MethodError{rawType: "serverFail"})`.
- Migrated `addMailboxSet` — one case per update-algebra usage pattern (empty update set rejected at construction time, not at builder time; a valid `MailboxUpdateSet` passes through and serialises to the correct PatchObject-shaped JSON).

`tests/protocol/tmail_methods.nim` — append cases for:
- `addEmailImport` — builds an invocation; phantom-typed handle carries `EmailImportResponse`; `emails: NonEmptyEmailImportMap` parameter serialises to the correct top-level `emails` key.
- Migrated `addVacationResponseSet` — builds an invocation with the `singleton` id hardcoded internally; the `update: VacationResponseUpdateSet` parameter serialises to the correct wire patch; `ifInState` parameter passes through unchanged.

`tests/unit/mail/tmailbox.nim` — append cases for `MailboxUpdate` (five
variants, each with total constructor) and `MailboxUpdateSet` (empty-
input rejection, duplicate-target-property rejection) inline per F4.5.

`tests/serde/mail/tserde_mailbox.nim` — append cases for
`toJson(MailboxUpdate)` (five variants) and `toJson(MailboxUpdateSet)`
(flattening to top-level JSON object, one key per variant).

`tests/serde/mail/tserde_vacation.nim` — append cases for
`toJson(VacationResponseUpdate)` (six variants) and
`toJson(VacationResponseUpdateSet)` (flattening).

### 8.5. PatchObject migration strategy

Approximately seventeen test files reference `PatchObject` across
several test categories. Two migration strategies apply:

1. **Tests exercising mail builder/method surfaces** rewrite their
   setup to construct typed update-sets via the public smart
   constructors. These include:
   - `tests/protocol/tmail_methods.nim` — update construction for
     `addVacationResponseSet` (migrates to `VacationResponseUpdateSet`).
   - `tests/protocol/tmethods.nim` and `tests/protocol/tbuilder.nim`
     — any references through generic `/set` that shaped over mail
     migrate via the same path.

2. **Tests exercising core `PatchObject` serde directly** either:
   - Relocate to test the typed-algebra → wire-patch translation
     (single source of truth: if typed-algebra serde is tested, core
     `PatchObject` serde is transitively covered via the serde
     composition).
   - Retain internal-symbol access via `import jmap_client/framework {.all.}`
     pragma, which continues to see the (now-private) `PatchObject`
     symbol for deep-integration testing.

Applies to: `tests/mproperty.nim`, `tests/unit/tframework.nim`,
`tests/serde/tserde_framework.nim`, `tests/property/tprop_framework.nim`,
`tests/property/tprop_serde.nim`, and others.

Per-file migration decisions are made during the Part F implementation
PR; the design doc enumerates the file set but does not pre-commit each
one to strategy 1 or 2. The `{.all.}` escape hatch exists precisely to
absorb tests whose fundamental purpose is core-internal verification,
not API surface verification.

### 8.6. Test infrastructure additions

New `mfixtures.nim` factories, organised under a new "Mail Part F
factories" section after Part E's:

- `makeEmailUpdate(kind, ...)` — overload per variant.
- `makeEmailUpdateSet(updates = @[...])` — single-call convenience.
- `makeMailboxUpdate(kind, ...)` and `makeVacationResponseUpdate(...)`.
- `makeEmailCopyItem(id = ..., overrides = ...)`.
- `makeEmailImportItem(blobId = ..., mailboxIds = ..., keywords = ...)`.
- `makeNonEmptyEmailImportMap(entries = @[...])`.
- `makeEmailCreatedItem(id = ..., blobId = ..., threadId = ..., size = 1024)`.
- `makeEmailSetResponse`, `makeEmailCopyResponse`, `makeEmailImportResponse`
  — full and minimal variants (matching Part D's precedent).
- `makeEmailCopyHandles(copyId, destroyId)` — constructs the compound
  handle record for test use.

New `mproperty.nim` generators:

- `genEmailUpdate(rng, trial)` — edge-biased: each variant at trials
  0–5, random combinations above.
- `genEmailUpdateSet(rng, trial)` — composes `genEmailUpdate` with
  edge-biased conflict-injection (Classes 1/2/3) in the negative-case
  generator arm.
- `genInvalidEmailUpdateSet(rng, trial, class)` — targeted conflict
  injection for property-based conflict-detection coverage.
- `genEmailCopyItem`, `genEmailImportItem`, `genNonEmptyEmailImportMap`.

New `massertions.nim` templates:

- `assertUpdateSetErr(expr, violations: set[EmailUpdateSetViolation])`
  — asserts `Err` with matching violation types. Parallels Part E's
  `assertBlueprintErr` (L-1).
- `assertCompoundHandleShortCircuit(resp, handles, expected: MethodErrorType)`
  — verifies `getBoth` short-circuits on the first failing handle with
  the expected error.

Equality helpers (`mfixtures.nim`):

- `emailUpdateEq` (case-object, 6 variants).
- `emailUpdateSetEq` (ordered seq equality — different from Part E's
  K-2/K-9 split, because EmailUpdateSet order is caller-specified and
  preserved through serde).
- `mailboxUpdateEq`, `mailboxUpdateSetEq`, `vacationResponseUpdateEq`,
  `vacationResponseUpdateSetEq`.
- `emailCopyItemEq`, `emailImportItemEq`, `emailCreatedItemEq`.
- `emailSetResponseEq`, `emailCopyResponseEq`, `emailImportResponseEq`
  — each decomposes into per-field comparison, reusing
  `setErrorEq` for the `createResults` entries.

### 8.7. Verification commands

Implementation PR verification sequence:

- `just build` — shared library compiles; no new warnings.
- `just test` — every test file above runs green.
- `just analyse` — nimalyzer passes without new suppressions.
- `just fmt-check` — nph formatting unchanged.
- `just ci` — full pipeline green.

The compile-time reachability smoke (`tmail_f_reexport.nim` with
`action: "compile"`) fails loudly if any new public symbol is not
re-exported through `jmap_client.nim`. Property tests in
`tprop_mail_f.nim` cover the three `EmailUpdateSet` conflict classes
exhaustively (plus empty-input rejection and variant-equality across
the five domain-named ctors).

---

*End of Part F2 design document.*
