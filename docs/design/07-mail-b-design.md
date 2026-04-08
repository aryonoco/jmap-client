# RFC 8621 JMAP Mail — Design B: Keyword, Mailbox

This document is the detailed specification for the Keyword shared sub-type
and the Mailbox entity — plus their supporting types. It covers all layers
(L1 types, L2 serde, L3 entity registration and builder functions) for each
type, cutting vertically through the architecture.

Builds on the cross-cutting architecture design (`05-mail-design.md`), the
existing RFC 8620 infrastructure (`00-architecture.md` through
`04-layer-4-design.md`), and Design A (`06-mail-a-design.md`). Decisions
from the cross-cutting doc are referenced by section number.

---

## Table of Contents

1. [Scope](#1-scope)
2. [Core Prerequisites](#2-core-prerequisites)
3. [Keyword — keyword.nim](#3-keyword--keywordnim)
4. [Mailbox — mailbox.nim](#4-mailbox--mailboxnim)
5. [MailboxFilterCondition — mail_filters.nim](#5-mailboxfiltercondition--mail_filtersnim)
6. [Entity Registration and Builders](#6-entity-registration-and-builders)
7. [Test Specification](#7-test-specification)
8. [Decision Traceability Matrix](#8-decision-traceability-matrix)

---

## 1. Scope

### 1.1. Entities Covered

| Entity  | RFC 8621 Section | Capability URI              | Complexity |
|---------|------------------|-----------------------------|------------|
| Mailbox | §2               | `urn:ietf:params:jmap:mail` | Moderate   |

### 1.2. Supporting Types Covered

| Type | Module | Rationale |
|------|--------|-----------|
| `Keyword`, `KeywordSet` | `keyword.nim` | Shared sub-type required by Email (keywords field) and EmailSubmission; used by filter conditions in future design docs |
| `MailboxRole` | `mailbox.nim` | Distinct type for IANA-registered mailbox roles |
| `MailboxIdSet` | `mailbox.nim` | Distinct `HashSet[Id]` for the `mailboxIds` map pattern; used by Email in future design docs |
| `MailboxRights` | `mailbox.nim` | ACL rights sub-type for Mailbox |
| `MailboxCreate` | `mailbox.nim` | Creation model for Mailbox/set |
| `MailboxFilterCondition` | `mail_filters.nim` | Query specification for Mailbox/query |
| `MailboxChangesResponse` | `mail_builders.nim` | Non-standard response type for Mailbox/changes |
| `QueryParams` | `framework.nim` (core) | Shared value object for query parameters (core prerequisite) |

### 1.3. Deferred

Email, SearchSnippet, EmailSubmission, and all their sub-types (HeaderValue,
EmailBodyPart, etc.) are deferred to Design C and Design D documents.

### 1.4. Relationship to Cross-Cutting Design

This document refines `05-mail-design.md` into implementation-ready
specifications. It also specifies two additive core extensions as
prerequisites (§2).

### 1.5. General Conventions Established

This document establishes four general conventions that apply to all future
design docs:

1. **Lenient fromJson convention** — All `fromJson` for distinct types use
   the lenient `*FromServer` parser variant. Strict parsers are for
   client-constructed values. (Already implicit in Design A; made explicit
   here.)

2. **Filter conditions are toJson-only** — Filter conditions are "query
   creation types" with unidirectional flow: client constructs, serialises,
   server consumes. No `fromJson`. Same directional pattern as creation
   types (e.g., `IdentityCreate`).

3. **Strict/lenient parser pairs are principled, not mechanical** — A single
   parser suffices when no meaningful gap exists between spec-specific and
   structural constraints. The pair exists only when there are additional
   spec-specific constraints to relax for server data.

4. **Entity-specific builders accept typed creation models** — Custom
   builder functions that exist for other reasons (extra parameters) should
   accept typed creation models when available, rather than raw `JsonNode`.
   Generic builders accept `JsonNode` because they must be entity-agnostic.

### 1.6. Module Summary

All modules live under `src/jmap_client/mail/` per cross-cutting doc §3.3,
except for two core prerequisite additions.

| Module | Layer | Contents |
|--------|-------|----------|
| `keyword.nim` | L1 | `Keyword`, `KeywordSet`, `parseKeyword`, `parseKeywordFromServer`, system constants |
| `mailbox.nim` | L1 | `MailboxRole`, `MailboxIdSet`, `MailboxRights`, `Mailbox`, `MailboxCreate` |
| `mail_filters.nim` | L1 | `MailboxFilterCondition` |
| `serde_keyword.nim` | L2 | `toJson`/`fromJson` for Keyword, KeywordSet |
| `serde_mailbox.nim` | L2 | `toJson`/`fromJson` for Mailbox, MailboxCreate, MailboxRights, MailboxRole, MailboxIdSet |
| `serde_mail_filters.nim` | L2 | `toJson` for MailboxFilterCondition |
| `mail_entities.nim` | L3 | Entity registration for Mailbox (extends existing module) |
| `mail_builders.nim` | L3 | `MailboxChangesResponse`, `addMailboxChanges`, `addMailboxQuery`, `addMailboxQueryChanges`, `addMailboxSet` |

**Core prerequisites** (additive extensions, not mail modules):

| Module | Layer | Addition |
|--------|-------|----------|
| `validation.nim` | Core | `defineHashSetDistinctOps` template |
| `framework.nim` | Core | `QueryParams` value object |

---

## 2. Core Prerequisites

This section specifies two additive core extensions required by this design.
Both are infrastructure — general-purpose templates and value objects that
happen to be first needed by mail types. Neither carries mail-domain
knowledge.

**Principles:** Open-Closed (core extended through addition, not
modification of existing types), DRY (shared infrastructure defined once).

### 2.1. defineHashSetDistinctOps — validation.nim

**Module:** `src/jmap_client/validation.nim`

A new borrow template alongside the existing `defineStringDistinctOps` and
`defineIntDistinctOps`. Borrows read-only operations for `distinct
HashSet[T]` types.

```nim
template defineHashSetDistinctOps*(T: typedesc, E: typedesc) =
  ## Borrows standard read-only operations for a ``distinct HashSet``
  ## type. T is the distinct type, E is the element type.
  func len*(s: T): int {.borrow.}
  func contains*(s: T, e: E): bool {.borrow.}
  func card*(s: T): int {.borrow.}
```

**Minimal read-only operations only.** No mutation ops (`incl`, `excl`),
no functional builders (`with`, `without`). These are read models —
constructed once via infallible constructors or serde, never modified.
Mutation is a domain mismatch: you never `incl` a keyword on a
server-received set; updates go through `/set` with `PatchObject`.

Each consuming module manually defines its own `initXxxSet` constructor
and `items` iterator — these are domain-specific (different element types,
different construction contexts) and do not belong in the generic template.
This follows the precedent of `defineStringDistinctOps`, which borrows
operations but does not generate constructors.

**Principles:**
- **DRY** — One template for all distinct `HashSet` types (KeywordSet,
  MailboxIdSet, and future types in contacts/calendars extensions).
- **Immutability by default** — No mutation operations exposed. The right
  thing (immutable read access) is easy; the wrong thing (mutation) is hard.

### 2.2. QueryParams — framework.nim

**Module:** `src/jmap_client/framework.nim`

A value object grouping the five standard query parameters defined by
RFC 8620 §5.5. These parameters appear identically on every `/query` and
`/queryChanges` method across all entities.

```nim
type QueryParams* = object
  position*: JmapInt             ## default 0
  anchor*: Opt[Id]               ## default: absent
  anchorOffset*: JmapInt         ## default 0
  limit*: Opt[UnsignedInt]       ## default: server-determined
  calculateTotal*: bool          ## default false
```

Plain public fields, no smart constructor — all field combinations are
valid per RFC. Default values match RFC 8620 §5.5.

**Core refactor:** The existing `addQuery[T, C]` and
`addQueryChanges[T, C]` in `builder.nim` currently accept these five
parameters individually. They should be refactored to accept `QueryParams`
instead. This is a mechanical signature change — existing callers are
updated by wrapping their individual arguments in `QueryParams(...)`.

**Principles:**
- **DRY** — Five parameters defined once, not duplicated across every
  query builder overload (Mailbox, Email, EmailSubmission).
- **DDD** — QueryParams is RFC 8620 protocol knowledge. Core owns it.
- **One source of truth** — The parameters are defined once, accepted
  once, and entity-specific builders compose on top.

---

## 3. Keyword — keyword.nim

**Module:** `src/jmap_client/mail/keyword.nim`

`Keyword` and `KeywordSet` are shared sub-types used by multiple entities.
They are specified here as a prerequisite section — a shared bounded
context, not subordinated to any single entity. `Keyword` is used by
Email (`keywords` field), EmailSubmission, filter conditions, and sort
properties.

**Principles:** DDD (keywords are their own bounded context), DRY (one
specification, referenced by multiple future consumers), Parse-don't-validate
(full parsing boundary defined now).

### 3.1. Keyword Type Definition

**RFC reference:** §4.1.1 (keywords property).

A keyword is an IMAP flag atom — a case-insensitive ASCII string with
specific character restrictions. The `Keyword` distinct type enforces
validity at construction time and normalises to lowercase as the canonical
form.

```nim
type Keyword* = distinct string
```

Borrowed operations via `defineStringDistinctOps(Keyword)`: `==`, `$`,
`hash`, `len`.

**Principles:**
- **Newtype everything that has meaning** — A keyword is not an arbitrary
  string. The distinct type prevents accidentally using a random string
  where a keyword is expected.
- **Parse, don't validate** — The smart constructor transforms input into
  canonical form (lowercase), not just checks it.

### 3.2. Smart Constructors

**parseKeyword (strict):**

```nim
func parseKeyword*(raw: string): Result[Keyword, ValidationError]
```

Validates:
- Length: 1–255 bytes
- Character range: ASCII `%x21`–`%x7E` (printable, no space)
- Rejects forbidden characters: `( ) { ] % * " \`
- **Normalises to lowercase** during construction

Post-construction `doAssert` verifies `len >= 1` and `len <= 255` (same
pattern as `parseId` in `primitives.nim`).

**parseKeywordFromServer (lenient):**

```nim
func parseKeywordFromServer*(raw: string): Result[Keyword, ValidationError]
```

Validates:
- Length: 1–255 bytes
- No control characters (same `validateServerAssignedToken` pattern as
  `parseIdFromServer`)
- **Normalises to lowercase** during construction

The strict/lenient gap is exactly the IMAP-specific forbidden character
set. Structural constraints (non-empty, bounded length, no control
characters, lowercase normalisation) are shared. This follows the
established `parseId`/`parseIdFromServer` pattern — strict enforces the
spec charset, lenient enforces only the structural minimum.

**Principles:**
- **Parse, don't validate** — Both constructors transform input into
  canonical lowercase form. After construction, `Keyword` is always
  lowercase, always valid.
- **Total functions** — Both map every input to `ok(Keyword)` or
  `err(ValidationError)`.
- **Postel's law** — Strict for client-constructed keywords, lenient for
  server data. Accept the widest reasonable input from servers.
- **DRY** — The leniency boundary is defined by the same principle across
  all server-facing parsers (B15 convention), not ad-hoc per type.

### 3.3. Forbidden Characters Constant

```nim
const KeywordForbiddenChars*: set[char] = {'(', ')', '{', ']', '%', '*', '"', '\\'}
```

Defined once, used by `parseKeyword`. Same pattern as `Base64UrlChars` in
`primitives.nim`.

**Principle:** DRY — single source of truth for the forbidden character set.

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

Module-level `const` construction is the one permitted bypass of the smart
constructor, justified by compile-time provability — these are literals that
are provably valid and already lowercase.

**Principles:**
- **DRY** — Define once, use everywhere.
- **Make illegal states unrepresentable** — Pre-validated at compile time.
  The common case is ergonomic.

### 3.5. KeywordSet

**RFC reference:** §4.1.1.

`KeywordSet` is a distinct `HashSet[Keyword]` — not `Table[Keyword, bool]`.

The RFC mandates that all values in the `keywords` map MUST be `true`. The
`bool` carries no information. A `HashSet[Keyword]` makes the "value is
always true" invariant unrepresentable rather than validated. The serde
layer parses `{"$seen": true, "$flagged": true}` into `KeywordSet`,
rejecting any entry with `false`.

```nim
type KeywordSet* = distinct HashSet[Keyword]
```

Borrowed operations via `defineHashSetDistinctOps(KeywordSet, Keyword)`:
`len`, `contains`, `card`.

**Constructor:**

```nim
func initKeywordSet*(keywords: openArray[Keyword]): KeywordSet
```

Infallible — construction cannot fail because:
- Every `Keyword` in the input is already validated (the type guarantees it)
- An empty set is valid (an email with no keywords is a normal domain state;
  the RFC default for `keywords` is `{}`)

The non-empty invariant, when needed, belongs to the consumer (e.g.,
`EmailBlueprint` may require at least one mailbox, not at least one
keyword), not to the collection type itself.

**Principle:** Constructors that can't fail, don't.

**Items iterator:**

```nim
iterator items*(ks: KeywordSet): Keyword
```

Enables `for kw in keywordSet:` syntax.

**Principles:**
- **Make illegal states unrepresentable** — Eliminates an entire class of
  invalid state (a keyword mapped to `false`) at the type level.
- **DDD** — The domain model doesn't mirror the wire format. The serde
  layer handles the `Table[Keyword, bool]` JSON representation.
- **Immutability by default** — `KeywordSet` is an immutable value type.
  No mutation operations exposed.

### 3.6. Serde — serde_keyword.nim

**Module:** `src/jmap_client/mail/serde_keyword.nim`

Follows established core serde patterns (`checkJsonKind`, `parseError`).

**Keyword serialisation:**

`toJson`:
- Emits the underlying string value: `%($kw)`.
- Uses `defineDistinctStringToJson(Keyword)` template.

`fromJson`:
- Validates JString.
- Delegates to `parseKeywordFromServer` for construction (lenient — per
  B15 convention: all `fromJson` for distinct types use the lenient
  `*FromServer` parser variant).
- Uses `defineDistinctStringFromJson(Keyword, parseKeywordFromServer)`
  template.
- Returns `Result[Keyword, ValidationError]`.

**KeywordSet serialisation:**

Wire format:

```json
{"$seen": true, "$flagged": true}
{}
```

`toJson`:
- Iterates `KeywordSet` via `items`, emits each keyword as a key with
  `true` as value.
- Empty set emits `{}`.

```nim
func toJson*(ks: KeywordSet): JsonNode =
  var node = newJObject()
  for kw in ks:
    node[$kw] = newJBool(true)
  return node
```

`fromJson`:
- Validates JObject.
- Iterates key-value pairs. For each:
  - Validates value is JBool with value `true`. Rejects `false` with
    `err(validationError("KeywordSet", "all keyword values must be true",
    key))`.
  - Parses key via `parseKeywordFromServer` (lenient). Short-circuits on
    first element error via `?`.
- Constructs `KeywordSet` directly from the accumulated `HashSet[Keyword]`.
- Returns `Result[KeywordSet, ValidationError]`.

---

## 4. Mailbox — mailbox.nim

**RFC reference:** §2.

A Mailbox represents a named, stretchable mailbox that contains Emails.
Mailboxes form a tree (via `parentId`), have access rights, and support
rich query/filter operations including tree-aware sorting.

**Module:** `src/jmap_client/mail/mailbox.nim`

This section covers all sub-types and both models (read and create) as a
single vertical slice of the Mailbox bounded context. Sub-types
(`MailboxRole`, `MailboxIdSet`, `MailboxRights`) are nested here because
they belong to the Mailbox domain, unlike `Keyword` which is shared across
entities.

### 4.1. MailboxRole

**RFC reference:** §2 (role property), IANA "IMAP Mailbox Name Attributes"
registry.

A mailbox role is a lowercase string from the IANA registry. The registry
is open-ended (servers may define custom roles), but has been stable since
2019 (10 registered values, no additions in 7 years). A distinct type
provides type safety; compile-time constants provide ergonomics for the
well-known set.

**Type definition:**

```nim
type MailboxRole* = distinct string
```

Borrowed operations via `defineStringDistinctOps(MailboxRole)`: `==`, `$`,
`hash`, `len`.

**Smart constructor:**

```nim
func parseMailboxRole*(raw: string): Result[MailboxRole, ValidationError]
```

Validates: `raw` non-empty. Normalises to lowercase during construction
(`raw.toLowerAscii()`). Post-construction `doAssert` verifies `len > 0`.

**Single parser, no strict/lenient pair.** `MailboxRole`'s only constraints
beyond non-empty are lowercase normalisation. Unlike `Keyword` (which has
IMAP-specific forbidden chars to relax), there is no meaningful gap between
spec-specific and structural constraints. A single parser that validates
non-empty and normalises to lowercase serves both client construction and
server data parsing. This is not an exception to the B15 convention — it
is the principled application: the strict/lenient pair exists only when
there are additional spec-specific constraints to enforce on
client-constructed values (B20).

**Well-known role constants:**

```nim
const
  roleInbox*         = MailboxRole("inbox")
  roleDrafts*        = MailboxRole("drafts")
  roleSent*          = MailboxRole("sent")
  roleTrash*         = MailboxRole("trash")
  roleJunk*          = MailboxRole("junk")
  roleArchive*       = MailboxRole("archive")
  roleImportant*     = MailboxRole("important")
  roleAll*           = MailboxRole("all")
  roleFlagged*       = MailboxRole("flagged")
  roleSubscriptions* = MailboxRole("subscriptions")
```

Same pattern as `kwDraft`/`kwSeen` keyword constants — known-valid literals
as named constants, while the type stays open for server-specific values.

**Principles:**
- **Newtype everything that has meaning** — A mailbox role is not an
  arbitrary string. The distinct type prevents mixing roles with other
  strings.
- **Parse, don't validate** — `parseMailboxRole` normalises to lowercase
  canonical form. After construction, all downstream code can compare
  against constants without case concerns.
- **DRY** — Constants defined once, used everywhere. Prevents typos.
- **Total functions** — Maps every input to `ok(MailboxRole)` or
  `err(ValidationError)`.

### 4.2. MailboxIdSet

**RFC reference:** §4.1.1 (mailboxIds property on Email).

`MailboxIdSet` is a distinct `HashSet[Id]` — not `Table[Id, bool]`. Same
design rationale as `KeywordSet` (§3.5): the RFC mandates all values are
`true`, so the `bool` carries no information. The serde layer parses
`{"mbx1": true, "mbx2": true}` into `MailboxIdSet`, rejecting any entry
with `false`.

```nim
type MailboxIdSet* = distinct HashSet[Id]
```

Borrowed operations via `defineHashSetDistinctOps(MailboxIdSet, Id)`:
`len`, `contains`, `card`.

**Constructor:**

```nim
func initMailboxIdSet*(ids: openArray[Id]): MailboxIdSet
```

Infallible — same reasoning as `initKeywordSet`. An empty set is valid for
the collection type itself. The "at least one mailbox" invariant on
`EmailBlueprint` is enforced by `EmailBlueprint`'s smart constructor, not
by `MailboxIdSet`.

**Items iterator:**

```nim
iterator items*(ms: MailboxIdSet): Id
```

**Principles:**
- **Make illegal states unrepresentable** — Eliminates `false` values at
  the type level.
- **DDD** — `MailboxIdSet` lives in `mailbox.nim` (its domain), not in
  `keyword.nim`. The shared `defineHashSetDistinctOps` template lives in
  `validation.nim` (infrastructure).

### 4.3. MailboxRights

**RFC reference:** §2.4.

`MailboxRights` represents the current user's permissions on a mailbox.
Nine boolean fields, each describing a specific capability.

**Type definition:**

```nim
type MailboxRights* = object
  mayReadItems*: bool      ## Can the user read emails in this mailbox?
  mayAddItems*: bool       ## Can the user add emails to this mailbox?
  mayRemoveItems*: bool    ## Can the user remove emails from this mailbox?
  maySetSeen*: bool        ## Can the user modify the $seen keyword?
  maySetKeywords*: bool    ## Can the user modify keywords (other than $seen)?
  mayCreateChild*: bool    ## Can the user create child mailboxes?
  mayRename*: bool         ## Can the user rename or move this mailbox?
  mayDelete*: bool         ## Can the user delete this mailbox?
  maySubmit*: bool         ## Can the user submit emails from this mailbox?
```

Plain public fields, no smart constructor. All boolean combinations are
valid — there are no cross-field invariants. Every combination of nine
booleans has a meaningful domain interpretation (a user with different
permission levels).

**Boolean exception (documented):** The "booleans are a code smell"
principle targets cases where `bool` hides what the two states mean
(e.g., `isActive` where `false` could mean disabled, deleted, or pending).
`MailboxRights` is an exception because the `may*` naming is
self-documenting — `mayDelete: true` means "may delete", `mayDelete:
false` means "may not delete". The RFC also literally models these as
`Boolean`. Code reads like the spec.

**Read-only.** `MailboxRights` is server-set and immutable — it represents
the current user's rights, not a rights assignment. It is excluded from
`MailboxCreate` (§4.5).

**Principles:**
- **Constructors that can't fail, don't** — Infallible construction.
- **Code reads like the spec** — Nine RFC-defined boolean properties,
  named identically.
- **DDD** — ACL rights are a Mailbox domain concept.

### 4.4. Mailbox Type Definition

**Plain public fields** — no Pattern A. All field-level invariants are
captured by the types themselves (`Id`, `Opt[MailboxRole]`, `UnsignedInt`,
`MailboxRights`, `bool`). No cross-field invariants. Consistent with
`Identity` and `Account` in core.

The typed `Mailbox` represents a **complete** RFC domain object — all
properties present. Partial property responses (when the client requests
only specific properties via `addGet`) use `GetResponse[Mailbox].list:
seq[JsonNode]` for raw access. No `Opt` wrapping for "was this property
requested?".

```nim
type Mailbox* = object
  id*: Id
  name*: string                    ## non-empty (fromJson enforced)
  parentId*: Opt[Id]               ## null = root-level mailbox
  role*: Opt[MailboxRole]          ## null = no assigned role
  sortOrder*: UnsignedInt          ## default 0; lower = more prominent
  totalEmails*: UnsignedInt        ## count of emails in this mailbox
  unreadEmails*: UnsignedInt       ## count of unread emails
  totalThreads*: UnsignedInt       ## count of threads with emails in this mailbox
  unreadThreads*: UnsignedInt      ## count of threads with unread emails
  myRights*: MailboxRights         ## current user's permissions
  isSubscribed*: bool              ## whether user has subscribed to this mailbox
```

**String field uses `string`, not `Opt[string]`** for `name` — the RFC
specifies `name` as `String` (never null) and it is required on every
Mailbox. `fromJson` rejects absent or empty `name` at the parsing boundary
(same pattern as Identity rejecting empty `email` in Design A, Decision
A18).

**`parentId: Opt[Id]`** — null means this is a root-level (top-level)
mailbox. This is domain-level optionality (the RFC says `parentId` can be
null), not "was this property requested?" optionality.

**`role: Opt[MailboxRole]`** — null means no role assigned. Uses the
distinct `MailboxRole` type (§4.1). Domain-level optionality.

No smart constructor for the read model — `fromJson` extracts fields,
validates JSON structure, and constructs directly.

**Principles:**
- **Code reads like the spec** — Every RFC §2 property is a field.
- **Parse, don't validate** — Non-empty `name` enforced at the parsing
  boundary. After construction, all downstream code trusts the invariant.
- **One source of truth per fact** — Each field has one meaning (its
  domain meaning). No overloaded "absent" semantics.

### 4.5. MailboxCreate (Creation Model)

The Mailbox read model and creation model have different valid field sets:
creates require `name` and exclude server-set fields (`id`, `totalEmails`,
`unreadEmails`, `totalThreads`, `unreadThreads`, `myRights`). A distinct
type makes "create without name" unrepresentable.

```nim
type MailboxCreate* = object
  name*: string                    ## required, non-empty
  parentId*: Opt[Id]               ## default: null (top-level)
  role*: Opt[MailboxRole]          ## default: null (no role)
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

Validates: `name` non-empty. Post-construction `doAssert` verifies
`name.len > 0` (same pattern as `parseIdentityCreate` in Design A §4.2).
Default parameter values match RFC-specified defaults for ergonomic
construction:

```nim
let mc = ?parseMailboxCreate(name = "Archive")          # all defaults
let mc2 = ?parseMailboxCreate(name = "Inbox",
    role = Opt.some(roleInbox))                          # with role
```

**`role: Opt[MailboxRole]`** — the RFC allows setting role on create. The
server may reject certain role assignments via `SetError` (e.g., a server
that reserves `inbox` role). Server rejection is handled at the protocol
level, not the type level — the creation type allows the client to try.

No `MailboxCreate.fromJson` — creation types are constructed by the
consumer, not parsed from server responses (same as `IdentityCreate`).

**Principles:**
- **Make illegal states unrepresentable** — `name` is required by
  construction. Server-set fields (`id`, counts, `myRights`) don't exist
  on this type.
- **DDD** — Create and read are different domain operations with different
  valid shapes (same rationale as `IdentityCreate` in Design A §4.2).
- **Total functions** — `parseMailboxCreate()` →
  `Result[MailboxCreate, ValidationError]`.
- **Railway-Oriented Programming** — Construction railway via `Result`.

### 4.6. Serde — serde_mailbox.nim

**Module:** `src/jmap_client/mail/serde_mailbox.nim`

Imports `serde_keyword.nim` for `KeywordSet` serde (used by
`MailboxIdSet`'s parallel pattern). Follows established core serde patterns.

#### MailboxRole serialisation

`toJson`:
- Emits the underlying string value: `%($role)`.
- Uses `defineDistinctStringToJson(MailboxRole)` template.

`fromJson`:
- Validates JString.
- Delegates to `parseMailboxRole` for construction (single parser — per
  B20, no strict/lenient pair needed).
- Uses `defineDistinctStringFromJson(MailboxRole, parseMailboxRole)`
  template.
- Returns `Result[MailboxRole, ValidationError]`.

#### MailboxIdSet serialisation

Wire format:

```json
{"mbx123": true, "mbx456": true}
```

`toJson`:
- Iterates `MailboxIdSet` via `items`, emits each `Id` as a key with
  `true` as value. Same structure as `KeywordSet.toJson`.

`fromJson`:
- Validates JObject.
- Iterates key-value pairs. Validates each value is `JBool(true)`.
- Parses each key via `parseIdFromServer` (lenient, per B15 convention).
- Short-circuits on first element error via `?`.
- Returns `Result[MailboxIdSet, ValidationError]`.

#### MailboxRights serialisation

Wire format:

```json
{
  "mayReadItems": true,
  "mayAddItems": true,
  "mayRemoveItems": false,
  "maySetSeen": true,
  "maySetKeywords": true,
  "mayCreateChild": false,
  "mayRename": false,
  "mayDelete": false,
  "maySubmit": true
}
```

`fromJson`:
- Validates JObject.
- Extracts all 9 fields as bool (required). Absent or non-bool →
  `err(ValidationError)`.
- Constructs `MailboxRights` directly.
- Returns `Result[MailboxRights, ValidationError]`.

`toJson`:
- Emits all 9 fields as bools. Always emits all fields (explicit is safer
  than relying on defaults).

#### Mailbox serialisation

Wire format (example):

```json
{
  "id": "mbx123",
  "name": "Inbox",
  "parentId": null,
  "role": "inbox",
  "sortOrder": 10,
  "totalEmails": 1432,
  "unreadEmails": 5,
  "totalThreads": 820,
  "unreadThreads": 3,
  "myRights": { "mayReadItems": true, ... },
  "isSubscribed": true
}
```

**Mailbox.fromJson:**
- Validates JObject.
- Extracts `id` via `Id.fromJson` (required).
- Extracts `name` as string (required, rejects absent/null/non-string/empty).
- Extracts `parentId` — absent or null → `Opt.none(Id)`, present string →
  parse via `Id.fromJson`.
- Extracts `role` — absent or null → `Opt.none(MailboxRole)`, present
  string → parse via `MailboxRole.fromJson`.
- Extracts `sortOrder`, `totalEmails`, `unreadEmails`, `totalThreads`,
  `unreadThreads` via `UnsignedInt.fromJson` (all required).
- Extracts `myRights` via `MailboxRights.fromJson` (required).
- Extracts `isSubscribed` as bool (required).
- Constructs `Mailbox` directly (no smart constructor).
- Returns `Result[Mailbox, ValidationError]`.

**Mailbox.toJson:**
- Emits all fields. `parentId`/`role` emit as `null` or value.
  All other fields always present.

#### MailboxCreate serialisation

**MailboxCreate.toJson:**
- Emits all fields including defaults. No `id`, `totalEmails`,
  `unreadEmails`, `totalThreads`, `unreadThreads`, or `myRights` fields.
- `parentId`/`role` emit as `null` or value.
- All fields always present — explicit is safer than relying on server
  defaults.

```json
{
  "name": "Archive",
  "parentId": null,
  "role": null,
  "sortOrder": 0,
  "isSubscribed": false
}
```

No `MailboxCreate.fromJson` — creation types are constructed by the
consumer, not parsed from server responses.

---

## 5. MailboxFilterCondition — mail_filters.nim

**Module:** `src/jmap_client/mail/mail_filters.nim`

**RFC reference:** §2.3.

`MailboxFilterCondition` is a query specification — a value object that
describes filter criteria for `Mailbox/query`. It is not a domain entity;
it has no identity, no smart constructor (beyond what types enforce), and
is equal by structure.

### 5.1. Type Definition

```nim
type MailboxFilterCondition* = object
  parentId*: Opt[Opt[Id]]            ## three-state: absent / null / value
  name*: Opt[string]                 ## contains match
  role*: Opt[Opt[MailboxRole]]       ## three-state: absent / null / value
  hasAnyRole*: Opt[bool]
  isSubscribed*: Opt[bool]
```

**The `Opt[Opt[T]]` pattern:** RFC 8621 distinguishes between "this filter
property is not specified" (omit from JSON) and "this filter property
matches null" (include as `null` in JSON). For `parentId` and `role`,
`null` is a meaningful filter value (top-level mailboxes, no-role
mailboxes):

- `Opt.none` = not filtering on this property (omit from JSON)
- `Opt.some(Opt.none)` = filtering for null (emit `null`)
- `Opt.some(Opt.some(value))` = filtering for specific value

The double-wrapping looks unusual but encodes a real three-state domain.

**`role` uses `Opt[Opt[MailboxRole]]`** — a consequence of Decision B8.
Once `MailboxRole` is a distinct type, it propagates to every place that
references roles. One type for the concept everywhere.

**Principles:**
- **Make illegal states unrepresentable** — `Opt[Opt[T]]` encodes the
  three-state domain explicitly. No sentinel values, no stringly-typed
  dispatch.
- **DDD** — Value object, not entity. Construction is infallible (all
  fields are `Opt`).
- **Newtype everything that has meaning** — `role` uses `MailboxRole`,
  not `string`.

### 5.2. Serde (toJson only)

**toJson only — no fromJson.** Filter conditions are "query creation
types" with unidirectional flow: client constructs, serialises to JSON,
server consumes. The server never sends filter conditions back. Same
directional pattern as `IdentityCreate` and `MailboxCreate` (B11
convention).

**Opt[Opt[T]] three-way dispatch:**

```nim
func toJson*(fc: MailboxFilterCondition): JsonNode =
  var node = newJObject()
  # parentId: three-way dispatch
  for outer in fc.parentId:           # Opt.none → skip (omit key)
    if outer.isNone:
      node["parentId"] = newJNull()   # Opt.some(Opt.none) → null
    else:
      for inner in outer:
        node["parentId"] = inner.toJson()  # Opt.some(Opt.some(v)) → value
  # role: same three-way dispatch with MailboxRole
  for outer in fc.role:
    if outer.isNone:
      node["role"] = newJNull()
    else:
      for inner in outer:
        node["role"] = %($inner)
  # Simple Opt fields
  for v in fc.name:
    node["name"] = %v
  for v in fc.hasAnyRole:
    node["hasAnyRole"] = %v
  for v in fc.isSubscribed:
    node["isSubscribed"] = %v
  return node
```

**Principles:**
- **Total functions** — Every `MailboxFilterCondition` maps to a valid
  JSON object. All-none fields produce `{}` (match everything).
- **Parse, don't validate** — The three-way dispatch is deterministic:
  the type guarantees which branch to take.

---

## 6. Entity Registration and Builders

### 6.1. Entity Registration

**Module:** `src/jmap_client/mail/mail_entities.nim` (extends existing
module from Design A).

```nim
func methodNamespace*(T: typedesc[Mailbox]): string = "Mailbox"
func capabilityUri*(T: typedesc[Mailbox]): string = "urn:ietf:params:jmap:mail"
registerJmapEntity(Mailbox)
registerQueryableEntity(Mailbox)
```

Mailbox is registered with **both** `registerJmapEntity` (provides
`methodNamespace`, `capabilityUri`, enables result references) and
`registerQueryableEntity` (provides `filterType`, enables `addQuery`
dispatch).

**Registration is infrastructure, not API surface.** The generic builder
instantiations (`addGet[Mailbox]`, `addChanges[Mailbox]`, `addSet[Mailbox]`,
`addQuery[Mailbox]`) all compile, but consumers should use the custom
overloads for methods with extra parameters. The mail re-export hub
exports:

- `addGet[Mailbox]` — generic, no extensions needed (re-exported as-is)
- `addMailboxChanges` — custom (extra `updatedProperties` in response)
- `addMailboxQuery` — custom (extra `sortAsTree`, `filterAsTree`)
- `addMailboxQueryChanges` — custom (extra `sortAsTree`, `filterAsTree`)
- `addMailboxSet` — custom (extra `onDestroyRemoveEmails`, typed create)

**Principles:**
- **DDD** — Registration says "Mailbox is a JMAP entity." Custom builders
  say "here's how you interact with it."
- **Make the right thing easy** — The standard import path gives you only
  the custom builders.
- **DRY** — Infrastructure (methodNamespace, capabilityUri, result
  references) is written once via registration, not duplicated in custom
  builders.

### 6.2. MailboxChangesResponse

**Module:** `src/jmap_client/mail/mail_builders.nim`

RFC 8621 §2.2 extends the standard `/changes` response with an extra
`updatedProperties` field. A custom response type models this via
composition with the standard `ChangesResponse[Mailbox]`.

```nim
type MailboxChangesResponse* = object
  base*: ChangesResponse[Mailbox]
  updatedProperties*: Opt[seq[string]]
```

**Forwarding template:**

```nim
template forwardChangesFields(T: typedesc) =
  func accountId*(r: T): AccountId = r.base.accountId
  func oldState*(r: T): JmapState = r.base.oldState
  func newState*(r: T): JmapState = r.base.newState
  func hasMoreChanges*(r: T): bool = r.base.hasMoreChanges
  func created*(r: T): seq[Id] = r.base.created
  func updated*(r: T): seq[Id] = r.base.updated
  func destroyed*(r: T): seq[Id] = r.base.destroyed

forwardChangesFields(MailboxChangesResponse)
```

UFCS forwarding funcs for all base fields. Consumer writes
`resp.accountId`, `resp.created` — same API as if it were a flat type.

**fromJson:**
- Parses the standard changes fields via `ChangesResponse[Mailbox].fromJson`
  for the base.
- Extracts `updatedProperties` — absent or null → `Opt.none`,
  present JArray → `Opt.some(seq[string])` with each element validated
  as JString.
- Returns `Result[MailboxChangesResponse, ValidationError]`.

**Principles:**
- **DRY** — One source of truth for the base fields (in
  `ChangesResponse[T]`), one template for forwarding.
- **Code reads like the spec** — "standard /changes + extra field" =
  composition.
- **Open-Closed** — Core's `ChangesResponse[T]` is unchanged. Mail
  extends through composition.

### 6.3. addMailboxChanges

```nim
func addMailboxChanges*(b: var RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): ResponseHandle[MailboxChangesResponse]
```

- Adds `"urn:ietf:params:jmap:mail"` capability to the request.
- Creates invocation with name `"Mailbox/changes"`.
- Returns `ResponseHandle[MailboxChangesResponse]` (not
  `ResponseHandle[ChangesResponse[Mailbox]]` — the phantom type ensures
  the caller uses the correct response type with `updatedProperties`).

### 6.4. addMailboxQuery

```nim
proc addMailboxQuery*(b: var RequestBuilder,
    accountId: AccountId,
    filterConditionToJson: proc(c: MailboxFilterCondition): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[MailboxFilterCondition]] = Opt.none(Filter[MailboxFilterCondition]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    queryParams: QueryParams = QueryParams(),
    sortAsTree: bool = false,
    filterAsTree: bool = false,
): ResponseHandle[QueryResponse[Mailbox]]
```

- Adds `"urn:ietf:params:jmap:mail"` capability.
- Creates invocation with name `"Mailbox/query"`.
- Serialises `sortAsTree` and `filterAsTree` into the invocation
  arguments alongside standard query parameters.
- `proc` not `func` due to callback parameter — inherited constraint from
  core's `addQuery`.

**`sortAsTree` and `filterAsTree`** are inline boolean parameters (not
wrapped in a value object). Two booleans across two functions do not
justify a type. The `*AsTree` naming is self-documenting, and the RFC
models these as `Boolean`. This is a documented boolean exception (same
reasoning as `MailboxRights` §4.3).

### 6.5. addMailboxQueryChanges

```nim
proc addMailboxQueryChanges*(b: var RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filterConditionToJson: proc(c: MailboxFilterCondition): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[MailboxFilterCondition]] = Opt.none(Filter[MailboxFilterCondition]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
    sortAsTree: bool = false,
    filterAsTree: bool = false,
): ResponseHandle[QueryChangesResponse[Mailbox]]
```

- Adds `"urn:ietf:params:jmap:mail"` capability.
- Creates invocation with name `"Mailbox/queryChanges"`.
- Includes `sortAsTree` and `filterAsTree` — per RFC 8621 §2.6, which
  extends Mailbox/queryChanges with these parameters.

**Architecture doc discrepancy:** The cross-cutting architecture doc §13.1
states "standard params only" for Mailbox/queryChanges. This contradicts
RFC 8621 §2.6 which explicitly extends `/queryChanges` with the same tree
parameters. The RFC is the upstream authority; this design follows the RFC.

### 6.6. addMailboxSet

```nim
func addMailboxSet*(b: var RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, MailboxCreate]] = Opt.none(Table[CreationId, MailboxCreate]),
    update: Opt[Table[Id, PatchObject]] = Opt.none(Table[Id, PatchObject]),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    onDestroyRemoveEmails: bool = false,
): ResponseHandle[SetResponse[Mailbox]]
```

- Adds `"urn:ietf:params:jmap:mail"` capability.
- Creates invocation with name `"Mailbox/set"`.
- Serialises `onDestroyRemoveEmails` into the invocation arguments.
- **Accepts `Table[CreationId, MailboxCreate]`** — typed, not `JsonNode`.
  The builder calls `toJson` on each `MailboxCreate` internally. This is
  the general principle (B21): entity-specific builders that exist for
  other reasons should accept typed creation models when available.
- `func` not `proc` — no callback parameter.

**`onDestroyRemoveEmails`** (RFC 8621 §2.5): when `true`, emails solely
in a destroyed mailbox are also destroyed. When `false` (default), the
server returns a `mailboxHasEmail` `SetError` for non-empty mailboxes.

**Principles:**
- **Make illegal states unrepresentable** — Typed `MailboxCreate` prevents
  malformed creation JSON and accidental inclusion of server-set fields.
- **DDD** — `onDestroyRemoveEmails` is mailbox-domain knowledge that
  the generic builder cannot express.

---

## 7. Test Specification

Numbered test scenarios for implementation plan reference. Unit tests
verify smart constructors and type invariants. Serde tests verify
round-trip and structural JSON correctness.

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
| 12 | `Keyword` equality is case-normalised: both constructed from same input compare equal | pass |
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
| 21 | `fromJson` with `false` value `{"$seen": false}` | `err(ValidationError)` |
| 22 | `fromJson`/`toJson` round-trip | identity |

### 7.3. MailboxRole (scenarios 23–29)

| # | Scenario | Expected |
|---|----------|----------|
| 23 | `parseMailboxRole("inbox")` | `ok`, value = `roleInbox` |
| 24 | `parseMailboxRole("INBOX")` — uppercase normalised | `ok`, value = `roleInbox` |
| 25 | `parseMailboxRole("CustomRole")` — custom role | `ok`, lowercase |
| 26 | `parseMailboxRole("")` | `err(ValidationError)` |
| 27 | Well-known constants equal their parsed equivalents | pass |
| 28 | `toJson(roleInbox)` | `"inbox"` |
| 29 | `fromJson` valid role string | `ok` |

### 7.4. MailboxIdSet (scenarios 30–35)

| # | Scenario | Expected |
|---|----------|----------|
| 30 | `initMailboxIdSet(@[id1, id2])` | `len == 2`, contains both |
| 31 | `initMailboxIdSet(@[])` — empty set | `len == 0` |
| 32 | `toJson` with ids | `{"id1": true, "id2": true}` |
| 33 | `fromJson` valid `{"id1": true}` | `ok`, `len == 1` |
| 34 | `fromJson` with `false` value | `err(ValidationError)` |
| 35 | `fromJson`/`toJson` round-trip | identity |

### 7.5. MailboxRights (scenarios 36–39)

| # | Scenario | Expected |
|---|----------|----------|
| 36 | `fromJson` all 9 fields present | `ok`, all fields populated |
| 37 | `fromJson` missing field | `err(ValidationError)` |
| 38 | `fromJson` non-bool field | `err(ValidationError)` |
| 39 | `toJson`/`fromJson` round-trip | identity |

### 7.6. Mailbox (scenarios 40–49)

| # | Scenario | Expected |
|---|----------|----------|
| 40 | `fromJson` all fields present | `ok`, all fields populated |
| 41 | `fromJson` `name` absent | `err(ValidationError)` |
| 42 | `fromJson` `name` empty `""` | `err(ValidationError)` |
| 43 | `fromJson` `parentId` null → `Opt.none` | pass |
| 44 | `fromJson` `parentId` present → `Opt.some(Id)` | pass |
| 45 | `fromJson` `role` null → `Opt.none(MailboxRole)` | pass |
| 46 | `fromJson` `role` present → `Opt.some(MailboxRole)`, lowercase normalised | pass |
| 47 | `fromJson` `role` present uppercase → normalised to lowercase | pass |
| 48 | `toJson`/`fromJson` round-trip | identity |
| 49 | `fromJson` missing required field (e.g. `isSubscribed`) | `err(ValidationError)` |

### 7.7. MailboxCreate (scenarios 50–55)

| # | Scenario | Expected |
|---|----------|----------|
| 50 | `parseMailboxCreate("Archive")` defaults only | `ok`, parentId = none, role = none, sortOrder = 0, isSubscribed = false |
| 51 | `parseMailboxCreate("Inbox", role = some(roleInbox))` all fields | `ok` |
| 52 | `parseMailboxCreate("")` | `err(ValidationError)` |
| 53 | `toJson` includes all fields | structural match |
| 54 | `toJson` does not emit `id`, `totalEmails`, `unreadEmails`, `totalThreads`, `unreadThreads`, `myRights` | verified absent |
| 55 | `toJson` emits `parentId`/`role` as `null` when none | pass |

### 7.8. MailboxFilterCondition (scenarios 56–62)

| # | Scenario | Expected |
|---|----------|----------|
| 56 | `toJson` all fields none → `{}` | pass |
| 57 | `toJson` `parentId = Opt.some(Opt.none)` → `{"parentId": null}` | pass |
| 58 | `toJson` `parentId = Opt.some(Opt.some(id))` → `{"parentId": "id"}` | pass |
| 59 | `toJson` `role = Opt.some(Opt.none)` → `{"role": null}` | pass |
| 60 | `toJson` `role = Opt.some(Opt.some(roleInbox))` → `{"role": "inbox"}` | pass |
| 61 | `toJson` `name = Opt.some("test")` → `{"name": "test"}` | pass |
| 62 | `toJson` mixed filter (parentId null + hasAnyRole true) | structural match |

### 7.9. MailboxChangesResponse (scenarios 63–67)

| # | Scenario | Expected |
|---|----------|----------|
| 63 | `fromJson` valid with `updatedProperties` present | `ok`, `updatedProperties = Opt.some(seq)` |
| 64 | `fromJson` valid with `updatedProperties` absent | `ok`, `updatedProperties = Opt.none` |
| 65 | `fromJson` valid with `updatedProperties` null | `ok`, `updatedProperties = Opt.none` |
| 66 | Forwarding accessors (`accountId`, `oldState`, `newState`, etc.) return base values | pass |
| 67 | `fromJson` missing required base field (e.g. `newState`) | `err(ValidationError)` |

### 7.10. Entity Registration and Builder (scenarios 68–79)

| # | Scenario | Expected |
|---|----------|----------|
| 68 | `registerJmapEntity(Mailbox)` compiles | pass |
| 69 | `registerQueryableEntity(Mailbox)` compiles | pass |
| 70 | `addMailboxChanges` produces invocation name `"Mailbox/changes"` | pass |
| 71 | `addMailboxChanges` adds mail capability | pass |
| 72 | `addMailboxQuery` produces invocation name `"Mailbox/query"` | pass |
| 73 | `addMailboxQuery` with `sortAsTree = true` includes parameter in args | pass |
| 74 | `addMailboxQuery` with `filterAsTree = true` includes parameter in args | pass |
| 75 | `addMailboxQueryChanges` produces invocation name `"Mailbox/queryChanges"` | pass |
| 76 | `addMailboxQueryChanges` with tree parameters includes them in args | pass |
| 77 | `addMailboxSet` produces invocation name `"Mailbox/set"` | pass |
| 78 | `addMailboxSet` with `onDestroyRemoveEmails = true` includes parameter | pass |
| 79 | `addMailboxSet` with typed `MailboxCreate` serialises correctly in create map | pass |

---

## 8. Decision Traceability Matrix

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|----------|--------------------|--------|-------------------|
| B1 | `parseKeywordFromServer` leniency | A) Accept forbidden chars, B) Accept wider ASCII, C) Only skip forbidden chars, D) Accept non-ASCII | C refined (same `validateServerAssignedToken` as `parseIdFromServer`) | Parse-don't-validate, Postel's law, DRY |
| B2 | KeywordSet empty validity | A) Empty valid, B) Must be non-empty | A (empty = valid domain state "no keywords") | Constructors that can't fail don't, DDD, One source of truth |
| B3 | Distinct HashSet operations | A) Minimal read-only, B) Read + functional builders, C) Read + mutable incl/excl | A (len, contains, card only) | Immutability by default, DDD, Make the right thing easy |
| B4 | MailboxIdSet location | A) In keyword.nim, B) Dedicated sets.nim, C) Each in own module, template in validation.nim | C (KeywordSet in keyword.nim, MailboxIdSet in mailbox.nim, template in validation.nim) | DDD, DRY |
| B5 | Mailbox field sealing | A) Plain public fields, B) Sealed Pattern A, C) Partial sealing | A (read model, no invariants beyond field types) | Code reads like the spec, Parse-don't-validate |
| B6 | MailboxRights smart constructor | A) Plain object, B) Smart constructor with validation | A (all bool combinations valid) | Constructors that can't fail don't, Code reads like the spec |
| B7 | Mailbox creation model | A) MailboxCreate with smart constructor, B) PatchObject only, C) MailboxCreate without smart constructor | A (IdentityCreate pattern, RFC-matching defaults) | Make illegal states unrepresentable, DDD, Total functions |
| B8 | Mailbox role type | A) Distinct MailboxRole, B) String + constants, C) Just string constants | A (newtype with parseMailboxRole + 10 constants) | Newtype everything that has meaning, Parse-don't-validate, DRY |
| B9 | MailboxChangesResponse modelling | A) Custom flat type, B) Composition, C) Composition + forwarding template | C (composition + forwardChangesFields template) | DRY, Code reads like the spec, Open-Closed |
| B10 | QueryParams location | A) mail_builders.nim, B) framework.nim, C) Skip entirely | B + core addQuery refactor (core prerequisite) | DRY, DDD, One source of truth |
| B11 | Filter condition serde direction | A) toJson only, B) Both toJson and fromJson | A (general convention: filter conditions are query creation types) | Parse-don't-validate, DDD |
| B12 | Mailbox/queryChanges builder | A) Custom with sortAsTree/filterAsTree, B) Use core generic | A (RFC 8621 §2.6 extends queryChanges with tree params) | Code reads like the spec, Total functions |
| B13 | Tree option parameter style | A) MailboxTreeOptions type, B) Inline booleans | B (2 params across 2 functions — premature abstraction) | Booleans exception (may*/AsTree naming self-documenting, RFC models as Boolean) |
| B14 | Mailbox entity registration | A) Register + custom overloads, B) Register + hide generics, C) All custom | Modified A (register for infrastructure, custom overloads as API, re-export customs from hub) | DDD, Make the right thing easy, DRY |
| B15 | fromJson parser convention | A) Lenient per-type, B) General convention | B (general rule: all fromJson use lenient *FromServer parser) | DRY, Postel's law |
| B16 | Filter role type | A) Opt[Opt[MailboxRole]], B) Opt[Opt[string]] | A (consequence of B8 — one type for the concept everywhere) | Newtype everything that has meaning, One source of truth |
| B17 | Document structure | A) Keyword first then Mailbox, B) Interleaved by module | Refined A (core prerequisites → shared sub-types → entity → filter → builders) | Parse once at the boundary (dependencies top-down) |
| B18 | MailboxCreate role field | A) Include as Opt[MailboxRole], B) Exclude | A (RFC allows, server rejection via SetError) | Postel's law, DDD |
| B19 | Mailbox partial response handling | A) All fields Opt, B) All fields required, C) Split required/Opt | B (typed Mailbox = complete domain object, partial via raw JSON) | Code reads like the spec, Make illegal states unrepresentable, One source of truth |
| B20 | MailboxRole parser pair | A) Single parseMailboxRole, B) Strict/lenient pair | A (no meaningful gap between spec and structural constraints) | DRY, Constructors that can't fail don't |
| B21 | addMailboxSet create type | A) Consumer calls toJson, B) Builder accepts MailboxCreate | B (typed creation model on entity-specific builder) | Make the right thing easy, Make illegal states unrepresentable, Parse once at the boundary |
