# RFC 8621 JMAP Mail — Cross-Cutting Architecture Design

This document captures the architectural decisions that affect all entity types
in the RFC 8621 (JMAP Mail) implementation. It is the single reference for
cross-cutting concerns; per-entity implementation details are deferred to
implementation plans.

The design builds on the existing RFC 8620 (JMAP Core) infrastructure documented
in `00-architecture.md` through `04-layer-4-design.md`. All five layers, the
three-railway error model, the generic builder/dispatch pattern, and the
type-safety conventions carry forward unchanged. This document specifies how
mail-specific types, serialisation, protocol methods, and builder extensions
plug into that infrastructure.

## Table of Contents

1. [Scope](#1-scope)
2. [Governing Principles](#2-governing-principles)
3. [Module Layout](#3-module-layout)
4. [Knowledge Boundary Principle](#4-knowledge-boundary-principle)
5. [Keyword Type](#5-keyword-type)
6. [Header Parsed Forms](#6-header-parsed-forms)
7. [Body Structure](#7-body-structure)
8. [Email Type and Creation Type](#8-email-type-and-creation-type)
9. [Entity-Specific Builder Overloads](#9-entity-specific-builder-overloads)
10. [Custom Methods](#10-custom-methods)
11. [Compound Handles](#11-compound-handles)
12. [Filter Conditions](#12-filter-conditions)
13. [Per-Entity Summary](#13-per-entity-summary)

---

## 1. Scope

**Full RFC 8621** — all seven data types, all methods, all properties:

| Data Type          | Complexity | Key Challenge                                           |
|--------------------|------------|---------------------------------------------------------|
| Mailbox            | Moderate   | MailboxRights, query with tree sorting, `/set` extras   |
| Thread             | Simple     | 2 properties, only `/get` and `/changes`                |
| Email              | Very high  | 30+ properties, MIME tree, header parsed forms, create   |
| SearchSnippet      | Simple     | Non-standard `/get`, no state, required filter          |
| Identity           | Simple     | 7 properties, standard methods                          |
| EmailSubmission    | High       | Implicit chaining, envelope, delivery status            |
| VacationResponse   | Simple     | Singleton pattern, only `/get` and `/set`               |

Three capability URIs:

- `urn:ietf:params:jmap:mail` — Mailbox, Thread, Email, SearchSnippet
- `urn:ietf:params:jmap:submission` — Identity, EmailSubmission
- `urn:ietf:params:jmap:vacationresponse` — VacationResponse

---

## 2. Governing Principles

The following principles from the core architecture govern every decision in
this document. Each decision section traces back to the specific principles
that drive it.

- **Parse, don't validate** — Smart constructors produce well-typed Result
  values. After construction, the value is canonical and valid. The parsing
  boundary is at the layer that owns the domain knowledge.
- **Make illegal states unrepresentable** — Distinct types, case objects, and
  smart constructors prevent invalid values from existing. Prefer type-level
  constraints over runtime validation.
- **Railway-Oriented Programming** — Three railways (construction, transport,
  per-method) compose via the `?` operator. Error types are specific and
  actionable.
- **Total functions** — Every function maps every input to a result. No partial
  functions, no panics, no unhandled cases. `{.push raises: [].}` on every
  module.
- **Functional Core, Imperative Shell** — All mail modules are pure (Layer 1
  types, Layer 2 serde, Layer 3 builders). The imperative shell is core's
  `client.nim`. Mail never touches it.
- **Immutability by default** — All types are value objects, constructed once
  and never modified. Builder functions take values, not `var` references
  (except `var RequestBuilder` for accumulation).
- **DRY** — Shared abstractions defined once. Duplication is acceptable only
  when documented as a conscious trade-off.
- **Domain-Driven Design** — Core owns core knowledge, mail owns mail
  knowledge. Types model domain concepts, not wire format. API names reflect
  domain intent, not protocol encoding.
- **Open-Closed Principle** — Core types are stable and closed for
  modification. Mail extends through composition, parsing, and new modules —
  never by modifying core types.

---

## 3. Module Layout

### 3.1. Decision

All RFC 8621 modules live under `src/jmap_client/mail/` with a `mail.nim`
re-export hub at the directory level. This parallels core's flat structure
under `src/jmap_client/` with `types.nim` as its hub.

### 3.2. Options Analysed

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Flat alongside core** | `src/jmap_client/mailbox.nim`, `email.nim`, etc. | Simple, matches existing layout. Directory grows to ~40 files — hard to navigate. No separation between core and mail. |
| **B) Nested under `mail/`** | `src/jmap_client/mail/mailbox.nim`, etc. with `mail.nim` hub. | Clean core/mail separation. Scales for future RFCs (`contacts/`, `calendars/`). Single import path (`import jmap_client/mail`). |
| **C) Nested by layer** | `src/jmap_client/mail/types/`, `mail/serde/`, etc. | More structure but overkill for this project size. Adds depth without proportional benefit. |

### 3.3. Decision: Option B

**Principles:** DDD (core/mail knowledge boundary), Open-Closed (core directory
unchanged), scalability for future RFC extensions.

### 3.4. Module Tree

```
src/jmap_client/mail/
├── mail.nim                    # Top-level re-export hub (all layers)
│
│  # Re-export hubs (per-layer)
├── types.nim                   # Re-export hub for all Layer 1 mail types
├── serialisation.nim           # Re-export hub for all Layer 2 mail serde
│
│  # Shared sub-types (Layer 1)
├── keyword.nim                 # Keyword distinct type, parseKeyword, system constants
├── addresses.nim               # EmailAddress, EmailAddressGroup
├── headers.nim                 # EmailHeader, HeaderPropertyKey, HeaderValue, AllowedHeaderForms
├── body.nim                    # EmailBodyPart (isMultipart case object), EmailBodyValue, PartId
│
│  # Entity types (Layer 1)
├── mailbox.nim                 # Mailbox, MailboxRights, MailboxIdSet
├── thread.nim                  # Thread
├── email.nim                   # Email, ParsedEmail, EmailBlueprint (creation type)
├── snippet.nim                 # SearchSnippet
├── identity.nim                # Identity
├── submission.nim              # EmailSubmission, Envelope, Address, DeliveryStatus,
│                               #   UndoStatus, SubmissionEmailRef
├── vacation.nim                # VacationResponse
│
│  # Mail-specific framework types (Layer 1)
├── mail_capabilities.nim       # MailCapabilities, SubmissionCapabilities
├── mail_errors.nim             # MailSetErrorType enum
├── mail_filters.nim            # MailboxFilterCondition, EmailFilterCondition,
│                               #   EmailSubmissionFilterCondition, EmailHeaderFilter
│
│  # Serialisation (Layer 2)
├── serde_keyword.nim
├── serde_addresses.nim
├── serde_headers.nim
├── serde_body.nim
├── serde_mailbox.nim
├── serde_thread.nim
├── serde_email.nim
├── serde_snippet.nim
├── serde_identity.nim
├── serde_submission.nim
├── serde_vacation.nim
├── serde_mail_capabilities.nim
├── serde_mail_filters.nim
│
│  # Entity registration + builder extensions (Layer 3)
├── mail_entities.nim           # registerJmapEntity for all 7 types
├── mail_builders.nim           # Entity-specific overloads of standard methods
├── mail_methods.nim            # Custom methods (Email/import, Email/parse, SearchSnippet/get)
└── mail_convenience.nim        # Pipeline combinators for common mail patterns
```

### 3.5. Dependency Flow

```
keyword.nim    addresses.nim          (no dependencies on each other)
    │               │
    │        ┌──────┘
    │        ▼
    │    headers.nim ──► addresses.nim
    │        │
    │        │         body.nim        (standalone)
    │        │            │
    │        └─────┬──────┘
    │              ▼
    ├────────► email.nim               (imports keyword, addresses, headers, body)
    │
    ├────────► mailbox.nim             (imports keyword for MailboxIdSet pattern)
    │
    │          thread.nim              (standalone)
    │          snippet.nim             (standalone)
    │
    ├────────► identity.nim            (imports addresses)
    │
    ├────────► submission.nim          (imports addresses, keyword)
    │
    │          vacation.nim            (standalone)
    │
    ├────────► mail_filters.nim        (imports keyword, addresses)
    │
    │          mail_capabilities.nim   (standalone — parses from core ServerCapability)
    │          mail_errors.nim         (standalone — parses from core SetError)
    │
    │  Serde modules: each serde_X.nim imports X.nim + core serde helpers
    │  No serde module imports another serde module (except through re-export hubs)
    │
    │  Layer 3 modules: import Layer 1 types + Layer 2 serde + core protocol
    └────────► mail_builders.nim, mail_methods.nim, mail_convenience.nim
```

All mail modules import from core (`types.nim`, `validation.nim`). No mail
module imports from core's serde or protocol layers directly — only through
the public interface. No circular dependencies within mail.

### 3.6. Test Layout

```
tests/
├── unit/mail/           # Smart constructor + type invariant tests
├── serde/mail/          # Round-trip + structural JSON tests
├── property/mail/       # Property-based tests
└── compliance/mail/     # RFC 8621 compliance vectors
```

Mirrors the source module structure. Each test file covers one source module.

### 3.7. Sub-Type Organisation

The shared sub-types are organised by semantic domain, not by parent entity:

| Module | Types | Rationale |
|--------|-------|-----------|
| `addresses.nim` | `EmailAddress`, `EmailAddressGroup` | Used by Email, Identity, EmailSubmission. About addresses, not any single entity. |
| `headers.nim` | `EmailHeader`, `HeaderPropertyKey`, `HeaderValue`, `AllowedHeaderForms` | About parsed header forms. One-way dependency on `addresses.nim` (Addresses/GroupedAddresses forms produce `EmailAddress`/`EmailAddressGroup`). |
| `body.nim` | `EmailBodyPart`, `EmailBodyValue`, `PartId` | About MIME structure. Separate bounded context from headers. |

**Principles:** DDD (bounded contexts), single-responsibility (each module has
one focus), one-way dependencies (no cycles).

This was refined from an initial proposal that grouped `HeaderValue` with body
types. The user identified that headers and body structure are genuinely
different domains — `HeaderValue` is about "parsed header forms", not "MIME
structure" — and separated them into distinct modules.

---

## 4. Knowledge Boundary Principle

### 4.1. Decision

Core types are stable and closed. Mail-specific knowledge is parsed and
classified at the mail layer, never pushed into core. The same pattern applies
consistently across three extension points: capabilities, errors, and method
extensions.

### 4.2. Capabilities Boundary

**Options analysed:**

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Add typed variants to `ServerCapability`** | Extend case object with `ckMail: MailCapabilities`, etc. | Typed access. But core has compile-time knowledge of mail — violates Open-Closed. Every future RFC modifies the same case object. |
| **B) Keep raw, parse on demand** | Mail capability data stays as `rawData: JsonNode`. Standalone parsing in mail module. | Core stable. Clean knowledge boundary. One extra call for consumers. |

**Decision: Option B.**

- Core Layer 2 (`serde_session.nim`) parses `ServerCapability` with
  `rawData: JsonNode` for non-core URIs. This is correct — core genuinely
  doesn't know what `maxMailboxDepth` means.
- Mail Layer 1 (`mail_capabilities.nim`) defines `MailCapabilities` and
  `SubmissionCapabilities` as fully typed objects with smart constructors.
- Mail Layer 2 (`serde_mail_capabilities.nim`) provides
  `parseMailCapabilities(cap: ServerCapability): Result[MailCapabilities, ValidationError]`.
- Consumer calls `parseMailCapabilities` once after session fetch, holds typed
  value thereafter.

**Principles:**
- **DDD** — Core doesn't know what `maxMailboxDepth` means. Mail owns that
  knowledge.
- **Parse, don't validate** — `parseMailCapabilities` transforms raw JSON into
  typed `MailCapabilities` at the mail serde layer. After that call, you hold
  validated data. The parsing boundary moves to the layer that owns the domain
  knowledge, but it doesn't disappear.
- **Open-Closed** — Core is closed for modification. Mail extends through
  composition (parsing raw JSON) without changing `ServerCapability`.
- **Functional Core** — Both `ServerCapability` (core) and `MailCapabilities`
  (mail) are pure value types. The parsing function is a pure `func`.

### 4.3. Errors Boundary

**Options analysed:**

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Extend core `SetErrorType` enum** | Add RFC 8621 error codes to `SetErrorType`. | Simple. But core has compile-time knowledge of mail errors. Same OCP violation as capabilities. Repeats for every future RFC. |
| **B) `setUnknown` + raw string matching** | Mail code does `if error.rawType == "mailboxHasChild"`. | No core changes. But stringly-typed — exactly the pattern the project avoids. |
| **C) Mail-layer enum with parsing** | Mail module defines `MailSetErrorType` enum and `parseMailSetErrorType(error: SetError): MailSetErrorType`. | Core stable. Mail has typed classification. Same pattern as capabilities. |

**Decision: Option C.**

- Core Layer 1 (`errors.nim`) owns `SetError` with `rawType: string` and
  `setUnknown` catch-all. The raw type is always preserved for lossless
  round-trip.
- Mail Layer 1 (`mail_errors.nim`) defines `MailSetErrorType` enum:
  `msetMailboxHasChild`, `msetMailboxHasEmail`, `msetBlobNotFound`,
  `msetTooManyKeywords`, `msetTooManyMailboxes`, `msetInvalidEmail`,
  `msetTooManyRecipients`, `msetNoRecipients`, `msetInvalidRecipients`,
  `msetForbiddenMailFrom`, `msetForbiddenFrom`, `msetCannotUnsend`,
  `msetUnknown`.
- Mail Layer 1 provides
  `parseMailSetErrorType(error: SetError): MailSetErrorType` — inspects
  `rawType`, returns typed classification.

**Principles:**
- **Make illegal states unrepresentable** — `MailSetErrorType` is a closed
  enum. Pattern matching is exhaustive (with `msetUnknown` as catch-all). No
  stringly-typed comparisons leak into consumer code.
- **Railway-Oriented Programming** — The error classification stays on the
  same rail. `parseMailSetErrorType` takes a `SetError` (already on the
  success rail as data) and refines it — it doesn't change railways.
- **Total functions** — `parseMailSetErrorType` maps every possible `rawType`
  to a variant. `msetUnknown` makes it total.
- **Open-Closed** — Core's `SetError` is unchanged. Mail adds classification
  through a new module.

### 4.4. Method Extensions Boundary

**Options analysed:**

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Entity-specific builder functions in mail module** | `addEmailGet`, `addMailboxQuery`, etc. call core's internal `addInvocation`. | Type-safe, discoverable. No core changes. Mail owns mail knowledge. |
| **B) Extend core builder with generic "custom args"** | Add `extras: Opt[JsonNode]` parameter to generic builder methods. | Flexible but untyped. Loses the compile-time safety the project values. |

**Decision: Option A.**

- Core Layer 3 (`builder.nim`) owns generic `addGet[T]`, `addQuery[T, C]`,
  etc. and the internal `addInvocation` mechanism.
- Mail Layer 3 (`mail_builders.nim`) provides entity-specific overloads
  (`addEmailGet`, `addMailboxQuery`, `addEmailQuery`) with extra parameters.
- Mail Layer 3 (`mail_methods.nim`) provides custom methods
  (`addEmailImport`, `addEmailParse`, `addSearchSnippetGet`) with bespoke
  request/response types.
- Entities without extensions (`Thread`, `Identity`) use the core generic
  builder unchanged.

**Principles:**
- **DDD** — `addEmailGet` lives in the mail module because it encodes
  mail-specific knowledge (`bodyProperties`, `fetchTextBodyValues`). Core's
  `addGet[T]` doesn't know those exist.
- **Immutability by default** — Builder overloads produce immutable
  `Invocation` values and return phantom-typed `ResponseHandle[T]`. No
  mutable state beyond the builder's accumulation.
- **DRY** — Mail builder functions call into core's `addInvocation` mechanism.
  Capability deduplication, call ID generation, and invocation accumulation
  are written once in core, reused by every mail method.

---

## 5. Keyword Type

### 5.1. Decision

`Keyword` is a distinct validated type with a smart constructor that validates
and normalises to lowercase during construction. System keywords are
compile-time constants.

### 5.2. Type Definition

```nim
type Keyword* = distinct string
```

Borrowed operations via `defineStringDistinctOps(Keyword)`: `==`, `$`, `hash`,
`len`.

### 5.3. Smart Constructor

`parseKeyword(raw: string): Result[Keyword, ValidationError]`:
- Validates: 1–255 bytes, ASCII `%x21–%x7E`
- Rejects forbidden characters: `( ) { ] % * " \`
- **Normalises to lowercase** during construction

After construction, `Keyword` is always lowercase, always valid. No downstream
code ever needs to worry about case.

**Principles:**
- **Parse, don't validate** — The smart constructor transforms input into
  canonical form, not just checks it. This is the principle at its purest.
- **Total functions** — Maps every input to `ok(Keyword)` or
  `err(ValidationError)`.

Lenient variant `parseKeywordFromServer(raw: string): Result[Keyword, ValidationError]`
for server data — wider accepted input set, still total, still normalises to
lowercase, never silently swallows errors.

### 5.4. Forbidden Characters Constant

```nim
const KeywordForbiddenChars*: set[char] = {'(', ')', '{', ']', '%', '*', '"', '\\'}
```

Defined once, used by both `parseKeyword` and `parseKeywordFromServer`. Same
pattern as `Base64UrlChars` in `primitives.nim`.

**Principle:** DRY — single source of truth for the forbidden character set.

### 5.5. System Keyword Constants

```nim
const
  kwDraft*     = Keyword("$draft")
  kwSeen*      = Keyword("$seen")
  kwFlagged*   = Keyword("$flagged")
  kwAnswered*  = Keyword("$answered")
  kwForwarded* = Keyword("$forwarded")
  kwPhishing*  = Keyword("$phishing")
  kwJunk*      = Keyword("$junk")
  kwNotJunk*   = Keyword("$notjunk")
```

Module-level `const` construction is the one permitted bypass of the smart
constructor, justified by compile-time provability — these are literals that
are provably valid.

**Principles:**
- **DRY** — Define once, use everywhere.
- **Make illegal states unrepresentable** — Pre-validated at compile time.
  The common case is ergonomic.

### 5.6. KeywordSet

`KeywordSet = distinct HashSet[Keyword]` — not `Table[Keyword, bool]`.

The RFC mandates that all values in the `keywords` map MUST be `true`. The
`bool` carries no information. A `HashSet[Keyword]` makes the "value is always
true" invariant unrepresentable rather than validated. The serde layer parses
`{"$seen": true, "$flagged": true}` into `KeywordSet`, rejecting any entry
with `false`.

**Principles:**
- **Make illegal states unrepresentable** — Eliminates an entire class of
  invalid state (a keyword mapped to `false`) at the type level.
- **DDD** — The domain model doesn't mirror the wire format. The serde layer
  handles the `Table[Keyword, bool]` JSON representation.
- **Immutability by default** — `KeywordSet` is an immutable value type.
  Adding/removing keywords produces a new set, not a mutation.

---

## 6. Header Parsed Forms

### 6.1. Decision

Dynamic header requests return a typed `HeaderValue` case object. The serde
layer determines the correct variant from the property name suffix and parses
into the corresponding type. No JSON blobs leak into the domain model.

### 6.2. Options Analysed

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) String-keyed JsonNode map** | `Table[string, JsonNode]` with full property name as key. | Simple, flexible. No type safety. Parsing is the consumer's problem. |
| **B) Typed header value enum** | Case object `HeaderValue` with variants for each parsed form. Requested headers in `Table[HeaderPropertyKey, HeaderValue]`. | Type-safe. Parse-don't-validate at the serde boundary. More complex but complexity contained in serde. |
| **C) Convenience properties only** | Only model RFC 8621 convenience shortcuts as typed fields. Dynamic `header:X:asY` syntax stored as raw JSON. | Covers 95% of use cases. But unvalidated JSON in domain model for the remaining 5%. |

**Decision: Option B, with convenience properties as first-class fields.**

The user's argument was decisive: "parse, don't validate applied consistently"
— every parsed form that comes back from the server gets parsed into a proper
type at the deserialisation boundary. The complexity is real but contained in
the serde layer where it belongs. The domain types themselves are clean.

### 6.3. Three Tiers of Header Access

1. **Convenience fields** on `Email` (`from`, `to`, `subject`, `sentAt`, etc.)
   — first-class, always parsed when present in the response. These are the
   primary API for the vast majority of clients.

2. **Dynamic parsed headers** via `requestedHeaders: Table[HeaderPropertyKey, HeaderValue]`
   — typed, form-aware. When you ask for `header:X:asAddresses`, the
   deserialiser parses into `HeaderValue(form: hfAddresses, ...)`. Used for
   custom headers or headers not covered by convenience fields.

3. **Raw headers** via `headers: Opt[seq[EmailHeader]]` — the escape hatch.
   Raw string values for all header fields. This is the RFC's "Raw" form.

### 6.4. HeaderValue Case Object

```nim
type HeaderForm* = enum
  hfRaw, hfText, hfAddresses, hfGroupedAddresses, hfMessageIds, hfDate, hfUrls

type HeaderValue* = object
  case form*: HeaderForm
  of hfRaw:              rawValue*: string
  of hfText:             textValue*: string
  of hfAddresses:        addresses*: seq[EmailAddress]
  of hfGroupedAddresses: groups*: seq[EmailAddressGroup]
  of hfMessageIds:       messageIds*: Opt[seq[string]]   # null if parsing failed
  of hfDate:             date*: Opt[Date]                 # null if parsing failed
  of hfUrls:             urls*: Opt[seq[string]]          # null if parsing failed
```

**Principles:**
- **Make illegal states unrepresentable** — Each form has exactly the fields
  it needs. No optional fields on variants where the data is always present.
- **Total functions** — Pattern matching on the `form` discriminant is
  exhaustive. The compiler warns if a branch is missed.

### 6.5. HeaderPropertyKey

A structured type replacing raw string keys:

```nim
type HeaderPropertyKey* = object
  name*: string         # e.g., "From", "X-Custom"
  form*: HeaderForm     # e.g., hfAddresses
  isAll*: bool          # :all suffix
```

**Principles:**
- **Make illegal states unrepresentable** — The form is stated once (in the
  key). A smart constructor for inserting a header entry enforces that the
  `HeaderValue` variant matches the key's `form`. You cannot store an
  `hfDate` value under an `hfAddresses` key.
- **Parse, don't validate** — `parseHeaderPropertyName` produces
  `Result[HeaderPropertyKey, ValidationError]`, not a tuple. The raw string
  `"header:From:asAddresses:all"` goes in, a validated `HeaderPropertyKey`
  comes out. After that, no code ever re-parses the string. Named types are
  the parsed form; tuples are anonymous.

`parseHeaderPropertyName(prop: string): Result[HeaderPropertyKey, ValidationError]`:
- Validates: `header:` prefix, non-empty header name, valid form suffix
- Handles: `header:Name`, `header:Name:asForm`, `header:Name:all`,
  `header:Name:asForm:all`
- **Total** — handles every input: missing prefix, unknown form suffix, empty
  name. All map to `err(ValidationError)`.

### 6.6. AllowedHeaderForms

A const table mapping known header names to their permitted parsed forms:

```nim
const AllowedHeaderForms*: Table[string, set[HeaderForm]] = {
  "from":       {hfAddresses, hfGroupedAddresses, hfRaw},
  "sender":     {hfAddresses, hfGroupedAddresses, hfRaw},
  "reply-to":   {hfAddresses, hfGroupedAddresses, hfRaw},
  "to":         {hfAddresses, hfGroupedAddresses, hfRaw},
  "cc":         {hfAddresses, hfGroupedAddresses, hfRaw},
  "bcc":        {hfAddresses, hfGroupedAddresses, hfRaw},
  "subject":    {hfText, hfRaw},
  "date":       {hfDate, hfRaw},
  "message-id": {hfMessageIds, hfRaw},
  "in-reply-to":{hfMessageIds, hfRaw},
  "references": {hfMessageIds, hfRaw},
  # ... (full list per RFC 8621 §4.1.2)
}.toTable
```

**Principles:**
- **DRY** — Defined once. Both creation validation and any future
  documentation generation derive from this single source of truth.
- **Total functions** — Unknown header names (not in the table) are allowed
  with any form (the RFC explicitly permits custom headers with any form).
  Known headers with forbidden forms return `err(ValidationError)`.

### 6.7. Serde Layer

`serde_headers.nim` — the parsing boundary for header values.

The deserialiser:
1. Calls `?parseHeaderPropertyName(prop)` to extract `HeaderPropertyKey`
2. Calls `?parseHeaderValue(key.form, jsonNode)` to parse into the correct
   `HeaderValue` variant
3. Inserts into the typed map with key–value consistency enforced

Each step returns `Result`, each can fail independently with a specific
`ValidationError`. The railway is clean.

The `Opt[Opt[T]]` pattern does not apply to headers (headers are always
present or absent, never `null`). The three-way dispatch documented in
§12.6 is specific to filter conditions.

### 6.8. Email Fields for Dynamic Headers

```nim
# On the Email type:
requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]
```

Named `requestedHeaders` (not `dynamicHeaders`) because they are
"client-requested parsed header views" — not all headers (that's
`headers: Opt[seq[EmailHeader]]`), but the specific parsed views the client
asked for.

**Principles:**
- **DDD** — The name expresses what the field represents: requested header
  projections.
- **Immutability by default** — Both tables are immutable once constructed.
  The serde layer builds them and seals them.

---

## 7. Body Structure

### 7.1. Decision

`EmailBodyPart` is a case object discriminated by `isMultipart`. The RFC's
invariant ("partId and blobId are null if and only if the part is multipart/*")
is enforced at the type level.

### 7.2. Options Analysed

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) All fields optional** | `subParts: Opt[seq[EmailBodyPart]]`, `partId: Opt[string]`, etc. | Simple. But permits invalid combinations (e.g., multipart node with `partId`). |
| **B) Case object by multipart** | Discriminant `isMultipart`. Leaf fields on `false` branch, `subParts` on `true` branch. Shared fields in common area. | Compiler-enforced invariant. Exhaustive pattern matching. No invalid combinations possible. |
| **C) Separate types** | `EmailBodyPartNode` and `EmailBodyPartLeaf` unified under variant. | Same structural idea as B with different naming. |

**Decision: Option B.**

**Principles:**
- **Make illegal states unrepresentable** — The case discriminant encodes
  the RFC invariant directly. Leaf nodes always have `partId`/`blobId`/`size`.
  Multipart nodes always have `subParts`. No runtime checks needed downstream.
- **Parse, don't validate** — The serde layer inspects the `type` field
  (or presence of `subParts`), picks the correct discriminant, and constructs
  the right variant. By the time you hold an `EmailBodyPart`, the invariant
  is guaranteed.
- **Total functions** — Any function operating on `EmailBodyPart` can
  pattern-match on the discriminant exhaustively. The compiler warns if a
  branch is missed.

### 7.3. Type Definition

```nim
type PartId* = distinct string  # unique within an Email

type EmailBodyPart* = object
  ## Shared fields (all parts):
  headers*: seq[EmailHeader]
  name*: Opt[string]              # decoded filename
  contentType*: string            # e.g., "text/plain", "multipart/mixed"
  charset*: Opt[string]           # null for non-text/*, "us-ascii" default for text/*
  disposition*: Opt[string]       # "inline", "attachment", or null
  cid*: Opt[string]               # Content-Id without angle brackets
  language*: Opt[seq[string]]     # Content-Language tags
  location*: Opt[string]          # Content-Location URI

  case isMultipart*: bool
  of true:
    subParts*: seq[EmailBodyPart] # recursive children
  of false:
    partId*: PartId               # unique within the Email
    blobId*: Id                   # reference to content blob
    size*: UnsignedInt            # decoded content size in octets
```

### 7.4. PartId Distinct Type

`PartId = distinct string` — same pattern as `Id`, `Keyword`. Prevents
accidentally using an arbitrary string as a body values lookup key.

Smart constructor `parsePartId(raw: string): Result[PartId, ValidationError]`
validates non-empty.

### 7.5. contentType and isMultipart Consistency

The `isMultipart` discriminant and `contentType` string encode overlapping
information. `isMultipart` is the canonical discriminant; `contentType` is the
full MIME type string. The serde layer **derives** `isMultipart` from
`contentType` — they are not independently specified. This avoids any future
temptation to set them inconsistently.

**Principle:** DRY — one source of truth for "is this a multipart part?".

### 7.6. Recursive Depth Limit

The serde layer's `fromJson` for `EmailBodyPart` handles arbitrarily deep
nesting. A configurable depth limit (with a sensible default, e.g., 64)
returns `err(ValidationError)` beyond the bound. This keeps the function total
even against adversarial input.

**Principle:** Total functions — every input maps to a result, including
pathologically deep trees.

### 7.7. Flat List Invariant

The `Email` type carries `textBody`, `htmlBody`, `attachments` as
`Opt[seq[EmailBodyPart]]`. These flat lists must only contain leaf parts
(never multipart nodes). The serde layer validates this during construction
— any multipart entry in a flat list is rejected with
`err(ValidationError)`.

The invariant is "guaranteed by construction" — after parsing, the flat lists
are guaranteed to contain only leaf parts.

**Principle:** Make illegal states unrepresentable — while Nim's type system
can't express "a seq containing only the `isMultipart: false` variant" without
a separate type, the smart constructor enforces it.

### 7.8. EmailBodyValue

```nim
type EmailBodyValue* = object
  value*: string              # decoded text content
  isEncodingProblem*: bool    # default false
  isTruncated*: bool          # default false
```

Plain value object. On creation (`EmailBlueprint`), both flags must be `false`
— enforced by the creation type's smart constructor.

### 7.9. Immutability of Recursive Tree

`seq[EmailBodyPart]` in `subParts` is a value type under Nim's ARC memory
management. The recursive tree is fully immutable once constructed. This is
worth noting explicitly since recursive immutable trees are sometimes a concern
in other languages — in Nim with ARC, value semantics apply throughout.

---

## 8. Email Type and Creation Type

### 8.1. Decision

The Email data type is split into three distinct types:
- `Email` — read model for server responses (store-backed)
- `ParsedEmail` — read model for `Email/parse` responses (blob-backed, no metadata)
- `EmailBlueprint` — creation model for `Email/set` create (validated, body-kind discriminated)

### 8.2. Email (Read Model)

```nim
type Email* = object
  # Metadata (immutable, server-set or creation-only)
  id*: Id
  blobId*: Id
  threadId*: Id
  mailboxIds*: MailboxIdSet          # distinct HashSet[Id], not Table
  keywords*: KeywordSet              # distinct HashSet[Keyword]
  size*: UnsignedInt
  receivedAt*: UTCDate

  # Convenience header fields (first-class, always parsed when present)
  messageId*: Opt[seq[string]]
  inReplyTo*: Opt[seq[string]]
  references*: Opt[seq[string]]
  sender*: Opt[seq[EmailAddress]]
  fromAddr*: Opt[seq[EmailAddress]]  # 'from' is Nim keyword
  to*: Opt[seq[EmailAddress]]
  cc*: Opt[seq[EmailAddress]]
  bcc*: Opt[seq[EmailAddress]]
  replyTo*: Opt[seq[EmailAddress]]
  subject*: Opt[string]
  sentAt*: Opt[Date]

  # Raw headers (escape hatch)
  headers*: Opt[seq[EmailHeader]]

  # Requested parsed header views
  requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
  requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]

  # Body (all Opt — client controls which are returned)
  bodyStructure*: Opt[EmailBodyPart]
  bodyValues*: Opt[Table[PartId, EmailBodyValue]]
  textBody*: Opt[seq[EmailBodyPart]]     # leaf parts only, guaranteed by construction
  htmlBody*: Opt[seq[EmailBodyPart]]     # leaf parts only, guaranteed by construction
  attachments*: Opt[seq[EmailBodyPart]]  # leaf parts only, guaranteed by construction
  hasAttachment*: Opt[bool]
  preview*: Opt[string]
```

**Key design notes:**

- **`MailboxIdSet`** instead of `Table[Id, bool]` — same principle as
  `KeywordSet`. The `bool` carries no information (RFC mandates always
  `true`). The domain model doesn't mirror the wire format; the serde layer
  handles the `Table[Id, bool]` JSON representation.

- **`fromAddr`** — avoids the `from` keyword collision. The same naming
  convention is applied consistently to `EmailFilterCondition.fromAddr`.

- **All body list fields** (`textBody`, `htmlBody`, `attachments`) are
  guaranteed to contain only leaf parts by the serde layer's smart
  constructor.

- **Email mutability:** Only `mailboxIds` and `keywords` are mutable after
  creation. Everything else is immutable. This is enforced by `Email/set` —
  the builder for Email updates accepts only `mailboxIds` and `keywords`
  patches, not by the `Email` type itself (which is a read model).

### 8.3. ParsedEmail

A distinct type from store-backed `Email`. Metadata fields that are
structurally absent on a parsed blob (from `Email/parse`) are not present
on the type, rather than being `Opt.none` on a shared type.

```nim
type ParsedEmail* = object
  # Metadata — structurally different from store Email
  threadId*: Opt[Id]               # may be null if server can't determine

  # Header fields — same structure as Email
  messageId*: Opt[seq[string]]
  inReplyTo*: Opt[seq[string]]
  references*: Opt[seq[string]]
  sender*: Opt[seq[EmailAddress]]
  fromAddr*: Opt[seq[EmailAddress]]
  to*: Opt[seq[EmailAddress]]
  cc*: Opt[seq[EmailAddress]]
  bcc*: Opt[seq[EmailAddress]]
  replyTo*: Opt[seq[EmailAddress]]
  subject*: Opt[string]
  sentAt*: Opt[Date]

  # Headers and body — same structure as Email
  headers*: Opt[seq[EmailHeader]]
  requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
  requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]
  bodyStructure*: Opt[EmailBodyPart]
  bodyValues*: Opt[Table[PartId, EmailBodyValue]]
  textBody*: Opt[seq[EmailBodyPart]]
  htmlBody*: Opt[seq[EmailBodyPart]]
  attachments*: Opt[seq[EmailBodyPart]]
  hasAttachment*: Opt[bool]
  preview*: Opt[string]
```

**Principles:**
- **Parse, don't validate** — These aren't "optional in the normal sense";
  they're "structurally absent because this is a parsed blob, not a store
  object." A distinct type makes this semantic difference visible.
- **DDD** — A "parsed blob" and a "stored email" are different aggregates
  with different invariants. Collapsing them into one type with "some fields
  are always none" is a modelling compromise that obscures the domain.

**Conscious trade-off:** The header and body fields are duplicated between
`Email` and `ParsedEmail`. This is acceptable because the `Opt` wrapping and
differing metadata fields make a shared base type impractical without
sacrificing type safety. The duplication is structural, not behavioural.

### 8.4. EmailBlueprint (Creation Model)

The name `EmailBlueprint` conveys "a complete, validated email specification
ready for submission to the server" — a domain concept, not a lifecycle
annotation. Names like `EmailForCreate` describe when it's used; `EmailBlueprint`
describes what it is.

```nim
type EmailBodyKind* = enum
  ebkStructured    # client provides full bodyStructure tree
  ebkFlat          # client provides textBody/htmlBody/attachments

type EmailBlueprint* = object
  mailboxIds*: MailboxIdSet          # required, at least one
  keywords*: KeywordSet              # default: empty
  receivedAt*: Opt[UTCDate]          # default: server time

  # Header fields (convenience typed properties)
  fromAddr*: Opt[seq[EmailAddress]]
  to*: Opt[seq[EmailAddress]]
  cc*: Opt[seq[EmailAddress]]
  bcc*: Opt[seq[EmailAddress]]
  replyTo*: Opt[seq[EmailAddress]]
  sender*: Opt[seq[EmailAddress]]
  subject*: Opt[string]
  sentAt*: Opt[Date]
  messageId*: Opt[seq[string]]
  inReplyTo*: Opt[seq[string]]
  references*: Opt[seq[string]]

  # Additional headers (dynamic, validated form-per-header)
  extraHeaders*: Table[HeaderPropertyKey, HeaderValue]

  # Body — case discriminant enforces "either/or, never both"
  case bodyKind*: EmailBodyKind
  of ebkStructured:
    bodyStructure*: EmailBodyPart
  of ebkFlat:
    textBody*: Opt[EmailBodyPart]       # at most one text/plain (singular, not seq)
    htmlBody*: Opt[EmailBodyPart]       # at most one text/html (singular, not seq)
    attachments*: seq[EmailBodyPart]    # zero or more
    bodyValues*: Table[PartId, EmailBodyValue]
```

**Key design decisions:**

- **Body-kind discriminant** — The RFC says you can provide either
  `bodyStructure` or `textBody`/`htmlBody`/`attachments`, never both. The
  case object makes this a compile-time constraint: `ebkStructured` has one
  field, `ebkFlat` has the others. The compiler prevents the "never both"
  violation.

- **Singular `textBody`/`htmlBody`** — The RFC allows at most one
  `text/plain` part in `textBody` and at most one `text/html` part in
  `htmlBody` on creation. Either may be omitted (a text-only email has
  no `htmlBody`; an HTML-only email has no `textBody`). `Opt[EmailBodyPart]`
  captures this: optional, but when present exactly one (not `seq`).
  `attachments` remains `seq` (zero-or-more).

- **`MailboxIdSet` with at least one** — The "must belong to at least one
  mailbox" invariant is enforced by the smart constructor.

### 8.5. EmailBlueprint Smart Constructor

Returns `Result[EmailBlueprint, seq[ValidationError]]` — collects all
constraint violations, not short-circuits on the first one. A caller with
three problems learns about all three at once.

RFC 8621 §4.6 constraints enforced:

1. `mailboxIds` must contain at least one entry
2. No `headers` property directly — individual header fields only (enforced
   by type: `EmailBlueprint` has no `headers: seq[EmailHeader]` field)
3. No duplicate header representations — can't set both `fromAddr` and
   `extraHeaders` with `header:From:asAddresses`
4. Content-* headers only permitted on `EmailBodyPart`, not at top level
   via `extraHeaders`
5. `ebkFlat`: when present, `textBody` must be `text/plain`; `htmlBody` must
   be `text/html`; at least one of `textBody`/`htmlBody` must be present
6. `bodyValues` entries: `isEncodingProblem` and `isTruncated` must both
   be `false`
7. Allowed header forms validated against `AllowedHeaderForms` const table

**Validation errors are specific and actionable:**
- `"duplicate header representation: both 'fromAddr' and extraHeader 'header:From:asAddresses' specified"`
- `"Content-Transfer-Encoding header not permitted on EmailBlueprint top-level"`
- `"ebkFlat textBody must be text/plain, found text/html"`

**Principles:**
- **Make illegal states unrepresentable** — The body-kind discriminant and
  singular fields eliminate multiple constraint classes at the type level.
  The smart constructor handles the remaining constraints that can't be
  encoded structurally.
- **Total functions** — Accumulates all errors. Every input maps to
  `ok(EmailBlueprint)` or `err(seq[ValidationError])`.
- **Railway-Oriented Programming** — The accumulating error pattern stays on
  the same railway. A single call returns the complete error picture.
- **Immutability by default** — Constructed once via smart constructor, never
  modified. Builder takes `EmailBlueprint` by value.

### 8.6. EmailBlueprint Scoping

`EmailBlueprint` is only for `Email/set` create. `Email/import` has its own
simpler type (`EmailImportItem` — see §10.1) with `blobId`, `mailboxIds`,
`keywords`, `receivedAt`. The two operations have different semantics (create
from parts vs import from uploaded blob) and deserve separate types.

**Principle:** DDD — different domain operations deserve different types, even
when inputs partially overlap.

---

## 9. Entity-Specific Builder Overloads

### 9.1. Decision

For each entity whose standard method has extra parameters, provide a named
builder function in the mail module. Entities without extensions use the core
generic builder unchanged. Entity-specific overloads return entity-specific
response types when the response shape differs.

### 9.2. Pattern

All entity-specific builder overloads:
- Live in `mail_builders.nim` (Layer 3, mail module)
- Call core's internal `addInvocation` to accumulate the `Invocation`
- Return `ResponseHandle[T]` with the appropriate response type
- Are `func` (pure) — the one exception is when taking a
  `filterConditionToJson` callback, which forces `proc` (inherited
  constraint from core's `addQuery`, not a new one)

### 9.3. Overloads

**Email/get → `addEmailGet`:**
```nim
func addEmailGet*(b: var RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = ...,
    properties: Opt[seq[PropertyName]] = ...,   # PropertyName, not string
    bodyFetchOptions: EmailBodyFetchOptions = ...,
): ResponseHandle[EmailGetResponse]
```

Returns `ResponseHandle[EmailGetResponse]` — not `ResponseHandle[GetResponse[Email]]`
— because the response shape carries body-specific data controlled by the
request parameters.

**EmailBodyFetchOptions value object** (DRY — shared with `EmailParseRequest`):
```nim
type EmailBodyFetchOptions* = object
  bodyProperties*: Opt[seq[PropertyName]]
  fetchTextBodyValues*: bool           # default false
  fetchHTMLBodyValues*: bool           # default false
  fetchAllBodyValues*: bool            # default false
  maxBodyValueBytes*: Opt[UnsignedInt]
```

`fetchAllBodyValues` supersedes `fetchTextBodyValues`/`fetchHTMLBodyValues`
when `true`. Both can be set — this is redundant but valid per RFC. The builder
accepts both silently. Behaviour is defined and total.

**Mailbox/query → `addMailboxQuery`:**
```nim
func addMailboxQuery*(b: var RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[MailboxFilterCondition]] = ...,
    sort: Opt[seq[Comparator]] = ...,
    queryParams: QueryParams = ...,
    sortAsTree: bool = false,
    filterAsTree: bool = false,
): ResponseHandle[QueryResponse[Mailbox]]
```

**QueryParams value object** (DRY — shared across all query overloads):
```nim
type QueryParams* = object
  position*: JmapInt             # default 0
  anchor*: Opt[Id]
  anchorOffset*: JmapInt         # default 0
  limit*: Opt[UnsignedInt]
  calculateTotal*: bool          # default false
```

**Email/query → `addEmailQuery`:**
```nim
proc addEmailQuery*(b: var RequestBuilder,
    accountId: AccountId,
    filterConditionToJson: proc(c: EmailFilterCondition): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[EmailFilterCondition]] = ...,
    sort: Opt[seq[Comparator]] = ...,
    queryParams: QueryParams = ...,
    collapseThreads: bool = false,
): ResponseHandle[QueryResponse[Email]]
```

`proc` not `func` due to callback parameter — inherited constraint, documented.

**Email/queryChanges → `addEmailQueryChanges`:**
Adds `collapseThreads` to standard `/queryChanges` parameters.

**Email/copy → `addEmailCopy` / `addEmailCopyChained`:**
Adds `onSuccessDestroyOriginal` and `destroyFromIfInState` to standard `/copy`
parameters. `addEmailCopyChained` returns `EmailCopyHandles` — see §11.10 for
compound handle details.

**Mailbox/changes → `addMailboxChanges`:**
Returns `ResponseHandle[MailboxChangesResponse]` with the extra
`updatedProperties: Opt[seq[string]]` field.

**Mailbox/set → `addMailboxSet`:**
```nim
func addMailboxSet*(b: var RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = ...,
    create: Opt[Table[CreationId, Mailbox]] = ...,
    update: Opt[Table[Id, PatchObject]] = ...,
    destroy: Opt[seq[Id]] = ...,
    onDestroyRemoveEmails: bool = false,
): ResponseHandle[SetResponse[Mailbox]]
```

`onDestroyRemoveEmails` (RFC 8621 §2.5): when `true`, emails solely in a
destroyed mailbox are also destroyed. When `false` (default), the server
returns a `mailboxHasEmail` SetError for non-empty mailboxes.

**VacationResponse/set → `addVacationResponseSet`:**
```nim
func addVacationResponseSet*(b: var RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = ...,
    update: Table[Id, PatchObject],     # only update, no create/destroy
): ResponseHandle[SetResponse[VacationResponse]]
```

No `create`/`destroy` parameters — the RFC forbids both for the singleton.
A compile-time constraint, not a runtime error from the server.

**Principle:** Make illegal states unrepresentable — the overload's signature
prevents create/destroy attempts.

### 9.4. Entities Using Generic Builder Unchanged

- `addGet[Thread]`, `addChanges[Thread]`
- `addGet[Identity]`, `addChanges[Identity]`, `addSet[Identity]`

These have no entity-specific extensions and use core's generic builder
directly.

### 9.5. Dispatch Confirmation

Entity-specific response types (`EmailGetResponse`, `MailboxChangesResponse`)
work with the existing phantom-typed dispatch. The railway from
`ResponseHandle[EmailGetResponse]` through `get[EmailGetResponse]` to
`Result[EmailGetResponse, MethodError]` uses the same mechanism as core's
generic dispatch — no core modifications required.

**Principle:** DRY — core provides the dispatch mechanism, mail provides the
types. The phantom type parameterisation handles the rest.

---

## 10. Custom Methods

### 10.1. Decision

Non-standard methods (`Email/import`, `Email/parse`, `SearchSnippet/get`)
get custom builder functions in `mail_methods.nim` with bespoke request/response
types. They compose with the existing builder infrastructure (addInvocation,
ResponseHandle, get[T]) without modifying core.

### 10.2. Options Analysed

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Custom builder functions** | Standalone functions with bespoke types, calling core's `addInvocation`. | Type-safe, discoverable. ResponseHandle[T] phantom typing prevents wrong extraction. No core changes. |
| **B) Extend core builder** | Generic "custom method" support in Layer 3. | Over-engineering for three methods. Adds complexity to core without proportional benefit. |

**Decision: Option A.**

**Principles:**
- **DDD** — These methods belong to the mail domain, not core. Core provides
  the generic mechanism; mail provides the domain-specific methods.
- **Make illegal states unrepresentable** — `addEmailImport` returns
  `ResponseHandle[EmailImportResponse]`, not `ResponseHandle[GetResponse[Email]]`.
  The phantom type prevents wrong extraction at compile time.
- **Total functions** — Builder functions return `ResponseHandle[T]`
  (infallible). `get[T]` returns `Result[T, MethodError]` (total).
- **Railway-Oriented Programming** — Track 0 (construction), Track 1
  (transport), Track 2 (method errors) all work unchanged.

### 10.3. Email/import

**Request types:**
```nim
type EmailImportItem* = object
  blobId*: Id
  mailboxIds*: MailboxIdSet       # at least one (smart constructor enforces)
  keywords*: KeywordSet           # default: empty
  receivedAt*: Opt[UTCDate]       # default: server time

type EmailImportRequest* = object
  accountId*: AccountId
  ifInState*: Opt[JmapState]
  emails*: Table[CreationId, EmailImportItem]  # non-empty (smart constructor)
```

**Response type:**
```nim
type EmailImportResponse* = object
  accountId*: AccountId
  oldState*: Opt[JmapState]
  newState*: JmapState
  created*: Opt[Table[CreationId, Email]]
  notCreated*: Opt[Table[CreationId, SetError]]
```

**Builder:** `addEmailImport(b, accountId, emails, ifInState) → ResponseHandle[EmailImportResponse]`

`EmailImportItem` has its own smart constructor enforcing the "at least one
mailbox" invariant. `EmailImportRequest` requires non-empty `emails` table.
Both accumulate validation errors.

### 10.4. Email/parse

**Request type:**
```nim
type EmailParseRequest* = object
  accountId*: AccountId
  blobIds*: seq[Id]                        # non-empty (smart constructor)
  bodyFetchOptions*: EmailBodyFetchOptions  # shared with addEmailGet (DRY)
  properties*: Opt[seq[PropertyName]]
```

**Response type:**
```nim
type EmailParseResponse* = object
  accountId*: AccountId
  parsed*: Opt[Table[Id, ParsedEmail]]    # blobId → ParsedEmail (not Email)
  notParseable*: Opt[seq[Id]]
  notFound*: Opt[seq[Id]]                 # blobIds not found on the server
```

**Builder:** `addEmailParse(b, accountId, blobIds, ...) → ResponseHandle[EmailParseResponse]`

Returns `ParsedEmail` (not `Email`) — different aggregate, different invariants
(see §8.3).

### 10.5. SearchSnippet/get

**Request type:**
```nim
type SearchSnippetGetRequest* = object
  accountId*: AccountId
  filter*: Filter[EmailFilterCondition]   # required, not Opt
  emailIds*: seq[Id]                       # non-empty (smart constructor)
```

**Response type:**
```nim
type SearchSnippetGetResponse* = object
  accountId*: AccountId
  list*: seq[SearchSnippet]
  notFound*: Opt[seq[Id]]
  # No state field — stateless by design
```

**Builder:** `addSearchSnippetGet(b, accountId, emailIds, filter) → ResponseHandle[SearchSnippetGetResponse]`

Key differences from standard `/get`:
- `filter` is required (not optional)
- No `state` in response — stateless derived data
- `SearchSnippet` has no `id` property (keyed by `emailId`)

**Non-empty enforcement:** `emailIds` must contain at least one entry — empty
is a meaningless request. Smart constructor rejects.

**Duplicate emailIds:** Passed through to server (which handles deduplication
per RFC). Builder behaviour is defined and total.

**Method-level errors:** `requestTooLarge` and `unsupportedFilter` are core
`MethodErrorType` variants (defined in RFC 8620's error space). No
mail-specific error classification needed; standard
`Result[T, MethodError]` railway.

### 10.6. Railway Consistency

Across all three custom methods:
- Builder functions return `ResponseHandle[T]` (infallible)
- `get[T](response, handle)` returns `Result[T, MethodError]`
- Response types carry per-item errors as data (`notCreated`, `notParseable`,
  `notFound`) on the success rail
- Smart constructors on request types accumulate errors
  (`Result[T, seq[ValidationError]]`)
- All types are immutable value objects, constructed once and passed by value

---

## 11. Compound Handles

### 11.1. Decision

Two methods produce implicit `Email/set` responses alongside their primary
response, requiring compound handles:

**EmailSubmission/set:** Two overloads distinguished by name:
- `addEmailSubmissionSet` — standard `/set`, returns single handle
- `addEmailSubmissionSetChained` — with `onSuccess*` parameters, returns
  compound handles

**Email/copy:** Two overloads distinguished by name (§11.10):
- `addEmailCopy` — standard `/copy`, returns single handle
- `addEmailCopyChained` — with `onSuccessDestroyOriginal`, returns compound
  handles

Both follow the compound handle pattern established by `QueryGetHandles[T]`
in the convenience layer.

### 11.2. Options Analysed

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Model in request, explicit helper for response** | Builder serialises `onSuccess*` params. Separate helper `getImplicitEmailSet` locates the implicit response. | Keeps one-method-one-handle model. But the caller must know to call a separate helper. |
| **B) Compound handle type** | Builder returns `EmailSubmissionSetHandles` with both handles when chaining. Matches `QueryGetHandles` pattern. | Type system tells you there are two responses. Established precedent. |
| **Modified B) Overloaded by operation** | Two function names: plain returns single handle, chained returns compound. Return type reflects what the protocol produces. | Explicit intent. Same precedent as `addQueryThenGet` vs `addQuery`. |

**Decision: Modified B.**

**Principles:**
- **DDD** — Two separate function names represent different domain operations:
  "submit email" vs "submit email and apply side-effects on success." Different
  operations deserve different names, even if the wire protocol bundles them
  into one method.
- **Make illegal states unrepresentable** — `addEmailSubmissionSetChained`
  requires at least one of `onSuccessUpdateEmail`/`onSuccessDestroyEmail` to
  be non-empty. If both are empty, it's the wrong overload. Smart constructor
  enforces.

### 11.3. Type Definitions

```nim
type EmailSubmissionSetHandles* = object
  submission*: ResponseHandle[SetResponse[EmailSubmission]]
  implicitEmailSet*: ResponseHandle[SetResponse[Email]]

type EmailSubmissionSetResults* = object
  submission*: SetResponse[EmailSubmission]
  emailSet*: SetResponse[Email]
```

### 11.4. Simple Overload

```nim
func addEmailSubmissionSet*(b: var RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = ...,
    create: Opt[Table[CreationId, EmailSubmission]] = ...,
    update: Opt[Table[Id, PatchObject]] = ...,
    destroy: Opt[seq[Id]] = ...,
): ResponseHandle[SetResponse[EmailSubmission]]
```

### 11.5. Chained Overload

```nim
func addEmailSubmissionSetChained*(b: var RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = ...,
    create: Opt[Table[CreationId, EmailSubmission]] = ...,
    update: Opt[Table[Id, PatchObject]] = ...,
    destroy: Opt[seq[Id]] = ...,
    onSuccessUpdateEmail: Opt[Table[SubmissionEmailRef, PatchObject]] = ...,
    onSuccessDestroyEmail: Opt[seq[SubmissionEmailRef]] = ...,
): EmailSubmissionSetHandles
```

### 11.6. SubmissionEmailRef

Keys in `onSuccessUpdateEmail` are either creation references (`#creationId`)
or direct Email ids. A structured type makes this explicit:

```nim
type SubmissionEmailRefKind* = enum
  serDirect, serCreationRef

type SubmissionEmailRef* = object
  case kind*: SubmissionEmailRefKind
  of serDirect:
    id*: Id
  of serCreationRef:
    creationId*: CreationId
```

**Principles:**
- **Make illegal states unrepresentable** — Eliminates malformed `#`-prefixed
  strings at the type level.
- **Parse, don't validate** — Parsed from wire format (`"#foo"` →
  `serCreationRef(CreationId("foo"))`, `"msg123"` → `serDirect(Id("msg123"))`)
  at the serde boundary. After parsing, no code ever inspects string prefixes.

### 11.7. Response Location

Per RFC 8621 §7.5, the implicit `Email/set` response shares the same method
call id as the `EmailSubmission/set` response. Both handles carry the same
underlying `MethodCallId`. The `get[T]` dispatch distinguishes them by
response name — which it already does (the existing dispatch checks the method
name in the invocation tuple). No core changes needed.

### 11.8. getBoth

```nim
func getBoth*(resp: Response, handles: EmailSubmissionSetHandles,
): Result[EmailSubmissionSetResults, MethodError]
```

Must handle the case where the implicit `Email/set` response is absent (e.g.,
all submissions failed). Returns `Result` with `MethodError`, not assumes both
responses exist. Total over all possible response shapes.

**Principles:**
- **Total functions** — Defines behaviour for every response shape, including
  absent implicit response.
- **Railway-Oriented Programming** — First error from either response
  short-circuits. The railway doesn't fork; sequential extraction on the
  same rail.

### 11.9. DRY Consideration

Three compound-handle types now exist: `QueryGetHandles[T]` (convenience
layer), `EmailSubmissionSetHandles` (§11.3), and `EmailCopyHandles` (§11.10).
Evaluate during implementation whether the three instances share enough
structure to justify a generic `CompoundHandles[A, B]` with a generic
`getBoth`.

### 11.10. Email/copy Compound Handle

RFC 8621 §4.7 defines `onSuccessDestroyOriginal: bool` on `Email/copy`. When
`true`, the server destroys the original in the source account after successful
copy and produces an implicit `Email/set` destroy response with the same method
call id.

```nim
type EmailCopyHandles* = object
  copy*: ResponseHandle[CopyResponse[Email]]
  implicitEmailSet*: ResponseHandle[SetResponse[Email]]

type EmailCopyResults* = object
  copy*: CopyResponse[Email]
  emailSet*: SetResponse[Email]
```

Two overloads, same pattern as EmailSubmission (§11.4–11.5):

- `addEmailCopy` — standard `/copy` with `onSuccessDestroyOriginal` defaulting
  to `false`, returns `ResponseHandle[CopyResponse[Email]]`
- `addEmailCopyChained` — always sets `onSuccessDestroyOriginal: true`, returns
  `EmailCopyHandles`

`addEmailCopyChained` adds `destroyFromIfInState: Opt[JmapState]` (state
assertion for the source account destroy). Both overloads add the standard
`Email/copy` parameters (`fromAccountId`, `ifFromInState`, `ifInState`,
`create`).

`getBoth` extracts both responses, handling the absent implicit response case
(all copies failed). Response location uses method name dispatch (§11.7).

**Principles:**
- **DDD** — Different function names for different domain operations.
- **Make illegal states unrepresentable** — The chained overload always destroys
  the original. The return type tells you there are two responses to handle.

---

## 12. Filter Conditions

### 12.1. Decision

Three filter condition types, one per queryable entity. Filter conditions are
query specifications (value objects), not domain entities — they don't need
smart constructors beyond what types enforce, with one exception
(`EmailHeaderFilter`).

### 12.2. Options Analysed

No option analysis needed — the approach follows directly from the existing
`Filter[C]` generic in core. The design decisions are about the condition
types themselves and their field types.

### 12.3. MailboxFilterCondition

```nim
type MailboxFilterCondition* = object
  parentId*: Opt[Opt[Id]]        # three-state: absent / null / value
  name*: Opt[string]             # contains match
  role*: Opt[Opt[string]]        # three-state: absent / null / value
  hasAnyRole*: Opt[bool]
  isSubscribed*: Opt[bool]
```

**The `Opt[Opt[T]]` pattern:** RFC 8621 distinguishes between "this filter
property is not specified" (omit from JSON) and "this filter property matches
null" (include as `null` in JSON). For `parentId` and `role`, `null` is a
meaningful filter value (top-level mailboxes, no-role mailboxes):
- `Opt.none` = not filtering on this property
- `Opt.some(Opt.none)` = filtering for null
- `Opt.some(Opt.some(value))` = filtering for specific value

The double-wrapping looks unusual but encodes a real three-state domain.

### 12.4. EmailFilterCondition

```nim
type EmailFilterCondition* = object
  inMailbox*: Opt[Id]
  inMailboxOtherThan*: Opt[seq[Id]]       # non-empty when present
  before*: Opt[UTCDate]
  after*: Opt[UTCDate]
  minSize*: Opt[UnsignedInt]
  maxSize*: Opt[UnsignedInt]
  allInThreadHaveKeyword*: Opt[Keyword]
  someInThreadHaveKeyword*: Opt[Keyword]
  noneInThreadHaveKeyword*: Opt[Keyword]
  hasKeyword*: Opt[Keyword]
  notKeyword*: Opt[Keyword]
  hasAttachment*: Opt[bool]
  text*: Opt[string]
  fromAddr*: Opt[string]                  # consistent with Email.fromAddr naming
  to*: Opt[string]
  cc*: Opt[string]
  bcc*: Opt[string]
  subject*: Opt[string]
  body*: Opt[string]
  header*: Opt[EmailHeaderFilter]
```

**`fromAddr`** — consistent naming with `Email.fromAddr` for the `from`
keyword collision. Applied everywhere.

**`Keyword` type on filter fields** — `hasKeyword`, `notKeyword`, etc. use
`Opt[Keyword]`, not `Opt[string]`. The `Keyword` type provides validation.
No per-field validation needed.

**`inMailboxOtherThan`** — when present, must be non-empty (empty exclusion
is a no-op). Validated at construction or documented as contract.

### 12.5. EmailHeaderFilter

The RFC's `header` filter takes a `String[]` of 1–2 elements. A structured
type eliminates empty arrays, 3+ elements, and untyped positional semantics:

```nim
type EmailHeaderFilter* = object
  name*: string                  # required, non-empty
  value*: Opt[string]            # optional value to match
```

**This is the one filter type that needs a smart constructor** — `name` must
be non-empty.

**Principle:** Make illegal states unrepresentable — structured type instead
of `String[]` with positional semantics.

### 12.6. EmailSubmissionFilterCondition

```nim
type EmailSubmissionFilterCondition* = object
  identityIds*: Opt[seq[Id]]     # non-empty when present
  emailIds*: Opt[seq[Id]]        # non-empty when present
  threadIds*: Opt[seq[Id]]       # non-empty when present
  undoStatus*: Opt[UndoStatus]   # enum, not string
  before*: Opt[UTCDate]
  after*: Opt[UTCDate]
```

**`UndoStatus` enum:**
```nim
type UndoStatus* = enum
  usPending = "pending"
  usFinal = "final"
  usCanceled = "canceled"
  usUnknown
```

Defined in `submission.nim` (alongside the entity, not the filter module).
Used by both `EmailSubmission.undoStatus` and the filter condition. The filter
module imports it.

**Principles:**
- **Make illegal states unrepresentable** — `Opt[UndoStatus]` instead of
  `Opt[string]`. Constrains to the three valid states plus `usUnknown` for
  forward compatibility.
- **DDD** — `UndoStatus` models a real domain concept (lifecycle state of a
  submission). It belongs with the entity definition.

### 12.7. Opt[Opt[T]] Serde Three-Way Dispatch

The `Opt[Opt[T]]` deserialisation for `parentId` and `role` requires explicit
three-way dispatch:
- Absent key in JSON → `Opt.none` (not filtering)
- Present key with `null` value → `Opt.some(Opt.none)` (filtering for null)
- Present key with value → `Opt.some(Opt.some(parsed))` (filtering for value)

This must be explicitly implemented and thoroughly tested in
`serde_mail_filters.nim`.

### 12.8. Filter Conditions as Value Objects

Filter conditions are query specifications, not domain entities:
- They describe criteria, they have no identity, they're equal by structure
- They don't need id fields or smart constructors beyond what the types enforce
- Construction is infallible (all fields are `Opt` — assembling a query, not
  validating data)
- The railway matters at the serde boundary (`fromJson` returns `Result`), not
  at the construction boundary

The one exception is `EmailHeaderFilter`, which needs a smart constructor for
the non-empty name constraint.

**Principles:**
- **DDD** — Value objects, not entities.
- **Railway-Oriented Programming** — Construction is infallible. The railway
  applies at the serde boundary where JSON is parsed into these types.

### 12.9. Integration with Filter[C]

These plug directly into core's `Filter[C]` generic:
- `Filter[MailboxFilterCondition]` for `addMailboxQuery`
- `Filter[EmailFilterCondition]` for `addEmailQuery` and `addSearchSnippetGet`
- `Filter[EmailSubmissionFilterCondition]` for `addEmailSubmissionQuery`

Core provides the recursive tree structure (`Filter[C]`, `FilterOperator`).
Mail provides the condition types and their `toJson` callbacks. The `toJson`
callbacks are `func` (pure, `{.noSideEffect.}`).

### 12.10. DRY Considerations

- `before: Opt[UTCDate]` / `after: Opt[UTCDate]` appear on both
  `EmailFilterCondition` and `EmailSubmissionFilterCondition`. A `DateRange`
  value object could be shared. Noted as potential extraction — deferred
  unless the pattern appears a third time.
- Keyword filter fields (`hasKeyword`, `notKeyword`,
  `allInThreadHaveKeyword`, `someInThreadHaveKeyword`,
  `noneInThreadHaveKeyword`) all use `Opt[Keyword]` — the `Keyword` type
  itself provides the DRY validation.

---

## 13. Per-Entity Summary

Quick reference for each entity's methods, key properties, and design notes.

### 13.1. Mailbox

| Aspect | Detail |
|--------|--------|
| Module | `mailbox.nim` |
| Methods | `/get`, `/changes` (extra: `updatedProperties`), `/query` (extra: `sortAsTree`, `filterAsTree`), `/queryChanges`, `/set` (extra: `onDestroyRemoveEmails`) |
| Key sub-types | `MailboxRights` (9 boolean fields), `MailboxIdSet` (distinct `HashSet[Id]`) |
| Filter conditions | `MailboxFilterCondition` — `parentId`, `name`, `role`, `hasAnyRole`, `isSubscribed` |
| Sort properties | `sortOrder`, `name` |
| Builder overloads | `addMailboxQuery` (sortAsTree, filterAsTree), `addMailboxChanges` (returns `MailboxChangesResponse`), `addMailboxSet` (onDestroyRemoveEmails) |
| Roles | From IANA registry, lowercase. One role per mailbox, one mailbox per role per account. |
| Design notes | `MailboxIdSet` on Email uses same set pattern as `KeywordSet`. Mailbox roles are strings (not enum) since the registry is open-ended. |

### 13.2. Thread

| Aspect | Detail |
|--------|--------|
| Module | `thread.nim` |
| Methods | `/get`, `/changes` |
| Properties | `id: Id`, `emailIds: seq[Id]` (sorted by `receivedAt`) |
| Builder | Uses generic `addGet[Thread]`, `addChanges[Thread]` — no extensions |
| Design notes | Simplest entity. No filter, no query, no set. |

### 13.3. Email

| Aspect | Detail |
|--------|--------|
| Module | `email.nim` |
| Types | `Email` (read model), `ParsedEmail` (blob-backed), `EmailBlueprint` (creation) |
| Methods | `/get` (extra: body fetch options), `/changes`, `/query` (extra: `collapseThreads`), `/queryChanges` (extra: `collapseThreads`), `/set`, `/copy` (extra: `onSuccessDestroyOriginal`), `/import`, `/parse` |
| Key sub-types | `EmailAddress`, `EmailAddressGroup`, `EmailHeader`, `HeaderPropertyKey`, `HeaderValue`, `EmailBodyPart`, `EmailBodyValue`, `PartId`, `KeywordSet`, `MailboxIdSet` |
| Filter conditions | `EmailFilterCondition` — 19 fields including thread-keyword filters, header filter |
| Sort properties | `receivedAt` (must), `size`, `from`, `to`, `subject`, `sentAt`, `hasKeyword`, `allInThreadHaveKeyword`, `someInThreadHaveKeyword` (should) |
| Builder overloads | `addEmailGet`, `addEmailQuery`, `addEmailQueryChanges`, `addEmailCopy`/`addEmailCopyChained` (compound handle, §11.10) |
| Custom methods | `addEmailImport`, `addEmailParse` |
| Mutability | Only `mailboxIds` and `keywords` mutable after creation |
| Design notes | Most complex entity. Three distinct types for read/parse/create models. Body-kind case discriminant on blueprint. |

### 13.4. SearchSnippet

| Aspect | Detail |
|--------|--------|
| Module | `snippet.nim` |
| Properties | `emailId: Id`, `subject: Opt[string]`, `preview: Opt[string]` |
| Methods | Custom `/get` variant (required filter, no state) |
| Custom method | `addSearchSnippetGet` |
| Design notes | No `id` property. Stateless derived data. Uses `Filter[EmailFilterCondition]` (same as Email/query). Subject/preview contain HTML `<mark>` tags. |

### 13.5. Identity

| Aspect | Detail |
|--------|--------|
| Module | `identity.nim` |
| Methods | `/get`, `/changes`, `/set` |
| Properties | `id`, `name`, `email` (immutable), `replyTo`, `bcc`, `textSignature`, `htmlSignature`, `mayDelete` (server-set) |
| Builder | Uses generic builder — no extensions |
| Design notes | Simple entity. `email` is immutable after creation. |

### 13.6. EmailSubmission

| Aspect | Detail |
|--------|--------|
| Module | `submission.nim` |
| Types | `EmailSubmission`, `Envelope`, `Address`, `DeliveryStatus`, `UndoStatus`, `SubmissionEmailRef` |
| Methods | `/get`, `/changes`, `/query`, `/queryChanges`, `/set` (with implicit chaining) |
| Filter conditions | `EmailSubmissionFilterCondition` — `identityIds`, `emailIds`, `threadIds`, `undoStatus`, date range |
| Sort properties | `emailId`, `threadId`, `sentAt` (all must support) |
| Builder overloads | `addEmailSubmissionSet` (plain), `addEmailSubmissionSetChained` (compound handles) |
| Design notes | Implicit `Email/set` chaining is the trickiest protocol feature. `SubmissionEmailRef` case type for `#creationId` / direct id references. `UndoStatus` enum shared between entity and filter. |

### 13.7. VacationResponse

| Aspect | Detail |
|--------|--------|
| Module | `vacation.nim` |
| Methods | `/get`, `/set` (update only — no create, no destroy) |
| Properties | `id` (always "singleton"), `isEnabled`, `fromDate`, `toDate`, `subject`, `textBody`, `htmlBody` |
| Builder overload | `addVacationResponseSet` (update-only signature) |
| Design notes | Singleton pattern — exactly one per account, id always "singleton". Builder overload prevents create/destroy at compile time. |

---

## Appendix A: Decision Traceability Matrix

| # | Decision | Options | Chosen | Primary Principles |
|---|----------|---------|--------|-------------------|
| 1 | Module location | A) Flat, B) Nested `mail/`, C) Nested by layer | B | DDD, Open-Closed |
| 2 | Sub-type organisation | A) One shared module, B) By semantic domain, C) In parent entity | B (refined: addresses + headers + body) | DDD, SRP |
| 3 | Capabilities boundary | A) Typed variants on core, B) Raw + parse on demand | B | DDD, Parse-don't-validate, Open-Closed |
| 4 | Errors boundary | A) Extend core enum, B) String matching, C) Mail-layer enum | C | Make illegal states unrepresentable, ROP, Total functions |
| 5 | Method extensions | A) Mail builder functions, B) Core extras param | A | DDD, DRY, Immutability |
| 6 | Header parsed forms | A) JsonNode map, B) Typed HeaderValue, C) Convenience only | B + convenience fields | Parse-don't-validate, Make illegal states unrepresentable |
| 7 | Body structure | A) All optional, B) Case object by multipart, C) Separate types | B | Make illegal states unrepresentable, Parse-don't-validate, Total functions |
| 8 | Email creation type | Body-kind discriminant with singular fields | Case object `ebkStructured`/`ebkFlat` | Make illegal states unrepresentable, Total functions |
| 9 | Non-standard methods | A) Custom builder functions, B) Extend core builder | A | DDD, Make illegal states unrepresentable, ROP |
| 10 | EmailSubmission chaining | A) Explicit helper, B) Compound handle, Modified B) Overloaded by name | Modified B | DDD, Make illegal states unrepresentable |
| 11 | Keyword type | Distinct type with lowercase normalisation + system constants | `Keyword = distinct string` | Parse-don't-validate, Make illegal states unrepresentable, DRY |
| 12 | Email read model sets | `Table[K, bool]` vs `HashSet[K]` | `MailboxIdSet`, `KeywordSet` (distinct HashSet) | Make illegal states unrepresentable, DDD |
| 13 | ParsedEmail vs Email | Shared type with Opt.none vs distinct type | Distinct `ParsedEmail` | Parse-don't-validate, DDD |
| 14 | EmailBlueprint naming | Lifecycle name vs domain name | `EmailBlueprint` (domain concept) | DDD |
| 15 | EmailBlueprint errors | Short-circuit vs accumulate | `Result[T, seq[ValidationError]]` | Total functions, ROP |
| 16 | VacationResponse builder | Generic /set vs update-only overload | `addVacationResponseSet` (no create/destroy) | Make illegal states unrepresentable |
| 17 | QueryParams DRY | Repeated params vs value object | `QueryParams` value object | DRY |
| 18 | EmailBodyFetchOptions DRY | Repeated params vs value object | `EmailBodyFetchOptions` value object | DRY |
| 19 | SubmissionEmailRef | String with # prefix vs case type | Case type (`serDirect`/`serCreationRef`) | Make illegal states unrepresentable, Parse-don't-validate |
| 20 | UndoStatus | String vs enum | Enum in `submission.nim` | Make illegal states unrepresentable, DDD |
| 21 | Filter conditions as smart-constructed | Smart constructors vs plain construction | Plain construction (value objects, not entities). Exception: `EmailHeaderFilter` | DDD (value objects), ROP |
| 22 | Opt[Opt[T]] for null-filterable fields | Opt[T] vs Opt[Opt[T]] vs sentinel | `Opt[Opt[T]]` | Make illegal states unrepresentable |
| 23 | Mailbox/set builder overload | Generic /set vs entity-specific with onDestroyRemoveEmails | `addMailboxSet` with extra param | DDD, Make illegal states unrepresentable |
| 24 | Email/copy compound handle | Single handle vs compound (same as §11) | `addEmailCopy`/`addEmailCopyChained` | DDD, Make illegal states unrepresentable |
