# Mail Part G Implementation Plan (G1 source-side only)

This plan turns the G1 design specification (`docs/design/12-mail-G1-design.md`)
into ordered build steps for **EmailSubmission** (RFC 8621 §7). Part G1
covers source code, serde, builders, capability refinement, re-exports,
and audit. The companion test specification (G2) is a separate effort.

5 phases, one commit each. Every phase passes `just ci` before
committing. Cross-cutting requirements apply to every step: SPDX header,
`{.push raises: [], noSideEffect.}` for L1/L2 and `{.push raises: [].}`
for L3, `func`-only in L1–L3, `Result`/`ValidationError`/`Opt[T]` from
nim-results, `toJson`-only serde for creation, filter, and sort types (design §7, §1.2).

---

## Phase 1: L1 vocabulary — envelope and status modules

Two new L1 modules. No existing modules touched.

- **Step 1:** Create `src/jmap_client/mail/submission_envelope.nim` with
  RFC 5321 address primitives per design §2.1–2.2: `RFC5321Mailbox`
  (distinct string, strict + lenient parser pair) and `RFC5321Keyword`
  (distinct string with `$` borrow and custom case-insensitive `==` /
  `hash` via ASCII case-fold per RFC 5321 §2.4; single parser accepting
  leading letter or digit).

- **Step 2:** Extend `submission_envelope.nim` with the SMTP parameter
  type algebra per design §2.3–2.4: payload enums/newtypes
  (`BodyEncoding`, `DsnRetType`, `DsnNotifyFlag`, `OrcptAddrType`,
  `DeliveryByMode`, `HoldForSeconds`, `MtPriority`),
  `SubmissionParamKind`, `SubmissionParam` case object,
  `SubmissionParamKey` identity type, `SubmissionParams`
  (`distinct OrderedTable`), and `parseSubmissionParams`. Smart
  constructors for `HoldForSeconds`/`MtPriority` return `Result` — no
  `range[T]`. NOTIFY mutual exclusion enforced in `spkNotify`
  constructor.

- **Step 3:** Extend `submission_envelope.nim` with composite types per
  design §2.5: `SubmissionAddress` (parameters `Opt[SubmissionParams]`
  per G34), `ReversePath` case object with `rpkNullPath`/`rpkMailbox`
  and infallible constructors (G32), `NonEmptyRcptList`
  (strict/lenient parser pair per G7), `Envelope` (`mailFrom:
  ReversePath` + `rcptTo: NonEmptyRcptList`).

- **Step 4:** Create `src/jmap_client/mail/submission_status.nim` per
  design §3: `UndoStatus`, `DeliveredState` + `ParsedDeliveredState`,
  `DisplayedState` + `ParsedDisplayedState`, `SmtpReply` (distinct
  string + smart constructor), `DeliveryStatus`, `DeliveryStatusMap`
  with `countDelivered`/`anyFailed`.

### CI gate

Run `just ci` before committing.

---

## Phase 2: L1 entity — EmailSubmission module

One new L1 module containing the GADT-style entity, creation model,
update algebra, filter/sort types, and compound-handle types. Depends
on the Phase 1 modules.

- **Prerequisite:** Ensure `BlobId` exists in `primitives.nim`
  (distinct string newtype, like `Id`). Required by `dsnBlobIds` /
  `mdnBlobIds` on the entity read model (design §4.1).

- **Step 5:** Create `src/jmap_client/mail/email_submission.nim` with
  the phantom-typed entity per design §4: `EmailSubmission[S: static
  UndoStatus]` and `AnyEmailSubmission` existential wrapper.

- **Step 6:** Extend with the creation model per design §5:
  `EmailSubmissionBlueprint` and `parseEmailSubmissionBlueprint`
  (accumulating).

- **Step 7:** Extend with the update algebra per design §6:
  `EmailSubmissionUpdateVariantKind`, `EmailSubmissionUpdate`,
  `setUndoStatusToCanceled()` protocol-primitive constructor,
  `cancelUpdate(EmailSubmission[usPending])` domain-named constructor,
  `NonEmptyEmailSubmissionUpdates`.

- **Step 8:** Extend with filter, sort, and response types per design
  §§8.2–8.4: `NonEmptyIdSeq`, `EmailSubmissionFilterCondition`,
  `EmailSubmissionSortProperty` (wire token `sentAt` ≠ entity field
  `sendAt`), `EmailSubmissionComparator`,
  `EmailSubmissionSetResponse`.

- **Step 9:** Extend with `IdOrCreationRef` per design §9.0 (G35/G36:
  creation references, distinct from `Referencable[T]` result
  references) and compound-handle types per design §9.2:
  `EmailSubmissionHandles`, `EmailSubmissionResults`.

  > **Deviation from design §1.5 — enforced by Nim's type-resolution
  > semantics.** `getBoth` does NOT land in Step 9. The monomorphic
  > `?resp.get(handles.submission)` body forces generic instantiation
  > of `SetResponse[EmailSubmissionCreatedItem].fromJson` at the
  > extractor's definition site, which recurses into
  > `EmailSubmissionCreatedItem.fromJson` — not yet in scope until
  > Step 12 lands the L2 serde. `mixin fromJson` only defers resolution
  > when the enclosing routine is itself generic; it is a no-op inside
  > a non-generic `func`. Placing `getBoth` in `email_submission.nim`
  > produces *"expression '' has no type (or is ambiguous)"* at
  > `methods.nim:645-646` inside `mergeCreateResults[T]`. F1 sidesteps
  > this by hosting its `getBoth` in `mail_builders.nim` (L3), where
  > the file imports L2 serde. Step 9 leaves `getBoth` for Step 17 (see
  > Step 17 note below).

### CI gate

Run `just ci` before committing.

---

## Phase 3: L2 serde

Multiple L2 serde modules (split per concern) covering all Phase 1–2 L1 modules.

- **Step 10:** Create `src/jmap_client/mail/serde_submission_envelope.nim`
  with envelope serde per design §7.2. `ReversePath` serde dispatches
  on empty vs non-empty `email` field. **No** `xtextEncode` /
  `xtextDecode` helpers — see the resolution in design §7.2 (RFC 8621
  §7.3.2 strips xtext at the JMAP boundary, so the L1 model and serde
  layer carry plain UTF-8 throughout).

- **Step 11:** Extend with status type serde per design §§3, 7.1.
  Include a named `parseUndoStatus(raw, path)` returning
  `Result[UndoStatus, SerdeViolation]` — Step 12's `AnyEmailSubmission`
  deserialiser depends on it. `fromJson`-only for `SmtpReply`,
  `DeliveryStatus`, `DeliveryStatusMap` (server-set).

- **Step 12:** Extend with entity and creation serde per design §§7.1,
  7.3. `fromJson` for `AnyEmailSubmission` dispatches on `undoStatus`
  then delegates to `fromJsonShared[S]` generic helper.
  `NonEmptyEmailSubmissionUpdates` translates to `PatchObject`
  `{ "undoStatus": "canceled" }` on the wire. `IdOrCreationRef` serde
  is `toJson`-only: `icrDirect` → Id string, `icrCreation` → `"#"` +
  creationId. `toJson`-only for `EmailSubmissionFilterCondition` and
  `EmailSubmissionComparator` (client → server only, design §7.3).

### CI gate

Run `just ci` before committing.

---

## Phase 4: L3 builders + entity registration + capability amendment

Wires L1/L2 types into the builder layer and amends existing modules.

- **Step 13:** Amend `src/jmap_client/mail/mail_capabilities.nim` per
  design §11.1: add `SubmissionExtensionMap` (`distinct
  OrderedTable[RFC5321Keyword, seq[string]]`), change
  `SubmissionCapabilities.submissionExtensions` to use it. Update
  existing tests and serde.

- **Step 14:** Update `src/jmap_client/mail/serde_mail_capabilities.nim`
  to parse `submissionExtensions` keys through `parseRFC5321Keyword` at
  the serde boundary.

- **Step 15:** Extend `src/jmap_client/mail/mail_entities.nim` with
  EmailSubmission entity registration per design §1.5: capability URI,
  method namespace, per-verb method-name resolvers.

- **Step 16:** Add `MethodName` enum variants to
  `src/jmap_client/methods_enum.nim` for `EmailSubmission/get`,
  `/changes`, `/query`, `/queryChanges`, `/set`.

- **Step 17:** Create `src/jmap_client/mail/submission_builders.nim`
  with standard method builders per design §8:
  `addEmailSubmissionGet`, `addEmailSubmissionChanges`,
  `addEmailSubmissionQuery`, `addEmailSubmissionQueryChanges`,
  `addEmailSubmissionSet` (simple). Additionally, add `getBoth(Response,
  EmailSubmissionHandles): Result[EmailSubmissionResults, MethodError]`
  here (deferred from Step 9 — see that step's note). This module must
  `import ./serde_email_submission` and `./serde_email` (or re-export
  them) so `EmailSubmissionCreatedItem.fromJson` and
  `EmailCreatedItem.fromJson` are in scope at `getBoth`'s definition
  site — same pattern as F1's `mail_builders.nim:32-37`. The `getBoth`
  body mirrors F1 (`mail_builders.nim:481-491`): `mixin fromJson`,
  `?resp.get(handles.submission)`, `?resp.get(handles.emailSet)`,
  `ok(EmailSubmissionResults(...))`.

- **Step 18:** Extend `submission_builders.nim` with the compound
  builder per design §9.1: `addEmailSubmissionAndEmailSet` with
  `IdOrCreationRef`-keyed `onSuccessUpdateEmail` /
  `onSuccessDestroyEmail` (G35). Returns
  `(RequestBuilder, EmailSubmissionHandles)`.

### CI gate

Run `just ci` before committing.

---

## Phase 5: Re-exports, audit, DTM spot-check

- **Step 19:** Update `src/jmap_client/mail/types.nim` to re-export
  Part G's new public L1 types per design §1.2/§1.5:
  - From `submission_envelope.nim` (new): `RFC5321Mailbox`,
    `RFC5321Keyword`, `SubmissionParamKind`, `SubmissionParam`,
    `SubmissionParamKey`, `SubmissionParams`, `SubmissionAddress`,
    `ReversePathKind`, `ReversePath`, `nullReversePath`,
    `reversePath`, `NonEmptyRcptList`, `Envelope`, `BodyEncoding`,
    `DsnRetType`, `DsnNotifyFlag`, `OrcptAddrType`, `DeliveryByMode`,
    `HoldForSeconds`, `MtPriority`, and all public functions
    (`paramKey`, smart constructors, parsers).
  - From `submission_status.nim` (new): `UndoStatus`, `DeliveredState`,
    `ParsedDeliveredState`, `DisplayedState`, `ParsedDisplayedState`,
    `SmtpReply`, `DeliveryStatus`, `DeliveryStatusMap`,
    `countDelivered`, `anyFailed`, and parsers.
  - From `email_submission.nim` (new): `EmailSubmission`,
    `AnyEmailSubmission`, `IdOrCreationRefKind`, `IdOrCreationRef`,
    `directRef`, `creationRef`, `EmailSubmissionBlueprint`,
    `EmailSubmissionUpdate`, `EmailSubmissionUpdateVariantKind`,
    `NonEmptyEmailSubmissionUpdates`, `EmailSubmissionFilterCondition`,
    `NonEmptyIdSeq`, `EmailSubmissionSortProperty`,
    `EmailSubmissionComparator`, `EmailSubmissionSetResponse`,
    `EmailSubmissionHandles`, `EmailSubmissionResults`,
    `setUndoStatusToCanceled`, `cancelUpdate`,
    `parseEmailSubmissionBlueprint`,
    `parseNonEmptyEmailSubmissionUpdates`, `parseNonEmptyIdSeq`,
    `getBoth`.
  - From `mail_capabilities.nim` (amended): `SubmissionExtensionMap`.

- **Step 20:** Update `src/jmap_client/mail/serialisation.nim` to
  re-export new serde module(s).

- **Step 21:** Verify Part G public symbols are accessible via
  `import jmap_client` end-to-end. Compile-time smoke reference to
  each Step 19 symbol catches re-export omissions.

- **Step 22:** Cross-cutting convention audit across every new and
  modified Part G source file:
  - SPDX header at line 1.
  - `{.push raises: [], noSideEffect.}` for L1/L2;
    `{.push raises: [].}` for L3.
  - `func` only in L1–L3.
  - Smart constructors return `Result`; no `raise` on domain paths.
  - `Opt[T]` from nim-results, never `std/options`.
  - `toJson`-only for creation/filter types.
  - Phantom parameter `[S: static UndoStatus]` correctly threaded.

- **Step 23:** DTM spot-check for items **not** compiler-enforced
  (design §13):
  - **G2** — phantom encoding, not flat record.
  - **G3** — `static UndoStatus` generic (DataKinds).
  - **G4** — `cancelUpdate` accepts `EmailSubmission[usPending]` only.
  - **G6** — `RFC5321Mailbox` distinct from `EmailAddress.email`.
  - **G7** — strict/lenient parser pair; strict rejects duplicates.
  - **G8a** — `SubmissionParams` is
    `distinct OrderedTable[SubmissionParamKey, ...]`.
  - **G12** — `SmtpReply` is distinct string + smart constructor.
  - **G16** — single-variant case object with both constructor forms.
  - **G19** — sort wire token is `sentAt` (not `sendAt`).
  - **G21** — specific `EmailSubmissionHandles`, not generic.
  - **G22** — `onSuccessUpdateEmail` values typed `EmailUpdateSet`.
  - **G25** — `submissionExtensions` uses `SubmissionExtensionMap`.
  - **G32** — `Envelope.mailFrom` is `ReversePath`, not
    `SubmissionAddress`.
  - **G34** — `SubmissionAddress.parameters` is
    `Opt[SubmissionParams]`.
  - **G35** — `onSuccess*` keys are `IdOrCreationRef`, not
    `Referencable[Id]`.
  - **G36** — `IdOrCreationRef` is a separate type from
    `Referencable[T]`, not a third arm on the existing sum.
  - **G37** — filter list fields use `Opt[NonEmptyIdSeq]`, not
    `Opt[seq[Id]]`.

  Items covered by G2 test scenarios land in the separate G2 effort.

### CI gate

Run `just ci` before committing. Steps 21–23 are prerequisites for
the Phase 5 commit.

---

*End of Part G (G1 source-side) implementation plan.*
