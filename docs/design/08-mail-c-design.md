# RFC 8621 JMAP Mail — Design C: Header and Body Sub-Types

This document is the detailed specification for the header and body sub-types
required by the Email entity — plus their serde modules. It covers Layers 1
and 2 (L1 types, L2 serde) for each type, cutting vertically through the
architecture.

Part C is a pure vocabulary document. It defines shared building blocks
consumed by Part D (Email entity, SearchSnippet) and beyond. No entity
registration, no builder functions, no filter conditions.

Builds on the cross-cutting architecture design (`05-mail-architecture.md`),
the existing RFC 8620 infrastructure (`00-architecture.md` through
`04-layer-4-design.md`), Design A (`06-mail-a-design.md`), and Design B
(`07-mail-b-design.md`).

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
| `HeaderForm` | `headers.nim` | Enum of RFC 8621 header parsed-form suffixes |
| `parseHeaderForm` | `headers.nim` | Case-insensitive form-suffix parser |
| `EmailHeader` | `headers.nim` | Raw header name-value pair for MIME parts |
| `HeaderPropertyKey` | `headers.nim` | Sealed key encoding `header:Name:asForm:all` |
| `HeaderValue` | `headers.nim` | Case object carrying parsed header content by form |
| `allowedForms` | `headers.nim` | Header-name → permitted-form-set lookup |
| `validateHeaderForm` | `headers.nim` | Domain check pairing `HeaderPropertyKey` with `allowedForms` |
| `BlueprintEmailHeaderName` | `headers.nim` | Distinct name for `EmailBlueprint.extraHeaders` |
| `BlueprintBodyHeaderName` | `headers.nim` | Distinct name for `BlueprintBodyPart.extraHeaders` |
| `BlueprintHeaderMultiValue` | `headers.nim` | Form-discriminated `NonEmptySeq[T]` carrier |
| `*Single` / `*Multi` constructors | `headers.nim` | Per-form helpers for `BlueprintHeaderMultiValue` |
| `MaxBodyPartDepth` | `body.nim` | Public depth bound for body-part trees (128) |
| `PartId` | `body.nim` | Distinct string identifier for body parts within an Email |
| `ContentDisposition` | `body.nim` | Validated RFC 2183 §2.1 disposition with extension arm |
| `EmailBodyPart` | `body.nim` | Recursive case object for MIME body structure (read model) |
| `EmailBodyValue` | `body.nim` | Decoded body text content with encoding/truncation flags |
| `BlueprintBodyValue` | `body.nim` | Creation-only body-value carrier (no flags) |
| `BlueprintPartSource` | `body.nim` | Enum discriminant for creation leaf source (inline vs blob) |
| `BlueprintLeafPart` | `body.nim` | Inner case object for the non-multipart half of a blueprint |
| `BlueprintBodyPart` | `body.nim` | Outer case object for creation body structure |
| `composeHeaderKey` | `serde_headers.nim` | Wire-key composer (`header:<name>[:asForm][:all]`) |
| `multiLen` | `serde_headers.nim` | Cardinality probe for `BlueprintHeaderMultiValue` |
| `blueprintMultiValueToJson` | `serde_headers.nim` | 7-form variant dispatcher |

### 1.2. Deferred

`Email` (read model), `ParsedEmail`, `EmailBlueprint`, `EmailUpdate`,
`SearchSnippet`, `EmailFilterCondition`, `EmailHeaderFilter`,
`EmailComparator`, `EmailBodyFetchOptions`, and the `Email/import`,
`Email/copy`, `Email/parse` types are all owned by Design D.
`EmailSubmission` and its sub-types are owned by Design E.

### 1.3. Relationship to Cross-Cutting Design

This document refines `05-mail-architecture.md` §6 (Header Parsed Forms) and
§7 (Body Structure) into implementation-ready specifications for the header
and body bounded contexts. The creation-side header vocabulary
(`BlueprintEmailHeaderName` / `BlueprintBodyHeaderName` /
`BlueprintHeaderMultiValue`) is documented at the architecture level in §6.9
and refined here.

### 1.4. Module Summary

All modules live under `src/jmap_client/mail/`. Each `.nim` file under
`src/` opens with `{.push raises: [], noSideEffect.}` followed by
`{.experimental: "strictCaseObjects".}`, per the project-wide L1–L3
purity contract.

| Module | Layer | Contents |
|--------|-------|----------|
| `headers.nim` | L1 | `HeaderForm`, `parseHeaderForm`, `EmailHeader`, `parseEmailHeader`, `HeaderPropertyKey` (sealed), `parseHeaderPropertyName`, `name`/`form`/`isAll`/`hash`/`$`/`toPropertyString`, `HeaderValue`, `allowedForms`, `validateHeaderForm`, `BlueprintEmailHeaderName`, `parseBlueprintEmailHeaderName`, `BlueprintBodyHeaderName`, `parseBlueprintBodyHeaderName`, `BlueprintHeaderMultiValue`, the seven `*Single` / `*Multi` constructors, `defineNonEmptySeqOps` instantiations |
| `body.nim` | L1 | `MaxBodyPartDepth`, `PartId`, `parsePartIdFromServer`, `ContentDispositionKind`, `ContentDisposition` (sealed), `kind`/`identifier`/`$`/`==`/`hash`, `dispositionInline`, `dispositionAttachment`, `parseContentDisposition`, `EmailBodyPart`, `EmailBodyValue`, `BlueprintBodyValue`, `BlueprintPartSource`, `BlueprintLeafPart`, `BlueprintBodyPart` |
| `serde_headers.nim` | L2 | `EmailHeader.toJson`/`fromJson`, `parseHeaderValue`, `HeaderValue.toJson`, `BlueprintEmailHeaderName.toJson`/`fromJson`, `BlueprintBodyHeaderName.toJson`/`fromJson`, `multiLen`, `composeHeaderKey`, `blueprintMultiValueToJson` |
| `serde_body.nim` | L2 | `PartId.toJson`/`fromJson`, `EmailBodyPart.toJson`/`fromJson`, `EmailBodyValue.toJson`/`fromJson`, `BlueprintBodyValue.toJson`, `BlueprintBodyPart.toJson` |

### 1.5. Error Conventions

L1 smart constructors return `Result[T, ValidationError]`. L2 serde returns
`Result[T, SerdeViolation]` (the structured deserialisation ADT defined in
core's `serde.nim`); inner `ValidationError` failures are bridged via
`wrapInner` so the JSON path of the offending field is preserved. Every
`fromJson` accepts an optional trailing `path: JsonPath = emptyJsonPath()`
argument that nested helpers extend (`path / "key"`, `path / index`).

---

## 2. Header Sub-Types — headers.nim

**Module:** `src/jmap_client/mail/headers.nim`

Headers are a shared bounded context used by the Email read model
(convenience fields, dynamic parsed headers, raw headers), `EmailBodyPart`
(raw headers per MIME part), `EmailBlueprint` (top-level `extraHeaders`),
and `BlueprintBodyPart` (per-body-part `extraHeaders`). All header-related
types live in `headers.nim` — the dependency graph shows they are always
co-required.

The module splits into two concentric vocabularies:

- **Read / query vocabulary** — `HeaderForm`, `EmailHeader`,
  `HeaderPropertyKey`, `HeaderValue`, `allowedForms`,
  `validateHeaderForm`. Bidirectional: parsed from server responses,
  emitted on `properties` queries.
- **Creation vocabulary** — `BlueprintEmailHeaderName`,
  `BlueprintBodyHeaderName`, `BlueprintHeaderMultiValue` and their
  `*Single` / `*Multi` constructors. Unidirectional: constructed by the
  client and emitted; the server never sends these back, so there are no
  `*FromServer` lenient siblings.

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

String-backed enum mapping to JMAP form suffixes. `$form` returns the
backing string (`$hfAddresses == "asAddresses"`), which is load-bearing for
`toPropertyString` and `composeHeaderKey`.

**Form-suffix parser:**

```nim
func parseHeaderForm*(raw: string): Result[HeaderForm, ValidationError]
```

Parses a suffix string into a `HeaderForm` variant using
`nimIdentNormalize` for case-insensitive matching that ignores underscores.
Internally:

1. A module-private `HeaderFormViolationKind` enum names the two structural
   failure modes: `hfvEmpty` and `hfvUnknown`.
2. A pure classifier `detectHeaderForm` returns
   `Result[HeaderForm, HeaderFormViolationKind]` — separating
   classification from wire-error translation.
3. A translator `toValidationError(v, raw)` converts the kind to a
   `ValidationError` with `typeName = "HeaderForm"`.

This three-step shape (detect → classify → translate) is the project-wide
pattern for token parsers: classification stays in ADT form so consumers
can re-wrap the inner violation under their own `typeName` (used by
`HeaderPropertyKey`'s parser — see §2.3).

**Principles:**
- **DRY** — A single form-suffix parser; `HeaderPropertyKey` reuses it.
- **Code reads like the spec** — `hfAddresses = "asAddresses"`.
- **Total functions** — `parseEnum`-style classifier with named failure
  kinds; no exceptions.

### 2.2. EmailHeader

**RFC reference:** §4.1.2.

An `EmailHeader` represents a single raw RFC 5322 header field — a
name-value pair as provided by the server. Used by `EmailBodyPart.headers`
and the read-model `Email.headers` field.

**Type definition:**

```nim
type EmailHeader* {.ruleOff: "objects".} = object
  name*: string   ## non-empty (enforced by parseEmailHeader)
  value*: string  ## raw header value (may be empty)
```

Plain public fields. The `ruleOff: "objects"` pragma silences nimalyzer's
complaint about a non-sealed object — `EmailHeader` is a simple value
object whose only invariant is captured by the smart constructor.

**Smart constructor:**

```nim
func parseEmailHeader*(
    name: string, value: string
): Result[EmailHeader, ValidationError]
```

Validates `name` non-empty. No format validation beyond non-empty — the
server provides arbitrary header names, possibly including non-ASCII bytes.

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

**Type definition (sealed):**

```nim
type HeaderPropertyKey* {.ruleOff: "objects".} = object
  rawName: string       ## module-private, lowercase, non-empty
  rawForm: HeaderForm   ## module-private
  rawIsAll: bool        ## module-private
```

Sealed (Pattern A): all fields are module-private. Direct construction of
`HeaderPropertyKey(rawName: "", ...)` is rejected outside `headers.nim`.
External access flows through UFCS accessors:

```nim
func name*(k: HeaderPropertyKey): string
func form*(k: HeaderPropertyKey): HeaderForm
func isAll*(k: HeaderPropertyKey): bool
func hash*(k: HeaderPropertyKey): Hash
func `$`*(k: HeaderPropertyKey): string
```

`hash` mixes `rawName`, `ord(rawForm)`, and `rawIsAll` so the type can
serve as a `Table` key (it is used for `Email.requestedHeaders` and
`Email.requestedHeadersAll`). `$` delegates to `toPropertyString` (below).

**Smart constructor:**

```nim
func parseHeaderPropertyName*(
    raw: string
): Result[HeaderPropertyKey, ValidationError]
```

Accepts the full wire string including the `header:` prefix. Internally
delegates to a module-private `classifyHeaderKey` that returns
`Result[HeaderPropertyKey, HeaderKeyViolation]`, where `HeaderKeyViolation`
is a case object with five kinds:

- `hkvMissingPrefix` — no `header:` prefix.
- `hkvEmptyName` — empty header name after the prefix.
- `hkvInvalidForm` — nests the inner `HeaderFormViolationKind` so the
  translator can reuse `formViolationMessage` rather than duplicate its
  wire text.
- `hkvExpectedAllSuffix` — third segment present but not `:all`. Carries
  the offending segment for error message interpolation.
- `hkvTooManySegments` — more than three colon-delimited segments.

A single translator `toValidationError(v, raw)` converts every variant to
a `ValidationError` with `typeName = "HeaderPropertyKey"`. Adding a new
violation kind forces a compile error at the translator (the project-wide
ADT-translation pattern documented in `nim-functional-core.md`).

The classifier:
- Splits `raw[7..^1]` on `':'` (1, 2, or 3 segments).
- Lowercase-normalises the header name (`toLowerAscii`).
- Defaults the form to `hfRaw` when no form suffix is present.
- Treats `cmpIgnoreCase(segment, "all") == 0` as the `:all` suffix —
  case-insensitive.
- Delegates form parsing to `detectHeaderForm` (case-insensitive,
  underscore-tolerant via `nimIdentNormalize`).

The structural parser does **not** validate that the form is allowed for
the given header name. That is domain validation (§2.6), not structural
parsing. It also does **not** validate that the header name contains only
printable ASCII — that is enforced on creation-side keys by
`BlueprintEmailHeaderName` / `BlueprintBodyHeaderName` (§2.7–§2.8). The
read parser is lenient (Postel's law).

**Wire-string reconstruction:**

```nim
func toPropertyString*(k: HeaderPropertyKey): string
```

Reconstructs the canonical wire string from component sources of truth:
`"header:"` literal + lowercase `rawName` + (`":" & $form` when
`form != hfRaw`) + (`":all"` when `rawIsAll`). The form suffix is omitted
for `hfRaw` (the default), producing the shortest canonical
representation.

**Principles:**
- **Make illegal states unrepresentable** — Sealed fields + smart
  constructor guarantee non-empty lowercase name and a valid form.
- **Parse, don't validate** — Lowercase canonical form means `==` and
  `hash` "just work" everywhere.
- **DRY** — Form parsing reuses `detectHeaderForm`; ADT translation lives
  in one site.
- **Total functions** — Every input maps to `ok` or `err`.

### 2.4. HeaderValue

**RFC reference:** §4.1.2.

A `HeaderValue` carries parsed header content, discriminated by
`HeaderForm`. Each variant holds exactly the type that the corresponding
form produces — the case object makes illegal states unrepresentable.

**Type definition:**

```nim
type HeaderValue* {.ruleOff: "objects".} = object
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
case-object syntax is already type-safe by construction. Each variant
carries exactly the fields it needs.

**Parse failure representation:** The `hfMessageIds`, `hfDate`, and
`hfUrls` variants carry `Opt[T]`. `Opt.none` means "the server could not
parse this header" — the RFC specifies that these forms return `null` when
parsing fails. One meaning per state.

**`hfDate` uses `Date`** (RFC 3339, any timezone), not `UTCDate`. RFC 8621
§4.1.2.6 specifies the `Date` header parsed form returns a `Date`.

**Principles:**
- **Make illegal states unrepresentable** — Each variant has exactly what
  it needs.
- **Total functions** — Pattern matching on the discriminant is exhaustive.
- **DRY** — No wrapper constructors duplicating what the type system
  already enforces.

### 2.5. allowedForms

**RFC reference:** §4.1.2.

`allowedForms` maps known header names to their permitted parsed-form
sets. The table covers every header field defined in RFC 5322 and RFC
2369, plus `List-Id` from RFC 2919 (explicitly named in §4.1.2.2).
Headers defined in RFC 5322 §3.6.7 but not listed for any parsed form
(`Return-Path`, `Received`) are restricted to Raw only. Unknown headers
allow all forms per the RFC's catch-all clause.

**Private table + public function:**

```nim
const allowedHeaderFormsTable = {
  ## Address headers (RFC 5322 §3.6.2–3.6.3, §3.6.6, §4.5.6) — 12 entries
  "from":              {hfAddresses, hfGroupedAddresses, hfRaw},
  "sender":            {hfAddresses, hfGroupedAddresses, hfRaw},
  "reply-to":          {hfAddresses, hfGroupedAddresses, hfRaw},
  "to":                {hfAddresses, hfGroupedAddresses, hfRaw},
  "cc":                {hfAddresses, hfGroupedAddresses, hfRaw},
  "bcc":               {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-from":       {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-sender":     {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-reply-to":   {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-to":         {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-cc":         {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-bcc":        {hfAddresses, hfGroupedAddresses, hfRaw},
  ## Text headers (RFC 5322 §3.6.5, RFC 2919) — 4 entries
  "subject":           {hfText, hfRaw},
  "comments":          {hfText, hfRaw},
  "keywords":          {hfText, hfRaw},
  "list-id":           {hfText, hfRaw},
  ## Date headers (RFC 5322 §3.6.1, §3.6.6) — 2 entries
  "date":              {hfDate, hfRaw},
  "resent-date":       {hfDate, hfRaw},
  ## Message-id headers (RFC 5322 §3.6.4, §3.6.6) — 4 entries
  "message-id":        {hfMessageIds, hfRaw},
  "in-reply-to":       {hfMessageIds, hfRaw},
  "references":        {hfMessageIds, hfRaw},
  "resent-message-id": {hfMessageIds, hfRaw},
  ## URL headers (RFC 2369) — 6 entries
  "list-help":         {hfUrls, hfRaw},
  "list-unsubscribe":  {hfUrls, hfRaw},
  "list-subscribe":    {hfUrls, hfRaw},
  "list-post":         {hfUrls, hfRaw},
  "list-owner":        {hfUrls, hfRaw},
  "list-archive":      {hfUrls, hfRaw},
  ## Raw-only headers (RFC 5322 §3.6.7) — 2 entries
  "return-path":       {hfRaw},
  "received":          {hfRaw},
}.toTable
```

Total: 30 entries. The table is **private**. The public API is the
function:

```nim
func allowedForms*(name: string): set[HeaderForm]
```

Uses `getOrDefault` with the full set `{hfRaw..hfUrls}` as the default.
Precondition: callers MUST pass a lowercase name (typically obtained via
`HeaderPropertyKey.name`, which normalises). A non-lowercase name simply
misses the table and returns the full set — a permissive
mis-classification, not an error.

**Principles:**
- **One source of truth per fact** — Private table for data, public
  function for the lookup rule.
- **Total functions** — Every header name maps to a set.
- **Make the right thing easy** — Consumers call `allowedForms`; they
  cannot reach the partial path.
- **DRY** — One mapping definition.

### 2.6. validateHeaderForm

**RFC reference:** §4.1.2.

`validateHeaderForm` is the domain check that `HeaderPropertyKey.form` is
permitted for `HeaderPropertyKey.name` per `allowedForms`. Separate from
`parseHeaderPropertyName` (§2.3), which validates structural correctness
only.

```nim
func validateHeaderForm*(
    key: HeaderPropertyKey
): Result[HeaderPropertyKey, ValidationError]
```

Returns `ok(key)` if `key.form in allowedForms(key.name)`, else
`err(ValidationError)` with a message of the form
`"form <Form> not allowed for header <name>"`.

The `EmailBlueprint` smart constructor (Design D) applies this rule
recursively to every body-part `extraHeaders` entry as constraint 7 —
the violations surface as `ebcAllowedFormRejected` errors. The serde
layer for server-provided header data does not call this — Postel's
law applies on receive.

**Principles:**
- **Parse once at the boundary** — Structural parsing
  (`parseHeaderPropertyName`) and domain validation
  (`validateHeaderForm`) are separate concerns.
- **Postel's law** — Server data is not rejected for unusual form
  combinations.
- **Total functions** — Both the constructor and the validator are total.
- **DRY** — `allowedForms` is the single source of truth.

### 2.7. BlueprintEmailHeaderName

**RFC reference:** §4.6 (constraint 4 — top-level `Content-*` rejection).

`BlueprintEmailHeaderName` is the validated header name used as a `Table`
key on `EmailBlueprint.extraHeaders`. Identity is name-only; the form
lives on the paired value (`BlueprintHeaderMultiValue`), so within-table
duplicates of the same name are structurally impossible.

```nim
type BlueprintEmailHeaderName* = distinct string
defineStringDistinctOps(BlueprintEmailHeaderName)
```

**Smart constructor:**

```nim
func parseBlueprintEmailHeaderName*(
    name: string
): Result[BlueprintEmailHeaderName, ValidationError]
```

Strict (no `*FromServer` sibling — creation vocabulary is unidirectional):

1. Non-empty.
2. All bytes in `0x21..0x7E` (printable ASCII; RFC 5322 §3.6.8 ftext).
3. No colon.
4. After lowercase normalisation: must not start with `"content-"`
   (RFC 8621 §4.6 constraint 4 — the `Content-*` family is managed by
   JMAP itself).

The first three checks are factored into a private `detectBlueprintCommon`
shared with `parseBlueprintBodyHeaderName`. A `BlueprintNameViolation`
enum names every failure mode (`bnvEmpty`, `bnvNonPrintable`,
`bnvContainsColon`, `bnvContentPrefix`, `bnvContentTransferEncoding`),
and a single `toValidationError(v, typeName, raw)` translator brands the
outer type name (`"BlueprintEmailHeaderName"` here, `"BlueprintBodyHeaderName"`
at §2.8). One translator, two callers, zero duplicated wire text.

**Principles:**
- **Newtype everything that has meaning** — Top-level header names and
  body-part header names are different concepts with different rules.
- **Parse, don't validate** — Strict validation at construction; the
  domain holds well-typed lowercased names.
- **DRY** — Common detector + parameterised translator.

### 2.8. BlueprintBodyHeaderName

**RFC reference:** §4.6 (constraint 9 — `Content-Transfer-Encoding`
rejection).

`BlueprintBodyHeaderName` is the validated header name used as a `Table`
key on `BlueprintBodyPart.extraHeaders`. Same shape as
`BlueprintEmailHeaderName` (distinct string, name-only identity, no
`*FromServer` sibling) but the per-context constraint differs:

```nim
type BlueprintBodyHeaderName* = distinct string
defineStringDistinctOps(BlueprintBodyHeaderName)
```

```nim
func parseBlueprintBodyHeaderName*(
    name: string
): Result[BlueprintBodyHeaderName, ValidationError]
```

Reuses `detectBlueprintCommon` for the structural rules (non-empty,
printable ASCII, no colon), then rejects the exact lowercase name
`"content-transfer-encoding"`. Other `Content-*` headers ARE permitted on
body parts (e.g., `Content-Type` is set automatically but the constraint
applies only to `Content-Transfer-Encoding`).

### 2.9. BlueprintHeaderMultiValue

**RFC reference:** §4.1.2 (parsed forms), §4.6 (creation).

`BlueprintHeaderMultiValue` carries one or more values for a single
creation header field, all sharing one parsed form. The case discriminant
enforces form uniformity; `NonEmptySeq[T]` enforces at-least-one-value.
This type has no standalone wire identity — wire-key composition lives at
the consumer aggregate (§2.11).

```nim
type BlueprintHeaderMultiValue* {.ruleOff: "objects".} = object
  case form*: HeaderForm
  of hfRaw:              rawValues*:        NonEmptySeq[string]
  of hfText:             textValues*:       NonEmptySeq[string]
  of hfAddresses:        addressLists*:     NonEmptySeq[seq[EmailAddress]]
  of hfGroupedAddresses: groupLists*:       NonEmptySeq[seq[EmailAddressGroup]]
  of hfMessageIds:       messageIdLists*:   NonEmptySeq[seq[string]]
  of hfDate:             dateValues*:       NonEmptySeq[Date]
  of hfUrls:             urlLists*:         NonEmptySeq[seq[string]]
```

`NonEmptySeq[T]` is a distinct seq with a smart constructor
(`parseNonEmptySeq`) and op-template instantiations
(`defineNonEmptySeqOps`). The instantiations needed for the seven
variants live at the top of `headers.nim`:

```nim
defineNonEmptySeqOps(string)
defineNonEmptySeqOps(Date)
defineNonEmptySeqOps(seq[EmailAddress])
defineNonEmptySeqOps(seq[EmailAddressGroup])
defineNonEmptySeqOps(seq[string])
```

Five op instantiations cover the seven variants — `string` backs both
`hfRaw` and `hfText`; `seq[string]` backs both `hfMessageIds` and `hfUrls`.

The wire shape (set at `composeHeaderKey` / `blueprintMultiValueToJson`
time) is:
- Cardinality 1 → emit a scalar value (a JString, a JArray of address
  objects, etc., depending on form). Wire key has no `:all` suffix.
- Cardinality > 1 → emit a JArray-of-values. Wire key gets `:all` (the
  `:all` suffix is decided at the consumer aggregate based on
  `multiLen`).

**Principles:**
- **Make illegal states unrepresentable** — Empty value lists are
  unrepresentable (`NonEmptySeq[T]`). Form mismatch between the discriminant
  and the variant fields is a compile error.
- **One source of truth per fact** — The form lives on the value, never on
  the key. Within-table duplicates of the same name are structurally
  impossible.

### 2.10. Blueprint multi-value constructors

For each `HeaderForm` variant, two smart constructors are provided —
`<form>Single` (infallible, single value) and `<form>Multi` (fallible if
the input seq is empty):

```nim
func rawSingle*(value: string): BlueprintHeaderMultiValue
func textSingle*(value: string): BlueprintHeaderMultiValue
func addressesSingle*(value: seq[EmailAddress]): BlueprintHeaderMultiValue
func groupedAddressesSingle*(value: seq[EmailAddressGroup]): BlueprintHeaderMultiValue
func messageIdsSingle*(value: seq[string]): BlueprintHeaderMultiValue
func dateSingle*(value: Date): BlueprintHeaderMultiValue
func urlsSingle*(value: seq[string]): BlueprintHeaderMultiValue

func rawMulti*(values: seq[string]): Result[BlueprintHeaderMultiValue, ValidationError]
func textMulti*(values: seq[string]): Result[BlueprintHeaderMultiValue, ValidationError]
func addressesMulti*(values: seq[seq[EmailAddress]]):
    Result[BlueprintHeaderMultiValue, ValidationError]
func groupedAddressesMulti*(values: seq[seq[EmailAddressGroup]]):
    Result[BlueprintHeaderMultiValue, ValidationError]
func messageIdsMulti*(values: seq[seq[string]]):
    Result[BlueprintHeaderMultiValue, ValidationError]
func dateMulti*(values: seq[Date]): Result[BlueprintHeaderMultiValue, ValidationError]
func urlsMulti*(values: seq[seq[string]]):
    Result[BlueprintHeaderMultiValue, ValidationError]
```

`*Single` constructs `NonEmptySeq[T]` directly via `@[value]`-coercion —
a literal one-element seq is statically non-empty, so the smart-constructor
ceremony is bypassed (this avoids `tryGet` calls that would conflict with
the module's `raises: []` pragma).

`*Multi` delegates to `parseNonEmptySeq`, propagating its
`ValidationError` with `typeName = "NonEmptySeq"` if the input is empty.

**Principles:**
- **Constructors that can't fail, don't** — `*Single` is total. `*Multi`
  is fallible only on the empty-seq case.
- **DRY** — One delegate (`parseNonEmptySeq`) per `*Multi`; no per-variant
  re-implementation of the non-empty check.

### 2.11. Serde — serde_headers.nim

**Module:** `src/jmap_client/mail/serde_headers.nim`

Follows established core serde patterns: `expectKind`, `fieldJString`,
`optJsonField`, `wrapInner`, and `SerdeViolation` errors with `JsonPath`
provenance.

#### EmailHeader serialisation

Wire format:

```json
{"name": "From", "value": "Joe Bloggs <joe@example.com>"}
```

`toJson` emits `name` and `value` as strings.

`fromJson(EmailHeader, node, path)`:
- `expectKind(node, JObject)`.
- Extracts `name` via `fieldJString` (required, rejects absent / null /
  non-string).
- Extracts `value` via `fieldJString` (required).
- Delegates to `parseEmailHeader` via `wrapInner` so the inner
  `ValidationError` is bridged to a `SerdeViolation` carrying the
  current path.

#### HeaderValue — parseHeaderValue

```nim
func parseHeaderValue*(
    form: HeaderForm,
    node: JsonNode,
    path: JsonPath = emptyJsonPath()
): Result[HeaderValue, SerdeViolation]
```

Dispatches on the form:

- `hfRaw`: `expectKind JString`, construct `HeaderValue(form: hfRaw, rawValue: ...)`.
- `hfText`: `expectKind JString`, construct.
- `hfAddresses`: `expectKind JArray`; each element via
  `EmailAddress.fromJson(elem, path / i)`.
- `hfGroupedAddresses`: `expectKind JArray`; each element via
  `EmailAddressGroup.fromJson(elem, path / i)`.
- `hfMessageIds`: routed through the shared `parseNullableStringArray`
  helper — JNull (or nil node) → `Opt.none(seq[string])`; JArray of
  JString → `Opt.some(seq)`.
- `hfDate`: JNull → `Opt.none(Date)`; otherwise `Date.fromJson`.
- `hfUrls`: routed through `parseNullableStringArray`.

`parseNullableStringArray` is a private helper because the message-id and
URL forms share the same nullable-string-array shape. It does not extend
to grouped-addresses or addresses (those are not nullable per the RFC).

The function takes `form` only, not the full `HeaderPropertyKey`. The
caller handles `:all` dispatch (the `Email.requestedHeadersAll` table is
built by iterating the JArray and calling `parseHeaderValue` per element).

#### HeaderValue — toJson

```nim
func toJson*(v: HeaderValue): JsonNode
```

Dispatches on `v.form`:
- `hfRaw` → JString from `rawValue`.
- `hfText` → JString from `textValue`.
- `hfAddresses` → JArray of `EmailAddress.toJson` per element.
- `hfGroupedAddresses` → JArray of `EmailAddressGroup.toJson`.
- `hfMessageIds`: `Opt.none` → `newJNull()`; `Opt.some` → JArray of
  JString.
- `hfDate`: `Opt.none` → `newJNull()`; `Opt.some` → `Date.toJson`.
- `hfUrls`: `Opt.none` → `newJNull()`; `Opt.some` → JArray of JString.

#### Blueprint header-name serde

Both distinct-string types use the standard borrow templates:

```nim
defineDistinctStringToJson(BlueprintEmailHeaderName)
defineDistinctStringFromJson(BlueprintEmailHeaderName, parseBlueprintEmailHeaderName)
defineDistinctStringToJson(BlueprintBodyHeaderName)
defineDistinctStringFromJson(BlueprintBodyHeaderName, parseBlueprintBodyHeaderName)
```

The `fromJson` routes through the strict smart constructor — there is no
lenient counterpart because the server never sends these names back. The
serde definitions are present for symmetry with the rest of the
distinct-string family; they are not exercised on the inbound path.

#### multiLen — cardinality probe

```nim
func multiLen*(m: BlueprintHeaderMultiValue): int
```

Returns the underlying `NonEmptySeq` length for any variant. The case
object wraps seven differently-named fields, so no borrowed `len` exists
on `BlueprintHeaderMultiValue` directly. Consumer aggregates use this to
decide whether to append `:all` to the wire key.

#### composeHeaderKey — wire-key composition

```nim
func composeHeaderKey*[T: BlueprintEmailHeaderName or BlueprintBodyHeaderName](
    name: T, form: HeaderForm, isAll: bool
): string
```

Composes `"header:<name>[:as<Form>][:all]"`. Form suffix is omitted for
`hfRaw` (matches `toPropertyString`'s convention from §2.3). Generic over
both header-name newtypes — the wire rule is one fact; the two types
share the rule but split the context-validation rules at construction
time.

The caller decides `isAll` (typically `multiLen(mv) > 1`).

#### blueprintMultiValueToJson — variant dispatcher

```nim
func blueprintMultiValueToJson*(m: BlueprintHeaderMultiValue): JsonNode
```

Public dispatcher. Consumer aggregates (`EmailBlueprint.toJson` in
serde_email_blueprint.nim, `BlueprintBodyPart.toJson` in serde_body.nim)
compose the wire key via `composeHeaderKey` and pair it with the output
of this dispatcher.

Five private helpers carry the per-form cardinality logic:

- `neStringToJson`: cardinality 1 → JString; otherwise JArray of JString
  (covers `hfRaw`, `hfText`).
- `neAddrListsToJson`: cardinality 1 → JArray of address objects;
  otherwise JArray of JArrays (covers `hfAddresses`).
- `neGroupListsToJson`: cardinality 1 → JArray of group objects;
  otherwise JArray of JArrays (covers `hfGroupedAddresses`).
- `neStringSeqToJson`: cardinality 1 → flat JArray of JString; otherwise
  JArray of JArrays (covers `hfMessageIds`, `hfUrls`).
- `neDateToJson`: cardinality 1 → JString (RFC 3339); otherwise JArray
  of JString (covers `hfDate`).

The cardinality-1 case emits the inner shape directly; the multi case
emits an array of inner shapes. The wire result for cardinality 1 with
`hfRaw` is a JString, not a one-element JArray — matching how single
values are sent on JMAP without the `:all` suffix.

**Principles:**
- **Parse, don't validate** — `parseHeaderValue` transforms raw JSON into
  a typed `HeaderValue`.
- **Total functions** — Every valid input maps to `ok` or `err`.
- **DDD** — Header serde knowledge lives in the header serde module.
- **Make illegal states unrepresentable** — `NonEmptySeq` rules out
  empty-array emission; the case discriminant rules out form mismatch.

---

## 3. Body Sub-Types — body.nim

**Module:** `src/jmap_client/mail/body.nim`

Body sub-types define the structural vocabulary for Email body parts —
the read model (`EmailBodyPart`) and the creation model
(`BlueprintBodyPart`). Both share `PartId`, the `isMultipart` discriminant
pattern, and the `MaxBodyPartDepth` recursion bound. Creation-side
constraints that differ from the read model (inline vs blob-ref source,
no flags on `BlueprintBodyValue`, lowercase typed header names) are lifted
into separate types so the parser only enforces what cannot be encoded
in types.

### 3.1. MaxBodyPartDepth

```nim
const MaxBodyPartDepth* = 128
```

Public depth bound for body-part trees. Carried as a type-level
invariant by `parseEmailBlueprint` — trees exceeding this depth are
rejected at construction via `ebcBodyPartDepthExceeded`, so the
`BlueprintBodyPart` serialiser can recurse unconditionally.
`EmailBodyPart.fromJson` uses the same bound defensively at the wire-in
boundary (Postel's law — adversarial servers).

128 matches the `Filter[C]` precedent from `serde_framework.nim` —
consistent depth cap for every recursive serde site in the project.

### 3.2. PartId

**RFC reference:** §4.1.4.

A `PartId` identifies a body part uniquely within an Email. Used by
`EmailBodyPart` (read-model leaf parts) and `BlueprintLeafPart` (creation
inline leaves) as the key into the top-level `bodyValues` map.

```nim
type PartId* = distinct string
defineStringDistinctOps(PartId)
```

**Smart constructor:**

```nim
func parsePartIdFromServer*(raw: string): Result[PartId, ValidationError]
```

Validates: non-empty, no control characters (`< 0x20`). No length limit —
RFC 8621 types `partId` as `String` (not `Id`), so the 1–255 octet
constraint from RFC 8620's `Id` definition does not apply. The
control-character rejection is a defensive Postel's-law measure; no
compliant server would emit them.

Single parser, named `parsePartIdFromServer` per the project-wide naming
convention: all `fromJson` for distinct types route through the lenient
`*FromServer` parser. There is no strict `parsePartId` sibling — the
read-model and creation-model constraints are identical (both the server
and the client choose part identifiers from the same string space), so a
single parser covers both directions.

**Principles:**
- **Newtype everything that has meaning** — `PartId` is not interchangeable
  with arbitrary strings or with `Id`.
- **Parse, don't validate** — Smart constructor enforces invariants at
  the construction boundary.
- **One source of truth** — `partId` constraints derive from RFC 8621's
  `String` typing, not from `Id`'s.

### 3.3. ContentDisposition

**RFC reference:** RFC 2183 §2.1, §2.8 (cited via JMAP §4.1.4).

`ContentDisposition` is a validated wrapper around RFC 2183's
disposition-type token. The RFC §2.1 names two well-known values
(`inline`, `attachment`) and §2.8 explicitly mandates handling unknown
values — the `cdExtension` arm is the escape hatch for vendor extensions
and `x-` tokens.

```nim
type ContentDispositionKind* = enum
  cdInline     = "inline"
  cdAttachment = "attachment"
  cdExtension                    ## no string backing — see below

type ContentDisposition* {.ruleOff: "objects".} = object
  case rawKind: ContentDispositionKind
  of cdExtension:
    rawIdentifier: string         ## module-private — preserved verbatim
  of cdInline, cdAttachment:
    discard
```

Sealed (Pattern A): `rawKind` and `rawIdentifier` are module-private.
External code cannot literally construct a `ContentDisposition` — it
must use `parseContentDisposition` for untrusted input or the named
constants for the IANA-registered values:

```nim
const
  dispositionInline*     = ContentDisposition(rawKind: cdInline)
  dispositionAttachment* = ContentDisposition(rawKind: cdAttachment)
```

**UFCS accessors:**

```nim
func kind*(d: ContentDisposition): ContentDispositionKind
func identifier*(d: ContentDisposition): string
func `$`*(d: ContentDisposition): string                ## delegates to identifier
func `==`*(a, b: ContentDisposition): bool
func hash*(d: ContentDisposition): Hash
```

`identifier` returns `$d.rawKind` for the two well-known kinds (the
enum's backing string) and `d.rawIdentifier` for `cdExtension`. `==` and
`hash` are hand-rolled to support strict-case-objects: structural
equality on a case object would fail compilation otherwise (see
`nim-type-safety.md`).

**Smart constructor:**

```nim
func parseContentDisposition*(
    raw: string
): Result[ContentDisposition, ValidationError]
```

1. `detectNonControlString` — non-empty, no control characters.
2. `toLowerAscii` — RFC 2183 §2.1 specifies values are not case-sensitive.
3. `parseEnum[ContentDispositionKind](normalised, cdExtension)` — falls
   back to `cdExtension` for tokens that don't match the two IANA values.
4. For `cdExtension`, captures the lowercased token in `rawIdentifier`.

Single parser — same rationale as `parseMailboxRole` (§13.1 of mail
architecture): the token has one set of structural rules, and the
extension arm absorbs anything semantically unknown. Lossless wire
round-trip for all three cases.

**Principles:**
- **Make illegal states unrepresentable** — Closed RFC vocabulary is closed
  at the type level; vendor extensions live in their own arm.
- **Parse, don't validate** — Lowercase canonical form, same pattern as
  `Keyword`, `MailboxRole`, `HeaderPropertyKey.name`.
- **DDD** — Disposition is its own bounded sub-context; consumers use
  named constants or the parser.

### 3.4. EmailBodyPart

**RFC reference:** §4.1.4.

`EmailBodyPart` represents the MIME structure of an email body as
received from the server. Recursive case object discriminated by
`isMultipart` — multipart nodes carry child parts, leaf nodes carry a
`PartId` and `BlobId`.

**Type definition:**

```nim
type EmailBodyPart* {.ruleOff: "objects".} = object
  ## Shared fields (all parts):
  headers*:     seq[EmailHeader]      ## raw MIME headers; @[] if absent
  name*:        Opt[string]           ## decoded filename
  contentType*: string                ## e.g. "text/plain", "multipart/mixed"
  charset*:     Opt[string]           ## server-provided or implicit "us-ascii"
  disposition*: Opt[ContentDisposition]
  cid*:         Opt[string]           ## Content-Id without angle brackets
  language*:    Opt[seq[string]]      ## Content-Language tags
  location*:    Opt[string]           ## Content-Location URI
  size*:        UnsignedInt           ## RFC unconditional — all parts

  case isMultipart*: bool
  of true:
    subParts*: seq[EmailBodyPart]     ## recursive children
  of false:
    partId*:   PartId                 ## unique within the Email
    blobId*:   BlobId                 ## typed blob reference
```

**`contentType` field naming.** The field is named `contentType` because
the domain concept is Content-Type (RFC 2045 §5). JMAP's wire format
uses the abbreviated key `"type"`; the serde layer maps between the two.
JMAP's abbreviation is not the source of truth for the domain model.

**`isMultipart` discriminant.** Derived from `contentType` at the
parsing boundary: `ctLower.startsWith("multipart/")`. The check is
case-insensitive (the boundary lowercases `contentType` once and
re-uses the result for the `text/*` charset default).

**`headers` field.** `seq[EmailHeader]`, not `Opt[seq[EmailHeader]]`.
Every MIME part has headers (possibly zero). The collection may be empty;
the field is never conceptually absent. `fromJson` defaults to `@[]` if
absent or non-array.

**`charset` field.** `Opt[string]` with two states per the RFC: a string
value (explicit charset parameter or implicit `"us-ascii"` for `text/*`),
or `Opt.none` (not `text/*`). The serde layer applies the RFC default in
the same parse pass that derives `isMultipart` (it already inspects
`ctLower`). Postel's law: a non-compliant server sending `null` charset
for a `text/*` part gets the default applied rather than ambiguity passed
inward.

**`disposition` field.** `Opt[ContentDisposition]` (typed), not
`Opt[string]`. The serde layer routes through `parseContentDisposition`
so unknown vendor tokens land in `cdExtension` and the two IANA values
land in `dispositionInline` / `dispositionAttachment`. Malformed
disposition tokens (empty, control characters) surface as
`SerdeViolation` at the boundary — they are not silently round-tripped.

**`size` field.** `UnsignedInt` on all parts, including multipart. RFC
8621 §4.1.4 specifies `size` unconditionally. The serde layer requires
`size` on leaf parts and defaults to `UnsignedInt(0)` on multipart parts
if absent — leniency where safe, since multipart size is non-informative.

**`blobId` field.** `BlobId` (the typed distinct from core's
`identifiers.nim`), not `Id`. Blob references and entity IDs cannot be
silently exchanged.

No smart constructor for the read model — `fromJson` extracts fields,
validates JSON structure, and constructs directly.

**Principles:**
- **Make illegal states unrepresentable** — Case discriminant encodes the
  RFC invariant: multipart parts have `subParts`; leaf parts have
  `partId` / `blobId`.
- **One source of truth per fact** — `contentType` determines
  `isMultipart`; the boundary's lowercased `ctLower` determines both
  `isMultipart` and the `text/*` charset default.
- **Parse, don't validate** — Disposition is parsed once; consumers see
  `Opt[ContentDisposition]`, not raw strings.
- **Code reads like the spec** — Every RFC §4.1.4 property is a field.

### 3.5. EmailBodyValue

**RFC reference:** §4.1.4.

An `EmailBodyValue` carries decoded text content for a body part,
referenced by `PartId` in the read-model `bodyValues` map on `Email`.

```nim
type EmailBodyValue* {.ruleOff: "objects".} = object
  value*:             string  ## decoded text content
  isEncodingProblem*: bool    ## default false
  isTruncated*:       bool    ## default false
```

Plain public fields, no smart constructor. All combinations of the three
fields are valid for the read model — the server may set either flag to
`true` to indicate encoding problems or truncation.

The creation constraint (both flags MUST be `false`) is encoded by a
separate type (§3.6), not by validation.

**Principles:**
- **Constructors that can't fail, don't** — All field combinations are
  valid for the read model.
- **Code reads like the spec** — Three RFC-defined properties.
- **DDD** — Creation constraints live on the creation type.

### 3.6. BlueprintBodyValue

**RFC reference:** §4.1.4 / §4.6 constraint 6.

`BlueprintBodyValue` is the creation-time companion to `EmailBodyValue`.
It strips both flags — RFC 8621 §4.6 mandates them `false` on creation,
and the stripped type makes the illegal state unrepresentable rather
than runtime-validated.

```nim
type BlueprintBodyValue* {.ruleOff: "objects".} = object
  value*: string  ## decoded body content
```

Plain object — no smart constructor (the only field is unconstrained).
Lives co-located with the part it belongs to: each `BlueprintLeafPart`
of source `bpsInline` carries its own `BlueprintBodyValue` (§3.8). The
serde layer harvests these into a top-level `bodyValues` JSON object at
emission time.

**Principles:**
- **Make illegal states unrepresentable** — No flags means no way to
  emit `isEncodingProblem: true` on creation.
- **DDD** — Read-model and creation-model body values are different
  domain concepts with different constraints.

### 3.7. BlueprintPartSource

**RFC reference:** §4.6.

`BlueprintPartSource` discriminates how a leaf body part's content is
sourced during Email creation: inline (referenced by `PartId` into a
co-located `BlueprintBodyValue`) or blob-referenced (by `BlobId`).

```nim
type BlueprintPartSource* = enum
  bpsInline    ## partId → co-located BlueprintBodyValue
  bpsBlobRef   ## blobId → uploaded blob reference
```

Plain enum, no string backing. String-backed enums in this codebase
encode wire-format mappings (`HeaderForm`, `ContentDispositionKind`,
`MailboxRole`). `BlueprintPartSource` has no wire-format string
representation — the discriminant is derived by the consumer's
construction (which fields are populated), not by a field on the wire.

**Principles:**
- **Make illegal states unrepresentable** — Two-variant enum expresses the
  XOR constraint.
- **One source of truth** — No wire string exists; no string backing
  pretends one does.

### 3.8. BlueprintLeafPart

**RFC reference:** §4.6.

`BlueprintLeafPart` is the content half of a non-multipart
`BlueprintBodyPart`. Extracted into its own type so each discriminator
(`BlueprintBodyPart.isMultipart` and `BlueprintLeafPart.source`) lives on
a separate type — Nim's `strictCaseObjects` flow analysis does not
propagate nested case-object facts across multiple discriminators on the
same type, so hoisting the inner case into its own type is the
structural fix (see `nim-type-safety.md` "Rule 4 — Nested case objects").

```nim
type BlueprintLeafPart* {.ruleOff: "objects".} = object
  case source*: BlueprintPartSource
  of bpsInline:
    partId*: PartId               ## reference to the body value
    value*:  BlueprintBodyValue   ## co-located body content
  of bpsBlobRef:
    blobId*:  BlobId
    size*:    Opt[UnsignedInt]    ## optional, ignored by server
    charset*: Opt[string]
```

**Co-located inline value.** `bpsInline` carries both `partId` AND
`value` together. The serde layer harvests every `bpsInline` value into
a top-level `bodyValues: { partId: { value } }` JSON object at emission
time. Callers do not pass a separate `bodyValues` table — they put each
inline value next to the part it belongs to. This eliminates the
"partId without bodyValues entry" failure mode at the type level.

**bpsBlobRef fields.** `size` and `charset` are `Opt[T]`. The RFC says
they are optional on creation and the server ignores them; their presence
is harmless. The case object guarantees they are absent on `bpsInline`
parts.

**Principles:**
- **Make illegal states unrepresentable** — Nested case object encodes
  the RFC MUST-omit constraints. `charset` with `partId` is uncompilable.
- **One source of truth** — Co-located inline values mean the `partId`
  cannot reference a missing `bodyValues` entry.

### 3.9. BlueprintBodyPart

**RFC reference:** §4.6.

`BlueprintBodyPart` represents the body structure for Email creation. It
discriminates multipart containers from leaves; leaves delegate to
`BlueprintLeafPart` for their inner discriminant.

```nim
type BlueprintBodyPart* {.ruleOff: "objects".} = object
  contentType*:  string
  name*:         Opt[string]
  disposition*:  Opt[ContentDisposition]
  cid*:          Opt[string]
  language*:     Opt[seq[string]]
  location*:     Opt[string]
  extraHeaders*: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]

  case isMultipart*: bool
  of true:
    subParts*: seq[BlueprintBodyPart]   ## recursive children
  of false:
    leaf*: BlueprintLeafPart
```

**Outer / inner discriminator split.** Outer `isMultipart` (this type)
separates containers from leaves; inner `BlueprintLeafPart.source`
(§3.8) separates inline leaves from blob-referenced leaves. The split is
load-bearing for `strictCaseObjects` flow analysis.

**`extraHeaders` typing.** `Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]`
— typed name keys (lowercased, validated for body-part context) paired
with form-discriminated multi-values. The form lives on the value, not
the key, so the table cannot encode duplicate names with different
forms. Form consistency between the wire-key suffix and the value
variant is structurally enforced.

**`disposition` typing.** `Opt[ContentDisposition]` — the same typed
disposition as the read model. Vendor extensions are accepted via
`cdExtension`.

**No raw `headers` field.** `EmailBodyPart` carries
`headers: seq[EmailHeader]` (raw headers from the server).
`BlueprintBodyPart` has only `extraHeaders` (typed, parsed). Having both
would create two sources of truth for the same header data and would
require un-parsing typed values back to strings, violating the
directional flow of "parse once at the boundary."

**Content-Transfer-Encoding restriction.** RFC 8621 §4.6 specifies that
`Content-Transfer-Encoding` MUST NOT be given on creation body parts.
Enforced structurally by `BlueprintBodyHeaderName`'s smart constructor —
the typed key cannot be constructed for that name, so the table cannot
contain the offending entry.

**Top-level `Content-*` restriction.** RFC 8621 §4.6 also forbids most
`Content-*` headers at the **top level** of a creation. Enforced
structurally by `BlueprintEmailHeaderName`'s smart constructor (§2.7).
The body-part variant is more permissive (other `Content-*` headers ARE
allowed on body parts).

No smart constructor for `BlueprintBodyPart` itself — field types and
the nested case object capture structural invariants. Cross-field and
cross-part constraints (header duplicates, allowed-form rule, depth)
are enforced by the consuming `EmailBlueprint` smart constructor (Design D).

**Principles:**
- **Make illegal states unrepresentable** — Outer / inner discriminator
  split + typed name keys + `NonEmptySeq` value lists rule out a long
  list of failure modes at the type level.
- **One source of truth** — No `headers` field on the creation model.
- **Parse once at the boundary** — `extraHeaders` uses typed names and
  values throughout.
- **DDD** — Creation vocabulary (structural shape) and creation model
  (the email being created) are different concerns; this type is
  vocabulary, `EmailBlueprint` is the model.

### 3.10. Serde — serde_body.nim

**Module:** `src/jmap_client/mail/serde_body.nim`

Follows established core serde patterns (`expectKind`, `fieldJString`,
`optJsonField`, `wrapInner`, `JsonPath`-aware errors).

#### PartId serialisation

Standard distinct-string templates:

```nim
defineDistinctStringToJson(PartId)
defineDistinctStringFromJson(PartId, parsePartIdFromServer)
```

#### EmailBodyPart — fromJson

Wire format (leaf example):

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

Wire format (multipart example):

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

Recursive parsing with depth limit:

```nim
func fromJsonImpl(
    node: JsonNode, depth: int, path: JsonPath
): Result[EmailBodyPart, SerdeViolation]

func fromJson*(
    T: typedesc[EmailBodyPart],
    node: JsonNode,
    path: JsonPath = emptyJsonPath()
): Result[EmailBodyPart, SerdeViolation]
```

The public entry point hands `MaxBodyPartDepth` to the implementation.

The implementation is decomposed into focused helpers — each pulls one
field group with its own JSON-shape rules:

- `parseOptString(node, key)` — absent / null / wrong-kind → `Opt.none`;
  string present → `Opt.some(...)`. Used for `name`, `cid`, `location`.
- `parseOptDisposition(node, path)` — absent / null / wrong-kind →
  `Opt.none`; string present → routed through `parseContentDisposition`
  via `wrapInner`. Malformed tokens surface at the parse boundary.
- `parseCharsetField(node, ctLower)` — string present →
  `Opt.some(value)`; absent / null and `ctLower.startsWith("text/")` →
  `Opt.some("us-ascii")` (RFC §4.1.4 default applied for compliant and
  non-compliant servers alike); absent / null and not `text/*` → `Opt.none`.
- `parseLanguageField(node, path)` — non-array (absent / null / wrong
  kind) → `Opt.none`; JArray → `Opt.some(seq)` with each element
  validated as JString.
- `parseSizeField(node, isMultipart, path)` — absent / non-int and
  multipart → `UnsignedInt(0)`; otherwise delegate to `UnsignedInt.fromJson`
  (which surfaces wrong-kind, negative, or out-of-range as
  `SerdeViolation`).
- `parseHeadersField(node, path)` — absent / non-array → `@[]`; JArray →
  each element via `EmailHeader.fromJson`.

The recursive driver (`fromJsonImpl`):

1. `expectKind JObject`; if `depth <= 0`, return
   `SerdeViolation(kind: svkDepthExceeded, path, maxDepth: MaxBodyPartDepth)`.
2. Extract `"type"` via `fieldJString` → `contentType`. Lowercase it once
   into `ctLower` for both the multipart check and the charset default.
3. `isMultipart = ctLower.startsWith("multipart/")` — the discriminant is
   derived from `contentType`, never from `subParts` presence.
4. Run the six helpers above to extract shared fields.
5. Multipart branch: extract `subParts` (absent / non-array → `@[]`,
   per Postel's law); recurse with `depth - 1` per child. `partId` and
   `blobId` are ignored even if present.
6. Leaf branch: extract `partId` and `blobId` via the distinct-string
   `fromJson`s. `subParts` is ignored if present.

#### EmailBodyPart — toJson

Recursive serialisation with depth limit. `toJson` must be total over the
recursive type, so the depth limit is symmetric with `fromJson`.

```nim
func toJsonImpl(part: EmailBodyPart, depth: int): JsonNode
func toJson*(part: EmailBodyPart): JsonNode
```

Public entry hands `MaxBodyPartDepth`. At depth exhaustion, `toJsonImpl`
returns a partial JObject containing only `"type"` — the truncated
output preserves totality without crashing on a pathologically deep tree.

Field emission:
- `"type"` ← `contentType`.
- `"headers"` always emitted (a JArray, possibly empty).
- `"name"`, `"charset"`, `"cid"`, `"location"` use `optStringToJsonOrNull` →
  string or `null`.
- `"disposition"` → `$d` for `Opt.some`, `null` for `Opt.none`.
- `"language"` → JArray of JString or `null`.
- `"size"` → `UnsignedInt.toJson`.

Branch-specific (`case part.isMultipart` — case, not if, for
`strictCaseObjects`):
- multipart → `"subParts"` JArray of recursive children.
- leaf → `"partId"`, `"blobId"`.

#### EmailBodyValue serialisation

Wire format:

```json
{
  "value": "Hello, world!",
  "isEncodingProblem": false,
  "isTruncated": false
}
```

`fromJson(EmailBodyValue, node, path)`:
- `expectKind JObject`.
- `value` extracted via `fieldJString` (required).
- `isEncodingProblem` and `isTruncated`: absent or null → default
  `false`; non-bool → `SerdeViolation(kind: svkWrongKind)` at
  `path / "isEncodingProblem"` etc.

`toJson` always emits all three fields (explicit is safer than relying
on defaults).

#### BlueprintBodyValue — toJson only

```nim
func toJson*(v: BlueprintBodyValue): JsonNode = %*{"value": v.value}
```

No `fromJson` — creation types are unidirectional.

#### BlueprintBodyPart — toJson only

`BlueprintBodyPart` is a creation type. Bidirectional serde would create
a second construction path bypassing the smart-constructor chain
(`EmailBlueprint` is the only construction path); the same pattern as
`IdentityCreate` (Design A) and `MailboxCreate` (Design B).

Recursive serialisation, **unbounded by construction**:
`parseEmailBlueprint` rejects trees deeper than `MaxBodyPartDepth` via
`ebcBodyPartDepthExceeded`, so a well-typed blueprint is guaranteed to
fit the stack budget. The serde function simply recurses without a
depth parameter:

```nim
func bpToJsonImpl(bp: BlueprintBodyPart): JsonNode
func toJson*(bp: BlueprintBodyPart): JsonNode
```

Field emission:
- `"type"` ← `contentType`.
- Optional shared fields (`name`, `cid`, `location`) emitted via
  `emitOpt` — present → string; absent → key omitted (NOT null).
- `"disposition"` → `$d` when present; absent → key omitted.
- `"language"` via `emitLanguage` — present → JArray; absent → key
  omitted.
- `extraHeaders` — for each `(name, mv)` entry, compose the wire key via
  `composeHeaderKey(name, mv.form, isAll)` where
  `isAll = multiLen(mv) > 1`, then assign
  `blueprintMultiValueToJson(mv)` to that key.

Branch-specific (`case bp.isMultipart`, then `case bp.leaf.source` —
each discriminator on its own type, so `strictCaseObjects` tracks them
independently):

- multipart → `"subParts"` JArray of recursive children.
- leaf inline (`bpsInline`) → `"partId"` only. `bp.leaf.value` is NOT
  emitted here — `EmailBlueprint.toJson` harvests every inline value into
  the top-level `bodyValues` JSON object (Design D).
- leaf blob-ref (`bpsBlobRef`) → `"blobId"`; `"size"` and `"charset"`
  emitted only when `Opt.some`.

Wire-shape examples:

```json
// inline leaf (charset/size/blobId KEYS ABSENT, not null)
{"type": "text/plain", "partId": "1", "disposition": "inline"}

// blob-ref leaf
{
  "type": "image/png",
  "blobId": "abc123",
  "charset": "utf-8",
  "size": 5678,
  "name": "photo.png",
  "disposition": "attachment"
}

// multipart
{
  "type": "multipart/mixed",
  "subParts": [
    {"type": "text/plain", "partId": "1"},
    {"type": "image/png", "blobId": "abc123"}
  ]
}
```

Key omission for `bpsInline` is a consequence of the case-object
structure, not a serialisation convention — the inner fields do not
exist on the `bpsInline` variant, so the serialiser cannot emit keys
for fields that are not there.

**Principles:**
- **Total functions** — Depth limit on `EmailBodyPart` makes recursive
  serde total over unbounded types; `BlueprintBodyPart` is total because
  the type itself is bounded by construction.
- **Parse, don't validate** — `EmailBodyPart.fromJson` transforms raw
  JSON into a fully-typed recursive structure; disposition tokens are
  parsed.
- **Make illegal states unrepresentable** — Key omission for `bpsInline`
  is a consequence of the case object, not a convention.
- **DDD** — Body serde knowledge lives in the body serde module.

---

## 4. Test Specification

Test scenarios live across five files, each owning a clearly delimited
slice of the Part C surface:

| File | Scope |
|------|-------|
| `tests/unit/mail/theaders.nim` | `HeaderForm`, `EmailHeader` smart constructor, `HeaderPropertyKey`, `allowedForms`, `validateHeaderForm` |
| `tests/unit/mail/theaders_blueprint.nim` | `BlueprintEmailHeaderName`, `BlueprintBodyHeaderName`, `BlueprintHeaderMultiValue` |
| `tests/unit/mail/tbody.nim` | `PartId` smart constructor, compile-time access checks for `EmailBodyPart` and `BlueprintBodyPart` case branches |
| `tests/serde/mail/tserde_headers.nim` | `EmailHeader` serde, `parseHeaderValue`, `HeaderValue.toJson` |
| `tests/serde/mail/tserde_body.nim` | `EmailBodyPart` serde (incl. depth limit, charset default, content-type edges), `EmailBodyValue` serde, `BlueprintBodyPart.toJson`, adversarial scenarios |

Property-based tests live in `tests/property/tprop_mail_c.nim`.
`ContentDisposition` has no direct unit test file — it is exercised
exclusively through the `EmailBodyPart` round-trip suite, which covers
each of the three variants (`cdInline`, `cdAttachment`, `cdExtension`)
plus malformed-token rejection.

### 4.1. HeaderForm — `theaders.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 1 | `parseHeaderForm` for all 7 known suffixes (`asRaw` … `asURLs`) | `ok` with the matching variant |
| 2 | `parseHeaderForm("asURLs")` — `nimIdentNormalize` matching | `ok(hfUrls)` |
| 3 | `parseHeaderForm("asUnknown")` | `err`, `typeName == "HeaderForm"`, message `"unknown header form suffix"` |
| 4 | `$hfRaw == "asRaw"`, `$hfUrls == "asURLs"`, etc. — backing strings preserved | passes (load-bearing for `toPropertyString`) |
| 4a | `parseHeaderForm("")` | `err`, message `"empty form suffix"` |
| 4b | `parseHeaderForm("as_Addresses")` — underscore tolerance | `ok(hfAddresses)` (`nimIdentNormalize` strips underscores) |

### 4.2. EmailHeader unit + serde — `theaders.nim` + `tserde_headers.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 5 | `parseEmailHeader("From", "joe@example.com")` | `ok` |
| 6 | `parseEmailHeader("", "value")` | `err`, message `"name must not be empty"` |
| 7 | `parseEmailHeader("X-Custom", "")` — empty value | `ok` |
| 8 | `EmailHeader.toJson` produces `{"name", "value"}` | structural match |
| 9 | `fromJson(toJson(eh))` round-trip | identity |
| 10 | `parseEmailHeader` with control character in name (e.g. `"From\x00"`) | `ok` (lenient — server provides arbitrary names) |
| 11 | `parseEmailHeader` with whitespace-only name | `ok` (lenient) |
| 11a | `EmailHeader.fromJson` on JArray | `err(SerdeViolation)` |
| 11b | absent `"name"` field | `err` |
| 11c | null `"name"` field | `err` |
| 11d | wrong-kind `"name"` (e.g. JInt) | `err` |
| 11e | absent `"value"` field | `err` |
| 11f | null `"value"` field | `err` |

### 4.3. HeaderPropertyKey — `theaders.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 12 | `parseHeaderPropertyName("header:From:asAddresses")` | `ok`, name `"from"`, form `hfAddresses`, `isAll == false` |
| 13 | `parseHeaderPropertyName("header:Subject:asText")` | `ok`, form `hfText` |
| 14 | `parseHeaderPropertyName("header:From:asAddresses:all")` | `ok`, `isAll == true` |
| 15 | `parseHeaderPropertyName("header:From")` — name only | `ok`, form `hfRaw`, `isAll == false` |
| 16 | `parseHeaderPropertyName("header:From:all")` — `:all` without form | `ok`, form `hfRaw`, `isAll == true` |
| 17 | `parseHeaderPropertyName("From:asAddresses")` — missing prefix | `err` |
| 18 | `parseHeaderPropertyName("header::asAddresses")` — empty name | `err` |
| 19 | `parseHeaderPropertyName("header:From:asUnknown")` — bad form | `err` |
| 20 | `parseHeaderPropertyName("header:FROM:asRaw")` — uppercase name | `ok`, name normalised to `"from"` |
| 21 | `toPropertyString` with form → `"header:from:asAddresses"` | passes |
| 22 | `toPropertyString` for `hfRaw` omits the form suffix → `"header:from"` | passes |
| 23 | `toPropertyString` with `isAll` → `"header:from:asAddresses:all"` | passes |
| 24 | `toPropertyString` round-trip via `parseHeaderPropertyName` | identity |
| 25 | `parseHeaderPropertyName("header:From:asRaw")` — explicit `hfRaw` | `ok`, form `hfRaw`, `isAll == false` |
| 26 | `parseHeaderPropertyName("header:From:asRaw:all")` | `ok`, form `hfRaw`, `isAll == true` |
| 27 | `parseHeaderPropertyName("header:X-My:Custom:asText")` — too many segments / unrecognised middle form | `err` |
| 28 | `parseHeaderPropertyName("header:FROM:asAddresses")` — uppercase name | `ok`, name normalised to `"from"` |
| 29 | `parseHeaderPropertyName("header:From:asaddresses")` lowercases through `nimIdentNormalize` → `hfAddresses`; `"ASADDRESSES"` does NOT (first-char case preserved) → `err` | passes |
| 29a | `parseHeaderPropertyName("")` | `err` |
| 29b | `parseHeaderPropertyName("header:From:asAddresses:")` — trailing colon | `err` (third segment is empty, not `"all"`) |
| 29c | `parseHeaderPropertyName("header:From:asAddresses:ALL")` — uppercase `:all` | `ok`, `isAll == true` (case-insensitive `cmpIgnoreCase`) |
| 29d | `parseHeaderPropertyName("header:From:as_Addresses")` — underscore tolerance | `ok`, form `hfAddresses` |
| 29e | `==` and `hash` of keys parsed from `"header:FROM:..."` and `"header:from:..."` | equal |

### 4.4. HeaderValue — `tserde_headers.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 30 | `parseHeaderValue(hfRaw, %"...")` | `ok`, `rawValue == "..."` |
| 31 | `parseHeaderValue(hfText, %"...")` | `ok`, `textValue == "..."` |
| 32 | `parseHeaderValue(hfAddresses, JArray of address objects)` | `ok` |
| 33 | `parseHeaderValue(hfGroupedAddresses, JArray of group objects)` | `ok` |
| 34 | `parseHeaderValue(hfMessageIds, JArray of JString)` | `ok`, `Opt.some(seq)` |
| 35 | `parseHeaderValue(hfMessageIds, JNull)` | `ok`, `Opt.none(seq[string])` |
| 36 | `parseHeaderValue(hfDate, JString date)` | `ok`, `Opt.some(Date)` |
| 37 | `parseHeaderValue(hfDate, JNull)` | `ok`, `Opt.none(Date)` |
| 38 | `parseHeaderValue(hfUrls, JArray of JString)` | `ok`, `Opt.some(seq)` |
| 39 | `parseHeaderValue(hfUrls, JNull)` | `ok`, `Opt.none(seq[string])` |
| 40 | `parseHeaderValue(hfRaw, %42)` — wrong kind | `err(SerdeViolation, svkWrongKind)` |
| 41 | `parseHeaderValue(hfAddresses, %"not an array")` — wrong kind | `err` |
| 42 | `HeaderValue.toJson` for each of 7 forms (Some variants) | structural match |
| 43 | Round-trip per form (Some + None where applicable) | identity |
| 44 | `HeaderValue.toJson` for `hfDate` with `Opt.none` → `JNull` | passes |
| 45 | `parseHeaderValue(hfAddresses, %*[])` — empty array | `ok`, empty addresses seq |
| 46 | `parseHeaderValue(hfGroupedAddresses, %*[])` | `ok`, empty groups seq |
| 47 | `parseHeaderValue(hfMessageIds, %*[])` | `ok`, `Opt.some(@[])` |
| 48 | `parseHeaderValue(hfUrls, %*[])` | `ok`, `Opt.some(@[])` |
| 49 | Malformed address element (object missing `email`) | `err` |
| 50 | Malformed date string | `err` |
| 51 | Wrong JSON kinds for the remaining forms (`hfText`, `hfGroupedAddresses`, `hfMessageIds`, `hfDate`, `hfUrls`) | `err` |
| 52 | JNull for non-nullable form (`hfAddresses`) | `err` |
| 52a | `parseHeaderValue(hfRaw, %"")` — empty raw string | `ok`, empty `rawValue` |
| 52b | `hfAddresses` array with mixed-kind elements | `err` |
| 52c | `hfMessageIds` array with non-string element | `err` |

### 4.5. allowedForms + validateHeaderForm — `theaders.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 53 | `allowedForms("from")` | `{hfAddresses, hfGroupedAddresses, hfRaw}` |
| 54 | `allowedForms("subject")` | `{hfText, hfRaw}` |
| 55 | `allowedForms("date")` | `{hfDate, hfRaw}` |
| 56 | `allowedForms("message-id")` | `{hfMessageIds, hfRaw}` |
| 57 | `allowedForms("x-custom-header")` — unknown | `{hfRaw..hfUrls}` |
| 58 | `validateHeaderForm` with `from` + `hfAddresses` | `ok` |
| 59 | `validateHeaderForm` with `subject` + `hfAddresses` | `err`, message contains `"form hfAddresses not allowed for header subject"` |
| 60 | `allowedForms("resent-from")` | `{hfAddresses, hfGroupedAddresses, hfRaw}` |
| 60a | Table contains exactly 30 entries; every entry's set includes `hfRaw`; every key is lowercase | passes |
| 61 | `allowedForms("list-unsubscribe")` | `{hfUrls, hfRaw}` |
| 62 | `allowedForms("return-path")` | `{hfRaw}` |
| 68 | `validateHeaderForm` on unknown header + any form | `ok` |
| 69 | `validateHeaderForm` with `from` + `hfRaw` | `ok` (`hfRaw` always allowed) |
| 69a | `allowedForms("FROM")` — non-lowercase input misses table | `{hfRaw..hfUrls}` (documents lowercase precondition) |

### 4.6. BlueprintEmailHeaderName — `theaders_blueprint.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 28a | Case variants `"X-Custom"`, `"x-custom"`, `"X-CUSTOM"` all normalise to `"x-custom"`; pairwise `==` and `hash` agree | passes |
| 29 | `parseBlueprintEmailHeaderName("Content-Type")` | `err`, message `"name must not start with 'content-'"` |
| 29a | Forbidden-prefix table — `"Content-Disposition"`, `"CONTENT-TYPE"`, `"content-type"` | `err` for every casing |
| 30 | Colon rejected — `"header:X-Custom:asText"`, `"X:Custom"` | `err`, message `"name must not contain a colon"` |
| 31 | Character rejection table — empty, space, tab, `\x7F` (DEL), `\x00` (NUL), UTF-8 bytes | `err` |
| 32 | Prefix boundary — `"Content"` (no hyphen) ok; `"contents"` ok; `"content-"` (minimum forbidden) → `err` |
| 32a | Printable-ASCII byte sweep — exactly 93 accepted (printable minus `:`) and 163 rejected at each tested position | passes |
| 32c | Strict-only commitment — `parseBlueprintEmailHeaderNameFromServer` and `parseBlueprintBodyHeaderNameFromServer` | does not compile |

### 4.7. BlueprintBodyHeaderName — `theaders_blueprint.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 33 | Allowed names — `"Content-Type"`, `"Content-Disposition"`, `"Content-Language"`, `"X-Custom"` | `ok` |
| 35 | `Content-Transfer-Encoding` exact-name rejected in all casings | `err`, message `"name must not be 'content-transfer-encoding'"` |
| 35c | `"Content-Transfer-Encoding-X"` — not exact match | `ok` |
| 35d | UTF-8 homoglyph approximating `"Content-Type"` (e.g. `"\xC3\x83\xC2\xA7ontent-Type"`) | `err` (printable-ASCII check fires before exact-name check) |
| 36 | Character rejection — empty, space, tab, `"header:X-Custom:asText"` | `err` |
| 37b | Case equivalence and hash agreement for `"X-Custom"` vs `"x-custom"` | passes |

### 4.8. BlueprintHeaderMultiValue — `theaders_blueprint.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 37c | `rawMulti(@["v1"])` → `multiLen == 1`, `form == hfRaw` | passes |
| 37d | `rawMulti(@["v1", "v2"])` → `multiLen == 2` | passes |
| 37e | `rawMulti(@[])` | `err` (delegates to `parseNonEmptySeq`) |
| 37f | All per-form `*Multi` helpers (`textMulti`, `addressesMulti`, `groupedAddressesMulti`, `messageIdsMulti`, `dateMulti`, `urlsMulti`) | `ok` with the correct discriminant and length |
| 37g | `rawSingle("value")` returns `BlueprintHeaderMultiValue` directly (no `Result`) | passes |
| 37h | Direct case-object construction equality with helper construction (compare discriminator + active branch field — generic `==` does not compile for case objects) | passes |

### 4.9. PartId — `tbody.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 70 | `parsePartIdFromServer("1")` | `ok` |
| 71 | `parsePartIdFromServer("")` | `err`, message `"must not be empty"` |
| 72 | `parsePartIdFromServer("abc\x1Fdef")` — control char | `err`, message `"contains control characters"` |
| 73 | Round-trip via `$pid` and re-parse | identity |
| 73a | `==` and `hash` consistent for two constructions of the same string | passes |
| 74 | `parsePartIdFromServer` with 500-character string | `ok` (no length limit) |
| 75 | `parsePartIdFromServer` with multi-byte UTF-8 (`"\xC3\xA9\xC3\xA0\xC3\xBC"`) | `ok` |
| 76 | Typical formats — `"1"`, `"1.2"`, `"1.2.3"` | `ok` |

### 4.10. EmailBodyPart serde — `tserde_body.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 77 | `fromJson` leaf with `type`, `partId`, `blobId`, `size`, `charset` | `ok`, `isMultipart == false` |
| 78 | `fromJson` multipart with `subParts` | `ok`, `isMultipart == true` |
| 79 | Multipart with absent `subParts` — Postel's law | `ok`, `subParts == @[]` |
| 80 | Leaf absent `partId` | `err` |
| 81 | Leaf absent `blobId` | `err` |
| 82 | `text/plain` with `subParts` key — discriminant from `contentType` only | `ok`, `isMultipart == false` |
| 83 | `size` required on leaf — absent → `err` | passes |
| 84 | `size` absent on multipart → default `UnsignedInt(0)` | passes |
| 85 | `charset` absent on `text/plain` → `Opt.some("us-ascii")` | passes |
| 86 | `charset` present on `text/plain` → `Opt.some(value)` | passes |
| 87 | `charset` null on `text/html` → `Opt.some("us-ascii")` (Postel's law) | passes |
| 88 | `charset` absent on `image/png` → `Opt.none` | passes |
| 89 | `charset` absent on `multipart/...` → `Opt.none` | passes |
| 90 | `charset` present on `image/png` (`"binary"`) — preserved | `Opt.some("binary")` |
| 91 | `headers` absent → `@[]` | passes |
| 92 | `headers` present → parsed seq | passes |
| 93 | Depth limit: 128 multipart wrappers + 1 leaf = 129 parse calls → `err(svkDepthExceeded, maxDepth: 128)` | passes |
| 94 | Round-trip leaf with all optional fields populated | identity |
| 95 | Round-trip multipart with `subParts` | identity |
| 96 | `toJson` stress at depth 200 — produces a JObject without crashing | passes |
| 97 | Absent `type` | `err` |
| 97a | Non-object input — JArray, JNull, JString | `err` |
| 97b | `type` wrong-kind (JInt) | `err` |
| 98 | `"MULTIPART/MIXED"` — case-insensitive prefix match | `isMultipart == true` |
| 98a | `"TEXT/PLAIN"` charset default applies | `Opt.some("us-ascii")` |
| 99 | `"multipart/"` — slash only, leniently treated as multipart | `isMultipart == true` |
| 99a | `"text/"` — charset default applies | `Opt.some("us-ascii")` |
| 99b | `"textplain"` — no slash, falls through to leaf branch | `err` (missing leaf fields) |
| 99c | `"multipart"` — no trailing slash, falls through to leaf branch | `err` (missing leaf fields) |
| 99d | Empty `type` — leaf branch | `err` (missing leaf fields) |
| 100 | Leaf with `subParts` — extra key ignored | `isMultipart == false` |
| 101 | Multipart with `partId`/`blobId` — extra keys ignored | `isMultipart == true` |
| 102 | Null in `headers` array | `err` |
| 102a | Non-string in `language` array | `err` |
| 103 | Null in `subParts` array | `err` |
| 104 | Depth at exactly 128 | `ok` |
| 105 | Empty charset string preserved | `Opt.some("")` |
| 106 | Negative `size` | `err` |
| 107 | `size` exceeding `UnsignedInt` range | `err` |
| 108 | `toJson` at exact depth 128 — leaf fully serialised | passes |
| 108a | Compile-time: constructing multipart with `partId` field | does not compile |
| 108b | Compile-time: constructing leaf with `subParts` field | does not compile |
| 108c | Duplicate `"type"` key — `std/json` last-wins semantics | second value wins |

### 4.11. EmailBodyValue serde — `tserde_body.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 109 | All fields present | `ok` |
| 110 | `isEncodingProblem: true` | preserved |
| 111 | `isTruncated: true` | preserved |
| 112 | Both flags `true` | preserved |
| 113 | Flags absent → default `false` | passes |
| 114 | Round-trip | identity |
| 115 | Absent `value` | `err` |
| 115a | Non-object input — JArray, JNull | `err` |
| 116 | Null `value` | `err` |
| 117 | Wrong-kind `value` (JInt) | `err` |
| 118 | Wrong-kind flag (JString `"true"`) | `err(svkWrongKind)` |
| 118a | Empty `value` string | `ok` |
| 118b | Null bool flag → treated as absent → default `false` | passes |

### 4.12. BlueprintBodyPart serde — `tserde_body.nim`

| # | Scenario | Expected |
|---|----------|----------|
| 119 | Inline leaf — `partId` emitted; `blobId` / `charset` / `size` keys ABSENT (not null) | passes |
| 120 | Blob-ref leaf with `Opt.some` `size` and `charset` — both emitted | passes |
| 121 | Blob-ref both `Opt.some` | both emitted |
| 122 | Blob-ref both `Opt.none` | both keys absent |
| 123 | Multipart with one child | `subParts` JArray of length 1 |
| 124 | Stress at depth 200 — produces a JObject without crashing | passes |
| 125 | `BlueprintBodyPart.fromJson` — `assertNotCompiles` | does not compile (creation type, `toJson` only) |
| 125a | Compile-time: `blobId` on `bpsInline` leaf | does not compile |
| 125b | Compile-time: `charset` on `bpsInline` leaf | does not compile |
| 125c | Compile-time: `partId` on multipart blueprint | does not compile |
| 125d | Compile-time: `subParts` on non-multipart blueprint | does not compile |
| 126 | Inline-leaf key absence — `"blobId" notin node`, `"charset" notin`, `"size" notin` | passes |
| 127 | `extraHeaders` entry `"x-custom"` with `textSingle("custom value")` | key `"header:x-custom:asText"`, scalar JString value |
| 127a | `extraHeaders` entry with `rawSingle("raw value")` — `hfRaw` form suffix omitted | key `"header:x-custom"` |
| 128 | Empty `extraHeaders` — no `header:*` keys emitted | passes |
| 129 | Multipart with empty `subParts` | `subParts: []` |
| 130 | Nested multipart (multipart/mixed → multipart/alternative → leaf) | recursive structure preserved |
| 130a | Mixed children — inline leaf and blob-ref leaf as siblings of one multipart | both render correctly with their respective fields |
| 131 | Blob-ref with both `size` and `charset` `Opt.none` | `"charset" notin`, `"size" notin` |

### 4.13. ContentDisposition

`ContentDisposition` has no dedicated unit test file — its variants are
exercised through the `EmailBodyPart` round-trip suite. Scenario 94
(`roundTripLeaf` in `tserde_body.nim`) drives a leaf with
`"disposition": "inline"` end-to-end and asserts
`rt.disposition == Opt.some(dispositionInline)`. The
`parseOptDisposition` boundary surfaces malformed tokens through
`EmailBodyPart.fromJson` rejection (the `wrapInner` chain attaches the
JsonPath to the offending field). Case-object equality and hash
semantics are covered indirectly by `propRoundTripEmailBodyPart` in
`tprop_mail_c.nim` (random `disposition` fields including extension
identifiers are generated and round-tripped).

The omission of a dedicated unit-test file follows from C39 (single
parser, lossless round-trip) and C38 (sealed Pattern A — illegal state
unrepresentable means the only structural failure modes are empty input
and control characters, both already covered by `detectNonControlString`
in `validation.nim`).

### 4.14. Adversarial scenarios — `tserde_body.nim`

Adversarial edge cases probe the parsing boundaries that the type
system cannot rule out at compile time:

| # | Scenario | Expected |
|---|----------|----------|
| A1 | `parseHeaderPropertyName("header:From\x00Evil:asAddresses")` — embedded NUL byte | `ok` (NUL ≠ `:`); name retains the raw bytes (FFI-side `strlen` truncation risk noted) |
| A2 | `parseHeaderPropertyName("header:From\xC0\xBA:asAddresses")` — overlong UTF-8 colon | `ok` (byte-level split on literal `:` only) |
| A3 | `EmailBodyPart.fromJson` with `"type": "text/plain\x00multipart/mixed"` | `ok`, `isMultipart == false` (`startsWith` byte-level on full sequence) |
| A4 | `EmailBodyPart.fromJson` multipart with 10,000 leaf children | `ok` (no breadth limit; depth limit only) |
| A6 | `EmailBodyPart.fromJson` with `"size": 3.14` (JFloat) | `err(SerdeViolation, svkWrongKind)` from `UnsignedInt.fromJson` |

`Content-Transfer-Encoding` injection through body-part `extraHeaders`
needs no serde-level adversarial: `BlueprintBodyHeaderName`'s smart
constructor rejects every casing of `"content-transfer-encoding"`
(scenario 35 in `theaders_blueprint.nim`), so the offending entry
cannot exist in a well-typed `BlueprintBodyPart`. The structural
rejection at the type boundary subsumes any serde-level test.

### 4.15. Property-based test strategy — `tprop_mail_c.nim`

Uses the `mproperty.nim` infrastructure with fixed seed and edge-biased
generators. Three trial tiers: `DefaultTrials = 500`,
`ThoroughTrials = 2000`, `QuickTrials` (lower count for expensive
generators).

**Round-trip identity (DefaultTrials):**
- `propRoundTripEmailHeader` — `EmailHeader.fromJson(toJson(h)) == h`.
- `propRoundTripPartId` — `PartId.fromJson(toJson(pid)) == pid`.
- `propRoundTripEmailBodyValue` — value plus both flags preserved.
- `propRoundTripHeaderValue` — all 7 forms including `Opt.none` variants;
  per-form field-level comparison required (case-object generic `==`
  does not compile).
- `propRoundTripEmailBodyPart` — random recursive structures generated
  to depth 3, compared via `bodyPartEq` (custom recursive equality;
  generic case-object `==` does not compile).

**Totality (ThoroughTrials, except where noted):**
- `propParseHeaderPropertyNameTotality` — arbitrary strings.
- `propParseHeaderPropertyNameMaliciousTotality` — adversarial strings.
- `propParseHeaderPropertyNameArbitraryTotality` — header-shaped strings.
- `propParseHeaderValueTotality` — arbitrary `(HeaderForm, JsonNode)` pairs.
- `propEmailBodyPartFromJsonTotality` — arbitrary JSON nodes (depth 3).
- `propEmailBodyPartFromJsonDeepTotality` (`QuickTrials`) — deep
  arbitrary JSON objects (depth 5).
- `propEmailHeaderFromJsonTotality` — arbitrary JSON.
- `propEmailBodyValueFromJsonTotality` — arbitrary JSON.
- `propParsePartIdFromServerTotality` — arbitrary strings.

**Idempotence (DefaultTrials):**
- `propIdempotenceEmailBodyPart` — `toJson(fromJson(toJson(x))) == toJson(x)`.
- `propIdempotenceHeaderValue` — same shape per form.
- `propIdempotenceEmailHeader` — same shape.

**Invariant properties:**
- `propHeaderPropertyKeyNormalisesName` — `key.name == key.name.toLowerAscii()`.
- `propHeaderPropertyKeyRoundTripToPropertyString` — name, form, isAll
  all preserved through `toPropertyString` / `parseHeaderPropertyName`.
- `propAllowedFormsAlwaysIncludesRaw` — `hfRaw in allowedForms(name)`
  for every name in a 10-entry pool of known and unknown headers.
- `propValidateHeaderFormRespectsAllowedForms` — `validateHeaderForm`
  agrees with `allowedForms` membership.
- `propEmailBodyPartCharsetDefault` — every `text/*` leaf has
  `charset.isSome` after a `toJson` / `fromJson` round-trip (Postel's
  law default applied even if the original was generated without one).

---

## 5. Decision Traceability Matrix

| # | Decision | Chosen | Primary Principles |
|---|----------|--------|-------------------|
| C1 | `HeaderPropertyKey` sealing | Pattern A — sealed fields, smart constructor enforces non-empty lowercase name and valid form | Make illegal states unrepresentable, Parse-don't-validate |
| C2 | `HeaderPropertyKey` name casing | Lowercase canonical form; `==` and `hash` work uniformly | Parse-don't-validate, One source of truth |
| C3 | `HeaderPropertyKey` form-validation scope | Separate `validateHeaderForm` function — structural parsing and domain validation are different concerns | Parse once at the boundary, Postel's law, Total functions, DRY |
| C4 | `HeaderForm` enum style | String-backed; `parseHeaderForm` uses `nimIdentNormalize` for case-insensitive, underscore-tolerant matching | DRY, Code reads like the spec, One source of truth |
| C5 | `HeaderValue` parse-failure representation | `Opt.none` on the three nullable forms means "server could not parse" | Make illegal states unrepresentable, One source of truth |
| C6 | `hfDate` variant type | `Date` (any timezone), per RFC 8621 §4.1.2.6 | Code reads like the spec |
| C7 | `HeaderValue` construction | No domain-level constructors — the case object IS the constructor | DRY, Make illegal states unrepresentable |
| C8 | `EmailHeader` shape | Plain object with `ruleOff: "objects"`; smart constructor enforces non-empty name | Parse-don't-validate, Total functions |
| C9 | `EmailHeader` module placement | In `headers.nim` (same bounded context) | DDD |
| C10 | `allowedForms` exposure | Private const table + public total function | One source of truth, Total functions, Make the right thing easy |
| C11 | `parseHeaderValue` signature | Form only, not full `HeaderPropertyKey`. Caller handles `:all` dispatch | DDD |
| C12 | `HeaderValue` serde direction | Both `toJson` and `fromJson` (`parseHeaderValue`) | DDD, One source of truth |
| C13 | `PartId` parser naming | Single `parsePartIdFromServer` (no strict sibling) — read and creation use the same constraints | DRY, Postel's law |
| C14 | `EmailBodyPart` discriminant | Derived from `contentType` (`startsWith("multipart/")`, case-insensitive); `subParts` defaults to `@[]` if absent | One source of truth, Postel's law, Total functions |
| C15 | `EmailBodyPart.size` field | `UnsignedInt` on all parts; required on leaf, defaults to `0` on multipart | Postel's law, Code reads like the spec |
| C16 | Recursive depth limit | Public `MaxBodyPartDepth* = 128` (matches `Filter[C]` precedent) | DRY, Total functions, Make the right thing easy |
| C17 | `EmailBodyPart.contentType` field naming | `contentType` (RFC 2045 domain concept); serde maps to `"type"` wire key | DDD, Code reads like the spec |
| C18 | `EmailBodyPart.charset` default | Apply RFC §4.1.4 implicit `"us-ascii"` for `text/*` at the wire boundary; `Opt.none` means "not text/*" | Parse once at the boundary, Code reads like the spec, Postel's law |
| C19 | `EmailBodyPart.disposition` typing | `Opt[ContentDisposition]` — typed at the wire boundary, vendor extensions in `cdExtension` | Make illegal states unrepresentable, DDD |
| C20 | `EmailBodyPart.blobId` typing | `BlobId` (typed distinct), not `Id` | Newtype everything |
| C21 | `EmailBodyValue` construction | Plain object — all flag combinations valid for the read model | Constructors that can't fail don't, DDD |
| C22 | `BlueprintBodyValue` separation | Distinct type stripping `isEncodingProblem` and `isTruncated` | Make illegal states unrepresentable |
| C23 | `BlueprintBodyPart.extraHeaders` typing | `Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]` — name-only key, form on the value | Make illegal states unrepresentable, One source of truth |
| C24 | `BlueprintBodyPart` raw `headers` field | Absent — only `extraHeaders` (typed) | One source of truth, Parse once at the boundary |
| C25 | `BlueprintBodyPart` leaf shape | Hoisted into separate `BlueprintLeafPart` with its own discriminator | Make illegal states unrepresentable (for strictCaseObjects) |
| C26 | Inline-value placement | Co-located on `BlueprintLeafPart` (`bpsInline.value`); harvested into `bodyValues` at emission time | Make illegal states unrepresentable, One source of truth |
| C27 | `BlueprintPartSource` enum style | Plain enum, no string backing — no wire-format mapping exists | One source of truth |
| C28 | `BlueprintBodyPart` serde direction | `toJson` only — creation types are unidirectional | Parse once at the boundary, Constructors are privileges |
| C29 | `BlueprintBodyPart` depth bounding | Bounded by construction (`parseEmailBlueprint` rejects depth > `MaxBodyPartDepth`); serde recurses unboundedly | Total functions, DRY |
| C30 | `EmailBodyPart` `toJson` totality | Depth-limited recursive serialiser; truncates at depth exhaustion | Total functions |
| C31 | `EmailBodyPart.headers` field type | `seq[EmailHeader]` (always present, possibly empty) — same pattern as `emailQuerySortOptions` | One source of truth, Code reads like the spec |
| C32 | `EmailBodyPart.fromJson` decomposition | Six focused field-extraction helpers + a recursive driver | DDD, DRY |
| C33 | `BlueprintEmailHeaderName` vs `BlueprintBodyHeaderName` split | Two distinct types — different validation rules per context (top-level forbids `Content-*`; body-part forbids only `Content-Transfer-Encoding`) | Newtype everything, Make illegal states unrepresentable |
| C34 | `BlueprintHeaderMultiValue` shape | Form-discriminated case object with `NonEmptySeq[T]` per variant — name-only key + form-on-value rules out duplicate-name and empty-list states | Make illegal states unrepresentable, DRY |
| C35 | Multi-value constructor pair | Per-form `*Single` (infallible) + `*Multi` (fallible on empty seq) | Constructors that can't fail don't, DRY |
| C36 | `composeHeaderKey` placement | L2 serde, generic over both header-name newtypes — one wire-key rule, two contexts | DRY, Code reads like the spec |
| C37 | `BlueprintHeaderMultiValue` cardinality wire shape | Cardinality 1 → scalar wire shape, no `:all`; cardinality > 1 → JArray, `:all` appended | Code reads like the spec, Make illegal states unrepresentable |
| C38 | `ContentDisposition` shape | Sealed Pattern A case object; closed RFC vocabulary + `cdExtension` for §2.8 extensions | Make illegal states unrepresentable, Parse-don't-validate |
| C39 | `ContentDisposition` parser | Single `parseContentDisposition` (no strict/lenient pair) — same rationale as `parseMailboxRole` | DRY, Postel's law |
| C40 | `List-Id` in `allowedForms` table | Included with `{hfText, hfRaw}` per RFC 8621 §4.1.2.2's explicit enumeration | Code reads like the spec, One source of truth |
| C41 | `PartId` validation | Non-empty + reject control characters; no length limit (RFC §4.1.4 types `partId` as `String`, not `Id`) | One source of truth, Postel's law |
| C42 | `BlueprintEmailHeaderName` / `BlueprintBodyHeaderName` strict-only | Strict smart constructors with no `*FromServer` siblings — creation vocabulary is unidirectional | Parse once at the boundary, Make the right thing easy |
| C43 | `HeaderPropertyKey` `hash` and `$` | Public — required for `Email.requestedHeaders` / `requestedHeadersAll` `Table` keying | Make illegal states unrepresentable |
| C44 | Header-violation ADTs | Module-private `HeaderFormViolationKind` and `HeaderKeyViolation` ADTs; single `toValidationError` translator per type | DRY, Make illegal states unrepresentable |
