# Mail Part D Implementation Plan

Layers 1-4 of RFC 8620 core are complete. Mail Parts A-C added Thread,
Identity, VacationResponse, Keyword, Mailbox, and all header/body sub-types.
This plan adds the Email read path: Email and ParsedEmail entities,
EmailComparator, EmailBodyFetchOptions, EmailFilterCondition, SearchSnippet,
plus all serde, builder functions, and custom methods. All new mail code lives
under `src/jmap_client/mail/`. Full specification:
`docs/design/09-mail-d-design.md`, building on cross-cutting design
`docs/design/05-mail-design.md`.

5 phases, one commit each, bottom-up through the dependency DAG. Every phase
passes `just ci` before committing.

Cross-cutting requirements apply to all steps: all modules follow established
core patterns — SPDX header, `{.push raises: [].}`, `func` for pure
functions, `Result[T, ValidationError]` for smart constructors, `Opt[T]` for
optional fields, `checkJsonKind`/`optJsonField`/`parseError` for serde.
Design doc §12 (test specification, 136 scenarios across §12.1–12.14) and
§13 (decision traceability matrix, D1–D20) provide per-scenario coverage
targets. §12.14 specifies test file organisation, fixture factories, equality
helpers, and generators.

---

## Phase 1: L1 Types — email.nim + snippet.nim + mail_filters.nim additions

**Design doc:** §2–6 (type definitions), §7 (SearchSnippet), §12.1
(scenarios 1–2), §12.14 (fixture factories), Decisions D1–D3, D6–D9,
D12, D16, D20.

Three independent L1 modules. None depend on each other; all depend only
on pre-existing Parts A–C types.

### Step 1: email.nim

**Create:** `src/jmap_client/mail/email.nim`

Defines seven types in one module (domain cohesion, D14):

`PlainSortProperty` as string-backed enum with 6 variants (`pspReceivedAt`,
`pspSize`, `pspFrom`, `pspTo`, `pspSubject`, `pspSentAt`).

`KeywordSortProperty` as string-backed enum with 3 variants
(`kspHasKeyword`, `kspAllInThreadHaveKeyword`,
`kspSomeInThreadHaveKeyword`).

`EmailComparatorKind` as plain enum (`eckPlain`, `eckKeyword`).

`EmailComparator` as case object discriminated by `kind:
EmailComparatorKind`. Shared fields `isAscending: Opt[bool]` and
`collation: Opt[string]` before the case. `eckPlain` branch:
`property: PlainSortProperty`. `eckKeyword` branch:
`keywordProperty: KeywordSortProperty`, `keyword: Keyword`. Two total
constructors `plainComparator` and `keywordComparator` — both infallible,
no `Result` (D8). Trivial constructor tests removed per §12.5 rationale;
serde tests exercise constructors implicitly.

`BodyValueScope` as plain enum with 5 variants (`bvsNone`, `bvsText`,
`bvsHtml`, `bvsTextAndHtml`, `bvsAll`). Replaces three RFC booleans (D9).

`EmailBodyFetchOptions` as plain object with `bodyProperties:
Opt[seq[PropertyName]]`, `fetchBodyValues: BodyValueScope`,
`maxBodyValueBytes: Opt[UnsignedInt]`. No smart constructor —
`default(EmailBodyFetchOptions)` produces correct RFC defaults.

`Email` as plain object with 28 fields across metadata (7), convenience
headers (11), raw headers (1), dynamic header tables (2), and body (7).
A typed `Email` is a complete domain object — every property present,
body fields use non-Opt types with natural "empty" values (empty Table,
empty seq, `false`, `""`) (D2). `fromAddr` for the `from` property (Nim
keyword, architecture Decision 12.4). `parseEmail` smart constructor
validates only non-empty `mailboxIds` (D1, D15). Plain public fields —
28 fields too costly for Pattern A.

`ParsedEmail` as plain object with 22 fields — structurally distinct from
Email (6 metadata fields absent, `threadId: Opt[Id]` instead of `Id`).
Full field duplication — no shared sub-objects (D7, D20). No smart
constructor beyond `fromJson`.

Convenience predicate `isLeaf(part: EmailBodyPart): bool` for leaf-only
body list assertions (D6).

### Step 2: snippet.nim

**Create:** `src/jmap_client/mail/snippet.nim`

`SearchSnippet` as plain object with `emailId: Id`, `subject: Opt[string]`,
`preview: Opt[string]`. No smart constructor — pure data carrier.
`SearchSnippet.toJson` is defined in `serde_snippet.nim` (Phase 2), not here.

### Step 3: mail_filters.nim additions

**Update:** `src/jmap_client/mail/mail_filters.nim`

`EmailHeaderFilter` with Pattern A sealed `name` field (non-empty
invariant) and public `value: Opt[string]`. `name` accessor function.
`parseEmailHeaderFilter` smart constructor validates non-empty name.

`EmailFilterCondition` as plain object with 20 fields across mailbox
membership (2), date/size (4), thread keywords (3), per-email keywords
(2), boolean (1), text search (7), and header filter (1). `fromAddr`
for the `from` property. No smart constructor — all field combinations
valid (B16). Keyword fields use typed `Keyword`, not `string`.

### Step 4: Fixture factories (§12.14)

**Update:** `tests/mfixtures.nim`

Add to `tests/mfixtures.nim` — type-level factories for use across all
Part D test files:

`makeEmail()` → minimal valid `Email` (non-empty `mailboxIds`, empty
keywords, default body). Satisfies `parseEmail`. `makeParsedEmail()` →
minimal `ParsedEmail` (`threadId = Opt.none`).
`makeEmailComparator()` → plain comparator for builder tests.
`makeKeywordComparator()` → keyword comparator for builder tests.
`makeEmailBodyFetchOptions()` → default body fetch options.
`makeEmailFilterCondition()` → all-none filter for toJson baseline.
`makeSearchSnippet()` → minimal valid `SearchSnippet`.

### Step 5: Tests

**Create:** `tests/unit/mail/temail.nim`

`tests/unit/mail/temail.nim` (§12.1, scenarios 1–2, plus isLeaf):
`parseEmail` non-empty mailboxIds (1), empty mailboxIds rejection with
`typeName = "Email"` (2). `isLeaf` returns true for a leaf
`EmailBodyPart` and false for a multipart part.

### CI gate

Run `just ci` before committing.

---

## Phase 2: L2 Serde — serde_email.nim + serde_snippet.nim + serde_mail_filters.nim additions

**Design doc:** §8.1–8.11 (all serde), §12.2–12.9 (scenarios 3–74,
excluding response-type scenarios 66–74 deferred to Phase 3), §12.14
(equality helpers, JSON fixtures), Decisions D4, D5, D7, D8, D9, D13,
D15, D19.

### Step 6: serde_email.nim

**Create:** `src/jmap_client/mail/serde_email.nim`

The most complex deserialiser in the library. Three internal shared helper
types and procs (D7) for code shared between `emailFromJson` and
`parsedEmailFromJson`:

`ConvenienceHeaders` internal helper object (11 fields, not exported).
`parseConvenienceHeaders(node)` extracts all 11 convenience header fields.
Maps JSON `"from"` key to `fromAddr` field.

`BodyFields` internal helper object (7 fields, not exported).
`parseBodyFields(node)` extracts all 7 body fields. `bodyValues` keys
parsed via `parsePartIdFromServer` for typed `Table[PartId,
EmailBodyValue]` (D19).

`parseRawHeaders(node)` extracts `headers: seq[EmailHeader]`. Absent key
yields empty seq.

`emailFromJson` uses two-phase strategy (D4): Phase 1 does structured
extraction via direct key lookups for all standard properties. `keywords`
defaults to empty `KeywordSet` if absent. Phase 2 iterates all keys,
routing `"header:"` prefixed keys to `requestedHeaders` or
`requestedHeadersAll` based on `isAll` suffix. Unknown non-header keys
silently ignored. `emailFromJson` does NOT call `parseEmail` — it
constructs `Email` directly via `ok(Email(...))` (D15: lenient at the
server→client boundary; trust the server's RFC contract).

`parsedEmailFromJson` same two-phase strategy. Phase 1 extracts only
`threadId` as `Opt[Id]`. Convenience header and body phases delegate to
the same shared helpers.

`Email.toJson` emits all domain fields always (D5): `Opt.none` → null,
empty seq → `[]`, empty Table → `{}`. Dynamic headers emitted as N
top-level keys. `fromAddr` emits as `"from"` key.

`ParsedEmail.toJson` same pattern but omits the 6 absent metadata fields.

`emailComparatorFromJson` synthesises discriminant by inspecting the
`property` name (D8). Tries `KeywordSortProperty` values first (require
`keyword` field), then `PlainSortProperty`.

`EmailComparator.toJson` dispatches on `kind`. Both branches emit
`property` as string. `eckKeyword` additionally emits `keyword`.
`isAscending` and `collation` omitted when `Opt.none`.

`EmailBodyFetchOptions.toJson` maps `BodyValueScope` enum back to the
three RFC booleans (D9). `bvsNone` omits all fetch keys.

### Step 7: serde_snippet.nim

**Create:** `src/jmap_client/mail/serde_snippet.nim`

`searchSnippetFromJson` extracts `emailId` (required), `subject` and
`preview` (both `Opt`, null yields `Opt.none`).

`SearchSnippet.toJson` emits all three fields: `emailId` via `Id.toJson`,
`subject` and `preview` via `Opt` → null when none.

### Step 8: serde_mail_filters.nim additions

**Update:** `src/jmap_client/mail/serde_mail_filters.nim`

`EmailFilterCondition.toJson` only — no fromJson (B11). Same pattern as
existing `MailboxFilterCondition.toJson`. `fromAddr` emits as `"from"`
key. `header` field emits as 1-or-2 element JArray. Keyword fields emit
via `$` (Keyword → string). `Opt.none` fields omitted.

### Step 9: Shared serde helpers

Two new helpers needed (not currently in codebase):

`collapseNullToEmptySeq` — parses `Id[]|null` fields where null/absent
collapses to empty seq. Used by `SearchSnippetGetResponse` and
`EmailParseResponse` in Phase 3. Place in `serde.nim` (shared core) or
locally in mail serde — decide based on whether core RFC 8620 types
need it.

`parseIdKeyedTable` — parses JSON object into `Table[Id, T]` with typed
value parser callback. Used by `EmailParseResponse.fromJson` in Phase 3.
Same placement decision as above.

### Step 10: Equality helpers and JSON fixtures (§12.14)

**Update:** `tests/mfixtures.nim`

Equality helpers: `emailEq(a, b: Email): bool` (field-by-field, handles
Table/seq/case-object HeaderValue, follows `sessionEq` pattern),
`parsedEmailEq(a, b: ParsedEmail): bool` (delegates to common field
comparisons), `emailComparatorEq(a, b: EmailComparator): bool`
(case-object equality, follows `setErrorEq` pattern).

JSON fixtures derived from type factories via `toJson()` (not
hand-crafted): `makeEmailJson()`, `makeParsedEmailJson()`,
`makeSearchSnippetJson()`. Hand-crafted JSON reserved for adversarial
tests in Phase 3.

### Step 11: serde_email tests

**Create:** `tests/serde/mail/tserde_email.nim`

`tests/serde/mail/tserde_email.nim` (§12.2–12.5, scenarios 3–45):

Email fromJson (3–17): non-JObject rejection (3), complete valid golden
path (4), absent keywords default (5), convenience headers null+present
combined (6), `"from"` → `fromAddr` (7), dynamic `header:Subject:asText`
routing (8), dynamic `header:From:asAddresses:all` routing (9), both
`:all` and non-`:all` simultaneously (10), unknown non-header key ignored
(11), bodyValues typed PartId keys (12), missing required metadata field
per-field (13), convenience header wrong type (14), malformed dynamic
header key (15), mailboxIds as JNull (16), keywords wrong type (17).

Email toJson (18–23): Opt.none → null (18), fromAddr → `"from"` (19),
requestedHeaders top-level keys (20), requestedHeadersAll with `:all`
suffix (21), empty tables → no extra keys (22), empty seq → `[]` and
empty Table → `{}` (23).

ParsedEmail (24–33): threadId null (24), threadId present (25), absent
metadata not error (26), `"from"` → fromAddr (27), dynamic headers
routed (28), threadId wrong type (29), unexpected metadata silently
ignored (30), toJson omits absent metadata but emits threadId (31),
toJson fromAddr → `"from"` (32), round-trip identity (33).

EmailComparator (34–45): toJson plain (34), keyword (35), omits optional
fields when none (36), all four keys present (37), fromJson plain (38),
fromJson all three keyword variants individually (39–41), keyword
property without keyword field (42), unknown property (43), isAscending
round-trip (44), collation round-trip (45).

### Step 12: serde_snippet tests

**Create:** `tests/serde/mail/tserde_snippet.nim`

`tests/serde/mail/tserde_snippet.nim` (§12.9, scenarios 64–65 only):
`searchSnippetFromJson` valid (64), null subject/preview (65).
Response-type scenarios (66–74) deferred to Phase 3 when response types
exist.

### Step 13: serde_mail_filters tests

**Update:** `tests/serde/mail/tserde_mail_filters.nim`

Update `tests/serde/mail/tserde_mail_filters.nim` (§12.6–12.8,
scenarios 46–63): EmailBodyFetchOptions.toJson defaults to `{}` (46),
bvsText (47), bvsHtml (48), bvsTextAndHtml (49), bvsAll (50),
maxBodyValueBytes (51), bodyProperties emitted (52).
parseEmailHeaderFilter valid (53), empty rejection (54).
EmailFilterCondition.toJson all none `{}` (55), inMailbox (56),
hasKeyword (57), all 5 keyword fields (58), fromAddr → `"from"` (59),
header both forms (60), mixed filter (61), inMailboxOtherThan empty seq
(62), all 20 fields populated (63).

### CI gate

Run `just ci` before committing.

---

## Phase 3: L3 — Entity registration + builders + custom methods + adversarial/integration tests

**Design doc:** §9–10 (builders and custom methods), §12.9 (response-type
scenarios 66–74), §12.10 (scenarios 75–90), §12.11 (adversarial scenarios
91–123), §12.13 (integration scenarios 132–136), §12.14 (response JSON
fixtures), Decisions D10–D13, D17, D18.

### Step 14: mail_entities.nim additions

**Update:** `src/jmap_client/mail/mail_entities.nim`

Register Email: `methodNamespace` returns `"Email"`, `capabilityUri`
returns `"urn:ietf:params:jmap:mail"`. `registerJmapEntity(Email)`.
`registerQueryableEntity(Email)` with `filterType` yielding
`EmailFilterCondition` and `filterConditionToJson` dispatching to
`EmailFilterCondition.toJson`.

### Step 15: builder.nim refactoring (D10)

**Update:** `src/jmap_client/builder.nim`

Extract an internal (non-exported) helper proc from the existing
`addQuery` body that builds the common query arguments JSON (accountId,
filter serialisation, QueryParams unpacking). Both the generic
`addQuery[T, C]` and the new `addEmailQuery` delegate to this helper.
Same extraction for `addQueryChanges` / `addEmailQueryChanges`. This
avoids duplicating filter/sort/window serialisation logic.

Alternative (if extraction proves disruptive): follow the Mailbox
precedent — construct a `QueryRequest` with `sort: Opt.none`, call
`toJson`, then patch in `EmailComparator` sort and `collapseThreads`
on the resulting `JsonNode`. This is already established by
`addMailboxQuery`.

### Step 16: mail_builders.nim additions

**Update:** `src/jmap_client/mail/mail_builders.nim`

`addEmailGet` (`func`): adds mail capability, `"Email/get"` invocation.
Standard `ids`, `properties` parameters plus `bodyFetchOptions:
EmailBodyFetchOptions = default(EmailBodyFetchOptions)`. Body fetch
options serialised via `toJson` and merged into invocation arguments.
Default omits all body-fetch keys. Returns
`ResponseHandle[GetResponse[Email]]`.

Email/changes uses generic `addChanges[Email]` directly (D17). No custom
wrapper.

`addEmailQuery` (`proc` — callback parameter): adds mail capability,
`"Email/query"` invocation. Accepts `seq[EmailComparator]` for sort
(not `seq[Comparator]`), `Filter[EmailFilterCondition]`,
`QueryParams`, `collapseThreads: bool = false`. Delegates to extracted
internal helper. Returns `ResponseHandle[QueryResponse[Email]]`.

`addEmailQueryChanges` (`proc`): adds mail capability,
`"Email/queryChanges"` invocation. Parallel to `addEmailQuery` with
`sinceQueryState`, `maxChanges`, `upToId`, `calculateTotal`,
`collapseThreads`. Same sort type. Returns
`ResponseHandle[QueryChangesResponse[Email]]`.

### Step 17: mail_methods.nim additions

**Update:** `src/jmap_client/mail/mail_methods.nim`

`EmailParseResponse` type: `accountId: AccountId`, `parsed: Table[Id,
ParsedEmail]`, `notParseable: seq[Id]`, `notFound: seq[Id]`.
`emailParseResponseFromJson` uses `parseIdKeyedTable` for `parsed`,
`collapseNullToEmptySeq` for `notParseable` and `notFound`. Note:
RFC key is `"notParsable"` (one 'e'); Nim field is `notParseable`.

`SearchSnippetGetResponse` type: `accountId: AccountId`,
`list: seq[SearchSnippet]`, `notFound: seq[Id]`.
`searchSnippetGetResponseFromJson` uses `collapseNullToEmptySeq` for
`notFound`.

`addEmailParse` (`func`): adds mail capability, `"Email/parse"`
invocation. `blobIds: seq[Id]` (not Referencable), optional
`properties`, `bodyFetchOptions`. Returns
`ResponseHandle[EmailParseResponse]`.

`addSearchSnippetGet` (`proc` — `filterConditionToJson` callback
parameter): adds mail capability, `"SearchSnippet/get"` invocation.
`filterConditionToJson: proc(c: EmailFilterCondition): JsonNode`
callback, same pattern as `addEmailQuery`. `filter` is required
(not Opt). `emailIds` non-emptiness enforced via cons-cell pattern:
`firstEmailId: Id, restEmailIds: seq[Id] = @[]` (D12). Builder
concatenates internally. Returns
`ResponseHandle[SearchSnippetGetResponse]`.

### Step 18: Response JSON fixtures (§12.14)

**Update:** `tests/mfixtures.nim`

Add to `tests/mfixtures.nim`: `makeSearchSnippetGetResponseJson()` and
`makeEmailParseResponseJson()`. These are hand-crafted JSON (not derived
via `toJson()`) because response types are server-only with no `toJson`.
They require the response types defined in `mail_methods.nim` above for
structural reference.

### Step 19: Entity registration tests

**Update:** `tests/protocol/tmail_entities.nim`

Update `tests/protocol/tmail_entities.nim`: Email registration compiles,
`addChanges[Email]` produces `"Email/changes"` (scenario 77).

### Step 20: Builder tests

**Update:** `tests/protocol/tmail_builders.nim`

Update `tests/protocol/tmail_builders.nim` (§12.10, scenarios 75–83):
`addEmailGet` name + capability + default body options (75), non-default
body options in args (76). `addEmailQuery` name (78), collapseThreads
true (79), collapseThreads false default behaviour (80), EmailComparator
sort (81). `addEmailQueryChanges` name (82), collapseThreads + sort
parameters (83).

### Step 21: Method tests

**Update:** `tests/protocol/tmail_methods.nim`

Update `tests/protocol/tmail_methods.nim` (§12.10, scenarios 84–90):
`addEmailParse` name + capability (84), body fetch options parity with
addEmailGet (85). `addSearchSnippetGet` name (86), single email id (87),
cons-cell ids (88), filter required compile check via
`assertNotCompiles` (89), filter serialised in args (90).

### Step 22: Response serde tests

**Update:** `tests/serde/mail/tserde_snippet.nim`

Extend `tests/serde/mail/tserde_snippet.nim` (§12.9, scenarios 66–74):
`searchSnippetGetResponseFromJson` notFound null (66), notFound array
(67), notFound key absent (68). `emailParseResponseFromJson` parsed null
(69), parsed entries (70), parsed key absent (71), `"notParsable"` RFC
key (72), `"notParseable"` Nim spelling NOT accepted (73). Non-JObject
input for both response types (74).

### Step 23: Adversarial tests

**Create:** `tests/serde/mail/tserde_email_adversarial.nim`

Create `tests/serde/mail/tserde_email_adversarial.nim` (§12.11,
scenarios 91–123): Two-phase boundary — `"from"` and
`"header:From:asAddresses"` coexistence (91), 100 dynamic header keys
stress (92). Dynamic header injection — empty name (93), too many
segments (94), unknown form (95), `"header"` without colon (96).
EmailComparator discriminant — underscore in property (97), wrong case
(98), leading whitespace (99), empty keyword (100), spurious keyword on
plain (101), missing property (102), null property (103).
EmailHeaderFilter — colon in name (104), NUL byte (105). Filter with
empty value vs absent (106). PartId — duplicate keys last-wins (107),
empty string rejection (108). Filter contradictory size (109), colon in
header name (110). Response adversarial — null list (111), HTML
preserved in snippet (112), unknown fields ignored (113), all wrong
types (114). Recursive 50-level body (115), Cyrillic homoglyph key
(116), max UnsignedInt (117). Cross-field — same header different form
(118), all flags true with empty value (119), keyword-mailbox mismatch
(120), attachments-hasAttachment contradiction (121), temporal
contradiction in filter (122), referential integrity not validated (123).

### Step 24: Integration tests

**Create:** `tests/serde/mail/tserde_email_integration.nim`

Create `tests/serde/mail/tserde_email_integration.nim` (§12.13,
scenarios 132–136): Shared helper parity — same JSON to emailFromJson
and parsedEmailFromJson produces identical shared fields (132). Email
round-trip with dynamic headers (133). Dynamic header Phase 2 round-trip
preserving keys and values (134). Builder body fetch options parity
between addEmailGet and addEmailParse (135). Builder-filter chain —
addEmailQuery filter matches EmailFilterCondition.toJson output (136).

### CI gate

Run `just ci` before committing.

---

## Phase 4: Re-export hub updates

**Design doc:** §11.3 (re-export hub updates).

### Step 25: types.nim re-exports

**Update:** `src/jmap_client/mail/types.nim`

Update `mail/types.nim` to import and re-export Part D Layer 1 modules:
`email`, `snippet`.

### Step 26: serialisation.nim re-exports

**Update:** `src/jmap_client/mail/serialisation.nim`

Update `mail/serialisation.nim` to import and re-export Part D Layer 2
modules: `serde_email`, `serde_snippet`.

No changes to `mail.nim` or `src/jmap_client.nim` — the existing
re-export chain transitively covers the new modules. `mail_entities.nim`,
`mail_builders.nim`, and `mail_methods.nim` are already re-exported from
prior parts. `mail_filters.nim` and `serde_mail_filters.nim` are already
in the hub from Part B.

Verify all Part D public symbols are accessible through
`import jmap_client`: `Email`, `ParsedEmail`, `parseEmail`, `isLeaf`,
`PlainSortProperty`, `KeywordSortProperty`, `EmailComparatorKind`,
`EmailComparator`, `plainComparator`, `keywordComparator`, `BodyValueScope`,
`EmailBodyFetchOptions`, `SearchSnippet`, `EmailFilterCondition`,
`EmailHeaderFilter`, `parseEmailHeaderFilter`, `emailFromJson`,
`parsedEmailFromJson`, `emailComparatorFromJson`, `searchSnippetFromJson`,
`searchSnippetGetResponseFromJson`, `emailParseResponseFromJson`,
`EmailParseResponse`, `SearchSnippetGetResponse`, `addEmailGet`,
`addEmailQuery`, `addEmailQueryChanges`, `addEmailParse`,
`addSearchSnippetGet`.

### CI gate

Run `just ci` before committing.

---

## Phase 5: Property-based tests

**Design doc:** §12.12 (scenarios 124–131), §12.14 (generators).

### Step 27: Generators (§12.14)

**Update:** `tests/mproperty.nim`

Add to `tests/mproperty.nim` following existing conventions (edge-biased
early trials, fixed seed):

Leaf generators: `genKeyword(rng)` (pool of standard keywords + random
valid flag names), `genKeywordSet(rng)` (0–5 keywords),
`genMailboxIdSet(rng)` (1–5 Ids, non-empty for Email invariant),
`genSearchSnippet(rng)` (random emailId, optional subject/preview).

Shared helper generators mirroring serde helpers (D7):
`genConvenienceHeaders(rng)` (11 fields, composes `genEmailAddress`,
`genValidDate`, `genArbitraryString`), `genBodyFields(rng)` (7 fields,
composes `genEmailBodyPart`, `genPartId`, `genEmailBodyValue`).
Both used by `genEmail` and `genParsedEmail` to ensure parity.

Composite generators: `genEmailComparator(rng)` (50/50 plain/keyword,
random optional isAscending/collation), `genEmailBodyFetchOptions(rng)`
(uniform BodyValueScope, optional bodyProperties/maxBodyValueBytes),
`genEmailFilterCondition(rng)` (early-biased: trial 0 = all-none,
trial 1 = all-some, remaining 30% some / 70% none per field),
`genDeepBodyStructure(rng, depth)` (recursive multipart for stress
tests), `genEmail(rng)` (composes all leaf + helper generators, 28
fields), `genParsedEmail(rng)` (like genEmail minus 6 metadata, threadId
50/50 some/none).

### Step 28: Property tests (§12.12, scenarios 124–131)

**Create:** `tests/property/tprop_mail_d.nim`

`tests/property/tprop_mail_d.nim` covers:

EmailComparator round-trip (124, DefaultTrials = 500):
`emailComparatorFromJson(ec.toJson()) == ec`.

EmailBodyFetchOptions structural (125, QuickTrials = 200):
`BodyValueScope` variant determines exactly which `fetch*BodyValues`
keys appear.

EmailFilterCondition field-count (126, DefaultTrials = 500):
`fc.toJson().len == count of Opt.some fields in fc`. Early-biased
generator guarantees all-none and all-some extremes.

Totality — emailFromJson (127, DefaultTrials = 500): never crashes on
arbitrary `JsonNode` (maxDepth=3). Totality — parsedEmailFromJson (128,
DefaultTrials = 500). Totality — emailComparatorFromJson (129,
DefaultTrials = 500, maxDepth=2).

Email round-trip (130, ThoroughTrials = 2000):
`emailFromJson(e.toJson()) == e` for valid Email including dynamic
headers. ParsedEmail round-trip (131, ThoroughTrials = 2000).

### CI gate

Run `just ci` before committing.
