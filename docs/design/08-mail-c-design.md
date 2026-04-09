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
   - 4.1–4.9: Unit, serde, and compile-time tests per type
   - 4.10: Adversarial scenarios
   - 4.11: Property-based test strategy
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
| `headers.nim` | L1 | `HeaderForm`, `EmailHeader`, `parseEmailHeader`, `HeaderPropertyKey`, `parseHeaderPropertyName`, `toPropertyString`, `HeaderValue`, `allowedForms`, `validateHeaderForm` |
| `body.nim` | L1 | `PartId`, `parsePartIdFromServer`, `EmailBodyPart`, `EmailBodyValue`, `BlueprintPartSource`, `BlueprintBodyPart` |
| `serde_headers.nim` | L2 | `parseHeaderValue`, `toJson`/`fromJson` for `HeaderValue` and `EmailHeader` |
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

The parser also does **not** validate that the header name contains only
printable ASCII characters (33–126, excluding colon), even though RFC 8621
§4.1.3 defines `{header-field-name}` with this constraint. This is a
deliberate strict/lenient split: the structural parser is lenient to accept
server-provided header property names (Postel's law). The printable-ASCII
constraint is enforced on client-constructed values at the Part D boundary
— see §2.6.

The structural parser's concern is "is this a well-formed header property
name?" — not "does the RFC permit this combination?" or "is the name valid
for sending?"

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
§4.1.2.6 specifies the `Date` header parsed form returns a `Date`, not a
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
The table covers every header field defined in RFC 5322 and RFC 2369, plus
`List-Id` from RFC 2919 (explicitly named in §4.1.2.2 — see note below).
Headers defined in these RFCs but not listed for any parsed form (e.g.,
`Return-Path`, `Received`) are restricted to Raw only. Unknown headers
(including vendor extensions and headers from other RFCs not explicitly
named in §4.1.2) allow all forms per the RFC's catch-all clause.

**Private table + public function:**

```nim
const allowedHeaderFormsTable: Table[string, set[HeaderForm]] = {
  ## RFC 5322 §3.6.2–3.6.3 address headers (§4.1.2.3, §4.1.2.4)
  "from":              {hfAddresses, hfGroupedAddresses, hfRaw},
  "sender":            {hfAddresses, hfGroupedAddresses, hfRaw},
  "reply-to":          {hfAddresses, hfGroupedAddresses, hfRaw},
  "to":                {hfAddresses, hfGroupedAddresses, hfRaw},
  "cc":                {hfAddresses, hfGroupedAddresses, hfRaw},
  "bcc":               {hfAddresses, hfGroupedAddresses, hfRaw},
  ## RFC 5322 §3.6.6 resent address headers (§4.1.2.3, §4.1.2.4)
  "resent-from":       {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-sender":     {hfAddresses, hfGroupedAddresses, hfRaw},
  ## RFC 5322 §4.5.6 obsolete resent field, listed in RFC 8621 §4.1.2.3
  "resent-reply-to":   {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-to":         {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-cc":         {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-bcc":        {hfAddresses, hfGroupedAddresses, hfRaw},
  ## RFC 5322 §3.6.5 text headers (§4.1.2.2)
  "subject":           {hfText, hfRaw},
  "comments":          {hfText, hfRaw},
  "keywords":          {hfText, hfRaw},
  ## RFC 2919 — explicitly named in §4.1.2.2 (Text). Although List-Id is
  ## not defined in RFC 5322 or RFC 2369 (so the catch-all in §4.1.2.3–7
  ## would technically permit all forms), the RFC's explicit enumeration
  ## under Text is treated as the authoritative restriction (Decision C40).
  "list-id":           {hfText, hfRaw},
  ## RFC 5322 §3.6.1 + §3.6.6 date headers (§4.1.2.6)
  "date":              {hfDate, hfRaw},
  "resent-date":       {hfDate, hfRaw},
  ## RFC 5322 §3.6.4 + §3.6.6 message-id headers (§4.1.2.5)
  "message-id":        {hfMessageIds, hfRaw},
  "in-reply-to":       {hfMessageIds, hfRaw},
  "references":        {hfMessageIds, hfRaw},
  "resent-message-id": {hfMessageIds, hfRaw},
  ## RFC 2369 list headers (§4.1.2.7)
  "list-help":         {hfUrls, hfRaw},
  "list-unsubscribe":  {hfUrls, hfRaw},
  "list-subscribe":    {hfUrls, hfRaw},
  "list-post":         {hfUrls, hfRaw},
  "list-owner":        {hfUrls, hfRaw},
  "list-archive":      {hfUrls, hfRaw},
  ## RFC 5322 §3.6.7 — not listed for any parsed form (Raw only)
  "return-path":       {hfRaw},
  "received":          {hfRaw},
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
  on creation-model headers — strict for client-constructed values. Part D
  also validates that all `HeaderPropertyKey` names in `extraHeaders`
  contain only printable ASCII (33–126, excluding colon) per RFC 8621
  §4.1.3. This follows the same strict/lenient split as `parseId` vs
  `parseIdFromServer`: strict on client-constructed values, lenient on
  server-provided data (Decision C42).
- The serde layer for server-provided header data **skips** both checks —
  Postel's law: accept unusual form combinations and non-standard name
  characters from servers.

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

Validates: `raw` non-empty. No length limit — RFC 8621 types `partId` as
`String` (not `Id`), so the 1–255 octet constraint from RFC 8620's `Id`
definition does not apply. `PartId` uses its own validation function, not
the shared `validateServerAssignedToken` used by `Id`. Control characters
(< 0x20) are rejected as a defensive Postel's-law measure (no compliant
server would produce them), not because the RFC mandates it — this is a
distinct decision from the `Id` character-set constraint (Decision C41).
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

**`charset` field** — `Opt[string]`. Two states per the RFC: a string
value (either the explicit charset parameter or the implicit `"us-ascii"`
default for `text/*` parts), or `Opt.none` meaning "not `text/*`". The
`fromJson` boundary applies the RFC rule: if `contentType` is `text/*` and
charset is absent/null, emit `Opt.some("us-ascii")`. The boundary already
inspects `contentType` to derive `isMultipart`; applying the charset
default in the same parse pass is not a layer violation — it is the same
field, in the same function, for the same reason (deriving domain truth
from `contentType`). Postel's law: if a non-compliant server sends null
charset for a `text/*` part, the default is applied rather than passing
ambiguity inward. After the boundary, interior code can trust: "if charset
is `Opt.some`, it carries a value; if `Opt.none`, the part is not
`text/*`."

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
  - `name`, `disposition`, `cid`, `location`: `Opt[string]`.
    Absent/null → `Opt.none`.
  - `charset`: `Opt[string]`. If `contentType` starts with `"text/"` and
    charset is absent/null, emit `Opt.some("us-ascii")` (RFC §4.1.4
    implicit default, Postel's law for non-compliant servers). If
    `contentType` is not `text/*` and charset is absent/null, emit
    `Opt.none`. If charset is present as a string, emit
    `Opt.some(value)` regardless of `contentType`.
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
structural JSON correctness. Compile-time tests verify that case objects and
sealed types prevent invalid access. Numbering is self-contained to this
document. Scenarios added during test optimisation review use alphabetic
suffixes (e.g., 4a, 4b) relative to the original scenario they follow.

### 4.1. HeaderForm (scenarios 1–4, 4a–4b)

| # | Scenario | Expected |
|---|----------|----------|
| 1 | `parseEnum[HeaderForm]` for each known suffix string (`"asRaw"`, `"asText"`, `"asAddresses"`, `"asGroupedAddresses"`, `"asMessageIds"`, `"asDate"`, `"asURLs"`) | correct variant |
| 2 | `nimIdentNormalize` verification for `"asURLs"` vs `hfUrls` — confirm wrapper function produces `hfUrls`. Verify and document whether `parseEnum` or a manual match function is used | pass — wrapper handles any mismatch |
| 3 | Unknown suffix string (e.g., `"asUnknown"`) via wrapper function | `err` — unrecognised form suffix rejected |
| 4 | `$` operator for all 7 variants produces string backing: `$hfAddresses == "asAddresses"`, `$hfUrls == "asURLs"`, etc. | pass — load-bearing for `toPropertyString` |
| 4a | Wrapper function with empty string `""` | `err` — no form suffix to parse |
| 4b | Wrapper function with `"as_Addresses"` (underscore in suffix) — `nimIdentNormalize` false match test | Pin behaviour: `ok` (if `parseEnum` normalises) or `err` (if exact match). Document the parsing mechanism |

### 4.2. EmailHeader (scenarios 5–11, 11a–11f)

| # | Scenario | Expected |
|---|----------|----------|
| 5 | `parseEmailHeader("From", "joe@example.com")` | `ok`, name = `"From"`, value = `"joe@example.com"` |
| 6 | `parseEmailHeader("", "value")` | `err(ValidationError)` |
| 7 | `parseEmailHeader("X-Custom", "")` — empty value is valid | `ok` |
| 8 | `toJson` produces `{"name": "From", "value": "..."}` | structural match |
| 9 | `fromJson`/`toJson` round-trip | identity |
| 10 | `parseEmailHeader` with control character in name (`"From\x00"`, `"X\x1F"`) — no format validation beyond non-empty | `ok` (lenient — server provides arbitrary names) |
| 11 | `parseEmailHeader` with whitespace-only name (`"   "`) — non-empty but semantically vacuous | `ok` (non-empty constraint is structural, not semantic) |
| 11a | `fromJson` with non-JObject input (JArray) | `err(ValidationError)` |
| 11b | `fromJson` with absent `"name"` key | `err(ValidationError)` |
| 11c | `fromJson` with `"name": null` | `err(ValidationError)` |
| 11d | `fromJson` with `"name"` as JInt (wrong kind) | `err(ValidationError)` |
| 11e | `fromJson` with absent `"value"` key | `err(ValidationError)` |
| 11f | `fromJson` with `"value": null` | `err(ValidationError)` |

### 4.3. HeaderPropertyKey (scenarios 12–29, 29a–29e)

| # | Scenario | Expected |
|---|----------|----------|
| 12 | `parseHeaderPropertyName("header:From:asAddresses")` | `ok`, name = `"from"`, form = `hfAddresses`, isAll = `false` |
| 13 | `parseHeaderPropertyName("header:Subject:asText")` | `ok`, name = `"subject"`, form = `hfText`, isAll = `false` |
| 14 | `parseHeaderPropertyName("header:From:asAddresses:all")` | `ok`, name = `"from"`, form = `hfAddresses`, isAll = `true` |
| 15 | `parseHeaderPropertyName("header:From")` — no form suffix → `hfRaw` | `ok`, name = `"from"`, form = `hfRaw`, isAll = `false` |
| 16 | `parseHeaderPropertyName("header:From:all")` — `:all` without form | `ok`, name = `"from"`, form = `hfRaw`, isAll = `true` |
| 17 | `parseHeaderPropertyName("From:asAddresses")` — missing `header:` prefix | `err(ValidationError)` |
| 18 | `parseHeaderPropertyName("header::asAddresses")` — empty name | `err(ValidationError)` |
| 19 | `parseHeaderPropertyName("header:From:asUnknown")` — unknown form suffix | `err(ValidationError)` |
| 20 | Name normalised to lowercase: `"header:FROM:asRaw"` → name = `"from"` | pass |
| 21 | `toPropertyString` produces `"header:from:asAddresses"` (form suffix from enum string backing) | pass |
| 22 | `toPropertyString` with `hfRaw` omits form suffix: `"header:from"` | pass |
| 23 | `toPropertyString` with `:all`: `"header:from:asAddresses:all"` | pass |
| 24 | `toPropertyString` round-trip with `parseHeaderPropertyName` | identity |
| 25 | `parseHeaderPropertyName("header:From:asRaw")` — explicit hfRaw form suffix | `ok`, name = `"from"`, form = `hfRaw`, isAll = `false` |
| 26 | `parseHeaderPropertyName("header:From:asRaw:all")` — explicit hfRaw + `:all` | `ok`, name = `"from"`, form = `hfRaw`, isAll = `true` |
| 27 | `parseHeaderPropertyName("header:X-My:Custom:asText")` — colon in apparent name portion | `err(ValidationError)` — RFC 5322 header names do not contain colons; the parser treats colons as structural delimiters. The segment `"Custom"` is parsed as an unrecognised form suffix |
| 28 | `parseHeaderPropertyName("header:FROM:asAddresses")` — full uppercase name | `ok`, name = `"from"` |
| 29 | Form suffix case variants: `"header:From:asaddresses"`, `"header:From:ASADDRESSES"` | Pin behaviour: `err` or `ok` per the form suffix parsing mechanism. `parseEnum` applies `nimIdentNormalize` (case-insensitive after first character). Document the exact rule used |
| 29a | `parseHeaderPropertyName("")` — empty string | `err(ValidationError)` |
| 29b | `parseHeaderPropertyName("header:From:asAddresses:")` — trailing colon after form | `err(ValidationError)` — segment after form suffix is neither `"all"` nor absent |
| 29c | `parseHeaderPropertyName("header:From:asAddresses:ALL")` — `:all` suffix uppercase | Pin behaviour: `err` or `ok`. Document the case sensitivity rule for the `:all` suffix |
| 29d | `parseHeaderPropertyName("header:From:as_Addresses")` — underscore in form suffix (`nimIdentNormalize` false match) | Pin behaviour: `ok` (if `parseEnum` normalises) or `err` (if exact match). Document whether `parseEnum` normalisation applies to form suffix parsing |
| 29e | `HeaderPropertyKey` equality after case normalisation: keys from `"header:FROM:asAddresses"` and `"header:from:asAddresses"` | `key1 == key2` and `hash(key1) == hash(key2)` — required for correct `Table` key behaviour in `extraHeaders` |

### 4.4. HeaderValue (scenarios 30–52, 52a–52c)

| # | Scenario | Expected |
|---|----------|----------|
| 30 | `parseHeaderValue(hfRaw, JString)` | `ok`, rawValue populated |
| 31 | `parseHeaderValue(hfText, JString)` | `ok`, textValue populated |
| 32 | `parseHeaderValue(hfAddresses, JArray of address objects)` | `ok`, addresses populated |
| 33 | `parseHeaderValue(hfGroupedAddresses, JArray of group objects)` | `ok`, groups populated |
| 34 | `parseHeaderValue(hfMessageIds, JArray of JString)` | `ok`, messageIds = `Opt.some(seq)` |
| 35 | `parseHeaderValue(hfMessageIds, JNull)` | `ok`, messageIds = `Opt.none` |
| 36 | `parseHeaderValue(hfDate, JString valid date)` | `ok`, date = `Opt.some(Date)` |
| 37 | `parseHeaderValue(hfDate, JNull)` | `ok`, date = `Opt.none` |
| 38 | `parseHeaderValue(hfUrls, JArray of JString)` | `ok`, urls = `Opt.some(seq)` |
| 39 | `parseHeaderValue(hfUrls, JNull)` | `ok`, urls = `Opt.none` |
| 40 | `parseHeaderValue(hfRaw, JInt)` — wrong JSON kind | `err(ValidationError)` |
| 41 | `parseHeaderValue(hfAddresses, JString)` — wrong kind | `err(ValidationError)` |
| 42 | `toJson` for each of 7 forms | structural match |
| 43 | `toJson`/`parseHeaderValue` round-trip per form, including `Opt.none` variants for `hfMessageIds`, `hfDate`, `hfUrls` (null → toJson → parseHeaderValue → null) | identity |
| 44 | `toJson` for `hfDate` with `Opt.none` | `null` |
| 45 | `parseHeaderValue(hfAddresses, JArray of [])` — empty addresses array | `ok`, addresses = `@[]` |
| 46 | `parseHeaderValue(hfGroupedAddresses, JArray of [])` — empty groups array | `ok`, groups = `@[]` |
| 47 | `parseHeaderValue(hfMessageIds, JArray of [])` — empty message-id array | `ok`, messageIds = `Opt.some(@[])` |
| 48 | `parseHeaderValue(hfUrls, JArray of [])` — empty URLs array | `ok`, urls = `Opt.some(@[])` |
| 49 | `parseHeaderValue(hfAddresses, JArray with malformed address)` — missing `email` field in element | `err(ValidationError)` — propagated from `EmailAddress.fromJson` |
| 50 | `parseHeaderValue(hfDate, JString with malformed date)` — e.g., `"not-a-date"` | `err(ValidationError)` — propagated from `Date.fromJson` |
| 51 | Wrong JSON kind for remaining forms: `hfText` + JInt, `hfGroupedAddresses` + JString, `hfMessageIds` + JObject, `hfDate` + JArray, `hfUrls` + JObject | `err(ValidationError)` for each |
| 52 | `parseHeaderValue(hfAddresses, JNull)` — null for non-nullable form | `err(ValidationError)` |
| 52a | `parseHeaderValue(hfRaw, %"")` — empty raw string | `ok`, `rawValue == ""` |
| 52b | `parseHeaderValue(hfAddresses, %*[42, "not-an-object"])` — mixed-kind array elements | `err(ValidationError)` on first non-JObject element |
| 52c | `parseHeaderValue(hfMessageIds, %*["valid", 42])` — non-JString element in message-id array | `err(ValidationError)` on the JInt element |

### 4.5. allowedForms + validateHeaderForm (scenarios 53–69, 60a, 69a)

| # | Scenario | Expected |
|---|----------|----------|
| 53 | `allowedForms("from")` | `{hfAddresses, hfGroupedAddresses, hfRaw}` |
| 54 | `allowedForms("subject")` | `{hfText, hfRaw}` |
| 55 | `allowedForms("date")` | `{hfDate, hfRaw}` |
| 56 | `allowedForms("message-id")` | `{hfMessageIds, hfRaw}` |
| 57 | `allowedForms("x-custom-header")` — unknown header | `{hfRaw..hfUrls}` (all forms) |
| 58 | `validateHeaderForm` with `from` + `hfAddresses` | `ok` |
| 59 | `validateHeaderForm` with `subject` + `hfAddresses` | `err(ValidationError)` |
| 60 | `allowedForms("resent-from")` — resent address category representative | `{hfAddresses, hfGroupedAddresses, hfRaw}` |
| 61 | `allowedForms("list-unsubscribe")` — URLs category representative | `{hfUrls, hfRaw}` |
| 62 | `allowedForms("return-path")` — Raw-only category | `{hfRaw}` |
| 60a | Table completeness: `allowedHeaderFormsTable` contains exactly 27 entries, and every entry's form set includes `hfRaw` | pass — implementation SHOULD exhaustively test every table entry; this scenario asserts structural correctness |
| 68 | `validateHeaderForm` with unknown header (`"x-custom"`) + `hfAddresses` | `ok` — unknown headers allow all forms |
| 69 | `validateHeaderForm` with `from` + `hfRaw` | `ok` — Raw always allowed |
| 69a | `allowedForms("FROM")` — non-lowercase input | `{hfRaw..hfUrls}` (all forms) — lookup misses because table keys are lowercase. Documents the caller contract: callers MUST pass lowercase names |

### 4.6. PartId (scenarios 70–76, 73a)

| # | Scenario | Expected |
|---|----------|----------|
| 70 | `parsePartIdFromServer("1")` | `ok` |
| 71 | `parsePartIdFromServer("")` | `err(ValidationError)` |
| 72 | `parsePartIdFromServer` with control character | `err(ValidationError)` |
| 73 | `toJson`/`fromJson` round-trip | identity |
| 73a | `PartId` equality: two constructions from same string produce equal values; `hash` matches | pass — required for `bodyValues` map key correctness |
| 74 | `parsePartIdFromServer` with long value (e.g., 500 chars) | `ok` — no length limit (partId is String, not Id) |
| 75 | `parsePartIdFromServer` with multi-byte UTF-8 at any length | `ok` |
| 76 | `parsePartIdFromServer` with typical server formats (`"1"`, `"1.2"`, `"1.2.3"`) | `ok` |

### 4.7. EmailBodyPart (scenarios 77–108, 97a–99d, 102a, 108a–108c)

| # | Scenario | Expected |
|---|----------|----------|
| 77 | `fromJson` leaf part (`"type": "text/plain"`) — required `partId`, `blobId` present | `ok`, `isMultipart == false` |
| 78 | `fromJson` multipart (`"type": "multipart/mixed"`) — `subParts` present | `ok`, `isMultipart == true` |
| 79 | `fromJson` multipart with absent `subParts` | `ok`, `subParts == @[]` |
| 80 | `fromJson` leaf with absent `partId` | `err(ValidationError)` |
| 81 | `fromJson` leaf with absent `blobId` | `err(ValidationError)` |
| 82 | `isMultipart` derived from `contentType`, not `subParts` key presence | pass |
| 83 | `size` required on leaf, absent → `err` | pass |
| 84 | `size` absent on multipart → default `UnsignedInt(0)` | pass |
| 85 | `charset` absent on `text/plain` → `Opt.some("us-ascii")` (RFC default applied) | pass |
| 86 | `charset` present on `text/plain` → `Opt.some(value)` | pass |
| 87 | `charset` null on `text/html` → `Opt.some("us-ascii")` (Postel's law) | pass |
| 88 | `charset` absent on `image/png` → `Opt.none` (not text/*) | pass |
| 89 | `charset` absent on `multipart/mixed` → `Opt.none` (not text/*) | pass |
| 90 | `charset` present on `image/png` → `Opt.some(value)` (trust server) | pass |
| 91 | `headers` absent → `@[]` | pass |
| 92 | `headers` present → parsed `seq[EmailHeader]` | pass |
| 93 | Depth limit: nesting at depth 129 → `err(ValidationError)` | pass |
| 94 | `toJson` round-trip for leaf part | identity |
| 95 | `toJson` round-trip for multipart with children | identity |
| 96 | `toJson` depth limit — deeply nested structure → `err` or truncation | totality preserved |
| 97 | `fromJson` with absent `contentType`/`"type"` key | `err(ValidationError)` |
| 98 | `fromJson` with `contentType` = `"MULTIPART/MIXED"` (uppercase) | `ok`, `isMultipart == true` (case-insensitive prefix check) |
| 99 | `fromJson` with `contentType` = `"multipart/"` (nothing after slash) | `ok`, `isMultipart == true` |
| 100 | `fromJson` leaf with `subParts` key present → ignored | `ok`, `isMultipart == false` |
| 101 | `fromJson` multipart with `partId`/`blobId` keys present → ignored | `ok`, `isMultipart == true` |
| 102 | `fromJson` with null element in `headers` array | `err(ValidationError)` |
| 103 | `fromJson` with null element in `subParts` array | `err(ValidationError)` |
| 104 | `fromJson` at depth exactly 128 | `ok` — boundary success |
| 105 | `fromJson` with `charset` = `""` (empty string) on `text/plain` | `ok`, `charset == Opt.some("")` (Postel's law) |
| 106 | `fromJson` with `size` as negative number | `err(ValidationError)` — propagated from `UnsignedInt.fromJson` |
| 107 | `fromJson` with `size` exceeding 2^53-1 | `err(ValidationError)` — propagated from `UnsignedInt.fromJson` |
| 108 | `toJson` at depth exactly 128 | `ok` — totality preserved at boundary |
| 97a | `fromJson` with non-JObject input (JArray, JNull, JString) | `err(ValidationError)` |
| 97b | `fromJson` with `"type"` key as JInt (wrong JSON kind) | `err(ValidationError)` |
| 98a | `fromJson` `"TEXT/PLAIN"` with absent charset — case sensitivity of `text/*` prefix check | Pin and justify: `Opt.some("us-ascii")` (case-insensitive, consistent with `isMultipart` per scenario 98) or `Opt.none` (case-sensitive). If `isMultipart` is case-insensitive, `text/*` should be too for consistency |
| 99a | `fromJson` `"text/"` (nothing after slash) with absent charset | `ok`, `charset == Opt.some("us-ascii")` — starts with `"text/"` |
| 99b | `fromJson` `"textplain"` (no slash) — not a valid MIME type but structurally valid JSON | `ok`, `isMultipart == false`, leaf requires `partId`/`blobId` |
| 99c | `fromJson` `"multipart"` (no trailing slash) — does not start with `"multipart/"` | Not multipart. Treated as leaf; absent `partId`/`blobId` → `err(ValidationError)` |
| 99d | `fromJson` with `contentType = ""` (empty string) | Pin behaviour: `ok` or `err`. If `ok`: `isMultipart == false`, `charset == Opt.none` |
| 102a | `fromJson` with `language` array containing JInt element | `err(ValidationError)` — parallel to scenario 102 for headers |
| 108a | Compile-time: accessing `partId` on multipart variant | Does not compile (`assertNotCompiles`) |
| 108b | Compile-time: accessing `subParts` on leaf variant | Does not compile (`assertNotCompiles`) |
| 108c | `fromJson` with duplicate `"type"` key (`"text/plain"` then `"multipart/mixed"`) — `std/json` last-wins semantics | `ok`, `isMultipart == true` (second key wins), `subParts` defaults to `@[]`. `partId`/`blobId` keys ignored on multipart |

### 4.8. EmailBodyValue (scenarios 109–118, 115a, 118a–118b)

| # | Scenario | Expected |
|---|----------|----------|
| 109 | `fromJson` all fields present, flags false | `ok` |
| 110 | `fromJson` with `isEncodingProblem = true` | `ok` (read model allows) |
| 111 | `fromJson` with `isTruncated = true` | `ok` |
| 112 | `fromJson` with both flags true | `ok` |
| 113 | `fromJson` flags absent → default `false` | pass |
| 114 | `toJson`/`fromJson` round-trip | identity |
| 115 | `fromJson` with absent `value` field | `err(ValidationError)` |
| 116 | `fromJson` with `value` = `null` | `err(ValidationError)` |
| 117 | `fromJson` with wrong JSON kind for `value` (JInt instead of JString) | `err(ValidationError)` |
| 118 | `fromJson` with wrong JSON kind for flags (JString `"true"` instead of JBool `true`) | `err(ValidationError)` |
| 115a | `fromJson` with non-JObject input (JArray, JNull) | `err(ValidationError)` |
| 118a | `fromJson` with `value = ""` (empty string) | `ok`, `value == ""` |
| 118b | `fromJson` with `isEncodingProblem: null` (JNull, not absent) — distinct from absent | Pin behaviour: `ok` (treated as absent → default `false`) or `err(ValidationError)` (strict kind check). Document the null-vs-absent rule for bool flags |

### 4.9. BlueprintBodyPart (scenarios 119–131, 125a–125d, 127a, 130a–130b)

| # | Scenario | Expected |
|---|----------|----------|
| 119 | `toJson` inline leaf (`bpsInline`) — emits `partId`, omits `blobId`/`charset`/`size` | structural match |
| 120 | `toJson` blob-ref leaf (`bpsBlobRef`) — emits `blobId`, optional `charset`/`size` | structural match |
| 121 | `toJson` blob-ref leaf with `charset` and `size` present | both emitted |
| 122 | `toJson` blob-ref leaf with `charset` and `size` absent | both omitted |
| 123 | `toJson` multipart — emits `subParts`, recursive | structural match |
| 124 | `toJson` depth limit — depth 128 → `ok`, depth 129 → `err` or truncation (matching `MaxBodyPartDepth = 128` and scenarios 93/104/108) | totality preserved at exact boundary |
| 125 | No `fromJson` for `BlueprintBodyPart` — creation type is toJson-only | compile-time: no such function |
| 126 | `toJson` inline leaf — verify `blobId`, `charset`, `size` keys are **absent** (not null) in JSON output | pass — keys not in `node.fields` |
| 127 | `toJson` with `extraHeaders` — entries emitted as `"header:name:asForm": value` properties | structural match |
| 128 | `toJson` with empty `extraHeaders` table — no extra properties emitted | structural match |
| 129 | `toJson` multipart with empty `subParts` (`@[]`) | `"subParts": []` emitted |
| 130 | `toJson` multipart with 2+ levels of nesting (multipart → multipart → leaf) | structural match |
| 131 | `toJson` blob-ref leaf with `Opt.none` for both `charset` and `size` — verify both keys **absent** | pass — keys not in `node.fields` |
| 125a | Compile-time: accessing `blobId` on inline variant | Does not compile (`assertNotCompiles`) |
| 125b | Compile-time: accessing `charset` on inline variant | Does not compile (`assertNotCompiles`) |
| 125c | Compile-time: accessing `partId` on multipart variant | Does not compile (`assertNotCompiles`) |
| 125d | Compile-time: accessing `subParts` on leaf variant | Does not compile (`assertNotCompiles`) |
| 127a | `toJson` with `extraHeaders` entry whose key has `hfRaw` form — verify `toPropertyString` omits form suffix in JSON key | structural match: key is `"header:x-custom"`, not `"header:x-custom:asRaw"` |
| 130a | `toJson` multipart with mixed children: one inline leaf + one blob-ref leaf in same `subParts` | structural match — both serialised correctly |
| 130b | `toJson` with `extraHeaders` where key.form ≠ value.form (e.g., key `hfAddresses`, value `hfText`) | Serialises without error. Documents that form consistency enforcement is deferred to Part D's `EmailBlueprint` smart constructor |

### 4.10. Adversarial Scenarios (scenarios A1–A6)

Adversarial edge cases probing parsing boundaries and cross-component
interactions. These follow the conventions established in
`tests/serde/tserde_adversarial.nim` and `tests/stress/tadversarial.nim`.

| # | Scenario | Expected |
|---|----------|----------|
| A1 | `parseHeaderPropertyName("header:From\x00Evil:asAddresses")` — NUL byte in header name portion | Pin behaviour: `ok` with NUL in name (NUL byte is not `0x3A` colon, not caught by any character check), or `err` if ASCII-only names enforced. Document FFI truncation risk: C-side `strlen` sees `"header:From"` |
| A2 | `parseHeaderPropertyName` with overlong UTF-8 colon `\xC0\xBA` in name portion — overlong encoding of `:` (0x3A) | `ok` — overlong-encoded colons are NOT literal `0x3A` bytes and do not trigger delimiter splits. Name contains raw bytes. Document the byte-level (not Unicode-aware) splitting |
| A3 | `EmailBodyPart.fromJson` with `"type"` value containing NUL: `"text/plain\x00multipart/mixed"` | `ok`, `isMultipart == false` — `startsWith("multipart/")` operates on full byte sequence. NUL is not `/`. Document Nim/C semantic divergence |
| A4 | `EmailBodyPart.fromJson` multipart with 10,000 leaf children — breadth stress | `ok` — no breadth limit specified. Depth limit does not restrict breadth. Documents memory implication |
| A5 | `BlueprintBodyPart.toJson` with `extraHeaders` containing `Content-Transfer-Encoding` key | `toJson` emits the header without error. RFC 8621 §4.6 MUST NOT constraint is enforced by Part D's `EmailBlueprint` smart constructor, not at the Part C vocabulary level |
| A6 | `EmailBodyPart.fromJson` with `"size": 3.14` (JFloat, not JInt) | `err(ValidationError)` — `UnsignedInt.fromJson` requires `JInt` kind. JFloat is a distinct JSON kind |

### 4.11. Property-Based Test Strategy

Property-based tests follow the `mproperty.nim` infrastructure (fixed seed,
edge-biased generators, tiered trial counts). These are not numbered
scenarios but describe the coverage strategy for random/generative testing.

**Round-trip identity** (DefaultTrials = 500):
- `EmailBodyPart`: generate random recursive structures (mixed multipart
  and leaf), verify `fromJson(toJson(part)) == part`.
- `HeaderValue`: all 7 forms including `Opt.none` variants, verify
  `parseHeaderValue(form, toJson(value)) == value`.
- `EmailHeader`: random name/value pairs, verify round-trip.
- `PartId`: random valid strings, verify round-trip.

**Totality** (ThoroughTrials = 2000):
- `EmailBodyPart.fromJson` never crashes on arbitrary `JsonNode` input
  (malformed objects, wrong kinds, deeply nested structures). Uses
  `discard` — must not panic.
- `parseHeaderPropertyName` never crashes on arbitrary strings (empty,
  very long, binary content, embedded NULs).
- `parseHeaderValue` never crashes on arbitrary `(HeaderForm, JsonNode)`
  pairs.

**Edge-biased generators:** Early trials (0–3) cover boundary conditions:
empty strings, depth-1, max depth (128), `Opt.none` variants, empty
arrays, single-element arrays. Remaining trials use uniform random
generation across the valid input space.

---

## 5. Decision Traceability Matrix

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|----------|--------------------|--------|-------------------|
| C1 | HeaderPropertyKey sealing | A) Plain public fields, B) Pattern A (sealed) | B — real invariant (non-empty name, valid form). Sealed prevents `HeaderPropertyKey(name: "", ...)` | Make illegal states unrepresentable, Parse-don't-validate |
| C2 | HeaderPropertyKey name casing | A) Store as-is, B) Normalise to lowercase, C) Normalise to title case | B — canonical form means `==` just works. Same pattern as Keyword and MailboxRole | Parse-don't-validate, One source of truth |
| C3 | HeaderPropertyKey form validation scope | A) Validate against AllowedHeaderForms in constructor, B) No form validation in constructor, C) Strict/lenient pair, Modified B) Separate `validateHeaderForm` function | Modified B — structural parsing (`parseHeaderPropertyName`) and domain validation (`validateHeaderForm`) are separate concerns | Parse once at the boundary, Postel's law, Total functions, DRY |
| C4 | HeaderForm enum style | A) String-backed, B) Plain enum + manual parse | A — JMAP suffix string as backing. `parseEnum` for free. Code reads like the spec | DRY, Code reads like the spec, One source of truth |
| C5 | HeaderValue parse failure representation | A) Opt.none, B) Explicit parse-failure variant | A — one meaning per state. None = "server could not parse." No overloaded semantics | Make illegal states unrepresentable, One source of truth |
| C6 | hfDate variant type | A) Date (RFC 3339, any timezone), B) UTCDate | A — RFC 8621 §4.1.2.6 specifies Date, not UTCDate | Code reads like the spec, DDD |
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
| C20 | EmailBodyPart charset | A) Opt[string] no default, B) Opt[string] default applied for text/* at serde boundary | B — RFC §4.1.4 defines charset as always a string for text/* (explicit or implicit "us-ascii"), null only for non-text/*. fromJson already inspects contentType to derive isMultipart; applying the charset default in the same parse pass is consistent. Opt.none = "not text/*". Postel's law: non-compliant servers sending null for text/* get the default applied, not ambiguity passed inward | Parse once at the boundary, Code reads like the spec, One source of truth, Postel's law |
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
| C40 | List-Id in allowedForms table | A) Include with {hfText, hfRaw}, B) Exclude (let catch-all grant all forms) | A — RFC 8621 §4.1.2.2 explicitly names List-Id under Text. Although List-Id is RFC 2919 (not RFC 5322/2369) and technically qualifies for every section's catch-all, the explicit enumeration under one specific form is treated as the authoritative restriction. The catch-all is not intended to override explicit mentions | Code reads like the spec, One source of truth |
| C41 | PartId validation constraints | A) Reuse validateServerAssignedToken (Id constraints), B) Own validator (non-empty + defensive control-char rejection), C) Non-empty only | Modified B — RFC 8621 types partId as String, not Id. No length limit is imposed. Control-character rejection is a defensive Postel's-law measure, not an RFC mandate. PartId's constraints derive from its own RFC definition, not from Id's | One source of truth, Code reads like the spec, Postel's law |
| C42 | HeaderPropertyKey name character validation | A) In parseHeaderPropertyName (structural parser), B) Deferred to Part D's EmailBlueprint, C) No validation | Modified B — structural parser is lenient for server-provided data (Postel's law). Part D's EmailBlueprint enforces printable-ASCII (33–126, no colon) on client-constructed extraHeaders keys per RFC 8621 §4.1.3. Same strict/lenient split as parseId/parseIdFromServer | Parse once at the boundary, Postel's law, Make the right thing easy |
