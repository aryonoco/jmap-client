# RFC 8621 JMAP Mail — Design F1: Email Write Path — Specification (set / copy / import)

Part F closes the Email aggregate's lifecycle. Parts A–E delivered the
read model, filter vocabulary, entity scaffolding, and the
`EmailBlueprint` creation aggregate. Part F wires `EmailBlueprint` into
three concrete JMAP methods — `Email/set` (§4.6), `Email/copy` (§4.7),
`Email/import` (§4.8) — sharing a single typed successful-create record
(`EmailCreatedItem`), and lights up RFC 8620 §5.4 implicit-call
compound dispatch through the generic `CompoundHandles[A, B]` that
serves both this part's `addEmailCopyAndDestroy` and Part G's
`addEmailSubmissionAndEmailSet`.

Part F also carries the **typed update algebra** replacement for
RFC 8620 §5.3's wire `PatchObject`. `PatchObject`'s bare string-keyed
map form makes illegal update combinations representable — the exact
anti-pattern Parts A–E worked to eliminate elsewhere. Part F introduces
typed update algebras at two cardinalities:

- per-target patch sets (`EmailUpdateSet`, `MailboxUpdateSet`,
  `VacationResponseUpdateSet`) — one entity's worth of update operations,
  validated for internal conflicts;
- whole-container update tables (`NonEmptyEmailUpdates`,
  `NonEmptyMailboxUpdates`) — the `update:` parameter on the
  corresponding `/set` builders, validated non-empty and duplicate-id-free.

`PatchObject` does not exist as a public type in this codebase. The
typed algebras are the only path to mail `/set` update semantics; their
serde owns the projection to the wire JSON Pointer object.

## Table of Contents

- §1. Scope
- §2. Shared Response Surface
- §3. Typed Update Algebras
- §4. Email/set
- §5. Email/copy
- §6. Email/import
- §7. SetError Extraction Reference
- §8. Test Specification
- §9. Decision Traceability Matrix

---

## 1. Scope

### 1.1. Methods Covered

| Method | RFC 8621 | Builder | Response handle | Notes |
|--------|----------|---------|-----------------|-------|
| `Email/set` | §4.6 | `addEmailSet` | `ResponseHandle[SetResponse[EmailCreatedItem]]` | Routes through the generic `addSet[Email, EmailBlueprint, NonEmptyEmailUpdates, SetResponse[EmailCreatedItem]]`. |
| `Email/copy` | §4.7 | `addEmailCopy` | `ResponseHandle[CopyResponse[EmailCreatedItem]]` | Routes through `addCopy[Email, EmailCopyItem, CopyResponse[EmailCreatedItem]]` with `destroyMode` defaulted to `keepOriginals()`. |
| `Email/copy` (compound) | §4.7 | `addEmailCopyAndDestroy` | `EmailCopyHandles` → `(CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem])` | Same `addCopy` core with `destroyMode = destroyAfterSuccess(destroyFromIfInState)`; pairs the primary handle with a `NameBoundHandle[SetResponse[EmailCreatedItem]]` filtered by `mnEmailSet`. |
| `Email/import` | §4.8 | `addEmailImport` | `ResponseHandle[EmailImportResponse]` | Bespoke response type; takes `NonEmptyEmailImportMap`. |

### 1.2. Supporting Types

| Type | Module | Role |
|------|--------|------|
| `EmailCreatedItem` | `mail/email.nim` | Four-field successful-create record shared across §§4.6/4.7/4.8 (id, blobId, threadId, size). Carried by `SetResponse[EmailCreatedItem]`, `CopyResponse[EmailCreatedItem]`, and `EmailImportResponse.createResults`. |
| `EmailImportResponse` | `mail/email.nim` | Bespoke `Email/import` response. There is no generic `ImportResponse[T]` to absorb it. |
| `EmailCopyItem` | `mail/email.nim` | Per-entry create-side model for `Email/copy` (RFC §4.7). Total constructor `initEmailCopyItem`. |
| `EmailImportItem` | `mail/email.nim` | Per-entry create-side model for `Email/import` (RFC §4.8). Total constructor `initEmailImportItem`. |
| `NonEmptyEmailImportMap` | `mail/email.nim` | `distinct Table[CreationId, EmailImportItem]`; accumulating `initNonEmptyEmailImportMap` rejects empty input and duplicate `CreationId`s. |
| `EmailUpdate`, `EmailUpdateSet` | `mail/email_update.nim` | Six-variant case object plus a `distinct seq[EmailUpdate]` newtype. Smart constructor `initEmailUpdateSet` rejects empty input and three conflict classes. |
| `NonEmptyEmailUpdates` | `mail/email_update.nim` | `distinct Table[Id, EmailUpdateSet]`. Smart constructor `parseNonEmptyEmailUpdates` rejects empty input and duplicate Email ids. |
| `MailboxUpdate`, `MailboxUpdateSet` | `mail/mailbox.nim` | Five-variant case object plus a `distinct seq[MailboxUpdate]`. Smart constructor `initMailboxUpdateSet` rejects empty input and duplicate target properties. |
| `NonEmptyMailboxUpdates` | `mail/mailbox.nim` | `distinct Table[Id, MailboxUpdateSet]`. Smart constructor `parseNonEmptyMailboxUpdates` rejects empty input and duplicate Mailbox ids. |
| `VacationResponseUpdate`, `VacationResponseUpdateSet` | `mail/vacation.nim` | Six-variant case object plus a `distinct seq[VacationResponseUpdate]`. Smart constructor `initVacationResponseUpdateSet` rejects empty input and duplicate target properties. |
| `EmailCopyHandles` | `mail/mail_builders.nim` | Type alias for `CompoundHandles[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]` (inherits `primary`/`implicit` fields from the generic). |
| `EmailCopyResults` | `mail/mail_builders.nim` | Type alias for `CompoundResults[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]`. |
| `CompoundHandles[A, B]`, `CompoundResults[A, B]` | `dispatch.nim` | Generic compound-method dispatch types (RFC 8620 §5.4). `getBoth(resp, handles)` is the single generic extraction proc. |
| `NameBoundHandle[T]` | `dispatch.nim` | Response handle that pairs a `MethodCallId` with a `MethodName` filter — used for §5.4 implicit-call siblings whose call-id collides with the primary's. |
| `CopyDestroyMode` | `methods.nim` | Case object — `cdmKeep` or `cdmDestroyAfterSuccess(destroyIfInState: Opt[JmapState])` — that the `CopyRequest[T, CopyItem]` serialises to `onSuccessDestroyOriginal` + `destroyFromIfInState`. Smart constructors `keepOriginals()` and `destroyAfterSuccess(...)`. |

Convenience constructors on `EmailUpdate`: five domain-named smart
constructors (`markRead`, `markUnread`, `markFlagged`, `markUnflagged`,
`moveToMailbox`) co-located with the six protocol-primitive
constructors in `mail/email_update.nim`.

### 1.3. Out of Scope

- **EmailSubmission integration.** Part G covers
  `addEmailSubmissionAndEmailSet`, the second compound-method instance
  alongside `addEmailCopyAndDestroy`. Both share the generic
  `CompoundHandles[A, B]` and `CompoundResults[A, B]` from
  `dispatch.nim`; Part F is responsible only for the Email/copy
  participant.
- **Generic update-algebra sharing.** The three update algebras
  (`EmailUpdate`, `MailboxUpdate`, `VacationResponseUpdate`) live in
  their own modules with their own variant kinds; no shared generic
  unifies them. Their serde signatures are convergent
  (`toJson(u: T): (string, JsonNode)` for the per-update emitter,
  `toJson(us: TSet): JsonNode` for the wire patch object) but each
  function is monomorphic.

### 1.4. General Conventions

- **Pure L1/L2/L3 modules.** Every Part F module under `src/` opens
  with `{.push raises: [], noSideEffect.}` followed by
  `{.experimental: "strictCaseObjects".}`. Only `func` is permitted.
- **Result-based error handling.** Every smart constructor returns
  `Result[T, ValidationError]` or `Result[T, seq[ValidationError]]`
  (accumulating). No exceptions.
- **Typed errors on the error rail.** `SetError` outcomes are data on
  the `Result` rail inside `createResults` (and, for `SetResponse[T]`,
  `updateResults` / `destroyResults`). Mail-specific variants are first-
  class members of the central `SetErrorType` enum (e.g. `setBlobNotFound`,
  `setInvalidEmail`, `setTooManyKeywords`); their RFC-mandated payloads
  live on case-branch fields of `SetError` (e.g. `notFound: seq[BlobId]`
  on the `setBlobNotFound` arm).
- **Accumulating constructors when multiple invariants exist.**
  `initEmailUpdateSet`, `parseNonEmptyEmailUpdates`,
  `parseNonEmptyMailboxUpdates`, `initNonEmptyEmailImportMap`, and
  the `init…UpdateSet` family all return
  `Result[T, seq[ValidationError]]` and surface every violation in a
  single Err pass. The shared template `validateUniqueByIt` (in
  `validation.nim`) packages the empty-input + unique-key checks.
- **Total constructors when invariants are discharged at field level.**
  `initEmailCopyItem` and `initEmailImportItem` return the composed
  type directly because every field type (`Id`, `BlobId`,
  `NonEmptyMailboxIdSet`, `KeywordSet`, `UTCDate`) is itself
  smart-constructed and no cross-field invariant exists at the
  composition level.
- **Postel's law, sender-side strict.** Creation models
  (`EmailCopyItem`, `EmailImportItem`, `EmailUpdate`, `EmailUpdateSet`,
  `NonEmptyEmailUpdates`, `MailboxUpdate`, `MailboxUpdateSet`,
  `NonEmptyMailboxUpdates`, `VacationResponseUpdate`,
  `VacationResponseUpdateSet`, `NonEmptyEmailImportMap`) define
  `toJson` only. The server never sends these shapes back; making
  `fromJson` available would introduce a second construction path and
  violate "constructors are privileges, not rights."
- **Creation/response types co-located with their read model when the
  cluster is small; dedicated module otherwise.** `EmailCopyItem`,
  `EmailImportItem`, `NonEmptyEmailImportMap`, `EmailCreatedItem`,
  and `EmailImportResponse` live inline in `mail/email.nim` (§8.3
  `ParsedEmail`-alongside-`Email` precedent). `EmailUpdate` and its
  conflict-detection ADT warrant their own module
  (`email_update.nim`) because of the six variants, three conflict
  classes, five convenience constructors, named `Conflict`/`PathOp`
  helpers, and dependencies on `KeywordSet` /
  `NonEmptyMailboxIdSet`. `MailboxUpdate` and `VacationResponseUpdate`
  are simpler and append inline to their existing home modules.

### 1.5. Module Summary

| Module | Layer | Contents |
|--------|-------|----------|
| `mail/email.nim` | L1 | `EmailCreatedItem`, `EmailImportResponse`, `EmailCopyItem` + `initEmailCopyItem`, `EmailImportItem` + `initEmailImportItem`, `NonEmptyEmailImportMap` + `initNonEmptyEmailImportMap`. |
| `mail/email_update.nim` | L1 | `EmailUpdateVariantKind`, `EmailUpdate`, six protocol-primitive constructors, five domain-named convenience constructors, `EmailUpdateSet` + `initEmailUpdateSet` (with internal `Conflict`/`PathOp`/`PathShape` ADT and `samePathConflicts` / `parentPrefixConflicts` / `toValidationError` helpers), `NonEmptyEmailUpdates` + `parseNonEmptyEmailUpdates`. |
| `mail/serde_email.nim` | L2 | `toJson`/`fromJson` for `EmailCreatedItem`; `toJson`/`fromJson` for `EmailImportResponse`; `toJson` only for `EmailCopyItem`, `EmailImportItem`, `NonEmptyEmailImportMap`. |
| `mail/serde_email_update.nim` | L2 | `toJson(EmailUpdate)`, `toJson(EmailUpdateSet)`, `toJson(NonEmptyEmailUpdates)`. |
| `mail/mailbox.nim` | L1 | `MailboxUpdateVariantKind`, `MailboxUpdate`, five constructors, `MailboxUpdateSet` + `initMailboxUpdateSet`, `NonEmptyMailboxUpdates` + `parseNonEmptyMailboxUpdates` (under "Mailbox Update Algebra" sections). |
| `mail/serde_mailbox.nim` | L2 | `toJson(MailboxUpdate)`, `toJson(MailboxUpdateSet)`, `toJson(NonEmptyMailboxUpdates)`. |
| `mail/vacation.nim` | L1 | `VacationResponseUpdateVariantKind`, `VacationResponseUpdate`, six constructors, `VacationResponseUpdateSet` + `initVacationResponseUpdateSet`. |
| `mail/serde_vacation.nim` | L2 | `toJson(VacationResponseUpdate)`, `toJson(VacationResponseUpdateSet)`. |
| `mail/mail_builders.nim` | L3 | `addEmailSet`, `addEmailCopy`, `addEmailCopyAndDestroy`; `EmailCopyHandles` and `EmailCopyResults` aliases over the generic; `addMailboxSet` typed on `MailboxCreate` + `NonEmptyMailboxUpdates`. |
| `mail/mail_methods.nim` | L3 | `addEmailImport`; `addVacationResponseSet` typed on `VacationResponseUpdateSet` (singleton id remains hard-coded as `VacationResponseSingletonId`). |
| `mail/mail_entities.nim` | L1 | `setMethodName(typedesc[Email])`, `copyMethodName(typedesc[Email])`, `importMethodName(typedesc[Email])`, plus the entity-resolver templates `createType[T]`, `updateType[T]`, `setResponseType[T]`, `copyItemType[T]`, `copyResponseType[T]` for Email and Mailbox. `registerCompoundMethod(CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem])` enables Part F's compound participant. |
| `methods_enum.nim` | L1 | `mnEmailSet`, `mnEmailCopy`, `mnEmailImport` variants. |
| `methods.nim` | L1 | `SetRequest[T, C, U]` (three-parameter, `mixin toJson` on `C` and `U`); `CopyRequest[T, CopyItem]`; `CopyDestroyMode` + `keepOriginals()` + `destroyAfterSuccess()`; `SetResponse[T]` (`createResults` typed on `T`, `updateResults: Table[Id, Result[Opt[JsonNode], SetError]]`); `CopyResponse[T]`. |
| `dispatch.nim` | L1 | `NameBoundHandle[T]`, `CompoundHandles[A, B]`, `CompoundResults[A, B]`, generic `getBoth`, the `registerCompoundMethod` participation gate. |
| `validation.nim` | L1 | `validateUniqueByIt` template — used by every accumulating Part F smart constructor. |
| `serde.nim` | L1 | `jsonPointerEscape` (RFC 6901 §3 reference-token escaping). Used by `serde_email_update.nim` for keyword tokens. |

---

## 2. Shared Response Surface

### 2.1. EmailCreatedItem

RFC 8621 §§4.6, 4.7, 4.8 each specify verbatim that a successful create
entry contains exactly four properties: `id`, `blobId`, `threadId`, and
`size`. Three methods, identical successful-create shape; one typed
record consumed by all three response types:

```nim
type EmailCreatedItem* {.ruleOff: "objects".} = object
  id*: Id           ## JMAP object id of the created Email.
  blobId*: BlobId   ## Blob id for the raw RFC 5322 octets.
  threadId*: Id     ## Thread the created Email belongs to.
  size*: UnsignedInt ## Raw message size in octets.
```

All four fields are required and carry no `Opt`. `EmailCreatedItem.fromJson`
returns `Result[EmailCreatedItem, SerdeViolation]`; a server response
that omits any of the four fields short-circuits the surrounding
`SetResponse[EmailCreatedItem].fromJson` (or
`CopyResponse[EmailCreatedItem].fromJson`, or
`EmailImportResponse.fromJson`) with that violation rather than
fabricating a partial value.

### 2.2. Response Types

`Email/set` and `Email/copy` reuse the **generic** response types
defined in `methods.nim`:

```nim
type SetResponse*[T] = object
  accountId*: AccountId
  oldState*: Opt[JmapState]
  newState*: Opt[JmapState]
  createResults*: Table[CreationId, Result[T, SetError]]
  updateResults*: Table[Id, Result[Opt[JsonNode], SetError]]
  destroyResults*: Table[Id, Result[void, SetError]]

type CopyResponse*[T] = object
  fromAccountId*: AccountId
  accountId*: AccountId
  oldState*: Opt[JmapState]
  newState*: Opt[JmapState]
  createResults*: Table[CreationId, Result[T, SetError]]
```

For Part F, `T = EmailCreatedItem` at every Email-write site. The
generic resolves `T.fromJson` via `mixin` at each builder's
instantiation; `mail_builders.nim` and `mail_methods.nim` `export
serde_email` so the dispatch site has the resolver in scope.

`updateResults` carries `Result[Opt[JsonNode], SetError]`: `Opt.none`
encodes the wire `null` value RFC 8620 §5.3 admits ("server made no
changes the client doesn't already know"), and `Opt.some(node)` encodes
a non-null property-delta object. The library passes the `JsonNode`
through verbatim because the set of properties the server may alter is
open-ended; per-entity partial typing of update payloads is not in
scope.

`destroyResults` carries `Result[void, SetError]`: `Result.ok()` on
successful destroy, `Result.err(setError)` on rejection. Wire `destroyed`
arrays project to `ok()` rows; wire `notDestroyed` maps project to
`err(...)` rows.

`oldState` and `newState` are both `Opt[JmapState]`. RFC 8620 §5.3
mandates `newState`, but Stalwart 0.15.5 omits it from
`/set` and `/copy` responses whose only populated rails are failure
maps. Lenient on receive (Postel's law); consumers needing the
post-call state fall back to a fresh `<entity>/get`.

`Email/import` keeps its bespoke response (no generic
`ImportResponse[T]` exists in core):

```nim
type EmailImportResponse* {.ruleOff: "objects".} = object
  accountId*: AccountId
  oldState*: Opt[JmapState]
  newState*: Opt[JmapState]
  createResults*: Table[CreationId, Result[EmailCreatedItem, SetError]]
```

Same `Opt[JmapState]` lenience as the generics for the same Stalwart
reason.

### 2.3. Serde

`SetResponse[T].fromJson` and `CopyResponse[T].fromJson` (in
`methods.nim`) merge the wire `created`/`notCreated` parallel maps
through `mergeCreateResults[T]`, which calls `T.fromJson` on each
successful entry; similar `mergeUpdateResults` and `mergeDestroyResults`
helpers feed `updateResults` and `destroyResults`. `T.fromJson` is
`mixin`-resolved at the caller's instantiation scope.

`EmailImportResponse.fromJson` (in `serde_email.nim`) implements its
own `mergeCreatedResults` helper because the surrounding response shape
is bespoke; the inner per-entry `EmailCreatedItem.fromJson` is the
same parser the generic path uses.

### 2.4. Why typed `EmailCreatedItem` rather than raw `JsonNode`

- **Parse once at the boundary.** The four-field shape is fully
  specified by the RFC. There is no ambiguity a consumer could resolve
  that the serde layer cannot resolve identically.
- **Make illegal states unrepresentable.** A response lacking any of
  the four RFC-mandated fields is malformed; `EmailCreatedItem` refuses
  to construct from such JSON.
- **One source of truth.** Three methods, one shape. Defining
  `EmailCreatedItem` once and threading it through three response
  types is simpler than three parallel ad-hoc shapes and cannot drift.

---

## 3. Typed Update Algebras

### 3.1. Why the wire `PatchObject` cannot be the public type

RFC 8620 §5.3 specifies the wire patch shape: a JSON object whose
string keys are JSON Pointer paths into the updated entity, and whose
values are the replacement values (or `null` for removal from a
sub-path):

```json
{
  "keywords/$seen": true,
  "mailboxIds/abc": null,
  "mailboxIds/def": true
}
```

At the wire level, this shape is irreducible. The library's question
is where the boundary sits: which types may construct this shape
directly. Exposing a raw `Table[string, JsonNode]` as the public
update parameter fails the library's principles repeatedly:

- **Make illegal states unrepresentable.** Any string is a valid key
  at the type level. Invalid JSON Pointer paths, conflicting operations
  on the same sub-path, and nonsense values
  (`"keywords/$seen": "hello"` where RFC requires `true`/`null`) all
  construct without complaint.
- **Parse once at the boundary.** The RFC's update rules live in prose,
  not code; a programmatically-built patch table has no type-level
  guarantee of acceptance.
- **One source of truth.** The rules ("you may add a keyword", "you
  may replace the full keyword set", "you may not do both in the same
  patch") live in the caller's mental model. The type system holds
  none of it.
- **Right thing easy.** Zero affordance toward domain verbs. A caller
  who wants "mark this email as read" must know that the wire key is
  `keywords/$seen`, that the value must be boolean `true` not the
  string `"true"`, and that this cannot be combined with full-replace
  on `keywords` in the same patch.

The typed update algebras move all of this knowledge into the type
system. The caller expresses intent in domain verbs (`markRead()`,
`addToMailbox(id)`, `setKeywords(ks)`); the library converts to the
wire patch at the serde layer; the smart constructor rejects every
conflicting combination before the patch leaves the client.

`PatchObject` is not a public type in this codebase. The mail
`/set`/`/copy`/`/import` APIs accept only the typed algebra inputs;
the only path to a wire patch object is through their `toJson`
overloads.

### 3.2. EmailUpdate

#### 3.2.1. Variants

```nim
type EmailUpdateVariantKind* = enum
  euAddKeyword
  euRemoveKeyword
  euSetKeywords
  euAddToMailbox
  euRemoveFromMailbox
  euSetMailboxIds

type EmailUpdate* {.ruleOff: "objects".} = object
  case kind*: EmailUpdateVariantKind
  of euAddKeyword, euRemoveKeyword:
    keyword*: Keyword
  of euSetKeywords:
    keywords*: KeywordSet
  of euAddToMailbox, euRemoveFromMailbox:
    mailboxId*: Id
  of euSetMailboxIds:
    mailboxes*: NonEmptyMailboxIdSet
```

Six variants, one per RFC-sanctioned wire patch operation:

| Variant | Wire path (target) | Wire value | RFC semantic |
|---------|--------------------|------------|--------------|
| `euAddKeyword(k)` | `keywords/{keyword}` | `true` | Add keyword `k` to the email's keyword set. |
| `euRemoveKeyword(k)` | `keywords/{keyword}` | `null` | Remove keyword `k`. |
| `euSetKeywords(ks)` | `keywords` | object | Replace the full keyword set. |
| `euAddToMailbox(id)` | `mailboxIds/{id}` | `true` | Add this email to mailbox `id`. |
| `euRemoveFromMailbox(id)` | `mailboxIds/{id}` | `null` | Remove this email from mailbox `id`. |
| `euSetMailboxIds(ids)` | `mailboxIds` | object | Replace the full mailbox-membership set. |

`{keyword}` denotes the keyword value (which for IANA-registered
keywords begins with a literal `$`, e.g. `$seen`); `{id}` denotes a
bare `Id`. The keyword token is RFC 6901 escaped at serialisation
(see §3.2.5); the id requires no escaping because the `Id` charset
(RFC 8620 §1.2) excludes `/` and `~`.

The library does not expose update paths for other Email properties
(`receivedAt`, `subject`, body fields): those are set-at-creation-only
per RFC §4.6 and changing them after creation is either forbidden or
meaningless.

#### 3.2.2. Protocol-primitive smart constructors

Six constructors, one per variant. Each is total (returns
`EmailUpdate` directly, no `Result`) because all field-level
invariants are pre-discharged by the field types' own smart
constructors (`Keyword`, `KeywordSet`, `Id`, `NonEmptyMailboxIdSet`):

```nim
func addKeyword*(k: Keyword): EmailUpdate
func removeKeyword*(k: Keyword): EmailUpdate
func setKeywords*(ks: KeywordSet): EmailUpdate
func addToMailbox*(id: Id): EmailUpdate
func removeFromMailbox*(id: Id): EmailUpdate
func setMailboxIds*(ids: NonEmptyMailboxIdSet): EmailUpdate
```

#### 3.2.3. Domain-named convenience constructors

Five domain-named constructors. Each is a thin alias producing a value
structurally identical to one of the protocol-primitive variants:

```nim
func markRead*(): EmailUpdate          ## ≡ addKeyword(kwSeen)
func markUnread*(): EmailUpdate        ## ≡ removeKeyword(kwSeen)
func markFlagged*(): EmailUpdate       ## ≡ addKeyword(kwFlagged)
func markUnflagged*(): EmailUpdate     ## ≡ removeKeyword(kwFlagged)
func moveToMailbox*(id: Id): EmailUpdate ## ≡ setMailboxIds(NonEmpty[id])
```

`kwSeen` and `kwFlagged` are IANA-registered constants from
`mail/keyword.nim`; the convenience constructors introduce no new
`Keyword` values.

##### 3.2.3.1. Why `moveToMailbox` emits `euSetMailboxIds`, not `euAddToMailbox`

The name "move" is domain-loaded. Universal mail UI conventions —
Gmail's "Archive", Apple Mail's "Move", every desktop IMAP client's
"Move" — treat "move X to Y" as **replace** semantics, not **add**
semantics. The protocol-primitive `addToMailbox(id)` is available for
callers who genuinely want additive membership; the domain verb
`moveToMailbox` aligns with how mail users understand the word.
Choosing `euAddToMailbox` would introduce a name/semantics mismatch
(caller reads "move", wire does "add", email ends up in an unexpected
second mailbox).

#### 3.2.4. EmailUpdateSet + conflict algebra

```nim
type EmailUpdateSet* = distinct seq[EmailUpdate]

func initEmailUpdateSet*(
    updates: openArray[EmailUpdate]
): Result[EmailUpdateSet, seq[ValidationError]]
```

Conflict detection is a three-stage pipeline owned by `email_update.nim`:

1. **`classify(u: EmailUpdate): PathOp`** — compute target path,
   parent path, and kind for one update. JSON Pointer escaping is
   deferred to the serde layer; classification reasons in logical paths.
2. **`samePathConflicts(ops): seq[Conflict]`** — Class 1 (duplicate
   target path) and Class 2 (opposite operations on the same sub-path).
   Walks the op sequence, tracking the first kind seen at each target
   path via `withValue` (raises-free, total under
   `{.push raises: [].}`). Subsequent writes at the same path compare
   against the first occurrence.
3. **`parentPrefixConflicts(ops): seq[Conflict]`** — Class 3
   (sub-path operation alongside full-replace on the same parent).
   Computed as the set intersection of the parent paths of full-replace
   ops with the parent paths of sub-path ops.

Each conflict surfaces as a typed `Conflict` ADT, then translates to
the wire `ValidationError` shape through a single
`toValidationError(c: Conflict)` boundary so adding a `ConflictKind`
variant forces a compile error at exactly one place:

```nim
type ConflictKind = enum
  ckDuplicatePath
  ckOppositeOps
  ckPrefixCollision

type Conflict = object
  case kind: ConflictKind
  of ckDuplicatePath, ckOppositeOps:
    targetPath: string
  of ckPrefixCollision:
    property: string
```

For each variant a **target path**:

| Variant | Target path | Operation kind |
|---------|-------------|----------------|
| `euAddKeyword(k)` | `keywords/{keyword}` | sub-path write (value `true`) |
| `euRemoveKeyword(k)` | `keywords/{keyword}` | sub-path write (value `null`) |
| `euSetKeywords(ks)` | `keywords` | full-replace |
| `euAddToMailbox(id)` | `mailboxIds/{id}` | sub-path write (value `true`) |
| `euRemoveFromMailbox(id)` | `mailboxIds/{id}` | sub-path write (value `null`) |
| `euSetMailboxIds(ids)` | `mailboxIds` | full-replace |

**Class 1 — Duplicate target path.** Two or more updates with the same
target path. Examples:
- `euAddKeyword(kwSeen)` appearing twice (target: `keywords/$seen`)
- `euSetKeywords(ks1)` and `euSetKeywords(ks2)` (both target: `keywords`)

Rejected because a JSON object with two identical keys is not a valid
JSON object; one of the values would silently shadow the other,
hiding the caller's intent.

**Class 2 — Opposite operations on the same sub-path.** Examples:
- `euAddKeyword(kwSeen)` + `euRemoveKeyword(kwSeen)` (both target
  `keywords/$seen` with opposite values)
- `euAddToMailbox(id1)` + `euRemoveFromMailbox(id1)` (both target
  `mailboxIds/id1` with opposite values)

Rejected because the wire shape would carry a single key with a
last-write-wins value; one of the two operations is a no-op.

**Class 3 — Sub-path operation alongside full-replace on same parent.**
Examples:
- `euAddKeyword(kwSeen)` + `euSetKeywords(ks)` (both operate on
  `keywords`)
- `euAddToMailbox(id1)` + `euSetMailboxIds(ids)` (both operate on
  `mailboxIds`)

Rejected categorically by RFC 8620 §5.3: "There MUST NOT be two
patches in the PatchObject where the pointer of one is the prefix of
the pointer of the other." Emitting this shape is a wire-level
protocol violation, so the typed algebra refuses to construct it.

**Independent cases (NOT conflicts):**
- `euSetKeywords(ks)` + `euSetMailboxIds(ids)` — different parent
  paths (`keywords` vs `mailboxIds`).
- `euAddKeyword(kwSeen)` + `euAddKeyword(kwFlagged)` — different
  sub-paths.
- `euAddKeyword(kwSeen)` + `euAddToMailbox(id1)` — different parents.

**Empty input also rejected.** `initEmailUpdateSet(@[])` returns
`Err(@[validationError("EmailUpdateSet", "must contain at least one update", "")])`.
The whole-container `NonEmptyEmailUpdates` parameter on the builder
has exactly one "no updates for this id" representation: omit the
entry from the table entirely. Permitting an empty `EmailUpdateSet`
value would introduce a parallel encoding and a wasteful empty
`{}`-shaped wire patch.

The smart constructor performs every check in a single pass and
surfaces every detected conflict in one Err response. The caller
sees every issue at once, not just the first one.

#### 3.2.5. Serde

`PatchObject` keys are JSON Pointers per RFC 8620 §5.3. RFC 6901 §3
requires two characters to be escaped within a reference token: `~`
becomes `~0` and `/` becomes `~1`. RFC 8621 §4.1.1 lists the keyword
charset as ASCII `%x21-%x7e` minus `( ) { ] % * " \` — the set
explicitly **does not** exclude `/` or `~`, so a spec-faithful
`Keyword` smart constructor must accept keywords containing them.
Escaping therefore belongs at the serialisation boundary, not on the
type. `Id` values are restricted to `[A-Za-z0-9_-]` and need no
escaping.

The `jsonPointerEscape` helper lives in `serde.nim` (shared between
this module and any other reference-token producer); `~` is escaped
before `/` so the `~1` produced for `/` is not re-escaped:

```nim
func toJson*(u: EmailUpdate): (string, JsonNode)
func toJson*(us: EmailUpdateSet): JsonNode
func toJson*(upd: NonEmptyEmailUpdates): JsonNode
```

`toJson(EmailUpdate)` returns a `(wire-key, wire-value)` pair so the
aggregator can install the key directly in a `JObject` without parsing
it back out of a nested node. `toJson(EmailUpdateSet)` is intentionally
mechanical — `initEmailUpdateSet` has already rejected duplicate
target paths and every other conflict class, so blind aggregation
cannot shadow a prior entry. `toJson(NonEmptyEmailUpdates)` flattens
the whole-container algebra to `{emailId: patchObj, ...}`,
the wire `update` value of `Email/set`.

#### 3.2.6. NonEmptyEmailUpdates

```nim
type NonEmptyEmailUpdates* = distinct Table[Id, EmailUpdateSet]

func parseNonEmptyEmailUpdates*(
    items: openArray[(Id, EmailUpdateSet)]
): Result[NonEmptyEmailUpdates, seq[ValidationError]]
```

Whole-container update algebra — the builder's `update:` parameter
type. The accumulating smart constructor rejects:

- **Empty input.** The builder's `update: Opt[NonEmptyEmailUpdates]`
  has exactly one "no updates" representation (`Opt.none`). Permitting
  an empty `NonEmptyEmailUpdates` value would introduce a parallel
  encoding and a wasteful empty `{}`-shaped wire `update` value.
- **Duplicate Email ids.** Silent last-wins shadowing at `Table`
  construction would swallow caller data; `openArray[(Id,
  EmailUpdateSet)]` (rather than `Table`) preserves duplicates for
  inspection.

The `validateUniqueByIt` template in `validation.nim` discharges both
checks in one pass; each repeated id is reported exactly once
regardless of occurrence count.

### 3.3. MailboxUpdate

RFC 8621 §2 lists the settable Mailbox properties. Unlike `EmailUpdate`,
none of these have a sub-path / full-replace tension — every settable
Mailbox property is a whole-value replace.

```nim
type MailboxUpdateVariantKind* = enum
  muSetName
  muSetParentId
  muSetRole
  muSetSortOrder
  muSetIsSubscribed

type MailboxUpdate* {.ruleOff: "objects".} = object
  case kind*: MailboxUpdateVariantKind
  of muSetName:        name*: string
  of muSetParentId:    parentId*: Opt[Id]   # null = top-level
  of muSetRole:        role*: Opt[MailboxRole] # null = clear role
  of muSetSortOrder:   sortOrder*: UnsignedInt
  of muSetIsSubscribed: isSubscribed*: bool
```

Five total smart constructors, one per variant: `setName`,
`setParentId`, `setRole`, `setSortOrder`, `setIsSubscribed`. No
domain-named convenience wrappers — `Mailbox` mutations are rare in
typical client flows, and the set is small enough that aliases would
dilute rather than clarify.

```nim
type MailboxUpdateSet* = distinct seq[MailboxUpdate]

func initMailboxUpdateSet*(
    updates: openArray[MailboxUpdate]
): Result[MailboxUpdateSet, seq[ValidationError]]
```

The smart constructor rejects:
- **Empty input.**
- **Duplicate target property** — two updates with the same `kind`
  (e.g. two `muSetName`) would produce a JSON patch object with
  duplicate keys.

Class 2 and Class 3 do not apply: whole-value replace leaves no
sub-path to conflict with. `validateUniqueByIt` packages both checks.

```nim
type NonEmptyMailboxUpdates* = distinct Table[Id, MailboxUpdateSet]

func parseNonEmptyMailboxUpdates*(
    items: openArray[(Id, MailboxUpdateSet)]
): Result[NonEmptyMailboxUpdates, seq[ValidationError]]
```

Whole-container algebra — `addMailboxSet`'s `update:` parameter.
Same empty-input + unique-id discipline as `parseNonEmptyEmailUpdates`.

Serde (in `serde_mailbox.nim`) is mechanical — each variant emits
exactly one top-level key; no sub-path flattening. `toJson(MailboxUpdate)`
returns the `(key, value)` pair; `toJson(MailboxUpdateSet)` aggregates
into a JSON object; `toJson(NonEmptyMailboxUpdates)` flattens to
`{mailboxId: patchObj, ...}`.

### 3.4. VacationResponseUpdate

RFC 8621 §8 specifies the VacationResponse singleton's settable
properties. Structurally identical to `MailboxUpdate`:

```nim
type VacationResponseUpdateVariantKind* = enum
  vruSetIsEnabled
  vruSetFromDate
  vruSetToDate
  vruSetSubject
  vruSetTextBody
  vruSetHtmlBody

type VacationResponseUpdate* {.ruleOff: "objects".} = object
  case kind*: VacationResponseUpdateVariantKind
  of vruSetIsEnabled:  isEnabled*: bool
  of vruSetFromDate:   fromDate*: Opt[UTCDate]
  of vruSetToDate:     toDate*: Opt[UTCDate]
  of vruSetSubject:    subject*: Opt[string]
  of vruSetTextBody:   textBody*: Opt[string]
  of vruSetHtmlBody:   htmlBody*: Opt[string]

type VacationResponseUpdateSet* = distinct seq[VacationResponseUpdate]

func initVacationResponseUpdateSet*(
    updates: openArray[VacationResponseUpdate]
): Result[VacationResponseUpdateSet, seq[ValidationError]]
```

Six total constructors (`setIsEnabled`, `setFromDate`, `setToDate`,
`setSubject`, `setTextBody`, `setHtmlBody`). Smart constructor rejects
empty input and duplicate target property via `validateUniqueByIt`.

There is no `NonEmptyVacationResponseUpdates` whole-container type:
RFC 8621 §8 forbids any id other than `"singleton"`. The
`addVacationResponseSet` builder takes `update:
VacationResponseUpdateSet` directly and wraps it under
`VacationResponseSingletonId` in the wire `update` map.

### 3.5. Module home rationale

`EmailUpdate` and its conflict-detection ADT warrant a dedicated
`mail/email_update.nim` because the type cluster is non-trivial: six
variants with four distinct payload shapes; eleven public constructors
(six primitive + five convenience); three conflict classes;
internal `Conflict`/`PathOp`/`PathShape` ADT and `samePathConflicts` /
`parentPrefixConflicts` / `toValidationError` helpers; dependencies
on `Keyword`, `KeywordSet`, `Id`, `NonEmptyMailboxIdSet`.

`MailboxUpdate`, `MailboxUpdateSet`, and `NonEmptyMailboxUpdates`
append inline to `mail/mailbox.nim` under "Mailbox Update Algebra"
sections. `VacationResponseUpdate` and `VacationResponseUpdateSet`
append inline to `mail/vacation.nim`. Both inline appendings preserve
each entity's full modelling in its home file (one source of truth
per entity); the `EmailUpdate` exception is justified by the cluster's
specific complexity.

---

## 4. Email/set

RFC 8621 §4.6 specifies `Email/set` as a standard RFC 8620 §5.3 `/set`
method with no additional request arguments. The builder is a thin
wrapper over the generic `addSet[T, C, U, R]`.

### 4.1. Builder Signature

```nim
func addEmailSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, EmailBlueprint]] =
      Opt.none(Table[CreationId, EmailBlueprint]),
    update: Opt[NonEmptyEmailUpdates] = Opt.none(NonEmptyEmailUpdates),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): (RequestBuilder, ResponseHandle[SetResponse[EmailCreatedItem]])
```

Internally it calls
`addSet[Email, EmailBlueprint, NonEmptyEmailUpdates, SetResponse[EmailCreatedItem]]`
with no entity-specific extras. The generic resolves the four
type-class methods at instantiation:

- `setMethodName(typedesc[Email]) → mnEmailSet` (registered in
  `mail_entities.nim`).
- `capabilityUri(typedesc[Email]) → "urn:ietf:params:jmap:mail"`.
- `EmailBlueprint.toJson` and `NonEmptyEmailUpdates.toJson` via
  `mixin`.

Key choices:

- **`create` is typed `EmailBlueprint`** (Part E's creation aggregate),
  not raw `JsonNode`. The generic `SetRequest[T, C, U].toJson` calls
  `C.toJson` per entry through `mixin`.
- **`update` is typed `NonEmptyEmailUpdates`.** The whole-container
  algebra carries the non-empty + unique-id invariants; the per-target
  `EmailUpdateSet` carries the conflict-free invariants. Raw
  `Table[string, JsonNode]` patches cannot reach the wire from outside
  the serde layer.
- **No method-specific extras.** RFC §4.6 defines none (contrast
  Mailbox's `onDestroyRemoveEmails`).
- **`destroy` uses `Referencable[seq[Id]]`** — the standard JMAP
  back-reference mechanism. Literal ids or a result-reference into a
  previous invocation's output, both supported.
- **Empty `create`/`update`/`destroy` permitted at the wire level via
  `Opt.none` defaults.** A bare `Email/set { accountId: "..." }`
  invocation is wire-legal (return state, make no changes).

### 4.2. Response Handling

`ResponseHandle[SetResponse[EmailCreatedItem]]` is the typed phantom
handle. Dispatch (`get(handle)` in `dispatch.nim`) returns
`Result[SetResponse[EmailCreatedItem], MethodError]` on the outer
railway:

- `createResults: Table[CreationId, Result[EmailCreatedItem, SetError]]`
  carries successful and failed creates per CreationId.
- `updateResults: Table[Id, Result[Opt[JsonNode], SetError]]` carries
  successful updates (with `Opt.none` for "no further changes" or
  `Opt.some(deltaNode)` for server-altered properties) and failed
  updates per id.
- `destroyResults: Table[Id, Result[void, SetError]]` carries
  successful destroys (`Result.ok()`) and failed destroys per id.

`SetError.errorType` carries the typed RFC variant directly — including
mail-specific variants (`setBlobNotFound`, `setTooManyKeywords`, etc.) —
and `rawType` preserves the wire string verbatim for variants the enum
does not enumerate (`setUnknown`). See §7 for the full extraction surface.

### 4.3. addMailboxSet

`addMailboxSet` is the parallel wrapper for `Mailbox/set`. It takes
the same shape with substitutions:

```nim
func addMailboxSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, MailboxCreate]] =
      Opt.none(Table[CreationId, MailboxCreate]),
    update: Opt[NonEmptyMailboxUpdates] = Opt.none(NonEmptyMailboxUpdates),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    onDestroyRemoveEmails: bool = false,
): (RequestBuilder, ResponseHandle[SetResponse[MailboxCreatedItem]])
```

Differences from `addEmailSet`:

- `create` carries `MailboxCreate` (Part B's creation model) instead
  of `EmailBlueprint`.
- `update` carries `NonEmptyMailboxUpdates`.
- The `SetResponse[T]` payload is `MailboxCreatedItem` rather than the
  full `Mailbox` because RFC 8620 §5.3's `created[cid]` carries only
  the server-set subset (id + counts + myRights), and Stalwart 0.15.5
  further trims to `{"id": "..."}`. `MailboxCreatedItem`'s five
  non-id fields are `Opt[T]`.
- `onDestroyRemoveEmails: bool` extension key (RFC 8621 §2.5) is
  emitted unconditionally via the generic's `extras` parameter.

---

## 5. Email/copy

### 5.1. EmailCopyItem

RFC 8621 §4.7:

> This is a standard "/copy" method as described in [RFC 8620], Section 5.4,
> except only the "mailboxIds", "keywords", and "receivedAt" properties
> may be set during the copy.

`EmailCopyItem` constrains the creation entry to exactly those three
override properties plus the source-email id:

```nim
type EmailCopyItem* {.ruleOff: "objects".} = object
  id*: Id                              ## Source email id in the from-account.
  mailboxIds*: Opt[NonEmptyMailboxIdSet]
  keywords*: Opt[KeywordSet]
  receivedAt*: Opt[UTCDate]

func initEmailCopyItem*(
    id: Id,
    mailboxIds: Opt[NonEmptyMailboxIdSet] = Opt.none(NonEmptyMailboxIdSet),
    keywords: Opt[KeywordSet] = Opt.none(KeywordSet),
    receivedAt: Opt[UTCDate] = Opt.none(UTCDate),
): EmailCopyItem
```

`mailboxIds` is `Opt[NonEmptyMailboxIdSet]`. RFC §4.7 lists the three
override properties but is silent on cardinality; the non-emptiness
requirement derives from RFC §4.1.1's "An Email in the mail store
MUST belong to one or more Mailboxes at all times" applied to the
resulting Email after the override is merged. If supplied, the override
replaces the source's mailbox membership wholesale — so the override
itself must be non-empty. `NonEmptyMailboxIdSet` encodes this on the
override type directly.

The constructor is total: every field type is itself smart-constructed,
and no cross-field invariant exists at the composition level.

### 5.2. Simple overload — `addEmailCopy`

```nim
func addEmailCopy*(
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, EmailCopyItem],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[CopyResponse[EmailCreatedItem]])
```

Routes through
`addCopy[Email, EmailCopyItem, CopyResponse[EmailCreatedItem]]` with
`destroyMode` left at its default `keepOriginals()`. The
`CopyRequest.toJson` therefore omits `onSuccessDestroyOriginal` from
the wire (RFC 8620 §5.4 default-omission).

`create` is non-`Opt` `Table[CreationId, EmailCopyItem]`. `/copy`
without a `create` map is meaningless; the signature requires the
parameter. Empty map is wire-legal and produces an empty
`createResults` in the response.

### 5.3. Compound overload — `addEmailCopyAndDestroy`

```nim
func addEmailCopyAndDestroy*(
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, EmailCopyItem],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    destroyFromIfInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, EmailCopyHandles)
```

Constructs the same `addCopy[Email, EmailCopyItem, ...]` invocation,
but with `destroyMode = destroyAfterSuccess(destroyFromIfInState)`. The
typed `CopyDestroyMode` case object closes the illegal-state hole that
a flat `(onSuccessDestroyOriginal: bool, destroyFromIfInState:
Opt[JmapState])` parameter pair would leave open: a non-empty
`destroyFromIfInState` alongside `onSuccessDestroyOriginal: false`
would be structurally expressible but semantically meaningless (the
server would silently ignore the state guard because no implicit
destroy was issued). Two variants, two legitimate combinations:

```nim
type CopyDestroyMode* {.ruleOff: "objects".} = object
  case kind*: CopyDestroyModeKind
  of cdmKeep:
    discard
  of cdmDestroyAfterSuccess:
    destroyIfInState*: Opt[JmapState]
```

`CopyRequest[T, CopyItem].toJson` (in `methods.nim`) emits:

- `cdmKeep` — no `onSuccessDestroyOriginal` key, no
  `destroyFromIfInState` key.
- `cdmDestroyAfterSuccess` — `onSuccessDestroyOriginal: true`; emits
  `destroyFromIfInState` only if `destroyIfInState.isSome`.

On successful copy, the server appends an implicit `Email/set`
destroy invocation to the response sharing the primary's
method-call-id. The return shape — `EmailCopyHandles` — tells the
caller there are two responses to handle.

**Verb naming.** `addEmailCopyAndDestroy` (not `addEmailCopyChained`).
"Chained" describes a protocol mechanism (back-reference threading);
"and destroy" describes the domain outcome (original is gone after
this succeeds). Outcome framing keeps a single abstraction across the
overload name and the eventual handle pair (whose typed extraction
yields `CopyResponse[...]` + `SetResponse[...]`).

`destroyFromIfInState` controls the optimistic-concurrency assertion
for the source account's destroy. The parameter exists only on the
compound overload because the simple overload emits no destroy.

### 5.4. EmailCopyHandles / EmailCopyResults / getBoth

`EmailCopyHandles` and `EmailCopyResults` are domain-named
specialisations of the generic dispatch types in `dispatch.nim`:

```nim
# dispatch.nim
type CompoundHandles*[A, B] {.ruleOff: "objects".} = object
  primary*: ResponseHandle[A]
  implicit*: NameBoundHandle[B]

type CompoundResults*[A, B] {.ruleOff: "objects".} = object
  primary*: A
  implicit*: B

func getBoth*[A, B](
    resp: Response, handles: CompoundHandles[A, B]
): Result[CompoundResults[A, B], MethodError]

# mail/mail_builders.nim
type EmailCopyHandles* =
  CompoundHandles[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]

type EmailCopyResults* =
  CompoundResults[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]
```

Field access through `EmailCopyHandles` therefore uses `primary` and
`implicit`, inherited from the generic. The `getBoth` extraction proc
is the generic's; no mail-specific override is required.

`primary: ResponseHandle[CopyResponse[EmailCreatedItem]]` dispatches
through the default `get[T]` overload using its `MethodCallId`.
`implicit: NameBoundHandle[SetResponse[EmailCreatedItem]]` carries the
primary's `MethodCallId` paired with `methodName: mnEmailSet`;
dispatch resolves through `get[T](resp, h: NameBoundHandle[T])`,
which scans `methodResponses` for the first invocation matching both
call-id AND method-name. RFC 8620 §5.4's compound overloads share a
call-id between the primary and its implicit follow-up, so the
method-name filter is what distinguishes them.

`addEmailCopyAndDestroy` constructs the handle pair as follows:

```nim
let (b1, copyHandle) = addCopy[Email, EmailCopyItem, CopyResponse[EmailCreatedItem]](
  b, fromAccountId, accountId, create, ifFromInState, ifInState,
  destroyMode = destroyAfterSuccess(destroyFromIfInState),
)
let handles = EmailCopyHandles(
  primary: copyHandle,
  implicit: NameBoundHandle[SetResponse[EmailCreatedItem]](
    callId: MethodCallId(copyHandle), methodName: mnEmailSet,
  ),
)
```

`mail_entities.nim` enables Email/copy participation in the compound
machinery via:

```nim
registerCompoundMethod(CopyResponse[EmailCreatedItem],
                       SetResponse[EmailCreatedItem])
```

which compile-checks that `CopyResponse[EmailCreatedItem]` parametrises
`ResponseHandle` and `SetResponse[EmailCreatedItem]` parametrises
`NameBoundHandle`.

**Why two non-`Opt` fields, not `implicit: Opt[SetResponse[...]]`?**
The server appends the implicit destroy response if and only if the
copy method itself succeeded. If the copy method-errored (say
`fromAccountNotFound`), no destroy is appended. In that case
`getBoth`'s `?`-short-circuit on `primary` surfaces the copy's
`MethodError` on the `Err` rail before even looking at the implicit
handle; the caller never observes the implicit's absence through
`Opt.none`. If the field were `Opt`-wrapped, the `none` case would be
structurally unreachable on the Ok rail — the type would lie about
what states are representable. If a buggy server elided the implicit
destroy response despite a successful copy, the second extraction
returns `Err(MethodError{rawType: "serverFail"})` via dispatch's
existing missing-call-id handling. Absence surfaces only on the `Err`
rail.

---

## 6. Email/import

### 6.1. EmailImportItem

RFC 8621 §4.8 specifies four properties per import entry:

- `blobId: Id` — the raw `message/rfc822` blob previously uploaded.
- `mailboxIds: Id[Boolean]` — "At least one Mailbox MUST be given."
- `keywords: String[Boolean]` — default empty.
- `receivedAt: UTCDate` — default "time of the most recent Received
  header, or import time on the server if none".

```nim
type EmailImportItem* {.ruleOff: "objects".} = object
  blobId*: BlobId
  mailboxIds*: NonEmptyMailboxIdSet
  keywords*: Opt[KeywordSet]
  receivedAt*: Opt[UTCDate]

func initEmailImportItem*(
    blobId: BlobId,
    mailboxIds: NonEmptyMailboxIdSet,
    keywords: Opt[KeywordSet] = Opt.none(KeywordSet),
    receivedAt: Opt[UTCDate] = Opt.none(UTCDate),
): EmailImportItem
```

`blobId` is `BlobId` (the dedicated newtype for raw-octet blob
references), not the more general `Id`. `mailboxIds` is non-`Opt`
`NonEmptyMailboxIdSet`: the RFC marks `mailboxIds` required and
non-empty; the type reflects both. Contrast `EmailCopyItem.mailboxIds:
Opt[NonEmptyMailboxIdSet]` where the property is optional (override
the source's mailboxes only if specified).

`keywords: Opt[KeywordSet]`. `Opt.none` omits the wire key (server
default: empty). `Opt.some(empty)` is wire-indistinguishable per
RFC §4.8: the serde layer collapses both to an omitted key. A caller
wanting "explicitly empty" may still construct
`Opt.some(initKeywordSet(@[]))` to signal intent in their own code.

`receivedAt: Opt[UTCDate]`. `Opt.none` defers to the server default
(most recent Received header, or import time). The client cannot
replicate this default without parsing the raw RFC 5322 message —
deferral is the principled choice.

The constructor is total: every field type is itself smart-constructed,
and RFC §4.8 specifies zero cross-field invariants on `EmailImport`.

### 6.2. NonEmptyEmailImportMap

```nim
type NonEmptyEmailImportMap* = distinct Table[CreationId, EmailImportItem]

func initNonEmptyEmailImportMap*(
    items: openArray[(CreationId, EmailImportItem)]
): Result[NonEmptyEmailImportMap, seq[ValidationError]]
```

The smart constructor accumulates failures across both invariants in
one pass via `validateUniqueByIt`:

1. **Non-empty.** An empty `emails` map makes the entire `Email/import`
   invocation pointless; reject to prevent the wasteful round-trip.
2. **No duplicate creation-ids.** The `openArray` input (rather than
   `Table`) preserves order and surfaces duplicate keys to the
   constructor.

`openArray[(CreationId, EmailImportItem)]` rather than
`Table[CreationId, EmailImportItem]` because a `Table` input would
have already collapsed duplicates at construction, turning a
data-loss event into a silent accept — exactly the class of error
the smart constructor exists to catch.

### 6.3. Builder Signature

```nim
func addEmailImport*(
    b: RequestBuilder,
    accountId: AccountId,
    emails: NonEmptyEmailImportMap,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[EmailImportResponse])
```

`emails` is required and non-`Opt`: `NonEmptyEmailImportMap`
guarantees the caller has already constructed a valid, non-empty,
duplicate-free entry table. The builder body assembles the args
inline (rather than routing through a shared generic, since
`Email/import` has no generic counterpart):

```
accountId
emails       (via NonEmptyEmailImportMap.toJson)
ifInState    (only when Opt.some)
```

invokes under `mnEmailImport` + `urn:ietf:params:jmap:mail`, and
returns `ResponseHandle[EmailImportResponse]`.

### 6.4. Registration

- `methods_enum.nim` carries `mnEmailImport = "Email/import"`.
- `mail_entities.nim` defines `importMethodName(typedesc[Email]) →
  mnEmailImport` so any future generic-routed import path can resolve
  the method name from the entity typedesc.

### 6.5. Why no generic counterpart

`Email/import` is the only `/import`-shaped method in the JMAP
ecosystem the library targets. No `ImportRequest[T]` /
`ImportResponse[T]` generic pair exists in `methods.nim` because the
Rule of Three has not been reached. The bespoke `addEmailImport` body
and the bespoke `EmailImportResponse` type are the principled choice
at one instance.

---

## 7. SetError Extraction Reference

### 7.1. Unified `SetErrorType` enum

`SetError` is a single case object in `errors.nim`. The discriminator
`errorType: SetErrorType` enumerates every RFC 8620 §5.3 / §5.4 core
variant **and** every RFC 8621 mail-specific variant. There is no
mail-side `MailSetErrorType` enum and no `parseMailSetErrorType` step:
the typed mail variants are first-class members of the central enum,
and their RFC-mandated payloads ride on case-branch fields of
`SetError` itself:

```nim
type SetError* = object
  rawType*: string                 ## lossless wire-string round-trip
  description*: Opt[string]
  extras*: Opt[JsonNode]            ## non-standard fields, preserved
  case errorType*: SetErrorType
  of setInvalidProperties:
    properties*: seq[string]                    ## RFC 8620 §5.3
  of setAlreadyExists:
    existingId*: Id                             ## RFC 8620 §5.4
  of setBlobNotFound:
    notFound*: seq[BlobId]                      ## RFC 8621 §4.6
  of setInvalidEmail:
    invalidEmailPropertyNames*: seq[string]     ## RFC 8621 §7.5
  of setTooManyRecipients:
    maxRecipientCount*: UnsignedInt             ## RFC 8621 §7.5
  of setInvalidRecipients:
    invalidRecipients*: seq[string]             ## RFC 8621 §7.5
  of setTooLarge:
    maxSizeOctets*: Opt[UnsignedInt]            ## RFC 8621 §7.5 SHOULD
  else:
    discard
```

Variants without a typed payload (e.g. `setTooManyKeywords`,
`setTooManyMailboxes`, `setNotFound`, `setOverQuota`, `setForbidden`)
fall through the `else: discard` arm. Wire strings the enum does not
enumerate parse to `setUnknown`; `rawType` preserves the original
string for diagnostic display.

### 7.2. Mail-layer convenience accessors

`mail/mail_errors.nim` ships five mail-specific predicate accessors
that wrap the case-branch reads in `Opt[T]`-returning helpers. They
exist to give mail-domain code a vocabulary keyed off the RFC names
without forcing every call site to spell out the case discriminator:

| Accessor | Returns | Sourced from |
|----------|---------|--------------|
| `notFoundBlobIds` | `Opt[seq[BlobId]]` | `setBlobNotFound.notFound` |
| `maxSize` | `Opt[UnsignedInt]` | `setTooLarge.maxSizeOctets` (already `Opt`) |
| `maxRecipients` | `Opt[UnsignedInt]` | `setTooManyRecipients.maxRecipientCount` |
| `invalidRecipientAddresses` | `Opt[seq[string]]` | `setInvalidRecipients.invalidRecipients` |
| `invalidEmailProperties` | `Opt[seq[string]]` | `setInvalidEmail.invalidEmailPropertyNames` |

Each accessor is a one-line case-dispatch: `Opt.some(payload)` on the
matching `errorType`, `Opt.none` otherwise. Direct case-branch
reads (`case se.errorType of setBlobNotFound: se.notFound`) work
under `strictCaseObjects` because `errorType` is a public discriminator.

Part F adds zero new extraction code. Every RFC §§4.6/4.7/4.8 SetError
variant is reachable either through a direct case-branch read or
through one of the five mail-layer accessors.

### 7.3. Reference Table

| Method | RFC-listed SetError | `SetErrorType` variant | Payload extraction |
|--------|---------------------|------------------------|--------------------|
| Email/set (§4.6) | `invalidProperties` | `setInvalidProperties` | `err.properties: seq[string]` |
| Email/set (§4.6) | `blobNotFound` | `setBlobNotFound` | `err.notFound: seq[BlobId]` (or `err.notFoundBlobIds()`) |
| Email/set (§4.6) | `tooManyKeywords` | `setTooManyKeywords` | no payload; variant is self-describing |
| Email/set (§4.6) | `tooManyMailboxes` | `setTooManyMailboxes` | no payload |
| Email/copy (§4.7) | `alreadyExists` | `setAlreadyExists` | `err.existingId: Id` |
| Email/copy (§4.7) | `notFound` | `setNotFound` | no payload |
| Email/import (§4.8) | `alreadyExists` | `setAlreadyExists` | `err.existingId: Id` |
| Email/import (§4.8) | `invalidEmail` | `setInvalidEmail` | `err.invalidEmailPropertyNames: seq[string]` (or `err.invalidEmailProperties()`) |
| Email/import (§4.8) | `overQuota` | `setOverQuota` | no payload |
| Email/import (§4.8) | `invalidProperties` | `setInvalidProperties` | `err.properties: seq[string]` |

RFC §4.8 does not define a mail-specific `notFound` for `Email/import`.
An unknown `blobId` surfaces as `invalidProperties` per §4.8: "If the
'blobId', 'mailboxIds', or 'keywords' properties are invalid (e.g.,
missing, wrong type, id not found), the server MUST reject the import
with an 'invalidProperties' SetError." The `setTooLarge` variant
(paired with the `maxSizeOctets`/`maxSize` payload) is RFC 8621 §7.5
EmailSubmission territory, but the core `setTooLarge` (RFC 8620 §5.3,
typed `Opt[UnsignedInt]` payload) does apply transitively — see scoping
below.

Core RFC 8620 §5.3 generic SetErrors apply transitively, scoped per
RFC §5.3's per-operation annotations:

| SetError | Email/set | Email/copy | Email/import |
|----------|-----------|------------|--------------|
| `forbidden` | ✓ | ✓ | ✓ |
| `overQuota` | ✓ (create;update) | ✓ (create) | ✓ (create) |
| `tooLarge` | ✓ (create;update) | ✓ (create) | ✓ (create) |
| `rateLimit` | ✓ (create) | ✓ (create) | ✓ (create) |
| `notFound` | ✓ (update) | ✓ (RFC 8620 §5.4 "create or update"; RFC 8621 §4.7 also grants `notFound` explicitly for missing blobId) | — |
| `invalidPatch` | ✓ (update only) | — | — |
| `willDestroy` | ✓ (update only) | — | — |
| `invalidProperties` | ✓ (create;update) | ✓ (create) | ✓ (create) |

`singleton` is not applicable to any Part F method because Email is
not a singleton type.

`invalidPatch` remains relevant: the typed update algebra serialises
to an RFC 8620 §5.3 JSON Pointer patch that a server may reject (for
example, if a keyword contains an unescaped JSON Pointer
metacharacter that the algebra's serde escaping hasn't accounted for —
or if the server uses stricter validation than the client).

**`Email/copy` with `onSuccessDestroyOriginal: true`:** RFC 8620 §5.4
specifies that a successful copy with `onSuccessDestroyOriginal`
emits a *second* response sharing the same method-call-id, an
implicit `Email/set { destroy: [...] }` call on the source account.
The implicit `SetResponse[EmailCreatedItem]` carries its own
`destroyResults` map (per §2.2), populated with destroy-scoped
SetErrors (`notFound`, `forbidden`, `willDestroy`).

### 7.4. Caller flow

Single-step `case` over `err.errorType` reaches every variant. Direct
case-branch field reads are strict-safe because `errorType` is a
public discriminator and `strictCaseObjects` traces flow through a
literal `case` arm:

```nim
case err.errorType
of setAlreadyExists:
  echo "Email already exists at ", string(err.existingId)
of setInvalidProperties:
  echo "Invalid properties: ", err.properties
of setBlobNotFound:
  echo "Blobs not found: ", err.notFound
of setInvalidEmail:
  echo "Invalid email properties: ", err.invalidEmailPropertyNames
of setTooLarge:
  for limit in err.maxSizeOctets:
    echo "Too large, max: ", limit
of setTooManyKeywords, setTooManyMailboxes:
  echo $err.errorType, " (no typed payload)"
of setUnknown:
  echo "Unclassified server error: ", err.rawType
else:
  echo "Other error: ", $err.errorType
```

The mail-layer accessors (`err.notFoundBlobIds()`,
`err.invalidEmailProperties()`, `err.maxSize()`,
`err.maxRecipients()`, `err.invalidRecipientAddresses()`) are
shorthand for the same case-dispatch when the call site cares about a
single mail variant rather than a full `case` exhaust.

### 7.5. Method-level errors

Some errors for Part F methods are `MethodErrorType`, not
`SetErrorType` — they surface on the outer `MethodError` railway, not
inside `createResults` or `updateResults`:

| Method | MethodError | Core `MethodErrorType` |
|--------|-------------|------------------------|
| Email/set | `stateMismatch` | `metStateMismatch` |
| Email/set | `requestTooLarge` | `metRequestTooLarge` |
| Email/copy | `stateMismatch` | `metStateMismatch` |
| Email/copy | `fromAccountNotFound` | `metFromAccountNotFound` |
| Email/copy | `fromAccountNotSupportedByMethod` | `metFromAccountNotSupportedByMethod` |
| Email/import | `stateMismatch` | `metStateMismatch` |
| Email/import | `requestTooLarge` | `metRequestTooLarge` |

RFC 8620 §3.6.2 generic method-level errors (`serverFail`,
`accountNotFound`, `accountNotSupportedByMethod`, `accountReadOnly`,
`invalidArguments`, `invalidResultReference`, `forbidden`) apply
transitively to all three methods. All variants are present in
core's `MethodErrorType` enum; Part F adds none.

---

## 8. Test Specification

The test specification for Part F lives in its companion document
[`11-mail-F2-design.md`](./11-mail-F2-design.md). Section number `8`
is preserved there so cross-references from §1–§7 and §9 of this
document remain valid.

---

## 9. Decision Traceability Matrix

Flat numbering F1–F23. Each row records the chosen option as
implemented; the matrix is a current-state reference, not a historical
log.

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|----------|--------------------|--------|---------------------|
| F1 | Part F scope boundary | A) Email/set + Email/copy + Email/import together; B) Email/set only, defer copy+import; C) Email/set + Email/copy only | A — three methods together so the shared four-field create shape has a single source of truth | Make illegal states unrepresentable, DRY, code reads like the spec |
| F2 | `EmailCreatedItem` typed vs raw JsonNode | A) `Table[CreationId, Result[JsonNode, SetError]]`; B) Typed `EmailCreatedItem` record across all create paths; C) Raw + per-call typed accessor | B — `EmailCreatedItem` parameterises the generic `SetResponse[T]` and `CopyResponse[T]` for `Email/set` and `Email/copy` and is embedded directly in `EmailImportResponse.createResults` | Parse once at the boundary, illegal states unrepresentable, one source of truth |
| F3 | Compound-handle dispatch shape | A) Generic `CompoundHandles[A, B]` shared across all RFC 8620 §5.4 compound participants; B) Specific `EmailCopyHandles` newtype with `copy`/`destroy` fields; C) Specific always | A — generic `CompoundHandles[A, B]` (and `CompoundResults[A, B]`) live in `dispatch.nim` with `primary`/`implicit` fields; mail-specific names (`EmailCopyHandles`, `EmailCopyResults`) are aliases over the generic. Same mechanism serves Part G's `EmailSubmission` compound | DDD, return-types-as-documentation, DRY at the dispatch layer |
| F4 | PatchObject dissolution + typed update algebra scope | — | Three entities get typed algebras (Email + Mailbox + VacationResponse). Per-target patch sets (`EmailUpdateSet`, `MailboxUpdateSet`, `VacationResponseUpdateSet`) carry conflict-free invariants; whole-container algebras (`NonEmptyEmailUpdates`, `NonEmptyMailboxUpdates`) carry non-empty + unique-id invariants. `EmailUpdateSet` rejects three conflict classes via the `Conflict` ADT pipeline (`samePathConflicts` + `parentPrefixConflicts` + `toValidationError`). All accumulating constructors return `Result[T, seq[ValidationError]]` and use `validateUniqueByIt`. `EmailUpdate` lives in dedicated `email_update.nim`; `MailboxUpdate` and `VacationResponseUpdate` live inline in their home modules. `PatchObject` is not a public type | Make illegal states unrepresentable, one source of truth, parse once at the boundary, right thing easy, DDD |
| F5 | Email/set + Email/copy module home | A) Extend `mail_builders.nim`; B) New `email_write.nim`; C) New `mail_set.nim` + `mail_copy.nim` | A — mirrors CRUD-in-`mail_builders.nim` / specialty-verbs-in-`mail_methods.nim` split | DDD, precedent, right thing easy |
| F6 | Email/import module home | A) Extend `mail_methods.nim`; B) New `email_write.nim` (shared with /set, /copy); C) New `email_import.nim` | A — respects codebase's shape-based organising principle (blob-input verbs cluster in `mail_methods.nim`) | DDD, precedent |
| F7 | Shared response-type home | A) Split by layer — L1 data types in `email.nim`, L3 compound handles aliased in `mail_builders.nim`; B) Consolidate in new `mail_responses.nim`; C) Dedicated new file per response type | A — L1 types follow `ParsedEmail` precedent (`email.nim`); L3 alias for `EmailCopyHandles` colocates with `addEmailCopyAndDestroy` | DDD, strict layer discipline |
| F8 | `addEmailSet` create-map parameter type | A) `Opt[Table[CreationId, EmailBlueprint]]` (mirror `addMailboxSet`); B) Raw `JsonNode` for consistency with generic builder; C) Typed but non-Opt | A — typed creation aggregate, `Opt`-wrapped to allow update-only/destroy-only invocations | Precedent, DDD, illegal states unrepresentable |
| F9 | Update-path PatchObject: raw vs typed safe-update wrapper | — | Subsumed by F4. The typed algebras are the only public path; `PatchObject` does not exist as a public type | — |
| F10 | `EmailCopyItem` smart constructor policy | A) Total function (no Result); B) Result-returning with single-error rail; C) Result-returning with accumulating rail | A — all field types pre-validated; no cross-field invariants at this level; `mailboxIds: Opt[NonEmptyMailboxIdSet]` enforces non-emptiness on the override type | Return-types-as-documentation, constructors-that-can-fail-return-Result / can't-don't |
| F11 | Compound-method primary verb naming | A) `addEmailCopyChained` + protocol-mechanism field names; B) `addEmailCopyAndDestroy` + outcome-aligned wiring through `CompoundHandles`; C) `addEmailCopyWithImplicitDestroy` | B — outcome-oriented verb; the generic `CompoundHandles[A, B]` carries the structural pairing through `primary`/`implicit`, which the domain alias `EmailCopyHandles` inherits | One source of truth, right thing easy |
| F12 | Compound-handle semantics when implicit response is absent | A) Non-Opt both fields, short-circuit on `primary` first via `?`; B) `implicit: Opt[B]`; C) Sum type `CopySuccess`/`CopyFailed`; D) Non-short-circuit tuple | A — generic `getBoth` short-circuits on `primary`; absence surfaces only via Err rail (`MethodError{rawType: "serverFail"}`) | One source of truth, return-types-as-documentation, composability with `?` operator |
| F13 | Non-empty `emails` table enforcement for `Email/import` | A) Distinct `NonEmptyEmailImportMap` + accumulating smart ctor (empty + duplicate CreationIds); B) Plain `seq[(CreationId, EmailImportItem)]` + builder-level check; C) `seq[Id]` precedent from `/parse`; D) Result on builder | A — smart ctor on distinct Table; accumulating to carry both invariants in one pass via `validateUniqueByIt` | Parse once at the boundary, illegal states unrepresentable |
| F14 | `createResults` element type | — | Subsumed by F2 | — |
| F15 | `EmailImportItem` error accumulation style | A) Total function, typed inputs (`NonEmptyMailboxIdSet` param); B) Result-returning accumulating; C) Result-returning short-circuit; D) Builder-time accumulation | A — mirrors F10; four RFC fields with no client-enforceable cross-field invariants; all discharged by field-type smart ctors | Return-types-as-documentation, parse once at the boundary, constructors-can't-fail-don't |
| F16 | Typed `alreadyExists`/`blobNotFound` accessor helpers | — | No new code. `SetErrorType` enumerates every RFC 8621 mail variant directly, with typed payloads on case-branch fields of `SetError`; `mail/mail_errors.nim` ships five `Opt[T]` convenience accessors (`notFoundBlobIds`, `maxSize`, `maxRecipients`, `invalidRecipientAddresses`, `invalidEmailProperties`) over the case branches | DRY, precedent, parse once at the boundary |
| F17 | Test specification shape | A) Mirror Part E file-level spec (lettered-by-part + per-concept unit/serde); B) Per-method consolidation; C) Flat scenario numbering; D) Hybrid | A — lettered-by-part files + per-concept unit/serde modules per Part E precedent | Precedent, right thing easy, DRY |
| F18 | Decision Traceability Matrix location | A) Per-part only; B) Update architecture's matrix in-place; C) Both (cross-reference) | A — self-contained per-part DTM with F-prefixed numbering | Minimal surface, precedent adherence |
| F19 | PatchObject demotion strategy | A) Keep public, unused by mail; B) Demote to internal via drop-`*`-export; C) Deprecate with warning; D) Remove entirely from the public API surface | D — `PatchObject` is not a public type; the typed algebras' `toJson` are the only path to a wire patch object | One source of truth, wrong-thing-hard, right-thing-easy |
| F20 | Architecture amendment PR grouping | — | Per-part design doc is authoritative for its scope; architecture-level documents reference live state via per-part documents rather than duplicating their content | Truthfulness of references, single source of truth |
| F21 | `moveToMailbox(id)` wire semantics | A) Replace (`euSetMailboxIds`); B) Add (`euAddToMailbox`); C) Drop the convenience ctor | A — matches universal mail-UI "Move to" semantics; name ↔ variant agree; one source of truth at the value level (`moveToMailbox(id) ≡ setMailboxIds([id])`) | DDD, right thing easy, return-types-as-documentation, one source of truth |
| F22 | `initEmailUpdateSet` empty-input policy | A) Reject at ctor; B) Allow empty; C) Distinct `NonEmpty*` type at the per-target level | A — empty input returns `Err([validationError("EmailUpdateSet", "must contain at least one update", "")])`; the whole-container algebra's `Opt.none` is the single "no updates for this id" representation | One source of truth, illegal states unrepresentable, DRY, right thing easy |
| F23 | `EmailUpdateSet` conflict-class formal rules | Derivation from RFC 8620 §5.3 patch semantics | Three classes detected by the `Conflict` ADT pipeline (§3.2.4): (1) duplicate target path; (2) opposite ops on same sub-path; (3) sub-path op alongside full-replace on same parent. Smart ctor returns `Result[_, seq[ValidationError]]` with one ValidationError per detected conflict (accumulating), produced through the single `toValidationError(c: Conflict)` translation boundary | One source of truth, illegal states unrepresentable, parse once at the boundary |

---

*End of Part F1 design document.*
