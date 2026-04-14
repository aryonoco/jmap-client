# RFC 8621 JMAP Mail — Design F1: Email Write Path — Specification (set / copy / import)

Part F closes the Email aggregate's lifecycle. Parts A–E delivered the read
model, filter vocabulary, entity scaffolding, and the `EmailBlueprint`
creation aggregate. Part F wires `EmailBlueprint` into three concrete JMAP
methods — `Email/set` (§4.6), `Email/copy` (§4.7), `Email/import` (§4.8) —
sharing a common four-field successful-create shape, and introduces the
compound-handle pattern in its first single-entity form
(`addEmailCopyAndDestroy`) in preparation for Part G's cross-entity extension
to `EmailSubmission`.

Part F also carries the **typed update algebra** replacement for
`PatchObject`. `PatchObject` is an RFC 8620 §5.3 wire construct whose bare
string-keyed map form makes illegal update combinations representable — the
exact anti-pattern that Parts A–E worked to eliminate elsewhere. Part F
introduces `EmailUpdate`, `MailboxUpdate`, and `VacationResponseUpdate` case
objects with accumulating smart constructors, demotes `PatchObject` to a
serde-internal implementation detail, and migrates every existing public
mail `/set` surface onto the typed algebra.

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

| Method | RFC 8621 | Builder | Response type | Notes |
|--------|----------|---------|---------------|-------|
| `Email/set` | §4.6 | `addEmailSet` | `EmailSetResponse` | Standard `/set` shape; no method-specific extras. |
| `Email/copy` | §4.7 | `addEmailCopy` | `EmailCopyResponse` | Simple overload; `onSuccessDestroyOriginal` NOT exposed (use the compound overload instead). |
| `Email/copy` (compound) | §4.7 | `addEmailCopyAndDestroy` | `EmailCopyHandles` → `(EmailCopyResponse, EmailSetResponse)` | Destroys originals in the source account on success; returns two handles. |
| `Email/import` | §4.8 | `addEmailImport` | `EmailImportResponse` | Ingests raw `message/rfc822` blobs; takes `NonEmptyEmailImportMap`. |

### 1.2. Supporting Types Introduced

| Type | Module | Rationale |
|------|--------|-----------|
| `EmailCreatedItem` | `mail/email.nim` (extended) | Four-field typed record (`id`, `blobId`, `threadId`, `size`) shared across §§4.6/4.7/4.8 successful-create entries (F2). |
| `UpdatedEntry` | `mail/email.nim` (extended) | Two-case object encoding RFC 8620 §5.3's `Foo\|null` per-id value in the `updated` map: `uekUnchanged` (server made no changes the client doesn't already know) or `uekChanged(changedProperties: JsonNode)`. Replaces the double-`Opt` shape that admitted two encodings of the same fact (F2.1). |
| `EmailSetResponse` | `mail/email.nim` (extended) | `Email/set` response with `createResults: Table[CreationId, Result[EmailCreatedItem, SetError]]` and `updated: Opt[Table[Id, UpdatedEntry]]`. |
| `EmailCopyResponse` | `mail/email.nim` (extended) | `Email/copy` response, same `createResults` shape. |
| `EmailImportResponse` | `mail/email.nim` (extended) | `Email/import` response, same `createResults` shape. |
| `EmailCopyItem` | `mail/email.nim` (extended) | Creation-side override model for `Email/copy` (constrains to `mailboxIds`, `keywords`, `receivedAt` per RFC §4.7). |
| `EmailImportItem` | `mail/email.nim` (extended) | Creation-side model for `Email/import` (`blobId`, `mailboxIds`, `keywords`, `receivedAt` per RFC §4.8). |
| `NonEmptyEmailImportMap` | `mail/email.nim` (extended) | `distinct Table[CreationId, EmailImportItem]`; smart constructor enforces non-empty + duplicate-CreationId-free (F13). |
| `EmailUpdate` | `mail/email_update.nim` (new) | Case object; six variants matching RFC §4.6 wire patch operations (F4.2). |
| `EmailUpdateSet` | `mail/email_update.nim` (new) | `distinct seq[EmailUpdate]`; smart constructor rejects empty + three conflict classes (F22, F23). |
| `MailboxUpdate` | `mail/mailbox.nim` (extended) | Case object; variants per RFC 8621 §2 settable Mailbox properties. |
| `MailboxUpdateSet` | `mail/mailbox.nim` (extended) | `distinct seq[MailboxUpdate]`; smart constructor rejects empty + duplicate-target-property. |
| `VacationResponseUpdate` | `mail/vacation.nim` (extended) | Case object; variants per RFC 8621 §8 settable VacationResponse properties. |
| `VacationResponseUpdateSet` | `mail/vacation.nim` (extended) | Same shape as `MailboxUpdateSet`. |
| `EmailCopyHandles` | `mail/mail_builders.nim` (extended) | Two-handle record for the `addEmailCopyAndDestroy` compound overload (F3, F11). |
| `EmailCopyResults` | `mail/mail_builders.nim` (extended) | Extraction target of `getBoth(EmailCopyHandles)` (F12). |

Convenience constructors: five domain-named smart constructors on
`EmailUpdate` (`markRead`, `markUnread`, `markFlagged`, `markUnflagged`,
`moveToMailbox`) are co-located with their variant-producing counterparts in
`mail/email_update.nim` (F4.2, F21).

### 1.3. Deferred

- **Part G (EmailSubmission + cross-entity compound handles):** Part G
  extends the compound-handle pattern to `addEmailSubmissionAndEmailSet`,
  where the two handles span different entities. Part G will promote
  `EmailCopyHandles` into a new `mail/mail_convenience.nim` module once
  `EmailSubmissionHandles` arrives as the second instance — Rule of Three.
  Part F deliberately keeps `EmailCopyHandles` local to `mail_builders.nim`
  as a specific newtype (F3).
- **Generic `CompoundHandles[A, B]`:** Deferred to Part G or later. Part F
  commits to specific handle records per compound overload; a generic type
  requires at least three instances before introduction is principled
  (F3).
- **`addSet[Email]` generic overload exposure:** Not exposed. Core's
  `SetResponse[T]` is a valid internal type (Mailbox continues to use it),
  but the mail-specific `EmailSetResponse` is the only public surface for
  `Email/set`. Consumers cannot accidentally bypass `EmailCreatedItem`
  parsing via the generic path (F2).

### 1.4. Relationship to Cross-Cutting Design

This document refines `05-mail-architecture.md` §§9.3, 10.3, 11.10 and
Appendix A rows 23, 24, 31 into implementation-ready specification.
Several architectural sketches are **tightened or restructured** in this
part:

- Architecture §§9.3/10.3/11.10 currently present `update: PatchObject`
  (and `Opt[Table[Id, PatchObject]]`) as the update-path shape on public
  mail builders. Part F replaces every such surface with a per-entity typed
  update algebra (`EmailUpdateSet`, `MailboxUpdateSet`,
  `VacationResponseUpdateSet`). `PatchObject` itself is demoted to a
  serde-internal type (F19). See §1.5 for the migration scope and §3 for
  the typed replacement.
- Architecture §10.3's `EmailImportItem` uses `mailboxIds: MailboxIdSet`.
  Part F tightens this to `NonEmptyMailboxIdSet`, matching Part E's
  `EmailBlueprint` convention (F15). The "at least one mailbox" invariant
  moves from runtime rejection in the smart constructor to a signature-
  level type-level fact.
- Architecture §11.10's `EmailCopyItem.mailboxIds: Opt[MailboxIdSet]`
  tightens to `Opt[NonEmptyMailboxIdSet]`. RFC §4.1.1 requires every
  Email in the mail store to "belong to one or more Mailboxes at all
  times"; a copy override that supplies an empty `mailboxIds` map would
  produce a resulting Email that violates this invariant. The
  `NonEmptyMailboxIdSet` inner type encodes the post-override
  non-emptiness directly (F10).
- Architecture §11.10 names the compound-handle fields
  `copy`/`implicitEmailSet` and the chained overload
  `addEmailCopyChained`. Part F renames these to `copy`/`destroy` and
  `addEmailCopyAndDestroy` respectively (F11). The new names are
  outcome-register — the overload verb and the field name describe the
  same concept (the destroy outcome), keeping a single abstraction across
  both.
- Architecture §11.10's `EmailCopyResults` field names
  `copy`/`emailSet` are similarly renamed to `copy`/`destroy` for
  register consistency (F12).
- Architecture Appendix A rows 23, 24, 31 are amended retroactively in a
  separate follow-up PR (F20), landing after Part F design doc and
  implementation are merged. Between Part F landing and that follow-up
  PR's merge, architecture §§9.3/10.3/11.10 and rows 23/24/31 are
  known-stale; per-part design docs (this one) are authoritative for
  their scope during the lag.

### 1.5. PatchObject Retirement

#### 1.5.1. What changes

`PatchObject*` (defined at `src/jmap_client/framework.nim:80`) loses its
`*` export. `PatchObject` continues to exist as an internal type, but
only the serde-internal modules that translate typed update algebras onto
the wire may import it. All public mail-layer APIs that previously
accepted `PatchObject` (or `Table[Id, PatchObject]`, or
`Opt[Table[Id, PatchObject]]`) now accept the corresponding typed
update-set (`EmailUpdateSet` / `MailboxUpdateSet` /
`VacationResponseUpdateSet`, wrapped in `Table[Id, _]` and `Opt[_]` as
before).

#### 1.5.2. Migration scope

Six source files currently import or reference `PatchObject`:

- `src/jmap_client/framework.nim` — definition site; the `*` export drops.
- `src/jmap_client/serde_framework.nim` — absorbs the now-private
  `toJson`/`fromJson` helpers.
- `src/jmap_client/builder.nim` — internal use-site migrates to the
  serde-internal import path.
- `src/jmap_client/methods.nim` — `SetRequest[T].update` continues to
  carry `PatchObject` at the wire shape; the serde layer owns the
  translation, so no public-surface change here.
- `src/jmap_client/mail/mail_builders.nim` — `addMailboxSet`'s `update`
  parameter migrates from `Opt[Table[Id, PatchObject]]` to
  `Opt[Table[Id, MailboxUpdateSet]]`.
- `src/jmap_client/mail/mail_methods.nim` — `addVacationResponseSet`'s
  `update` parameter migrates from `PatchObject` to
  `VacationResponseUpdateSet`.

Approximately seventeen test files reference `PatchObject` across
`tests/compliance/`, `tests/property/`, `tests/protocol/`,
`tests/serde/`, `tests/stress/`, and `tests/unit/`. The migration
strategy is two-pronged:

1. **Tests exercising mail builder/method surfaces** rewrite their setup
   to construct typed update-sets (`EmailUpdateSet`, `MailboxUpdateSet`,
   `VacationResponseUpdateSet`) via the public smart constructors.
2. **Tests exercising core `PatchObject` serde directly**
   relocate to test the typed-algebra→wire translation (single source of
   truth — if the typed-algebra serde is tested, the underlying
   `PatchObject` serde is transitively covered), .

The migration ships in the Part F **implementation** PR alongside the new
update-algebra modules, not as a separate precursor. The blast radius is
known, the replacement types exist, and staging the change in two PRs
would leave `main` in an inconsistent state (public typed algebra
exposed, but some public surfaces still on raw `PatchObject`).

#### 1.5.3. Why demote rather than leave alone

Leaving `PatchObject` public-but-unused on the mail path would preserve
exactly the anti-pattern Part F exists to fix: two paths to the wire,
one validated (typed algebra) and one not (raw `PatchObject`). The
"wrong thing" — bypassing the typed algebra and building a raw
`PatchObject` directly — must be made harder at the API surface, not
merely discouraged. Demotion is the only option that makes the typed
algebra the **only** public path to mail `/set` update semantics.

### 1.6. General Conventions Applied

- **Pure L1/L2/L3 code** — `{.push raises: [], noSideEffect.}` at the top
  of every new or modified module in this part. Only `func` permitted.
- **Result-based error handling** — every smart constructor returns
  `Result`. No exceptions for domain-level failure.
- **Typed errors on the error rail** — every `SetError` outcome and every
  smart-constructor failure surfaces as a typed variant or validation
  reason; no stringly-typed errors cross a public boundary.
- **Accumulating constructors where multiple invariants exist** — smart
  constructors on `EmailUpdateSet` and `NonEmptyEmailImportMap` return
  `Result[T, seq[ValidationError]]`, matching Part E's `EmailBlueprint`
  idiom (F4.4, F13).
- **Total constructors where invariants are discharged at field type
  level** — `initEmailCopyItem` and `initEmailImportItem` return the
  composed type directly, not wrapped in `Result`, because all their
  fields are themselves smart-constructed and cross-field invariants do
  not exist at their level (F10, F15).
- **Postel's law, sender-side strict** — creation models (`EmailCopyItem`,
  `EmailImportItem`, `EmailUpdate`, `EmailUpdateSet`, `NonEmptyEmailImportMap`)
  are **toJson-only** (no `fromJson`). The server never sends these
  shapes back; making `fromJson` available would introduce a second
  construction path and violate "constructors are privileges, not
  rights."
- **Creation types colocated with their read-model counterparts** —
  per architecture §8.3's `ParsedEmail`-alongside-`Email` precedent (and
  Part E's `EmailBlueprint`-as-dedicated-module variant), Part F places
  the four new creation/response types (`EmailCopyItem`, `EmailImportItem`,
  `NonEmptyEmailImportMap`, `EmailCreatedItem` plus the three response
  wrappers) inline in `mail/email.nim`. `EmailUpdate` justifies a
  dedicated module (`email_update.nim`) because of its six variants, three
  conflict classes, five convenience constructors, and cross-type
  dependencies on `KeywordSet`/`NonEmptyMailboxIdSet`. `MailboxUpdate`
  and `VacationResponseUpdate` are simpler and append inline to their
  existing home modules (F4.5).

### 1.7. Module Summary

| Module | Layer | Status | Contents added |
|--------|-------|--------|----------------|
| `mail/email.nim` | L1 | extended | `EmailCreatedItem`, `UpdatedEntry`, `UpdatedEntryKind`, `EmailSetResponse`, `EmailCopyResponse`, `EmailImportResponse`, `EmailCopyItem`, `EmailImportItem`, `NonEmptyEmailImportMap`, `initEmailCopyItem`, `initEmailImportItem`, `initNonEmptyEmailImportMap` |
| `mail/email_update.nim` | L1 | **new** | `EmailUpdate`, `EmailUpdateVariantKind`, six protocol-primitive smart constructors, five convenience smart constructors, `EmailUpdateSet`, `initEmailUpdateSet` |
| `mail/serde_email.nim` | L2 | extended | `toJson`/`fromJson` for `EmailCreatedItem`, `UpdatedEntry`, `EmailSetResponse`, `EmailCopyResponse`, `EmailImportResponse`; `toJson` for `EmailCopyItem`, `EmailImportItem`, `NonEmptyEmailImportMap` |
| `mail/serde_email_update.nim` | L2 | **new** | `toJson` for `EmailUpdate`, `EmailUpdateSet` (translates to wire patch) |
| `mail/mailbox.nim` | L1 | extended | `MailboxUpdate`, `MailboxUpdateSet`, `initMailboxUpdateSet` (appended under a "Mailbox Update Algebra" section, mirroring the "Mailbox Creation Model" block at line 140) |
| `mail/serde_mailbox.nim` | L2 | extended | `toJson` for `MailboxUpdate`, `MailboxUpdateSet` |
| `mail/vacation.nim` | L1 | extended | `VacationResponseUpdate`, `VacationResponseUpdateSet`, `initVacationResponseUpdateSet` |
| `mail/serde_vacation.nim` | L2 | extended | `toJson` for `VacationResponseUpdate`, `VacationResponseUpdateSet` |
| `mail/mail_builders.nim` | L3 | extended | `addEmailSet`, `addEmailCopy`, `addEmailCopyAndDestroy`, `EmailCopyHandles`, `EmailCopyResults`, `getBoth(EmailCopyHandles)`; `addMailboxSet`'s `update` parameter migrated to `Opt[Table[Id, MailboxUpdateSet]]` |
| `mail/mail_methods.nim` | L3 | extended | `addEmailImport` + `EmailImportResponse.fromJson`; `addVacationResponseSet`'s `update` parameter migrated to `VacationResponseUpdateSet` |
| `methods_enum.nim` | L1 | extended | `mnEmailImport` enum variant |
| `mail/mail_entities.nim` | L1 | extended | `importMethodName` constant on `Email` |
| `framework.nim` | L1 | modified | `PatchObject*` loses `*` export (F19) |
| `serde_framework.nim` | L2 | modified | Absorbs private `PatchObject` serde helpers |
| `builder.nim`, `methods.nim` | L1/L3 | modified | Internal `PatchObject` use-sites migrate to the now-private import path |
| `types.nim` | — | extended | Re-exports the new public types |

---

## 2. Shared Response Surface

### 2.1. EmailCreatedItem

RFC 8621 §§4.6, 4.7, 4.8 each specify verbatim that a successful create
entry contains exactly four properties: `id`, `blobId`, `threadId`, and
`size`. RFC §4.6 (Email/set) states:

> For successfully created Email objects, the "created" response contains
> the "id", "blobId", "threadId", and "size" properties of the object.

RFC §4.7 (Email/copy) states the same four-field requirement. RFC §4.8
(Email/import) states:

> A map of the creation id to an object containing the "id", "blobId",
> "threadId", and "size" properties for each successfully imported Email,
> or null if none.

Three methods, identical successful-create shape. Part F captures this as
a single typed record consumed by all three response types:

```nim
type EmailCreatedItem* = object
  ## Successful-create entry for Email/set, Email/copy, and Email/import.
  ## Exactly the four fields RFC 8621 §§4.6/4.7/4.8 mandate — no more.
  id*: Id
  blobId*: Id
  threadId*: Id
  size*: UnsignedInt
```

All four fields are required and carry no `Opt`. A server that returns a
`created` entry missing any of the four fields has emitted a malformed
response; `fromJson` fails the containing `Result` with a
`ValidationError` rather than constructing a partial value.

### 2.2. Response Types

Each of the three methods carries its own response type. All three share
the `createResults: Table[CreationId, Result[EmailCreatedItem, SetError]]`
merge pattern established by core `SetResponse[T]` and `CopyResponse[T]`
and validated across Parts A–D. The error rail is the core
`errors.SetError` case object; mail-specific error payloads (such as
`blobNotFound`, `tooManyKeywords`) surface via the `rawType` +
`MailSetErrorType` decoding scheme established by Part A (§7).

RFC 8620 §5.3 types the per-id value in the `updated` response map as
`Foo|null` — `null` signalling "server made no further changes the
client doesn't already know" and a non-null object carrying the server-
altered properties. A single `Opt[JsonNode]` field would admit two
encodings of the "null" case (`Opt.none` vs `Opt.some(JNull)`),
violating one-source-of-truth. The dedicated two-case object makes the
state split a type-level fact:

```nim
type
  UpdatedEntryKind* = enum
    uekUnchanged
      ## Server made no changes the client doesn't already know.
    uekChanged
      ## Server altered properties; payload is the changed property map.
  UpdatedEntry* = object
    case kind*: UpdatedEntryKind
    of uekUnchanged:
      discard
    of uekChanged:
      changedProperties*: JsonNode
        ## Kept as raw JSON because the set of properties the server
        ## may alter is open-ended.

type EmailSetResponse* = object
  ## Email/set response (RFC 8621 §4.6; response envelope shape per
  ## RFC 8620 §5.3).
  accountId*: AccountId
  oldState*: Opt[JmapState]
  newState*: JmapState
  createResults*: Table[CreationId, Result[EmailCreatedItem, SetError]]
  updated*: Opt[Table[Id, UpdatedEntry]]
    ## RFC 8620 §5.3 `Id[Foo|null]|null`: outer Opt = map absent/null;
    ## per-entry `UpdatedEntry` encodes the `Foo|null` split.
  destroyed*: Opt[seq[Id]]
  notUpdated*: Opt[Table[Id, SetError]]
  notDestroyed*: Opt[Table[Id, SetError]]

type EmailCopyResponse* = object
  ## Email/copy response (RFC 8621 §4.7). Shares the four-field
  ## successful-create shape but omits /set-specific fields that /copy
  ## never populates (updated, destroyed, notUpdated, notDestroyed).
  fromAccountId*: AccountId
  accountId*: AccountId
  oldState*: Opt[JmapState]
  newState*: JmapState
  createResults*: Table[CreationId, Result[EmailCreatedItem, SetError]]

type EmailImportResponse* = object
  ## Email/import response (RFC 8621 §4.8).
  accountId*: AccountId
  oldState*: Opt[JmapState]
  newState*: JmapState
  createResults*: Table[CreationId, Result[EmailCreatedItem, SetError]]
```

### 2.3. Serde

`fromJson` for all three response types merges the wire-level
`created`/`notCreated` parallel maps (and, for `EmailSetResponse`, the
parallel `updated`/`notUpdated` and `destroyed`/`notDestroyed` maps) into
the `Result`-valued `createResults` shape. The merge pattern is
established by core's `SetResponse[T].fromJson` and reused without
re-implementation — mail serde calls into the core helper and then casts
each successful entry's `JsonNode` payload through
`EmailCreatedItem.fromJson`.

`EmailCreatedItem.fromJson` enforces all four fields present and
well-typed. A server response with a missing `size` field surfaces as an
`Err(SetError(...))` entry in the parent `createResults` table (not as a
silent default-zero), because the merge layer catches the parse failure
and demotes it to a synthetic `SetError` with `errorType: setUnknown` and
a descriptive `rawType`. This keeps the Result rail total without
introducing default values.

`UpdatedEntry.fromJson` maps the RFC 8620 §5.3 `Foo|null` inner value:
a JSON `null` becomes `UpdatedEntry(kind: uekUnchanged)`; a JSON
object becomes `UpdatedEntry(kind: uekChanged, changedProperties: …)`.
Any other JSON kind (string, number, array, boolean) surfaces as
`Err` on the containing `Result` rail — the spec admits only object
or null at this position. Because the `uekUnchanged` variant holds no
payload, a server that sends `null` and a server that sends `{}` for
the same semantic intent ("no further changes") still parse into
distinct values (`uekUnchanged` vs `uekChanged(JObject{})`), and the
library does **not** collapse them: `{}` represents the server
explicitly asserting an empty property delta, which is a different
wire claim than `null` even if the client-visible behaviour is the
same. Keeping the two apart preserves the server's intent on the
error-inspection rail and matches the `Foo|null` wire shape exactly.

### 2.4. Rationale

**B+ refinement of architecture §10.3's suggestion.** Architecture §10.3
suggested `EmailCreatedItem` "may be defined in a per-entity companion
document" while keeping `createResults: Table[CreationId, Result[JsonNode, SetError]]`
as the response shape. Part F commits to the typed record and threads it
through all three response types' `createResults`. Three principles drive
the tightening:

- **Parse once at the boundary.** The four-field shape is fully specified
  by the RFC. There is no ambiguity a consumer could resolve that the
  serde layer cannot resolve identically. Keeping `JsonNode` at the
  boundary would duplicate the parse across every consumer and open a
  surface for "I forgot to read `threadId`" bugs.
- **Make illegal states unrepresentable.** A response lacking any of the
  four RFC-mandated fields is malformed; `EmailCreatedItem` refuses to
  construct from such JSON. Consumers never see a half-populated
  successful-create entry.
- **One source of truth.** Three methods, one shape. Defining
  `EmailCreatedItem` once and threading it through three response types is
  simpler than three parallel ad-hoc shapes and cannot drift.

The generic core `SetResponse[T]` and `CopyResponse[T]` remain unchanged
and continue to serve `Mailbox` (`addMailboxSet` returns
`ResponseHandle[SetResponse[Mailbox]]`) and `Identity`. Part F does not
introduce an `addSet[Email]` generic overload. The three mail-specific
response types are the **only** public surface for Email write responses.
This closes a second path that would otherwise undermine
`EmailCreatedItem`'s one-source-of-truth guarantee.

---

## 3. Typed Update Algebras

### 3.1. Why replace PatchObject

RFC 8620 §5.3 specifies the `PatchObject` wire shape: a JSON object whose
string keys are JSON Pointer paths into the updated entity, and whose
values are the replacement values (or `null` for removal from a sub-path).
Example:

```json
{
  "keywords/$seen": true,
  "mailboxIds/abc": null,
  "mailboxIds/def": true
}
```

At the wire level, this shape is irreducible — every JMAP client must
eventually emit JSON of this form. The library's question is where the
boundary sits: **which types may construct a `PatchObject` directly**?

Before Part F, the library's public mail `/set` surfaces accepted
`PatchObject` directly. Callers were expected to construct the update
table by reaching for raw `PatchObject` smart constructors (or — more
realistically — by building a `JsonNode` manually, bypassing even
`PatchObject`'s own checks). This fails the library's core principles
repeatedly:

- **Make illegal states unrepresentable.** `PatchObject` is
  `distinct Table[string, JsonNode]`. Any string is a valid key at the
  type level. Invalid JSON Pointer paths, conflicting operations on the
  same sub-path, and nonsense values (`"keywords/$seen": "hello"` where
  RFC requires `true`/`null`) all construct without complaint.
- **Parse once at the boundary.** `PatchObject`'s boundary is the
  wire, not the caller. A client building a patch Table programmatically
  has no type-level guarantee that what they built is acceptable to the
  server; the RFC rules live in prose, not code.
- **One source of truth.** The rules that govern a valid update — "you
  may add a keyword", "you may replace the full keyword set", "you may
  not do both in the same patch" — live in the caller's mental model. The
  type system holds none of it.
- **Right thing easy.** `PatchObject` offers zero affordance toward
  domain verbs. A caller who wants to "mark this email as read" has to
  know that the wire key is `keywords/$seen` (with the dollar sign, lower
  case, RFC 5788 IANA registration), that the value must be boolean
  `true` not string `"true"`, and that this cannot be combined with
  `keywords: { ... }` full-replace in the same patch.

The typed update algebra moves all of this knowledge into the type
system. The caller expresses their intent in domain verbs
(`markRead()`, `addToMailbox(id)`, `setKeywords(ks)`); the library
converts to the wire patch at the serde layer; the caller cannot
construct a conflicting combination because the smart constructor
rejects it.

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

type EmailUpdate* = object
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
| `euSetMailboxIds(ids)` | `mailboxIds` | object | Replace the full mailbox membership set. |

Placeholder convention: `{keyword}` denotes the keyword value (which
for IANA-registered keywords begins with a literal `$`, e.g., `$seen`);
`{id}` denotes a bare `Id` value (no prefix). The keyword token is
RFC 6901 escaped before emission (see §3.2.5); the id token requires
no escaping because the `Id` charset (RFC 8620 §1.2) excludes `/` and
`~`.

Six variants precisely cover the RFC §4.6 update surface. The library
intentionally does not expose update paths for other Email properties
(`receivedAt`, `subject`, body fields): those are set-at-creation-only
per RFC §4.6 and changing them after creation is either forbidden or
meaningless.

#### 3.2.2. Protocol-primitive smart constructors

Six constructors, one per variant. Each is total (returns `EmailUpdate`
directly, no `Result`) because all cross-field invariants are discharged
by the field-level smart constructors (`Keyword`, `KeywordSet`, `Id`,
`NonEmptyMailboxIdSet` — all already validated at their own construction
boundary per Parts A–E):

```nim
func addKeyword*(k: Keyword): EmailUpdate =
  ## Add `k` to the target email's keyword set.
  EmailUpdate(kind: euAddKeyword, keyword: k)

func removeKeyword*(k: Keyword): EmailUpdate =
  ## Remove `k` from the target email's keyword set.
  EmailUpdate(kind: euRemoveKeyword, keyword: k)

func setKeywords*(ks: KeywordSet): EmailUpdate =
  ## Replace the target email's keyword set with `ks`.
  EmailUpdate(kind: euSetKeywords, keywords: ks)

func addToMailbox*(id: Id): EmailUpdate =
  ## Add the target email to mailbox `id` (additive; other memberships
  ## preserved).
  EmailUpdate(kind: euAddToMailbox, mailboxId: id)

func removeFromMailbox*(id: Id): EmailUpdate =
  ## Remove the target email from mailbox `id` (other memberships
  ## preserved).
  EmailUpdate(kind: euRemoveFromMailbox, mailboxId: id)

func setMailboxIds*(ids: NonEmptyMailboxIdSet): EmailUpdate =
  ## Replace the target email's full mailbox membership set with `ids`.
  EmailUpdate(kind: euSetMailboxIds, mailboxes: ids)
```

#### 3.2.3. Domain-named convenience constructors

Five domain-named constructors. Each is a thin, zero-arg or one-arg
alias producing a value structurally identical to one of the protocol-
primitive variants:

```nim
func markRead*(): EmailUpdate =
  ## Mark the target email as read. Equivalent to
  ## ``addKeyword(kwSeen)``.
  addKeyword(kwSeen)

func markUnread*(): EmailUpdate =
  ## Mark the target email as unread. Equivalent to
  ## ``removeKeyword(kwSeen)``.
  removeKeyword(kwSeen)

func markFlagged*(): EmailUpdate =
  ## Mark the target email as flagged. Equivalent to
  ## ``addKeyword(kwFlagged)``.
  addKeyword(kwFlagged)

func markUnflagged*(): EmailUpdate =
  ## Mark the target email as unflagged. Equivalent to
  ## ``removeKeyword(kwFlagged)``.
  removeKeyword(kwFlagged)

func moveToMailbox*(id: Id): EmailUpdate =
  ## Move the target email to mailbox `id`, replacing its full mailbox
  ## membership. Equivalent to
  ## ``setMailboxIds(parseNonEmptyMailboxIdSet(@[id]).get())``.
  ## Matches universal mail-UI "Move to" semantics: the email ends up
  ## in exactly one mailbox (the target), regardless of prior memberships.
  ## See §3.2.3.1 for the replace-vs-add decision rationale.
  EmailUpdate(
    kind: euSetMailboxIds,
    mailboxes: parseNonEmptyMailboxIdSet(@[id]).get(),
  )
```

The library uses `kwSeen` and `kwFlagged` from `mail/keyword.nim`
(IANA-registered constants `$seen` and `$flagged`). Convenience
constructors do not introduce any new `Keyword` values.

##### 3.2.3.1. Why `moveToMailbox` emits `euSetMailboxIds` (not `euAddToMailbox`)

The name "move" is domain-loaded. Universal mail UI conventions — Gmail's
"Archive" (which removes all labels except Archive), Apple Mail's "Move"
(which replaces the folder), every desktop IMAP client's "Move" (replace
target folder) — treat "move X to Y" as **replace** semantics, not
**add** semantics. The protocol-primitive `addToMailbox(id)` is
available for callers who genuinely want additive membership; the domain
verb `moveToMailbox` aligns with how mail users understand the word.

Choosing `euAddToMailbox` would introduce a name/semantics mismatch
(caller reads "move", wire does "add", email ends up in an unexpected
second mailbox) — exactly the anti-pattern the typed algebra exists to
prevent.

#### 3.2.4. EmailUpdateSet + conflict algebra

```nim
type EmailUpdateSet* = distinct seq[EmailUpdate]
```

`EmailUpdateSet` is a `distinct seq[EmailUpdate]` — a newtype conveying
"this sequence has been validated and accumulates one consumer's
update intent for a single email, with no internal conflicts." It never
appears on the wire in this form; serde flattens it to a `PatchObject`
(`Table[string, JsonNode]`) at serialisation time.

The smart constructor returns an accumulating `Result`, mirroring Part
E's `EmailBlueprint` idiom:

```nim
func initEmailUpdateSet*(
    updates: openArray[EmailUpdate]
): Result[EmailUpdateSet, seq[ValidationError]]
```

Three conflict classes cause rejection. Each class is derivable
mechanically from RFC 8620 §5.3's patch semantics and the requirement
that every `EmailUpdateSet` serialise to a `PatchObject` with
unambiguous, last-write-wins-free semantics.

For each variant, a **target path**:

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
JSON object; one of the values would silently shadow the other, hiding
the caller's intent. The failure mode ("which value wins?") has no
defensible answer.

**Class 2 — Opposite operations on the same sub-path.** Examples:
- `euAddKeyword(kwSeen)` + `euRemoveKeyword(kwSeen)` (both target
  `keywords/$seen` with opposite values)
- `euAddToMailbox(id1)` + `euRemoveFromMailbox(id1)` (both target
  `mailboxIds/id1` with opposite values)

Rejected because the wire shape would carry a single key with the
last-write-wins value; one of the two operations is a no-op. If the
caller wants a no-op, they should omit it; if the caller wants both, one
is wrong. Either interpretation violates one-source-of-truth (the pair
is expressing redundant intent).

**Class 3 — Sub-path operation alongside full-replace on same parent.**
Examples:
- `euAddKeyword(kwSeen)` + `euSetKeywords(ks)` (both operate on
  `keywords`)
- `euAddToMailbox(id1)` + `euSetMailboxIds(ids)` (both operate on
  `mailboxIds`)

Rejected categorically by RFC 8620 §5.3 (lines 1918–1920): "There MUST
NOT be two patches in the PatchObject where the pointer of one is the
prefix of the pointer of the other." A server that receives such a
combination MUST reject the update with an `invalidPatch` SetError.
Emitting this shape is a wire-level protocol violation, not merely
ambiguity the server might resolve inconsistently — the typed algebra
must therefore refuse to construct the offending value at the client
boundary.

**Independent cases (NOT conflicts):**
- `euSetKeywords(ks)` + `euSetMailboxIds(ids)` — different parent paths
  (`keywords` vs `mailboxIds`), both full-replace on independent fields.
  Accepted.
- `euAddKeyword(kwSeen)` + `euAddKeyword(kwFlagged)` — different
  sub-paths (`keywords/$seen` vs `keywords/$flagged`). Accepted.
- `euAddKeyword(kwSeen)` + `euAddToMailbox(id1)` — different parent
  paths entirely. Accepted.

**Empty input also rejected** (F22): `initEmailUpdateSet(@[])` returns
`Err(@[validationError("EmailUpdateSet", "must contain at least one update", "")])`.
An empty update set has exactly one sensible representation in the
builder's `update: Opt[Table[Id, EmailUpdateSet]]` parameter — omit the
entry from the table entirely. Permitting an empty `EmailUpdateSet`
value would introduce a parallel "no updates for this id" encoding,
violating one-source-of-truth and producing a wasteful empty
`{}`-shaped wire patch.

**Why not `NonEmptyEmailUpdateSet`?** RFC 8620 §5.3 defines
`PatchObject` as `String[*]` — an unordered set of patches — and the
`A[B]` notation (RFC 8620 §1.1) imposes no lower bound on cardinality,
so an empty patch object is not syntactically forbidden. The RFC is
silent on whether servers must accept an empty `PatchObject`; a
conformant server may return `invalidPatch`. The non-emptiness in
`EmailUpdateSet` is therefore a **client-imposed** invariant, not a
protocol-level one; naming the type `NonEmpty...` would falsely suggest
the spec cares about the emptiness distinction. Contrast
`NonEmptyMailboxIdSet`, where the spec-level "MUST belong to one or
more Mailboxes" invariant in RFC §4.1.1 makes the type name document a
genuine spec-level commitment.

**Accumulation semantics.** The smart constructor performs all three
conflict checks plus the empty-input check in a single pass. If any
combination of checks fails, the `Err` branch carries one
`ValidationError` per detected conflict plus one for the empty-input
case (if applicable). The caller sees every issue at once, not just the
first one.

#### 3.2.5. Serde

`PatchObject` keys are JSON Pointers per RFC 8620 §5.3. RFC 6901 §3
requires two characters to be escaped within a reference token: `~`
becomes `~0` and `/` becomes `~1`. RFC 8621 §4.1.1 (line 1383) lists
the keyword charset as ASCII `%x21-%x7e` minus `( ) { ] % * " \` — the
set explicitly **does not** exclude `/` or `~`, so a spec-faithful
`Keyword` smart constructor must accept keywords containing them
(Postel: accept the most general type). Escaping therefore belongs at
the serialisation boundary, not on the type. `Id` values (RFC 8620
§1.2) are restricted to `[A-Za-z0-9_-]` and need no escaping.

```nim
func jsonPointerEscape(s: string): string {.noSideEffect.} =
  ## RFC 6901 §3 reference-token escaping: `~` → `~0`, `/` → `~1`.
  ## Order matters: escape `~` first, otherwise the `~1` produced for
  ## `/` would be re-escaped into `~01`.
  result = s.replace("~", "~0").replace("/", "~1")

func toJson*(u: EmailUpdate): (string, JsonNode) {.noSideEffect.} =
  ## Emits the ``(wire-key, wire-value)`` pair for a single update.
  case u.kind
  of euAddKeyword:
    ("keywords/" & jsonPointerEscape($u.keyword), %true)
  of euRemoveKeyword:
    ("keywords/" & jsonPointerEscape($u.keyword), newJNull())
  of euSetKeywords:
    ("keywords", u.keywords.toJson())
  of euAddToMailbox:
    ("mailboxIds/" & $u.mailboxId, %true)
  of euRemoveFromMailbox:
    ("mailboxIds/" & $u.mailboxId, newJNull())
  of euSetMailboxIds:
    ("mailboxIds", u.mailboxes.toJson())

func toJson*(us: EmailUpdateSet): JsonNode {.noSideEffect.} =
  ## Flatten the validated update-set to an RFC 8620 §5.3 wire patch.
  ## Post-condition: every key is distinct (guaranteed by the smart
  ## constructor's Class 1 rejection); values are valid per RFC §4.6;
  ## all reference tokens are RFC 6901-escaped.
  result = newJObject()
  for u in seq[EmailUpdate](us):
    let (k, v) = u.toJson()
    result[k] = v
```

The serde layer is intentionally mechanical — all the interesting work
has already been done by the smart constructor. `toJson(EmailUpdateSet)`
cannot produce a conflicting `PatchObject` because the input is already
conflict-free, and cannot produce a malformed JSON Pointer because
every keyword reference token is escaped before concatenation.

### 3.3. MailboxUpdate

RFC 8621 §2 lists the settable Mailbox properties (§2.5 only adds the
`onDestroyRemoveEmails` argument and two SetError types). Unlike
`EmailUpdate`, none of these have a sub-path/full-replace tension —
every settable Mailbox property is a whole-value replace. The update
algebra is correspondingly simpler:

```nim
type MailboxUpdateVariantKind* = enum
  muSetName
  muSetParentId
  muSetRole
  muSetSortOrder
  muSetIsSubscribed

type MailboxUpdate* = object
  case kind*: MailboxUpdateVariantKind
  of muSetName:
    name*: string
  of muSetParentId:
    parentId*: Opt[Id]    # RFC permits null (reparent to top level)
  of muSetRole:
    role*: Opt[MailboxRole]   # RFC permits null (clear role)
  of muSetSortOrder:
    sortOrder*: UnsignedInt
  of muSetIsSubscribed:
    isSubscribed*: bool
```

Five smart constructors — one per variant, all total:

```nim
func setName*(name: string): MailboxUpdate = ...
func setParentId*(parentId: Opt[Id]): MailboxUpdate = ...
func setRole*(role: Opt[MailboxRole]): MailboxUpdate = ...
func setSortOrder*(sortOrder: UnsignedInt): MailboxUpdate = ...
func setIsSubscribed*(isSubscribed: bool): MailboxUpdate = ...
```

No domain-named convenience wrappers at this layer — `Mailbox`
mutations are rare in typical client flows, and the set is small enough
that aliases would dilute rather than clarify.

**MailboxUpdateSet** uses one conflict class only:

```nim
type MailboxUpdateSet* = distinct seq[MailboxUpdate]

func initMailboxUpdateSet*(
    updates: openArray[MailboxUpdate]
): Result[MailboxUpdateSet, seq[ValidationError]]
```

The smart constructor rejects:
- **Empty input** (same rationale as F22 for `EmailUpdateSet`).
- **Duplicate target property** (e.g., two `muSetName` updates) — Class 1
  only. No Class 2 or Class 3 applies because whole-value replace leaves
  no sub-path to conflict with.

Serde is even simpler than `EmailUpdate` — each variant emits exactly
one top-level key; no sub-path flattening is needed.

### 3.4. VacationResponseUpdate

RFC 8621 §8 specifies the VacationResponse singleton's settable
properties (§8.1 is the `/get` shape; §8.2 is `/set`). Structurally
identical to `MailboxUpdate`:

```nim
type VacationResponseUpdateVariantKind* = enum
  vruSetIsEnabled
  vruSetFromDate
  vruSetToDate
  vruSetSubject
  vruSetTextBody
  vruSetHtmlBody

type VacationResponseUpdate* = object
  case kind*: VacationResponseUpdateVariantKind
  of vruSetIsEnabled:
    isEnabled*: bool
  of vruSetFromDate:
    fromDate*: Opt[UTCDate]
  of vruSetToDate:
    toDate*: Opt[UTCDate]
  of vruSetSubject:
    subject*: Opt[string]
  of vruSetTextBody:
    textBody*: Opt[string]
  of vruSetHtmlBody:
    htmlBody*: Opt[string]

type VacationResponseUpdateSet* = distinct seq[VacationResponseUpdate]

func initVacationResponseUpdateSet*(
    updates: openArray[VacationResponseUpdate]
): Result[VacationResponseUpdateSet, seq[ValidationError]]
```

Smart constructor rejects empty input and duplicate target property.

`addVacationResponseSet` (in `mail/mail_methods.nim:53`) continues to
omit a `Table` wrapper around the update — the RFC forbids any id other
than `"singleton"`, and core's `VacationResponseSingletonId` is hardcoded
internally. The `update` parameter simply becomes
`VacationResponseUpdateSet` (replacing `PatchObject`).

### 3.5. Module home rationale

`EmailUpdate` + `EmailUpdateSet` warrant a new file `mail/email_update.nim`
(parallel to `mail/email_blueprint.nim`) because the type cluster is
complex:

- six variants with four distinct payload shapes,
- eleven public constructors (six primitive + five convenience),
- three conflict classes with non-trivial serde boundary,
- dependencies on `Keyword`, `KeywordSet`, `Id`, `NonEmptyMailboxIdSet`.

`MailboxUpdate` + `MailboxUpdateSet` append inline to existing
`mail/mailbox.nim` under a new "Mailbox Update Algebra" section,
mirroring the "Mailbox Creation Model" block at line 140.
`mail/mailbox.nim` is currently around 180 lines; the inline addition is
absorbed cleanly.

`VacationResponseUpdate` + `VacationResponseUpdateSet` append inline to
existing `mail/vacation.nim`, which is currently 25 lines. The addition
takes the file to roughly 80 lines — still well below any split
threshold. No new file.

This **mixed organisation** is principled: each entity's full modelling
lives in its home file (one source of truth per entity), except where
the complexity of one concrete type cluster (`EmailUpdate`) warrants a
dedicated module. Forcing all three update algebras into a generic
`mail_updates.nim` would be appearance-based coupling — the three share
no implementation scaffolding, and shared syntax would misrepresent the
actual relationships.

---

## 4. Email/set

RFC 8621 §4.6 specifies `Email/set` as a standard RFC 8620 §5.3 `/set`
method with no additional request arguments. The builder signature
mirrors `addMailboxSet` (`mail/mail_builders.nim:196`) mechanically,
substituting the Email creation/update/response types.

### 4.1. Builder Signature

```nim
func addEmailSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, EmailBlueprint]] =
      Opt.none(Table[CreationId, EmailBlueprint]),
    update: Opt[Table[Id, EmailUpdateSet]] =
      Opt.none(Table[Id, EmailUpdateSet]),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): (RequestBuilder, ResponseHandle[EmailSetResponse])
```

Key choices:

- **`create` is typed `EmailBlueprint`** (Part E's creation aggregate),
  not raw `JsonNode`. The builder's internal conversion follows
  `addMailboxSet` (lines 210–218): convert
  `Opt[Table[CreationId, EmailBlueprint]]` →
  `Opt[Table[CreationId, JsonNode]]` via per-entry `toJson`, then
  construct the core `SetRequest[Email]`.
- **`update` is typed `EmailUpdateSet`** (per F19 + F4.1), not
  `PatchObject`. The entire public surface routes through the typed
  algebra; raw `PatchObject` construction is no longer possible outside
  the serde layer.
- **No `create.keyword-on-sort`-like extra parameter.** RFC §4.6 defines
  no method-specific extras (contrast Mailbox's
  `onDestroyRemoveEmails`), so the builder exposes none.
- **`destroy` uses `Referencable[seq[Id]]`** — the standard JMAP
  back-reference mechanism from core. A caller may pass literal ids or
  a result-reference into a previous invocation's output.
- **Empty create/update/destroy permitted.** RFC 8620 §5.3 places no
  lower bound on the `create`, `update`, or `destroy` arguments; a
  bare `Email/set { accountId: "..." }` invocation is wire-legal and
  has well-defined semantics (return the current state, make no
  changes). The builder signature supports this via `Opt.none`
  defaults.

### 4.2. Response Handling

`ResponseHandle[EmailSetResponse]` is the typed phantom handle pattern
established by core's builder infrastructure. On `Request.execute`,
the dispatch layer (`dispatch.nim`) surfaces either
`Ok(EmailSetResponse)` or a typed `MethodError` on the outer railway.
Successful-create entries in `createResults` carry `EmailCreatedItem`;
failed-create entries carry `SetError` with `rawType` preserved for mail-
specific error decoding (see §7).

### 4.3. Rationale

Mechanical mirror of `addMailboxSet`. The only deviations from the
Mailbox builder are structurally necessary:

- `create` takes `EmailBlueprint` not `MailboxCreate`.
- `update` takes `EmailUpdateSet` not `MailboxUpdateSet` — but note:
  `addMailboxSet` itself migrates to `MailboxUpdateSet` in the same PR.
  Post-migration both builders have the same shape (different type
  parameters).
- `EmailSetResponse` replaces `SetResponse[Mailbox]` at the return site
  per F2.
- No `onDestroyRemoveEmails`-like extra — `Email/set` has none.

---

## 5. Email/copy

### 5.1. EmailCopyItem

RFC 8621 §4.7 specifies:

> This is a standard "/copy" method as described in [RFC 8620], Section 5.4,
> except only the "mailboxIds", "keywords", and "receivedAt" properties
> may be set during the copy.

`EmailCopyItem` constrains the creation entry to exactly those three
override properties plus the source-email `id`:

```nim
type EmailCopyItem* = object
  ## Source email + optional destination-account overrides for
  ## Email/copy (RFC 8621 §4.7). Unset `Opt.none` overrides preserve the
  ## source value; `Opt.some` overrides replace it in the destination.
  id*: Id
    ## Source email id in the from-account.
  mailboxIds*: Opt[NonEmptyMailboxIdSet]
  keywords*: Opt[KeywordSet]
  receivedAt*: Opt[UTCDate]

func initEmailCopyItem*(
    id: Id,
    mailboxIds: Opt[NonEmptyMailboxIdSet] = Opt.none(NonEmptyMailboxIdSet),
    keywords: Opt[KeywordSet] = Opt.none(KeywordSet),
    receivedAt: Opt[UTCDate] = Opt.none(UTCDate),
): EmailCopyItem =
  ## Total constructor. All field types are themselves smart-constructed
  ## (parseId, parseNonEmptyMailboxIdSet, initKeywordSet, parseUTCDate);
  ## there are no cross-field invariants for this type to enforce.
  EmailCopyItem(
    id: id,
    mailboxIds: mailboxIds,
    keywords: keywords,
    receivedAt: receivedAt,
  )
```

**`mailboxIds` tightened to `Opt[NonEmptyMailboxIdSet]`** (not
`Opt[MailboxIdSet]` as in architecture §11.10). RFC §4.7 lists
`mailboxIds`, `keywords`, and `receivedAt` as the only properties that
may be overridden during copy but is silent on cardinality itself; the
non-emptiness requirement derives from RFC §4.1.1's "An Email in the
mail store MUST belong to one or more Mailboxes at all times" applied
to the resulting Email after the copy override is merged. If the
override is supplied, it replaces the source's mailbox membership
wholesale, so the override itself must be non-empty — otherwise the
resulting Email would have zero mailboxes and violate the §4.1.1
invariant. `NonEmptyMailboxIdSet` encodes this on the override type
directly. This is the same tightening applied to
`EmailBlueprint.mailboxIds` in Part E (F14 → `NonEmptyMailboxIdSet`).

**Total constructor (no `Result`).** Mirrors Part E's `initKeywordSet`,
`initMailboxIdSet`, and `parseNonEmptyMailboxIdSet` precedents. The
field-level smart constructors discharge all invariants; the composition
itself has no cross-field rules that could fail.

### 5.2. Simple overload — `addEmailCopy`

```nim
func addEmailCopy*(
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, EmailCopyItem],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[EmailCopyResponse])
```

**`onSuccessDestroyOriginal` is NOT exposed on this overload.** A caller
who wants the post-copy destroy uses `addEmailCopyAndDestroy` instead
(§5.3). Binding the boolean to a distinct verb eliminates the Boolean
code smell and couples the implicit-destroy behaviour to the return
shape: if you get `EmailCopyHandles`, you get the destroy; if you get
`ResponseHandle[EmailCopyResponse]`, you don't.

**`create` is non-Opt `Table[CreationId, EmailCopyItem]`.** Unlike
`Email/set`'s `create: Opt[Table[...]]`, `/copy` without a `create` map
is meaningless (nothing to copy). The RFC does not forbid an empty
`create`, but forbids a missing one; the signature requires the
parameter. Empty map is accepted and produces an empty
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

This overload always emits `"onSuccessDestroyOriginal": true` on the wire.
On successful copy, the server implicitly appends an `Email/set` destroy
invocation to the response with the same method-call-id as the copy.
The return shape tells the caller there are **two** responses to handle —
the copy itself and the implicit destroy.

**Verb choice rationale.** The overload is named
`addEmailCopyAndDestroy`, not `addEmailCopyChained` (the architecture
§11.10 name). "Chained" describes a protocol mechanism
(back-reference threading); "and destroy" describes the domain outcome
(original is gone after this succeeds). The outcome framing matches
the field names in the returned `EmailCopyHandles` (`copy`, `destroy`) —
one abstraction (the outcome), one register, used consistently across
overload name and record fields.

**`destroyFromIfInState`** controls the optimistic-concurrency assertion
for the source account's destroy. The parameter exists only on the
compound overload because the simple overload emits no destroy.

### 5.4. EmailCopyHandles / EmailCopyResults / getBoth

```nim
type EmailCopyHandles* = object
  ## Two typed response handles from a successful addEmailCopyAndDestroy:
  ## the copy response itself and the implicit Email/set destroy response
  ## that the server appends when all copies succeed.
  copy*: ResponseHandle[EmailCopyResponse]
  destroy*: ResponseHandle[EmailSetResponse]

type EmailCopyResults* = object
  ## Both results extracted from a Response on success. If the caller
  ## got here via getBoth's Ok rail, both fields are populated.
  copy*: EmailCopyResponse
  destroy*: EmailSetResponse

func getBoth*(
    resp: Response,
    handles: EmailCopyHandles,
): Result[EmailCopyResults, MethodError]
```

**Why two non-`Opt` fields, not `destroy: Opt[EmailSetResponse]`?** The
server appends the implicit destroy response if — and only if — the
copy itself succeeded at the method level. If the copy method-errored
(say, `fromAccountNotFound`), no destroy is appended. In that case
`getBoth`'s `?`-short-circuit on `copy` surfaces the copy's
`MethodError` on the `Err` rail **before** even looking at the destroy
handle; the caller never observes the destroy's absence through
`Opt.none`. If `getBoth` instead carried `destroy: Opt[EmailSetResponse]`,
the `none` case would be structurally unreachable on the Ok rail — the
type would lie about what states are representable.

**Implementation pattern** (mirrors `convenience.nim:104`'s
`getBoth[T](QueryGetHandles[T])`):

```nim
func getBoth*(
    resp: Response,
    handles: EmailCopyHandles,
): Result[EmailCopyResults, MethodError] =
  let copy = ?resp.extract(handles.copy)
  let destroy = ?resp.extract(handles.destroy)
  ok(EmailCopyResults(copy: copy, destroy: destroy))
```

If the server failed to append the destroy response (which, per RFC
§4.7, only happens when the copy method itself errored — but could also
happen if a buggy server elided the implicit destroy), the second
`extract` returns `Err(MethodError{rawType: "serverFail"})` via the
dispatch layer's existing missing-call-id handling
(`dispatch.nim:100–105`). Absence surfaces on the `Err` rail — one
source of truth.

### 5.5. Why specific, not generic

`EmailCopyHandles` and `EmailCopyResults` are specific newtypes,
not instances of a generic `CompoundHandles[A, B]` / `CompoundResults[A, B]`.
Part F commits to this despite the apparent shape-duplication with the
Part G `EmailSubmissionHandles` that is coming. Rationale:

- **Appearance ≠ knowledge.** Two records with two fields named `copy` +
  `destroy` look like a generic; the moment Part G introduces its
  analogue with fields named `submission` + `emailSet`, the "shared
  generic" illusion breaks. Their knowledge is different: one encodes a
  single-entity compound operation, the other a cross-entity one.
- **Return-types-as-documentation.** `EmailCopyHandles.destroy:
  ResponseHandle[EmailSetResponse]` tells the reader exactly what the
  second response is. A generic `CompoundHandles[EmailCopyResponse,
  EmailSetResponse].second` loses that domain clarity.
- **Rule of Three.** Part F's `EmailCopyHandles` is instance #1;
  Part G's `EmailSubmissionHandles` will be instance #2. The third
  instance does not yet exist. Introducing a generic at two instances
  is a premature abstraction — Part G may reach the Rule of Three and
  promote both to a shared type living in a new
  `mail/mail_convenience.nim` module.

---

## 6. Email/import

### 6.1. EmailImportItem

RFC 8621 §4.8 specifies four properties per import entry:

- `blobId: Id` — the raw `message/rfc822` blob previously uploaded.
- `mailboxIds: Id[Boolean]` — "The ids of the Mailboxes to assign this
  Email to. At least one Mailbox MUST be given." (RFC §4.8).
- `keywords: String[Boolean]` — default empty.
- `receivedAt: UTCDate` — default "time of the most recent Received
  header, or import time on the server if none".

```nim
type EmailImportItem* = object
  ## Creation-side model for a single Email/import entry (RFC 8621 §4.8).
  blobId*: Id
  mailboxIds*: NonEmptyMailboxIdSet
  keywords*: Opt[KeywordSet]
    ## Opt.none: omit the key entirely (server default — empty).
    ## Opt.some(empty): explicitly empty (still omitted at wire level).
    ## Opt.some(non-empty): emit the full keyword map.
  receivedAt*: Opt[UTCDate]
    ## Opt.none: defer to server default (most recent Received header
    ## or import time). Client cannot replicate this default without
    ## parsing the raw RFC 5322 message — deferral is the principled
    ## choice.

func initEmailImportItem*(
    blobId: Id,
    mailboxIds: NonEmptyMailboxIdSet,
    keywords: Opt[KeywordSet] = Opt.none(KeywordSet),
    receivedAt: Opt[UTCDate] = Opt.none(UTCDate),
): EmailImportItem =
  ## Total constructor. All four fields are validated by their own type
  ## smart constructors; no cross-field invariants exist.
  EmailImportItem(
    blobId: blobId,
    mailboxIds: mailboxIds,
    keywords: keywords,
    receivedAt: receivedAt,
  )
```

**`mailboxIds` is non-`Opt` `NonEmptyMailboxIdSet`.** The RFC marks
`mailboxIds` as required and non-empty; the type reflects both.
Contrast `EmailCopyItem.mailboxIds: Opt[NonEmptyMailboxIdSet]` where the
property is optional (override the source's mailboxes only if specified).

**`keywords: Opt[KeywordSet]`.** The RFC permits either omitted (server
default: empty) or present-as-map. The library distinguishes these via
`Opt.none` vs `Opt.some(KeywordSet)`. A caller wanting "explicitly
empty" (which is wire-indistinguishable from "omitted" per RFC §4.8)
may still construct `Opt.some(initKeywordSet(@[]))` to signal intent
clearly in their own code; the serde layer collapses both to an omitted
key.

**Total constructor rationale.** Mirrors `initEmailCopyItem` (§5.1) and
`initKeywordSet` (Part A). RFC §4.8 specifies zero cross-field
invariants on `EmailImport`; every client-side rule is discharged by
the field-level smart constructors upstream.

### 6.2. NonEmptyEmailImportMap

RFC 8621 §4.8's `emails` parameter is a map from creation-id to
`EmailImport` entry:

```nim
type NonEmptyEmailImportMap* = distinct Table[CreationId, EmailImportItem]

func initNonEmptyEmailImportMap*(
    items: openArray[(CreationId, EmailImportItem)]
): Result[NonEmptyEmailImportMap, seq[ValidationError]]
```

The smart constructor accumulates failures across both invariants in a
single pass:

1. **Non-empty.** An empty `emails` map makes the entire `Email/import`
   invocation pointless (import nothing); reject to prevent the
   wasteful round-trip.
2. **No duplicate creation-ids.** The `openArray` input (rather than
   `Table`) preserves order and surfaces duplicate keys to the
   constructor. Duplicates silently shadow at `Table` construction
   time; accepting the seq form and checking for duplicates here
   prevents data loss.

Accumulating `Result[_, seq[ValidationError]]` follows Part E's
`parseEmailBlueprint` idiom (F13). Contrast `parseNonEmptyMailboxIdSet`
in Part E (§4.2.2), which returns a single-error `Result` because the
`NonEmptyMailboxIdSet` has exactly one invariant (non-empty); with two
independent invariants in play here, the accumulating form is the right
fit.

**Why `openArray[(CreationId, EmailImportItem)]` rather than
`Table[CreationId, EmailImportItem]` as input?** The seq form preserves
duplicate keys through the smart-constructor's inspection pass. A
`Table` input would have already collapsed duplicates at construction,
turning a data-loss event into a silent accept — exactly the class of
error the smart constructor exists to catch.

### 6.3. Builder Signature

```nim
func addEmailImport*(
    b: RequestBuilder,
    accountId: AccountId,
    emails: NonEmptyEmailImportMap,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[EmailImportResponse])
```

**`emails` is required and non-`Opt`**, because there is no meaningful
"no emails" import call. The `NonEmptyEmailImportMap` parameter type
guarantees the caller has already constructed a valid, non-empty,
duplicate-free entry table.

### 6.4. Registration

- `src/jmap_client/methods_enum.nim` — add `mnEmailImport = "Email/import"`
  variant. Currently absent (the plan's pre-flight verification
  confirmed this).
- `src/jmap_client/mail/mail_entities.nim` — extend the Email entity
  registration to add `importMethodName: "Email/import"` constant.
  This allows the dispatch layer to resolve `Email/import` responses to
  `EmailImportResponse` via the same mechanism used for `Email/get`,
  `Email/set`, `Email/query`, etc.

### 6.5. Rationale

Like `addEmailSet`, `addEmailImport` is a mechanical mirror of the
surrounding precedents — principally `addEmailParse`
(`mail/mail_methods.nim:149`, a specialty read verb) for the "blob-input
specialty verbs in `mail_methods.nim`" organising rule. The `emails`
parameter's non-`Opt`, non-empty, duplicate-free typing pushes all
validation to smart-constructor time. Builder-level logic is trivial:
serialise `emails` via `toJson`, assemble the invocation, return the
handle.

The `/parse` precedent does **not** apply to the `emails` parameter's
cardinality: `addEmailParse(blobIds: seq[Id])` accepts any `seq[Id]`
(even empty) because `/parse` is read-shaped and an empty parse returns
an empty list harmlessly. `/import` is write-shaped: an empty import is
wasteful. The asymmetry is justified — appearance (both are specialty
verbs with blob-ids) does not imply shared constraints.

---

## 7. SetError Extraction Reference

### 7.1. Zero new extraction code

Part A already shipped all five mail-specific `SetError.extras`
accessors as `Opt[T]`-returning helpers (`mail/mail_errors.nim`):

| Accessor | Line | Returns | Covers `MailSetErrorType` variants |
|----------|------|---------|-----------------------------------|
| `notFoundBlobIds` | 37 | `Opt[seq[Id]]` | `msetBlobNotFound` |
| `maxSize` | 56 | `Opt[UnsignedInt]` | `msetTooLarge` |
| `maxRecipients` | 70 | `Opt[UnsignedInt]` | `msetTooManyRecipients` |
| `invalidRecipientAddresses` | 84 | `Opt[seq[string]]` | `msetInvalidRecipients` |
| `invalidEmailProperties` | 100 | `Opt[seq[string]]` | `msetInvalidEmail` |

Core `SetError` already carries:
- `existingId: Id` on the `setAlreadyExists` case-branch
  (`src/jmap_client/errors.nim`)
- `properties: seq[string]` on the `setInvalidProperties` case-branch

Part F adds **zero** new extraction code. Every RFC §§4.6/4.7/4.8
SetError variant is already extractable via an existing mechanism.

### 7.2. Reference Table

| Method | RFC-listed SetError | Core enum? | Payload extraction |
|--------|---------------------|------------|--------------------|
| Email/set (§4.6) | `invalidProperties` | `setInvalidProperties` | `err.properties: seq[string]` (core case-branch) |
| Email/set (§4.6) | `blobNotFound` | — (mail `msetBlobNotFound` via `rawType`) | `err.notFoundBlobIds(): Opt[seq[Id]]` |
| Email/set (§4.6) | `tooManyKeywords` | — (mail `msetTooManyKeywords` via `rawType`) | no payload; error is self-describing |
| Email/set (§4.6) | `tooManyMailboxes` | — (mail `msetTooManyMailboxes` via `rawType`) | no payload |
| Email/copy (§4.7) | `alreadyExists` | `setAlreadyExists` | `err.existingId: Id` (core case-branch) |
| Email/copy (§4.7) | `notFound` | `setNotFound` | no payload |
| Email/import (§4.8) | `alreadyExists` | `setAlreadyExists` | `err.existingId: Id` (core case-branch) |
| Email/import (§4.8) | `invalidEmail` | — (mail `msetInvalidEmail` via `rawType`) | `err.invalidEmailProperties(): Opt[seq[string]]` |
| Email/import (§4.8) | `overQuota` | `setOverQuota` | no payload (core RFC 8620 §5.3 generic SetError) |
| Email/import (§4.8) | `invalidProperties` | `setInvalidProperties` | `err.properties: seq[string]` (core case-branch) |

RFC §4.8 does not define a mail-specific `notFound` or `tooLarge`
SetError for `Email/import`. An unknown `blobId` surfaces as
`invalidProperties` per §4.8's "If the 'blobId', 'mailboxIds', or
'keywords' properties are invalid (e.g., missing, wrong type, id not
found), the server MUST reject the import with an 'invalidProperties'
SetError" (RFC lines 3040–3042). The mail-specific `msetTooLarge`
variant (paired with the `maxSize` payload extractor at
`mail_errors.nim:56`) is defined by EmailSubmission (Part G) and does
not apply to Part F methods. The *core* `setTooLarge` (RFC 8620 §5.3,
no payload) does apply — see the per-operation scoping table below.
Implementers must route `tooLarge` errors from Part F methods to
`setTooLarge`, not `msetTooLarge`.

Core RFC 8620 §5.3 generic SetErrors apply transitively to Part F
methods, scoped per RFC §5.3's per-operation annotations:

| SetError | RFC op-scope | Email/set | Email/copy | Email/import |
|----------|--------------|-----------|------------|--------------|
| `forbidden` | create;update;destroy | ✓ | ✓ | ✓ |
| `overQuota` | create;update | ✓ (create;update) | ✓ (create) | ✓ (create) |
| `tooLarge` | create;update | ✓ (create;update) | ✓ (create) | ✓ (create) |
| `rateLimit` | create | ✓ (create) | ✓ (create) | ✓ (create) |
| `notFound` | update;destroy | ✓ (update) | ✓ (see RFC 8620 §5.4 "create or update" clause; RFC 8621 §4.7 also grants `notFound` explicitly for missing blobId) | — |
| `invalidPatch` | update | ✓ (update only) | — | — |
| `willDestroy` | update | ✓ (update only) | — | — |
| `invalidProperties` | create;update | ✓ (create;update) | ✓ (create) | ✓ (create) |

`singleton` (RFC §5.3: create;destroy) is **not** applicable to any
Part F method because Email is not a singleton type — singleton types
in JMAP Mail are `VacationResponse` (RFC 8621 §8) and `Identity` (RFC
8621 §6). A conformant server will never emit `singleton` for Email
and implementers need not wire a handler branch for it.

All variants in the table surface via core's `SetErrorType` enum with
no mail-specific payload extractors. `invalidPatch` remains relevant
post-F19: the typed update algebra still serialises to an RFC 8620
§5.3 JSON Pointer patch that a server may reject (for example, if a
keyword contains an unescaped JSON Pointer metacharacter — see
§3.2.5).

**`Email/copy` with `onSuccessDestroyOriginal: true`:** RFC 8620 §5.4
specifies that a successful copy with `onSuccessDestroyOriginal` emits
a *second* response sharing the same method-call-id, corresponding to
an implicit `Email/set { destroy: [...] }` call on the source account.
That implicit response carries its own `notDestroyed` SetError map,
populated with destroy-scoped SetErrors: `notFound`, `forbidden`,
`willDestroy`. Implementers must expect and handle two responses per
copy when this flag is set.

### 7.3. Caller flow

Every mail-specific `SetError` carries `errorType: setUnknown` in the
core enum, because core's `SetErrorType` enumerates only the RFC 8620
base variants. Mail-specific variants live in the string-backed
`MailSetErrorType` enum and surface via the `rawType: string` field
on `SetError`. Typical caller pattern:

```nim
case err.errorType
of setAlreadyExists:
  # Core variant — existingId is a case-branch field.
  echo "Email already exists at ", string(err.existingId)
of setInvalidProperties:
  echo "Invalid properties: ", err.properties
of setUnknown:
  # May be a mail-specific variant — decode via rawType.
  case parseMailSetErrorType(err.rawType)
  of msetBlobNotFound:
    for blobIds in err.notFoundBlobIds():
      echo "Blobs not found: ", blobIds
  of msetInvalidEmail:
    for properties in err.invalidEmailProperties():
      echo "Invalid email properties: ", properties
  of msetTooLarge:
    for limit in err.maxSize():
      echo "Too large, max: ", limit
  else:
    echo "Unclassified error: ", err.rawType
else:
  echo "Other error: ", $err.errorType
```

The flow is verbose but unambiguous. Part F does **not** introduce a
unifying wrapper proc that collapses the two-step
(`errorType == setUnknown` + `parseMailSetErrorType(rawType)`) sequence.
Rationale:

- **Rule of Three.** Part F has exactly two call sites (`Email/set`
  failure handling, `Email/import` failure handling — `Email/copy`'s
  SetError set is fully in core). Introducing a unifying wrapper at two
  instances is premature. Part G (EmailSubmission) or later may reach
  a third; that is the right moment to consolidate.
- **Return-types-as-documentation.** Separate `errorType` and `rawType`
  checks make the "mail-specific vs core" axis explicit in the caller's
  code. A wrapper that hides the split would obscure which errors
  consumers must learn to handle.

### 7.4. Method-level errors

Some errors for Part F methods are `MethodErrorType`, not
`SetErrorType` — these surface on the outer `MethodError` railway, not
inside `createResults`. RFC-listed method-specific errors:

| Method | MethodError | Core `MethodErrorType`? |
|--------|-------------|-------------------------|
| Email/set | `stateMismatch` | `metStateMismatch` |
| Email/set | `requestTooLarge` | `metRequestTooLarge` |
| Email/copy | `stateMismatch` | `metStateMismatch` |
| Email/copy | `fromAccountNotFound` | `metFromAccountNotFound` |
| Email/copy | `fromAccountNotSupportedByMethod` | `metFromAccountNotSupportedByMethod` |
| Email/import | `stateMismatch` | `metStateMismatch` |
| Email/import | `requestTooLarge` | `metRequestTooLarge` |

RFC 8620 §5.3 defines `requestTooLarge` as a method-level error for
every `/set`-shape method (RFC 8620 lines 2169–2172); it applies
directly to `Email/set` and by analogy to `Email/import` (which has a
creation-id map and a batch-count limit structurally identical to
`/set`, though RFC 8621 §4.8 enumerates only `stateMismatch` as an
explicit additional method-level error). It does not apply to `/copy`. `anchorNotFound` is
specific to `/query`/`/queryChanges` (RFC 8620 §§5.5–5.6) and does not
apply to any Part F method. RFC 8620 §3.6.2 generic method-level
errors (`serverFail`, `accountNotFound`, `accountNotSupportedByMethod`,
`accountReadOnly`, `invalidArguments`, `invalidResultReference`,
`forbidden`) apply transitively to all three methods.

All of these are already in core's `MethodErrorType` enum. Part F adds
no new method-error classifications.

---

## 8. Test Specification

The test specification for Part F lives in its companion document
[`11-mail-F2-design.md`](./11-mail-F2-design.md). Section number `8`
is preserved there so that cross-references from §1–§7 and §9 of this
document (e.g. "§8.6 test infrastructure additions") remain valid.

---

## 9. Decision Traceability Matrix

Flat numbering F1–F23 per F18, mirroring Part E's E1–E31 convention
without decimal sub-rows. Row F4 absorbs the D4.1–D4.5 dissolution /
resolution bundle via a bulleted "Chosen" cell. F9 and F14 preserve the
DISSOLVED and SUBSUMED paper trail per F18.

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|----------|--------------------|--------|---------------------|
| F1 | Part F scope boundary | A) Email/set + Email/copy + Email/import together; B) Email/set only, defer copy+import; C) Email/set + Email/copy only | A — three methods together so the shared four-field create shape has a single source of truth | Make illegal states unrepresentable, DRY, code reads like the spec |
| F2 | `EmailCreatedItem` typed vs raw JsonNode | A) `Table[CreationId, Result[JsonNode, SetError]]`; B) Typed `EmailCreatedItem` record across all three response types; C) Raw + per-call typed accessor | B refined — `EmailCreatedItem` threaded through `EmailSetResponse`, `EmailCopyResponse`, `EmailImportResponse`; generic `addSet[Email]` NOT exposed | Parse once at the boundary, illegal states unrepresentable, one source of truth |
| F3 | Generic `CompoundHandles[A, B]` now vs defer | A) Generic now; B) Specific `EmailCopyHandles` + defer generic to Part G; C) Specific always | B — specific newtype now (Rule of Three defers generic); field names revised by F11 | DDD, return-types-as-documentation, Rule of Three |
| F4 | PatchObject dissolution + typed update algebra scope (absorbs F4.1–F4.5) | — | **Chosen:** <ul><li>F4.1: all three entities get typed algebras (Email + Mailbox + VacationResponse); PatchObject fully retires from public mail API</li><li>F4.2: `EmailUpdate` has 6 variants (1:1 with RFC wire ops) + 5 domain-named convenience ctors structurally equal to their primitive counterparts (Option G)</li><li>F4.3: specialised-vs-generic overlap resolved by Option G — one value, multiple constructor names</li><li>F4.4: per-entity distinct seqs (`EmailUpdateSet` / `MailboxUpdateSet` / `VacationResponseUpdateSet`) with accumulating smart ctors returning `Result[T, seq[ValidationError]]`; `EmailUpdateSet` rejects 3 conflict classes at construction</li><li>F4.5: module homes — `EmailUpdate` in new `email_update.nim`; `MailboxUpdate` and `VacationResponseUpdate` inline in their home modules</li></ul> | Make illegal states unrepresentable, one source of truth, parse once at the boundary, right thing easy, DDD, duplicated appearance ≠ duplicated knowledge |
| F5 | Email/set + Email/copy module home | A) Extend `mail_builders.nim`; B) New `email_write.nim`; C) New `mail_set.nim` + `mail_copy.nim` | A — mirrors CRUD-in-`mail_builders.nim` / specialty-verbs-in-`mail_methods.nim` split | DDD, precedent, right thing easy |
| F6 | Email/import module home | A) Extend `mail_methods.nim`; B) New `email_write.nim` (shared with /set, /copy); C) New `email_import.nim` | A — respects codebase's shape-based organising principle (blob-input verbs cluster in `mail_methods.nim`) | DDD, precedent |
| F7 | Shared response-type home | A) Split by layer — L1 data types in `email.nim`, L3 protocol `EmailCopyHandles` in `mail_builders.nim`; B) Consolidate in new `mail_responses.nim`; C) Dedicated new file per response type | A — L1 types follow `ParsedEmail` precedent (`email.nim:188`); L3 compound-handle follows `QueryGetHandles` + `getBoth` colocation in `convenience.nim` | DDD, strict layer discipline, Rule of Three |
| F8 | `addEmailSet` create-map parameter type | A) Exact `addMailboxSet` precedent match — `Opt[Table[CreationId, EmailBlueprint]]`; B) Raw `JsonNode` for consistency with generic builder; C) Typed but non-Opt | A — mirror precedent exactly with Email substitutions | Precedent, DDD, illegal states unrepresentable |
| F9 | Update-path PatchObject: raw vs typed safe-update wrapper | — | **DISSOLVED** — subsumed by F4.1–F4.5. Typed algebra replaces both PatchObject's public role and any wrapper concept. | — |
| F10 | `EmailCopyItem` smart constructor policy | A) Total function (no Result); B) Result-returning with single-error rail; C) Result-returning with accumulating rail | A — all field types pre-validated; no cross-field invariants at this level; signature tightened to `Opt[NonEmptyMailboxIdSet]` | Return-types-as-documentation, constructors-that-can-fail-return-Result / can't-don't |
| F11 | Chained overload naming + `EmailCopyHandles` field names | A) `addEmailCopyChained` + fields `sourceSet`/`copy`; B) `addEmailCopyAndDestroy` + fields `copy`/`destroy`; C) `addEmailCopyWithImplicitDestroy` + fields `copy`/`implicitDestroy` | B — outcome-oriented verb + outcome-named fields; one abstraction register used consistently | One source of truth, right thing easy, return-types-as-documentation |
| F12 | Compound-handle semantics when implicit Email/set response is absent | A) Non-Opt both fields, short-circuit on `copy` first via `?`; B) `destroy: Opt[EmailSetResponse]`; C) Sum type `CopySuccess`/`CopyFailed`; D) Non-short-circuit tuple | A — mirrors `QueryGetHandles`/`getBoth` precedent; absence surfaces only via Err rail (`MethodError{rawType: "serverFail"}`) | One source of truth, return-types-as-documentation, composability with `?` operator |
| F13 | Non-empty `emails` table enforcement | A) Distinct `NonEmptyEmailImportMap` + accumulating smart ctor rejecting empty + duplicate CreationIds; B) Plain `seq[(CreationId, EmailImportItem)]` + builder-level check; C) `seq[Id]` precedent from `/parse`; D) Result on builder; E/F/G) Variants | A — smart ctor on distinct Table per NonEmptyMailboxIdSet precedent; accumulating to carry both invariants in one pass | Parse once at the boundary, illegal states unrepresentable, constructors-that-can-fail-return-Result |
| F14 | `createResults` element type (JsonNode vs `EmailCreatedItem`) | — | **SUBSUMED BY F2** — Part F commits to `Table[CreationId, Result[EmailCreatedItem, SetError]]` uniformly across all three response types. | — |
| F15 | `EmailImportItem` error accumulation style | A) Total function, typed inputs (`NonEmptyMailboxIdSet` param); B) Result-returning accumulating; C) Result-returning short-circuit; D) Builder-time accumulation | A — mirrors F10 pattern; four RFC fields with no client-enforceable cross-field invariants; all discharged by field-type smart ctors | Return-types-as-documentation, parse once at the boundary, constructors-can't-fail-don't |
| F16 | Typed `alreadyExists`/`blobNotFound` accessor helpers | — | RESOLVED — no new code. Part A already shipped all five mail-specific `SetError.extras` accessors plus core `existingId`/`properties` case-fields | DRY, precedent |
| F17 | Test specification shape | A) Mirror Part E file-level spec (lettered-by-part + per-concept unit/serde); B) Per-method consolidation; C) Flat scenario numbering; D) Hybrid | A — mirrors Part E; lettered-by-part files (`tprop_mail_f.nim`, etc.) continue the convention; per-concept unit/serde files | Precedent, right thing easy, DRY |
| F18 | Decision Traceability Matrix location | A) Per-part only; B) Update architecture's matrix in-place; C) Both (cross-reference) | B — self-contained per-part DTM with F-prefixed flat numbering (F1–F23); architecture DTM updates ship in a separate follow-up PR per F20 | Minimal surface, precedent adherence, one matrix per part |
| F19 | PatchObject demotion strategy | A) Keep public, unused by mail; B) Demote to internal via drop-`*`-export; C) Deprecate with warning; D) Leave alone | B — `PatchObject*` loses `*` in `framework.nim:80`; serde helpers relocate to `serde_framework.nim` as now-private; 6 src + ~17 tests migrated in the Part F implementation PR | One source of truth, wrong-thing-hard, right-thing-easy |
| F20 | Architecture amendment PR grouping | A) Same PR, two commits; B) Separate follow-up PR after Part F lands; C) Pre-amendment before Part F; D) Inline appendix in Part F | B — per-part design doc is authoritative for its scope; architecture amendments land after implementation so docs can reference live state truthfully | User preference for small focused PRs, truthfulness of references |
| F21 | `moveToMailbox(id)` wire semantics | A) Replace (`euSetMailboxIds`); B) Add (`euAddToMailbox`); C) Drop the convenience ctor | A — matches universal mail-UI "Move to" semantics; name ↔ variant agree; one source of truth at the value level (`moveToMailbox(id) ≡ setMailboxIds([id])`) | DDD, right thing easy, return-types-as-documentation, one source of truth |
| F22 | `initEmailUpdateSet` empty-input policy | A) Reject at ctor; B) Allow empty; C) Distinct `NonEmpty*` type | A — empty input returns `Err([validationError(..., "emptyUpdateSet")])`; builder's `update: Opt[Table[Id, EmailUpdateSet]]` has exactly one "no updates for this id" representation (omit the entry) | One source of truth, illegal states unrepresentable, return-types-as-documentation, DRY, right thing easy |
| F23 | `EmailUpdateSet` conflict-class formal rules | Derivation from RFC 8620 §5.3 patch semantics | Three classes with target-path table (§3.2.4): (1) duplicate target path — rejects two updates on the same target; (2) opposite ops on same sub-path — rejects redundant add/remove pairs; (3) sub-path op alongside full-replace on same parent — rejects server-order-dependent ambiguity. Smart ctor returns `Result[_, seq[ValidationError]]` with one ValidationError per detected conflict (accumulating). | One source of truth, illegal states unrepresentable, parse once at the boundary |

---

*End of Part F1 design document.*
