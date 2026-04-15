# Mail Part F Implementation Plan (F1 source-side only)

Layers 1–4 of RFC 8620 done; Mail Parts A–E done. This plan turns Mail
Part F's specification document (`docs/design/11-mail-F1-design.md`)
into ordered build steps. Part F delivers the Email write path
(`Email/set`, `Email/copy`, `Email/import`) and retires public
`PatchObject` in favour of three typed update algebras (`EmailUpdate`,
`MailboxUpdate`, `VacationResponseUpdate`).

**Scope note.** This plan covers F1 only — source code, serde,
builders/methods, PatchObject demotion, re-exports, and audit. The
companion test specification (`docs/design/11-mail-F2-design.md`) is
handled as a separate implementation effort. The single test-adjacent
step retained here (Step 16) is the compile-fix migration of existing
files that import `PatchObject*` — F1 §1.5.2 mandates this in the
same PR so `main` does not land in an inconsistent state.

5 phases, one commit each. Every phase passes `just ci` before
committing. Cross-cutting requirements (SPDX header, `{.push raises:
[], noSideEffect.}` for L1/L2 and `{.push raises: [].}` for L3,
`func`-only in L1–L3, `Result` / `ValidationError` / `Opt[T]` from
nim-results, `toJson`-only serde for creation types per Postel) per
design §1.6 apply to every step.

---

## Phase 1: Foundational L1 extensions

Independent additive changes across existing modules. No public-surface
breakage — the new types land unused until Phase 4 wires them in.

- **Step 1:** Add `mnEmailImport = "Email/import"` enum variant to
  `src/jmap_client/methods_enum.nim` per design §1.7, §6.4.
- **Step 2:** Add `importMethodName*(T: typedesc[Email]): MethodName`
  func overload returning `mnEmailImport` to
  `src/jmap_client/mail/mail_entities.nim` per design §6.4. Mirrors
  the existing per-verb resolver pattern at `mail_entities.nim:148–176`
  (`getMethodName`, `setMethodName`, `copyMethodName`, …)
   Allows the dispatch layer to resolve
  `Email/import` responses to `EmailImportResponse` via the same
  mechanism used for `Email/get`, `Email/set`, `Email/query`.
- **Step 3:** Extend `src/jmap_client/mail/mailbox.nim` with a new
  "Mailbox Update Algebra" section per design §3.3, §3.5, §1.7:
  `MailboxUpdateVariantKind` (five variants), `MailboxUpdate` case
  object, five total smart constructors (`setName`, `setParentId`,
  `setRole`, `setSortOrder`, `setIsSubscribed`), `MailboxUpdateSet`
  distinct seq, `initMailboxUpdateSet` rejecting empty input and
  duplicate target property. Mirrors the existing "Mailbox Creation
  Model" block around line 140.
- **Step 4:** Extend `src/jmap_client/mail/vacation.nim` with the
  `VacationResponseUpdate` algebra per design §3.4:
  `VacationResponseUpdateVariantKind` (six variants), case object, six
  total smart constructors, `VacationResponseUpdateSet` distinct seq,
  `initVacationResponseUpdateSet` rejecting empty input and duplicate
  target property.
- **Step 5:** Extend `src/jmap_client/mail/email.nim` with the shared
  response surface and creation models per design §§2.1, 2.2, 5.1,
  6.1, 6.2:
  - `EmailCreatedItem` — four-field typed record (`id`, `blobId`,
    `threadId`, `size`); all fields required (§2.1, F2/F14).
  - `UpdatedEntryKind` + `UpdatedEntry` — two-case object encoding
    RFC 8620 §5.3's `Foo|null` inner value (§2.2, F2.1).
  - `EmailSetResponse`, `EmailCopyResponse`, `EmailImportResponse` —
    per-method response types, all three carrying the shared
    `createResults: Table[CreationId, Result[EmailCreatedItem,
    SetError]]` merge shape (§2.2).
  - `EmailCopyItem` + `initEmailCopyItem` — total constructor;
    `mailboxIds: Opt[NonEmptyMailboxIdSet]` (§5.1, F10).
  - `EmailImportItem` + `initEmailImportItem` — total constructor;
    `mailboxIds: NonEmptyMailboxIdSet` non-`Opt` (§6.1, F15).
  - `NonEmptyEmailImportMap` + `initNonEmptyEmailImportMap` —
    accumulating `Result[_, seq[ValidationError]]` constructor
    rejecting empty input and duplicate CreationIds in a single pass
    (§6.2, F13).

### CI gate

Run `just ci` before committing.

---

## Phase 2: EmailUpdate algebra (new L1 module)

- **Step 6:** Create `src/jmap_client/mail/email_update.nim` per design
  §3.2:
  - `EmailUpdateVariantKind` (six variants: `euAddKeyword`,
    `euRemoveKeyword`, `euSetKeywords`, `euAddToMailbox`,
    `euRemoveFromMailbox`, `euSetMailboxIds`) and `EmailUpdate` case
    object (§3.2.1).
  - Six protocol-primitive total smart constructors (`addKeyword`,
    `removeKeyword`, `setKeywords`, `addToMailbox`, `removeFromMailbox`,
    `setMailboxIds`) per §3.2.2 — all total; all cross-field invariants
    discharged at field-type level.
  - Five domain-named convenience constructors (`markRead`,
    `markUnread`, `markFlagged`, `markUnflagged`, `moveToMailbox`) per
    §3.2.3. Note: `moveToMailbox(id)` emits `euSetMailboxIds` (replace
    semantics), not `euAddToMailbox` — matches universal mail-UI
    "Move to" convention (§3.2.3.1, F21).
  - `EmailUpdateSet` distinct seq + `initEmailUpdateSet` accumulating
    smart constructor per §3.2.4. The constructor enforces four
    invariants in a single pass with one `ValidationError` per
    detected violation:
    - Empty input rejected (F22).
    - Class 1 — duplicate target path (two updates writing the same
      target).
    - Class 2 — opposite operations on the same sub-path (e.g.
      add-keyword + remove-keyword on the same keyword).
    - Class 3 — sub-path operation alongside full-replace on the same
      parent (e.g. `euAddKeyword` + `euSetKeywords`) per RFC 8620
      §5.3 lines 1918–1920 (F23).

### CI gate

Run `just ci` before committing.

---

## Phase 3: L2 serde

- **Step 7:** Create `src/jmap_client/mail/serde_email_update.nim` per
  design §3.2.5:
  - `jsonPointerEscape(s: string): string` helper per RFC 6901 §3 —
    `~` → `~0` first, then `/` → `~1`; order matters or the `~1`
    produced for `/` would be re-escaped into `~01`.
  - `toJson(EmailUpdate): (string, JsonNode)` returning the wire-key /
    wire-value pair per variant; keyword reference tokens
    RFC 6901-escaped, id tokens left raw (the `Id` charset excludes
    `~` and `/`).
  - `toJson(EmailUpdateSet): JsonNode` flattening the validated set to
    a wire `PatchObject`-shaped `JsonNode`. Key distinctness is
    type-level guaranteed by `initEmailUpdateSet`'s Class 1 rejection.
- **Step 8:** Extend `src/jmap_client/mail/serde_email.nim` per design
  §2.3:
  - `toJson`/`fromJson` for `EmailCreatedItem` — all four fields
    required; a missing or wrong-typed field surfaces as a synthetic
    `Err(SetError(errorType: setUnknown, rawType: <descriptive>))` in the
    parent `createResults` merge, not silent zero (§2.3).
  - `toJson`/`fromJson` for `UpdatedEntry` — JSON `null` maps to
    `uekUnchanged`; JSON object to `uekChanged(changedProperties)`;
    other kinds fail onto the `Err` rail. `{}` and `null` are kept
    distinct at parse time (§2.3).
  - `toJson`/`fromJson` for `EmailSetResponse`, `EmailCopyResponse`,
    `EmailImportResponse`. The `created`/`notCreated` /
    `updated`/`notUpdated` / `destroyed`/`notDestroyed` wire maps merge
    into `createResults`, `updated`, `destroyed`, `notUpdated`,
    `notDestroyed` via existing core `SetResponse[T]` /
    `CopyResponse[T]` helpers — mail serde calls the core helper and
    casts payload through `EmailCreatedItem.fromJson`.
  - `toJson` only — no `fromJson` — for `EmailCopyItem`,
    `EmailImportItem`, `NonEmptyEmailImportMap` per §1.6 sender-side-
    strict rule: the server never returns these shapes, so
    introducing `fromJson` would open a second (unvalidated)
    construction path. `EmailImportItem.toJson` collapses both
    `Opt.none` and `Opt.some(empty KeywordSet)` to an omitted
    `keywords` key (§6.1).
- **Step 9:** Extend `src/jmap_client/mail/serde_mailbox.nim` with
  `toJson` for `MailboxUpdate` and `MailboxUpdateSet` per design §3.3.
  Each `MailboxUpdate` variant emits a single top-level key (no
  sub-path flattening — all Mailbox updates are whole-value replace).
- **Step 10:** Extend `src/jmap_client/mail/serde_vacation.nim` with
  `toJson` for `VacationResponseUpdate` and `VacationResponseUpdateSet`
  per design §3.4.

### CI gate

Run `just ci` before committing.

---

## Phase 4: PatchObject demotion + L3 public-surface switch

This phase is one atomic commit. Per design §1.5.2, staging it in two
PRs would leave `main` with public typed algebras alongside public
surfaces still accepting raw `PatchObject` — the precise inconsistency
Part F exists to eliminate. All demotion, new builders, and migrated
surfaces land together.

- **Step 11:** Drop `*` export on `PatchObject` at
  `src/jmap_client/framework.nim:80` per design §1.5.1 (F19).
- **Step 12:** Relocate the private `PatchObject` `toJson`/`fromJson`
  helpers into `src/jmap_client/serde_framework.nim` per design §1.5.2.
- **Step 13:** Migrate internal use-sites to the now-private import
  path:
  - `src/jmap_client/builder.nim` — internal use-site update.
  - `src/jmap_client/methods.nim` — `SetRequest[T].update` continues to
    carry `PatchObject` at the wire shape; the serde layer owns
    translation, so no public signature change here.
- **Step 14:** Extend `src/jmap_client/mail/mail_builders.nim` per
  design §§4–5:
  - `addEmailSet` — mechanical mirror of `addMailboxSet`
    (`mail_builders.nim:196`) with `EmailBlueprint` / `EmailUpdateSet` /
    `EmailSetResponse` substitutions; **no** `onDestroyRemoveEmails`-like
    method-specific extra (RFC §4.6 defines none) (§4.1).
  - `addEmailCopy` simple overload — `create` is **non-`Opt`**
    `Table[CreationId, EmailCopyItem]` (unlike `/set`'s `Opt[Table…]`,
    an empty `/copy` is meaningless); does **not** expose
    `onSuccessDestroyOriginal`; callers wanting post-copy destroy use
    `addEmailCopyAndDestroy` (§5.2).
  - `EmailCopyHandles`, `EmailCopyResults`,
    `getBoth(Response, EmailCopyHandles): Result[EmailCopyResults,
    MethodError]` — compound-handle pattern mirroring
    `convenience.nim:104`'s `getBoth[T](QueryGetHandles[T])` (§5.4).
  - `addEmailCopyAndDestroy` compound overload — adds
    `destroyFromIfInState: Opt[JmapState]` for the implicit destroy's
    state assertion (absent on the simple overload); always emits
    `onSuccessDestroyOriginal: true` on the wire; returns
    `EmailCopyHandles` (§5.3).
  - **Migrate** `addMailboxSet`'s `update` parameter from
    `Opt[Table[Id, PatchObject]]` to `Opt[Table[Id, MailboxUpdateSet]]`
    per design §1.5.2.
- **Step 15:** Extend `src/jmap_client/mail/mail_methods.nim` per
  design §6:
  - `addEmailImport` — `emails: NonEmptyEmailImportMap` non-`Opt`
    parameter; phantom-typed `ResponseHandle[EmailImportResponse]`
    (§6.3).
  - **Migrate** `addVacationResponseSet`'s `update` parameter from
    `PatchObject` to `VacationResponseUpdateSet` per design §1.5.2.
    The `Table` wrapper continues to be absent — RFC forbids any id
    other than `"singleton"` and core's `VacationResponseSingletonId`
    is hardcoded internally.
- **Step 16:** Compile-fix test migration only. Update the ~17 test
  files that import `PatchObject*` per design §1.5.2's two-pronged
  strategy. This step is deliberately scoped to the minimum required
  for `just ci` to pass after Phase 4; new F2 test scenarios are out
  of scope.
  - **Strategy 1 (builder/method tests):** rewrite fixture setup to
    construct typed update-sets via the public smart constructors
    (`MailboxUpdateSet`, `VacationResponseUpdateSet`,
    `EmailUpdateSet`).
  - **Strategy 2 (core `PatchObject` serde tests):** switch the import
    to `import jmap_client/framework {.all.}` so the now-private
    symbol remains visible for deep-integration coverage.
  Per-file decision (Strategy 1 vs Strategy 2) is made at
  migration time per design §1.5.2 — the design doc enumerates the
  file set but does not pre-commit each one.

### CI gate

Run `just ci` before committing.

---

## Phase 5: Re-exports, audit, DTM spot-check

- **Step 17:** Update `src/jmap_client/mail/types.nim` to re-export
  Part F's new public L1 types per design §1.7. Required exports:
  - From `email_update.nim` (new): `EmailUpdate`,
    `EmailUpdateVariantKind`, `EmailUpdateSet`, the six protocol-
    primitive constructors (`addKeyword`, `removeKeyword`,
    `setKeywords`, `addToMailbox`, `removeFromMailbox`,
    `setMailboxIds`), the five domain-named convenience constructors
    (`markRead`, `markUnread`, `markFlagged`, `markUnflagged`,
    `moveToMailbox`), `initEmailUpdateSet`.
  - From `email.nim` (extended): `EmailCreatedItem`, `UpdatedEntry`,
    `UpdatedEntryKind`, `EmailSetResponse`, `EmailCopyResponse`,
    `EmailImportResponse`, `EmailCopyItem`, `EmailImportItem`,
    `NonEmptyEmailImportMap`, `initEmailCopyItem`,
    `initEmailImportItem`, `initNonEmptyEmailImportMap`.
  - From `mailbox.nim` (extended): `MailboxUpdate`,
    `MailboxUpdateVariantKind`, the five smart constructors,
    `MailboxUpdateSet`, `initMailboxUpdateSet`.
  - From `vacation.nim` (extended): `VacationResponseUpdate`,
    `VacationResponseUpdateVariantKind`, the six smart constructors,
    `VacationResponseUpdateSet`, `initVacationResponseUpdateSet`.
- **Step 18:** Update `src/jmap_client/mail/serialisation.nim` to
  re-export new serde modules and additions per design §1.7:
  `serde_email_update` (new) plus the new `toJson`/`fromJson` symbols
  added to `serde_email`, `serde_mailbox`, `serde_vacation`.
- **Step 19:** Verify Part F public symbols are accessible via
  `import jmap_client` end-to-end. A compile-time smoke reference to
  each new symbol (see Step 17 enumeration) catches any omission in
  the re-export hubs.
- **Step 20:** Cross-cutting convention audit per design §1.6 across
  every new and modified Part F source file (`email_update.nim`,
  `serde_email_update.nim`, and extended regions of `email.nim`,
  `mailbox.nim`, `vacation.nim`, `serde_email.nim`,
  `serde_mailbox.nim`, `serde_vacation.nim`, `mail_builders.nim`,
  `mail_methods.nim`, `methods_enum.nim`, `mail_entities.nim`,
  `framework.nim`, `serde_framework.nim`, `builder.nim`,
  `methods.nim`):
  - SPDX header at line 1.
  - `{.push raises: [], noSideEffect.}` at module top for L1/L2
    modules; `{.push raises: [].}` for L3 builders/methods.
  - `func` only in L1–L3 — no `proc` definitions
    (`rg -n '^proc ' src/jmap_client/mail/` should return nothing in
    Part F files).
  - Smart constructors return `Result[T, ValidationError]` or
    `Result[T, seq[ValidationError]]` (accumulating, per F4.4 / F13);
    no `raise` statements on domain failure paths.
  - `Opt[T]` from nim-results, never `std/options`.
  - `toJson`-only serde for creation types; no `fromJson` defined on
    `EmailCopyItem`, `EmailImportItem`, `EmailUpdate`,
    `EmailUpdateSet`, or `NonEmptyEmailImportMap` per §1.6 sender-
    side-strict rule.
- **Step 21:** Decision Traceability Matrix spot-check for items
  **not** compiler-enforced (most decisions are — this list covers
  the few that aren't; see design §9 for the full matrix):
  - **F2** — confirm no `addSet[Email]` generic overload exposed; the
    three mail-specific response types are the only public surface
    for Email write responses.
  - **F10** — confirm `EmailCopyItem.mailboxIds: Opt[NonEmptyMailboxIdSet]`
    (tightened from architecture §11.10's `Opt[MailboxIdSet]`).
  - **F15** — confirm `EmailImportItem.mailboxIds: NonEmptyMailboxIdSet`
    (non-`Opt`; tightened from architecture §10.3's `MailboxIdSet`).
  - **F11** — confirm overload named `addEmailCopyAndDestroy` (not
    `addEmailCopyChained`) and `EmailCopyHandles` fields named
    `copy`/`destroy` (not `copy`/`implicitEmailSet`).
  - **F12** — confirm `EmailCopyHandles.destroy` typed non-`Opt`
    `ResponseHandle[EmailSetResponse]`; absence of the implicit
    response surfaces only via `getBoth`'s `?`-short-circuit on the
    `Err` rail.
  - **F19** — confirm `PatchObject` is no longer a public symbol of
    `framework.nim`; only the serde-internal path retains access.
  - **F21** — confirm `moveToMailbox(id)` emits `euSetMailboxIds`
    (replace), not `euAddToMailbox` (add).
  - **F22** — confirm `initEmailUpdateSet(@[])` returns `Err` (empty
    input rejection).
  - **F23** — confirm all three conflict classes implemented per
    §3.2.4.
  Where adherence is covered downstream by F2 test scenarios, that
  verification lands in the separate F2 effort. Step 21 here is
  structural only — inspection of type signatures, field types, and
  variant payloads against the design doc.

### CI gate

Run `just ci` before committing. Steps 19, 20 and 21 are
prerequisites for the Phase 5 commit — failures there block the
commit just like test failures.

---

*End of Part F (F1 source-side) implementation plan.*
