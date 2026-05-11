# RFC 8621 JMAP Mail — Design B: Keyword, Mailbox

This document is the detailed specification for the `Keyword` shared
sub-type, the `Mailbox` entity, and their supporting types. It covers all
layers (L1 types, L2 serde, L3 entity registration and builder
functions) for each type, cutting vertically through the architecture.

Builds on the cross-cutting architecture design (`05-mail-design.md`),
the existing RFC 8620 infrastructure (`00-architecture.md` through
`04-layer-4-design.md`), and Design A (`06-mail-a-design.md`).

---

## Table of Contents

1. [Scope](#1-scope)
2. [Core Prerequisites](#2-core-prerequisites)
3. [Keyword — keyword.nim](#3-keyword--keywordnim)
4. [Mailbox — mailbox.nim](#4-mailbox--mailboxnim)
5. [MailboxFilterCondition — mail_filters.nim](#5-mailboxfiltercondition--mail_filtersnim)
6. [Entity Registration and Builders](#6-entity-registration-and-builders)
7. [Test Specification](#7-test-specification)

---

## 1. Scope

### 1.1. Entities Covered

| Entity  | RFC 8621 Section | Capability URI              | Complexity |
|---------|------------------|-----------------------------|------------|
| Mailbox | §2               | `urn:ietf:params:jmap:mail` | Moderate   |

### 1.2. Supporting Types Covered

| Type | Module | Rationale |
|------|--------|-----------|
| `Keyword`, `KeywordSet` | `keyword.nim` | Shared sub-type used by Email (`keywords` field), `EmailFilterCondition`, and EmailSubmission |
| `MailboxRoleKind`, `MailboxRole` | `mailbox.nim` | Validated case-object role with closed enum + `mrOther` vendor-extension capture |
| `MailboxIdSet` | `mailbox.nim` | Read-model `distinct HashSet[Id]` for the `mailboxIds` map pattern |
| `NonEmptyMailboxIdSet` | `mailbox.nim` | Creation-context `distinct HashSet[Id]` with at-least-one invariant |
| `MailboxRights` | `mailbox.nim` | ACL flags sub-type for Mailbox |
| `Mailbox` | `mailbox.nim` | Read model |
| `MailboxCreatedItem` | `mailbox.nim` | Partial read model returned in `Mailbox/set` `created[cid]` |
| `MailboxCreate` | `mailbox.nim` | Creation model for `Mailbox/set` |
| `MailboxUpdate`, `MailboxUpdateSet`, `NonEmptyMailboxUpdates` | `mailbox.nim` | Typed update algebra for `Mailbox/set` `update` |
| `MailboxFilterCondition` | `mail_filters.nim` | Query specification for `Mailbox/query` |
| `MailboxChangesResponse` | `mailbox_changes_response.nim` | Extended `/changes` response carrying `updatedProperties` |
| `QueryParams` | `framework.nim` (core) | Shared value object for the five RFC 8620 §5.5 query parameters |

### 1.3. Deferred

`Email`, `SearchSnippet`, `EmailSubmission`, and their sub-types
(`HeaderValue`, `EmailBodyPart`, etc.) are deferred to Design C and
Design D documents. `EmailHeaderFilter` and `EmailFilterCondition` live
alongside `MailboxFilterCondition` in `mail_filters.nim` but are
specified in Design D — only `MailboxFilterCondition` is in scope here.

### 1.4. General Conventions Established

This document establishes four general conventions that apply to all
mail design docs:

1. **Lenient `fromJson` convention.** All `fromJson` for distinct token
   types delegate to the lenient `*FromServer` parser variant. Strict
   parsers are for client-constructed values.

2. **Filter conditions are `toJson`-only.** Filter conditions encode
   query criteria with unidirectional client→server flow. The server
   never sends filter conditions back, so no `fromJson` is defined.
   Same directional pattern as creation types (e.g., `IdentityCreate`,
   `MailboxCreate`).

3. **Strict/lenient parser pairs are principled, not mechanical.** A
   single parser suffices when no meaningful gap exists between
   spec-specific and structural constraints. The pair exists only when
   the strict parser enforces additional spec-specific constraints
   (e.g., IMAP-forbidden chars on `parseKeyword`) that should be
   relaxed for server data.

4. **Entity-specific builders accept typed creation and update
   models.** Custom builder functions accept `Table[CreationId,
   MailboxCreate]` and `NonEmptyMailboxUpdates` rather than raw
   `JsonNode`. Generic builders accept `JsonNode` because they must be
   entity-agnostic; entity-specific builders compose typed values atop
   the generic surface.

### 1.5. Module Summary

All mail modules live under `src/jmap_client/mail/` per cross-cutting
doc §3.3, except for two core prerequisite additions.

| Module | Layer | Contents |
|--------|-------|----------|
| `keyword.nim` | L1 | `Keyword`, `KeywordSet`, `parseKeyword`, `parseKeywordFromServer`, `KeywordForbiddenChars`, system constants |
| `mailbox.nim` | L1 | `MailboxRoleKind`, `MailboxRole`, `parseMailboxRole`, role constants, `MailboxIdSet`, `NonEmptyMailboxIdSet`, `parseNonEmptyMailboxIdSet`, `MailboxRights`, `Mailbox`, `MailboxCreatedItem`, `MailboxCreate`, `parseMailboxCreate`, `MailboxUpdate*`, `MailboxUpdateSet`, `NonEmptyMailboxUpdates` |
| `mail_filters.nim` | L1 | `MailboxFilterCondition` (and the deferred Email filter types) |
| `serde_keyword.nim` | L2 | `toJson`/`fromJson` for `Keyword`, `KeywordSet` |
| `serde_mailbox.nim` | L2 | `toJson`/`fromJson` for `MailboxRole`, `MailboxIdSet`, `NonEmptyMailboxIdSet` (toJson only), `MailboxRights`, `Mailbox`, `MailboxCreatedItem`, `MailboxCreate` (toJson only), `MailboxUpdate*`, `NonEmptyMailboxUpdates` (toJson only) |
| `serde_mail_filters.nim` | L2 | `toJson` for `MailboxFilterCondition` |
| `mailbox_changes_response.nim` | L1+L2 | `MailboxChangesResponse` type, forwarding accessors, and `fromJson` (separate leaf module to break the import cycle that would form between `mail_entities.nim` and `mail_builders.nim`) |
| `mail_entities.nim` | L3 | Entity registration for Mailbox |
| `mail_builders.nim` | L3 | `addMailboxChanges`, `addMailboxQuery`, `addMailboxQueryChanges`, `addMailboxSet` |

**Core prerequisites** (additive extensions, not mail modules):

| Module | Layer | Addition |
|--------|-------|----------|
| `validation.nim` | Core | `defineHashSetDistinctOps`, `defineNonEmptyHashSetDistinctOps`, `validateUniqueByIt` |
| `framework.nim` | Core | `QueryParams` value object |

---

## 2. Core Prerequisites

This section specifies core extensions consumed by the Mailbox
implementation. They are infrastructure — general-purpose templates
and value objects that happen to be first needed by mail types.

### 2.1. defineHashSetDistinctOps — validation.nim

Read-only operations for a `distinct HashSet[T]` type. Two parameters
— the distinct type `T` and the element type `E`:

```nim
template defineHashSetDistinctOps*(T: typedesc, E: typedesc) =
  func len*(s: T): int {.borrow.}
  func contains*(s: T, e: E): bool =
    sets.contains(HashSet[E](s), e)
  func card*(s: T): int {.borrow.}
```

`len` and `card` use `{.borrow.}` (single-parameter, only the set type
is unwrapped). `contains` requires a manual implementation because
Nim's `{.borrow.}` would unwrap *both* distinct type parameters
independently, peeling `E → base-of-E` and producing a type mismatch
when `E` is itself distinct (e.g., `Keyword = distinct string`). The
manual implementation converts only the set type and delegates to
`sets.contains`.

The template requires `std/sets` to be imported at the definition site
(`validation.nim`) because Nim resolves non-parameter identifiers in
template bodies at the definition site, not the expansion site.

**Read-only operations only.** No `==`, no `hash`, no mutation
(`incl`, `excl`), no functional builders. These are read-model sets:
constructed once via infallible constructors or serde, queried, never
compared as whole sets, never used as table keys. Mutation goes
through `/set` with `PatchObject`, not local mutation. Each consuming
module manually defines its own `init*Set` constructor and `items`
iterator — these are domain-specific.

### 2.2. defineNonEmptyHashSetDistinctOps — validation.nim

Creation-context companion template. Composes `defineHashSetDistinctOps`
and adds the operations legitimate when the set is client-constructed
and carries a non-empty invariant:

```nim
template defineNonEmptyHashSetDistinctOps*(T, E: typedesc) =
  defineHashSetDistinctOps(T, E)        # inherits len, contains, card
  func `==`*(a, b: T): bool {.borrow.}
  func `$`*(a: T): string {.borrow.}
  iterator items*(s: T): E = ...
  iterator pairs*(s: T): (int, E) = ...
```

Kept distinct from `defineHashSetDistinctOps` so the read-model
prohibition on whole-set equality is preserved for the base case;
creation-context types opt in to the richer op set explicitly.

`hash` is deliberately absent — stdlib `HashSet.hash` reads `result`
before initialising it, which fails `strictDefs` + `Uninit`-as-error
under `{.borrow.}`. The domain has no use for a non-empty mailbox-id
set as a Table key.

### 2.3. validateUniqueByIt — validation.nim

Accumulating uniqueness validator for smart constructors. Returns a
`seq[ValidationError]` that is empty iff the input is non-empty and
all keys are distinct. Otherwise: one error for empty input, plus one
error per distinct repeated key (three occurrences yield exactly one
error, naming the key once). Single translation site from the
"empty / duplicate" classification to the wire `ValidationError`
shape; callers supply the three wire strings.

Consumed by `initMailboxUpdateSet` (uniqueness over `MailboxUpdate.kind`)
and `parseNonEmptyMailboxUpdates` (uniqueness over mailbox `Id`).

### 2.4. QueryParams — framework.nim

Value object grouping the five query parameters defined by RFC 8620
§5.5. These parameters appear identically on every `/query` and
`/queryChanges` method across all entities.

```nim
type QueryParams* = object
  position*: JmapInt             ## default 0
  anchor*: Opt[Id]               ## default: absent
  anchorOffset*: JmapInt         ## default 0
  limit*: Opt[UnsignedInt]       ## default: absent
  calculateTotal*: bool          ## default false
```

Plain public fields, no smart constructor — all field combinations
are valid per RFC. RFC defaults match Nim zero-initialisation, so
`QueryParams()` produces an RFC-default value. `limit = Opt.none`
means the field is absent on the wire and the server picks the
window size.

The generic `addQuery[T, C, SortT]` and entity-specific
`addMailboxQuery` / `addEmailQuery` builders accept `QueryParams`.

---

## 3. Keyword — keyword.nim

`Keyword` and `KeywordSet` are shared sub-types used by multiple
entities. They are specified here as a prerequisite section — a
shared bounded context, not subordinated to any single entity.
`Keyword` is used by Email (`keywords` field), `EmailFilterCondition`,
and EmailSubmission.

### 3.1. Keyword Type Definition

**RFC reference:** §4.1.1 (`keywords` property).

A keyword is an IMAP flag atom — a case-insensitive ASCII string with
specific character restrictions. The `Keyword` distinct type enforces
validity at construction time and normalises to lowercase as the
canonical form.

```nim
type Keyword* = distinct string

defineStringDistinctOps(Keyword)        # ==, $, hash, len
```

### 3.2. Smart Constructors

Both parsers compose detector primitives from `validation.nim` and
fold any `TokenViolation` to `ValidationError` via `toValidationError`.

**`parseKeyword` (strict):**

```nim
func parseKeyword*(raw: string): Result[Keyword, ValidationError] =
  detectStrictPrintableToken(raw, KeywordForbiddenChars).isOkOr:
    return err(toValidationError(error, "Keyword", raw))
  return ok(Keyword(raw.toLowerAscii()))
```

`detectStrictPrintableToken` enforces:

- Length 1–255 octets
- Printable ASCII (`%x21`..`%x7E`)
- No characters from `KeywordForbiddenChars`

After detection, the value is lowercase-normalised.

**`parseKeywordFromServer` (lenient):**

```nim
func parseKeywordFromServer*(raw: string): Result[Keyword, ValidationError] =
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "Keyword", raw))
  return ok(Keyword(raw.toLowerAscii()))
```

`detectLenientToken` enforces:

- Length 1–255 octets
- No control characters

Tolerates IMAP-forbidden bytes that strict rejects. The structural
constraints (non-empty, bounded length, no control characters,
lowercase normalisation) are shared; the gap is exactly the
IMAP-specific forbidden-character set.

### 3.3. Forbidden Characters Constant

```nim
const KeywordForbiddenChars* =
  {'(', ')', '{', ']', '%', '*', '"', '\\'}
```

Defined once; consumed by `parseKeyword`.

### 3.4. System Keyword Constants

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

Module-level `const` construction is the one permitted bypass of the
smart constructor — these are literals that are provably valid and
already lowercase.

### 3.5. KeywordSet

**RFC reference:** §4.1.1.

`KeywordSet` is a `distinct HashSet[Keyword]`. The RFC mandates that
all values in the wire `keywords` map MUST be `true`; the `bool`
carries no information. A `HashSet[Keyword]` makes the "value is
always true" invariant unrepresentable rather than validated. The
serde layer parses `{"$seen": true, "$flagged": true}` into
`KeywordSet`, rejecting any entry with `false`.

```nim
type KeywordSet* = distinct HashSet[Keyword]

defineHashSetDistinctOps(KeywordSet, Keyword)   # len, contains, card
```

**Constructor:**

```nim
func initKeywordSet*(keywords: openArray[Keyword]): KeywordSet =
  KeywordSet(keywords.toHashSet)
```

Infallible: every `Keyword` in the input is already validated, and
the empty set is a valid domain state (an email with no keywords;
the RFC default for `keywords` is `{}`). The non-empty invariant,
when needed, belongs to the consumer (e.g., `EmailBlueprint` may
require at least one mailbox), not to the collection type itself.

**Items iterator:**

```nim
iterator items*(ks: KeywordSet): Keyword =
  for kw in HashSet[Keyword](ks):
    yield kw
```

Enables `for kw in keywordSet:` syntax. Defined manually because
`defineHashSetDistinctOps` is read-only and intentionally does not
emit an `items` iterator.

### 3.6. Serde — serde_keyword.nim

**Keyword serialisation:**

```nim
defineDistinctStringToJson(Keyword)
defineDistinctStringFromJson(Keyword, parseKeywordFromServer)
```

`fromJson` delegates to the lenient `parseKeywordFromServer`.

**KeywordSet serialisation:**

Wire format:

```json
{"$seen": true, "$flagged": true}
{}
```

`toJson` iterates via `items`, emitting each keyword as a key with
`true` as value. Empty set emits `{}`.

`fromJson`:

- Validates `JObject`.
- Iterates key-value pairs. For each:
  - Validates value is `JBool`. Non-bool → `svkWrongKind`.
  - Rejects `false` with `svkEnumNotRecognised` (`enumTypeLabel = "keyword value"`,
    `rawValue = "false"`).
  - Parses key via `parseKeywordFromServer`, wrapping any
    `ValidationError` as `svkFieldParserFailed` via `wrapInner`.
- Constructs `KeywordSet` from the accumulated `HashSet[Keyword]`.

---

## 4. Mailbox — mailbox.nim

**RFC reference:** §2.

A Mailbox represents a named, stretchable mailbox that contains
Emails. Mailboxes form a tree (via `parentId`), have access rights,
and support rich query/filter operations including tree-aware sorting.

### 4.1. MailboxRole

**RFC reference:** §2 (`role` property), IANA "IMAP Mailbox Name
Attributes" registry.

`MailboxRole` is a sealed case object discriminated by `MailboxRoleKind`.
Ten enum variants name the RFC 8621 §2 well-known roles plus an
`mrOther` catch-all that captures the wire identifier of any
vendor-extension role:

```nim
type MailboxRoleKind* = enum
  mrInbox = "inbox"
  mrDrafts = "drafts"
  mrSent = "sent"
  mrTrash = "trash"
  mrJunk = "junk"
  mrArchive = "archive"
  mrImportant = "important"
  mrAll = "all"
  mrFlagged = "flagged"
  mrSubscriptions = "subscriptions"
  mrOther                                ## no backing string

type MailboxRole* = object
  case rawKind: MailboxRoleKind          ## module-private discriminator
  of mrOther:
    rawIdentifier: string                ## vendor-extension wire identifier
  of mrInbox, mrDrafts, mrSent, mrTrash, mrJunk, mrArchive,
      mrImportant, mrAll, mrFlagged, mrSubscriptions:
    discard
```

**Construction is sealed.** `rawKind` and `rawIdentifier` are
module-private, so direct literal construction from outside this
module is rejected. Use `parseMailboxRole` for untrusted input, or
the named role constants (`roleInbox`, `roleDrafts`, …) for the ten
well-known values.

**Public surface:**

```nim
func kind*(r: MailboxRole): MailboxRoleKind
func identifier*(r: MailboxRole): string
func `$`*(r: MailboxRole): string         # equivalent to identifier
func `==`*(a, b: MailboxRole): bool
func hash*(r: MailboxRole): Hash
```

`identifier` is the wire form: the enum's backing string for the ten
well-known kinds, the captured `rawIdentifier` for `mrOther`. Equality
and hash are nested-case dispatch; under `strictCaseObjects` both
operands' discriminators must be matched literally before any
variant-only field is read (see `nim-type-safety.md` "Rule 4").

**Smart constructor:**

```nim
func parseMailboxRole*(raw: string): Result[MailboxRole, ValidationError] =
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "MailboxRole", raw))
  let normalised = raw.toLowerAscii()
  let parsed = parseEnum[MailboxRoleKind](normalised, mrOther)
  case parsed
  of mrInbox: return ok(roleInbox)
  ...
  of mrOther: return ok(MailboxRole(rawKind: mrOther, rawIdentifier: normalised))
```

`detectNonControlString` rejects empty input and control characters;
after lowercase normalisation, `parseEnum` classifies against the
ten well-known backing strings, falling back to `mrOther` for vendor
extensions. Lossless wire round-trip:
`$(parseMailboxRole(x).get) == x.toLowerAscii` for every `x` that
survives detection.

**Single parser, no strict/lenient pair.** `MailboxRole`'s only
constraints beyond non-empty + no-control-chars are lowercase
normalisation. Unlike `Keyword` (which has IMAP-specific forbidden
chars to relax), there is no meaningful gap between spec and
structural constraints — a single parser serves both client
construction and server-data parsing.

**Well-known role constants:**

```nim
const
  roleInbox*         = MailboxRole(rawKind: mrInbox)
  roleDrafts*        = MailboxRole(rawKind: mrDrafts)
  roleSent*          = MailboxRole(rawKind: mrSent)
  roleTrash*         = MailboxRole(rawKind: mrTrash)
  roleJunk*          = MailboxRole(rawKind: mrJunk)
  roleArchive*       = MailboxRole(rawKind: mrArchive)
  roleImportant*     = MailboxRole(rawKind: mrImportant)
  roleAll*           = MailboxRole(rawKind: mrAll)
  roleFlagged*       = MailboxRole(rawKind: mrFlagged)
  roleSubscriptions* = MailboxRole(rawKind: mrSubscriptions)
```

Constructed inside `mailbox.nim`, so the sealed `rawKind` field is
accessible. Outside the module, the constants are the only way to
obtain a `MailboxRole` value without going through `parseMailboxRole`.

### 4.2. Mailbox ID Collections

Two parallel `distinct HashSet[Id]` types with different invariants,
kept side-by-side so the "same shape, different contract"
relationship is structurally visible.

**MailboxIdSet (read-model, empty allowed):**

```nim
type MailboxIdSet* = distinct HashSet[Id]

defineHashSetDistinctOps(MailboxIdSet, Id)   # len, contains, card

func initMailboxIdSet*(ids: openArray[Id]): MailboxIdSet
iterator items*(ms: MailboxIdSet): Id
```

Construction is infallible. Empty set is valid. Used wherever the
domain represents "a possibly-empty collection of mailbox ids" —
e.g., `Email.mailboxIds` reads.

**NonEmptyMailboxIdSet (creation-context, at-least-one):**

```nim
type NonEmptyMailboxIdSet* = distinct HashSet[Id]

defineNonEmptyHashSetDistinctOps(NonEmptyMailboxIdSet, Id)
                                              # len, contains, card,
                                              # ==, $, items, pairs

func parseNonEmptyMailboxIdSet*(
    ids: openArray[Id]
): Result[NonEmptyMailboxIdSet, ValidationError]
```

`parseNonEmptyMailboxIdSet` returns `err` on empty input and dedupes
via the underlying `HashSet`. Mutating ops (`incl`, `excl`) are
deliberately not borrowed — they would violate the at-least-one
invariant. Consumed by `EmailBlueprint` (Design D) as the typed
`mailboxIds` parameter.

### 4.3. MailboxRights

**RFC reference:** §2.4.

Plain object with nine independent boolean flags:

```nim
type MailboxRights* = object
  mayReadItems*: bool
  mayAddItems*: bool
  mayRemoveItems*: bool
  maySetSeen*: bool
  maySetKeywords*: bool
  mayCreateChild*: bool
  mayRename*: bool
  mayDelete*: bool
  maySubmit*: bool
```

Plain public fields, no smart constructor. Every combination of
nine booleans has a meaningful domain interpretation (a user with
different permission levels). The `may*` naming is self-documenting
(`mayDelete: true` means "may delete"); the RFC also literally
models these as `Boolean`. This is the documented exception to the
"booleans are a code smell" guideline (see
`nim-functional-core.md` "Named two-case enum replaces bool").

`MailboxRights` is server-set and immutable from the client's
perspective — it represents the current user's rights, not a rights
assignment. It is excluded from `MailboxCreate` (§4.6).

### 4.4. Mailbox

The typed `Mailbox` represents a **complete** RFC domain object —
all properties present. `GetResponse[Mailbox].list: seq[Mailbox]`
requires every wire entry to satisfy `Mailbox.fromJson`'s
full-record contract (A3). Partial property responses (when the
client deliberately requests only specific properties via
`addMailboxGet(properties = …)`) surface
`MethodError(metServerFail)` on the public typed entry point
because elided fields fail full-record parsing; a future
`PartialMailbox` type (A3.6) closes the public-surface gap
additively. Raw `Invocation.arguments` is sealed inside the
`internal/` namespace per A2 — not an application escape hatch.
No `Opt` wrapping on `Mailbox` itself for "was this property
requested?".

```nim
type Mailbox* = object
  id*: Id
  name*: string                    ## non-empty (fromJson enforced)
  parentId*: Opt[Id]               ## null = root-level mailbox
  role*: Opt[MailboxRole]          ## null = no assigned role
  sortOrder*: UnsignedInt          ## default 0
  totalEmails*: UnsignedInt
  unreadEmails*: UnsignedInt
  totalThreads*: UnsignedInt
  unreadThreads*: UnsignedInt
  myRights*: MailboxRights
  isSubscribed*: bool
```

Plain public fields. All field-level invariants are captured by the
types themselves (`Id`, `Opt[MailboxRole]`, `UnsignedInt`,
`MailboxRights`, `bool`). No cross-field invariants. Consistent with
`Identity` and `Account` in core.

`name` uses `string` (not `Opt[string]`) — the RFC specifies `name`
as `String` (never null) and it is required on every Mailbox.
`fromJson` rejects absent or empty `name` at the parsing boundary.

`parentId: Opt[Id]` and `role: Opt[MailboxRole]` are domain-level
optionals (the RFC says these can be null), not "was this property
requested?" optionality.

No smart constructor for the read model — `fromJson` extracts fields,
validates JSON structure, and constructs directly.

### 4.5. MailboxCreatedItem

**RFC reference:** RFC 8620 §5.3 (the `created[cid]` payload returned
by `Foo/set`), RFC 8621 §2.1 (server-set Mailbox properties).

The server-authoritative subset returned in `Mailbox/set` `created[cid]`:
the server MUST return `id` plus any server-set or server-modified
properties. For Mailbox the server-set properties per RFC 8621 §2.1
are the four count fields and `myRights`. The full `Mailbox` record
is NOT returned — the client already knows the other fields (it
sent them in `create`).

```nim
type MailboxCreatedItem* = object
  id*: Id
  totalEmails*: Opt[UnsignedInt]
  unreadEmails*: Opt[UnsignedInt]
  totalThreads*: Opt[UnsignedInt]
  unreadThreads*: Opt[UnsignedInt]
  myRights*: Opt[MailboxRights]
```

All five server-set fields are `Opt[T]` because Stalwart 0.15.5 omits
them from this payload (a strict-RFC §5.3 minor divergence): the
create acknowledgement is just `{"id": "<id>"}`. Postel's-law
accommodation: be lenient on receive. Mirrors the `IdentityCreatedItem`
shape in `identity.nim`.

`MailboxCreatedItem` is the typed `createResults` payload of
`SetResponse[MailboxCreatedItem]` — the response handle returned by
`addMailboxSet`.

### 4.6. MailboxCreate

The Mailbox read model and creation model have different valid field
sets: creates require `name` and exclude all server-set fields
(`id`, the four counts, `myRights`). A distinct type makes "create
without name" unrepresentable.

```nim
type MailboxCreate* = object
  name*: string                    ## required, non-empty
  parentId*: Opt[Id]               ## default: none (top-level)
  role*: Opt[MailboxRole]          ## default: none (no role)
  sortOrder*: UnsignedInt          ## default: 0
  isSubscribed*: bool              ## default: false
```

**Smart constructor:**

```nim
func parseMailboxCreate*(
    name: string,
    parentId: Opt[Id] = Opt.none(Id),
    role: Opt[MailboxRole] = Opt.none(MailboxRole),
    sortOrder: UnsignedInt = UnsignedInt(0),
    isSubscribed: bool = false,
): Result[MailboxCreate, ValidationError]
```

Validates: `name` non-empty (returns
`validationError("MailboxCreate", "name must not be empty", "")` on
empty input). Default parameter values match RFC-specified defaults
for ergonomic construction:

```nim
let mc  = ?parseMailboxCreate(name = "Archive")          # all defaults
let mc2 = ?parseMailboxCreate(name = "Inbox",
    role = Opt.some(roleInbox))
```

`role` is included on the creation type — the RFC allows setting role
on create. Server rejection (e.g., a server that reserves `inbox`
role) is handled via `SetError`, not at the type level.

No `MailboxCreate.fromJson` — creation types flow client→server only.

### 4.7. Mailbox Update Algebra

`MailboxUpdate` is a typed sum-type ADT for `Mailbox/set` `update`
operations. One variant per RFC 8621 §2 settable property.
Whole-value replace semantics — no sub-path targeting (contrast
`EmailUpdate`, which targets keyword/mailbox sub-paths).

```nim
type MailboxUpdateVariantKind* = enum
  muSetName
  muSetParentId
  muSetRole
  muSetSortOrder
  muSetIsSubscribed

type MailboxUpdate* = object
  case kind*: MailboxUpdateVariantKind
  of muSetName:         name*: string
  of muSetParentId:     parentId*: Opt[Id]              ## null reparents to top-level
  of muSetRole:         role*: Opt[MailboxRole]         ## null clears the role
  of muSetSortOrder:    sortOrder*: UnsignedInt
  of muSetIsSubscribed: isSubscribed*: bool
```

The case object makes "exactly one target per update" a type-level
fact, closing the empty-update and multi-property-update holes that
a flat five-`Opt[T]` record would leave open.

**Smart constructors** — one per variant:

```nim
func setName*(name: string): MailboxUpdate
func setParentId*(parentId: Opt[Id]): MailboxUpdate
func setRole*(role: Opt[MailboxRole]): MailboxUpdate
func setSortOrder*(sortOrder: UnsignedInt): MailboxUpdate
func setIsSubscribed*(isSubscribed: bool): MailboxUpdate
```

Total — `setName("")` is permitted at the type level because an
empty `name` would surface as an RFC 8621 §2 server-side `SetError`,
not a client-side validation error.

**MailboxUpdateSet** — validated, conflict-free batch targeting a
single mailbox `Id`:

```nim
type MailboxUpdateSet* = distinct seq[MailboxUpdate]

func initMailboxUpdateSet*(
    updates: openArray[MailboxUpdate]
): Result[MailboxUpdateSet, seq[ValidationError]]
```

Accumulating smart constructor (uses `validateUniqueByIt` from
`validation.nim`). Rejects:

- empty input — the wire `update` table has exactly one
  "no updates for this id" representation: omit the entry.
- duplicate target property — two updates with the same `kind` would
  produce a JSON patch object with duplicate keys.

All violations surface in a single `Err` pass; each repeated kind
is reported exactly once.

**NonEmptyMailboxUpdates** — whole-container `update` algebra for
`Mailbox/set`:

```nim
type NonEmptyMailboxUpdates* = distinct Table[Id, MailboxUpdateSet]

func parseNonEmptyMailboxUpdates*(
    items: openArray[(Id, MailboxUpdateSet)]
): Result[NonEmptyMailboxUpdates, seq[ValidationError]]
```

Accumulating smart constructor. Rejects:

- empty input — the `/set` builder's `update` field has exactly one
  "no updates" representation: omit it via `Opt.none`.
- duplicate `Id` keys — silent last-wins shadowing at `Table`
  construction would swallow caller data; the `openArray` input
  preserves duplicates for inspection.

The shape mirrors `NonEmptyEmailSubmissionUpdates` (in
`email_submission.nim`). `addMailboxSet` accepts
`Opt[NonEmptyMailboxUpdates]` and the generic `SetRequest[T, C, U].toJson`
serialises the container via its own `toJson` (§4.8 below) rather
than assembling the wire patch per-caller.

### 4.8. Serde — serde_mailbox.nim

#### MailboxRole

`toJson` emits `r.identifier` as a JSON string (the enum's backing
string for the ten well-known kinds, the captured `rawIdentifier`
for `mrOther`).

`fromJson`:

- Validates `JString`.
- Delegates to `parseMailboxRole`. Rejects non-string with
  `svkWrongKind`; wraps any parser violation (empty, control chars)
  via `wrapInner` as `svkFieldParserFailed`.

#### MailboxIdSet / NonEmptyMailboxIdSet

Wire format:

```json
{"mbx123": true, "mbx456": true}
```

`MailboxIdSet.toJson` and `NonEmptyMailboxIdSet.toJson` share the
same wire shape (the non-empty invariant is enforced at construction,
not in serialisation). `MailboxIdSet.fromJson` validates `JObject`,
rejects non-bool values (`svkWrongKind`), rejects `false`
(`svkEnumNotRecognised`, `enumTypeLabel = "mailbox id value"`), and
parses each key via `parseIdFromServer`.

`NonEmptyMailboxIdSet` is `toJson`-only — it is a creation-context
type that flows client→server.

#### MailboxRights

Wire format:

```json
{
  "mayReadItems": true, "mayAddItems": true, "mayRemoveItems": false,
  "maySetSeen": true, "maySetKeywords": true, "mayCreateChild": false,
  "mayRename": false, "mayDelete": false, "maySubmit": true
}
```

`fromJson` validates `JObject`, extracts all 9 fields as required
booleans (absent or non-bool → `svkWrongKind`), and constructs
directly. `toJson` always emits all 9 fields.

#### Mailbox

`fromJson` validates `JObject`, extracts:

- `id` via `Id.fromJson` (required `JString`).
- `name` as required `JString`, then `nonEmptyStr` enforces non-empty
  at the parsing boundary.
- `parentId` via `parseOptId` — absent or null → `Opt.none(Id)`,
  present `JString` → `Id.fromJson`.
- `role` via `parseOptMailboxRole` — same null/absent semantics.
- `sortOrder`, `totalEmails`, `unreadEmails`, `totalThreads`,
  `unreadThreads` via `UnsignedInt.fromJson` (all required).
- `myRights` via `MailboxRights.fromJson` (required `JObject`).
- `isSubscribed` as required boolean.

`toJson` emits all fields. `parentId` and `role` emit as their value
or `null`; all other fields are unconditional.

#### MailboxCreatedItem

`fromJson` validates `JObject`, requires `id`, and treats the four
count fields plus `myRights` as `Opt` (Stalwart 0.15.5 omits them).
`toJson` emits `id` always and the five server-set fields only when
present (round-trips Stalwart's elision symmetrically — Postel's
law on send too).

#### MailboxCreate

`toJson` only — creation models flow client→server.

```nim
func toJson*(mc: MailboxCreate): JsonNode
```

Wire-shape rules:

- `name` always emitted.
- `parentId` always emitted (value or `null`) — the wire shape
  distinguishes "top-level mailbox" (null) from "nested under X"
  (value).
- `role` emitted only when `Opt.some` — Stalwart accepts both
  omitted and explicit-null forms, but James 3.9 treats `role` as a
  server-set property and rejects creation with
  `invalidArguments` whenever it appears in the payload
  (`MailboxSetMethod.scala` allow-list). RFC 8621 §2.5 leaves `role`
  as an optional client suggestion, so omitting it when the caller
  did not supply a value is RFC-conformant on both targets.
- `sortOrder` emitted only when non-zero — same James 3.9
  compatibility reason. Zero is the RFC default.
- `isSubscribed` always emitted.

#### MailboxUpdate / MailboxUpdateSet / NonEmptyMailboxUpdates

`toJson` only.

```nim
func toJson*(u: MailboxUpdate): (string, JsonNode)
func toJson*(us: MailboxUpdateSet): JsonNode
func toJson*(upd: NonEmptyMailboxUpdates): JsonNode
```

`MailboxUpdate.toJson` emits the `(wire-key, wire-value)` pair —
RFC 8621 §2 settable Mailbox properties are whole-value replace,
each variant maps to exactly one top-level property:

| Variant | Wire key | Wire value |
|---------|----------|------------|
| `muSetName` | `"name"` | `%u.name` |
| `muSetParentId` | `"parentId"` | `u.parentId.optToJsonOrNull()` |
| `muSetRole` | `"role"` | `u.role.optToJsonOrNull()` |
| `muSetSortOrder` | `"sortOrder"` | `u.sortOrder.toJson()` |
| `muSetIsSubscribed` | `"isSubscribed"` | `%u.isSubscribed` |

`MailboxUpdateSet.toJson` flattens to an RFC 8620 §5.3 patch object
`{"name": ..., "role": ..., ...}`. `initMailboxUpdateSet` has
already rejected duplicate target properties, so blind aggregation
cannot shadow a prior entry.

`NonEmptyMailboxUpdates.toJson` flattens to the RFC 8620 §5.3 wire
`update` value `{"<mailboxId>": <patchObj>, ...}`.
`parseNonEmptyMailboxUpdates` has already enforced non-empty input
and distinct ids.

---

## 5. MailboxFilterCondition — mail_filters.nim

**RFC reference:** §2.3.

`MailboxFilterCondition` is a query specification — a value object
describing filter criteria for `Mailbox/query`. It is not a domain
entity; it has no identity, no smart constructor, and is equal by
structure.

The module also hosts `EmailHeaderFilter` and `EmailFilterCondition`
(deferred to Design D).

### 5.1. Type Definition

```nim
type MailboxFilterCondition* = object
  parentId*: Opt[Opt[Id]]            ## three-state: absent / null / value
  name*: Opt[string]                 ## contains match
  role*: Opt[Opt[MailboxRole]]       ## three-state: absent / null / value
  hasAnyRole*: Opt[bool]
  isSubscribed*: Opt[bool]
```

Plain public fields, no smart constructor. All field combinations
are valid.

**The `Opt[Opt[T]]` pattern.** RFC 8621 distinguishes between "this
filter property is not specified" (omit from JSON) and "this filter
property matches null" (include as `null` in JSON). For `parentId`
and `role`, `null` is a meaningful filter value (top-level mailboxes,
no-role mailboxes):

- `Opt.none` = not filtering on this property (omit from JSON)
- `Opt.some(Opt.none)` = filtering for null (emit `null`)
- `Opt.some(Opt.some(value))` = filtering for specific value

`role` uses `Opt[Opt[MailboxRole]]` — once `MailboxRole` is the
typed concept, it propagates to every place that references roles.
One type for the concept everywhere.

### 5.2. Serde — toJson only

`toJson` only — filter conditions flow client→server. The server
never sends filter conditions back.

```nim
func emitThreeState[T](node: JsonNode, key: string, opt: Opt[Opt[T]]) =
  for outer in opt:                       # Opt.none → skip (omit key)
    if outer.isNone:
      node[key] = newJNull()               # Opt.some(Opt.none) → null
    else:
      for inner in outer:
        node[key] = inner.toJson()         # Opt.some(Opt.some(v)) → value

func toJson*(fc: MailboxFilterCondition): JsonNode =
  var node = newJObject()
  node.emitThreeState("parentId", fc.parentId)
  for v in fc.name:        node["name"]         = %v
  node.emitThreeState("role", fc.role)
  for v in fc.hasAnyRole:  node["hasAnyRole"]   = %v
  for v in fc.isSubscribed: node["isSubscribed"] = %v
  return node
```

`emitThreeState` is reusable across any `Opt[Opt[T]]` filter field.
Both `parentId` and `role` use it; the `MailboxRole` overload of
`toJson` (in `serde_mailbox.nim`) handles the inner serialisation
in the third branch.

---

## 6. Entity Registration and Builders

### 6.1. Entity Registration — mail_entities.nim

Mailbox is registered alongside `Thread`, `Identity`, `Email`, and
`AnyEmailSubmission` in `mail_entities.nim`. Three registration
templates verify required overloads at definition time:

```nim
registerJmapEntity(Mailbox)
registerQueryableEntity(Mailbox)
registerSettableEntity(Mailbox)
```

Required overloads provided in this module:

```nim
func methodEntity*(T: typedesc[Mailbox]): MethodEntity = meMailbox
func capabilityUri*(T: typedesc[Mailbox]): string = "urn:ietf:params:jmap:mail"

# Per-verb method-name resolvers — invalid (entity, verb) pairs fail
# at the call site with an undeclared-identifier compile error.
func getMethodName*(T: typedesc[Mailbox]): MethodName = mnMailboxGet
func changesMethodName*(T: typedesc[Mailbox]): MethodName = mnMailboxChanges
func setMethodName*(T: typedesc[Mailbox]): MethodName = mnMailboxSet
func queryMethodName*(T: typedesc[Mailbox]): MethodName = mnMailboxQuery
func queryChangesMethodName*(T: typedesc[Mailbox]): MethodName = mnMailboxQueryChanges

# Associated type templates — return typedesc, resolved at the
# generic builder's instantiation site via mixin.
template changesResponseType*(T: typedesc[Mailbox]): typedesc = MailboxChangesResponse
template filterType*(T: typedesc[Mailbox]): typedesc = MailboxFilterCondition
template createType*(T: typedesc[Mailbox]): typedesc = MailboxCreate
template updateType*(T: typedesc[Mailbox]): typedesc = NonEmptyMailboxUpdates
template setResponseType*(T: typedesc[Mailbox]): typedesc = SetResponse[MailboxCreatedItem]
```

`registerJmapEntity` checks that `methodEntity` and `capabilityUri`
exist; per-verb resolvers are intentionally NOT checked at
registration — they fail at the call site with an error that names
the offending `(entity, verb)` pair, which is more precise than a
generic registration check could be.

`registerQueryableEntity` checks `filterType` and the existence of
a `toJson` overload on the filter condition.
`registerSettableEntity` checks `setMethodName`, `createType`,
`updateType`, and `setResponseType`.

The generic builder instantiations (`addGet[Mailbox]`,
`addChanges[Mailbox]`, `addSet[Mailbox]`, `addQuery[Mailbox]`,
`addQueryChanges[Mailbox]`) all compile via the registered
infrastructure. Consumers should use the entity-specific overloads
in `mail_builders.nim` for methods that carry extra parameters.

### 6.2. MailboxChangesResponse — mailbox_changes_response.nim

RFC 8621 §2.2 extends the standard `/changes` response with an extra
`updatedProperties` field. A custom response type models this via
composition with the standard `ChangesResponse[Mailbox]`.

The type lives in its own leaf module so `mail_entities.nim` can
declare `changesResponseType(Mailbox) = MailboxChangesResponse`
without creating an import cycle with `mail_builders.nim` (which
imports this leaf for its `addMailboxChanges` wrapper).

```nim
type MailboxChangesResponse* = object
  base*: ChangesResponse[Mailbox]
  updatedProperties*: Opt[seq[string]]
```

**Forwarding template:**

```nim
template forwardChangesFields(T: typedesc) =
  func accountId*(r: T): AccountId        = r.base.accountId
  func oldState*(r: T): JmapState         = r.base.oldState
  func newState*(r: T): JmapState         = r.base.newState
  func hasMoreChanges*(r: T): bool        = r.base.hasMoreChanges
  func created*(r: T): seq[Id]            = r.base.created
  func updated*(r: T): seq[Id]            = r.base.updated
  func destroyed*(r: T): seq[Id]          = r.base.destroyed

forwardChangesFields(MailboxChangesResponse)
```

UFCS forwarding funcs for all base fields. Consumer writes
`resp.accountId`, `resp.created` — same API as if it were a flat
type.

**fromJson:**

- Validates `JObject`.
- Reuses `ChangesResponse[Mailbox].fromJson` for the seven standard
  fields (assigned to `base`).
- Extracts `updatedProperties` — absent or null → `Opt.none`,
  present `JArray` → `Opt.some(seq[string])` with each element
  validated as `JString`. Non-array → `svkWrongKind`.

### 6.3. addMailboxChanges

```nim
func addMailboxChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[MailboxChangesResponse]) =
  addChanges[Mailbox, MailboxChangesResponse](
    b, accountId, sinceState, maxChanges
  )
```

Thin alias over the two-parameter `addChanges[T, RespT]`. The
extended response type `MailboxChangesResponse` is fixed at the
phantom type so the caller cannot accidentally use the bare
`ChangesResponse[Mailbox]`.

Builders are functional — they take `RequestBuilder` (not `var`) and
return a tuple `(RequestBuilder, ResponseHandle[T])`. The mail
capability URI is added to the request via the generic builder's
`mixin capabilityUri` resolution.

### 6.4. addMailboxQuery

```nim
func addMailboxQuery*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[MailboxFilterCondition]] =
      Opt.none(Filter[MailboxFilterCondition]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    queryParams: QueryParams = QueryParams(),
    sortAsTree: bool = false,
    filterAsTree: bool = false,
): (RequestBuilder, ResponseHandle[QueryResponse[Mailbox]]) =
  addQuery[Mailbox, MailboxFilterCondition, Comparator](
    b, accountId, filter, sort, queryParams,
    extras = @[("sortAsTree",   %sortAsTree),
               ("filterAsTree", %filterAsTree)],
  )
```

Mailbox uses the protocol-level `Comparator`; the RFC defines no
typed Mailbox comparator. Tree extension args are emitted
unconditionally — `sortAsTree: false` and `filterAsTree: false` are
the RFC defaults but appear on the wire regardless. This is a
documented boolean exception (same reasoning as `MailboxRights`):
the `*AsTree` naming is self-documenting and the RFC models these
as `Boolean`.

`MailboxFilterCondition.toJson` resolves at the caller's
instantiation site via the `mixin` cascade through
`Filter[C].toJson`.

### 6.5. addMailboxQueryChanges

```nim
func addMailboxQueryChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filter: Opt[Filter[MailboxFilterCondition]] =
      Opt.none(Filter[MailboxFilterCondition]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
): (RequestBuilder, ResponseHandle[QueryChangesResponse[Mailbox]]) =
  addQueryChanges[Mailbox, MailboxFilterCondition, Comparator](
    b, accountId, sinceQueryState, filter, sort,
    maxChanges, upToId, calculateTotal,
  )
```

No extension args — RFC 8621 §2.4 specifies `Mailbox/queryChanges`
as a standard `/queryChanges` method with no additional request
arguments. The tree parameters apply only to `Mailbox/query` (§2.3).

### 6.6. addMailboxSet

```nim
func addMailboxSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, MailboxCreate]] =
      Opt.none(Table[CreationId, MailboxCreate]),
    update: Opt[NonEmptyMailboxUpdates] =
      Opt.none(NonEmptyMailboxUpdates),
    destroy: Opt[Referencable[seq[Id]]] =
      Opt.none(Referencable[seq[Id]]),
    onDestroyRemoveEmails: bool = false,
): (RequestBuilder, ResponseHandle[SetResponse[MailboxCreatedItem]]) =
  addSet[
    Mailbox, MailboxCreate, NonEmptyMailboxUpdates,
    SetResponse[MailboxCreatedItem]
  ](
    b, accountId, ifInState, create, update, destroy,
    extras = @[("onDestroyRemoveEmails", %onDestroyRemoveEmails)],
  )
```

Thin wrapper over the four-parameter generic `addSet[T, C, U, R]`
with the Mailbox-specific `onDestroyRemoveEmails` extension emitted
via `extras`. `create` arrives as `Table[CreationId, MailboxCreate]`
and `update` as `NonEmptyMailboxUpdates`; the generic
`SetRequest[T, C, U].toJson` serialises both through the `mixin
toJson` cascade.

The response handle carries `SetResponse[MailboxCreatedItem]`, not
`SetResponse[Mailbox]`, because RFC 8620 §5.3's `created[cid]`
carries only the server-set subset (id + counts + myRights), and
Stalwart further trims to `{"id": "..."}`. The partial type lets the
parser succeed without forcing a full-entity reconstruction.

`onDestroyRemoveEmails` (RFC 8621 §2.5): when `true`, emails solely
in a destroyed mailbox are also destroyed. When `false` (default),
the server returns a `mailboxHasEmail` `SetError` for non-empty
mailboxes. Boolean exception: the name is self-documenting, the
RFC models it as `Boolean`.

---

## 7. Test Specification

Numbered test scenarios for implementation plan reference. Unit
tests verify smart constructors and type invariants. Serde tests
verify round-trip and structural JSON correctness.

### 7.1. Keyword (scenarios 1–14)

| # | Scenario | Expected |
|---|----------|----------|
| 1 | `parseKeyword("$flagged")` | `ok`, value = `Keyword("$flagged")` |
| 2 | `parseKeyword("MyCustomFlag")` | `ok`, value = `Keyword("mycustomflag")` (lowercase) |
| 3 | `parseKeyword("")` | `err(ValidationError)` |
| 4 | `parseKeyword` with 256-byte string | `err(ValidationError)` |
| 5 | `parseKeyword` with space character | `err(ValidationError)` |
| 6 | `parseKeyword` with forbidden char `(` | `err(ValidationError)` |
| 7 | `parseKeyword` with forbidden char `\` | `err(ValidationError)` |
| 8 | `parseKeywordFromServer("$Flag(ed)")` — forbidden chars accepted | `ok`, lowercase normalised |
| 9 | `parseKeywordFromServer` with control char `\x01` | `err(ValidationError)` |
| 10 | `parseKeywordFromServer("")` | `err(ValidationError)` |
| 11 | System constants (`kwDraft`, `kwSeen`, etc.) are valid Keywords | pass |
| 12 | `Keyword` equality is case-normalised: same-input parses compare equal | pass |
| 13 | `Keyword` `hash` is consistent with `==` | pass |
| 14 | `Keyword` `len` returns underlying string length | pass |

### 7.2. KeywordSet (scenarios 15–22)

| # | Scenario | Expected |
|---|----------|----------|
| 15 | `initKeywordSet(@[kwSeen, kwFlagged])` | `len == 2`, contains both |
| 16 | `initKeywordSet(@[])` — empty set | `len == 0` |
| 17 | `initKeywordSet` with duplicate keywords | `len` = deduplicated count |
| 18 | `toJson` with keywords | `{"$seen": true, "$flagged": true}` |
| 19 | `toJson` empty set | `{}` |
| 20 | `fromJson` valid `{"$seen": true}` | `ok`, `len == 1` |
| 21 | `fromJson` with `false` value `{"$seen": false}` | `err(SerdeViolation)` (`svkEnumNotRecognised`) |
| 22 | `fromJson`/`toJson` round-trip | identity |

### 7.3. MailboxRole (scenarios 23–32)

| # | Scenario | Expected |
|---|----------|----------|
| 23 | `parseMailboxRole("inbox")` | `ok`, `kind == mrInbox`, equals `roleInbox` |
| 24 | `parseMailboxRole("INBOX")` — uppercase normalised | `ok`, equals `roleInbox` |
| 25 | `parseMailboxRole("CustomRole")` — vendor extension | `ok`, `kind == mrOther`, `identifier == "customrole"` |
| 26 | `parseMailboxRole("")` | `err(ValidationError)` |
| 27 | `parseMailboxRole` with control char `\x01` | `err(ValidationError)` |
| 28 | Well-known constants equal their parsed equivalents | pass |
| 29 | `toJson(roleInbox)` | `"inbox"` |
| 30 | `toJson` of vendor `mrOther` emits captured `rawIdentifier` | pass |
| 31 | `fromJson` valid role string round-trips through `$` | pass |
| 32 | `==` and `hash` distinguish two distinct `mrOther` identifiers | pass |

### 7.4. MailboxIdSet (scenarios 33–38)

| # | Scenario | Expected |
|---|----------|----------|
| 33 | `initMailboxIdSet(@[id1, id2])` | `len == 2`, contains both |
| 34 | `initMailboxIdSet(@[])` — empty set | `len == 0` |
| 35 | `toJson` with ids | `{"id1": true, "id2": true}` |
| 36 | `fromJson` valid `{"id1": true}` | `ok`, `len == 1` |
| 37 | `fromJson` with `false` value | `err(SerdeViolation)` |
| 38 | `fromJson`/`toJson` round-trip | identity |

### 7.5. NonEmptyMailboxIdSet (scenarios 39–43)

| # | Scenario | Expected |
|---|----------|----------|
| 39 | `parseNonEmptyMailboxIdSet(@[id1, id2])` | `ok`, `len == 2` |
| 40 | `parseNonEmptyMailboxIdSet(@[])` | `err(ValidationError)` |
| 41 | `parseNonEmptyMailboxIdSet` with duplicates | `ok`, deduplicated |
| 42 | `toJson` with ids | `{"id1": true, "id2": true}` |
| 43 | `==` between equal sets is `true` | pass |

### 7.6. MailboxRights (scenarios 44–47)

| # | Scenario | Expected |
|---|----------|----------|
| 44 | `fromJson` all 9 fields present | `ok`, all fields populated |
| 45 | `fromJson` missing field | `err(SerdeViolation)` |
| 46 | `fromJson` non-bool field | `err(SerdeViolation)` |
| 47 | `toJson`/`fromJson` round-trip | identity |

### 7.7. Mailbox (scenarios 48–57)

| # | Scenario | Expected |
|---|----------|----------|
| 48 | `fromJson` all fields present | `ok`, all fields populated |
| 49 | `fromJson` `name` absent | `err(SerdeViolation)` |
| 50 | `fromJson` `name` empty `""` | `err(SerdeViolation)` (`nonEmptyStr`) |
| 51 | `fromJson` `parentId` null → `Opt.none` | pass |
| 52 | `fromJson` `parentId` present → `Opt.some(Id)` | pass |
| 53 | `fromJson` `role` null → `Opt.none(MailboxRole)` | pass |
| 54 | `fromJson` `role` present → `Opt.some(MailboxRole)`, lowercase normalised | pass |
| 55 | `fromJson` `role` present uppercase → normalised to lowercase | pass |
| 56 | `toJson`/`fromJson` round-trip | identity |
| 57 | `fromJson` missing required field (e.g. `isSubscribed`) | `err(SerdeViolation)` |

### 7.8. MailboxCreatedItem (scenarios 58–62)

| # | Scenario | Expected |
|---|----------|----------|
| 58 | `fromJson` `{"id": "x"}` (Stalwart trim) | `ok`, all five `Opt` fields = `Opt.none` |
| 59 | `fromJson` with all server-set fields | `ok`, all `Opt.some(...)` |
| 60 | `fromJson` missing `id` | `err(SerdeViolation)` |
| 61 | `toJson` of trim-only payload | `{"id": "x"}` |
| 62 | `toJson`/`fromJson` round-trip | identity |

### 7.9. MailboxCreate (scenarios 63–68)

| # | Scenario | Expected |
|---|----------|----------|
| 63 | `parseMailboxCreate("Archive")` defaults only | `ok`, all defaults |
| 64 | `parseMailboxCreate("Inbox", role = some(roleInbox))` | `ok` |
| 65 | `parseMailboxCreate("")` | `err(ValidationError)` |
| 66 | `toJson` always emits `name`, `parentId`, `isSubscribed` | structural match |
| 67 | `toJson` omits `role` when `Opt.none` (James 3.9 compatibility) | verified absent |
| 68 | `toJson` omits `sortOrder` when zero (James 3.9 compatibility) | verified absent |

### 7.10. MailboxUpdate / MailboxUpdateSet / NonEmptyMailboxUpdates (scenarios 69–78)

| # | Scenario | Expected |
|---|----------|----------|
| 69 | `setName("New")` | `MailboxUpdate(kind: muSetName, name: "New")` |
| 70 | `setRole(Opt.some(roleInbox)).toJson` | `("role", "inbox")` |
| 71 | `setRole(Opt.none(MailboxRole)).toJson` | `("role", null)` |
| 72 | `setParentId(Opt.none(Id)).toJson` | `("parentId", null)` |
| 73 | `initMailboxUpdateSet(@[])` | `err(seq[ValidationError])` (empty) |
| 74 | `initMailboxUpdateSet(@[setName("A"), setName("B")])` | `err(seq[ValidationError])` (duplicate kind) |
| 75 | `initMailboxUpdateSet(@[setName("A"), setRole(Opt.none)])` | `ok`, two-key patch |
| 76 | `parseNonEmptyMailboxUpdates(@[])` | `err(seq[ValidationError])` (empty) |
| 77 | `parseNonEmptyMailboxUpdates` with duplicate `Id` keys | `err(seq[ValidationError])` |
| 78 | `NonEmptyMailboxUpdates.toJson` | `{"<id>": {"name": "A", ...}}` |

### 7.11. MailboxFilterCondition (scenarios 79–85)

| # | Scenario | Expected |
|---|----------|----------|
| 79 | `toJson` all fields none → `{}` | pass |
| 80 | `toJson` `parentId = Opt.some(Opt.none)` → `{"parentId": null}` | pass |
| 81 | `toJson` `parentId = Opt.some(Opt.some(id))` → `{"parentId": "id"}` | pass |
| 82 | `toJson` `role = Opt.some(Opt.none)` → `{"role": null}` | pass |
| 83 | `toJson` `role = Opt.some(Opt.some(roleInbox))` → `{"role": "inbox"}` | pass |
| 84 | `toJson` `name = Opt.some("test")` → `{"name": "test"}` | pass |
| 85 | `toJson` mixed filter (parentId null + hasAnyRole true) | structural match |

### 7.12. MailboxChangesResponse (scenarios 86–90)

| # | Scenario | Expected |
|---|----------|----------|
| 86 | `fromJson` valid with `updatedProperties` present | `ok`, `updatedProperties = Opt.some(seq)` |
| 87 | `fromJson` valid with `updatedProperties` absent | `ok`, `updatedProperties = Opt.none` |
| 88 | `fromJson` valid with `updatedProperties` null | `ok`, `updatedProperties = Opt.none` |
| 89 | Forwarding accessors (`accountId`, `oldState`, `newState`, …) return base values | pass |
| 90 | `fromJson` missing required base field (e.g. `newState`) | `err(SerdeViolation)` |

### 7.13. Entity Registration and Builders (scenarios 91–101)

| # | Scenario | Expected |
|---|----------|----------|
| 91 | `registerJmapEntity(Mailbox)` compiles | pass |
| 92 | `registerQueryableEntity(Mailbox)` compiles | pass |
| 93 | `registerSettableEntity(Mailbox)` compiles | pass |
| 94 | `addMailboxChanges` produces invocation name `"Mailbox/changes"` | pass |
| 95 | `addMailboxQuery` produces invocation name `"Mailbox/query"` and includes `sortAsTree`/`filterAsTree` in args | pass |
| 96 | `addMailboxQueryChanges` produces invocation name `"Mailbox/queryChanges"` | pass |
| 97 | `addMailboxQueryChanges` does NOT include `sortAsTree`/`filterAsTree` | pass |
| 98 | `addMailboxSet` produces invocation name `"Mailbox/set"` and includes `onDestroyRemoveEmails` | pass |
| 99 | `addMailboxSet` with typed `MailboxCreate` serialises through `mixin toJson` | pass |
| 100 | `addMailboxSet` with `NonEmptyMailboxUpdates` produces correct `update` patch wire shape | pass |
| 101 | `addMailboxSet` response handle is typed `SetResponse[MailboxCreatedItem]` (not `SetResponse[Mailbox]`) | pass |
