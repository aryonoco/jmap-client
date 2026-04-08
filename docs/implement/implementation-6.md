# Mail Part B Implementation Plan

Layers 1-4 of RFC 8620 core are complete. Mail Part A added Thread, Identity,
and VacationResponse entities plus shared sub-types. This plan adds the second
vertical slice of RFC 8621: Keyword shared sub-type, Mailbox entity, and all
supporting types (MailboxRole, MailboxIdSet, MailboxRights, MailboxCreate,
MailboxFilterCondition), plus two additive core prerequisites and
Mailbox-specific builder functions. All new mail code lives under
`src/jmap_client/mail/`. Full specification: `docs/design/07-mail-b-design.md`,
building on cross-cutting design `docs/design/05-mail-design.md`.

5 steps, one commit each, bottom-up through the dependency DAG. Every step
passes `just ci` before committing.

Cross-cutting requirements apply to all steps: all modules follow established
core patterns — SPDX header, `{.push raises: [].}`, `func` for pure
functions, `Result[T, ValidationError]` for smart constructors, `Opt[T]` for
optional fields, `checkJsonKind`/`optJsonField`/`parseError` for serde.
Design doc §7 (test specification, scenarios 1–79) and §8 (decision
traceability matrix, B1–B21) provide per-scenario coverage targets.

---

## Step 1: Core prerequisites — defineHashSetDistinctOps, QueryParams, builder refactor

**Update:** `src/jmap_client/validation.nim`,
`src/jmap_client/framework.nim`, `src/jmap_client/builder.nim`,
`tests/protocol/tbuilder.nim`

**Design doc:** §2 (Core Prerequisites), Decisions B3, B10.

Add the `defineHashSetDistinctOps` template to `validation.nim` alongside
the existing `defineStringDistinctOps` and `defineIntDistinctOps`. The
template takes two `typedesc` parameters (`T` for the distinct type, `E`
for the element type) and borrows three read-only operations: `len`,
`contains`, `card`. No mutation operations — these are immutable read
models (Decision B3).

Add the `QueryParams` value object to `framework.nim`. Five plain public
fields: `position: JmapInt` (default `JmapInt(0)`), `anchor: Opt[Id]`
(default absent), `anchorOffset: JmapInt` (default `JmapInt(0)`),
`limit: Opt[UnsignedInt]` (default absent), `calculateTotal: bool`
(default `false`). No smart constructor — all field combinations are valid
per RFC 8620 §5.5.

Refactor `addQuery[T, C]` and `addQueryChanges[T, C]` in `builder.nim` to
accept `QueryParams` instead of the five individual parameters (`position`,
`anchor`, `anchorOffset`, `limit`, `calculateTotal`). Mechanical signature
change — the builder unpacks `QueryParams` fields into the request. The
single-type-parameter template overloads (`addQuery[T]`,
`addQueryChanges[T]`) are unchanged — Nim cannot evaluate `QueryParams()`
(which contains case-object `Opt[T]` fields) as a template default value.
For custom `QueryParams`, callers use the two-parameter proc overloads
directly.

Update `tests/protocol/tbuilder.nim`: existing test blocks need no changes
(all use default parameters, which are identical with default
`QueryParams()`). Add four new test blocks verifying `QueryParams`
integration: non-default fields unpacked correctly, default `QueryParams()`
matches RFC 8620 §5.5, `calculateTotal` flows through to queryChanges,
and non-applicable fields (position, anchor, anchorOffset, limit) do not
leak into queryChanges JSON.

---

## Step 2: Keyword + KeywordSet — keyword.nim + serde_keyword.nim

**Create:** `src/jmap_client/mail/keyword.nim`,
`src/jmap_client/mail/serde_keyword.nim`,
`tests/unit/mail/tkeyword.nim`, `tests/serde/mail/tserde_keyword.nim`

**Design doc:** §3 (Keyword), Decisions B1, B2, B3, B15.

`keyword.nim` defines:

`KeywordForbiddenChars` constant: `set[char] = {'(', ')', '{', ']', '%',
'*', '"', '\\'}`. Same pattern as `Base64UrlChars` in `primitives.nim`.

`Keyword` as `distinct string` with `defineStringDistinctOps(Keyword)` for
`==`, `$`, `hash`, `len`. `parseKeyword` (strict) validates length 1–255
bytes, ASCII printable range `%x21`–`%x7E` (no space), rejects
`KeywordForbiddenChars`, normalises to lowercase. Post-construction
`doAssert` on length bounds. `parseKeywordFromServer` (lenient) validates
length 1–255 bytes, no control characters (same `validateServerAssignedToken`
pattern as `parseIdFromServer`), normalises to lowercase. The strict/lenient
gap is the IMAP-specific forbidden character set (Decision B1).

Eight system keyword constants as module-level `const`: `kwDraft`,
`kwSeen`, `kwFlagged`, `kwAnswered`, `kwForwarded`, `kwPhishing`, `kwJunk`,
`kwNotJunk`. Direct `Keyword(...)` construction is the permitted bypass for
compile-time-provable literals.

`KeywordSet` as `distinct HashSet[Keyword]` with
`defineHashSetDistinctOps(KeywordSet, Keyword)`. Infallible
`initKeywordSet(keywords: openArray[Keyword]): KeywordSet` (empty set
valid per Decision B2). `items` iterator for `for kw in keywordSet:` syntax.

`serde_keyword.nim`: `Keyword` serde via `defineDistinctStringToJson` and
`defineDistinctStringFromJson(Keyword, parseKeywordFromServer)` (lenient per
B15 convention). `KeywordSet.toJson` iterates via `items`, emits each keyword
as key with `true` value; empty set emits `{}`. `KeywordSet.fromJson`
validates JObject, rejects any `false` value with
`err(validationError("KeywordSet", "all keyword values must be true", key))`,
parses each key via `parseKeywordFromServer` with `?` short-circuit.

Tests cover scenarios 1–22:

`tests/unit/mail/tkeyword.nim` (scenarios 1–17): `parseKeyword` valid
lowercase (1), uppercase normalised (2), empty rejection (3), 256-byte
rejection (4), space rejection (5), forbidden `(` (6), forbidden `\` (7).
`parseKeywordFromServer` accepts forbidden chars (8), rejects control chars
(9), rejects empty (10). System constants valid (11). Equality
case-normalised (12), hash consistent with `==` (13), `len` correct (14).
`initKeywordSet` two keywords (15), empty set (16), deduplication (17).

`tests/serde/mail/tserde_keyword.nim` (scenarios 18–22): `toJson` with
keywords (18), empty set (19). `fromJson` valid (20), `false` value
rejection (21). Round-trip identity (22).

---

## Step 3: Mailbox types + MailboxFilterCondition

**Create:** `src/jmap_client/mail/mailbox.nim`,
`src/jmap_client/mail/serde_mailbox.nim`,
`src/jmap_client/mail/mail_filters.nim`,
`src/jmap_client/mail/serde_mail_filters.nim`,
`tests/unit/mail/tmailbox.nim`, `tests/serde/mail/tserde_mailbox.nim`,
`tests/serde/mail/tserde_mail_filters.nim`

**Design doc:** §4 (Mailbox), §5 (MailboxFilterCondition), Decisions B4,
B5, B6, B7, B8, B11, B16, B18, B19, B20, B21.

`mailbox.nim` defines five types:

`MailboxRole` as `distinct string` with `defineStringDistinctOps`. Single
`parseMailboxRole` validates non-empty, normalises to lowercase,
post-construction `doAssert len > 0`. No strict/lenient pair — no
meaningful gap between spec and structural constraints (Decision B20). Ten
well-known constants: `roleInbox`, `roleDrafts`, `roleSent`, `roleTrash`,
`roleJunk`, `roleArchive`, `roleImportant`, `roleAll`, `roleFlagged`,
`roleSubscriptions`.

`MailboxIdSet` as `distinct HashSet[Id]` with
`defineHashSetDistinctOps(MailboxIdSet, Id)`. Infallible
`initMailboxIdSet(ids: openArray[Id]): MailboxIdSet`. `items` iterator.
Same pattern as `KeywordSet` (Decision B4).

`MailboxRights` as plain object with nine `bool` fields: `mayReadItems`,
`mayAddItems`, `mayRemoveItems`, `maySetSeen`, `maySetKeywords`,
`mayCreateChild`, `mayRename`, `mayDelete`, `maySubmit`. No smart
constructor — all boolean combinations valid (Decision B6).

`Mailbox` as plain object with eleven fields: `id: Id`, `name: string`,
`parentId: Opt[Id]`, `role: Opt[MailboxRole]`, `sortOrder: UnsignedInt`,
`totalEmails: UnsignedInt`, `unreadEmails: UnsignedInt`,
`totalThreads: UnsignedInt`, `unreadThreads: UnsignedInt`,
`myRights: MailboxRights`, `isSubscribed: bool`. No smart constructor —
`fromJson` enforces non-empty `name` at parsing boundary (Decisions B5,
B19).

`MailboxCreate` with `parseMailboxCreate` smart constructor validating
non-empty `name`, default parameters matching RFC defaults
(`parentId = Opt.none(Id)`, `role = Opt.none(MailboxRole)`,
`sortOrder = UnsignedInt(0)`, `isSubscribed = false`). Post-construction
`doAssert name.len > 0`. Same pattern as `parseIdentityCreate` (Decision
B7).

`serde_mailbox.nim`: `MailboxRole` serde via `defineDistinctStringToJson`
and `defineDistinctStringFromJson(MailboxRole, parseMailboxRole)`.
`MailboxIdSet` serde same structure as `KeywordSet` but uses
`parseIdFromServer` for key parsing. `MailboxRights.toJson` emits all 9
bool fields. `MailboxRights.fromJson` extracts all 9 bool fields as
required, absent or non-bool yields error. `Mailbox.toJson` emits all
fields; `parentId`/`role` emit as `null` or value.
`Mailbox.fromJson` validates all required fields, `name` rejects
absent/null/empty, `parentId`/`role` absent/null yield `Opt.none`.
`MailboxCreate.toJson` emits all 5 fields; no `fromJson`.

`mail_filters.nim`: `MailboxFilterCondition` with `Opt[Opt[T]]` three-state
pattern for `parentId: Opt[Opt[Id]]` and `role: Opt[Opt[MailboxRole]]`,
plus `name: Opt[string]`, `hasAnyRole: Opt[bool]`,
`isSubscribed: Opt[bool]`. No smart constructor (Decision B16).

`serde_mail_filters.nim`: `MailboxFilterCondition.toJson` only (Decision
B11). Three-way dispatch for `Opt[Opt[T]]` fields: `Opt.none` omits key,
`Opt.some(Opt.none)` emits `null`, `Opt.some(Opt.some(v))` emits value.
Simple `Opt` fields emit when present, omit when absent. No `fromJson`.

Tests cover scenarios 23–62:

`tests/unit/mail/tmailbox.nim` (scenarios 23–27, 30–31, 50–52):
`parseMailboxRole` valid lowercase (23), uppercase normalised (24), custom
role (25), empty rejection (26), constants equal parsed equivalents (27).
`initMailboxIdSet` with ids (30), empty (31). `parseMailboxCreate`
defaults-only (50), all fields (51), empty name rejection (52).

`tests/serde/mail/tserde_mailbox.nim` (scenarios 28–29, 32–49, 53–55):
`MailboxRole` toJson (28), fromJson (29). `MailboxIdSet` toJson (32),
fromJson valid (33), false rejection (34), round-trip (35).
`MailboxRights` fromJson all fields (36), missing field (37), non-bool
(38), round-trip (39). `Mailbox` fromJson all fields (40), name absent
(41), name empty (42), parentId null (43), parentId present (44), role
null (45), role present (46), role uppercase normalised (47), round-trip
(48), missing required field (49). `MailboxCreate` toJson structure (53),
no server-set fields (54), null optionals (55).

`tests/serde/mail/tserde_mail_filters.nim` (scenarios 56–62): all fields
none yields `{}` (56), parentId null (57), parentId value (58), role null
(59), role value (60), name present (61), mixed filter (62).

---

## Step 4: Entity registration + builder functions

**Create:** `src/jmap_client/mail/mail_builders.nim`,
`tests/protocol/tmail_builders.nim`

**Update:** `src/jmap_client/mail/mail_entities.nim`,
`tests/protocol/tmail_entities.nim`

**Design doc:** §6 (Entity Registration and Builders), Decisions B9, B12,
B13, B14, B21.

Update `mail_entities.nim`: add Mailbox registration alongside existing
Thread and Identity. Define `methodNamespace` (`"Mailbox"`) and
`capabilityUri` (`"urn:ietf:params:jmap:mail"`) overloads. Call
`registerJmapEntity(Mailbox)`. Define `template filterType*(T:
typedesc[Mailbox]): typedesc = MailboxFilterCondition` and the
`filterConditionToJson` func dispatching to `MailboxFilterCondition.toJson`.
Call `registerQueryableEntity(Mailbox)`.

Create `mail_builders.nim` with five components:

`MailboxChangesResponse` via composition (Decision B9):
`base: ChangesResponse[Mailbox]` plus
`updatedProperties: Opt[seq[string]]`. `forwardChangesFields` template
generates UFCS forwarding funcs (`accountId`, `oldState`, `newState`,
`hasMoreChanges`, `created`, `updated`, `destroyed`). `fromJson` parses
base via `ChangesResponse[Mailbox].fromJson`, extracts
`updatedProperties` (absent/null yields `Opt.none`, JArray yields
`Opt.some(seq[string])`).

`addMailboxChanges`: adds mail capability, `"Mailbox/changes"` invocation.
Returns `ResponseHandle[MailboxChangesResponse]`. Parameters: `accountId`,
`sinceState`, `maxChanges`.

`addMailboxQuery` (`proc` — callback parameter): adds mail capability,
`"Mailbox/query"` invocation. Standard query parameters via `QueryParams`,
plus `sortAsTree: bool = false` and `filterAsTree: bool = false` (inline
booleans per Decision B13). Returns `ResponseHandle[QueryResponse[Mailbox]]`.

`addMailboxQueryChanges` (`proc`): adds mail capability,
`"Mailbox/queryChanges"` invocation. Standard parameters only — RFC 8621
§2.4 specifies no additional request arguments (Decision B12, corrected).
Returns `ResponseHandle[QueryChangesResponse[Mailbox]]`.

`addMailboxSet` (`func`): adds mail capability, `"Mailbox/set"` invocation.
Accepts `Table[CreationId, MailboxCreate]` for create (typed per Decision
B21), calls `toJson` on each `MailboxCreate` internally. Includes
`onDestroyRemoveEmails: bool = false`. Returns
`ResponseHandle[SetResponse[Mailbox]]`.

Tests cover scenarios 63–79:

Update `tests/protocol/tmail_entities.nim`: Mailbox registration compiles
(68), queryable registration compiles (69).

Create `tests/protocol/tmail_builders.nim`:
`MailboxChangesResponse.fromJson` with `updatedProperties` present (63),
absent (64), null (65), forwarding accessors (66), missing base field (67).
`addMailboxChanges` invocation name (70), capability (71).
`addMailboxQuery` invocation name (72), `sortAsTree` in args (73),
`filterAsTree` in args (74). `addMailboxQueryChanges` invocation name (75),
no tree parameters (76). `addMailboxSet` invocation name (77),
`onDestroyRemoveEmails` (78), typed `MailboxCreate` in create map (79).

---

## Step 5: Re-export hub updates

**Update:** `src/jmap_client/mail/types.nim`,
`src/jmap_client/mail/serialisation.nim`, `src/jmap_client/mail.nim`

**Design doc:** §1.6 (Module Summary), cross-cutting doc §3.3 (module
layout).

Update `mail/types.nim` to import and re-export Part B Layer 1 modules:
`keyword`, `mailbox`, `mail_filters`.

Update `mail/serialisation.nim` to import and re-export Part B Layer 2
modules: `serde_keyword`, `serde_mailbox`, `serde_mail_filters`.

Update `mail.nim` to add import and re-export of `mail_builders`. The
existing `mail_entities` re-export already covers updated registrations.

No changes to `src/jmap_client.nim` — it already imports and re-exports
`mail`, which transitively covers all new modules.

Verify all Part B public symbols are accessible through
`import jmap_client`: `Keyword`, `KeywordSet`, `kwDraft` through
`kwNotJunk`, `parseKeyword`, `parseKeywordFromServer`, `initKeywordSet`,
`MailboxRole`, `roleInbox` through `roleSubscriptions`, `parseMailboxRole`,
`MailboxIdSet`, `initMailboxIdSet`, `MailboxRights`, `Mailbox`,
`MailboxCreate`, `parseMailboxCreate`, `MailboxFilterCondition`,
`MailboxChangesResponse`, `addMailboxChanges`, `addMailboxQuery`,
`addMailboxQueryChanges`, `addMailboxSet`, `QueryParams`. Run `just ci`.
