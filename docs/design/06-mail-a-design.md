# RFC 8621 JMAP Mail — Design A: Thread, Identity, VacationResponse

This document is the detailed specification for three RFC 8621 entity types —
Thread, Identity, and VacationResponse — plus their supporting types. It
covers all layers (L1 types, L2 serde, L3 entity registration and builder
functions) for each entity, cutting vertically through the architecture.

Builds on the cross-cutting architecture design (`05-mail-architecture.md`)
and the existing RFC 8620 infrastructure (`00-architecture.md` through
`04-layer-4-design.md`). Decisions from the cross-cutting doc are referenced
by section number.

---

## Table of Contents

1. [Scope](#1-scope)
2. [Shared Sub-Types — addresses.nim](#2-shared-sub-types--addressesnim)
3. [Thread — thread.nim](#3-thread--threadnim)
4. [Identity — identity.nim](#4-identity--identitynim)
5. [VacationResponse — vacation.nim](#5-vacationresponse--vacationnim)
6. [Capability Types — mail_capabilities.nim](#6-capability-types--mail_capabilitiesnim)
7. [Mail Set Error Accessors — mail_errors.nim](#7-mail-set-error-accessors--mail_errorsnim)
8. [Test Specification](#8-test-specification)
9. [Decision Traceability Matrix](#9-decision-traceability-matrix)

---

## 1. Scope

### 1.1. Entities Covered

| Entity           | RFC 8621 Section | Capability URI                          | Complexity |
|------------------|------------------|-----------------------------------------|------------|
| Thread           | §3               | `urn:ietf:params:jmap:mail`             | Simple     |
| Identity         | §6               | `urn:ietf:params:jmap:submission`       | Simple     |
| VacationResponse | §8               | `urn:ietf:params:jmap:vacationresponse` | Simple     |

### 1.2. Supporting Types Covered

| Type | Module | Rationale |
|------|--------|-----------|
| `EmailAddress`, `EmailAddressGroup` | `addresses.nim` | Shared sub-type required by Identity; also consumed by Email and EmailSubmission |
| `MailCapabilities` | `mail_capabilities.nim` | Typed parsing of the `urn:ietf:params:jmap:mail` capability |
| `SubmissionCapabilities` | `mail_capabilities.nim` | Typed parsing of the `urn:ietf:params:jmap:submission` capability |
| `SubmissionExtensionMap` | `mail_capabilities.nim` | RFC 5321 EHLO-keyword → args map keyed by validated `RFC5321Keyword` |
| Mail set error accessors | `mail_errors.nim` | Mail-specific predicate vocabulary over the central `SetError` ADT |

### 1.3. Module Summary

All modules live under `src/jmap_client/mail/`.

| Module | Layer | Contents |
|--------|-------|----------|
| `addresses.nim` | L1 | `EmailAddress`, `EmailAddressGroup`, `parseEmailAddress` |
| `thread.nim` | L1 | `Thread` (sealed-fields), `parseThread`, `id`/`emailIds` accessors |
| `identity.nim` | L1 | `Identity`, `IdentityCreate`, `IdentityCreatedItem`, `IdentityUpdate`, `IdentityUpdateSet`, `NonEmptyIdentityUpdates` |
| `vacation.nim` | L1 | `VacationResponse`, `VacationResponseUpdate`, `VacationResponseUpdateSet`, `VacationResponseSingletonId` |
| `mail_capabilities.nim` | L1 | `MailCapabilities`, `SubmissionCapabilities`, `SubmissionExtensionMap` |
| `mail_errors.nim` | L1 | Mail-specific typed accessors over `SetError` |
| `serde_addresses.nim` | L2 | `toJson`/`fromJson` for `EmailAddress` and `EmailAddressGroup` |
| `serde_thread.nim` | L2 | `toJson`/`fromJson` for `Thread` |
| `serde_identity.nim` | L2 | `toJson`/`fromJson` for `Identity` and `IdentityCreatedItem`; `toJson` only for `IdentityCreate` |
| `serde_identity_update.nim` | L2 | `toJson` for `IdentityUpdate`/`IdentityUpdateSet`/`NonEmptyIdentityUpdates` |
| `serde_vacation.nim` | L2 | `toJson`/`fromJson` for `VacationResponse`; `toJson` for `VacationResponseUpdate`/`VacationResponseUpdateSet` |
| `serde_mail_capabilities.nim` | L2 | `parseMailCapabilities`, `parseSubmissionCapabilities` |
| `mail_entities.nim` | L3 | Per-verb method-name resolvers, `capabilityUri`, `registerJmapEntity`/`registerSettableEntity` |
| `identity_builders.nim` | L3 | Thin wrappers `addIdentityGet`/`addIdentityChanges`/`addIdentitySet` |
| `mail_methods.nim` | L3 | `addVacationResponseGet`, `addVacationResponseSet` (and the SearchSnippet/Email-parse/Email-import builders) |

### 1.4. Relationship to Cross-Cutting Design

This document specifies the per-entity layout for the simplest three RFC 8621
entities. Full RFC 8621 coverage spans the companion design documents
(`07-mail-b-design.md` through `13-mail-H1-design.md`); the patterns
introduced here (sealed-field invariants, typed creation models, typed update
algebras, custom builder functions for non-standard entities, capability
parsing) recur throughout.

---

## 2. Shared Sub-Types — addresses.nim

**Module:** `src/jmap_client/mail/addresses.nim`

`EmailAddress` and `EmailAddressGroup` are shared sub-types used by multiple
entities — Identity, Email, and EmailSubmission. They are specified here as
a prerequisite section because Identity consumes them.

**Principles:** DDD (addresses are their own bounded context), DRY (one
specification, three consumers), Parse-don't-validate (full parsing
boundary defined now).

### 2.1. EmailAddress

**RFC reference:** §4.1.2.3.

An `EmailAddress` represents a single email address with an optional display
name. Used by Identity (`replyTo`, `bcc`), Email (convenience header
fields), and EmailSubmission (envelope addresses).

```nim
type EmailAddress* {.ruleOff: "objects".} = object
  name*: Opt[string]   ## Display name, or none if absent.
  email*: string       ## RFC 5322 addr-spec (non-empty, not format-validated).
```

Plain public fields. The `email` non-empty invariant is enforced by the
smart constructor `parseEmailAddress`. `EmailAddress` is a value object
used extensively — sealed-field accessor ceremony is disproportionate to
the risk.

**Smart constructor:**

```nim
func parseEmailAddress*(
    email: string, name: Opt[string] = Opt.none(string),
): Result[EmailAddress, ValidationError]
```

Validates: `email.len > 0`. No format validation beyond non-empty — JMAP
servers deliver clean JSON with pre-parsed addresses, and the
`forbiddenFrom` set error handles invalid sender addresses at the protocol
level.

### 2.2. EmailAddressGroup

**RFC reference:** §4.1.2.4.

```nim
type EmailAddressGroup* {.ruleOff: "objects".} = object
  name*: Opt[string]              ## Group name, or none if not a named group.
  addresses*: seq[EmailAddress]   ## Members of the group (may be empty).
```

No smart constructor — all invariants are captured by the field types.
`addresses` may be empty (a group with no members is valid per RFC).

### 2.3. Serde — serde_addresses.nim

**Module:** `src/jmap_client/mail/serde_addresses.nim`

`fromJson` returns `Result[T, SerdeViolation]` — the structured serde-error
ADT used at every wire boundary. L1 smart-constructor failures bridge into
the serde rail via `wrapInner` (which wraps a `Result[T, ValidationError]`
inside `SerdeViolation.svkFieldParserFailed`).

**EmailAddress wire format:**

```json
{"name": "Joe Bloggs", "email": "joe@example.com"}
{"name": null, "email": "joe@example.com"}
```

**`toJson(ea: EmailAddress)`**
- Emits `name` as string or `null` (from `Opt.none`).
- Always emits `email`.

**`EmailAddress.fromJson`**
- Validates JObject via `expectKind`.
- Extracts required `email` field via `fieldJString`.
- Extracts optional `name` via `optJsonField` — absent or null → `Opt.none`,
  string → `Opt.some(value)`.
- Delegates to `parseEmailAddress`, bridged through `wrapInner`.

**EmailAddressGroup wire format:**

```json
{"name": "Engineering", "addresses": [{"name": null, "email": "eng@example.com"}]}
{"name": null, "addresses": []}
```

**`toJson(group: EmailAddressGroup)`**
- Emits `name` as string or `null`.
- Always emits `addresses` array.

**`EmailAddressGroup.fromJson`**
- Validates JObject.
- Extracts `name` (same null handling as `EmailAddress`).
- Extracts `addresses` as required JArray; parses each element via
  `EmailAddress.fromJson`. Short-circuits on first element error via `?`.
- Constructs `EmailAddressGroup` directly — no smart constructor.

---

## 3. Thread — thread.nim

**RFC reference:** §3.

A Thread groups related Emails into a flat list sorted by `receivedAt`.
Every Email belongs to exactly one Thread. Thread is the simplest entity
in RFC 8621 — two properties, two methods, no `/query`, no `/set`.

**Module:** `src/jmap_client/mail/thread.nim`

### 3.1. Type Definition

Thread uses **sealed (module-private) fields** to enforce the non-empty
`emailIds` invariant that `seq[Id]` cannot express on its own — every
Thread contains at least one Email per RFC §3.

```nim
type Thread* {.ruleOff: "objects".} = object
  rawId: Id              ## module-private
  rawEmailIds: seq[Id]   ## module-private, guaranteed non-empty
```

Sealed fields prevent external construction with arbitrary state — the
consumer cannot name any field in a `Thread(...)` literal outside
`thread.nim`. The only legitimate construction paths are `parseThread`
(which enforces non-empty `emailIds`) and `Thread.fromJson` (which
delegates to `parseThread`).

The project's `config.nims` promotes `ProveInit` to an error, so a `var t:
Thread` without provable initialisation is a compile error.

**No `{.requiresInit.}` pragma.** That pragma is incompatible with
`seq[Thread]` under the project's `UnsafeSetLen` error promotion — Nim's
internal `seq` hooks (`=destroy`, `=copy`) instantiate `setLen` code
paths, which would block `GetResponse[Thread]` and any collection usage.
Sealed fields alone provide the practical guarantee.

**Principles:**
- **Make illegal states unrepresentable** — Module-private fields plus
  the smart constructor guarantee non-empty `emailIds`.
- **Parse, don't validate** — The smart constructor enforces the
  invariant once at the construction boundary.

### 3.2. Smart Constructor

```nim
func parseThread*(id: Id, emailIds: seq[Id]):
    Result[Thread, ValidationError]
```

Validates: `emailIds.len > 0`. Returns
`err(validationError("Thread", "emailIds must contain at least one Id", ""))`
on violation. A Thread with zero emails has no domain meaning — invalid
server data belongs on the error rail.

### 3.3. Accessors

```nim
func id*(t: Thread): Id
func emailIds*(t: Thread): seq[Id]
```

UFCS accessors for the sealed fields. `emailIds` returns a copy of the
internal `seq[Id]` (value semantics under ARC).

### 3.4. Serde — serde_thread.nim

**Module:** `src/jmap_client/mail/serde_thread.nim`

**Wire format:**

```json
{
  "id": "f123u4",
  "emailIds": ["eaa623", "f782cbb"]
}
```

**`toJson(t: Thread)`**
- Emits `id` and `emailIds` fields.
- Reads sealed fields through the public accessors.

**`Thread.fromJson`**
- Validates JObject.
- Extracts `id` via `fieldJString` + `Id.fromJson`.
- Extracts `emailIds` as a required JArray; parses each element via
  `Id.fromJson`, short-circuiting on the first element error via `?`.
- Delegates to `parseThread`, bridged through `wrapInner` (so the
  non-empty rejection surfaces as `svkFieldParserFailed`).

### 3.5. Entity Registration

**Module:** `src/jmap_client/mail/mail_entities.nim`

Thread supports `/get` (§3.1) and `/changes` (§3.2). It has no `/query`,
`/set`, `/copy`, `/queryChanges`, or `/parse` overload — the corresponding
per-verb resolvers are deliberately absent, so `addSet[Thread]` (etc.)
fails at the call site with an undeclared-identifier compile error.

```nim
func methodEntity*(T: typedesc[thread.Thread]): MethodEntity = meThread
func getMethodName*(T: typedesc[thread.Thread]): MethodName = mnThreadGet
func changesMethodName*(T: typedesc[thread.Thread]): MethodName = mnThreadChanges
func capabilityUri*(T: typedesc[thread.Thread]): string = "urn:ietf:params:jmap:mail"

template changesResponseType*(T: typedesc[thread.Thread]): typedesc =
  ChangesResponse[thread.Thread]

registerJmapEntity(thread.Thread)
```

`registerJmapEntity` emits a static check that `methodEntity` and
`capabilityUri` exist for `Thread`; missing overloads produce a
domain-specific compile error rather than a cryptic failure at a
generic call site. Per-verb method-name resolvers are not part of that
check by design — they fail at the consumer's `addX[Thread]` call site
with a precise undeclared-identifier error.

`Thread` participates in chained methods: `GetResponse[Thread]` is
registered via `registerChainableMethod` so that `Thread/get` may chain
out to `Email/get` via `rpListEmailIds` (RFC 8621 §4.10 first-login
workflow).

**Builder usage:** Generic `addGet[Thread]` and `addChanges[Thread]` —
no entity-specific extensions.

---

## 4. Identity — identity.nim

**RFC reference:** §6.

An Identity stores information about an email address or domain the user
may send from. Eight properties, three standard methods (`/get`,
`/changes`, `/set`). The defining constraints: `email` is immutable after
creation, and the `/set` `created[cid]` payload is a server-set subset
(not the full Identity record).

**Module:** `src/jmap_client/mail/identity.nim`

### 4.1. Identity (Read Model)

Plain public fields. All field-level invariants are captured by the field
types themselves (`Id`, `Opt[seq[EmailAddress]]`, `bool`, `string`); no
cross-field invariants.

```nim
type Identity* {.ruleOff: "objects".} = object
  id*: Id                              ## Server-assigned identifier.
  name*: string                        ## Display name; default "".
  email*: string                       ## Email address; immutable after creation.
  replyTo*: Opt[seq[EmailAddress]]     ## Default Reply-To addresses, or none.
  bcc*: Opt[seq[EmailAddress]]         ## Default Bcc addresses, or none.
  textSignature*: string               ## Plain-text signature; default "".
  htmlSignature*: string               ## HTML signature; default "".
  mayDelete*: bool                     ## Server-set; whether the client may delete.
```

**String fields use `string`, not `Opt[string]`.** The RFC specifies
`name`, `textSignature`, and `htmlSignature` as `String` (never null) with
default `""`. `Identity.fromJson` treats absent keys as `""` (the
RFC-defined default). This eliminates a meaningless `Opt.none` state and
keeps the `Opt`-means-nullable convention clean across the codebase.

**`email` immutability** is server-enforced. Attempting to update `email`
via `/set` returns a `SetError`. The type-level "email required on
create" lives on `IdentityCreate` (§4.2).

**`email` lenient-on-receive.** RFC 8621 §6.1 specifies `email` as a
plain `String` with no MUST-non-empty constraint. Cyrus 3.12.2 emits an
empty `email` for server-default identities (config-derived, no explicit
address); Stalwart and James populate it with the user's primary
address. `Identity.fromJson` accepts whatever string the server sends —
client-construction validation lives in `parseIdentityCreate`, not on
the receive path.

**`mayDelete`** is a server-set boolean. Attempting to destroy an
Identity with `mayDelete == false` surfaces as a per-id `SetError` inside
`destroyResults` — there is no client-side pre-check.

No smart constructor for the read model — `fromJson` extracts fields,
validates JSON structure, and constructs directly.

### 4.2. IdentityCreate (Creation Model)

The Identity read model and creation model have different valid field
sets: creates require `email` and exclude `id`/`mayDelete`. A distinct
type makes "create without email" unrepresentable.

```nim
type IdentityCreate* {.ruleOff: "objects".} = object
  email*: string                       ## Required, non-empty.
  name*: string                        ## Default "".
  replyTo*: Opt[seq[EmailAddress]]     ## Default Opt.none.
  bcc*: Opt[seq[EmailAddress]]         ## Default Opt.none.
  textSignature*: string               ## Default "".
  htmlSignature*: string               ## Default "".
```

**Smart constructor:**

```nim
func parseIdentityCreate*(
    email: string,
    name: string = "",
    replyTo: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    bcc: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    textSignature: string = "",
    htmlSignature: string = "",
): Result[IdentityCreate, ValidationError]
```

Validates: `email.len > 0`. Default parameter values match RFC-specified
defaults for ergonomic construction:

```nim
let ic = ?parseIdentityCreate(email = "joe@example.com")
let ic2 = ?parseIdentityCreate(email = "joe@example.com", name = "Joe")
```

**Layer separation:** `IdentityCreate` is a Layer 1 type. Its `toJson` is
in `serde_identity.nim`. `addIdentitySet` accepts
`Opt[Table[CreationId, IdentityCreate]]` directly — `addSet[Identity, ...]`
resolves `IdentityCreate.toJson` via `mixin` at the instantiation site.

### 4.3. IdentityCreatedItem (Server-Set Subset)

The wire payload for `/set`'s `created[cid]` table is *not* the full
`Identity` record. RFC 8620 §5.3 says the server MUST return the new
`id` plus any server-set or server-modified properties; for Identity
the only such property is `mayDelete`. The client already sent every
other field in `create`.

```nim
type IdentityCreatedItem* {.ruleOff: "objects".} = object
  id*: Id
  mayDelete*: Opt[bool]
```

**`mayDelete: Opt[bool]`** — Stalwart 0.15.5 omits `mayDelete` from this
payload (a strict-RFC §5.3 minor divergence): the create acknowledgement
is just `{"id": "<id>"}`. Postel-receive accommodation; mirrors the
`EmailCreatedItem` design.

`SetResponse[IdentityCreatedItem]` is the typed response carried by the
`addIdentitySet` handle (§4.6), keyed by `CreationId` in
`createResults`.

### 4.4. Identity Update Algebra

The settable Identity properties (RFC 8621 §6) are five: `name`, `replyTo`,
`bcc`, `textSignature`, `htmlSignature`. A typed sum-type ADT with one
variant per settable property makes "exactly one target per update" a
type-level fact — no empty patches and no multi-property patches in a
single `IdentityUpdate`. Shape mirrors `MailboxUpdate` and
`VacationResponseUpdate`.

```nim
type IdentityUpdateVariantKind* = enum
  iuSetName
  iuSetReplyTo
  iuSetBcc
  iuSetTextSignature
  iuSetHtmlSignature

type IdentityUpdate* {.ruleOff: "objects".} = object
  case kind*: IdentityUpdateVariantKind
  of iuSetName:           name*: string
  of iuSetReplyTo:        replyTo*: Opt[seq[EmailAddress]]
  of iuSetBcc:            bcc*: Opt[seq[EmailAddress]]
  of iuSetTextSignature:  textSignature*: string
  of iuSetHtmlSignature:  htmlSignature*: string
```

`Opt.none` on `replyTo` / `bcc` clears the default list, per RFC 8621 §6.

**Builder helpers** (one per variant) construct the case object with the
correct literal discriminator:

```nim
func setName*(name: string): IdentityUpdate
func setReplyTo*(replyTo: Opt[seq[EmailAddress]]): IdentityUpdate
func setBcc*(bcc: Opt[seq[EmailAddress]]): IdentityUpdate
func setTextSignature*(textSignature: string): IdentityUpdate
func setHtmlSignature*(htmlSignature: string): IdentityUpdate
```

#### IdentityUpdateSet — per-id batch

A single `/set` update on an Identity may touch several properties at
once. `IdentityUpdateSet` is a validated, conflict-free batch of
`IdentityUpdate` operations targeting one Identity:

```nim
type IdentityUpdateSet* = distinct seq[IdentityUpdate]

func initIdentityUpdateSet*(updates: openArray[IdentityUpdate]):
    Result[IdentityUpdateSet, seq[ValidationError]]
```

`initIdentityUpdateSet` is an accumulating smart constructor
(`validateUniqueByIt` from `validation.nim`). It rejects:

- empty input — the `/set` builder's "no updates for this id"
  representation is to omit the entry from the outer table, not pass an
  empty set;
- duplicate target property — two updates with the same `kind` would
  produce a JSON patch object with duplicate keys.

All violations surface in a single `Err` pass; each repeated kind is
reported exactly once regardless of occurrence count.

#### NonEmptyIdentityUpdates — whole-container update algebra

```nim
type NonEmptyIdentityUpdates* = distinct Table[Id, IdentityUpdateSet]

func parseNonEmptyIdentityUpdates*(
    items: openArray[(Id, IdentityUpdateSet)]
): Result[NonEmptyIdentityUpdates, seq[ValidationError]]
```

`parseNonEmptyIdentityUpdates` rejects:

- empty input — the `/set` builder's `update:` field has exactly one "no
  updates" representation (omit the parameter via `Opt.none`);
- duplicate `Id` keys — silent last-wins shadowing at `Table`
  construction would swallow caller data, so `openArray` (not `Table`)
  is the input shape and duplicates are detected before construction.

### 4.5. Serde — serde_identity.nim and serde_identity_update.nim

**Module:** `src/jmap_client/mail/serde_identity.nim`

Imports `serde_addresses` for `EmailAddress` serde. `fromJson` returns
`Result[T, SerdeViolation]`.

**`Identity.fromJson`**
- Validates JObject.
- Extracts `id` via `fieldJString` + `Id.fromJson`.
- Extracts `email` as a required JString — no non-empty check on receive
  (Cyrus accommodation; see §4.1).
- Extracts `name`, `textSignature`, `htmlSignature` via the local helper
  `parseDefaultingString`: absent or null → `""`; present non-string →
  `svkWrongKind`.
- Extracts `replyTo`, `bcc` via the local helper `parseOptEmailAddresses`:
  absent or null → `Opt.none`; JArray → `Opt.some` with each element
  parsed by `EmailAddress.fromJson`; other kinds → `svkWrongKind`.
- Extracts `mayDelete` as a required JBool.
- Constructs `Identity` directly.

**`Identity.toJson`**
- Emits all eight fields. `replyTo`/`bcc` emit as JSON `null` (for
  `Opt.none`) or array. `name`/`textSignature`/`htmlSignature` emit as
  string (even when `""`).

**`IdentityCreate.toJson`**
- Emits all six fields including defaults (`""` for the strings,
  `null` for `replyTo`/`bcc` when `Opt.none`). No `id` or `mayDelete`
  fields.
- All fields always present — explicit is safer than relying on server
  defaults.

```json
{
  "email": "joe@example.com",
  "name": "Joe",
  "replyTo": null,
  "bcc": null,
  "textSignature": "",
  "htmlSignature": ""
}
```

There is no `IdentityCreate.fromJson` — creation types flow client→server,
and the server never sends them back.

**`IdentityCreatedItem.fromJson`**
- Validates JObject.
- Extracts required `id`.
- Extracts optional `mayDelete` — absent or null → `Opt.none(bool)`;
  JBool → `Opt.some`. Stalwart's elision is round-tripped symmetrically
  by `IdentityCreatedItem.toJson` (emit `mayDelete` only when
  `Opt.some`).

**Module:** `src/jmap_client/mail/serde_identity_update.nim`

Send-side only. `IdentityUpdate` patches flatten to RFC 8620 §5.3 wire
patches; the property names match Identity field names verbatim. There
is no `fromJson` — the server never echoes update objects.

```nim
func toJson*(u: IdentityUpdate): (string, JsonNode)
func toJson*(us: IdentityUpdateSet): JsonNode
func toJson*(upd: NonEmptyIdentityUpdates): JsonNode
```

`IdentityUpdate.toJson` returns one `(wireKey, wireValue)` pair per
variant — e.g. `iuSetReplyTo` → `("replyTo", emitOptEmailAddresses(...))`
where `emitOptEmailAddresses` projects `Opt.none` to JSON `null` (the
"clear the default list" signal) and `Opt.some` to a JSON array.
`IdentityUpdateSet.toJson` aggregates the pairs into one patch object
(no shadowing risk because `initIdentityUpdateSet` already rejected
duplicates). `NonEmptyIdentityUpdates.toJson` flattens to the wire
`update:` value `{identityId: patchObj, ...}`.

### 4.6. Entity Registration and Builders

**Module:** `src/jmap_client/mail/mail_entities.nim`

Identity supports `/get` (§6.1), `/changes` (§6.2), `/set` (§6.3). It has
no `/query`, `/queryChanges`, or `/copy` — the corresponding per-verb
resolvers are deliberately absent.

```nim
func methodEntity*(T: typedesc[Identity]): MethodEntity = meIdentity
func getMethodName*(T: typedesc[Identity]): MethodName = mnIdentityGet
func changesMethodName*(T: typedesc[Identity]): MethodName = mnIdentityChanges
func setMethodName*(T: typedesc[Identity]): MethodName = mnIdentitySet
func capabilityUri*(T: typedesc[Identity]): string = "urn:ietf:params:jmap:submission"

template changesResponseType*(T: typedesc[Identity]): typedesc =
  ChangesResponse[Identity]
template createType*(T: typedesc[Identity]): typedesc       = IdentityCreate
template updateType*(T: typedesc[Identity]): typedesc       = NonEmptyIdentityUpdates
template setResponseType*(T: typedesc[Identity]): typedesc  =
  SetResponse[IdentityCreatedItem]

registerJmapEntity(Identity)
registerSettableEntity(Identity)
```

`registerSettableEntity` emits static checks that `setMethodName`,
`createType`, `updateType`, and `setResponseType` exist for `Identity`;
missing overloads produce domain-specific compile errors.

**Module:** `src/jmap_client/mail/identity_builders.nim`

Thin wrappers over the generic builders, so consumers can call
`addIdentityGet(...)` instead of `addGet[Identity](...)`. Builders return
`(RequestBuilder, ResponseHandle[T])` tuples — the builder is
functional, not a `var` parameter.

```nim
func addIdentityGet*(
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[Identity]])

func addIdentityChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[ChangesResponse[Identity]])

func addIdentitySet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, IdentityCreate]] =
      Opt.none(Table[CreationId, IdentityCreate]),
    update: Opt[NonEmptyIdentityUpdates] = Opt.none(NonEmptyIdentityUpdates),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): (RequestBuilder, ResponseHandle[SetResponse[IdentityCreatedItem]])
```

The module re-exports `serde_identity` and `serde_identity_update` so
that consumers who import `identity_builders` get the relevant
`toJson` overloads in scope automatically (`mixin`-resolved at the
generic builder's instantiation site).

`createResults` is keyed by `CreationId` and carries
`IdentityCreatedItem` (`id` plus the optional server-set `mayDelete`),
not full `Identity` records — the wire payload is the server-set subset
per RFC 8620 §5.3. Destroying an Identity whose `mayDelete` is false
surfaces as a per-id `SetError` inside `destroyResults`; no client-side
pre-check.

---

## 5. VacationResponse — vacation.nim

**RFC reference:** §8.

A VacationResponse represents vacation auto-reply settings for an account.
Singleton pattern — exactly one per account, id always `"singleton"`. Only
`/get` and `/set` (update-only) are supported. No `/changes`, no `/query`.

**Module:** `src/jmap_client/mail/vacation.nim`

### 5.1. Type Definition

The Nim type has **no `id` field** — the `"singleton"` id has zero
degrees of freedom and carries no information. Omitting it eliminates the
illegal state "VacationResponse with a wrong id" by construction.

```nim
const VacationResponseSingletonId* = "singleton"
  ## The fixed identifier for the sole VacationResponse object (RFC 8621 §7).
  ## Imported by serde (validation on deserialise, emission on serialise)
  ## and by the /set builder (hardcoded in the update map).

type VacationResponse* {.ruleOff: "objects".} = object
  isEnabled*: bool          ## Whether the vacation response is active.
  fromDate*: Opt[UTCDate]   ## Start of the vacation window, or none.
  toDate*: Opt[UTCDate]     ## End of the vacation window, or none.
  subject*: Opt[string]     ## Subject line for the auto-reply, or none.
  textBody*: Opt[string]    ## Plain-text body, or none.
  htmlBody*: Opt[string]    ## HTML body, or none.
```

No smart constructor — all invariants are captured by field types. The
`fromDate`/`toDate` business rule (if both present, `fromDate` should
precede `toDate`) is the server's responsibility to enforce.

**No creation or destruction** — RFC 8621 §8 forbids both. The singleton
always exists. Updates use the typed update algebra (§5.2) via
`addVacationResponseSet` (§5.3).

### 5.2. VacationResponse Update Algebra

Six settable properties, one variant each. Same shape as `IdentityUpdate`
and `MailboxUpdate` — case object enforces "exactly one target per
update" at the type level.

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
```

`Opt.none` on `fromDate` / `toDate` / `subject` / `textBody` / `htmlBody`
clears that property per RFC 8621 §8.

**Builder helpers** (one per variant) construct the case object with the
correct literal discriminator:

```nim
func setIsEnabled*(isEnabled: bool): VacationResponseUpdate
func setFromDate*(fromDate: Opt[UTCDate]): VacationResponseUpdate
func setToDate*(toDate: Opt[UTCDate]): VacationResponseUpdate
func setSubject*(subject: Opt[string]): VacationResponseUpdate
func setTextBody*(textBody: Opt[string]): VacationResponseUpdate
func setHtmlBody*(htmlBody: Opt[string]): VacationResponseUpdate
```

**Validated batch:**

```nim
type VacationResponseUpdateSet* = distinct seq[VacationResponseUpdate]

func initVacationResponseUpdateSet*(
    updates: openArray[VacationResponseUpdate]
): Result[VacationResponseUpdateSet, seq[ValidationError]]
```

`initVacationResponseUpdateSet` rejects empty input and duplicate target
properties (`validateUniqueByIt` over `kind`). Because VacationResponse
is a singleton, there is no whole-container `NonEmptyXxxUpdates` shape —
the `/set` builder takes a single `VacationResponseUpdateSet` directly.

### 5.3. Serde — serde_vacation.nim

**Module:** `src/jmap_client/mail/serde_vacation.nim`

**Wire format:**

```json
{
  "id": "singleton",
  "isEnabled": true,
  "fromDate": "2024-12-01T00:00:00Z",
  "toDate": "2025-01-15T00:00:00Z",
  "subject": "Out of office",
  "textBody": "I am on vacation.",
  "htmlBody": null
}
```

**`VacationResponse.fromJson`**
- Validates JObject.
- Extracts required `id` as JString and verifies
  `id == VacationResponseSingletonId`. Mismatch → `svkEnumNotRecognised`
  with `enumTypeLabel = "VacationResponse id"`. The validated id is
  discarded after verification — it has served its purpose at the parsing
  boundary.
- Extracts required `isEnabled` as JBool.
- Extracts optional `fromDate`/`toDate` via the local helper
  `parseOptUtcDate` (absent or null → `Opt.none`; JString →
  `UTCDate.fromJson`).
- Extracts optional `subject`/`textBody`/`htmlBody` via the local helper
  `parseOptString` (absent, null, or non-string → `Opt.none`).
- Constructs `VacationResponse` directly.

**`VacationResponse.toJson`**
- Emits `"id": VacationResponseSingletonId` (the protocol requires it,
  the type does not carry it).
- Emits `isEnabled` as bool.
- Emits the four `Opt[...]` fields via the `emitOptUtcDate`/
  `emitOptString` helpers — `Opt.none` projects to JSON `null`,
  `Opt.some` to the value.

**`VacationResponseUpdate.toJson`** returns one `(wireKey, wireValue)`
pair per variant. `vruSetFromDate` / `vruSetToDate` use the shared
`optToJsonOrNull` helper from core serde (`Opt.none` → JSON `null`); the
three string-bodied variants use `optStringToJsonOrNull`.

**`VacationResponseUpdateSet.toJson`** aggregates the pairs into one
patch object — `initVacationResponseUpdateSet` already rejected
duplicates, so blind aggregation cannot shadow.

### 5.4. Builder Functions

**No entity registration.** VacationResponse is NOT registered with
`registerJmapEntity`. It has only two valid methods (`/get` always
fetching the singleton with no `ids`; `/set` update-only with no
create/destroy), neither of which fits the generic builder shape.
Custom builder functions make invalid method calls uncompilable.

**Module:** `src/jmap_client/mail/mail_methods.nim`

```nim
func addVacationResponseGet*(
    b: RequestBuilder,
    accountId: AccountId,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[VacationResponse]])
```

- Adds `"urn:ietf:params:jmap:vacationresponse"` capability to the
  request.
- Emits invocation name `mnVacationResponseGet` (`"VacationResponse/get"`).
- Always fetches the singleton — no `ids` parameter in the function
  signature because the only valid id is `"singleton"`, and omitting
  `ids` achieves the same result.
- Internally constructs `GetRequest[VacationResponse]` with
  `ids = Opt.none` and the optional `properties`.

```nim
func addVacationResponseSet*(
    b: RequestBuilder,
    accountId: AccountId,
    update: VacationResponseUpdateSet,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[SetResponse[VacationResponse]])
```

- Adds `"urn:ietf:params:jmap:vacationresponse"` capability.
- Emits invocation name `mnVacationResponseSet` (`"VacationResponse/set"`).
- Builds the update map as
  `{VacationResponseSingletonId: update.toJson()}` — the singleton id is
  referenced from the domain constant, not caller-specified.
- Takes a single `VacationResponseUpdateSet` directly, not a
  `Table[Id, VacationResponseUpdateSet]` — eliminates the possibility of
  a wrong id at the type level.
- No `create` or `destroy` parameters — RFC 8621 §8 forbids them; the
  signature simply omits them.

**Response dispatch:** Uses standard `GetResponse[VacationResponse]` and
`SetResponse[VacationResponse]` response types. No core modifications
needed.

---

## 6. Capability Types — mail_capabilities.nim

**Module:** `src/jmap_client/mail/mail_capabilities.nim` (Layer 1 types),
`src/jmap_client/mail/serde_mail_capabilities.nim` (Layer 2 parsing).

The two RFC 8621 capabilities with payload — `urn:ietf:params:jmap:mail`
and `urn:ietf:params:jmap:submission` — are defined in full. The parsing
functions take a core `ServerCapability` (whose `rawData` carries the
JSON payload) and produce typed values. After a single
`parseMailCapabilities` / `parseSubmissionCapabilities` call
post-session-fetch, all capability data is typed and validated.

Defining complete types upfront (rather than deferring fields to later
design docs) is driven by:

- **Parse, don't validate** — the parse function transforms raw JSON
  into a fully-typed value. Partial parsing leaves unparsed JSON leaking
  into the domain model.
- **DRY** — Nim object types cannot be extended after definition; one
  pass is enough.
- **Total functions** — partial types silently discard fields.

### 6.1. MailCapabilities

**RFC reference:** §1.3.1.

```nim
type MailCapabilities* {.ruleOff: "objects".} = object
  maxMailboxesPerEmail*: Opt[UnsignedInt]   ## Null = no limit; >= 1 when present.
  maxMailboxDepth*: Opt[UnsignedInt]        ## Null = no limit.
  maxSizeMailboxName*: Opt[UnsignedInt]
    ## Octets; >= 100 when present per RFC 8621 §1.3.1. Optional —
    ## informational hint, not MUST. Cyrus 3.12.2 omits this field;
    ## the Postel-receive parser surfaces absence as Opt.none rather
    ## than synthesising a default.
  maxSizeAttachmentsPerEmail*: UnsignedInt  ## Octets.
  emailQuerySortOptions*: HashSet[string]   ## Supported sort properties.
  mayCreateTopLevelMailbox*: bool
```

Plain public fields. Validation happens in `parseMailCapabilities`.

**Field notes:**

| Field | RFC Constraint | Validation | Consumed By |
|-------|----------------|------------|-------------|
| `maxMailboxesPerEmail` | `>= 1` when present, null = no limit | Serde validates `>= 1` | Mailbox set validation |
| `maxMailboxDepth` | null = no limit | None beyond `UnsignedInt` | Mailbox set validation |
| `maxSizeMailboxName` | `>= 100` when present (informational) | Serde validates `>= 100` when present | Mailbox name validation |
| `maxSizeAttachmentsPerEmail` | none specified | None beyond `UnsignedInt` | Email creation |
| `emailQuerySortOptions` | server-advertised sort properties | None | Consumer reference |
| `mayCreateTopLevelMailbox` | boolean | None | Mailbox set validation |

**`maxSizeMailboxName: Opt[UnsignedInt]`** — RFC 8621 §1.3.1 lists the
field as informational rather than MUST. Cyrus 3.12.2 omits it. The
Postel-receive parser surfaces absence as `Opt.none` rather than
synthesising a default; the `>= 100` invariant only applies when the
field is present.

**`emailQuerySortOptions: HashSet[string]`** — The primary domain
operation is membership testing ("does the server support sorting by
`receivedAt`?"), which `HashSet` serves in O(1). The values are opaque
server-advertised strings that may include vendor extensions. When the
canonical field is absent (Cyrus 3.12.2 emits a divergent label
`emailsListSortOptions`, accepted as absence), the parser surfaces an
empty `HashSet[string]`. Mirrors the `collationAlgorithms: HashSet[string]`
precedent in `CoreCapabilities`.

### 6.2. SubmissionCapabilities and SubmissionExtensionMap

**RFC reference:** §1.3.2.

```nim
type SubmissionExtensionMap* =
  distinct OrderedTable[RFC5321Keyword, seq[string]]
  ## RFC 5321 §2.2.1 EHLO-name → args map for the
  ## urn:ietf:params:jmap:submission capability's submissionExtensions
  ## field (RFC 8621 §1.3.2). Keys are validated ESMTP keywords with
  ## case-insensitive equality and hash; the underlying OrderedTable
  ## therefore gives structural uniqueness and wire-order fidelity
  ## automatically.

func `==`*(a, b: SubmissionExtensionMap): bool {.borrow.}
func `$`*(a: SubmissionExtensionMap): string {.borrow.}

type SubmissionCapabilities* {.ruleOff: "objects".} = object
  maxDelayedSend*: UnsignedInt          ## Seconds; 0 = not supported.
  submissionExtensions*: SubmissionExtensionMap
```

**`RFC5321Keyword`** (defined in `submission_atoms.nim`) is a `distinct
string` validated to RFC 5321 §4.1.1.1 grammar — `(ALPHA / DIGIT)
*(ALPHA / DIGIT / "-")` bounded to 1..64 octets. Its `==` and `hash` are
ASCII case-insensitive (RFC 5321 §2.4); `$` preserves the original
casing for diagnostic round-trip. Wrapping the keys in this validated
type means duplicate-or-conflicting EHLO names (`PIPELINING` vs
`pipelining`) collapse to a single entry by the table's natural
uniqueness, with no parallel normalisation pass.

**`OrderedTable`** preserves insertion order from the server response
JSON, consistent with JSON round-trip fidelity (both `std/tables` and
`std/json` use `OrderedTable` for objects).

### 6.3. VacationResponse Capability

**RFC reference:** §1.3.3.

The `urn:ietf:params:jmap:vacationresponse` capability has an empty
object as its value in both session and account capabilities. **No type
is defined** — the consumer may verify the capability exists on the
session before calling `addVacationResponseGet` /
`addVacationResponseSet`, but no typed parsing step is required, and
the builders add the URI to the request `using` array unconditionally.

### 6.4. Serde — serde_mail_capabilities.nim

**Module:** `src/jmap_client/mail/serde_mail_capabilities.nim`

Both functions return `Result[T, SerdeViolation]`.

```nim
func parseMailCapabilities*(
    cap: ServerCapability, path: JsonPath = emptyJsonPath()
): Result[MailCapabilities, SerdeViolation]
```

- Validates `cap.kind == ckMail`. Other kinds → `svkEnumNotRecognised`
  with `enumTypeLabel = "capability kind"`. Under `strictCaseObjects`,
  `rawData` (declared in the `else:` branch of `ServerCapability`) is
  only accessible when the use-site case also goes through `else:` — so
  the function dispatches `of ckCore: <error>; else: <if kind != ckMail
  then error else parse>`.
- Validates `rawData` is JObject.
- `maxMailboxesPerEmail`: JNull or absent → `Opt.none`; JInt parsed as
  `UnsignedInt`, then validates `>= 1` (`svkEmptyRequired` with label
  `"maxMailboxesPerEmail (must be >= 1)"`).
- `maxMailboxDepth`: JNull or absent → `Opt.none`; JInt parsed as
  `UnsignedInt`.
- `maxSizeMailboxName`: JNull or absent → `Opt.none`; JInt parsed as
  `UnsignedInt`, then validates `>= 100`.
- `maxSizeAttachmentsPerEmail`: required JInt parsed as `UnsignedInt`.
- `emailQuerySortOptions`: optional JArray of JString (Cyrus emits a
  divergent label that surfaces as absence here); collected into
  `HashSet[string]`. Absent or null → empty set.
- `mayCreateTopLevelMailbox`: required JBool.

```nim
func parseSubmissionCapabilities*(
    cap: ServerCapability, path: JsonPath = emptyJsonPath()
): Result[SubmissionCapabilities, SerdeViolation]
```

- Validates `cap.kind == ckSubmission` (same `else:`-branch dispatch
  pattern as `parseMailCapabilities`).
- Validates `rawData` is JObject.
- `maxDelayedSend`: required JInt parsed as `UnsignedInt` (0 is valid —
  the RFC's "not supported" sentinel).
- `submissionExtensions`: required JObject. Iterates key/value pairs in
  order; each key parsed via `parseRFC5321Keyword` (bridged through
  `wrapInner`); each value validated as JArray of JString and collected
  into `seq[string]`. Builds an `OrderedTable[RFC5321Keyword, seq[string]]`,
  then wraps it in `SubmissionExtensionMap`.

**Strictness rationale:** Structural invalidity (wrong JSON kind, missing
MUST fields) always rejects. RFC MUST constraints (`>= 1`, `>= 100`)
reject because the constraint is a domain invariant —
`maxMailboxesPerEmail = 0` has no valid domain interpretation. Unknown
or extra fields are preserved through `ServerCapability.rawData` for
forward compatibility; the consumer's recourse for a non-conformant
server is to fall back to `rawData` parsing.

---

## 7. Mail Set Error Accessors — mail_errors.nim

**Module:** `src/jmap_client/mail/mail_errors.nim`

**RFC reference:** §§2.3, 4.6, 6.3, 7.5.

The full RFC 8621 SetError vocabulary lives on the **central
`SetErrorType` enum** in `src/jmap_client/errors.nim`, alongside the RFC
8620 §5.3 / §5.4 core variants:

```nim
# RFC 8620 §5.3 / §5.4 — core
setForbidden, setOverQuota, setTooLarge, setRateLimit, setNotFound,
setInvalidPatch, setWillDestroy, setInvalidProperties, setAlreadyExists,
setSingleton,
# RFC 8621 §2.3 — Mailbox/set
setMailboxHasChild, setMailboxHasEmail,
# RFC 8621 §4.6 — Email/set
setBlobNotFound, setTooManyKeywords, setTooManyMailboxes,
# RFC 8621 §7.5 — EmailSubmission/set (and §6 Identity/set)
setInvalidEmail, setTooManyRecipients, setNoRecipients,
setInvalidRecipients, setForbiddenMailFrom, setForbiddenFrom,
setForbiddenToSend, setCannotUnsend,
setUnknown
```

The wire string `"forbiddenFrom"` is shared between Identity/set (§6)
and EmailSubmission/set (§7.5); a single enum variant `setForbiddenFrom`
covers both contexts — the calling method determines which
SHOULD-semantic applies.

`SetError` is a case object with public discriminator `errorType*:
SetErrorType`. Seven variants carry typed payload fields:

| `errorType` | Payload field | RFC | Field type |
|-------------|---------------|-----|------------|
| `setInvalidProperties` | `properties` | RFC 8620 §5.3 | `seq[string]` |
| `setAlreadyExists` | `existingId` | RFC 8620 §5.4 | `Id` |
| `setBlobNotFound` | `notFound` | RFC 8621 §4.6 | `seq[BlobId]` |
| `setInvalidEmail` | `invalidEmailPropertyNames` | RFC 8621 §7.5 | `seq[string]` |
| `setTooManyRecipients` | `maxRecipientCount` | RFC 8621 §7.5 | `UnsignedInt` |
| `setInvalidRecipients` | `invalidRecipients` | RFC 8621 §7.5 | `seq[string]` |
| `setTooLarge` | `maxSizeOctets` | RFC 8621 §7.5 SHOULD | `Opt[UnsignedInt]` |

All other variants share a payload-less `else: discard` arm.

### 7.1. Mail-specific Accessors

`mail_errors.nim` provides five typed accessor functions over `SetError`.
Each is a one-line case-branch read off the central ADT — no JSON walk
through `extras`.

```nim
func notFoundBlobIds*(se: SetError): Opt[seq[BlobId]]
func maxSize*(se: SetError): Opt[UnsignedInt]
func maxRecipients*(se: SetError): Opt[UnsignedInt]
func invalidRecipientAddresses*(se: SetError): Opt[seq[string]]
func invalidEmailProperties*(se: SetError): Opt[seq[string]]
```

| Accessor | Returns `Opt.some` for | RFC requirement |
|----------|------------------------|-----------------|
| `notFoundBlobIds` | `setBlobNotFound` | MUST (§4.6) |
| `maxSize` | `setTooLarge` (when `maxSizeOctets` is `Opt.some`) | SHOULD (§7.5) |
| `maxRecipients` | `setTooManyRecipients` | MUST (§7.5) |
| `invalidRecipientAddresses` | `setInvalidRecipients` | MUST (§7.5) |
| `invalidEmailProperties` | `setInvalidEmail` | SHOULD (§7.5) |

All other `errorType` variants return `Opt.none`. The accessors live in
the mail layer so that mail-specific predicate vocabulary stays next to
the mail domain even though the underlying ADT is in core.

**Field-name disambiguation.** The `SetError` payload field names
deliberately differ from the mail-layer accessor names (e.g.
`maxSizeOctets` vs `maxSize`, `maxRecipientCount` vs `maxRecipients`,
`invalidEmailPropertyNames` vs `invalidEmailProperties`) so that a `case
se.errorType of setTooLarge: se.maxSizeOctets` in core code does not
shadow `mail_errors.maxSize(se)` at the call site.

### 7.2. Consumer Dispatch

The full SetError vocabulary is one closed enum, so consumer dispatch is
a single exhaustive `case`:

```nim
case se.errorType
of setBlobNotFound:
  for ids in se.notFoundBlobIds():
    # handle unresolved blobs
of setTooManyRecipients:
  let cap = se.maxRecipientCount   # direct field access
of setForbiddenFrom:
  # handle forbidden sender (Identity/set or EmailSubmission/set)
of setUnknown:
  # forward-compatible catch-all — log se.rawType
else:
  discard
```

Adding a variant to `SetErrorType` forces a compile error at every
non-`else` case site — the design's safety guarantee.

---

## 8. Test Specification

Scenario numbers track the labels embedded in the source test files
(`# scenario N` markers). Numbered tables list the cases each test
file pins; the trailing prose subsections cover material whose tests
do not carry explicit scenario markers (update algebras,
`IdentityCreatedItem`, builder wire anchors).

### 8.1. EmailAddress (`taddresses.nim` + `tserde_addresses.nim`)

| # | Scenario | Expected |
|---|----------|----------|
| 1 | `parseEmailAddress("joe@example.com")` | `ok`, name = `Opt.none` |
| 2 | `parseEmailAddress("joe@example.com", some("Joe"))` | `ok`, name = `Opt.some("Joe")` |
| 3 | `parseEmailAddress("")` | `err(ValidationError)` |
| 4 | `toJson` with name | `{"name": "Joe", "email": "..."}` |
| 5 | `toJson` without name | `{"name": null, "email": "..."}` |
| 6 | `fromJson` valid with name | `ok(EmailAddress)` |
| 7 | `fromJson` missing `email` | `err(SerdeViolation, svkMissingField)` |
| 8 | `fromJson` null `email` | `err(SerdeViolation, svkWrongKind)` |

### 8.2. EmailAddressGroup (`taddresses.nim` + `tserde_addresses.nim`)

| # | Scenario | Expected |
|---|----------|----------|
| 9 | Construction with name and addresses | valid |
| 10 | Construction with null name | valid |
| 11 | Construction with empty addresses | valid |
| 12 | `toJson` / `fromJson` round-trip | identity |

### 8.3. Thread (`tthread.nim` + `tserde_thread.nim`)

| # | Scenario | Expected |
|---|----------|----------|
| 13 | `parseThread(id, @[emailId])` — single email | `ok`, `emailIds.len == 1` |
| 14 | `parseThread(id, @[e1, e2, e3])` — multiple emails | `ok`, `emailIds.len == 3` |
| 15 | `parseThread(id, @[])` — empty | `err(ValidationError)` |
| 16 | `id` accessor returns the constructed `Id` | pass |
| 17 | `emailIds` accessor returns the constructed `seq` | pass |
| 18 | `toJson` produces `{"id": "...", "emailIds": ["..."]}` | structural match |
| 19 | `fromJson` valid single email | `ok` |
| 20 | `fromJson` valid multiple emails | `ok`, order preserved |
| 21 | `fromJson` empty `emailIds` array | `err(SerdeViolation, svkFieldParserFailed)` |
| 22 | External code naming `rawId` / `rawEmailIds` in a constructor literal | compile error (sealed fields) |
| 23 | External code reading `t.rawId` / `t.rawEmailIds` directly | compile error (sealed fields) |

### 8.4. Identity (`tserde_identity.nim`)

| # | Scenario | Expected |
|---|----------|----------|
| 24 | `fromJson` all fields present | `ok`, all fields populated |
| 25 | `fromJson` optional fields absent, defaults applied | `ok` |
| 26 | `fromJson` `name` absent → `""` | pass |
| 27 | `fromJson` `textSignature` absent → `""` | pass |
| 28 | `fromJson` `htmlSignature` absent → `""` | pass |
| 29 | `fromJson` `replyTo` null → `Opt.none` | pass |
| 30 | `fromJson` `replyTo` with addresses → `Opt.some(seq)` | pass |
| 31 | `toJson` / `fromJson` round-trip | identity |
| 32 | `fromJson` `email` empty (Cyrus accommodation) | `ok` (lenient receive) |

### 8.5. IdentityCreate (`tidentity.nim` + `tserde_identity.nim`)

| # | Scenario | Expected |
|---|----------|----------|
| 33 | `parseIdentityCreate("joe@example.com", ...)` all fields | `ok` |
| 34 | `parseIdentityCreate("joe@example.com")` defaults only | `ok`, name = `""`, sigs = `""` |
| 35 | `parseIdentityCreate("")` | `err(ValidationError)` |
| 36 | `toJson` includes all 6 fields | structural match |
| 37 | `toJson` does not emit `id` or `mayDelete` | verified absent |

### 8.6. VacationResponse (`tserde_vacation.nim`)

| # | Scenario | Expected |
|---|----------|----------|
| 38 | `fromJson` valid, id = `"singleton"`, all fields | `ok` |
| 39 | `fromJson` optional fields null | `ok`, `Opt.none` for each |
| 40 | `fromJson` id = `"wrong"` | `err(SerdeViolation, svkEnumNotRecognised)` |
| 41 | `fromJson` id absent | `err(SerdeViolation, svkMissingField)` |
| 42 | `toJson` emits `"id": "singleton"` | structural match |
| 43 | `toJson` / `fromJson` round-trip | identity |
| 44 | No `id` field on `VacationResponse` type | compile-time: `vr.id` does not compile |

### 8.7. MailCapabilities (`tserde_mail_capabilities.nim`)

| # | Scenario | Expected |
|---|----------|----------|
| 45 | `parseMailCapabilities` valid, all fields present | `ok` |
| 46 | `parseMailCapabilities` wrong capability kind | `err(SerdeViolation, svkEnumNotRecognised)` |
| 47 | `maxMailboxesPerEmail = 1` (boundary) | `ok` |
| 48 | `maxMailboxesPerEmail = 0` | `err(SerdeViolation, svkEmptyRequired)` |
| 49 | `maxMailboxesPerEmail` null → `Opt.none` | `ok` |
| 50 | `maxSizeMailboxName = 99` | `err(SerdeViolation, svkEmptyRequired)` |
| 51 | `maxSizeMailboxName = 100` (boundary) | `ok` |

Edge-case blocks beyond scenarios 45–51 cover Cyrus accommodations
(`maxSizeMailboxName` absent → `Opt.none`; absent
`emailQuerySortOptions` → empty `HashSet`), `maxMailboxDepth = null`,
non-object `rawData`, the `ckCore` rejection arm, and explicit
`maxMailboxesPerEmail` / `maxMailboxDepth` absent paths.

### 8.8. SubmissionCapabilities (`tserde_mail_capabilities.nim`)

| # | Scenario | Expected |
|---|----------|----------|
| 52 | `parseSubmissionCapabilities` valid | `ok` |
| 53 | `parseSubmissionCapabilities` wrong kind | `err(SerdeViolation, svkEnumNotRecognised)` |
| 54 | `maxDelayedSend = 0` (RFC sentinel for "not supported") | `ok` |
| 55 | `submissionExtensions` with multiple EHLO entries, mixed casing | `ok`, parsed; case-insensitive equality |

Edge-case blocks beyond scenarios 52–55 cover non-array values,
invalid RFC 5321 keywords (`svkFieldParserFailed`), empty keywords,
case-insensitive collapse of `PIPELINING` vs `pipelining`, and
`OrderedTable` insertion-order preservation.

### 8.9. Mail SetError parsing and accessors (`tmail_errors.nim`)

| # | Scenario | Expected |
|---|----------|----------|
| 56 | `parseSetErrorType` exhaustive table over the thirteen RFC 8621 wire strings | each maps to its expected `SetErrorType` variant |
| 57 | `parseSetErrorType("someVendorError")` / `parseSetErrorType("")` | `setUnknown` |
| 58 | `parseSetErrorType` Nim ident-normalisation behaviour | `"mailboxHas_Child"` → `setMailboxHasChild`; `"MailboxHasChild"` → `setUnknown` |
| 60 | `maxRecipients` on `setTooManyRecipients` | `Opt.some(UnsignedInt)` |
| 61 | `maxRecipients` when payload absent (defensive `setUnknown`) | `Opt.none` |
| 62 | `invalidRecipientAddresses` on `setInvalidRecipients` | `Opt.some(seq[string])` |
| 63 | `invalidRecipientAddresses` on malformed payload (defensive `setUnknown`) | `Opt.none` |
| 64 | `notFoundBlobIds` on `setBlobNotFound` | `Opt.some(seq[BlobId])` |
| 65 | `notFoundBlobIds` on malformed payload | `Opt.none` |
| 66 | `maxSize` on `setTooLarge` with `maxSizeOctets = Opt.some(...)` | `Opt.some(UnsignedInt)` |
| 67 | `maxSize` on `setTooLarge` with `maxSizeOctets = Opt.none` | `Opt.none` |
| 68 | `invalidEmailProperties` on `setInvalidEmail` | `Opt.some(seq[string])` |
| 69 | `invalidEmailProperties` on malformed payload | `Opt.none` |

Scenario 59 is reserved across the wider design suite (filter/header
tests) and is intentionally absent from `tmail_errors.nim`. Edge-case
blocks also assert that every accessor returns `Opt.none` on
unrelated `errorType` variants, and that `setErrorInvalidEmail` with
an empty array round-trips as `Opt.some(@[])`.

### 8.10. IdentityCreatedItem (`tserde_identity.nim` + captured fixtures)

Scenarios are not numbered in source. Verified:

- `fromJson` of `{"id": "..."}` (Stalwart 0.15.5 elision) → `ok`,
  `mayDelete = Opt.none(bool)`.
- `fromJson` of `{"id": "...", "mayDelete": false}` → `ok`,
  `mayDelete = Opt.some(false)`.
- `toJson` round-trips Stalwart's elision symmetrically — the wire
  output contains `"id"` only and omits the `"mayDelete"` key when
  `mayDelete.isNone`.
- Captured cross-server fixtures
  (`tcaptured_identity_set_update_stalwart.nim`,
  `tcaptured_identity_changes_with_updates.nim`) decode the create
  payload through `IdentityCreatedItem` end-to-end.

### 8.11. Identity Update Algebra (`tidentity_update.nim`)

Scenarios are not numbered in source. Verified:

- Each builder helper (`setName`, `setReplyTo`, `setBcc`,
  `setTextSignature`, `setHtmlSignature`) constructs an
  `IdentityUpdate` whose `kind` matches the builder name.
- `setReplyTo(Opt.none(seq[EmailAddress]))` produces an
  `iuSetReplyTo` carrying the cleared list.
- `initIdentityUpdateSet(@[])` errs with `"must contain at least one
  update"`.
- `initIdentityUpdateSet` over duplicate-kind input errs once per
  distinct repeated kind, regardless of occurrence count (e.g. three
  copies of `setName(...)` → exactly one `"duplicate target
  property"` error naming `iuSetName`).
- `initIdentityUpdateSet` accepts mixed-kind batches.
- `parseNonEmptyIdentityUpdates(@[])` errs with the empty-input
  message.
- `parseNonEmptyIdentityUpdates` over duplicate `Id` keys errs once
  per distinct repeated id (`"duplicate identity id"`).
- `IdentityUpdate.toJson` for `iuSetReplyTo(Opt.none)` →
  `("replyTo", null)`.
- `IdentityUpdateSet.toJson` aggregates each `(key, value)` pair into
  one patch object.
- `NonEmptyIdentityUpdates.toJson` flattens to the wire shape
  `{identityId: patchObj, ...}`.

### 8.12. VacationResponse Update Algebra (`tvacation.nim` + `tserde_vacation.nim`)

Scenarios are not numbered in source. Verified:

- Each builder helper (`setIsEnabled`, `setFromDate`, `setToDate`,
  `setSubject`, `setTextBody`, `setHtmlBody`) constructs a
  `VacationResponseUpdate` whose `kind` matches the builder name.
- `Opt.none` arguments to `setSubject` / `setTextBody` /
  `setHtmlBody` / `setFromDate` / `setToDate` produce variants with
  cleared payloads.
- `initVacationResponseUpdateSet(@[])` errs with `"must contain at
  least one update"`.
- `initVacationResponseUpdateSet` rejects duplicate `kind` (single
  error per distinct repeated kind).
- `VacationResponseUpdate.toJson` per variant emits the expected
  `(wireKey, wireValue)` pair, with `Opt.none` projecting to JSON
  `null` for date and string-bodied variants.
- `VacationResponseUpdateSet.toJson` aggregates pairs into a single
  patch object.

### 8.13. Builder wire anchors (`tidentity_builders.nim`, integration tests)

Scenarios are not numbered in source. Verified:

- `addIdentityGet` routes to method name `mnIdentityGet` and adds
  capability `urn:ietf:params:jmap:submission`.
- `addIdentityChanges` routes to `mnIdentityChanges`.
- `addIdentitySet` create-only emits the six-field `IdentityCreate`
  payload at `args.create["<creationId>"]` and routes to
  `mnIdentitySet` with the submission capability; `id` and
  `mayDelete` are absent.
- `addIdentitySet` update-only emits per-id patches keyed by the
  Identity `Id` in `args.update`, with neither `create` nor
  `destroy` keys.
- `addIdentitySet` destroy-only emits `args.destroy` as a JSON array
  of ids.
- `addVacationResponseGet` routes to `mnVacationResponseGet` and
  adds capability `urn:ietf:params:jmap:vacationresponse`.
- `addVacationResponseSet` builds `args.update["singleton"]` from
  the supplied `VacationResponseUpdateSet` and routes to
  `mnVacationResponseSet`. The signature has no `create` / `destroy`
  parameters by construction.
- Compile-time: `setMethodName(typedesc[thread.Thread])` — fails
  with an undeclared-identifier error at the call site.
- Compile-time: `addIdentitySet` `createResults` is typed as
  `SetResponse[IdentityCreatedItem]` (resolved through
  `setResponseType`).

---

## 9. Decision Traceability Matrix

| # | Decision | Chosen | Primary Principles |
|---|----------|--------|--------------------|
| A1 | `EmailAddress` placement | Shared §2 section preceding the entities that consume it | DDD, Parse-don't-validate, DRY |
| A2 | Capability types scope | Complete typed `MailCapabilities` and `SubmissionCapabilities` upfront | Parse-don't-validate, DRY, Total functions |
| A3 | Identity creation model | Lightweight `IdentityCreate` with email-required smart constructor | Make illegal states unrepresentable, DDD |
| A4 | Thread field sealing | Sealed (module-private) fields with `parseThread` smart constructor | Make illegal states unrepresentable |
| A5 | Identity field sealing | Plain public fields (no cross-field invariants) | Consistency with Account/CoreCapabilities |
| A6 | VacationResponse `id` field | Omit — singleton id is a constant, not state | Make illegal states unrepresentable, DDD, DRY |
| A7 | VacationResponse entity registration | Do not register; custom `addVacationResponseGet` / `addVacationResponseSet` builders | Make illegal states unrepresentable, DDD |
| A8 | Mail set-error vocabulary | Single central `SetErrorType` covering RFC 8620 + RFC 8621 variants; mail layer provides typed accessors only | DRY, Total functions, Open-Closed |
| A9 | Identity string field types | `string` with default `""` (RFC types are `String`, not `String\|null`) | Parse-don't-validate, Make illegal states unrepresentable |
| A10 | Thread `emailIds` non-empty | Reject empty at the parsing boundary | Parse-don't-validate, Make illegal states unrepresentable |
| A11 | Serde module split for addresses | Separate `serde_addresses.nim` (shared bounded context) | DDD, DRY |
| A12 | VacationResponse set signature | `update: VacationResponseUpdateSet` (singleton id hardcoded) | Make illegal states unrepresentable |
| A13 | `emailQuerySortOptions` collection type | `HashSet[string]` (O(1) membership; mirrors `collationAlgorithms`) | DDD, DRY |
| A14 | Thread initialisation pragma | Sealed fields without `{.requiresInit.}` (compatible with `seq[Thread]` under `UnsafeSetLen`) | Make illegal states unrepresentable, build correctness |
| A15 | VacationResponse singleton id location | Shared `const VacationResponseSingletonId` in `vacation.nim`, imported by serde and builder | DRY |
| A16 | `submissionExtensions` table type | `distinct OrderedTable[RFC5321Keyword, seq[string]]` | DDD, Make illegal states unrepresentable |
| A17 | RFC 5321 keyword key type | `RFC5321Keyword` with case-insensitive equality and hash | DDD, Total functions |
| A18 | Mail SetError typed access | One-line accessors over the case object's variant fields (no JSON re-parse) | Parse-don't-validate, DDD |
| A19 | Identity `email` lenient on receive | Accept any string from the server (Cyrus compatibility); strictness lives in `parseIdentityCreate` | Postel's law, Parse-don't-validate |
| A20 | `maxSizeMailboxName` cardinality | `Opt[UnsignedInt]` — informational, Cyrus-omitted | Parse-don't-validate, Postel's law |
| A21 | Identity update model | Closed sum-type `IdentityUpdate` + validated `IdentityUpdateSet` + `NonEmptyIdentityUpdates` | Make illegal states unrepresentable, Total functions |
| A22 | VacationResponse update model | Closed sum-type `VacationResponseUpdate` + validated `VacationResponseUpdateSet` | Make illegal states unrepresentable, Total functions |
| A23 | Identity `/set` `created[cid]` payload | Distinct `IdentityCreatedItem` with `Opt[bool] mayDelete` (Stalwart elision) | RFC 8620 §5.3, Postel's law |
| A24 | Builder return shape | `(RequestBuilder, ResponseHandle[T])` tuples (functional) | Immutability by default |
| A25 | Identity entity-specific builders | Thin wrappers `addIdentityGet` / `addIdentityChanges` / `addIdentitySet` over the generic builders | API ergonomics |
| A26 | Serde error rail | `Result[T, SerdeViolation]` at every `fromJson`; bridged from L1 `ValidationError` via `wrapInner` | Errors are part of the API |
