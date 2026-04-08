# RFC 8621 JMAP Mail — Design C: Header and Body Sub-Types

This document is the detailed specification for the header and body sub-types
required by the Email entity — plus their serde modules. It covers Layers 1
and 2 (L1 types, L2 serde) for each type, cutting vertically through the
architecture.

Part C is a pure vocabulary document. It defines shared building blocks
consumed by Part D (Email entity, SearchSnippet) and beyond. No entity
registration, no builder functions, no filter conditions.

Builds on the cross-cutting architecture design (`05-mail-design.md`), the
existing RFC 8620 infrastructure (`00-architecture.md` through
`04-layer-4-design.md`), Design A (`06-mail-a-design.md`), and Design B
(`07-mail-b-design.md`). Decisions from the cross-cutting doc are referenced
by section number.

---

## Table of Contents

1. [Scope](#1-scope)
2. [Header Sub-Types — headers.nim](#2-header-sub-types--headersnim)
3. [Body Sub-Types — body.nim](#3-body-sub-types--bodynim)
4. [Test Specification](#4-test-specification)
5. [Decision Traceability Matrix](#5-decision-traceability-matrix)

---

## 1. Scope

### 1.1. Supporting Types Covered

| Type | Module | Rationale |
|------|--------|-----------|
| `HeaderForm` | `headers.nim` | Enum of RFC 8621 header parsed form suffixes |
| `EmailHeader` | `headers.nim` | Raw header name-value pair for MIME parts |
| `HeaderPropertyKey` | `headers.nim` | Structured key encoding header name + form + `:all` suffix |
| `HeaderValue` | `headers.nim` | Case object carrying parsed header content by form |
| `allowedForms` | `headers.nim` | Validation function for header-name-to-form constraints |
| `validateHeaderForm` | `headers.nim` | Domain validation composing `allowedForms` with `HeaderPropertyKey` |
| `PartId` | `body.nim` | Distinct string identifier for body parts within an Email |
| `EmailBodyPart` | `body.nim` | Recursive case object for MIME body structure (read model) |
| `EmailBodyValue` | `body.nim` | Decoded body text content with encoding/truncation flags |
| `BlueprintPartSource` | `body.nim` | Enum discriminant for creation body part source (inline vs blob) |
| `BlueprintBodyPart` | `body.nim` | Nested case object for creation body structure |

### 1.2. Deferred

Email (read model, parsed model, creation model), SearchSnippet,
EmailFilterCondition, EmailHeaderFilter, EmailComparator,
EmailBodyFetchOptions, and all Email builder functions are deferred to
Design D. EmailSubmission and all its sub-types are deferred to Design E.

### 1.3. Relationship to Cross-Cutting Design

This document refines `05-mail-design.md` into implementation-ready
specifications for the header and body bounded contexts.

### 1.4. Module Summary

All modules live under `src/jmap_client/mail/` per cross-cutting doc §3.3.

| Module | Layer | Contents |
|--------|-------|----------|
| `headers.nim` | L1 | `HeaderForm`, `EmailHeader`, `HeaderPropertyKey`, `HeaderValue`, `allowedForms`, `validateHeaderForm` |
| `body.nim` | L1 | `PartId`, `EmailBodyPart`, `EmailBodyValue`, `BlueprintPartSource`, `BlueprintBodyPart` |
| `serde_headers.nim` | L2 | `parseHeaderPropertyName`, `toPropertyString`, `parseHeaderValue`, `toJson`/`fromJson` for `HeaderValue` and `EmailHeader` |
| `serde_body.nim` | L2 | `toJson`/`fromJson` for `EmailBodyPart`, `fromJson`/`toJson` for `EmailBodyValue`, `toJson` for `BlueprintBodyPart`, `PartId` serde |

---

## 2. Header Sub-Types — headers.nim

**Module:** `src/jmap_client/mail/headers.nim`

Headers are a shared bounded context used by Email (convenience fields,
dynamic parsed headers, raw headers), EmailBodyPart (raw headers per MIME
part), and BlueprintBodyPart (extra headers on creation parts). All
header-related types live in `headers.nim` — the dependency graph shows
they are always co-required.

**Principles:** DDD (headers are their own bounded context), DRY (one
specification, referenced by multiple future consumers), Parse-don't-validate
(full parsing boundary defined now).

### 2.1. HeaderForm

**RFC reference:** §4.1.2.

`HeaderForm` is the set of parsed forms that RFC 8621 defines for header
property access. Each form determines how the server parses a header field
and what type the parsed value carries.

**Type definition:**

```nim
type HeaderForm* = enum
  hfRaw              = "asRaw"
  hfText             = "asText"
  hfAddresses        = "asAddresses"
  hfGroupedAddresses = "asGroupedAddresses"
  hfMessageIds       = "asMessageIds"
  hfDate             = "asDate"
  hfUrls             = "asURLs"
```

String-backed enum mapping to JMAP form suffixes. Enables
`strutils.parseEnum` for parsing form suffixes from property name strings.

**`nimIdentNormalize` compatibility:** Nim's `parseEnum` uses
`nimIdentNormalize` (case-insensitive after first character, underscores
stripped). The suffix `"asURLs"` normalises to `"asurls"`, and `hfUrls`
normalises to `"hfurls"` — these do not match because the enum value
string `"asURLs"` is compared literally, not through `nimIdentNormalize`.
`parseEnum` compares the input against each variant's string backing
directly (case-insensitive after first char). Verification during
implementation is required; a thin wrapper function handles any mismatch.

**Principles:**
- **DRY** — The mapping between enum variants and JMAP suffix strings
  lives in one place (the enum definition). `parseEnum` provides the parse
  function.
- **Code reads like the spec** — `hfAddresses = "asAddresses"` is
  self-documenting.
- **One source of truth per fact** — The string backing is the mapping.

### 2.2. EmailHeader

**RFC reference:** §4.1.2.

An `EmailHeader` represents a single raw RFC 5322 header field — a
name-value pair as provided by the server. Used by Email's `headers`
property and EmailBodyPart's `headers` field.

**Type definition:**

```nim
type EmailHeader* = object
  name*: string   ## non-empty (enforced by parseEmailHeader)
  value*: string  ## raw header value
```

Plain public fields. The `name` non-empty invariant is enforced by the
smart constructor, but `EmailHeader` is a simple value object — Pattern A
sealing would add accessor ceremony disproportionate to the risk.
Consistent with the `EmailAddress` pattern in Design A §2.1.

**Smart constructor:**

```nim
func parseEmailHeader*(
    name: string,
    value: string,
): Result[EmailHeader, ValidationError]
```

Validates: `name` non-empty. No format validation beyond non-empty — the
server provides arbitrary header names. Post-construction `doAssert`
verifies the invariant on the constructed value (`name.len > 0`).

**Principles:**
- **Parse, don't validate** — Smart constructor enforces non-empty name at
  the construction boundary.
- **Total functions** — Maps every input to `ok(EmailHeader)` or
  `err(ValidationError)`.

### 2.3. HeaderPropertyKey

**RFC reference:** §4.1.2.

A `HeaderPropertyKey` is a structured representation of a JMAP header
property name. It encodes the entire `header:Name:asForm:all` wire
structure — the `header:` prefix, a lowercase header name, a parsed form,
and an optional `:all` suffix.

**Module:** `src/jmap_client/mail/headers.nim`

**Type definition:**

**Pattern A (sealed fields)** — `HeaderPropertyKey` has real invariants:
name must be non-empty, and form must be a valid parsed form suffix. Sealing
prevents construction of a `HeaderPropertyKey` with empty name outside
`headers.nim`.

```nim
type HeaderPropertyKey* = object
  rawName: string       ## module-private, lowercase, non-empty
  rawForm: HeaderForm   ## module-private
  rawIsAll: bool        ## module-private
```

**Smart constructor:**

```nim
func parseHeaderPropertyName*(
    raw: string,
): Result[HeaderPropertyKey, ValidationError]
```

Accepts the full wire string including the `header:` prefix. Validates
structural correctness only:
- `header:` prefix present (required).
- Header name non-empty after prefix extraction.
- Form suffix, if present, is a valid `HeaderForm` string.
- `:all` suffix, if present, is in the correct position (after the form
  suffix or after the header name if no form suffix).
- **Normalises** the header name to lowercase during construction.
- Default form when no suffix is present: `hfRaw`.

Post-construction `doAssert` verifies `rawName.len > 0`.

The smart constructor does **not** validate that the form is allowed for the
given header name. That is domain validation (§2.6), not structural parsing.
The structural parser's concern is "is this a well-formed header property
name?" — not "does the RFC permit this combination?"

**Principles:**
- **Make illegal states unrepresentable** — Module-private fields + smart
  constructor guarantee non-empty name and valid form. Direct construction
  of `HeaderPropertyKey(rawName: "", ...)` is prevented outside
  `headers.nim`.
- **Parse, don't validate** — Normalises to lowercase canonical form.
  After construction, `==` just works everywhere. Same pattern as `Keyword`
  and `MailboxRole`.
- **Total functions** — Maps every input to `ok(HeaderPropertyKey)` or
  `err(ValidationError)`.

**Accessors:**

```nim
func name*(k: HeaderPropertyKey): string
func form*(k: HeaderPropertyKey): HeaderForm
func isAll*(k: HeaderPropertyKey): bool
```

UFCS accessors for sealed fields.

**Serialisation to wire string:**

```nim
func toPropertyString*(k: HeaderPropertyKey): string
```

Reconstructs the full wire string from its component sources of truth:
`"header:"` literal + lowercase name (from `rawName`) + `$form` (from
enum string backing, e.g., `"asAddresses"`) + `":all"` (from `rawIsAll`
bool). Each component is sourced from its own field — no original casing
stored, no round-trip fidelity concern. The canonical form IS the domain
truth, and the wire format is case-insensitive.

When form is `hfRaw`, the form suffix is omitted (the default form is
`hfRaw`, and omitting it produces the shortest canonical representation).

### 2.4. HeaderValue

**RFC reference:** §4.1.2.

A `HeaderValue` carries parsed header content, discriminated by
`HeaderForm`. Each variant holds exactly the type that the corresponding
form produces — the case object makes illegal states unrepresentable.

**Type definition:**

```nim
type HeaderValue* = object
  case form*: HeaderForm
  of hfRaw:              rawValue*: string
  of hfText:             textValue*: string
  of hfAddresses:        addresses*: seq[EmailAddress]
  of hfGroupedAddresses: groups*: seq[EmailAddressGroup]
  of hfMessageIds:       messageIds*: Opt[seq[string]]
  of hfDate:             date*: Opt[Date]
  of hfUrls:             urls*: Opt[seq[string]]
```

No domain-level constructors. The case object IS the constructor — Nim's
case object syntax is already type-safe by construction. Each variant
carries exactly the fields it needs; the discriminant prevents accessing
fields from the wrong variant at compile time. Adding wrapper functions
would restate what the type system already enforces.

**Parse failure representation:** The `hfMessageIds`, `hfDate`, and
`hfUrls` variants carry `Opt[T]`. `Opt.none` means "the server could not
parse this header" — the RFC specifies that these forms return `null` when
parsing fails. One meaning per state: `Opt.none` is not "absent" or
"not requested", it is "parse failure on the server side."

**`hfDate` uses `Date`** (RFC 3339, any timezone), not `UTCDate`. RFC 8621
§4.1.2.4 specifies the `Date` header parsed form returns a `Date`, not a
`UTCDate`. The `Date` distinct type from `primitives.nim` matches the spec.

**`hfAddresses` and `hfGroupedAddresses`** reference `seq[EmailAddress]`
and `seq[EmailAddressGroup]` from `addresses.nim` (Design A §2). The
import dependency is self-documenting from the type definitions.

The serde layer provides `parseHeaderValue` (§2.7) for constructing
`HeaderValue` from JSON. Domain code constructs `HeaderValue` directly via
Nim's case object syntax.

**Principles:**
- **Make illegal states unrepresentable** — Each variant has exactly what
  it needs. No JSON blobs leak into the domain model.
- **Total functions** — Pattern matching on the discriminant is exhaustive.
- **Parse, don't validate** — The serde layer determines the variant from
  the property name suffix, parses into the correct type.
- **DRY** — No wrapper constructors duplicating what the type system
  enforces.

### 2.5. allowedForms

**RFC reference:** §4.1.2.

`allowedForms` maps known header names to their permitted parsed form sets.
Unknown headers (including vendor extensions) allow all forms per the RFC.

**Private table + public function:**

```nim
const allowedHeaderFormsTable: Table[string, set[HeaderForm]] = {
  "from":        {hfAddresses, hfGroupedAddresses, hfRaw},
  "sender":      {hfAddresses, hfGroupedAddresses, hfRaw},
  "reply-to":    {hfAddresses, hfGroupedAddresses, hfRaw},
  "to":          {hfAddresses, hfGroupedAddresses, hfRaw},
  "cc":          {hfAddresses, hfGroupedAddresses, hfRaw},
  "bcc":         {hfAddresses, hfGroupedAddresses, hfRaw},
  "subject":     {hfText, hfRaw},
  "date":        {hfDate, hfRaw},
  "message-id":  {hfMessageIds, hfRaw},
  "in-reply-to": {hfMessageIds, hfRaw},
  "references":  {hfMessageIds, hfRaw},
}.toTable
```

The table is **private** (not exported). The public API is the function:

```nim
func allowedForms*(name: string): set[HeaderForm] =
  ## Returns permitted forms for a header name (lowercase).
  ## Unknown headers allow all forms per RFC 8621.
  if name in allowedHeaderFormsTable:
    return allowedHeaderFormsTable[name]
  return {hfRaw..hfUrls}
```

Only the total function is exposed. The table is the data; the function is
the rule. Exposing both would create two paths — one total, one partial.
"Make the right thing easy and the wrong thing hard" means: don't expose the
partial path at all.

**Principles:**
- **One source of truth per fact** — Private table for data, public
  function for the lookup rule.
- **Total functions** — Every header name maps to a set. Unknown headers
  return all forms.
- **Make the right thing easy** — Consumers call `allowedForms`, never
  touch the table.
- **DRY** — The complete header-to-form mapping is defined once.

### 2.6. validateHeaderForm

**RFC reference:** §4.1.2.

`validateHeaderForm` is a domain validation function that checks whether a
`HeaderPropertyKey`'s form is permitted for its header name per the
`allowedForms` table. It is separate from `parseHeaderPropertyName` (§2.3),
which validates structural correctness only.

```nim
func validateHeaderForm*(
    key: HeaderPropertyKey,
): Result[HeaderPropertyKey, ValidationError]
```

Checks `key.form in allowedForms(key.name)`. Returns `ok(key)` if the form
is allowed, `err(ValidationError)` if not.

Consumers compose this as needed:
- EmailBlueprint's smart constructor (Part D) calls `validateHeaderForm`
  on creation-model headers — strict for client-constructed values.
- The serde layer for server-provided header data **skips** this check —
  Postel's law: accept unusual form combinations from servers.

**Principles:**
- **Parse once at the boundary** — Each boundary does its own level of
  validation. Structural parsing (`parseHeaderPropertyName`) and domain
  validation (`validateHeaderForm`) are separate concerns.
- **Postel's law** — Server data is not rejected for using an unusual form
  on a known header.
- **Total functions** — Both the constructor and the validator are total.
- **DRY** — `allowedForms` is the single source of truth, used by one
  validation function.

### 2.7. Serde — serde_headers.nim

**Module:** `src/jmap_client/mail/serde_headers.nim`

Follows established core serde patterns (`checkJsonKind`, `optJsonField`,
`parseError`).

**parseHeaderPropertyName** is defined in `headers.nim` (L1) because it is
the smart constructor for `HeaderPropertyKey`. `serde_headers.nim` imports
and uses it.

**toPropertyString** is defined in `headers.nim` (L1) because it is a
domain operation on `HeaderPropertyKey` (reconstructing the wire string from
sealed fields).

#### EmailHeader serialisation

Wire format:

```json
{"name": "From", "value": "Joe Bloggs <joe@example.com>"}
```

`toJson`:
- Emits `name` and `value` as strings.

`fromJson`:
- Validates JObject.
- Extracts `name` as string (required, rejects absent/null/non-string).
- Extracts `value` as string (required).
- Delegates to `parseEmailHeader` for construction (enforces non-empty
  name).
- Returns `Result[EmailHeader, ValidationError]`.

#### HeaderValue serialisation

**parseHeaderValue:**

```nim
func parseHeaderValue*(
    form: HeaderForm,
    node: JsonNode,
): Result[HeaderValue, ValidationError]
```

Takes a `HeaderForm` and a `JsonNode`. Dispatches on the form to parse the
JSON value into the correct `HeaderValue` variant:

- `hfRaw`: Validates JString. Constructs `HeaderValue(form: hfRaw, rawValue: node.getStr)`.
- `hfText`: Validates JString. Constructs `HeaderValue(form: hfText, textValue: node.getStr)`.
- `hfAddresses`: Validates JArray. Parses each element via
  `EmailAddress.fromJson`. Short-circuits on first error via `?`.
- `hfGroupedAddresses`: Validates JArray. Parses each element via
  `EmailAddressGroup.fromJson`. Short-circuits via `?`.
- `hfMessageIds`: JNull → `Opt.none(seq[string])`. JArray → parses each
  element as JString. Returns the variant with `Opt.some(seq)` or
  `Opt.none` for null.
- `hfDate`: JNull → `Opt.none(Date)`. JString → parses via
  `Date.fromJson`. Returns the variant with `Opt.some(Date)` or `Opt.none`
  for null.
- `hfUrls`: JNull → `Opt.none(seq[string])`. JArray → parses each
  element as JString. Returns the variant with `Opt.some(seq)` or
  `Opt.none` for null.

Returns `Result[HeaderValue, ValidationError]`.

The function takes `form` only, not the full `HeaderPropertyKey`. The caller
handles `:all` dispatch — checking `isAll` on the key and, if true,
iterating the JArray calling `parseHeaderValue` per element. This is not
extracted into a `parseHeaderValues` (plural) function because it would be a
mechanical wrapper over an established iteration pattern carrying no domain
knowledge.

**toJson:**

```nim
func toJson*(v: HeaderValue): JsonNode
```

Dispatches on `v.form`:
- `hfRaw`: `%v.rawValue`
- `hfText`: `%v.textValue`
- `hfAddresses`: JArray of `EmailAddress.toJson` per element.
- `hfGroupedAddresses`: JArray of `EmailAddressGroup.toJson` per element.
- `hfMessageIds`: `Opt.none` → `newJNull()`. `Opt.some` → JArray of
  JString per element.
- `hfDate`: `Opt.none` → `newJNull()`. `Opt.some` → `Date.toJson`.
- `hfUrls`: `Opt.none` → `newJNull()`. `Opt.some` → JArray of JString per
  element.

Both `toJson` and `parseHeaderValue` live in `serde_headers.nim` because
serialisation knowledge belongs with the type, not with any particular
consumer.

**Principles:**
- **Parse, don't validate** — `parseHeaderValue` transforms raw JSON into
  a typed `HeaderValue`. After the call, you hold validated data.
- **Total functions** — Every valid JSON input maps to `ok(HeaderValue)` or
  `err(ValidationError)`.
- **DDD** — Header serde knowledge lives in the header serde module.

---

## 3. Body Sub-Types — body.nim

**Module:** `src/jmap_client/mail/body.nim`

Body sub-types define the structural vocabulary for Email body parts —
both the read model (server-provided MIME structure) and the creation model
(client-constructed body for Email creation). Both models share `PartId`
and the `isMultipart` discriminant pattern.

This section covers all sub-types as a single vertical slice of the body
bounded context. `BlueprintBodyPart` is included here because it is
creation *vocabulary* (the structural shape of a body part in creation
context), not a creation *model* (that is Part D's `EmailBlueprint`). The
relationship parallels `KeywordSet` in `keyword.nim` being vocabulary
consumed by `EmailBlueprint`.

### 3.1. PartId

**RFC reference:** §4.1.4.

A `PartId` identifies a body part uniquely within an Email. Used by
`EmailBodyPart` (read model, leaf parts) and `BlueprintBodyPart` (creation
model, inline parts) as the key into `bodyValues`.

**Type definition:**

```nim
type PartId* = distinct string
```

Borrowed operations via `defineStringDistinctOps(PartId)`: `==`, `$`,
`hash`, `len`.

**Smart constructor:**

```nim
func parsePartIdFromServer*(raw: string): Result[PartId, ValidationError]
```

Validates: `raw` non-empty. No control characters (same
`validateServerAssignedToken` pattern as `parseIdFromServer`).
Post-construction `doAssert` verifies `len > 0`.

Single parser, named `parsePartIdFromServer` per the B15 convention: all
`fromJson` for distinct types use the lenient `*FromServer` parser variant.
`fromJson` is the only construction path for `PartId` in the read model.
In the creation model, `PartId` values are client-assigned identifiers that
correspond to `bodyValues` keys — but the structural constraints (non-empty,
no control characters) are the same.

**Principles:**
- **Newtype everything that has meaning** — A part id is not an arbitrary
  string. The distinct type prevents accidentally using a random string
  where a part id is expected.
- **Parse, don't validate** — Smart constructor enforces non-empty at the
  construction boundary.
- **Total functions** — Maps every input to `ok(PartId)` or
  `err(ValidationError)`.

### 3.2. EmailBodyPart

**RFC reference:** §4.1.4.

`EmailBodyPart` represents the MIME structure of an email body as received
from the server. It is a recursive case object discriminated by
`isMultipart` — multipart nodes carry child parts, leaf nodes carry a
`PartId` and blob reference.

**Type definition:**

```nim
type EmailBodyPart* = object
  ## Shared fields (all parts):
  headers*: seq[EmailHeader]      ## raw MIME headers; @[] if absent
  name*: Opt[string]              ## decoded filename
  contentType*: string            ## e.g., "text/plain", "multipart/mixed"
  charset*: Opt[string]           ## server-provided charset, or none
  disposition*: Opt[string]       ## "inline", "attachment", or none
  cid*: Opt[string]               ## Content-Id without angle brackets
  language*: Opt[seq[string]]     ## Content-Language tags
  location*: Opt[string]          ## Content-Location URI
  size*: UnsignedInt              ## RFC unconditional — all parts

  case isMultipart*: bool
  of true:
    subParts*: seq[EmailBodyPart] ## recursive children
  of false:
    partId*: PartId               ## unique within the Email
    blobId*: Id                   ## reference to content blob
```

**`contentType` field naming** — The field is named `contentType` because
the domain concept is Content-Type (RFC 2045 §5). JMAP's wire format uses
the abbreviated key `"type"`. The serde layer maps between `contentType`
(Nim field) and `"type"` (JSON key). JMAP's abbreviation is not the source
of truth for the domain model.

**`isMultipart` discriminant** — Derived from `contentType` at the parsing
boundary. If `contentType` starts with `"multipart/"`, the part is
multipart. This is the one source of truth — `contentType` IS the
definition of multipart (MIME RFC 2046).

**`headers` field** — `seq[EmailHeader]`, not `Opt[seq[EmailHeader]]`.
Every MIME part has headers (possibly zero of them). The collection may be
empty; the field is never conceptually absent. This parallels
`emailQuerySortOptions: HashSet[string]` on `MailCapabilities` — always
present, possibly empty, never null. `fromJson` defaults to `@[]` if
absent.

**`charset` field** — `Opt[string]`. Represents exactly what the server
sent: absent/null → `Opt.none`, present → `Opt.some(value)`. The
`us-ascii` default for `text/*` parts is consumer interpretation, not
parsing. `Opt.none` means "server did not provide a charset value" — the
consumer has both `charset` and `contentType` on the same object and can
compose the default rule.

**`size` field** — `UnsignedInt` on all parts, including multipart. RFC
8621 §4.1.4 specifies `size` unconditionally. In the serde layer, `size`
is required on leaf parts. On multipart parts, `size` defaults to
`UnsignedInt(0)` if absent — leniency where safe, since multipart size is
non-informative.

No smart constructor for the read model — `fromJson` extracts fields,
validates JSON structure, and constructs directly.

**Principles:**
- **Make illegal states unrepresentable** — Case discriminant encodes the
  RFC invariant: multipart parts have `subParts`, leaf parts have
  `partId`/`blobId`. You cannot access `partId` on a multipart part.
- **One source of truth per fact** — `contentType` determines `isMultipart`.
  Not a separate field, not a JSON key presence check.
- **Parse, don't validate** — The serde layer inspects `contentType`, picks
  the correct variant, and constructs a typed value.
- **Code reads like the spec** — Every RFC §4.1.4 property is a field.

### 3.3. EmailBodyValue

**RFC reference:** §4.1.4.

An `EmailBodyValue` carries decoded text content for a body part,
referenced by `PartId` in the `bodyValues` map on Email.

**Type definition:**

```nim
type EmailBodyValue* = object
  value*: string              ## decoded text content
  isEncodingProblem*: bool    ## default false
  isTruncated*: bool          ## default false
```

Plain public fields, no smart constructor. All combinations of the three
fields are valid for the read model — the server may set either flag to
`true` to indicate encoding problems or truncation.

The creation constraint (both flags must be `false`) belongs to the
creation context. Part D's `EmailBlueprint` smart constructor validates
that all `bodyValues` entries have both flags false. If Part D determines
that the constraint deserves its own type (e.g., a `BlueprintBodyValue`
with no flag fields — because if the flags are always false, they carry
zero information on creation), that is Part D's decision, not Part C's.

**Principles:**
- **Constructors that can't fail, don't** — All field combinations are
  valid.
- **Code reads like the spec** — Three RFC-defined properties.
- **DDD** — Creation constraints belong to the creation context.

### 3.4. BlueprintPartSource

**RFC reference:** §4.6.

`BlueprintPartSource` discriminates how a leaf body part's content is
sourced during Email creation: either inline (referenced by `PartId` into
`bodyValues`) or as a blob reference (by `blobId`).

**Type definition:**

```nim
type BlueprintPartSource* = enum
  bpsInline    ## partId → bodyValues lookup
  bpsBlobRef   ## blobId → uploaded blob reference
```

Plain enum, no string backing. String-backed enums in this codebase
encode wire-format mappings (`CapabilityKind`, `MailSetErrorType`,
`HeaderForm`). `BlueprintPartSource` has no wire-format string
representation — the discriminant is derived from which JSON keys are
present (`partId` vs `blobId`), not from a string field. Encoding a
mapping that doesn't exist violates one source of truth.

**Principles:**
- **Make illegal states unrepresentable** — Two-variant enum expresses the
  XOR constraint: inline parts have `partId`, blob-referenced parts have
  `blobId`.
- **One source of truth** — No wire-format string exists; no string
  backing pretends one does.

### 3.5. BlueprintBodyPart

**RFC reference:** §4.6.

`BlueprintBodyPart` represents the body structure for Email creation. It
uses a nested case object: the outer discriminant (`isMultipart`) separates
multipart containers from leaf parts; the inner discriminant (`source`)
separates inline parts (referencing `bodyValues`) from blob-referenced
parts.

**Type definition:**

```nim
type BlueprintBodyPart* = object
  contentType*: string
  name*: Opt[string]
  disposition*: Opt[string]
  cid*: Opt[string]
  language*: Opt[seq[string]]
  location*: Opt[string]
  extraHeaders*: Table[HeaderPropertyKey, HeaderValue]

  case isMultipart*: bool
  of true:
    subParts*: seq[BlueprintBodyPart]   ## recursive children
  of false:
    case source*: BlueprintPartSource
    of bpsInline:
      partId*: PartId                   ## key into bodyValues
    of bpsBlobRef:
      blobId*: Id
      size*: Opt[UnsignedInt]           ## optional, ignored by server
      charset*: Opt[string]
```

**Nested case object** — The RFC specifies that:
- `partId` XOR `blobId` (mutually exclusive, not both).
- If `partId` is given: `charset` and `size` MUST be omitted.
- If `blobId` is given: `charset` optional, `size` optional (ignored by
  server).

The nested case object makes these MUST-omit constraints compile-time
guarantees rather than runtime checks. You cannot access `blobId` on an
inline part, and you cannot access `charset` on an inline part — the
fields do not exist on those variants.

**`language` field** — `Opt[seq[string]]` on both models (read and
creation). An empty seq when present is valid — the RFC doesn't define it
as invalid, so the type doesn't either. Types model legality, not
usefulness. Same reasoning as `KeywordSet` allowing empty (Decision B2).

**`extraHeaders` field** — `Table[HeaderPropertyKey, HeaderValue]`. The
key's `form` and the value's `form` discriminant must be consistent —
this is a cross-field invariant between the key and value. The
`BlueprintBodyPart` type cannot express this invariant (it would require a
dependent type). Enforcement belongs to Part D's `EmailBlueprint` smart
constructor, which validates consistency as one of its constraints.

**No raw `headers` field** — `EmailBodyPart` has `headers: seq[EmailHeader]`
(raw headers from the server). `BlueprintBodyPart` has only `extraHeaders`
(typed, parsed). Having both would create two sources of truth for the same
header data. Raw headers on a creation model would mean un-parsing typed
data back into strings, violating the directional flow of "parse once at
the boundary."

**Content-Transfer-Encoding restriction** — RFC 8621 §4.6 specifies that
`Content-Transfer-Encoding` MUST NOT be given on creation body parts. This
constraint is enforced by Part D's `EmailBlueprint` smart constructor,
which checks that no `BlueprintBodyPart.extraHeaders` entry has a
`Content-Transfer-Encoding` header name.

No smart constructor for `BlueprintBodyPart` itself — field types and the
nested case object capture structural invariants. Cross-field and
cross-part constraints belong to the consuming `EmailBlueprint`.

**Principles:**
- **Make illegal states unrepresentable** — Nested case object encodes RFC
  MUST-omit constraints at the type level. `charset` with `partId` is
  uncompilable.
- **One source of truth** — No `headers` field. `extraHeaders` is the only
  header mechanism.
- **DDD** — Creation vocabulary (structural shape of a body part)
  vs creation model (the Email being created) are different concerns.
  `BlueprintBodyPart` is vocabulary; `EmailBlueprint` (Part D) is the
  model.
- **Parse once at the boundary** — `extraHeaders` uses typed
  `HeaderPropertyKey`/`HeaderValue`. No un-parsing of typed data.

### 3.6. Serde — serde_body.nim

**Module:** `src/jmap_client/mail/serde_body.nim`

Follows established core serde patterns (`checkJsonKind`, `optJsonField`,
`parseError`).

#### PartId serialisation

Uses the standard distinct string serde templates:

```nim
defineDistinctStringToJson(PartId)
defineDistinctStringFromJson(PartId, parsePartIdFromServer)
```

#### EmailBodyPart serialisation

**Wire format (leaf example):**

```json
{
  "type": "text/plain",
  "charset": "utf-8",
  "disposition": "inline",
  "size": 1234,
  "partId": "1",
  "blobId": "abc123",
  "name": null,
  "cid": null,
  "language": null,
  "location": null,
  "headers": [{"name": "Content-Type", "value": "text/plain; charset=utf-8"}]
}
```

**Wire format (multipart example):**

```json
{
  "type": "multipart/mixed",
  "size": 5678,
  "subParts": [
    {"type": "text/plain", "partId": "1", "blobId": "abc", "size": 100},
    {"type": "image/png", "partId": "2", "blobId": "def", "size": 5578}
  ]
}
```

**fromJson:**

Recursive parsing with depth limit. Follows the `Filter[C]` pattern from
`serde_framework.nim`:

```nim
const MaxBodyPartDepth = 128  ## private

func fromJsonImpl(
    node: JsonNode,
    depth: int,
): Result[EmailBodyPart, ValidationError]
```

- Validates JObject.
- Extracts `"type"` key → `contentType` field (required string).
- Derives `isMultipart` from `contentType` (starts with `"multipart/"`).
  `contentType` is the one source of truth for the discriminant.
- Extracts shared fields:
  - `headers`: JArray of `EmailHeader.fromJson`. Absent → `@[]`.
  - `name`, `charset`, `disposition`, `cid`, `location`: `Opt[string]`.
    Absent/null → `Opt.none`.
  - `language`: `Opt[seq[string]]`. Absent/null → `Opt.none`. Present
    JArray → `Opt.some(seq)`.
  - `size`: `UnsignedInt`. On leaf parts, required (absent → error). On
    multipart parts, default `UnsignedInt(0)` if absent.
- If multipart:
  - Checks `depth > 0`. Returns `err` if depth exhausted.
  - Extracts `subParts` as JArray, parses each element recursively via
    `fromJsonImpl(child, depth - 1)`. Absent → `@[]` (Postel's law — an
    empty multipart container is valid per RFC).
  - Ignores `partId`/`blobId` keys if present on multipart parts.
- If not multipart (leaf):
  - Extracts `partId` via `PartId.fromJson` (required).
  - Extracts `blobId` via `Id.fromJson` (required).
  - Ignores `subParts` key if present on leaf parts.
- Returns `Result[EmailBodyPart, ValidationError]`.

Public entry point:

```nim
func fromJson*(
    t: typedesc[EmailBodyPart],
    node: JsonNode,
): Result[EmailBodyPart, ValidationError] =
  fromJsonImpl(node, MaxBodyPartDepth)
```

The design doc specifies the mapping (wire keys → fields, discriminant
derivation, required vs optional) and the invariants that hold after
parsing. The imperative order of field extraction within `fromJsonImpl` is
an implementation detail.

**toJson:**

Recursive serialisation with depth limit. Total functions must be defined
for every input of the declared type; the recursive `EmailBodyPart` type
is unbounded, so `toJson` needs a depth bound to remain total.

- Emits `"type"` key from `contentType` field.
- Emits all shared fields. `Opt.none` → `null`. `headers` always emitted
  (even if empty `@[]`).
- If multipart: emits `"subParts"` array, recursing per element.
- If leaf: emits `"partId"` and `"blobId"`.
- Returns `JsonNode`.

#### EmailBodyValue serialisation

Wire format:

```json
{
  "value": "Hello, world!",
  "isEncodingProblem": false,
  "isTruncated": false
}
```

`fromJson`:
- Validates JObject.
- Extracts `value` as string (required).
- Extracts `isEncodingProblem` as bool (default `false` if absent).
- Extracts `isTruncated` as bool (default `false` if absent).
- Constructs `EmailBodyValue` directly.
- Returns `Result[EmailBodyValue, ValidationError]`.

`toJson`:
- Emits all three fields. Always emits flags (explicit is safer than
  relying on defaults).

#### BlueprintBodyPart serialisation

**toJson only.** `BlueprintBodyPart` is a creation type — the directional
flow is unidirectional: construct → serialise → send. `fromJson` would
create a second construction path bypassing the smart constructor chain
(Part D's `EmailBlueprint`). Same pattern as `IdentityCreate` (Design A
§4.3) and `MailboxCreate` (Design B §4.6).

Recursive serialisation with depth limit. Total functions must be defined
for every input of the declared type; the recursive `BlueprintBodyPart`
type is unbounded.

**Wire format (inline leaf example):**

```json
{
  "type": "text/plain",
  "partId": "1",
  "disposition": "inline"
}
```

Note: `blobId`, `charset`, `size` are absent — not null, **absent**. The
nested case object makes this a compile-time guarantee. Inline parts
(`bpsInline`) do not have `blobId`, `charset`, or `size` fields; the
serialiser cannot emit keys for fields that don't exist on the variant.

**Wire format (blob-ref leaf example):**

```json
{
  "type": "image/png",
  "blobId": "abc123",
  "charset": "utf-8",
  "size": 5678,
  "name": "photo.png",
  "disposition": "attachment"
}
```

**Wire format (multipart example):**

```json
{
  "type": "multipart/mixed",
  "subParts": [
    {"type": "text/plain", "partId": "1"},
    {"type": "image/png", "blobId": "abc123"}
  ]
}
```

`toJson`:
- Emits `"type"` key from `contentType` field.
- Emits shared optional fields — `Opt.none` fields are **omitted** (not
  emitted as null). `extraHeaders` entries are emitted as individual
  properties using `toPropertyString` for keys and `HeaderValue.toJson`
  for values.
- If multipart: emits `"subParts"` array, recursing per element.
- If leaf, inline: emits `"partId"`. Does not emit `blobId`, `charset`,
  `size` — enforced by the case object.
- If leaf, blob-ref: emits `"blobId"`. Emits `charset` and `size` if
  `Opt.some`, omits if `Opt.none`.
- Returns `JsonNode`.

`EmailBodyPart.fromJson` and `BlueprintBodyPart.toJson` are fully
independent implementations. The recursive depth tracking in both is
duplicated appearance, not duplicated knowledge — each serde function owns
its own boundary logic. A shared helper would be a premature abstraction
over an incidental mechanical similarity.

**Principles:**
- **Total functions** — Depth limits make recursive serde total over
  unbounded types.
- **Parse, don't validate** — `EmailBodyPart.fromJson` transforms raw JSON
  into a fully-typed recursive structure.
- **Make illegal states unrepresentable** — `BlueprintBodyPart.toJson`
  key-omission is a consequence of the nested case object, not a convention.
- **DDD** — Body serde knowledge lives in the body serde module.
- **DRY** — No shared recursive helper; duplicated appearance is not
  duplicated knowledge.

---

## 4. Test Specification

Numbered test scenarios for implementation plan reference. Unit tests verify
smart constructors and type invariants. Serde tests verify round-trip and
structural JSON correctness. Numbering is self-contained to this document.

### 4.1. HeaderForm (scenarios 1–3)

| # | Scenario | Expected |
|---|----------|----------|
| 1 | `parseEnum[HeaderForm]` for each known suffix string (`"asRaw"`, `"asText"`, `"asAddresses"`, `"asGroupedAddresses"`, `"asMessageIds"`, `"asDate"`, `"asURLs"`) | correct variant |
| 2 | `nimIdentNormalize` verification for `"asURLs"` vs `hfUrls` — confirm `parseEnum` produces `hfUrls` | pass (or thin wrapper handles) |
| 3 | Unknown suffix string (e.g., `"asUnknown"`) via `parseEnum` with default | fallback value or wrapper error |

### 4.2. EmailHeader (scenarios 4–8)

| # | Scenario | Expected |
|---|----------|----------|
| 4 | `parseEmailHeader("From", "joe@example.com")` | `ok`, name = `"From"`, value = `"joe@example.com"` |
| 5 | `parseEmailHeader("", "value")` | `err(ValidationError)` |
| 6 | `parseEmailHeader("X-Custom", "")` — empty value is valid | `ok` |
| 7 | `toJson` produces `{"name": "From", "value": "..."}` | structural match |
| 8 | `fromJson`/`toJson` round-trip | identity |

### 4.3. HeaderPropertyKey (scenarios 9–22)

| # | Scenario | Expected |
|---|----------|----------|
| 9 | `parseHeaderPropertyName("header:From:asAddresses")` | `ok`, name = `"from"`, form = `hfAddresses`, isAll = `false` |
| 10 | `parseHeaderPropertyName("header:Subject:asText")` | `ok`, name = `"subject"`, form = `hfText`, isAll = `false` |
| 11 | `parseHeaderPropertyName("header:From:asAddresses:all")` | `ok`, name = `"from"`, form = `hfAddresses`, isAll = `true` |
| 12 | `parseHeaderPropertyName("header:From")` — no form suffix → `hfRaw` | `ok`, name = `"from"`, form = `hfRaw`, isAll = `false` |
| 13 | `parseHeaderPropertyName("header:From:all")` — `:all` without form | `ok`, name = `"from"`, form = `hfRaw`, isAll = `true` |
| 14 | `parseHeaderPropertyName("From:asAddresses")` — missing `header:` prefix | `err(ValidationError)` |
| 15 | `parseHeaderPropertyName("header::asAddresses")` — empty name | `err(ValidationError)` |
| 16 | `parseHeaderPropertyName("header:From:asUnknown")` — unknown form suffix | `err(ValidationError)` |
| 17 | Name normalised to lowercase: `"header:FROM:asRaw"` → name = `"from"` | pass |
| 18 | `toPropertyString` produces `"header:from:asAddresses"` (form suffix from enum string backing) | pass |
| 19 | `toPropertyString` with `hfRaw` omits form suffix: `"header:from"` | pass |
| 20 | `toPropertyString` with `:all`: `"header:from:asAddresses:all"` | pass |
| 21 | `toPropertyString` round-trip with `parseHeaderPropertyName` | identity |
| 22 | Accessor functions `name`, `form`, `isAll` return correct values | pass |

### 4.4. HeaderValue (scenarios 23–37)

| # | Scenario | Expected |
|---|----------|----------|
| 23 | `parseHeaderValue(hfRaw, JString)` | `ok`, rawValue populated |
| 24 | `parseHeaderValue(hfText, JString)` | `ok`, textValue populated |
| 25 | `parseHeaderValue(hfAddresses, JArray of address objects)` | `ok`, addresses populated |
| 26 | `parseHeaderValue(hfGroupedAddresses, JArray of group objects)` | `ok`, groups populated |
| 27 | `parseHeaderValue(hfMessageIds, JArray of JString)` | `ok`, messageIds = `Opt.some(seq)` |
| 28 | `parseHeaderValue(hfMessageIds, JNull)` | `ok`, messageIds = `Opt.none` |
| 29 | `parseHeaderValue(hfDate, JString valid date)` | `ok`, date = `Opt.some(Date)` |
| 30 | `parseHeaderValue(hfDate, JNull)` | `ok`, date = `Opt.none` |
| 31 | `parseHeaderValue(hfUrls, JArray of JString)` | `ok`, urls = `Opt.some(seq)` |
| 32 | `parseHeaderValue(hfUrls, JNull)` | `ok`, urls = `Opt.none` |
| 33 | `parseHeaderValue(hfRaw, JInt)` — wrong JSON kind | `err(ValidationError)` |
| 34 | `parseHeaderValue(hfAddresses, JString)` — wrong kind | `err(ValidationError)` |
| 35 | `toJson` for each of 7 forms | structural match |
| 36 | `toJson`/`parseHeaderValue` round-trip per form | identity |
| 37 | `toJson` for `hfDate` with `Opt.none` | `null` |

### 4.5. allowedForms + validateHeaderForm (scenarios 38–44)

| # | Scenario | Expected |
|---|----------|----------|
| 38 | `allowedForms("from")` | `{hfAddresses, hfGroupedAddresses, hfRaw}` |
| 39 | `allowedForms("subject")` | `{hfText, hfRaw}` |
| 40 | `allowedForms("date")` | `{hfDate, hfRaw}` |
| 41 | `allowedForms("message-id")` | `{hfMessageIds, hfRaw}` |
| 42 | `allowedForms("x-custom-header")` — unknown header | `{hfRaw..hfUrls}` (all forms) |
| 43 | `validateHeaderForm` with `from` + `hfAddresses` | `ok` |
| 44 | `validateHeaderForm` with `subject` + `hfAddresses` | `err(ValidationError)` |

### 4.6. PartId (scenarios 45–48)

| # | Scenario | Expected |
|---|----------|----------|
| 45 | `parsePartIdFromServer("1")` | `ok` |
| 46 | `parsePartIdFromServer("")` | `err(ValidationError)` |
| 47 | `parsePartIdFromServer` with control character | `err(ValidationError)` |
| 48 | `toJson`/`fromJson` round-trip | identity |

### 4.7. EmailBodyPart (scenarios 49–65)

| # | Scenario | Expected |
|---|----------|----------|
| 49 | `fromJson` leaf part (`"type": "text/plain"`) — required `partId`, `blobId` present | `ok`, `isMultipart == false` |
| 50 | `fromJson` multipart (`"type": "multipart/mixed"`) — `subParts` present | `ok`, `isMultipart == true` |
| 51 | `fromJson` multipart with absent `subParts` | `ok`, `subParts == @[]` |
| 52 | `fromJson` leaf with absent `partId` | `err(ValidationError)` |
| 53 | `fromJson` leaf with absent `blobId` | `err(ValidationError)` |
| 54 | `isMultipart` derived from `contentType`, not `subParts` key presence | pass |
| 55 | `size` required on leaf, absent → `err` | pass |
| 56 | `size` absent on multipart → default `UnsignedInt(0)` | pass |
| 57 | `charset` absent → `Opt.none` | pass |
| 58 | `charset` present → `Opt.some(value)` | pass |
| 59 | `headers` absent → `@[]` | pass |
| 60 | `headers` present → parsed `seq[EmailHeader]` | pass |
| 61 | `contentType` field maps to/from `"type"` wire key | pass |
| 62 | Depth limit: nesting at depth 129 → `err(ValidationError)` | pass |
| 63 | `toJson` round-trip for leaf part | identity |
| 64 | `toJson` round-trip for multipart with children | identity |
| 65 | `toJson` depth limit — deeply nested structure → `err` or truncation | totality preserved |

### 4.8. EmailBodyValue (scenarios 66–71)

| # | Scenario | Expected |
|---|----------|----------|
| 66 | `fromJson` all fields present, flags false | `ok` |
| 67 | `fromJson` with `isEncodingProblem = true` | `ok` (read model allows) |
| 68 | `fromJson` with `isTruncated = true` | `ok` |
| 69 | `fromJson` with both flags true | `ok` |
| 70 | `fromJson` flags absent → default `false` | pass |
| 71 | `toJson`/`fromJson` round-trip | identity |

### 4.9. BlueprintBodyPart (scenarios 72–79)

| # | Scenario | Expected |
|---|----------|----------|
| 72 | `toJson` inline leaf (`bpsInline`) — emits `partId`, omits `blobId`/`charset`/`size` | structural match |
| 73 | `toJson` blob-ref leaf (`bpsBlobRef`) — emits `blobId`, optional `charset`/`size` | structural match |
| 74 | `toJson` blob-ref leaf with `charset` and `size` present | both emitted |
| 75 | `toJson` blob-ref leaf with `charset` and `size` absent | both omitted |
| 76 | `toJson` multipart — emits `subParts`, recursive | structural match |
| 77 | `toJson` depth limit — deeply nested structure | totality preserved |
| 78 | `toJson` emits `"type"` key from `contentType` field | pass |
| 79 | No `fromJson` for `BlueprintBodyPart` — creation type is toJson-only | compile-time: no such function |

---

## 5. Decision Traceability Matrix

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|----------|--------------------|--------|-------------------|
| C1 | HeaderPropertyKey sealing | A) Plain public fields, B) Pattern A (sealed) | B — real invariant (non-empty name, valid form). Sealed prevents `HeaderPropertyKey(name: "", ...)` | Make illegal states unrepresentable, Parse-don't-validate |
| C2 | HeaderPropertyKey name casing | A) Store as-is, B) Normalise to lowercase, C) Normalise to title case | B — canonical form means `==` just works. Same pattern as Keyword and MailboxRole | Parse-don't-validate, One source of truth |
| C3 | HeaderPropertyKey form validation scope | A) Validate against AllowedHeaderForms in constructor, B) No form validation in constructor, C) Strict/lenient pair, Modified B) Separate `validateHeaderForm` function | Modified B — structural parsing (`parseHeaderPropertyName`) and domain validation (`validateHeaderForm`) are separate concerns | Parse once at the boundary, Postel's law, Total functions, DRY |
| C4 | HeaderForm enum style | A) String-backed, B) Plain enum + manual parse | A — JMAP suffix string as backing. `parseEnum` for free. Code reads like the spec | DRY, Code reads like the spec, One source of truth |
| C5 | HeaderValue parse failure representation | A) Opt.none, B) Explicit parse-failure variant | A — one meaning per state. None = "server could not parse." No overloaded semantics | Make illegal states unrepresentable, One source of truth |
| C6 | hfDate variant type | A) Date (RFC 3339, any timezone), B) UTCDate | A — RFC 8621 §4.1.2.4 specifies Date, not UTCDate | Code reads like the spec, DDD |
| C7 | HeaderValue construction | A) Per-variant constructors, B) Single dispatch function, C) Both, D) No constructors — case object IS the constructor | D — adding wrappers would be DRY-violating ceremony restating what the type system enforces | DRY, Make illegal states unrepresentable |
| C8 | EmailHeader type | A) Plain object + smart constructor, B) Sealed Pattern A | A — EmailAddress pattern. Smart constructor enforces non-empty name. Sealing disproportionate to risk | Parse-don't-validate, Total functions |
| C9 | EmailHeader module | A) In headers.nim, B) Separate module | A — same bounded context. Dependency graph shows always co-required | DDD |
| C10 | AllowedHeaderForms shape | A) Public const Table, B) Private table + public total function | B — private table, public `allowedForms` func as only API. Don't expose the partial path | One source of truth, Total functions, Make the right thing easy |
| C11 | Cross-module dependency documentation | A) Note explicitly, B) Obvious from types | B — types are self-documenting. A prose note would be duplicated knowledge | DRY |
| C12 | parseHeaderValue signature | A) Form only, B) Full HeaderPropertyKey | A — form is the only information needed. Caller handles `:all` dispatch | DDD, Postel's law |
| C13 | HeaderValue serde direction | A) Both toJson and fromJson, B) fromJson only | A — serialisation knowledge belongs with the type, not with any particular consumer | DDD, One source of truth |
| C14 | PartId parser naming | A) parsePartId, B) parsePartIdFromServer, C) Both names (alias) | B — B15 convention: `fromJson` uses `*FromServer` parser. Single parser, only construction path | DRY, Postel's law |
| C15 | EmailBodyPart discriminant derivation | A) Derive from contentType, B) Derive from subParts presence, C) Both (validate consistency) | Modified A — contentType is one source of truth. subParts defaults to @[] if absent on multipart. partId/blobId required on leaf. Ignore subParts on non-multipart | One source of truth, Postel's law, Parse once at the boundary, Total functions |
| C16 | EmailBodyPart size field | A) Required on all parts, B) Required on leaf, optional on multipart, C) Required on all, default 0 on multipart if absent | Modified C — UnsignedInt on all parts. Required on leaf (absent → err). Default UnsignedInt(0) on multipart if absent. Leniency only where safe | Postel's law, Code reads like the spec |
| C17 | EmailBodyPart depth limit mechanism | A) Module-level constant, B) Parameter with default, Modified A) Private const + private fromJsonImpl pattern | Modified A — follows Filter[C] precedent from serde_framework.nim. Public API hides depth entirely | DRY, Parse once at the boundary, Make the right thing easy, Total functions |
| C18 | Depth limit value | A) 64, B) 128, C) 32 | B — consistency with Filter[C] precedent | DRY |
| C19 | EmailBodyPart contentType field naming | A) contentType (RFC 2045 domain concept), B) type (backtick-escaped), C) contentType with serde mapping | Modified C — domain concept is Content-Type (RFC 2045). Serde maps to/from "type" wire key. JMAP's abbreviation is not the source of truth | DDD, Code reads like the spec, One source of truth |
| C20 | EmailBodyPart charset | A) Opt[string] no default, B) Opt[string] default applied for text/* | Modified A — Opt.none = "server did not provide charset." Default is consumer interpretation, not parsing. Consumer has both fields | One source of truth, Parse once at the boundary |
| C21 | EmailBodyValue construction | A) Plain object, B) Smart constructor enforcing flags false | Modified A — all combinations valid for read model. Creation constraint belongs to Part D's EmailBlueprint | Constructors that can't fail don't, DDD |
| C22 | BlueprintBodyPart placement | A) In Part C (body.nim), B) Deferred to Part D | Modified A — creation vocabulary, not creation model. Shares PartId, isMultipart, recursive structure with read model | DDD, DRY |
| C23 | BlueprintBodyPart extraHeaders type | A) Table[HeaderPropertyKey, HeaderValue], B) seq of tuples, C) Table[string, HeaderValue] | Modified A — typed keys. Form consistency is cross-field invariant enforced by Part D's EmailBlueprint smart constructor | Make illegal states unrepresentable, DDD |
| C24 | BlueprintBodyPart serde key-omission | A) Document as named pattern, B) Let the type speak | Modified B — key-omission is a consequence of the case object structure. Rationale notes nested case makes MUST-omit constraints compile-time guarantees | Make illegal states unrepresentable |
| C25 | BlueprintBodyPart language | A) Same type on both models (Opt[seq[string]]), B) Creation requires non-empty when present | A — RFC doesn't define empty as invalid; types model legality, not usefulness. Same reasoning as KeywordSet empty (B2) | Code reads like the spec, Make illegal states unrepresentable |
| C26 | BlueprintBodyPart raw headers | A) extraHeaders only, B) Both headers and extraHeaders | A — two sources of truth violates one-source-of-truth. Raw headers on creation = un-parsing typed data, violating directional parse flow | One source of truth, Parse once at the boundary |
| C27 | EmailBodyPart headers field type | A) Opt[seq[EmailHeader]], B) seq[EmailHeader] | Modified B — every MIME part has headers (possibly zero). Never conceptually absent. Parallels emailQuerySortOptions pattern. Default @[] if absent | One source of truth, Code reads like the spec |
| C28 | Body serde independence | A) Fully independent implementations, B) Shared recursive helper | A — depth tracking is duplicated appearance, not duplicated knowledge. Shared helper would be premature abstraction | DRY |
| C29 | toJson depth limits | A) No depth limit on toJson, B) Depth limit on both toJson functions | Modified B — total functions must be defined for every input; recursive types are unbounded. Depth limit makes toJson total | Total functions |
| C30 | BlueprintPartSource enum style | A) Plain enum, B) String-backed | A — string-backed enums encode wire-format mappings. No wire mapping exists. Encoding a mapping that doesn't exist violates one source of truth | One source of truth |
| C31 | BlueprintBodyPart fromJson | A) toJson only, B) Both toJson and fromJson | A — creation types are unidirectional (construct → serialise → send). fromJson would create a second construction path bypassing the smart constructor chain | Parse once at the boundary, Constructors are privileges |
| C32 | Flat list validation location | A) Helper in serde_body.nim, B) Entirely in Part D, C) isLeaf accessor on EmailBodyPart | Modified B — isMultipart discriminant is already public. Email's fromJson IS the boundary where the constraint matters | DDD, Parse once at the boundary |
| C33 | Test numbering | A) Start from 1, B) Continue from 80 | A — self-contained per document | DRY |
| C34 | DTM scope | A) All decisions, B) Significant only, C) Grouped | A — complete traceability | One source of truth |
| C35 | Doc structure — entity/builder section | A) Omit entirely, B) Include with not-applicable note | A — absent section is self-explanatory for readers of the template | DRY |
| C36 | EmailBodyPart fromJson specification level | A) Specify parse order, B) Specify mapping and invariants only | B — parse order is implementation detail. Design doc specifies what is parsed and what invariants hold | DDD |
| C37 | `:all` suffix serde | A) Caller's responsibility, B) Export parseHeaderValues (plural) | A — parseHeaderValues would be a mechanical wrapper carrying no domain knowledge | DRY |
| C38 | HeaderPropertyKey input format | A) Full wire string including `header:` prefix, B) After prefix | A — the type encapsulates the entire header:Name:form:all structure. Full wire string is input and output | Parse-don't-validate, One source of truth |
| C39 | HeaderPropertyKey toPropertyString | A) Emit lowercase name + enum string backing form, B) Store and emit original casing | Modified A — each component from its own source of truth. Canonical form IS the domain truth | One source of truth, DRY |
