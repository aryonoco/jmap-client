# RFC 8621 JMAP Mail — Design D: Email Read Path

This document is the detailed specification for the Email read model, query
infrastructure, Email/parse, and SearchSnippet — the "read path" of RFC 8621
§4–5. It covers all layers (L1 types, L2 serde, L3 builders and custom
methods) for each type, cutting horizontally through the architecture.

Email is the most property-rich entity in the spec (~30 properties across
metadata, headers, and body, plus dynamic `header:*` properties). The
horizontal layout — all types first, then all serde, then all builders — is
chosen over the vertical slices of Designs A–C because the Email serde layer
has significant cross-cutting concerns (shared helpers between Email and
ParsedEmail) that would be awkward to present within a single type section.

Builds on the cross-cutting architecture design (`05-mail-architecture.md`),
the existing RFC 8620 infrastructure (`00-architecture.md` through
`04-layer-4-design.md`), Design A (`06-mail-a-design.md`), Design B
(`07-mail-b-design.md`), and Design C (`08-mail-c-design.md`). Architecture
decisions are referenced by section number; Part A–C decisions by their
identifiers (A14, B11, B16, C1, etc.).

---

## Table of Contents

1.  [Scope](#1-scope)
2.  [Email Entity — email.nim](#2-email-entity--emailnim)
3.  [ParsedEmail Entity — email.nim](#3-parsedemail-entity--emailnim)
4.  [EmailComparator — email.nim](#4-emailcomparator--emailnim)
5.  [EmailBodyFetchOptions — email.nim](#5-emailbodyfetchoptions--emailnim)
6.  [EmailFilterCondition — mail_filters.nim](#6-emailfiltercondition--mail_filtersnim)
7.  [SearchSnippet — snippet.nim](#7-searchsnippet--snippetnim)
8.  [Serialisation](#8-serialisation)
9.  [Builders](#9-builders)
10. [Custom Methods](#10-custom-methods)
11. [Module Organisation](#11-module-organisation)
12. [Test Specification](#12-test-specification)
13. [Decision Traceability Matrix](#13-decision-traceability-matrix)

---

## 1. Scope

### 1.1. Entities Covered

| Entity | RFC 8621 Section | Capability URI | Complexity |
|--------|------------------|----------------|------------|
| Email (read model) | §4 | `urn:ietf:params:jmap:mail` | High |
| SearchSnippet | §5 | `urn:ietf:params:jmap:mail` | Low |

### 1.2. Supporting Types Covered

| Type | Module | Rationale |
|------|--------|-----------|
| `Email` | `email.nim` | Store-backed read model — ~28 fields across metadata, headers, body, and dynamic header properties |
| `ParsedEmail` | `email.nim` | Blob-backed read model for Email/parse — structurally distinct from Email (missing 6 metadata fields) |
| `PlainSortProperty` | `email.nim` | Enum of non-keyword Email sort properties |
| `KeywordSortProperty` | `email.nim` | Enum of keyword-bearing Email sort properties |
| `EmailComparator` | `email.nim` | Case object — compile-time enforcement that keyword sorts carry a `Keyword` |
| `BodyValueScope` | `email.nim` | Enum replacing three RFC booleans for body value fetching |
| `EmailBodyFetchOptions` | `email.nim` | Shared parameter type for Email/get and Email/parse body options |
| `EmailFilterCondition` | `mail_filters.nim` | 20-field query specification for Email/query (extends existing module) |
| `EmailHeaderFilter` | `mail_filters.nim` | Sub-type for the `header` filter field (sealed `name`, smart constructor) |
| `SearchSnippet` | `snippet.nim` | Search highlight data carrier — no id property |
| `EmailParseResponse` | `mail_methods.nim` | Typed response for Email/parse with `Table[Id, ParsedEmail]` |
| `SearchSnippetGetResponse` | `mail_methods.nim` | Typed response for SearchSnippet/get |

### 1.3. Deferred

**Part E (Email write path):** `EmailBlueprint` creation model, `Email/set`,
`Email/import`, `Email/copy` builders.

**Part F (submission):** `EmailSubmission` and all submission types.

### 1.4. Relationship to Cross-Cutting Design

This document refines `05-mail-architecture.md` into implementation-ready
specifications. The architecture doc locks in the three-type split (Email,
ParsedEmail, EmailBlueprint — Decision 13), `fromAddr` naming convention,
`MailboxIdSet`/`KeywordSet` as distinct types (Decision 12), and the
`requestedHeaders`/`requestedHeadersAll` table pattern (Decision 6).

**Refinement from architecture doc:** The architecture doc specified body
fields (`bodyStructure`, `bodyValues`, `textBody`, `htmlBody`, `attachments`)
as `Opt[T]` on the Email type. Decision D2 refines this: a typed `Email` is a
complete domain object with ALL properties present. Body fields use non-Opt
types with natural "empty" values (`Table` for bodyValues, `seq` for lists,
`bool` for hasAttachment, `string` for preview). Partial-property responses
use raw `GetResponse.list: seq[JsonNode]` (architecture Decision D3.6). This
eliminates the ambiguity of `Opt.none` meaning both "not requested" and
"absent" — on a typed Email, every `Opt` has exactly one meaning.

### 1.5. General Conventions Applied

All conventions established in prior designs apply:

1. **Lenient fromJson convention** (B15) — `*FromServer` parser variants for
   all server-received distinct types.
2. **Filter conditions are toJson-only** (B11) — no `fromJson`.
3. **Strict/lenient parser pairs are principled** (B20) — pair exists only
   when a meaningful gap between spec-specific and structural constraints.
4. **Entity-specific builders accept typed parameters** (B21).

### 1.6. Module Summary

All modules live under `src/jmap_client/mail/` per cross-cutting doc §3.3.

| Module | Layer | Contents |
|--------|-------|----------|
| `email.nim` | L1 | `Email`, `ParsedEmail`, `PlainSortProperty`, `KeywordSortProperty`, `EmailComparator`, `BodyValueScope`, `EmailBodyFetchOptions` |
| `snippet.nim` | L1 | `SearchSnippet` |
| `mail_filters.nim` | L1 | `EmailFilterCondition`, `EmailHeaderFilter` (extends existing module with Mailbox filters) |
| `serde_email.nim` | L2 | `toJson`/`fromJson` for Email, ParsedEmail, EmailComparator, EmailBodyFetchOptions; shared serde helpers |
| `serde_snippet.nim` | L2 | `fromJson` for SearchSnippet |
| `mail_entities.nim` | L3 | Entity registration for Email (extends existing module) |
| `mail_builders.nim` | L3 | `addEmailGet`, `addEmailQuery`, `addEmailQueryChanges` |
| `mail_methods.nim` | L3 | `addEmailParse`, `addSearchSnippetGet`, `EmailParseResponse`, `SearchSnippetGetResponse` (extends existing module) |

---

## 2. Email Entity — email.nim

**Module:** `src/jmap_client/mail/email.nim`

**RFC reference:** §4.1 (properties), §4.2 (Email/get).

The Email type is the store-backed read model — a complete representation of
a message as returned by `Email/get`. A typed `Email` is a complete domain
object: every property is present, every `Opt` has exactly one meaning
(Decision D2). Callers who need partial-property responses use raw
`GetResponse.list: seq[JsonNode]` and parse selectively.

**Principles:**
- **Code reads like the spec** — Fields map 1:1 to RFC §4.1 properties.
- **One meaning per Opt** — `Opt.none` on convenience headers means
  exclusively "header absent in message" (D3). No "not requested" semantics.
- **Parse, don't validate** — Construction via `parseEmail` validates
  non-empty `mailboxIds` (D1).

### 2.1. Type Definition

```nim
type Email* {.ruleOff: "objects".} = object
  ## Store-backed Email read model (RFC 8621 §4.1).
  ## A typed Email is a complete domain object — every property present.
  ## Partial-property access uses raw ``GetResponse.list: seq[JsonNode]``.

  # ── Metadata (§4.1.1) ── server-set, immutable except mailboxIds/keywords
  id*: Id                                        ## JMAP object id (not Message-ID header).
  blobId*: Id                                    ## Raw RFC 5322 octets.
  threadId*: Id                                  ## Thread this Email belongs to.
  mailboxIds*: MailboxIdSet                      ## ≥1 Mailbox at all times (RFC invariant).
  keywords*: KeywordSet                          ## Default: empty set.
  size*: UnsignedInt                             ## Raw message size in octets.
  receivedAt*: UTCDate                           ## IMAP internal date.

  # ── Convenience headers (§4.1.2–4.1.3) ── Opt.none = header absent in message
  messageId*: Opt[seq[string]]                   ## header:Message-ID:asMessageIds
  inReplyTo*: Opt[seq[string]]                   ## header:In-Reply-To:asMessageIds
  references*: Opt[seq[string]]                  ## header:References:asMessageIds
  sender*: Opt[seq[EmailAddress]]                ## header:Sender:asAddresses
  fromAddr*: Opt[seq[EmailAddress]]              ## header:From:asAddresses (``from`` is a Nim keyword)
  to*: Opt[seq[EmailAddress]]                    ## header:To:asAddresses
  cc*: Opt[seq[EmailAddress]]                    ## header:Cc:asAddresses
  bcc*: Opt[seq[EmailAddress]]                   ## header:Bcc:asAddresses
  replyTo*: Opt[seq[EmailAddress]]               ## header:Reply-To:asAddresses
  subject*: Opt[string]                          ## header:Subject:asText
  sentAt*: Opt[Date]                             ## header:Date:asDate

  # ── Raw headers (§4.1.3) ──
  headers*: seq[EmailHeader]                     ## All header fields in message order; @[] if absent.

  # ── Dynamic header properties (§4.1.3) ──
  requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
    ## Parsed headers requested via ``header:Name:asForm`` (last instance).
  requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]
    ## Parsed headers requested via ``header:Name:asForm:all`` (all instances).

  # ── Body (§4.1.4) ──
  bodyStructure*: EmailBodyPart                  ## Full MIME tree.
  bodyValues*: Table[PartId, EmailBodyValue]     ## Text part contents; empty if none fetched.
  textBody*: seq[EmailBodyPart]                  ## Leaf parts — text/plain preference.
  htmlBody*: seq[EmailBodyPart]                  ## Leaf parts — text/html preference.
  attachments*: seq[EmailBodyPart]               ## Leaf parts — non-body content.
  hasAttachment*: bool                           ## Server heuristic.
  preview*: string                               ## ≤256 characters plaintext fragment.
```

**28 fields total:** 7 metadata + 11 convenience headers + 1 raw headers +
2 dynamic header tables + 7 body.

**`fromAddr` naming:** `from` is a Nim reserved keyword. The architecture doc
(Decision 12.4) mandates `fromAddr` consistently across Email, ParsedEmail,
EmailBlueprint, and EmailFilterCondition. The serde layer maps to/from the
RFC's `"from"` key transparently.

**Field grouping rationale:**
- **Metadata** — Server-managed store properties. All non-Opt (typed Email =
  complete object). `mailboxIds` and `keywords` are the only mutable fields
  (mutated via `Email/set` with `PatchObject`, not on the read type).
- **Convenience headers** — Parsed forms of common header fields. `Opt.none`
  means exclusively "this header field does not exist in the message" (D3).
- **Raw headers** — The `headers` escape hatch for full header access.
  `seq[EmailHeader]` — empty seq means no headers (extremely unlikely in
  practice).
- **Dynamic headers** — Caller-requested `header:Name:asForm` properties.
  Tables are empty when no dynamic headers were requested. `fromJson` routes
  these via prefix matching (D4).
- **Body** — Message body structure and content. Non-Opt types with natural
  "empty" values (empty Table, empty seq, `false`, `""`).

### 2.2. Smart Constructor

```nim
func parseEmail*(e: Email): Result[Email, ValidationError] =
  ## Validates the single domain invariant: mailboxIds must not be empty.
  ## RFC 8621 §4.1.1: "An Email in the mail store MUST belong to one or more
  ## Mailboxes at all times."
  if e.mailboxIds.len == 0:
    return err(validationError("Email", "mailboxIds must not be empty", ""))
  ok(e)
```

**Why accept-and-validate, not 28-parameter constructor?** Email has 28
fields. A positional constructor with 28 parameters would be unwieldy and
fragile. Instead, `parseEmail` accepts a constructed `Email` object and
validates the single domain invariant. The primary construction path is
`fromJson` (which calls `parseEmail` internally). Client code that constructs
an Email directly (unlikely — this is a read model) uses field syntax and
then validates:

```nim
let email = Email(id: myId, blobId: myBlobId, ...).parseEmail.expect("valid")
```

**Plain public fields (D1):** Fields are public for reading ergonomics.
Construction is gated by `parseEmail` as a convention, not enforced by the
type system (unlike Pattern A, which seals fields behind module-private
access). With 28 fields, the cost of Pattern A (28 accessor functions, no
field syntax for construction) outweighs the benefit. ProveInit prevents
uninitialised use. Same pattern as Thread after Decision A14.

**mailboxIds validation only (D15):** `fromJson` is lenient (Postel's law) —
it accepts empty `mailboxIds` from the server without failing. The server's
contract (RFC §4.1.1) guarantees non-empty; the client trusts that contract.
`parseEmail` is for client-side construction where the boundary is different.
"Boundary" is context-dependent: server→client = trust the server's contract;
client→server = validate at our construction boundary.

**Principles:**
- **Parse, don't validate** — `parseEmail` returns `Result`, not a bare
  object.
- **Constructors that can fail return Result** — Non-empty `mailboxIds` can
  fail.
- **Postel's law** — `fromJson` accepts server data leniently; `parseEmail`
  validates client construction strictly.

### 2.3. Leaf-Only Body Lists (D6)

`textBody`, `htmlBody`, and `attachments` are guaranteed by the RFC to contain
only leaf parts (no multipart/* entries). The typed Email does **not** enforce
this invariant via smart constructor validation. Instead, it trusts the
server's contract (Postel's law) — same reasoning as D15 for `mailboxIds`.

A convenience predicate may be provided for callers who wish to assert:

```nim
func isLeaf*(part: EmailBodyPart): bool =
  ## True if this part is a leaf (not multipart/*).
  not part.isMultipart
```

---

## 3. ParsedEmail Entity — email.nim

**Module:** `src/jmap_client/mail/email.nim` (same module as Email).

**RFC reference:** §4.9 (Email/parse).

`ParsedEmail` is the blob-backed read model returned by `Email/parse`. It
represents a parsed message blob without store metadata. Structurally distinct
from `Email` — six metadata fields are physically absent (not `Opt.none`),
and `threadId` is `Opt[Id]` (the server may not be able to determine thread
assignment for a blob).

**Decision D7:** Full field duplication — both `Email` and `ParsedEmail` are
independent flat object types with all fields declared directly. No shared
sub-object types (no `EmailSharedHeaders` or similar). Shared serde helper
procs for common field groups (convenience headers, body fields, dynamic
header routing) keep parsing logic DRY without sacrificing type clarity.

"DRY — but duplicated appearance is not duplicated knowledge." The field
declarations look similar but belong to different domain aggregates with
different invariants. Factoring them into a shared sub-object would create a
type that lacks domain meaning.

**Principles:**
- **DDD** — Different aggregates with different invariants get different types
  (architecture doc Decision 13). "Structurally absent" ≠ "null."
- **Code reads like the spec** — Both types read as flat field lists matching
  the RFC property tables.
- **DRY where it matters** — Serde helpers (boundary code) are shared;
  declarations (domain code) are duplicated.

### 3.1. Type Definition

```nim
type ParsedEmail* {.ruleOff: "objects".} = object
  ## Blob-backed Email for Email/parse responses (RFC 8621 §4.9).
  ## Missing id, blobId, mailboxIds, keywords, size, receivedAt —
  ## structurally absent, not ``Opt.none``.

  # ── Metadata ── only threadId survives
  threadId*: Opt[Id]                             ## Server MAY provide if determinable; else none.

  # ── Convenience headers ── identical structure to Email
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

  # ── Raw headers ──
  headers*: seq[EmailHeader]

  # ── Dynamic header properties ──
  requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
  requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]

  # ── Body ──
  bodyStructure*: EmailBodyPart
  bodyValues*: Table[PartId, EmailBodyValue]
  textBody*: seq[EmailBodyPart]
  htmlBody*: seq[EmailBodyPart]
  attachments*: seq[EmailBodyPart]
  hasAttachment*: bool
  preview*: string
```

**22 fields total:** 1 metadata + 11 convenience headers + 1 raw headers +
2 dynamic header tables + 7 body.

**No smart constructor beyond fromJson.** ParsedEmail is a read-only result
from `Email/parse`. The only "construction" is parsing from server JSON. No
client-side construction path exists, so no validation beyond what `fromJson`
provides.

### 3.2. Field Comparison with Email

| Property Group | Email | ParsedEmail | Difference |
|----------------|-------|-------------|------------|
| Metadata | `id`, `blobId`, `threadId`, `mailboxIds`, `keywords`, `size`, `receivedAt` (7 fields) | `threadId: Opt[Id]` (1 field) | 6 fields absent; `threadId` becomes `Opt` (D20) |
| Convenience headers | 11 fields, all `Opt` | Identical | None |
| Raw headers | `headers: seq[EmailHeader]` | Identical | None |
| Dynamic headers | 2 tables | Identical | None |
| Body | 7 fields | Identical | None |

**`blobId` and `size` exclusion (D20):** RFC §4.9 lists four metadata
properties as null on parsed emails: `id`, `mailboxIds`, `keywords`,
`receivedAt`. It does not list `blobId` or `size` — they are technically
available if explicitly requested. ParsedEmail omits them for three reasons:
(1) `blobId` is redundant — the `EmailParseResponse.parsed` table is keyed by
blob id, so the caller already has it; (2) `size` is derivable from the blob
itself; (3) blob infrastructure is deferred (architecture doc §4.6 — "Binary
data out of scope for initial release"). When `BlobId` is promoted from
generic `Id` to a distinct type, ParsedEmail metadata should be revisited.
This follows the architecture doc's Decision 13 (§8.3): ParsedEmail models
"what a parsed blob IS" rather than mirroring the full Email type with holes.

---

## 4. EmailComparator — email.nim

**Module:** `src/jmap_client/mail/email.nim`

**RFC reference:** §4.4.2 (sorting).

RFC 8621 extends the standard Comparator (RFC 8620 §5.5) for Email/query
with a `keyword` property: three sort properties (`hasKeyword`,
`allInThreadHaveKeyword`, `someInThreadHaveKeyword`) require an accompanying
`Keyword` value. The remaining six (`receivedAt`, `size`, `from`, `to`,
`subject`, `sentAt`) do not.

The generic `Comparator` type (sealed via Pattern A in `framework.nim`) cannot
carry the extra `keyword` field. Rather than bolt an `Opt[Keyword]` onto the
generic type or erase the keyword into a `JsonNode`, Decision D8 models this
as a case object with split enums — making illegal states (keyword sort
without a keyword, plain sort with a keyword) unrepresentable at compile time.

### 4.1. Sort Property Enums

```nim
type
  PlainSortProperty* = enum
    ## Sort properties that take no additional parameters (RFC 8621 §4.4.2).
    pspReceivedAt = "receivedAt"
    pspSize       = "size"
    pspFrom       = "from"
    pspTo         = "to"
    pspSubject    = "subject"
    pspSentAt     = "sentAt"

  KeywordSortProperty* = enum
    ## Sort properties that require an accompanying Keyword (RFC 8621 §4.4.2).
    kspHasKeyword                  = "hasKeyword"
    kspAllInThreadHaveKeyword      = "allInThreadHaveKeyword"
    kspSomeInThreadHaveKeyword     = "someInThreadHaveKeyword"
```

**Two enums, not one:** The split encodes the structural difference. A single
`EmailSortProperty` enum with 9 variants would still require runtime checking
of whether the keyword field is present for keyword sorts. Split enums push
this check to the type system.

### 4.2. Case Object

```nim
type
  EmailComparatorKind* = enum
    eckPlain
    eckKeyword

  EmailComparator* {.ruleOff: "objects".} = object
    ## Email-specific sort criterion (RFC 8621 §4.4.2). Extends the standard
    ## Comparator with keyword-bearing sort properties.
    isAscending*: Opt[bool]          ## Absent = server default (RFC: true).
    collation*: Opt[string]          ## RFC 4790 collation identifier.
    case kind*: EmailComparatorKind
    of eckPlain:
      property*: PlainSortProperty
    of eckKeyword:
      keywordProperty*: KeywordSortProperty
      keyword*: Keyword              ## Required for keyword sorts.
```

**Shared fields before `case`:** `isAscending` and `collation` apply to both
branches — accessible without matching `kind`.

**`isAscending` is `Opt[bool]`:** Unlike the core `Comparator` (which
defaults `isAscending` to `true`), `EmailComparator` uses `Opt[bool]` so that
the serde layer can distinguish "client explicitly set ascending" from "use
server default." The RFC default is `true`, but some servers may interpret
absence differently. `Opt.none` → omit from JSON; `Opt.some(true)` → emit
`true`.

### 4.3. Total Constructors

Both constructors are total — no `Result`, no validation. Every input
combination produces a valid `EmailComparator`.

```nim
func plainComparator*(
    property: PlainSortProperty,
    isAscending: Opt[bool] = Opt.none(bool),
    collation: Opt[string] = Opt.none(string),
): EmailComparator =
  EmailComparator(
    kind: eckPlain,
    property: property,
    isAscending: isAscending,
    collation: collation,
  )

func keywordComparator*(
    keywordProperty: KeywordSortProperty,
    keyword: Keyword,
    isAscending: Opt[bool] = Opt.none(bool),
    collation: Opt[string] = Opt.none(string),
): EmailComparator =
  EmailComparator(
    kind: eckKeyword,
    keywordProperty: keywordProperty,
    keyword: keyword,
    isAscending: isAscending,
    collation: collation,
  )
```

**Principles:**
- **Make illegal states unrepresentable** — Keyword sort without keyword
  is a compile error (the `keyword` field only exists on the `eckKeyword`
  branch). Plain sort with keyword is a compile error (no `keyword` field
  on `eckPlain`).
- **Constructors that can't fail, don't** — Both constructors are infallible.
  All validation is pushed into the enum types (`PlainSortProperty` and
  `KeywordSortProperty` constrain the value set) and `Keyword` (validated at
  construction time).
- **Total functions** — Every input of the declared type produces a valid
  output.

---

## 5. EmailBodyFetchOptions — email.nim

**Module:** `src/jmap_client/mail/email.nim`

**RFC reference:** §4.2 (Email/get), §4.9 (Email/parse).

Both `Email/get` and `Email/parse` accept the same four body-related
parameters: `bodyProperties`, `fetchTextBodyValues`, `fetchHTMLBodyValues`,
`fetchAllBodyValues`, and `maxBodyValueBytes`. The three `fetch*BodyValues`
booleans are mutually overlapping — "booleans are a code smell" (CLAUDE.md).
Decision D9 replaces them with a domain-meaningful enum.

### 5.1. BodyValueScope Enum

```nim
type BodyValueScope* = enum
  ## Which body value parts to include in ``bodyValues``.
  ## Replaces three RFC booleans with a single domain-meaningful choice.
  bvsNone           ## No body values fetched (all three bools false).
  bvsText           ## fetchTextBodyValues = true.
  bvsHtml           ## fetchHTMLBodyValues = true.
  bvsTextAndHtml    ## fetchTextBodyValues = true, fetchHTMLBodyValues = true.
  bvsAll            ## fetchAllBodyValues = true.
```

**Mapping to RFC booleans:**

| Enum Value | fetchTextBodyValues | fetchHTMLBodyValues | fetchAllBodyValues |
|------------|----|----|-----|
| `bvsNone` | false | false | false |
| `bvsText` | true | false | false |
| `bvsHtml` | false | true | false |
| `bvsTextAndHtml` | true | true | false |
| `bvsAll` | false | false | true |

The serde layer maps the enum back to the three RFC booleans at the boundary.
Every valid combination is a distinct enum variant — no impossible states.

### 5.2. Type Definition

```nim
type EmailBodyFetchOptions* {.ruleOff: "objects".} = object
  ## Shared parameters for Email/get and Email/parse body value fetching.
  ## Default value via ``default(EmailBodyFetchOptions)`` produces correct
  ## RFC defaults (no body properties override, no body values, no truncation).
  bodyProperties*: Opt[seq[PropertyName]]   ## Override default body part properties.
  fetchBodyValues*: BodyValueScope          ## Default: bvsNone.
  maxBodyValueBytes*: Opt[UnsignedInt]      ## Absent = no truncation. 0 = no truncation.
```

**No smart constructor.** All field combinations are valid. `default(
EmailBodyFetchOptions)` produces correct RFC defaults (Nim zero-initialises:
`Opt.none`, `bvsNone`, `Opt.none`).

**Principles:**
- **Booleans are a code smell** — The enum replaces three booleans whose
  interaction is non-obvious (e.g., does `fetchAllBodyValues` override
  `fetchTextBodyValues`? The enum eliminates the question).
- **Make the right thing easy** — `default(EmailBodyFetchOptions)` is
  correct. Callers only specify what they want to change.
- **DRY** — One type shared by both `addEmailGet` and `addEmailParse`.

---

## 6. EmailFilterCondition — mail_filters.nim

**Module:** `src/jmap_client/mail/mail_filters.nim` (extends existing module
alongside `MailboxFilterCondition`).

**RFC reference:** §4.4.1 (filtering).

`EmailFilterCondition` is a query specification — a value object that
describes filter criteria for `Email/query`. Like `MailboxFilterCondition`
(Design B §5), it is toJson-only (B11), has no smart constructor (B16), and
all field combinations are valid.

### 6.1. EmailHeaderFilter

The RFC `header` filter field is a 1–2 element array: the first element is
the header name (required, non-empty), the second is the value to match
(optional). This structural constraint (non-empty name) is enforced via a
smart constructor — unlike the filter condition itself, where all combinations
are valid, an `EmailHeaderFilter` with an empty name is structurally invalid.

```nim
type EmailHeaderFilter* = object
  ## Filter sub-type for the ``header`` property of EmailFilterCondition
  ## (RFC 8621 §4.4.1). The ``name`` field is sealed (Pattern A) to enforce
  ## the non-empty invariant.
  name: string              ## Module-private, non-empty.
  value*: Opt[string]       ## Text to match in header value, or none = existence check.
```

**Accessor:**

```nim
func name*(f: EmailHeaderFilter): string = f.name
```

**Smart constructor:**

```nim
func parseEmailHeaderFilter*(
    name: string,
    value: Opt[string] = Opt.none(string),
): Result[EmailHeaderFilter, ValidationError] =
  ## Validates that name is non-empty.
  if name.len == 0:
    return err(validationError(
      "EmailHeaderFilter", "header name must not be empty", name))
  ok(EmailHeaderFilter(name: name, value: value))
```

**Principles:**
- **Parse, don't validate** — Non-empty name enforced at construction time.
- **Pattern A where warranted** — One sealed field with one invariant. Unlike
  Email (28 fields, one invariant — Pattern A too costly), EmailHeaderFilter
  has the right ratio.

### 6.2. Type Definition

```nim
type EmailFilterCondition* {.ruleOff: "objects".} = object
  ## Filter condition for Email/query (RFC 8621 §4.4.1). No smart constructor —
  ## all field combinations are valid (B16). toJson only — the server never
  ## sends this back (B11).

  # ── Mailbox membership ──
  inMailbox*: Opt[Id]                              ## Email must be in this Mailbox.
  inMailboxOtherThan*: Opt[seq[Id]]                ## Email must be in a Mailbox not in this list.

  # ── Date/size ──
  before*: Opt[UTCDate]                            ## receivedAt < this date.
  after*: Opt[UTCDate]                             ## receivedAt ≥ this date.
  minSize*: Opt[UnsignedInt]                       ## size ≥ this value.
  maxSize*: Opt[UnsignedInt]                       ## size < this value.

  # ── Thread keyword filters ──
  allInThreadHaveKeyword*: Opt[Keyword]            ## All thread emails have this keyword.
  someInThreadHaveKeyword*: Opt[Keyword]           ## At least one thread email has this keyword.
  noneInThreadHaveKeyword*: Opt[Keyword]           ## No thread emails have this keyword.

  # ── Per-email keyword filters ──
  hasKeyword*: Opt[Keyword]                        ## This email has the keyword.
  notKeyword*: Opt[Keyword]                        ## This email does not have the keyword.

  # ── Boolean filter ──
  hasAttachment*: Opt[bool]                        ## Match on hasAttachment value.

  # ── Text search ──
  text*: Opt[string]                               ## Search From, To, Cc, Bcc, Subject, body.
  fromAddr*: Opt[string]                           ## Search From header (``from`` is a Nim keyword).
  to*: Opt[string]                                 ## Search To header.
  cc*: Opt[string]                                 ## Search Cc header.
  bcc*: Opt[string]                                ## Search Bcc header.
  subject*: Opt[string]                            ## Search Subject header.
  body*: Opt[string]                               ## Search body parts.

  # ── Header filter ──
  header*: Opt[EmailHeaderFilter]                  ## Match header by name (and optionally value).
```

**20 fields total.** Keyword filter fields use typed `Keyword` (not `string`)
— consequence of the newtype-everything principle. The RFC specifies these as
`String`, but semantically they are keywords.

**No `Opt[Opt[T]]` pattern.** Unlike `MailboxFilterCondition` (which needs
three-state semantics for `parentId` and `role`), no Email filter field has a
meaningful "filter for null" state. `Opt.none` = not filtering on this
property (omit from JSON).

**`inMailboxOtherThan` non-empty enforcement (D16):** No enforcement. An
empty list is vacuous (matches everything) but not illegal — the RFC does not
prohibit it. "Make illegal states unrepresentable" targets domain invariant
violations, not usage quality.

**Principles:**
- **Newtype everything that has meaning** — Keyword filter fields use
  `Keyword`, not `string`. `inMailbox` uses `Id`, not `string`.
- **DDD** — Value object, not entity. Construction is infallible.
- **Make the right thing easy** — All-none produces `{}` (match everything).

---

## 7. SearchSnippet — snippet.nim

**Module:** `src/jmap_client/mail/snippet.nim`

**RFC reference:** §5 (SearchSnippet).

A `SearchSnippet` provides highlighted search result fragments for an Email.
Unlike most data types, SearchSnippet has no `id` property — it is keyed by
`emailId`.

### 7.1. Type Definition

```nim
type SearchSnippet* = object
  ## Search result highlight for an Email (RFC 8621 §5).
  ## No ``id`` property — keyed by ``emailId``.
  emailId*: Id                    ## The Email this snippet describes.
  subject*: Opt[string]           ## Highlighted subject fragment with ``<mark>`` tags, or none.
  preview*: Opt[string]           ## Highlighted body fragment with ``<mark>`` tags, or none.
```

**No smart constructor.** Pure data carrier — all field combinations valid.
Server provides both `subject` and `preview` as null when unable to determine
search snippets.

**`Opt` semantics:** `Opt.none` means "no matching content to highlight"
(domain-level). Both fields null = server could not determine snippets.

**Principles:**
- **Code reads like the spec** — Three fields mapping directly to RFC §5.
- **Constructors that can't fail, don't** — No invariants to enforce.

### 7.2. SearchSnippetGetResponse

```nim
type SearchSnippetGetResponse* = object
  ## Response for SearchSnippet/get (RFC 8621 §5.1).
  accountId*: AccountId
  list*: seq[SearchSnippet]       ## Snippets for requested Email ids.
  notFound*: seq[Id]              ## Email ids that could not be found.
```

**`notFound` is `seq[Id]`, not `Opt[seq[Id]]`** (D13). The RFC specifies
`Id[]|null`, but `fromJson` collapses both null and `[]` into an empty seq.
The wire distinction (null vs empty array) is noise; the domain fact is a
possibly-empty list. "Parse once at the boundary."

### 7.3. EmailParseResponse

```nim
type EmailParseResponse* = object
  ## Response for Email/parse (RFC 8621 §4.9).
  accountId*: AccountId
  parsed*: Table[Id, ParsedEmail]   ## Blob id → parsed Email, for successfully parsed blobs.
  notParseable*: seq[Id]            ## Blob ids that could not be parsed as Emails.
  notFound*: seq[Id]                ## Blob ids that could not be found.
```

**Dedicated response type with typed `ParsedEmail`** (D11). `fromJson` parses
`ParsedEmail` at the boundary — "parse once, trust forever." Callers receive
typed values with no second parsing step. `notParseable` and `notFound` use
the same `seq[Id]` null-collapsing pattern as `SearchSnippetGetResponse`.

**Principles:**
- **Parse once at the boundary** — `ParsedEmail` is fully typed in the
  response. No raw `JsonNode` for the caller to re-parse.
- **Code reads like the spec** — Fields map 1:1 to RFC §4.9 response.

---

## 8. Serialisation

### 8.1. Email fromJson — serde_email.nim

**Module:** `src/jmap_client/mail/serde_email.nim`

**RFC reference:** §4.1 (properties), §4.2.1 (example).

Email `fromJson` is the most complex deserialiser in the library. It uses a
two-phase strategy (D4):

**Phase 1 — Structured extraction:** Direct key lookups (`node{"id"}`,
`node{"from"}`, etc.) for all known standard properties. O(1) hash lookups on
`JsonNode`'s `OrderedTable`. Code mirrors the RFC property table — one
extraction per field.

**Phase 2 — Dynamic discovery:** Single iteration over all keys in the JSON
object. Keys starting with `"header:"` are parsed via
`parseHeaderPropertyName` and routed to `requestedHeaders` (single instance)
or `requestedHeadersAll` (`:all` suffix) based on `isAll`. Keys not matching
the `"header:"` prefix are silently ignored (forward compatibility with
future RFC extensions).

```nim
func emailFromJson*(node: JsonNode): Result[Email, ValidationError] =
  ## Parses a complete Email object from server JSON.
  if node.kind != JObject:
    return err(validationError("Email", "expected JObject", $node.kind))

  # ── Phase 1: Structured extraction ──

  # Metadata
  let id = ? Id.fromJson(node, "id")
  let blobId = ? Id.fromJson(node, "blobId")
  let threadId = ? Id.fromJson(node, "threadId")
  let mailboxIds = ? MailboxIdSet.fromJson(node, "mailboxIds")
  let keywords = node.keywordsOrDefault()   # defaults to empty KeywordSet if absent
  let size = ? UnsignedInt.fromJson(node, "size")
  let receivedAt = ? UTCDate.fromJson(node, "receivedAt")

  # Convenience headers — shared helper
  let convHeaders = ? parseConvenienceHeaders(node)

  # Raw headers
  let headers = ? parseRawHeaders(node)

  # Body — shared helper
  let bodyFields = ? parseBodyFields(node)

  # ── Phase 2: Dynamic header discovery ──
  var reqHeaders: Table[HeaderPropertyKey, HeaderValue]
  var reqHeadersAll: Table[HeaderPropertyKey, seq[HeaderValue]]
  for key, val in node:
    if key.startsWith("header:"):
      let hpk = ? parseHeaderPropertyName(key)
      if hpk.isAll:
        reqHeadersAll[hpk] = ? parseHeaderValueArray(val, hpk.form)
      else:
        reqHeaders[hpk] = ? parseHeaderValue(val, hpk.form)

  ok(Email(
    id: id, blobId: blobId, threadId: threadId,
    mailboxIds: mailboxIds, keywords: keywords,
    size: size, receivedAt: receivedAt,
    messageId: convHeaders.messageId,
    inReplyTo: convHeaders.inReplyTo,
    # ... (all convenience header fields from shared helper)
    headers: headers,
    requestedHeaders: reqHeaders,
    requestedHeadersAll: reqHeadersAll,
    bodyStructure: bodyFields.bodyStructure,
    bodyValues: bodyFields.bodyValues,
    # ... (all body fields from shared helper)
  ))
```

**`keywords` default:** RFC §4.1.1 specifies `keywords` with `default: {}`.
If the key is absent from the JSON, `fromJson` defaults to an empty
`KeywordSet` rather than failing. This is the only metadata field with a
default value.

**No parallel set of known property names.** Phase 2 does not maintain a set
of "known properties" to skip. Phase 1 extracts known properties by direct
key lookup; Phase 2 discovers unknown `header:*` keys by iteration. Keys that
are neither known standard properties nor `header:*` prefixed are silently
ignored. This mirrors the RFC structure: fixed properties by name, dynamic
extension by prefix.

### 8.2. ParsedEmail fromJson

Same two-phase strategy as Email, but Phase 1 extracts only `threadId`
(as `Opt[Id]`) instead of the full metadata group. The convenience header
and body phases are identical — delegating to the same shared helper procs.

```nim
func parsedEmailFromJson*(node: JsonNode): Result[ParsedEmail, ValidationError] =
  if node.kind != JObject:
    return err(validationError("ParsedEmail", "expected JObject", $node.kind))

  let threadId = ? parseOptId(node, "threadId")   # Opt[Id], null → Opt.none
  let convHeaders = ? parseConvenienceHeaders(node)
  let headers = ? parseRawHeaders(node)
  let bodyFields = ? parseBodyFields(node)
  # Phase 2: dynamic header discovery — identical to Email
  # ...
  ok(ParsedEmail(threadId: threadId, ...))
```

### 8.3. Shared Serde Helpers (D7)

Three shared helper procs extract common field groups for both `Email` and
`ParsedEmail`. Field declarations are duplicated (different types); parsing
logic is not (DRY where it matters most — boundary code).

**`parseConvenienceHeaders`:**

```nim
type ConvenienceHeaders = object
  ## Internal helper — not exported. Groups convenience header extraction
  ## results for both Email and ParsedEmail fromJson.
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

func parseConvenienceHeaders(node: JsonNode): Result[ConvenienceHeaders, ValidationError] =
  ## Extracts the 11 convenience header fields from a JSON object.
  ## Shared by emailFromJson and parsedEmailFromJson.
  # messageId, inReplyTo, references: Opt[seq[string]] via asMessageIds
  # sender, fromAddr, to, cc, bcc, replyTo: Opt[seq[EmailAddress]] via asAddresses
  # subject: Opt[string] via asText
  # sentAt: Opt[Date] via asDate
  # "from" key in JSON → fromAddr field
```

**`parseBodyFields`:**

```nim
type BodyFields = object
  bodyStructure*: EmailBodyPart
  bodyValues*: Table[PartId, EmailBodyValue]
  textBody*: seq[EmailBodyPart]
  htmlBody*: seq[EmailBodyPart]
  attachments*: seq[EmailBodyPart]
  hasAttachment*: bool
  preview*: string

func parseBodyFields(node: JsonNode): Result[BodyFields, ValidationError] =
  ## Extracts the 7 body fields from a JSON object.
  ## bodyValues keys parsed via parsePartIdFromServer (D19 — typed PartId key).
```

**`parseRawHeaders`:**

```nim
func parseRawHeaders(node: JsonNode): Result[seq[EmailHeader], ValidationError] =
  ## Extracts the ``headers`` field (seq[EmailHeader]) from a JSON object.
  ## Absent key → empty seq (not an error).
```

### 8.4. Email toJson / ParsedEmail toJson (D5)

Emit all domain fields always:

- `Opt.none` → `null`
- Empty `seq` → `[]`
- Empty `Table` → `{}`
- Dynamic header tables (`requestedHeaders`, `requestedHeadersAll`) are
  iterated; each entry emitted as a top-level `"header:Name:asForm"` key.
  Zero entries → zero keys naturally.

```nim
func toJson*(e: Email): JsonNode =
  var node = newJObject()

  # Metadata
  node["id"] = e.id.toJson()
  node["blobId"] = e.blobId.toJson()
  node["threadId"] = e.threadId.toJson()
  node["mailboxIds"] = e.mailboxIds.toJson()
  node["keywords"] = e.keywords.toJson()
  node["size"] = e.size.toJson()
  node["receivedAt"] = e.receivedAt.toJson()

  # Convenience headers — Opt.none → null
  node["messageId"] = e.messageId.toJsonOrNull()
  node["from"] = e.fromAddr.toJsonOrNull()    # fromAddr → "from" key
  # ... (remaining headers)

  # Body
  node["bodyStructure"] = e.bodyStructure.toJson()
  node["bodyValues"] = e.bodyValues.toJson()  # Table[PartId, EmailBodyValue]
  # ...

  # Dynamic headers — N top-level keys
  for hpk, val in e.requestedHeaders:
    node[hpk.toPropertyName()] = val.toJson()
  for hpk, vals in e.requestedHeadersAll:
    node[hpk.toPropertyName()] = vals.toJson()

  return node
```

**Domain state vs view state:** Dynamic headers are N top-level keys in JSON,
not a single `"requestedHeaders"` field. The `Table` is a domain-side
grouping; the wire format is flat.

### 8.5. bodyValues Table Key — PartId (D19)

`bodyValues` uses `Table[PartId, EmailBodyValue]` — typed key. "Newtype
everything that has meaning." `PartId` already has `hash` borrowed via
`defineStringDistinctOps`, so it works as a `Table` key. Consistent with
`MailboxIdSet` (`HashSet[Id]`, not `HashSet[string]`).

`fromJson` parses table keys via `parsePartIdFromServer` (lenient, per B15
convention). `toJson` emits keys via `$partId` (string conversion).

### 8.6. EmailComparator Serde (D8)

**toJson:**

```nim
func toJson*(c: EmailComparator): JsonNode =
  var node = newJObject()
  case c.kind
  of eckPlain:
    node["property"] = %($c.property)
  of eckKeyword:
    node["property"] = %($c.keywordProperty)
    node["keyword"] = %($c.keyword)
  for v in c.isAscending:
    node["isAscending"] = %v
  for v in c.collation:
    node["collation"] = %v
  return node
```

**fromJson:**

Synthesises the discriminant by inspecting the `property` name at the parse
boundary. If the property matches a `KeywordSortProperty` value, constructs
`eckKeyword` (requiring a `keyword` field). Otherwise, matches against
`PlainSortProperty`.

```nim
func emailComparatorFromJson*(node: JsonNode): Result[EmailComparator, ValidationError] =
  if node.kind != JObject:
    return err(validationError("EmailComparator", "expected JObject", $node.kind))
  let propStr = ? extractString(node, "property")
  # Try keyword sort properties first (require keyword field)
  for ksp in KeywordSortProperty:
    if $ksp == propStr:
      let kw = ? Keyword.fromJson(node, "keyword")
      return ok(keywordComparator(ksp, kw,
        isAscending = extractOptBool(node, "isAscending"),
        collation = extractOptString(node, "collation")))
  # Try plain sort properties
  for psp in PlainSortProperty:
    if $psp == propStr:
      return ok(plainComparator(psp,
        isAscending = extractOptBool(node, "isAscending"),
        collation = extractOptString(node, "collation")))
  err(validationError("EmailComparator", "unknown sort property", propStr))
```

### 8.7. EmailFilterCondition toJson

toJson only — no fromJson (B11 convention). Same pattern as
`MailboxFilterCondition.toJson` (Design B §5.2).

```nim
func toJson*(fc: EmailFilterCondition): JsonNode =
  var node = newJObject()
  # Simple Opt fields — omit when none
  for v in fc.inMailbox: node["inMailbox"] = v.toJson()
  for v in fc.inMailboxOtherThan:
    node["inMailboxOtherThan"] = toJsonArray(v)
  for v in fc.before: node["before"] = v.toJson()
  for v in fc.after: node["after"] = v.toJson()
  for v in fc.minSize: node["minSize"] = v.toJson()
  for v in fc.maxSize: node["maxSize"] = v.toJson()
  # Keyword fields — emit as string (Keyword → string via $)
  for v in fc.allInThreadHaveKeyword: node["allInThreadHaveKeyword"] = %($v)
  for v in fc.someInThreadHaveKeyword: node["someInThreadHaveKeyword"] = %($v)
  for v in fc.noneInThreadHaveKeyword: node["noneInThreadHaveKeyword"] = %($v)
  for v in fc.hasKeyword: node["hasKeyword"] = %($v)
  for v in fc.notKeyword: node["notKeyword"] = %($v)
  for v in fc.hasAttachment: node["hasAttachment"] = %v
  # Text search — string fields
  for v in fc.text: node["text"] = %v
  for v in fc.fromAddr: node["from"] = %v            # fromAddr → "from" key
  for v in fc.to: node["to"] = %v
  for v in fc.cc: node["cc"] = %v
  for v in fc.bcc: node["bcc"] = %v
  for v in fc.subject: node["subject"] = %v
  for v in fc.body: node["body"] = %v
  # Header filter — emit as 1-or-2 element array
  for v in fc.header:
    var arr = newJArray()
    arr.add(%v.name)
    for txt in v.value: arr.add(%txt)
    node["header"] = arr
  return node
```

### 8.8. EmailBodyFetchOptions toJson

```nim
func toJson*(opts: EmailBodyFetchOptions): JsonNode =
  ## Serialises body fetch options into request arguments.
  ## Maps BodyValueScope enum back to the three RFC booleans.
  var node = newJObject()
  for v in opts.bodyProperties:
    node["bodyProperties"] = toJsonArray(v)
  case opts.fetchBodyValues
  of bvsNone: discard                                  # all false — omit
  of bvsText: node["fetchTextBodyValues"] = %true
  of bvsHtml: node["fetchHTMLBodyValues"] = %true
  of bvsTextAndHtml:
    node["fetchTextBodyValues"] = %true
    node["fetchHTMLBodyValues"] = %true
  of bvsAll: node["fetchAllBodyValues"] = %true
  for v in opts.maxBodyValueBytes:
    node["maxBodyValueBytes"] = v.toJson()
  return node
```

No `fromJson` — body fetch options are request parameters, never returned by
the server.

### 8.9. SearchSnippet fromJson

```nim
func searchSnippetFromJson*(node: JsonNode): Result[SearchSnippet, ValidationError] =
  if node.kind != JObject:
    return err(validationError("SearchSnippet", "expected JObject", $node.kind))
  let emailId = ? Id.fromJson(node, "emailId")
  let subject = extractOptString(node, "subject")   # null → Opt.none
  let preview = extractOptString(node, "preview")
  ok(SearchSnippet(emailId: emailId, subject: subject, preview: preview))
```

### 8.10. SearchSnippetGetResponse fromJson

```nim
func searchSnippetGetResponseFromJson*(node: JsonNode):
    Result[SearchSnippetGetResponse, ValidationError] =
  if node.kind != JObject:
    return err(validationError("SearchSnippetGetResponse", "expected JObject", $node.kind))
  let accountId = ? AccountId.fromJson(node, "accountId")
  let list = ? parseJsonArray(node, "list", searchSnippetFromJson)
  let notFound = collapseNullToEmptySeq(node, "notFound", parseIdFromServer)
  ok(SearchSnippetGetResponse(accountId: accountId, list: list, notFound: notFound))
```

**`collapseNullToEmptySeq`:** Helper that parses `Id[]|null` — null or absent
→ `@[]`, present → parse each element. Shared by `SearchSnippetGetResponse`
and `EmailParseResponse`.

### 8.11. EmailParseResponse fromJson

```nim
func emailParseResponseFromJson*(node: JsonNode):
    Result[EmailParseResponse, ValidationError] =
  if node.kind != JObject:
    return err(validationError("EmailParseResponse", "expected JObject", $node.kind))
  let accountId = ? AccountId.fromJson(node, "accountId")
  # parsed: Id[Email]|null — null → empty Table
  let parsed = if node.hasKey("parsed") and node["parsed"].kind == JObject:
    ? parseIdKeyedTable(node["parsed"], parsedEmailFromJson)
  else:
    initTable[Id, ParsedEmail]()
  let notParseable = collapseNullToEmptySeq(node, "notParsable", parseIdFromServer)
  let notFound = collapseNullToEmptySeq(node, "notFound", parseIdFromServer)
  ok(EmailParseResponse(
    accountId: accountId, parsed: parsed,
    notParseable: notParseable, notFound: notFound))
```

**Note:** The RFC spells the field `"notParsable"` (one 'e'). The Nim field
uses `notParseable` (British English, per coding conventions), but the serde
layer reads from the RFC key `"notParsable"`.

---

## 9. Builders

### 9.1. Entity Registration

**Module:** `src/jmap_client/mail/mail_entities.nim` (extends existing
module from Designs A and B).

```nim
func methodNamespace*(T: typedesc[Email]): string = "Email"
func capabilityUri*(T: typedesc[Email]): string = "urn:ietf:params:jmap:mail"
registerJmapEntity(Email)
registerQueryableEntity(Email)
```

Email is registered with both `registerJmapEntity` and
`registerQueryableEntity`. The generic builders compile (`addGet[Email]`,
`addChanges[Email]`, `addQuery[Email]`), but consumers use the custom
overloads for methods with extra parameters.

### 9.2. addEmailGet

**Module:** `src/jmap_client/mail/mail_builders.nim`

```nim
func addEmailGet*(b: var RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): ResponseHandle[GetResponse[Email]]
```

- Adds `"urn:ietf:params:jmap:mail"` capability.
- Creates invocation with name `"Email/get"`.
- Standard `/get` parameters (`ids`, `properties`) plus body fetch options.
- `bodyFetchOptions` serialised via `toJson` and merged into the invocation
  arguments. `default(EmailBodyFetchOptions)` omits all body-fetch keys
  (correct RFC default).
- Returns `ResponseHandle[GetResponse[Email]]` — the standard generic
  response. Callers who need typed `Email` objects parse individual
  `JsonNode` entries from `GetResponse.list` via `emailFromJson`.

**`func` not `proc`:** No callback parameters. Unlike `addEmailQuery`
(which takes `filterConditionToJson`), `addEmailGet` has no proc parameters,
so `func` is appropriate.

### 9.3. Email/changes — Generic Builder (D17)

No custom builder. Email/changes is "a standard /changes method" (RFC §4.3)
with no extensions. Callers use `addChanges[Email]` directly.

Precedent: only entities with extensions get custom builders (Mailbox/changes
has `updatedProperties`). Thread uses generic `addChanges[Thread]` directly.
No wrapper for naming consistency — that would be ceremony without value.

### 9.4. addEmailQuery (D10)

**Module:** `src/jmap_client/mail/mail_builders.nim`

Email/query has three extensions beyond generic `/query`: (1) sort uses
`seq[EmailComparator]` instead of `seq[Comparator]`, (2) `collapseThreads:
bool`, and (3) the `collapseThreads` parameter affects query semantics. The
generic `addQuery` takes `Opt[seq[Comparator]]` — `EmailComparator` is a
different type, so generic `addQuery` cannot carry it without type erasure.

```nim
proc addEmailQuery*(b: var RequestBuilder,
    accountId: AccountId,
    filterConditionToJson:
      proc(c: EmailFilterCondition): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[EmailFilterCondition]] =
      Opt.none(Filter[EmailFilterCondition]),
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = false,
): ResponseHandle[QueryResponse[Email]]
```

- Adds `"urn:ietf:params:jmap:mail"` capability.
- Creates invocation with name `"Email/query"`.
- Serialises `collapseThreads` into request arguments alongside standard
  query parameters.
- `sort` serialised via `EmailComparator.toJson` (not `Comparator.toJson`).
- `proc` not `func` due to callback parameter (`filterConditionToJson`).
- Returns `ResponseHandle[QueryResponse[Email]]` — standard query response.

**Internal helper extraction:** The invocation-building logic currently inside
`addQuery` is extracted into an internal (non-exported) helper proc. Both
`addQuery[T, C]` and `addEmailQuery` delegate to this helper. This avoids
duplicating the filter serialisation, sort serialisation, and `QueryParams`
unpacking logic.

### 9.5. addEmailQueryChanges (D18)

**Module:** `src/jmap_client/mail/mail_builders.nim`

Parallel to D10. Email/queryChanges (RFC §4.5) extends standard
`/queryChanges` with `collapseThreads: bool`. Same structural incompatibility
as D10 — generic `addQueryChanges` cannot carry `EmailComparator`.

```nim
proc addEmailQueryChanges*(b: var RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filterConditionToJson:
      proc(c: EmailFilterCondition): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[EmailFilterCondition]] =
      Opt.none(Filter[EmailFilterCondition]),
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
    collapseThreads: bool = false,
): ResponseHandle[QueryChangesResponse[Email]]
```

- Adds `"urn:ietf:params:jmap:mail"` capability.
- Creates invocation with name `"Email/queryChanges"`.
- Delegates to the same extracted internal helper as `addEmailQuery`.
- `proc` not `func` due to callback parameter.

---

## 10. Custom Methods

### 10.1. addEmailParse (D11)

**Module:** `src/jmap_client/mail/mail_methods.nim` (extends existing module).

**RFC reference:** §4.9.

```nim
func addEmailParse*(b: var RequestBuilder,
    accountId: AccountId,
    blobIds: seq[Id],
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): ResponseHandle[EmailParseResponse]
```

- Adds `"urn:ietf:params:jmap:mail"` capability.
- Creates invocation with name `"Email/parse"`.
- `blobIds` is `seq[Id]` (not `Referencable` — Email/parse does not support
  result references on `blobIds`).
- `bodyFetchOptions` shared with `addEmailGet` (D9).
- Returns `ResponseHandle[EmailParseResponse]` — dedicated typed response
  (D11). Callers receive `Table[Id, ParsedEmail]` — fully typed, no second
  parsing step.
- `func` — no callback parameters.

### 10.2. addSearchSnippetGet (D12)

**Module:** `src/jmap_client/mail/mail_methods.nim`

**RFC reference:** §5.1.

```nim
proc addSearchSnippetGet*(b: var RequestBuilder,
    accountId: AccountId,
    filterConditionToJson:
      proc(c: EmailFilterCondition): JsonNode {.noSideEffect, raises: [].},
    filter: Filter[EmailFilterCondition],
    firstEmailId: Id,
    restEmailIds: seq[Id] = @[],
): ResponseHandle[SearchSnippetGetResponse]
```

- Adds `"urn:ietf:params:jmap:mail"` capability.
- Creates invocation with name `"SearchSnippet/get"`.
- `filter` is **required** (not `Opt`) per architecture doc — search snippets
  are meaningless without a search filter.
- `emailIds` non-emptiness enforced structurally via the cons-cell pattern:
  `firstEmailId: Id, restEmailIds: seq[Id] = @[]`. Every call provides at
  least one email id. The builder concatenates `@[firstEmailId] &
  restEmailIds` internally.
- Builder is total: no `Result`, no validation. Every input combination valid.
- `proc` not `func` due to callback parameter.

**Cons-cell pattern (D12):** Encodes `NonEmpty` without a wrapper type.
Appropriate when the constraint is local to one call site. The caller writes
`addSearchSnippetGet(b, acct, toJson, filter, emailId)` for a single id, or
`addSearchSnippetGet(b, acct, toJson, filter, firstId, @[id2, id3])` for
multiple. Both are valid by construction.

---

## 11. Module Organisation

### 11.1. File Layout (D14)

All new files live under `src/jmap_client/mail/`. Organisation follows domain
cohesion: entity + its method parameter types together (parallels
`mailbox.nim` which co-locates Mailbox + MailboxCreate + MailboxRights).

| File | Types | Rationale |
|------|-------|-----------|
| `email.nim` | `Email`, `ParsedEmail`, `PlainSortProperty`, `KeywordSortProperty`, `EmailComparator`, `BodyValueScope`, `EmailBodyFetchOptions` | Entity + method parameter types, parallels `mailbox.nim` |
| `snippet.nim` | `SearchSnippet` | Standalone per RFC §5 |
| `mail_filters.nim` | `EmailFilterCondition`, `EmailHeaderFilter` (adds to existing) | Filter conditions grouped by concern, parallels existing `MailboxFilterCondition` |
| `serde_email.nim` | `emailFromJson`, `parsedEmailFromJson`, `emailComparatorFromJson`, shared helpers | All Email/ParsedEmail serde + shared helpers (D7) |
| `serde_snippet.nim` | `searchSnippetFromJson` | SearchSnippet serde |
| `serde_mail_filters.nim` | `EmailFilterCondition.toJson` (adds to existing) | Filter serde grouped with existing `MailboxFilterCondition.toJson` |
| `mail_entities.nim` | Entity registration for Email (adds to existing) | Extends existing module |
| `mail_builders.nim` | `addEmailGet`, `addEmailQuery`, `addEmailQueryChanges` (adds to existing) | Standard method builders, parallels existing Mailbox builders |
| `mail_methods.nim` | `addEmailParse`, `addSearchSnippetGet`, `EmailParseResponse`, `SearchSnippetGetResponse` (adds to existing) | Custom methods + bespoke response types |

### 11.2. Dependency Flow

```
email.nim ──→ keyword.nim (KeywordSet)
          ──→ addresses.nim (EmailAddress)
          ──→ headers.nim (HeaderPropertyKey, HeaderValue, EmailHeader)
          ──→ body.nim (EmailBodyPart, EmailBodyValue, PartId)
          ──→ mailbox.nim (MailboxIdSet)

snippet.nim ──→ (core types only — Id, Opt)

mail_filters.nim ──→ keyword.nim (Keyword)
                 ──→ (core types — Id, UnsignedInt, UTCDate)

serde_email.nim ──→ email.nim
                ──→ serde_addresses.nim (EmailAddress fromJson)
                ──→ serde_headers.nim (HeaderValue fromJson)
                ──→ serde_body.nim (EmailBodyPart/EmailBodyValue fromJson)
                ──→ serde_keyword.nim (KeywordSet fromJson)
                ──→ serde_mailbox.nim (MailboxIdSet fromJson)

serde_snippet.nim ──→ snippet.nim

mail_builders.nim ──→ email.nim (EmailComparator, EmailBodyFetchOptions)
                  ──→ mail_filters.nim (EmailFilterCondition)
                  ──→ serde_email.nim (EmailComparator.toJson, EmailBodyFetchOptions.toJson)
                  ──→ builder.nim (internal helper, RequestBuilder)

mail_methods.nim ──→ email.nim (ParsedEmail)
                 ──→ snippet.nim (SearchSnippet)
                 ──→ serde_email.nim (parsedEmailFromJson)
                 ──→ serde_snippet.nim (searchSnippetFromJson)
```

### 11.3. Re-Export Hub Updates

**`types.nim`** — add:

```nim
import ./email
import ./snippet
export email
export snippet
```

**`serialisation.nim`** — add:

```nim
import ./serde_email
import ./serde_snippet
export serde_email
export serde_snippet
```

---

## 12. Test Specification

**136 scenarios** across 14 subsections: example-based unit and serde tests
(§12.1–12.10), adversarial/red-team tests (§12.11), property-based tests
(§12.12), integration tests (§12.13), and test infrastructure (§12.14).

**Design principles applied to the test spec itself:**

- **Remove trivia.** Total constructors are correct by construction — the type
  system guarantees them. Old scenarios 23–25 (trivially testing that
  `plainComparator(pspReceivedAt)` produces `eckPlain`) are removed; the
  toJson/fromJson tests exercise constructors implicitly.
- **Merge overlap.** Scenarios that test the same code path with only cosmetic
  differences are consolidated (e.g., convenience header null and present in
  one scenario; `addEmailGet` name + capability + default body options in one).
- **Test routing, not parsing.** Lower-level parsers (`HeaderPropertyKey`,
  `EmailBodyValue`, `PartId`, `Keyword`) are exhaustively tested in Part C
  tests. Email/ParsedEmail tests verify only that Phase 1 and Phase 2 *route*
  correctly to those parsers.
- **Adversarial coverage.** Boundary exploitation, injection, type confusion,
  and spelling mismatch tests — absent from the original spec.
- **Property-based coverage.** Round-trip, structural invariant, and totality
  properties that subsume groups of example tests.
- **Integration coverage.** Cross-component tests verifying shared helper
  parity, builder–serde chains, and round-trip preservation.

### 12.1. Email Smart Constructor (scenarios 1–2)

| # | Scenario | Expected |
|---|----------|----------|
| 1 | `parseEmail` with non-empty `mailboxIds` | `ok(Email)` |
| 2 | `parseEmail` with empty `mailboxIds` | `err(ValidationError)` with `typeName = "Email"` |

### 12.2. Email fromJson (scenarios 3–17)

| # | Scenario | Expected |
|---|----------|----------|
| 3 | `emailFromJson` non-JObject input (JArray, JString, JNull) | `err` referencing "expected JObject" |
| 4 | `emailFromJson` complete valid JSON (all 28 fields populated) | `ok(Email)`, all fields correct — golden path |
| 5 | `emailFromJson` with absent `keywords` key | `ok`, `keywords` = empty `KeywordSet` (RFC default) |
| 6 | `emailFromJson` convenience headers: null → `Opt.none`, present → `Opt.some(...)` (combined) | both cases pass in single test |
| 7 | `emailFromJson` `"from"` JSON key → `fromAddr` field | `ok`, `fromAddr = Opt.some(...)` |
| 8 | `emailFromJson` with `header:Subject:asText` dynamic property | routed to `requestedHeaders` table |
| 9 | `emailFromJson` with `header:From:asAddresses:all` dynamic property | routed to `requestedHeadersAll` table |
| 10 | `emailFromJson` with both non-`:all` and `:all` dynamic headers in same JSON | both tables populated simultaneously |
| 11 | `emailFromJson` with unknown non-`header:` key → silently ignored | pass (Postel's law) |
| 12 | `emailFromJson` with `bodyValues` keyed by `PartId` | `Table[PartId, EmailBodyValue]` correctly populated |
| 13 | `emailFromJson` missing required metadata field (each of id, blobId, threadId, mailboxIds, size, receivedAt individually) | `err` for each |
| 14 | `emailFromJson` convenience header with wrong JSON type (e.g. `"from": 42`) | `err` from `parseConvenienceHeaders` |
| 15 | `emailFromJson` malformed dynamic header key (`"header:"`, `"header:From:asUnknown"`, too many segments) | `err` propagated from `parseHeaderPropertyName` |
| 16 | `emailFromJson` `mailboxIds` as JNull (unlike `keywords`, no default) | `err` from `MailboxIdSet.fromJson` |
| 17 | `emailFromJson` `keywords` present but wrong JSON type (JArray instead of JObject) | `err` from `KeywordSet.fromJson` |

**Rationale for scenario 13 expansion:** The original spec tested "a missing
metadata field" without specifying which. Each of the 6 non-defaultable
metadata fields exercises a different direct-lookup error path. `keywords` is
excluded because it defaults to empty (scenario 5).

### 12.3. Email toJson (scenarios 18–23)

| # | Scenario | Expected |
|---|----------|----------|
| 18 | `Email.toJson` `Opt.none` convenience headers → `null` | pass |
| 19 | `Email.toJson` `fromAddr` field → `"from"` key in JSON | pass |
| 20 | `Email.toJson` `requestedHeaders` entries emitted as top-level keys | `"header:Subject:asText": "..."` |
| 21 | `Email.toJson` `requestedHeadersAll` entries emitted as top-level keys with `:all` suffix | `"header:From:asAddresses:all": [...]` |
| 22 | `Email.toJson` empty `requestedHeaders` + empty `requestedHeadersAll` → no extra keys | JSON key count = standard fields only |
| 23 | `Email.toJson` empty `seq` → `[]`, empty `Table` → `{}` (D5 contract) | `textBody: []`, `bodyValues: {}` |

**Rationale for scenario 23:** Decision D5 specifies "emit all domain fields
always." This test verifies the three empty-value emission paths: `Opt.none` →
null (scenario 18), empty seq → `[]`, and empty Table → `{}`.

### 12.4. ParsedEmail (scenarios 24–33)

| # | Scenario | Expected |
|---|----------|----------|
| 24 | `parsedEmailFromJson` valid JSON with `threadId: null` | `ok`, `threadId = Opt.none` |
| 25 | `parsedEmailFromJson` valid JSON with `threadId` present | `ok`, `threadId = Opt.some(id)` |
| 26 | `parsedEmailFromJson` absent metadata fields (id, blobId, mailboxIds, keywords, size, receivedAt) in JSON | `ok` — ParsedEmail does not require them |
| 27 | `parsedEmailFromJson` `"from"` JSON key → `fromAddr` field | `ok`, shared `parseConvenienceHeaders` applies same mapping |
| 28 | `parsedEmailFromJson` with dynamic headers | correctly routed to both tables |
| 29 | `parsedEmailFromJson` `threadId` as JInt (wrong type) | `err(ValidationError)` |
| 30 | `parsedEmailFromJson` server sends absent-by-design metadata fields (id, blobId, mailboxIds, etc.) present in JSON | `ok`, extra fields silently ignored (Postel's law) |
| 31 | `ParsedEmail.toJson` does not emit id, blobId, mailboxIds, keywords, size, receivedAt; DOES emit threadId | verified absent/present |
| 32 | `ParsedEmail.toJson` `fromAddr` field → `"from"` key | pass |
| 33 | `ParsedEmail` round-trip: `parsedEmailFromJson(pe.toJson()) == pe` for all fields including dynamic headers | identity preserved |

**Rationale for scenarios 26 vs 30:** These test opposite conditions. Scenario
26 verifies that ParsedEmail works without metadata (expected case — the type
does not require them). Scenario 30 verifies that ParsedEmail works with
unexpected metadata (Postel's law — a server may return full Email properties
for a parse result).

### 12.5. EmailComparator (scenarios 34–45)

Trivial constructor tests (old 23–25) removed. Total constructors are correct
by construction — `PlainSortProperty` constrains the value set, `Keyword` is
validated at construction time. The toJson and fromJson tests exercise
constructors implicitly.

| # | Scenario | Expected |
|---|----------|----------|
| 34 | `toJson` plain comparator → `{"property": "receivedAt"}` | pass |
| 35 | `toJson` keyword comparator → `{"property": "hasKeyword", "keyword": "$flagged"}` | pass |
| 36 | `toJson` omits `isAscending` and `collation` when `Opt.none` | neither key present |
| 37 | `toJson` keyword comparator with `isAscending` and `collation` both set | all four keys present |
| 38 | `emailComparatorFromJson` plain property → `ok(eckPlain)` | pass |
| 39 | `emailComparatorFromJson` `hasKeyword` with valid keyword → `ok(eckKeyword)` | pass |
| 40 | `emailComparatorFromJson` `allInThreadHaveKeyword` with valid keyword → `ok(eckKeyword)` | pass |
| 41 | `emailComparatorFromJson` `someInThreadHaveKeyword` with valid keyword → `ok(eckKeyword)` | pass |
| 42 | `emailComparatorFromJson` keyword property without `keyword` field | `err` |
| 43 | `emailComparatorFromJson` unknown property string | `err` |
| 44 | `emailComparatorFromJson` extracts `isAscending` correctly | `Opt.some(false)` round-trips |
| 45 | `emailComparatorFromJson` extracts `collation` correctly | `Opt.some("i;unicode-casemap")` round-trips |

**Rationale for scenarios 39–41:** The serde layer (§8.6) iterates over all
`KeywordSortProperty` variants to match the `property` string. Testing only
one variant leaves iteration bugs undetected. All three keyword sort variants
are explicitly tested for regression detection.

### 12.6. EmailBodyFetchOptions (scenarios 46–52)

| # | Scenario | Expected |
|---|----------|----------|
| 46 | `default(EmailBodyFetchOptions).toJson` → `{}` (all defaults) | pass |
| 47 | `bvsText` → `{"fetchTextBodyValues": true}` | pass |
| 48 | `bvsHtml` → `{"fetchHTMLBodyValues": true}` | pass |
| 49 | `bvsTextAndHtml` → both `fetchTextBodyValues` and `fetchHTMLBodyValues` true | pass |
| 50 | `bvsAll` → `{"fetchAllBodyValues": true}` | pass |
| 51 | `maxBodyValueBytes` present → emitted | pass |
| 52 | `bodyProperties = Opt.some(@[...])` → emitted as JSON array | pass |

### 12.7. EmailHeaderFilter (scenarios 53–54)

| # | Scenario | Expected |
|---|----------|----------|
| 53 | `parseEmailHeaderFilter("Subject")` | `ok`, `name == "Subject"` |
| 54 | `parseEmailHeaderFilter("")` | `err(ValidationError)` "header name must not be empty" |

### 12.8. EmailFilterCondition (scenarios 55–63)

| # | Scenario | Expected |
|---|----------|----------|
| 55 | `toJson` all fields none → `{}` | pass |
| 56 | `toJson` `inMailbox = Opt.some(id)` → `{"inMailbox": "..."}` | pass |
| 57 | `toJson` `hasKeyword = Opt.some(kwSeen)` → `{"hasKeyword": "$seen"}` | pass |
| 58 | `toJson` all 5 keyword fields (`hasKeyword`, `notKeyword`, `allInThreadHaveKeyword`, `someInThreadHaveKeyword`, `noneInThreadHaveKeyword`) with explicit `$keyword` value verification | all 5 keys present with correct `$keyword` string values |
| 59 | `toJson` `fromAddr` → `"from"` key in JSON | pass |
| 60 | `toJson` `header` name only → `["Name"]`; name + value → `["Name", "value"]` | both forms correct |
| 61 | `toJson` mixed filter (multiple fields from different groups) | structural match — correct keys, correct types |
| 62 | `toJson` `inMailboxOtherThan` with empty seq → `{"inMailboxOtherThan": []}` | pass (vacuous but not illegal) |
| 63 | `toJson` all 20 fields populated simultaneously | JSON object with 20 keys, all correct types |

**Rationale for scenario 58:** Keyword filter fields use typed `Keyword`
serialised via `$`. Testing all five fields simultaneously verifies the
`$keyword` string conversion for each — catching name/key transposition bugs
that scenario 63 (all 20 fields) checks structurally but not by value.

**Rationale for scenario 63:** With 20 fields, a key-name typo or wrong
serialisation for a single field is easy to introduce. The complete-population
test catches regressions that single-field tests miss.

### 12.9. SearchSnippet and Response Types (scenarios 64–74)

| # | Scenario | Expected |
|---|----------|----------|
| 64 | `searchSnippetFromJson` valid | `ok(SearchSnippet)`, all fields populated |
| 65 | `searchSnippetFromJson` `subject`/`preview` null | `ok`, both `Opt.none` |
| 66 | `searchSnippetGetResponseFromJson` with `notFound: null` | `ok`, `notFound` = empty seq |
| 67 | `searchSnippetGetResponseFromJson` with `notFound: [...]` | `ok`, `notFound` = parsed seq |
| 68 | `searchSnippetGetResponseFromJson` `notFound` key absent (not null, absent) | `ok`, `notFound` = empty seq |
| 69 | `emailParseResponseFromJson` with `parsed: null` | `ok`, `parsed` = empty `Table` |
| 70 | `emailParseResponseFromJson` with parsed entries | `ok`, `Table[Id, ParsedEmail]` populated |
| 71 | `emailParseResponseFromJson` `parsed` key absent (not null, absent) | `ok`, `parsed` = empty `Table` |
| 72 | `emailParseResponseFromJson` reads `"notParsable"` key (RFC spelling) | `notParseable` field populated |
| 73 | `emailParseResponseFromJson` `"notParseable"` key (Nim spelling) NOT accepted as alias | `notParseable` field stays empty — only RFC key `"notParsable"` is read |
| 74 | `searchSnippetGetResponseFromJson` / `emailParseResponseFromJson` non-JObject input | `err` referencing "expected JObject" |

**Rationale for scenario 73:** The design document (§8.11) explicitly documents
the spelling mismatch between the RFC key `"notParsable"` and the Nim field
`notParseable`. This test verifies that the serde layer reads ONLY the RFC key,
preventing silent data loss if the wrong key is used.

### 12.10. Builders (scenarios 75–90)

| # | Scenario | Expected |
|---|----------|----------|
| 75 | `addEmailGet` produces `"Email/get"`, adds `urn:ietf:params:jmap:mail` capability, default body options omits body keys | all three checks pass |
| 76 | `addEmailGet` with non-default body fetch options includes body keys in args | body keys present |
| 77 | `addChanges[Email]` produces `"Email/changes"` | pass |
| 78 | `addEmailQuery` produces `"Email/query"` | pass |
| 79 | `addEmailQuery` with `collapseThreads = true` includes parameter in args | pass |
| 80 | `addEmailQuery` with `collapseThreads = false` (default) — verify emission/omission behaviour | consistent with RFC expectation |
| 81 | `addEmailQuery` with `EmailComparator` sort serialises correctly | `sort` array in args matches `EmailComparator.toJson` |
| 82 | `addEmailQueryChanges` produces `"Email/queryChanges"` | pass |
| 83 | `addEmailQueryChanges` with `collapseThreads` and `EmailComparator` sort parameters | both serialised in args |
| 84 | `addEmailParse` produces `"Email/parse"`, adds mail capability | pass |
| 85 | `addEmailParse` with body fetch options includes body keys in args | body keys present, matching `addEmailGet` pattern |
| 86 | `addSearchSnippetGet` produces `"SearchSnippet/get"` | pass |
| 87 | `addSearchSnippetGet` with single email id → `emailIds: [id]` | pass |
| 88 | `addSearchSnippetGet` with cons-cell ids → `emailIds: [first, rest...]` | pass |
| 89 | `addSearchSnippetGet` `filter` required (not Opt) — `assertNotCompiles` | compile-time check |
| 90 | `addSearchSnippetGet` serialises `filter` in request args | filter structure present in args |

**Rationale for scenarios 75, 84 merges:** Builder basics (invocation name +
capability + default behaviour) are low-information tests. Consolidating them
into single test blocks reduces noise while preserving coverage.

### 12.11. Adversarial Tests (scenarios 91–123)

Red-team scenarios targeting boundary exploitation, injection, type confusion,
semantic ambiguity, and cross-field contradiction. These test the defence of
the serde boundary against malformed, ambiguous, or adversarial server
responses and client inputs.

**Two-phase parsing boundary (emailFromJson Phase 1 vs Phase 2):**

| # | Scenario | Expected |
|---|----------|----------|
| 91 | Both `"from"` (populated and as JNull) and `"header:From:asAddresses"` keys present in JSON | `ok` — Phase 1 routes `"from"` to `fromAddr` (populated or `Opt.none`); Phase 2 routes `"header:From:asAddresses"` to `requestedHeaders` — no interference between phases regardless of null state |
| 92 | 100 dynamic `header:*` keys in single JSON object | `ok` — all routed to correct tables — stress test Phase 2 iteration |

**Dynamic header injection:**

| # | Scenario | Expected |
|---|----------|----------|
| 93 | `"header:"` key (empty header name after colon) | `err` from `parseHeaderPropertyName` — empty name |
| 94 | `"header:From:asAddresses:all:extra"` (5 colon-separated segments) | `err` — too many segments |
| 95 | `"header:From:asUnknown"` (invalid form name) | `err` from `parseHeaderPropertyName` — unknown form |
| 96 | `"header"` key (no trailing colon — not `"header:"`) | silently ignored — `startsWith("header:")` does not match |

**EmailComparator discriminant synthesis:**

| # | Scenario | Expected |
|---|----------|----------|
| 97 | `emailComparatorFromJson` with `property: "received_At"` (underscore) | `err` — `$enum` comparison is NOT `nimIdentNormalize` |
| 98 | `emailComparatorFromJson` with `property: "RECEIVERAT"` (wrong case) | `err` — exact string match, case-sensitive |
| 99 | `emailComparatorFromJson` with `property: " receivedAt"` (leading whitespace) | `err` — no whitespace stripping |
| 100 | `emailComparatorFromJson` with `property: "hasKeyword"` and `keyword: ""` (empty string) | `err` from `Keyword.fromJson` — empty keyword |
| 101 | `emailComparatorFromJson` with `property: "receivedAt"` and spurious `keyword` field present | `ok(eckPlain)` — `keyword` field silently ignored on plain branch |
| 102 | `emailComparatorFromJson` with `property` field entirely missing | `err` — missing discriminant |
| 103 | `emailComparatorFromJson` with `property: null` (JNull instead of JString) | `err` from `extractString` |

**EmailHeaderFilter adversarial:**

| # | Scenario | Expected |
|---|----------|----------|
| 104 | `parseEmailHeaderFilter` name containing `":"` (colon) | `ok` — colon is valid in RFC 5322 header names |
| 105 | `parseEmailHeaderFilter` name containing `\x00` (NUL byte) | `ok` — only empty string is rejected; documents FFI truncation risk |
| 106 | `EmailFilterCondition.toJson` header filter with value `""` (empty string) | `["Name", ""]` — 2-element array, distinct from absent value (1-element) |

**Table[PartId, EmailBodyValue] adversarial:**

| # | Scenario | Expected |
|---|----------|----------|
| 107 | `emailFromJson` `bodyValues` with duplicate PartId keys in raw JSON | `ok` — last-wins semantics (std/json `OrderedTable` behaviour) |
| 108 | `emailFromJson` `bodyValues` with empty-string PartId key `""` | `err` from `parsePartIdFromServer` — empty string rejection |

**EmailFilterCondition structural edge cases:**

| # | Scenario | Expected |
|---|----------|----------|
| 109 | `toJson` with `minSize = Opt.some(0)` and `maxSize = Opt.some(0)` (contradictory) | both keys emitted — filter does not validate temporal/size consistency |
| 110 | `toJson` header filter with name containing `":"` | `["Na:me"]` — colon preserved in first array element |

**Response type adversarial:**

| # | Scenario | Expected |
|---|----------|----------|
| 111 | `searchSnippetGetResponseFromJson` with `list: null` (JNull for required field) | `err(ValidationError)` — `list` is required, not nullable |
| 112 | `searchSnippetFromJson` with `subject: "<mark>XSS</mark><script>alert(1)</script>"` | `ok` — HTML content preserved verbatim; library does not sanitise |
| 113 | `searchSnippetFromJson` with extra unknown field in JSON | `ok` — extra field silently ignored (Postel's law, forward compatibility) |
| 114 | `emailFromJson` with all 28 fields present as wrong JSON types (JInt for every string field) | `err` on first failing field — never panics, never crashes |

**Recursive structure and resource stress:**

| # | Scenario | Expected |
|---|----------|----------|
| 115 | `emailFromJson` with 50-level nested multipart `bodyStructure` (recursive MIME tree) | `ok(Email)` — parser handles recursive depth gracefully; never stack overflow |
| 116 | Dynamic header key with Cyrillic homoglyph prefix (`"һeader:Subject:asText"` with U+04BB) alongside real `"header:Subject:asText"` | `ok` — Cyrillic key silently ignored (`startsWith("header:")` byte-level match fails); real key routed to `requestedHeaders` |
| 117 | `emailFromJson` with `size` at `2^53-1` (max safe JSON integer / `UnsignedInt` max) | `ok(Email)` with `size` value preserved exactly — no overflow or truncation |

**Cross-field semantic contradictions:**

| # | Scenario | Expected |
|---|----------|----------|
| 118 | Both `"header:From:asText"` and `"header:From:asAddresses"` (same header name, different form) in single JSON | `ok` — both routed to `requestedHeaders` under distinct `HeaderPropertyKey` keys (form is part of key identity) |
| 119 | `emailFromJson` with `bodyValues` entry having `isTruncated: true` AND `isEncodingProblem: true` AND `value: ""` | `ok(Email)` — all flag combinations valid; no mutual exclusivity validation |
| 120 | `emailFromJson` with `keywords: {"$Draft": true}` but `mailboxIds` pointing to non-Draft mailbox | `ok(Email)` — keyword/mailbox consistency not validated at serde layer (Postel's law) |
| 121 | `emailFromJson` with non-empty `attachments` list but `hasAttachment: false` | `ok(Email)` — semantic contradiction preserved; no cross-field validation |
| 122 | `EmailFilterCondition.toJson` with `before` date earlier than `after` date (logically impossible range) | both keys emitted — filter does not validate temporal consistency |
| 123 | `searchSnippetGetResponseFromJson` with snippet referencing `emailId` not in any Email result set | `ok(SearchSnippetGetResponse)` — referential integrity not validated at serde layer |

### 12.12. Property-Based Tests (scenarios 124–131)

Property-based tests use fixed-seed generators (`mproperty.nim` infrastructure)
with edge-biased early trials. They supplement, not replace, example-based
tests — the example tests serve as documentation, the property tests probe the
input space.

| # | Property | Generator | Trials |
|---|----------|-----------|--------|
| 124 | **EmailComparator round-trip:** `emailComparatorFromJson(ec.toJson()) == ec` for any valid `EmailComparator` | `genEmailComparator` — uniform over `eckPlain`/`eckKeyword` branches, random optional fields | `DefaultTrials` (500) |
| 125 | **EmailBodyFetchOptions structural:** `BodyValueScope` variant determines exactly which `fetch*BodyValues` keys appear in `toJson` output | `genEmailBodyFetchOptions` — uniform over 5 `BodyValueScope` variants, random optional fields | `QuickTrials` (200) |
| 126 | **EmailFilterCondition field-count:** `fc.toJson().len == count of Opt.some fields in fc` | `genEmailFilterCondition` — early-biased: trial 0 = all-none, trial 1 = all-some, remaining trials each of 20 fields independently 30% some / 70% none | `DefaultTrials` (500) |
| 127 | **Totality — emailFromJson:** never crashes (returns `ok` or `err`) on arbitrary `JsonNode` input | `genArbitraryJsonNode(rng, maxDepth=3)` | `DefaultTrials` (500) |
| 128 | **Totality — parsedEmailFromJson:** never crashes on arbitrary `JsonNode` input | `genArbitraryJsonNode(rng, maxDepth=3)` | `DefaultTrials` (500) |
| 129 | **Totality — emailComparatorFromJson:** never crashes on arbitrary `JsonNode` input | `genArbitraryJsonNode(rng, maxDepth=2)` | `DefaultTrials` (500) |
| 130 | **Email round-trip:** `emailFromJson(e.toJson()) == e` for any valid `Email` including dynamic headers in both tables | `genEmail` — composes `genConvenienceHeaders`, `genBodyFields`, `genMailboxIdSet`, `genKeywordSet`, existing generators | `ThoroughTrials` (2000) |
| 131 | **ParsedEmail round-trip:** `parsedEmailFromJson(pe.toJson()) == pe` for any valid `ParsedEmail` | `genParsedEmail` — composes shared helpers from `genEmail` minus 6 metadata fields, `threadId` 50/50 some/none | `ThoroughTrials` (2000) |

**Rationale:** The totality properties (127–129) are the highest-value property
tests. They guarantee that no server response — no matter how malformed — can
crash the client's parsing layer. Arbitrary `JsonNode` generators include
wrong types, deep nesting, empty objects, null values, and numeric edge cases.
The round-trip properties (130–131) verify that no field is silently lost or
corrupted through the serialisation boundary for the two most complex types.

**Rationale for scenario 126 early-bias:** With 20 independent binary fields at
30% `some` rate, 500 random trials cover ~0.05% of the 2^20 combination space.
Edge cases (all-none producing `{}`, all-some producing all 20 keys) have
probabilities < 0.1% per trial. Early-biasing trials 0 and 1 guarantees
these critical extremes are always tested.

### 12.13. Integration Tests (scenarios 132–136)

Cross-component tests that verify interactions between types, shared helpers,
and the builder–serde chain.

| # | Scenario | Scope |
|---|----------|-------|
| 132 | **Shared helper parity:** identical JSON (convenience headers + body + dynamic headers) fed to both `emailFromJson` and `parsedEmailFromJson` → shared fields produce identical results | serde helpers: `parseConvenienceHeaders`, `parseBodyFields`, Phase 2 routing |
| 133 | **Email round-trip:** `emailFromJson(email.toJson()) == email` for a fully-populated Email including dynamic headers in both tables | full `emailFromJson` + `Email.toJson` |
| 134 | **Dynamic header Phase 2 round-trip:** JSON with both `:all` and non-`:all` `header:*` keys → `emailFromJson` → `Email.toJson` → dynamic header keys preserved with correct names and values | Phase 2 routing → toJson dynamic header emission |
| 135 | **Builder body fetch options parity:** `addEmailGet` and `addEmailParse` with identical non-default `EmailBodyFetchOptions` → produce identical body-related keys in request args | builder serde consistency |
| 136 | **Builder–filter chain:** `addEmailQuery` with non-trivial `EmailFilterCondition` → serialised filter in request args matches `EmailFilterCondition.toJson` output | builder → filter serde chain |

### 12.14. Test Infrastructure

**Test file organisation:** All new files under `tests/` following established
naming conventions (t-prefix, domain-cohesive grouping).

| File | Scenarios | Rationale |
|------|-----------|-----------|
| `tests/unit/mail/temail.nim` | 1–2 | Smart constructor tests. Parallels `tmailbox.nim`. |
| `tests/serde/mail/tserde_email.nim` | 3–45 | Email, ParsedEmail, EmailComparator serde. All source in `serde_email.nim`. |
| `tests/serde/mail/tserde_snippet.nim` | 64–74 | SearchSnippet + response types. Parallels `tserde_vacation.nim`. |
| `tests/serde/mail/tserde_mail_filters.nim` (extend) | 53–63 | EmailFilterCondition + EmailHeaderFilter. Appended after existing `MailboxFilterCondition` tests. |
| `tests/protocol/tmail_builders.nim` (extend) | 75–83 | `addEmailGet`, `addEmailQuery`, `addEmailQueryChanges`. Appended after existing Mailbox builders. |
| `tests/protocol/tmail_methods.nim` (extend) | 84–90 | `addEmailParse`, `addSearchSnippetGet`. Appended after existing VacationResponse tests. |
| `tests/protocol/tmail_entities.nim` (extend) | — | Entity registration: `methodNamespace(Email) == "Email"`, `registerQueryableEntity` compiles. |
| `tests/serde/mail/tserde_email_adversarial.nim` | 91–123 | Adversarial tests. Parallels `tserde_adversarial.nim` for core types. |
| `tests/property/tprop_mail_d.nim` | 124–131 | Property tests. Parallels `tprop_mail_c.nim`. |
| `tests/serde/mail/tserde_email_integration.nim` | 132–136 | Integration tests. Cross-component verification. |

**New fixture factories** (add to `tests/mfixtures.nim`):

| Function | Returns | Purpose |
|----------|---------|---------|
| `makeEmail()` | `Email` | Minimal valid Email (non-empty `mailboxIds`, empty keywords, default body). Satisfies `parseEmail`. |
| `makeParsedEmail()` | `ParsedEmail` | Minimal ParsedEmail (`threadId = Opt.none`). |
| `makeEmailComparator()` | `EmailComparator` | Plain comparator for builder tests. |
| `makeKeywordComparator()` | `EmailComparator` | Keyword comparator for builder tests. |
| `makeEmailBodyFetchOptions()` | `EmailBodyFetchOptions` | Default body fetch options. |
| `makeEmailFilterCondition()` | `EmailFilterCondition` | All-none filter for toJson baseline. |
| `makeSearchSnippet()` | `SearchSnippet` | Minimal valid SearchSnippet. |
| `makeEmailJson()` | `JsonNode` | Golden Email JSON with all 28 fields. Derived from `makeEmail().toJson()`. Round-trip reference. |
| `makeParsedEmailJson()` | `JsonNode` | Valid ParsedEmail JSON without metadata. Derived from `makeParsedEmail().toJson()`. |
| `makeSearchSnippetJson()` | `JsonNode` | Valid SearchSnippet JSON. |
| `makeSearchSnippetGetResponseJson()` | `JsonNode` | Valid `SearchSnippetGetResponse` JSON. |
| `makeEmailParseResponseJson()` | `JsonNode` | Valid `EmailParseResponse` JSON. |

JSON fixtures for typed objects (`makeEmailJson`, `makeParsedEmailJson`) are
derived from type factories via `toJson()` rather than hand-crafted JSON
literals. This ensures the golden JSON always reflects the current type
definition. Hand-crafted JSON is reserved for adversarial tests requiring
specific malformations (wrong types, missing fields, injection payloads).

**Equality helpers** (add to `tests/mfixtures.nim`):

| Function | Purpose |
|----------|---------|
| `emailEq(a, b: Email): bool` | Field-by-field equality. Handles `Table`, `seq`, case-object `HeaderValue`. Follows `sessionEq` pattern. |
| `parsedEmailEq(a, b: ParsedEmail): bool` | Same pattern as `emailEq`. Delegates to common field comparisons for shared groups. |
| `emailComparatorEq(a, b: EmailComparator): bool` | Case-object equality. Follows `setErrorEq` pattern. |

**New generators** (add to `tests/mproperty.nim`):

| Generator | Composes | Trials |
|-----------|----------|--------|
| `genKeyword(rng)` | Pool of standard keywords + random valid flag names | — |
| `genKeywordSet(rng)` | 0–5 keywords from `genKeyword` | — |
| `genMailboxIdSet(rng)` | 1–5 Ids from `makeId` (non-empty for Email invariant) | — |
| `genEmailComparator(rng)` | 50/50 plain/keyword, random optional `isAscending`/`collation` | — |
| `genEmailBodyFetchOptions(rng)` | Uniform `BodyValueScope`, optional `bodyProperties`/`maxBodyValueBytes` | — |
| `genEmailFilterCondition(rng)` | Early-biased: trial 0 = all-none, trial 1 = all-some, remaining trials each of 20 fields independently 30% some / 70% none | — |
| `genSearchSnippet(rng)` | Random `emailId`, optional `subject`/`preview` | — |
| `genConvenienceHeaders(rng)` | Shared helper: 11 convenience header fields. Composes `genEmailAddress`, `genValidDate`, `genArbitraryString`. Used by both `genEmail` and `genParsedEmail`. | — |
| `genBodyFields(rng)` | Shared helper: 7 body fields. Composes `genEmailBodyPart`, `genPartId`, `genEmailBodyValue`. Used by both `genEmail` and `genParsedEmail`. | — |
| `genDeepBodyStructure(rng, depth)` | Recursively nested multipart structure for adversarial stress tests (scenario 115) | — |
| `genEmail(rng)` | Composes: `makeId`, `genMailboxIdSet`, `genKeywordSet`, `genConvenienceHeaders`, `genBodyFields`, `genEmailHeader`, `genHeaderPropertyKey` + `genHeaderValue` | `ThoroughTrials` (2000) |
| `genParsedEmail(rng)` | Like `genEmail` minus metadata, `threadId` 50/50 some/none. Composes same shared helpers as `genEmail`. | `ThoroughTrials` (2000) |

Both `genEmail` and `genParsedEmail` compose shared helpers
`genConvenienceHeaders` and `genBodyFields` to ensure parity — mirroring the
serde layer's `parseConvenienceHeaders` and `parseBodyFields` helper
extraction (D7). This prevents divergence between the two generators' shared
field groups.

---

## 13. Decision Traceability Matrix

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|----------|--------------------|--------|-------------------|
| D1 | Email field sealing | A) Plain public fields, B) Pattern A (sealed), C) Partial sealing | A (28 fields too costly to seal; ProveInit prevents uninitialised use; same as Thread A14) | Code reads like the spec, Parse-don't-validate |
| D2 | Email fromJson required vs optional fields | A) All Opt, B) All required, C) Split by group | B refined (typed Email = complete domain object; Opt = header absent only; body fields non-Opt with empty defaults) | One meaning per Opt, Make illegal states unrepresentable, One source of truth |
| D3 | Convenience header Opt semantics | A) Opt = not requested or absent, B) Opt = absent only | B (subsumed by D2; one meaning per Opt) | One source of truth, Code reads like the spec |
| D4 | Dynamic header fromJson routing | A) Two-phase (structured + discovery), B) Single iteration, C) Known-property set | A (O(1) lookups for standard properties; single iteration for dynamic `header:*` discovery) | Code reads like the spec, Parse once at the boundary |
| D5 | Email toJson Opt body handling | A) Omit absent, B) Emit all (Opt→null, empty→[], Table→{}) | B (all domain fields always emitted; dynamic headers as N top-level keys) | One source of truth, Code reads like the spec |
| D6 | textBody/htmlBody/attachments leaf-only validation | A) Validate in smart constructor, B) Accept (Postel's law) | B (trust server's contract; provide convenience `isLeaf` predicate) | Postel's law, DDD |
| D7 | ParsedEmail code sharing with Email | A) Full duplication, B) Shared sub-objects, C) Inheritance, D) Generic, E) Shared serde helpers | A + E (types duplicated; serde helpers shared) | DRY — duplicated appearance is not duplicated knowledge, DDD |
| D8 | EmailComparator structure | A) Opt[Keyword] on Comparator, B) Flat enum, C) Single split enum, D) Case object with split enums | D (case object + PlainSortProperty + KeywordSortProperty; both constructors total) | Make illegal states unrepresentable, Constructors that can't fail don't, Total functions |
| D9 | EmailBodyFetchOptions | A) Inline 3 bools, B) Shared type with enum, C) Shared type with bools | Modified B (BodyValueScope enum; shared by Email/get and Email/parse) | Booleans are a code smell, DRY, Make the right thing easy |
| D10 | addEmailQuery sort type | A) Custom builder, B) Type erasure, C) Internal helper extraction | A + C (custom builder with EmailComparator; shared internal helper with addQuery) | Make illegal states unrepresentable, Make the right thing easy |
| D11 | Email/parse response structure | A) Raw JsonNode in response, B) Typed ParsedEmail | B (dedicated EmailParseResponse with Table[Id, ParsedEmail]) | Parse once at the boundary, Code reads like the spec |
| D12 | SearchSnippet/get filter + emailIds | A) Both Opt, B) Both required, C) Required filter + required non-empty emailIds | Modified C (cons-cell: firstEmailId + restEmailIds; filter required not Opt) | Total functions, Make the right thing easy |
| D13 | SearchSnippet response structure | A) Plain fields, B) Smart constructor, C) notFound as Opt | Modified A (plain fields; notFound as seq[Id] collapsing null/[] to empty seq) | Parse once at the boundary, Code reads like the spec |
| D14 | Module organisation | A) One file per type, B) By layer, C) Domain cohesion | Modified C (email.nim = entity + param types; mail_filters.nim += EmailFilterCondition; mail_builders.nim += Email builders; mail_methods.nim += custom methods) | DDD, DRY |
| D15 | Email fromJson mailboxIds non-empty validation | A) Validate in fromJson, B) Lenient (Postel's law) | B (subsumed by D1 + D6; fromJson lenient, parseEmail strict; boundary is context-dependent) | Postel's law, Parse once at the boundary |
| D16 | EmailFilterCondition inMailboxOtherThan non-empty | A) No enforcement, B) Smart constructor | A (subsumed by B16 + B11; empty list vacuous but not illegal; filter = toJson-only value object) | Make illegal states unrepresentable targets invariant violations not usage quality |
| D17 | Email/changes builder | A) Generic addChanges[Email], B) Custom wrapper | A (standard /changes, no extensions; no wrapper for naming consistency) | Code reads like the spec |
| D18 | Email/queryChanges builder | A) Custom addEmailQueryChanges, B) Generic addQueryChanges | A (parallel to D10; collapseThreads + EmailComparator sort) | Make illegal states unrepresentable, DRY |
| D19 | bodyValues Table key type | A) Table[PartId, EmailBodyValue], B) Table[string, EmailBodyValue] | A (typed key; PartId has hash; consistent with MailboxIdSet pattern) | Newtype everything that has meaning |
| D20 | ParsedEmail blobId/size exclusion | A) Include as Opt (RFC-faithful), B) Exclude (redundant + blob deferred) | B (blobId redundant — it is the response table key; size derivable from blob; blob infrastructure deferred per architecture §4.6; revisit when BlobId becomes distinct type) | DDD, Deferred scope alignment |
