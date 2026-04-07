# RFC 8621 JMAP Mail — Design A: Thread, Identity, VacationResponse

This document is the detailed specification for three RFC 8621 entity types —
Thread, Identity, and VacationResponse — plus their supporting types. It covers
all layers (L1 types, L2 serde, L3 entity registration and builder functions)
for each entity, cutting vertically through the architecture.

Builds on the cross-cutting architecture design (`05-mail-design.md`) and the
existing RFC 8620 infrastructure (`00-architecture.md` through
`04-layer-4-design.md`). Decisions from the cross-cutting doc are referenced by
section number.

---

## Table of Contents

1. [Scope](#1-scope)
2. [Shared Sub-Types — addresses.nim](#2-shared-sub-types--addressesnim)
3. [Thread — thread.nim](#3-thread--threadnim)
4. [Identity — identity.nim](#4-identity--identitynim)
5. [VacationResponse — vacation.nim](#5-vacationresponse--vacationnim)
6. [Capability Types — mail_capabilities.nim](#6-capability-types--mail_capabilitiesnim)
7. [Mail Set Error Types — mail_errors.nim](#7-mail-set-error-types--mail_errorsnim)
8. [Test Specification](#8-test-specification)
9. [Decision Traceability Matrix](#9-decision-traceability-matrix)

---

## 1. Scope

### 1.1. Entities Covered

| Entity           | RFC 8621 Section | Capability URI                           | Complexity |
|------------------|-----------------|------------------------------------------|------------|
| Thread           | §3              | `urn:ietf:params:jmap:mail`              | Simple     |
| Identity         | §6              | `urn:ietf:params:jmap:submission`        | Simple     |
| VacationResponse | §8              | `urn:ietf:params:jmap:vacationresponse`  | Simple     |

### 1.2. Supporting Types Covered

| Type | Module | Rationale |
|------|--------|-----------|
| `EmailAddress`, `EmailAddressGroup` | `addresses.nim` | Shared sub-type required by Identity; used by Email and EmailSubmission in future design docs |
| `MailCapabilities` | `mail_capabilities.nim` | Complete typed parsing of `urn:ietf:params:jmap:mail` capability |
| `SubmissionCapabilities` | `mail_capabilities.nim` | Complete typed parsing of `urn:ietf:params:jmap:submission` capability |
| `MailSetErrorType` | `mail_errors.nim` | Complete enum for RFC 8621 set error classification |

### 1.3. Deferred

Mailbox, Email, SearchSnippet, EmailSubmission, and all their sub-types
(Keyword, HeaderValue, EmailBodyPart, etc.) are deferred to Design B and
Design C documents.

### 1.4. Relationship to Cross-Cutting Design

This document refines `05-mail-design.md` into implementation-ready
specifications.

### 1.5. Module Summary

All modules live under `src/jmap_client/mail/` per cross-cutting doc §3.3.

| Module | Layer | Contents |
|--------|-------|----------|
| `addresses.nim` | L1 | `EmailAddress`, `EmailAddressGroup` |
| `thread.nim` | L1 | `Thread` (sealed, Pattern A) |
| `identity.nim` | L1 | `Identity`, `IdentityCreate` |
| `vacation.nim` | L1 | `VacationResponse` (no id field) |
| `mail_capabilities.nim` | L1 | `MailCapabilities`, `SubmissionCapabilities` |
| `mail_errors.nim` | L1 | `MailSetErrorType`, `parseMailSetErrorType` |
| `serde_addresses.nim` | L2 | `toJson`/`fromJson` for address types |
| `serde_thread.nim` | L2 | `toJson`/`fromJson` for Thread |
| `serde_identity.nim` | L2 | `toJson`/`fromJson` for Identity, IdentityCreate |
| `serde_vacation.nim` | L2 | `toJson`/`fromJson` for VacationResponse |
| `serde_mail_capabilities.nim` | L2 | `parseMailCapabilities`, `parseSubmissionCapabilities` |
| `mail_entities.nim` | L3 | Entity registration for Thread, Identity |
| `mail_methods.nim` | L3 | `addVacationResponseGet`, `addVacationResponseSet` |

---

## 2. Shared Sub-Types — addresses.nim

**Module:** `src/jmap_client/mail/addresses.nim`

`EmailAddress` and `EmailAddressGroup` are shared sub-types used by multiple
entities. They are specified here as a prerequisite section — a shared bounded
context, not subordinated to any single entity.

**Principles:** DDD (addresses are their own bounded context), DRY (one
specification, referenced by three future consumers), Parse-don't-validate
(full parsing boundary defined now, no forward references).

### 2.1. EmailAddress

**RFC reference:** §4.1.2.3.

An `EmailAddress` represents a single email address with an optional display
name. Used by Identity (`replyTo`, `bcc`), Email (convenience header fields),
and EmailSubmission (envelope addresses).

**Type definition:**

```nim
type EmailAddress* = object
  name*: Opt[string]    ## Display name, or none if absent
  email*: string        ## RFC 5322 addr-spec
```

Plain public fields. The `email` non-empty invariant is enforced by the smart
constructor, but `EmailAddress` is a simple value object used extensively —
Pattern A sealing would add accessor ceremony disproportionate to the risk.
Consistent with the simpler value object pattern used throughout the codebase.

**Smart constructor:**

```nim
func parseEmailAddress*(
    email: string,
    name: Opt[string] = Opt.none(string),
): Result[EmailAddress, ValidationError]
```

Validates: `email` non-empty. No format validation beyond non-empty — the
server provides arbitrary addresses, and clients send whatever the server
accepts. The `forbiddenFrom` set error handles invalid addresses at the
protocol level. Post-construction `doAssert` verifies the invariant on the
constructed value (`email.len > 0`), catching logic errors in the
validation code itself. Follows the `parseId`/`parseUnsignedInt` pattern
in `primitives.nim`.

**Principles:**
- **Parse, don't validate** — Smart constructor enforces non-empty email at
  the construction boundary. After construction, all downstream code can rely
  on the invariant.
- **Total functions** — Maps every input to `ok(EmailAddress)` or
  `err(ValidationError)`.

### 2.2. EmailAddressGroup

**RFC reference:** §4.1.2.4.

An `EmailAddressGroup` represents a named group of email addresses, or an
ungrouped list (when `name` is none). Used by Email's `GroupedAddresses`
header parsed form.

**Type definition:**

```nim
type EmailAddressGroup* = object
  name*: Opt[string]            ## Group name, or none if not a group
  addresses*: seq[EmailAddress]  ## Members of the group (may be empty)
```

No smart constructor needed — all invariants are captured by field types.
`addresses` may be empty (a group with no members is valid per RFC).

### 2.3. Serde — serde_addresses.nim

**Module:** `src/jmap_client/mail/serde_addresses.nim`

Follows established core serde patterns (`checkJsonKind`, `optJsonField`,
`parseError`). A dedicated serde module for addresses rather than embedding
in `serde_identity.nim`, since Email and EmailSubmission also need address
serde (cross-cutting doc §3.5: "No serde module imports another serde
module except through re-export hubs").

**EmailAddress serialisation:**

Wire format:

```json
{"name": "Joe Bloggs", "email": "joe@example.com"}
{"name": null, "email": "joe@example.com"}
```

`toJson`:
- Emits `name` as string or `null` (for `Opt.none`).
- Always emits `email`.

`fromJson`:
- Validates JObject.
- Extracts `email` (required string, rejects absent/null/non-string).
- Extracts `name` — absent or null → `Opt.none(string)`, string →
  `Opt.some(value)`.
- Delegates to `parseEmailAddress` for construction (enforces non-empty
  email).
- Returns `Result[EmailAddress, ValidationError]`.

**EmailAddressGroup serialisation:**

Wire format:

```json
{"name": "Engineering", "addresses": [{"name": null, "email": "eng@example.com"}]}
{"name": null, "addresses": []}
```

`toJson`:
- Emits `name` as string or `null`.
- Always emits `addresses` array.

`fromJson`:
- Validates JObject.
- Extracts `name` (same null handling as EmailAddress).
- Extracts `addresses` as JArray, parses each element via
  `EmailAddress.fromJson`. Short-circuits on first element error via `?`.
- Constructs `EmailAddressGroup` directly (no smart constructor).
- Returns `Result[EmailAddressGroup, ValidationError]`.

---

## 3. Thread — thread.nim

**RFC reference:** §3.

A Thread groups related Emails into a flat list sorted by `receivedAt`.
Every Email belongs to exactly one Thread. Thread is the simplest entity in
RFC 8621 — two properties, two methods, no query, no set.

**Module:** `src/jmap_client/mail/thread.nim`

### 3.1. Type Definition

**Pattern A (sealed fields)** — Thread has one invariant that `seq[Id]`
cannot express: `emailIds` must be non-empty (every Thread contains at least
one Email per RFC §3). Sealing prevents construction of a Thread with empty
`emailIds` outside the smart constructor.

```nim
type Thread* {.requiresInit.} = object
  rawId: Id              ## module-private
  rawEmailIds: seq[Id]   ## module-private, guaranteed non-empty
```

`{.requiresInit.}` complements the sealed fields. The project already
enables `strictDefs` and promotes `ProveInit` to an error, which prevents
*using* an uninitialised variable. `{.requiresInit.}` adds a distinct
layer: it prevents explicit zero-initialisation via `Thread()` (the object
constructor with all fields omitted) from outside the module. With sealed
fields, the consumer cannot name any fields in the constructor, so
`Thread()` is the only external constructor syntax — and it would produce
`rawEmailIds = @[]`, violating the non-empty invariant.

The project's `config.nims` promotes `UnsafeDefault` and `UnsafeSetLen`
warnings to compile errors. Combined with `{.requiresInit.}`, this means:
- `default(Thread)` is a compile error (`UnsafeDefault`).
- `seq[Thread].setLen(n)` is a compile error (`UnsafeSetLen`).
- `newSeq[Thread](n)` is a compile error (uses `setLen` internally).
- `var t: Thread` without provable initialisation is a compile error
  (`ProveInit`).

These four checks cover all known routes to zero-initialised `Thread`
values. Combined with sealed fields (which prevent external construction),
the non-empty `emailIds` invariant is enforced at compile time.

**Principles:**
- **Make illegal states unrepresentable** — Module-private fields +
  `{.requiresInit.}` + smart constructor guarantee non-empty `emailIds`.
  Direct construction of `Thread(rawId: x, rawEmailIds: @[])` is prevented
  outside `thread.nim`, and `Thread()` zero-initialisation is rejected by
  the pragma.
- **Parse, don't validate** — The smart constructor enforces the invariant
  once at the construction boundary.

### 3.2. Smart Constructor

```nim
func parseThread*(id: Id, emailIds: seq[Id]): Result[Thread, ValidationError]
```

Validates: `emailIds.len > 0`. Returns
`err(validationError("Thread", "emailIds must contain at least one Id"))`
on violation. Post-construction `doAssert` verifies `rawEmailIds.len > 0`
(same pattern as §2.1).

A Thread with zero emails has no domain meaning — it should not exist in the
model. Invalid server data belongs on the error rail.

**Principle:** Total functions — maps every input to `ok(Thread)` or
`err(ValidationError)`.

### 3.3. Accessors

```nim
func id*(t: Thread): Id
func emailIds*(t: Thread): seq[Id]
```

UFCS accessors for sealed fields. `emailIds` returns a copy of the internal
`seq[Id]` (value semantics under ARC).

### 3.4. Serde — serde_thread.nim

**Module:** `src/jmap_client/mail/serde_thread.nim`

**Wire format:**

```json
{
  "id": "f123u4",
  "emailIds": ["eaa623", "f782cbb"]
}
```

**toJson:**
- Emits `id` and `emailIds` fields.
- Uses accessor functions to read sealed fields.

**fromJson:**
- Validates JObject.
- Extracts `id` via `Id.fromJson` (required).
- Extracts `emailIds` as JArray, parses each element via `Id.fromJson`.
  Short-circuits on first element error via `?`.
- Delegates to `parseThread` for construction (enforces non-empty).
- Returns `Result[Thread, ValidationError]`.

### 3.5. Entity Registration

**Module:** `src/jmap_client/mail/mail_entities.nim`

```nim
func methodNamespace*(T: typedesc[Thread]): string = "Thread"
func capabilityUri*(T: typedesc[Thread]): string = "urn:ietf:params:jmap:mail"
registerJmapEntity(Thread)
```

**Valid methods:** `/get` (§3.1), `/changes` (§3.2). No `/query`, `/set`, or
`/copy`. Invalid method calls (e.g. `addSet[Thread]`) compile but produce
server errors — a client programming error, not a type-safety concern. Thread
supports exactly the two most common read-only methods; the generic builder
handles both perfectly.

**Builder usage:** Generic `addGet[Thread]`, `addChanges[Thread]` — no
entity-specific extensions (cross-cutting doc §9.4).

---

## 4. Identity — identity.nim

**RFC reference:** §6.

An Identity stores information about an email address or domain the user may
send from. Seven properties, three standard methods (`/get`, `/changes`,
`/set`). Simple entity with one noteworthy constraint: `email` is immutable
after creation.

**Module:** `src/jmap_client/mail/identity.nim`

### 4.1. Identity (Read Model)

**Plain public fields** — no Pattern A. All field-level invariants are
captured by the types themselves (`Id`, `Opt[seq[EmailAddress]]`, `bool`,
`string`). No cross-field invariants. Consistent with `Account` and
`CoreCapabilities` in core.

```nim
type Identity* = object
  id*: Id
  name*: string                     ## default: ""
  email*: string                    ## immutable after creation
  replyTo*: Opt[seq[EmailAddress]]  ## default: null
  bcc*: Opt[seq[EmailAddress]]      ## default: null
  textSignature*: string            ## default: ""
  htmlSignature*: string            ## default: ""
  mayDelete*: bool                  ## server-set
```

**String fields use `string`, not `Opt[string]`** — the RFC specifies
`name`, `textSignature`, and `htmlSignature` as `String` (never null) with
default `""`. The `fromJson` deserialiser treats absent keys as `""` (the
RFC-defined default). This eliminates a meaningless `Opt.none` state
(Identity's name is never "absent", it's just empty) and keeps the
`Opt`-means-nullable convention clean across the codebase.

Using `Opt[string]` would overload `Opt`'s meaning on a single type:
`Opt.none` on `replyTo` means "nullable", while `Opt.none` on `name` would
mean "maybe not requested". Two different semantics sharing one type-level
encoding violates Make illegal states unrepresentable.

**`email` immutability** — a server-enforced constraint. Attempting to
update `email` via `/set` returns a `SetError`. The type-level enforcement
of "email required on create" is in `IdentityCreate` (§4.2).

**`email` format** — the RFC permits wildcard addresses (e.g.
`*@example.com`). No format validation beyond non-empty in `IdentityCreate`.
The server decides what's valid; `forbiddenFrom` handles rejection.

**`mayDelete`** — server-set boolean. Attempting to destroy an Identity with
`mayDelete == false` returns standard `SetError(forbidden)`.

No smart constructor for the read model — `fromJson` extracts fields,
validates JSON structure, and constructs directly.

### 4.2. IdentityCreate (Creation Model)

The Identity read model and creation model have different valid field sets:
creates require `email` and exclude `id`/`mayDelete`. A distinct type makes
"create without email" unrepresentable.

```nim
type IdentityCreate* = object
  email*: string                     ## required, immutable after creation
  name*: string                      ## default: ""
  replyTo*: Opt[seq[EmailAddress]]   ## default: null
  bcc*: Opt[seq[EmailAddress]]       ## default: null
  textSignature*: string             ## default: ""
  htmlSignature*: string             ## default: ""
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

Validates: `email` non-empty. Post-construction `doAssert` verifies
`email.len > 0` (same pattern as §2.1). Default parameter values match
RFC-specified defaults for ergonomic construction:

```nim
let ic = ?parseIdentityCreate(email = "joe@example.com")  # all defaults
let ic2 = ?parseIdentityCreate(email = "joe@example.com", name = "Joe")
```

**Principles:**
- **Make illegal states unrepresentable** — `email` is required by
  construction. `id` and `mayDelete` don't exist on this type.
- **DDD** — Create and read are different domain operations with different
  valid shapes (same rationale as `EmailBlueprint` in cross-cutting doc
  §8.6: "different domain operations deserve different types").
- **Total functions** — `parseIdentityCreate()` →
  `Result[IdentityCreate, ValidationError]`.
- **Railway-Oriented Programming** — Construction railway via `Result`. The
  `?` operator composes with the consumer's existing railway.

**Layer separation:** `IdentityCreate` is a Layer 1 type. Its `toJson` is a
Layer 2 function. The generic `addSet[Identity]` builder (Layer 3) accepts
`Table[CreationId, JsonNode]` — the consumer calls `identityCreate.toJson()`
to produce the `JsonNode`. No Layer 3 extensions needed for Identity.

**Updates** use `PatchObject` via the generic `addSet[Identity]` builder. The
`email` immutability constraint is server-enforced on updates.

### 4.3. Serde — serde_identity.nim

**Module:** `src/jmap_client/mail/serde_identity.nim`

Imports `serde_addresses` for `EmailAddress` serde. Follows core serde
patterns.

**Identity wire format (example from RFC §6.4):**

```json
{
  "id": "XD-3301-222-11_22AAz",
  "name": "Joe Bloggs",
  "email": "joe@example.com",
  "replyTo": null,
  "bcc": [{"name": null, "email": "joe+archive@example.com"}],
  "textSignature": "-- \nJoe Bloggs\nMaster of Email",
  "htmlSignature": "<div><b>Joe Bloggs</b></div><div>Master of Email</div>",
  "mayDelete": false
}
```

**Identity.fromJson:**
- Validates JObject.
- Extracts `id` via `Id.fromJson` (required).
- Extracts `email` as string (required, rejects absent/null/non-string/empty).
- Extracts `name`, `textSignature`, `htmlSignature` as string — **absent
  key → `""` (RFC default)**. Present non-string → `err(ValidationError)`.
- Extracts `replyTo`, `bcc` as `Opt[seq[EmailAddress]]` — absent or null →
  `Opt.none`, present JArray → parse each element via `EmailAddress.fromJson`.
- Extracts `mayDelete` as bool (required).
- Constructs `Identity` directly (no smart constructor).
- Returns `Result[Identity, ValidationError]`.

**Identity.toJson:**
- Emits all fields. `replyTo`/`bcc` emit as `null` or array.
  `name`/`textSignature`/`htmlSignature` emit as string (even if `""`).

**IdentityCreate.toJson:**
- Emits all fields including defaults. No `id` or `mayDelete` fields.
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

No `IdentityCreate.fromJson` — creation types are constructed by the
consumer, not parsed from server responses.

### 4.4. Entity Registration

**Module:** `src/jmap_client/mail/mail_entities.nim`

```nim
func methodNamespace*(T: typedesc[Identity]): string = "Identity"
func capabilityUri*(T: typedesc[Identity]): string = "urn:ietf:params:jmap:submission"
registerJmapEntity(Identity)
```

**Valid methods:** `/get` (§6.1), `/changes` (§6.2), `/set` (§6.3). No
`/query`, `/queryChanges`, or `/copy`. Invalid method calls compile but
produce server errors.

**Builder usage:** Generic `addGet[Identity]`, `addChanges[Identity]`,
`addSet[Identity]` — no entity-specific extensions (cross-cutting doc §9.4).

**Set error:** `forbiddenFrom` on create (§6.3) — classified by
`MailSetErrorType` (§7).

---

## 5. VacationResponse — vacation.nim

**RFC reference:** §8.

A VacationResponse represents vacation auto-reply settings for an account.
Singleton pattern — exactly one per account, id always `"singleton"`. Only
`/get` and `/set` (update-only) are supported. No `/changes`, no `/query`.

**Module:** `src/jmap_client/mail/vacation.nim`

### 5.1. Type Definition

**No `id` field** — the `"singleton"` id has zero degrees of freedom. It
carries no information. Omitting it entirely eliminates the illegal state
(a VacationResponse with a wrong id) more strongly than any runtime check.

```nim
const VacationResponseSingletonId* = "singleton"
  ## The protocol-level id for the VacationResponse singleton.
  ## Used by serde (validation on deserialise, emission on serialise)
  ## and builder functions (hardcoded in update map).

type VacationResponse* = object
  isEnabled*: bool
  fromDate*: Opt[UTCDate]    ## null = effective immediately
  toDate*: Opt[UTCDate]      ## null = effective indefinitely
  subject*: Opt[string]      ## null = server chooses
  textBody*: Opt[string]     ## null = generated from htmlBody
  htmlBody*: Opt[string]     ## null = generated from textBody
```

No smart constructor needed — all invariants captured by field types. The
`fromDate`/`toDate` relationship (if both present, `fromDate` should precede
`toDate`) is a business rule, not a structural invariant; validation is the
server's responsibility.

**Principles:**
- **Make illegal states unrepresentable** — A constant is not state. The
  type only carries fields with actual degrees of freedom. You cannot have a
  VacationResponse with a wrong id because there is no id to be wrong.
- **DDD** — The domain concept is "vacation response settings for an
  account." The `"singleton"` id is a protocol addressing mechanism, not
  domain knowledge. The type models what the vacation response is (enabled,
  dates, body), not how the protocol addresses it.
- **DRY** — The `VacationResponseSingletonId` constant lives once in
  `vacation.nim` (domain layer), imported by both the serde module and
  builder functions. No string literal duplication.

**No creation or destruction** — the RFC forbids both. The singleton always
exists. Updates use `PatchObject` via `addVacationResponseSet` (§5.3).

### 5.2. Serde — serde_vacation.nim

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

**fromJson:**
- Validates JObject.
- Extracts `id` as string and validates
  `id == VacationResponseSingletonId`. Returns
  `err(validationError("VacationResponse", "id must be \"singleton\""))`
  on mismatch. The validated id is **discarded** after verification — it has
  served its purpose at the parsing boundary.
- Extracts `isEnabled` as bool (required).
- Extracts `fromDate`, `toDate` as `Opt[UTCDate]` — absent or null →
  `Opt.none`, present string → parse via `UTCDate.fromJson`.
- Extracts `subject`, `textBody`, `htmlBody` as `Opt[string]` — absent or
  null → `Opt.none`.
- Constructs `VacationResponse` directly.
- Returns `Result[VacationResponse, ValidationError]`.

**toJson:**
- Emits `"id": VacationResponseSingletonId` (the protocol requires it, the
  type does not carry it).
- Emits `isEnabled` as bool.
- Emits `fromDate`, `toDate`, `subject`, `textBody`, `htmlBody` — `Opt.none`
  emits as `null`, `Opt.some` emits the value.

### 5.3. Builder Functions

**No entity registration** — VacationResponse is NOT registered with
`registerJmapEntity`. It has only two valid methods (`/get` and `/set`,
update-only), neither of which are standard enough for the generic builder:
`/get` always fetches the singleton (no ids parameter needed), and `/set`
only supports update (no create/destroy). Custom builder functions make
invalid method calls uncompilable.

This follows the same pattern as `addSearchSnippetGet` in `mail_methods.nim`
— a non-standard entity that gets custom builder functions rather than using
the generic machinery.

**Module:** `src/jmap_client/mail/mail_methods.nim`

**addVacationResponseGet:**

```nim
func addVacationResponseGet*(b: var RequestBuilder,
    accountId: AccountId,
    properties: Opt[seq[PropertyName]] = Opt.none(seq[PropertyName]),
): ResponseHandle[GetResponse[VacationResponse]]
```

- Adds `"urn:ietf:params:jmap:vacationresponse"` capability to the request.
- Creates invocation with name `"VacationResponse/get"`.
- Omits `ids` — always fetches all, which is just the singleton. No `ids`
  parameter in the function signature because the only valid id is
  `"singleton"`, and omitting ids achieves the same result.
- Returns `ResponseHandle[GetResponse[VacationResponse]]`.

**addVacationResponseSet:**

```nim
func addVacationResponseSet*(b: var RequestBuilder,
    accountId: AccountId,
    update: PatchObject,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): ResponseHandle[SetResponse[VacationResponse]]
```

- Adds `"urn:ietf:params:jmap:vacationresponse"` capability to the request.
- Creates invocation with name `"VacationResponse/set"`.
- Internally constructs the update map as
  `{VacationResponseSingletonId: update.toJson()}` — the singleton id is
  referenced from the domain constant, not caller-specified.
- No `create` or `destroy` parameters — prevented at the function signature
  level.
- Takes `PatchObject` directly, not `Table[Id, PatchObject]` — eliminates
  the possibility of a wrong id.
- Returns `ResponseHandle[SetResponse[VacationResponse]]`.

**Principles:**
- **Make illegal states unrepresentable** — `addChanges[VacationResponse]`
  will not compile (no `methodNamespace`/`capabilityUri` overloads exist).
  `addVacationResponseSet` prevents create/destroy by omitting those
  parameters. The `"singleton"` id is hardcoded, not caller-specified.
- **DDD** — VacationResponse is a genuinely different kind of entity
  (singleton, no change tracking, restricted mutation). It deserves its own
  entry points rather than being forced through a generic framework designed
  for standard entities.
- **Total functions** — The API surface is exactly two functions, both total.

**Response dispatch:** Uses standard `GetResponse[VacationResponse]` and
`SetResponse[VacationResponse]` response types. The phantom-typed
`ResponseHandle[T]` dispatch works unchanged — the builder hardcodes the
method name strings (`"VacationResponse/get"`, `"VacationResponse/set"`),
and `get[T]` extraction matches by method name. No core modifications
needed.

---

## 6. Capability Types — mail_capabilities.nim

**Module:** `src/jmap_client/mail/mail_capabilities.nim` (Layer 1 types),
`src/jmap_client/mail/serde_mail_capabilities.nim` (Layer 2 parsing).

All three RFC 8621 capabilities are defined completely. The parsing functions
take `ServerCapability` (core Layer 1) and produce typed values. After a
single `parseMailCapabilities` call post-session-fetch, all capability data
is typed and validated.

Defining complete types now rather than deferring fields to later design docs
is driven by three principles:

- **Parse, don't validate** — `parseMailCapabilities` transforms raw JSON
  into a fully-typed value. You cannot "partially parse" — that would leave
  unparsed JSON leaking into the domain model.
- **DRY** — Nim enums and object types cannot be extended after definition.
  Define once, completely.
- **Total functions** — `parseMailCapabilities` must map every valid
  capability JSON to a typed result. Partial types silently discard data.

### 6.1. MailCapabilities

**RFC reference:** §1.3.1.

Typed parsing of the `urn:ietf:params:jmap:mail` account capability.

```nim
type MailCapabilities* = object
  maxMailboxesPerEmail*: Opt[UnsignedInt]   ## null = no limit; >= 1 when present
  maxMailboxDepth*: Opt[UnsignedInt]        ## null = no limit
  maxSizeMailboxName*: UnsignedInt           ## >= 100 (RFC mandates)
  maxSizeAttachmentsPerEmail*: UnsignedInt
  emailQuerySortOptions*: HashSet[string]
  mayCreateTopLevelMailbox*: bool
```

Plain public fields, no smart constructor — follows the `CoreCapabilities`
pattern in core. Validation happens in the serde layer's
`parseMailCapabilities`.

**Field notes:**

| Field | RFC Constraint | Validation | Consumed By |
|-------|---------------|------------|-------------|
| `maxMailboxesPerEmail` | `>= 1` when present, null for no limit | Serde validates `>= 1` | Mailbox validation (Design B) |
| `maxMailboxDepth` | null for no limit | None beyond `UnsignedInt` | Mailbox validation (Design B) |
| `maxSizeMailboxName` | `>= 100` | Serde validates `>= 100` | Mailbox name validation (Design B) |
| `maxSizeAttachmentsPerEmail` | none specified | None beyond `UnsignedInt` | Email creation (Design C) |
| `emailQuerySortOptions` | server-advertised sort properties | None | Consumer reference |
| `mayCreateTopLevelMailbox` | boolean | None | Mailbox set validation (Design B) |

`emailQuerySortOptions` is typed as `HashSet[string]` (not
`seq[PropertyName]`) because the primary domain operation is membership
testing ("does the server support sorting by `receivedAt`?"), which
`HashSet` serves in O(1). This follows the `collationAlgorithms:
HashSet[string]` precedent in `CoreCapabilities` (`capabilities.nim`),
which serves an identical purpose. The values are opaque
server-advertised strings that may include vendor extensions; the consumer
converts to `PropertyName` when constructing a `Comparator` for a query.

### 6.2. SubmissionCapabilities

**RFC reference:** §1.3.2.

Typed parsing of the `urn:ietf:params:jmap:submission` account capability.

```nim
type SubmissionCapabilities* = object
  maxDelayedSend*: UnsignedInt                       ## 0 = not supported
  submissionExtensions*: OrderedTable[string, seq[string]]  ## EHLO name → args
```

Plain public fields, no smart constructor.

**Field notes:**

| Field | RFC Constraint | Validation | Consumed By |
|-------|---------------|------------|-------------|
| `maxDelayedSend` | `0` = not supported | None beyond `UnsignedInt` | EmailSubmission creation (Design B) |
| `submissionExtensions` | EHLO name → arg list | None | EmailSubmission creation (Design B) |

`submissionExtensions` is `OrderedTable[string, seq[string]]` — keys are
SMTP EHLO extension names (e.g. `"FUTURERELEASE"`, `"SIZE"`), values are
argument lists (possibly empty). `OrderedTable` preserves insertion order
from the server response JSON, consistent with JSON round-trip fidelity
principles (both `std/tables` and `std/json` use `OrderedTable` for
objects).

### 6.3. VacationResponse Capability

**RFC reference:** §1.3.3.

The `urn:ietf:params:jmap:vacationresponse` capability has an empty object
as its value in both session and account capabilities. **No type is needed.**
The serde layer validates that the capability exists on the session (the
`rawData` is a JObject) but does not extract any fields.

The `addVacationResponseGet` and `addVacationResponseSet` builder functions
(§5.3) add this capability URI to the request. The consumer may optionally
verify the capability exists on the session before calling, but no typed
parsing step is required.

### 6.4. Serde — serde_mail_capabilities.nim

**Module:** `src/jmap_client/mail/serde_mail_capabilities.nim`

**parseMailCapabilities:**

```nim
func parseMailCapabilities*(cap: ServerCapability): Result[MailCapabilities, ValidationError]
```

- Validates `cap.kind == ckMail`. Returns
  `err(validationError("MailCapabilities", "expected ckMail capability"))`
  if wrong kind.
- Extracts `rawData: JsonNode` from the `ServerCapability`.
- Validates `rawData` is JObject.
- Parses each field with appropriate type conversions:
  - `maxMailboxesPerEmail`: JInt or JNull. When JInt, parses as
    `UnsignedInt`, then validates `>= 1`.
  - `maxMailboxDepth`: JInt or JNull. When JInt, parses as `UnsignedInt`.
  - `maxSizeMailboxName`: JInt (required). Parses as `UnsignedInt`, then
    validates `>= 100`.
  - `maxSizeAttachmentsPerEmail`: JInt (required). Parses as `UnsignedInt`.
  - `emailQuerySortOptions`: JArray of JString (required). Collects
    elements into `HashSet[string]`.
  - `mayCreateTopLevelMailbox`: JBool (required).
- Returns `ok(MailCapabilities)` or `err(ValidationError)`.

**parseSubmissionCapabilities:**

```nim
func parseSubmissionCapabilities*(cap: ServerCapability): Result[SubmissionCapabilities, ValidationError]
```

- Validates `cap.kind == ckSubmission`. Returns `err` if wrong kind.
- Extracts and validates `rawData` as JObject.
- Parses `maxDelayedSend` as `UnsignedInt` (required JInt).
- Parses `submissionExtensions` as JObject. Iterates key-value pairs in
  order, collecting into `OrderedTable`. Each key maps to a JArray of
  JString values. Malformed entries (non-array values, non-string array
  elements) produce `err(ValidationError)`.
- Returns `ok(SubmissionCapabilities)` or `err(ValidationError)`.

**Principles:**
- **Parse, don't validate** — Both functions transform raw JSON into fully
  typed values. After the call, you hold validated data.
- **Total functions** — Wrong capability kind, missing fields, invalid
  values, malformed JSON all map to `err(ValidationError)`.
- **DDD** — Core doesn't know what `maxMailboxDepth` means. Mail owns that
  knowledge. The parsing functions live in the mail module.
- **Open-Closed** — Core's `ServerCapability` is unchanged. Mail extends
  through composition (parsing `rawData`).

**Strictness rationale:** Structural invalidity (wrong JSON kind, missing
MUST fields) always rejects because the data is uninterpretable. RFC MUST
constraints (`>= 1`, `>= 100`) reject because the constraint is a domain
invariant — `maxMailboxesPerEmail = 0` has no valid domain interpretation.
Accepting it would push a contradiction into the typed model. Unknown/extra
fields are preserved via the underlying `ServerCapability.rawData` for
forward compatibility. The consumer's recourse for a non-conformant server
is to fall back to `rawData` parsing, which is always available on the
`ServerCapability`.

---

## 7. Mail Set Error Types — mail_errors.nim

**Module:** `src/jmap_client/mail/mail_errors.nim`

**RFC reference:** §§2.3, 4.6, 6.3, 7.5.

The complete RFC 8621 set error vocabulary, defined upfront. The enum
represents the RFC's error domain, not "errors relevant to entities
implemented so far" — following the same pattern as `CapabilityKind` in core,
which defines all known capabilities upfront regardless of implementation
progress.

### 7.1. MailSetErrorType Enum

```nim
type MailSetErrorType* = enum
  msetMailboxHasChild   = "mailboxHasChild"    ## Mailbox/set destroy
  msetMailboxHasEmail   = "mailboxHasEmail"    ## Mailbox/set destroy
  msetBlobNotFound      = "blobNotFound"       ## Email/import
  msetTooManyKeywords   = "tooManyKeywords"    ## Email/set
  msetTooManyMailboxes  = "tooManyMailboxes"   ## Email/set
  msetInvalidEmail      = "invalidEmail"       ## Email/set create, Email/import
  msetTooManyRecipients = "tooManyRecipients"  ## EmailSubmission/set
  msetNoRecipients      = "noRecipients"       ## EmailSubmission/set
  msetInvalidRecipients = "invalidRecipients"  ## EmailSubmission/set
  msetForbiddenMailFrom = "forbiddenMailFrom"  ## EmailSubmission/set
  msetForbiddenFrom     = "forbiddenFrom"      ## Identity/set create, EmailSubmission/set
  msetForbiddenToSend   = "forbiddenToSend"    ## EmailSubmission/set (§7.5)
  msetCannotUnsend      = "cannotUnsend"       ## EmailSubmission/set
  msetUnknown                                  ## catch-all for forward compatibility
```

String-backed enum for JSON serialisation. `msetUnknown` has no string
backing — it is the total-function catch-all for unrecognised error types.

**Principles:**
- **DRY** — Nim enums cannot be extended after definition. Defining the
  complete vocabulary upfront avoids rewriting the enum in later design docs.
- **Total functions** — `parseMailSetErrorType` maps every possible
  `rawType` to a variant. With the full enum, this function is complete and
  correct from day one. A partial enum would classify known types as
  `msetUnknown` — knowingly imprecise.
- **Make illegal states unrepresentable** — Closed enum with exhaustive
  pattern matching. No stringly-typed comparisons leak into consumer code.

### 7.2. parseMailSetErrorType

```nim
func parseMailSetErrorType*(rawType: string): MailSetErrorType
```

Uses `strutils.parseEnum` with `msetUnknown` as the fallback. Total over
all inputs. Identical signature pattern to `parseRequestErrorType`,
`parseMethodErrorType`, `parseSetErrorType` in core — all take a raw
string and return the typed enum.

Consumer pattern:

```nim
case parseMailSetErrorType(setError.rawType)
of msetForbiddenFrom:
  # handle forbidden sender address
of msetMailboxHasChild, msetMailboxHasEmail:
  # handle mailbox deletion constraints
of msetUnknown:
  # forward-compatible catch-all
# ... (exhaustive matching enforced by compiler)
```

### 7.3. Typed Error Accessors

Several RFC 8621 errors carry MUST-level extra properties beyond `type`
and `description`. These fields land in `SetError.extras: Opt[JsonNode]`
as raw JSON — core's `SetError` cannot be extended (Open-Closed
Principle).

The mail layer provides typed extraction via accessor functions in
`mail_errors.nim`:

| Error Type | Accessor | Return Type | RFC Requirement |
|------------|----------|-------------|-----------------|
| `blobNotFound` | `notFoundBlobIds*(se: SetError)` | `Opt[seq[Id]]` | MUST (§4.6) |
| `tooLarge` | `maxSize*(se: SetError)` | `Opt[UnsignedInt]` | MUST (§7.5) |
| `tooManyRecipients` | `maxRecipients*(se: SetError)` | `Opt[UnsignedInt]` | MUST (§7.5) |
| `invalidRecipients` | `invalidRecipientAddresses*(se: SetError)` | `Opt[seq[string]]` | MUST (§7.5) |
| `invalidEmail` | `invalidEmailProperties*(se: SetError)` | `Opt[seq[string]]` | SHOULD (§7.5) |

All return `Opt[T]` (not `Result`) because the server may omit a MUST
field — the accessor is typed extraction, not a parsing boundary.

These error types apply to entities in Design B/C. The accessors are
specified here because the enum is defined upfront per Decision A8, and
the accessor functions belong alongside the enum in `mail_errors.nim`.

**Principles:**
- **Parse, don't validate** — Typed extraction from raw JSON, not
  stringly-typed field access.
- **Open-Closed** — Core's `SetError` is unchanged. Mail extends through
  composition (accessor functions on the existing type).
- **DDD** — Mail-specific error semantics belong in the mail module.

### 7.4. Consumer Dispatch Pattern

`MailSetErrorType` is a classification overlay on `SetError.rawType`. The
two enums (`MailSetErrorType` and core `SetErrorType`) are disjoint by
design — no string values overlap. Consumers compose them via a two-step
dispatch:

```nim
## Recommended consumer pattern for mail /set errors:
let mailType = parseMailSetErrorType(setError.rawType)
case mailType
of msetForbiddenFrom, msetForbiddenToSend:
  # Handle mail-specific errors with typed classification
of msetTooManyRecipients:
  for maxR in setError.maxRecipients:  # typed accessor (§7.3)
    # Handle with typed value
of msetUnknown:
  # Not a mail-specific error — fall through to core classification
  case setError.errorType
  of setInvalidProperties:
    # Handle core error with typed variant fields
    let props = setError.properties
  of setForbidden, setOverQuota, setTooLarge:
    # Handle other core errors
  of setUnknown:
    # Genuinely unknown — log setError.rawType
  else: discard
else: discard
```

The outer `case` on `MailSetErrorType` handles mail-specific errors. When
`msetUnknown`, the inner `case` on `SetErrorType` handles core errors.
This pattern extends naturally as future design docs add domain-specific
error enums for other RFC extensions.

---

## 8. Test Specification

Numbered test scenarios for implementation plan reference. Unit tests verify
smart constructors and type invariants. Serde tests verify round-trip and
structural JSON correctness.

### 8.1. EmailAddress (scenarios 1–8)

| # | Scenario | Expected |
|---|----------|----------|
| 1 | `parseEmailAddress("joe@example.com")` | `ok`, name = `Opt.none` |
| 2 | `parseEmailAddress("joe@example.com", some("Joe"))` | `ok`, name = `Opt.some("Joe")` |
| 3 | `parseEmailAddress("")` | `err(ValidationError)` |
| 4 | `toJson` with name | `{"name": "Joe", "email": "joe@example.com"}` |
| 5 | `toJson` without name | `{"name": null, "email": "joe@example.com"}` |
| 6 | `fromJson` valid with name | `ok(EmailAddress)` |
| 7 | `fromJson` missing `email` field | `err(ValidationError)` |
| 8 | `fromJson` null `email` field | `err(ValidationError)` |

### 8.2. EmailAddressGroup (scenarios 9–12)

| # | Scenario | Expected |
|---|----------|----------|
| 9 | Construction with name and addresses | valid |
| 10 | Construction with null name | valid |
| 11 | Construction with empty addresses | valid |
| 12 | `toJson`/`fromJson` round-trip | identity |

### 8.3. Thread (scenarios 13–23)

| # | Scenario | Expected |
|---|----------|----------|
| 13 | `parseThread(id, @[emailId])` — single email | `ok`, `emailIds.len == 1` |
| 14 | `parseThread(id, @[e1, e2, e3])` — multiple emails | `ok`, `emailIds.len == 3` |
| 15 | `parseThread(id, @[])` — empty | `err(ValidationError)` |
| 16 | `id` accessor returns correct `Id` | pass |
| 17 | `emailIds` accessor returns correct `seq` | pass |
| 18 | `toJson` produces `{"id": "...", "emailIds": ["..."]}` | structural match |
| 19 | `fromJson` valid single email | `ok` |
| 20 | `fromJson` valid multiple emails | `ok`, order preserved |
| 21 | `fromJson` empty `emailIds` array | `err(ValidationError)` |
| 22 | `default(Thread)` | compile error (`UnsafeDefault`) |
| 23 | `var s: seq[Thread]; s.setLen(1)` | compile error (`UnsafeSetLen`) |

### 8.4. Identity (scenarios 24–32)

| # | Scenario | Expected |
|---|----------|----------|
| 24 | `fromJson` all fields present | `ok`, all fields populated |
| 25 | `fromJson` optional fields absent, defaults applied | `ok` |
| 26 | `fromJson` `name` absent → `""` | pass |
| 27 | `fromJson` `textSignature` absent → `""` | pass |
| 28 | `fromJson` `htmlSignature` absent → `""` | pass |
| 29 | `fromJson` `replyTo` null → `Opt.none` | pass |
| 30 | `fromJson` `replyTo` with addresses → `Opt.some(seq)` | pass |
| 31 | `toJson`/`fromJson` round-trip | identity |
| 32 | `fromJson` with `"email": ""` | `err(ValidationError)` |

### 8.5. IdentityCreate (scenarios 33–37)

| # | Scenario | Expected |
|---|----------|----------|
| 33 | `parseIdentityCreate("joe@example.com", ...)` all fields | `ok` |
| 34 | `parseIdentityCreate("joe@example.com")` defaults only | `ok`, name = `""`, sigs = `""` |
| 35 | `parseIdentityCreate("")` | `err(ValidationError)` |
| 36 | `toJson` includes all fields | structural match |
| 37 | `toJson` does not emit `id` or `mayDelete` | verified absent |

### 8.6. VacationResponse (scenarios 38–44)

| # | Scenario | Expected |
|---|----------|----------|
| 38 | `fromJson` valid, id = `"singleton"`, all fields | `ok` |
| 39 | `fromJson` optional fields null | `ok`, `Opt.none` for each |
| 40 | `fromJson` id = `"wrong"` | `err(ValidationError)` |
| 41 | `fromJson` id absent | `err(ValidationError)` |
| 42 | `toJson` emits `"id": "singleton"` | structural match |
| 43 | `toJson`/`fromJson` round-trip | identity |
| 44 | No `id` field on type | compile-time: `v.id` does not compile |

### 8.7. MailCapabilities (scenarios 45–51)

| # | Scenario | Expected |
|---|----------|----------|
| 45 | `parseMailCapabilities` valid, all fields present | `ok` |
| 46 | `parseMailCapabilities` wrong capability kind | `err(ValidationError)` |
| 47 | `maxMailboxesPerEmail = 1` | `ok` |
| 48 | `maxMailboxesPerEmail = 0` | `err(ValidationError)` |
| 49 | `maxMailboxesPerEmail` null → `Opt.none` | `ok` |
| 50 | `maxSizeMailboxName = 99` | `err(ValidationError)` |
| 51 | `maxSizeMailboxName = 100` | `ok` |

### 8.8. SubmissionCapabilities (scenarios 52–55)

| # | Scenario | Expected |
|---|----------|----------|
| 52 | `parseSubmissionCapabilities` valid | `ok` |
| 53 | `parseSubmissionCapabilities` wrong kind | `err(ValidationError)` |
| 54 | `maxDelayedSend = 0` (valid, means not supported) | `ok` |
| 55 | `submissionExtensions` with multiple EHLO entries | `ok`, parsed correctly |

### 8.9. MailSetErrorType (scenarios 56–69)

| # | Scenario | Expected |
|---|----------|----------|
| 56 | `parseMailSetErrorType` for each known type (13 cases) | correct variant |
| 57 | `parseMailSetErrorType` unknown `rawType` | `msetUnknown` |
| 58 | `parseMailSetErrorType` style-insensitive matching via `nimIdentNormalize` (first character case-sensitive, rest case-insensitive with underscores stripped; consistent with `parseSetErrorType` in core) | correct variant |
| 59 | Exhaustive pattern match compiles without missing branches | pass |
| 60 | `maxRecipients` on `tooManyRecipients` SetError with valid `extras` | `Opt.some(UnsignedInt)` |
| 61 | `maxRecipients` on SetError with absent/malformed `extras` | `Opt.none` |
| 62 | `invalidRecipientAddresses` on `invalidRecipients` SetError with valid `extras` | `Opt.some(seq[string])` |
| 63 | `invalidRecipientAddresses` on SetError with absent/malformed `extras` | `Opt.none` |
| 64 | `notFoundBlobIds` on `blobNotFound` SetError with valid `extras` | `Opt.some(seq[Id])` |
| 65 | `notFoundBlobIds` on SetError with absent/malformed `extras` | `Opt.none` |
| 66 | `maxSize` on `tooLarge` SetError with valid `extras` | `Opt.some(UnsignedInt)` |
| 67 | `maxSize` on SetError with absent/malformed `extras` | `Opt.none` |
| 68 | `invalidEmailProperties` on `invalidEmail` SetError with valid `extras` | `Opt.some(seq[string])` |
| 69 | `invalidEmailProperties` on SetError with absent/malformed `extras` | `Opt.none` |

### 8.10. Entity Registration and Builder (scenarios 70–75)

| # | Scenario | Expected |
|---|----------|----------|
| 70 | `registerJmapEntity(Thread)` compiles | pass |
| 71 | `registerJmapEntity(Identity)` compiles | pass |
| 72 | `addVacationResponseGet` produces invocation name `"VacationResponse/get"` | pass |
| 73 | `addVacationResponseGet` adds vacationresponse capability | pass |
| 74 | `addVacationResponseSet` produces invocation with `"singleton"` in update map | pass |
| 75 | `addVacationResponseSet` omits create and destroy from invocation args | pass |

---

## 9. Decision Traceability Matrix

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|----------|--------------------|--------|-------------------|
| A1 | EmailAddress in this doc vs deferred | A) Here as shared sub-type section, B) Defer to Design C, C) Separate doc | Modified A (shared section preceding entities) | DDD, Parse-don't-validate, DRY |
| A2 | Capability types scope | A) Complete now, B) Defer to consuming entities, C) Define all, document consumers | A (complete, all-or-nothing parsing) | Parse-don't-validate, DRY, Total functions |
| A3 | Identity creation model | A) PatchObject only, B) IdentityBlueprint, Modified B) Lightweight IdentityCreate | Modified B (`IdentityCreate` with email-required) | Make illegal states unrepresentable, DDD, Total functions |
| A4 | Thread field sealing | A) All public, B) Pattern A | B (non-empty `emailIds` invariant) | Make illegal states unrepresentable, Parse-don't-validate |
| A5 | Identity field sealing | A) All public, B) Pattern A | A (no invariants beyond field types) | Consistency with Account/CoreCapabilities |
| A6 | VacationResponse id field | A) `id: Id` validated, B) No `id` field, C) `id: Id` unvalidated | B (omit id — constant is not state) | Make illegal states unrepresentable, DDD, DRY |
| A7 | VacationResponse entity registration | A) Register + custom set, B) Don't register + custom get/set | B (compile-time prevention of invalid methods) | Make illegal states unrepresentable, DDD, Total functions |
| A8 | MailSetErrorType scope | A) Full enum now, B) Partial, extend later | A (complete vocabulary upfront) | DRY, Total functions, Parse-don't-validate |
| A9 | Identity string field types | A) `string` with default `""`, B) `Opt[string]` | A (RFC types are `String`, not `String\|null`) | Parse-don't-validate, Make illegal states unrepresentable, DDD |
| A10 | Thread emailIds non-empty | A) Enforce non-empty, B) Accept empty leniently | A (rejection at parsing boundary) | Parse-don't-validate, Make illegal states unrepresentable, Total functions |
| A11 | Serde module split for addresses | A) In `serde_identity.nim`, B) Separate `serde_addresses.nim` | B (shared bounded context, dependency flow) | DDD, DRY |
| A12 | VacationResponse set signature | A) `Table[Id, PatchObject]`, B) `PatchObject` (singleton hardcoded) | B (eliminate caller-specified id) | Make illegal states unrepresentable |
| A13 | `emailQuerySortOptions` collection type | A) `seq[string]`, B) `HashSet[string]` | B (O(1) membership testing, `collationAlgorithms` precedent) | DDD, DRY |
| A14 | Thread `{.requiresInit.}` pragma | A) Plain object, B) `{.requiresInit.}` | B (prevents zero-initialisation via `Thread()`, complements sealed fields and `strictDefs`/`ProveInit`) | Make illegal states unrepresentable |
| A15 | VacationResponse singleton id location | A) String literal in serde + builder, B) Shared `const` in `vacation.nim` | B (single source of truth, importable by serde and builder) | DRY |
| A16 | `submissionExtensions` table type | A) `Table`, B) `OrderedTable` | B (preserves JSON key order, consistent with `std/json` internals) | DDD |
| A17 | Mail error typed accessors | A) Extend core SetError, B) Parallel MailSetError case object, C) Typed accessor functions | C (extraction from extras) | Parse-don't-validate, Open-Closed, DDD |
| A18 | Identity.fromJson email validation | A) Accept empty (lenient), B) Reject empty (strict) | B (consistent with IdentityCreate) | Parse-don't-validate, DDD |
| A19 | `parseMailSetErrorType` signature | A) `(error: SetError)`, B) `(rawType: string)` | B (consistency with core parse functions) | DRY, DDD |
