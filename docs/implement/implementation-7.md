# Mail Part C Implementation Plan

Layers 1–4 of RFC 8620 core are complete. Mail Part A added Thread, Identity,
and VacationResponse entities plus shared sub-types. Mail Part B added Keyword,
KeywordSet, Mailbox entity, and supporting types. This plan adds the header and
body sub-types required by the Email entity — pure vocabulary consumed by Part D
(Email entity, SearchSnippet) and beyond. No entity registration, no builder
functions, no filter conditions. All new mail code lives under
`src/jmap_client/mail/`. Full specification: `docs/design/08-mail-c-design.md`,
building on cross-cutting design `docs/design/05-mail-design.md`.

4 steps, one commit each, bottom-up through the dependency DAG. Every step
passes `just ci` before committing.

Cross-cutting requirements apply to all steps: all modules follow established
core patterns — SPDX header, `{.push raises: [].}`, `func` for pure
functions, `Result[T, ValidationError]` for smart constructors, `Opt[T]` for
optional fields, `checkJsonKind`/`optJsonField`/`parseError` for serde.
Design doc §4 (test specification, scenarios 1–131 plus A1–A6) and §5
(decision traceability matrix, C1–C42) provide per-scenario coverage targets.

---

## Step 1: Header sub-types — headers.nim + serde_headers.nim

**Create:** `src/jmap_client/mail/headers.nim`,
`src/jmap_client/mail/serde_headers.nim`,
`tests/unit/mail/theaders.nim`, `tests/serde/mail/tserde_headers.nim`

**Design doc:** §2 (Header Sub-Types), §2.7 (Serde), Decisions C1–C13,
C37–C40, C42.

`headers.nim` defines six types/functions:

`HeaderForm` as string-backed enum with 7 variants: `hfRaw = "asRaw"`,
`hfText = "asText"`, `hfAddresses = "asAddresses"`,
`hfGroupedAddresses = "asGroupedAddresses"`,
`hfMessageIds = "asMessageIds"`, `hfDate = "asDate"`,
`hfUrls = "asURLs"`. Enables `parseEnum` for form suffix parsing. A thin
wrapper function handles any `nimIdentNormalize` mismatch for `"asURLs"`
(Decision C4). The wrapper returns `Result[HeaderForm, ValidationError]`.

`EmailHeader` as plain object with `name: string` and `value: string`.
`parseEmailHeader` smart constructor validates non-empty `name`.
Post-construction `doAssert name.len > 0`. Same pattern as `EmailAddress`
in `addresses.nim` (Decision C8).

`HeaderPropertyKey` using Pattern A (sealed fields): `rawName: string`
(module-private, lowercase, non-empty), `rawForm: HeaderForm`
(module-private), `rawIsAll: bool` (module-private). Three UFCS accessors:
`name`, `form`, `isAll`. `parseHeaderPropertyName` smart constructor
accepts full wire string including `header:` prefix, validates structural
correctness (prefix present, name non-empty, form suffix valid if present,
`:all` in correct position), normalises name to lowercase, defaults to
`hfRaw` when no form suffix present. Post-construction `doAssert
rawName.len > 0`. Does **not** validate form-name compatibility (that is
`validateHeaderForm`) nor printable-ASCII name characters (that is Part D)
(Decisions C1, C2, C3, C38, C42). `toPropertyString` reconstructs the wire
string from sealed fields: `"header:" & rawName & $rawForm & ":all"`,
omitting the form suffix when `hfRaw` (Decision C39).

`HeaderValue` as case object discriminated by `form: HeaderForm`. Seven
variants: `hfRaw` → `rawValue: string`, `hfText` → `textValue: string`,
`hfAddresses` → `addresses: seq[EmailAddress]`, `hfGroupedAddresses` →
`groups: seq[EmailAddressGroup]`, `hfMessageIds` →
`messageIds: Opt[seq[string]]`, `hfDate` → `date: Opt[Date]`, `hfUrls` →
`urls: Opt[seq[string]]`. No domain-level constructors — the case object IS
the constructor (Decisions C5, C6, C7). `Opt.none` represents server parse
failure for `hfMessageIds`, `hfDate`, `hfUrls`.

`allowedHeaderFormsTable` as private `const Table[string, set[HeaderForm]]`
with 27 entries covering all RFC 5322, RFC 2369, and RFC 2919 headers named
in §4.1.2. Public `allowedForms` function returns the set for a given
lowercase header name; unknown headers return all forms (Decision C10, C40).

`validateHeaderForm` function checks `key.form in allowedForms(key.name)`.
Returns `ok(key)` or `err(ValidationError)` (Decision C3).

`serde_headers.nim` defines:

`EmailHeader.toJson` emits `name` and `value` as strings. `EmailHeader.fromJson`
validates JObject, extracts required `name` (string, rejects absent/null/
non-string) and `value` (string, required), delegates to `parseEmailHeader`
(Decision C13).

`parseHeaderValue(form: HeaderForm, node: JsonNode): Result[HeaderValue,
ValidationError]`. Dispatches on form to parse JSON into the correct
variant. `hfRaw`/`hfText` validate JString. `hfAddresses`/
`hfGroupedAddresses` validate JArray, parse elements via
`EmailAddress.fromJson`/`EmailAddressGroup.fromJson` with `?`
short-circuit. `hfMessageIds`/`hfUrls` accept JNull (→ `Opt.none`) or
JArray of JString (→ `Opt.some(seq)`). `hfDate` accepts JNull (→
`Opt.none`) or JString parsed via `Date.fromJson` (→ `Opt.some(Date)`)
(Decision C12).

`HeaderValue.toJson` dispatches on `v.form`. `Opt.none` variants emit
`newJNull()`. Sequences emit JArray. Same dispatch structure as
`parseHeaderValue` in reverse.

Tests cover scenarios 1–69a:

`tests/unit/mail/theaders.nim` (scenarios 1–7, 4a–4b, 5–7, 10–11, 12–29,
29a–29e, 53–62, 60a, 68–69, 69a): `HeaderForm` parsing for all 7 suffixes
(1), `nimIdentNormalize` verification for `"asURLs"` (2), unknown suffix
rejection (3), `$` operator for all variants (4), empty string (4a),
underscore in suffix (4b). `parseEmailHeader` valid (5), empty name
rejection (6), empty value accepted (7), control chars in name accepted
(10), whitespace-only name accepted (11). `parseHeaderPropertyName`
standard cases (12–16), missing prefix (17), empty name (18), unknown form
(19), lowercase normalisation (20, 28), explicit `hfRaw` (25–26), colon in
name (27), case variants (29), empty string (29a), trailing colon (29b),
uppercase `:all` (29c), underscore in form (29d), equality after
normalisation (29e). `toPropertyString` cases (21–24). `allowedForms` for
known headers (53–57, 60–62, 60a), `validateHeaderForm` valid (58, 68–69),
invalid (59), non-lowercase input (69a).

`tests/serde/mail/tserde_headers.nim` (scenarios 8–9, 11a–11f, 30–52,
52a–52c): `EmailHeader` toJson (8), round-trip (9), fromJson edge cases
(11a–11f). `parseHeaderValue` for all 7 forms (30–39), wrong JSON kind
(40–41, 51), toJson per form (42), round-trips including `Opt.none` (43),
`hfDate` none (44), empty arrays (45–48), malformed elements (49–50),
null for non-nullable (52), empty raw string (52a), mixed-kind arrays
(52b–52c).

---

## Step 2: Body sub-types — body.nim + serde_body.nim

**Create:** `src/jmap_client/mail/body.nim`,
`src/jmap_client/mail/serde_body.nim`,
`tests/unit/mail/tbody.nim`, `tests/serde/mail/tserde_body.nim`

**Design doc:** §3 (Body Sub-Types), §3.6 (Serde), Decisions C14–C32,
C41.

`body.nim` defines five types:

`PartId` as `distinct string` with `defineStringDistinctOps(PartId)`.
`parsePartIdFromServer` validates non-empty and rejects control characters
(< 0x20). No length limit — RFC 8621 types `partId` as `String`, not `Id`.
Post-construction `doAssert len > 0`. Single parser per B15 convention
(Decision C14, C41).

`EmailBodyPart` as case object discriminated by `isMultipart: bool`. Shared
fields: `headers: seq[EmailHeader]` (default `@[]`), `name: Opt[string]`,
`contentType: string`, `charset: Opt[string]`, `disposition: Opt[string]`,
`cid: Opt[string]`, `language: Opt[seq[string]]`, `location: Opt[string]`,
`size: UnsignedInt`. Multipart branch: `subParts: seq[EmailBodyPart]`.
Leaf branch: `partId: PartId`, `blobId: Id`. `isMultipart` is derived from
`contentType` at the parsing boundary (`startsWith("multipart/")`). Field
named `contentType` (domain concept), serde maps to/from `"type"` wire key
(Decisions C15–C20, C27).

`EmailBodyValue` as plain object with `value: string`,
`isEncodingProblem: bool` (default `false`), `isTruncated: bool` (default
`false`). No smart constructor — all combinations valid for read model
(Decision C21).

`BlueprintPartSource` as plain enum (no string backing): `bpsInline`,
`bpsBlobRef` (Decision C30).

`BlueprintBodyPart` as nested case object. Shared fields:
`contentType: string`, `name: Opt[string]`, `disposition: Opt[string]`,
`cid: Opt[string]`, `language: Opt[seq[string]]`, `location: Opt[string]`,
`extraHeaders: Table[HeaderPropertyKey, HeaderValue]`. Outer discriminant
`isMultipart: bool` — multipart branch: `subParts: seq[BlueprintBodyPart]`.
Leaf branch has inner discriminant `source: BlueprintPartSource` — inline:
`partId: PartId`; blob-ref: `blobId: Id`, `size: Opt[UnsignedInt]`,
`charset: Opt[string]`. No smart constructor — structural invariants
encoded by nested case object; cross-field constraints deferred to Part D's
`EmailBlueprint` (Decisions C22–C26, C31).

`serde_body.nim` defines:

`PartId` serde via `defineDistinctStringToJson(PartId)` and
`defineDistinctStringFromJson(PartId, parsePartIdFromServer)`.

`EmailBodyPart.fromJson`: recursive parsing with private depth limit
`const MaxBodyPartDepth = 128` following the `Filter[C]` pattern from
`serde_framework.nim`. Private `fromJsonImpl(node, depth)` validates
JObject, extracts `"type"` key → `contentType`, derives `isMultipart` from
`contentType` (case-insensitive `startsWith("multipart/")`). Extracts
shared fields: `headers` (absent → `@[]`), optional strings, `charset`
(applies `"us-ascii"` default for `text/*` when absent/null), `language`
(`Opt[seq[string]]`), `size` (required on leaf, default `UnsignedInt(0)` on
multipart). Multipart: checks depth, parses `subParts` recursively (absent
→ `@[]`), ignores `partId`/`blobId`. Leaf: extracts required `partId` and
`blobId`, ignores `subParts`. Public `fromJson` entry point calls
`fromJsonImpl(node, MaxBodyPartDepth)` (Decisions C15–C20, C17–C18).

`EmailBodyPart.toJson`: recursive serialisation with depth limit. Emits
`"type"` from `contentType`. Emits all shared fields (`Opt.none` → `null`).
Multipart: emits `"subParts"`. Leaf: emits `"partId"` and `"blobId"`
(Decision C29).

`EmailBodyValue.fromJson`: validates JObject, extracts required `value`
(string), `isEncodingProblem` (bool, default `false`),
`isTruncated` (bool, default `false`). `EmailBodyValue.toJson`: emits all
three fields explicitly.

`BlueprintBodyPart.toJson` only — no `fromJson` (creation type,
unidirectional flow per Decision C31). Recursive with depth limit. Emits
`"type"` from `contentType`. `Opt.none` shared fields are **omitted** (not
null). `extraHeaders` entries emitted as individual properties via
`toPropertyString` for keys and `HeaderValue.toJson` for values. Multipart:
emits `"subParts"`. Inline leaf: emits `"partId"` only — `blobId`,
`charset`, `size` absent by case-object structure. Blob-ref leaf: emits
`"blobId"`, optional `charset`/`size` (Decisions C24, C28, C31).

Tests cover scenarios 70–131, A1–A6:

`tests/unit/mail/tbody.nim` (scenarios 70–76, 73a, 108a–108b, 125a–125d):
`parsePartIdFromServer` valid (70), empty rejection (71), control char
rejection (72), round-trip (73), equality/hash (73a), long value (74),
UTF-8 (75), typical formats (76). Compile-time: `partId` on multipart
(108a), `subParts` on leaf (108b), `blobId`/`charset` on inline (125a–b),
`partId` on multipart blueprint (125c), `subParts` on leaf blueprint
(125d).

`tests/serde/mail/tserde_body.nim` (scenarios 77–108, 97a–99d, 102a,
108c, 109–131, 115a, 118a–118b, 125–131, 127a, 130a–130b, A1–A6):
`EmailBodyPart.fromJson` leaf (77), multipart (78), absent subParts (79),
absent partId (80), absent blobId (81), isMultipart from contentType (82),
size required on leaf (83), size default on multipart (84), charset
defaults (85–90), headers absent/present (91–92), depth limit (93, 104),
round-trips (94–95), toJson depth (96, 108), absent contentType (97),
uppercase contentType (98), edge cases (99–103, 97a–99d, 102a, 105–107,
108c). `EmailBodyValue` all fields (109), flags true (110–112), flags
default (113), round-trip (114), absent value (115), null value (116),
wrong kinds (117–118), edge cases (115a, 118a–118b). `BlueprintBodyPart`
toJson inline (119), blob-ref (120–122), multipart (123), depth limit
(124), no fromJson (125), key absence (126), extraHeaders (127–128, 127a),
nested multipart (129–130, 130a–130b), absent optionals (131). Adversarial:
NUL in header name (A1), overlong UTF-8 colon (A2), NUL in contentType
(A3), 10k children breadth (A4), Content-Transfer-Encoding in extraHeaders
(A5), float size (A6).

---

## Step 3: Re-export hub updates

**Update:** `src/jmap_client/mail/types.nim`,
`src/jmap_client/mail/serialisation.nim`

**Design doc:** §1.4 (Module Summary), cross-cutting doc §3.3 (module
layout).

Update `mail/types.nim` to import and re-export Part C Layer 1 modules:
`headers`, `body`.

Update `mail/serialisation.nim` to import and re-export Part C Layer 2
modules: `serde_headers`, `serde_body`.

No changes to `mail.nim` or `src/jmap_client.nim` — Part C adds no entity
registrations or builder functions, and the existing re-export chain
(`jmap_client.nim` → `mail.nim` → `mail/types.nim` + `mail/serialisation.nim`)
transitively covers the new modules.

Verify all Part C public symbols are accessible through
`import jmap_client`: `HeaderForm`, `hfRaw` through `hfUrls`,
`EmailHeader`, `parseEmailHeader`, `HeaderPropertyKey`,
`parseHeaderPropertyName`, `toPropertyString`, `name`/`form`/`isAll`
accessors, `HeaderValue`, `allowedForms`, `validateHeaderForm`, `PartId`,
`parsePartIdFromServer`, `EmailBodyPart`, `EmailBodyValue`,
`BlueprintPartSource`, `bpsInline`/`bpsBlobRef`, `BlueprintBodyPart`.
Run `just ci`.

---

## Step 4: Property-based tests — generators + tprop_mail_c.nim

**Update:** `tests/mproperty.nim`
**Create:** `tests/property/tprop_mail_c.nim`

**Design doc:** §4.11 (Property-based test strategy).

Add Part C generators to `tests/mproperty.nim` following existing
conventions (edge-biased early trials, fixed seed, doc comments listing
covered/not-covered cases): `genHeaderForm`, `genEmailHeader`,
`genHeaderPropertyKey`, `genHeaderValue` (all 7 forms including
`Opt.none` variants), `genPartId`, `genEmailBodyPart` (recursive,
mixed multipart and leaf, depth-bounded), `genEmailBodyValue`,
`genArbitraryHeaderPropertyString` (for totality testing).

`tests/property/tprop_mail_c.nim` covers the §4.11 properties:

Round-trip identity (DefaultTrials = 500): `EmailBodyPart`
(`fromJson(toJson(part)) == part`), `HeaderValue`
(`parseHeaderValue(form, toJson(value)) == value`), `EmailHeader`,
`PartId`.

Totality (ThoroughTrials = 2000): `EmailBodyPart.fromJson` never
crashes on arbitrary `JsonNode` input (malformed objects, wrong kinds,
deeply nested structures — `discard`, must not panic).
`parseHeaderPropertyName` never crashes on arbitrary strings (empty,
very long, binary, embedded NULs). `parseHeaderValue` never crashes on
arbitrary `(HeaderForm, JsonNode)` pairs.

Run `just ci`.
