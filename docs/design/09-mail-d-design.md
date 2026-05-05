# RFC 8621 JMAP Mail — Design D: Email Read Path

This document is the detailed specification for the Email read model, query
infrastructure, Email/parse, and SearchSnippet — the "read path" of RFC 8621
§4–5. It covers all layers (L1 types, L2 serde, L3 builders and custom
methods) for each type, cutting horizontally through the architecture.

Email is the most property-rich entity in the spec (~30 properties across
metadata, headers, and body, plus dynamic `header:*` properties). The
horizontal layout — all types first, then all serde, then all builders — is
chosen because the Email serde layer has significant cross-cutting concerns
(shared helpers between Email and ParsedEmail) that would be awkward to
present within a single type section.

Builds on the cross-cutting architecture design (`05-mail-architecture.md`),
the existing RFC 8620 infrastructure (`00-architecture.md` through
`04-layer-4-design.md`), Design A (`06-mail-a-design.md`), Design B
(`07-mail-b-design.md`), and Design C (`08-mail-c-design.md`). Decisions
specific to this part are tagged D1–D20 in the traceability matrix (§13).

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
10. [Custom Methods and Compound Chains](#10-custom-methods-and-compound-chains)
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
| `Email` | `email.nim` | Server-shaped read model — every field `Opt` to admit property-filter responses |
| `ParsedEmail` | `email.nim` | Blob-backed read model for Email/parse — six metadata fields structurally absent |
| `PlainSortProperty` | `email.nim` | Enum of non-keyword Email sort properties |
| `KeywordSortProperty` | `email.nim` | Enum of keyword-bearing Email sort properties |
| `EmailComparator` | `email.nim` | Case object — compile-time enforcement that keyword sorts carry a `Keyword` |
| `BodyValueScope` | `email.nim` | Enum replacing three RFC booleans for body value fetching |
| `EmailBodyFetchOptions` | `email.nim` | Shared parameter type for Email/get and Email/parse body options |
| `EmailFilterCondition` | `mail_filters.nim` | 20-field query specification for Email/query (extends existing module) |
| `EmailHeaderFilter` | `mail_filters.nim` | Sub-type for the `header` filter field (sealed `name`, smart constructor) |
| `SearchSnippet` | `snippet.nim` | Search highlight data carrier — no id property |
| `EmailParseResponse` | `mail_methods.nim` | Typed response for Email/parse with `Table[BlobId, ParsedEmail]` |
| `SearchSnippetGetResponse` | `mail_methods.nim` | Typed response for SearchSnippet/get |
| `EmailQueryThreadChain` / `EmailQueryThreadResults` | `mail_builders.nim` | Compound dispatch handles + results for the RFC 8621 §4.10 first-login workflow |
| `EmailQuerySnippetChain` | `mail_methods.nim` | Compound chain alias for Email/query + SearchSnippet/get |

### 1.3. Deferred to Other Parts

- **Part E (Email write path):** `EmailBlueprint`, `EmailUpdate`,
  `addEmailSet`, `addEmailCopy`, `addEmailImport`, and the corresponding
  response/created-item types. These types live in `email.nim` and
  `email_blueprint.nim` / `email_update.nim` for module cohesion but
  belong to Part E.
- **Part F (submission):** `EmailSubmission` and all submission types.

### 1.4. Relationship to Cross-Cutting Design

This document refines `05-mail-architecture.md`. The architecture doc locks
in the three-type split (Email, ParsedEmail, EmailBlueprint), the
`fromAddr` naming convention, `MailboxIdSet`/`KeywordSet` as distinct
types, and the `requestedHeaders`/`requestedHeadersAll` table pattern.

The Email type is server-shaped: every property the wire admits absence on
is `Opt[T]`. `Email/get` supports property filtering, so any property may
be absent in a sparse response. The default-properties fetch (`properties =
Opt.none`) populates each `Opt` with `Opt.some`; property-filtered fetches
populate only the requested properties (D2).

### 1.5. General Conventions Applied

All conventions established in prior designs apply:

1. **Lenient fromJson convention** (B15) — `*FromServer` parser variants
   for all server-received distinct types.
2. **Filter conditions are toJson-only** (B11) — no `fromJson`.
3. **Strict/lenient parser pairs are principled** (B20) — pair exists
   only when there is a meaningful gap between spec-specific and
   structural constraints.
4. **JSON path tracking** — Every serde function takes a `path: JsonPath
   = emptyJsonPath()` argument; errors carry the path of the failing
   node, returned as `SerdeViolation` on the `Result` error rail.
5. **Typedesc-overload `fromJson`** — Each public read type provides a
   `fromJson*(T: typedesc[X], node: JsonNode, path: JsonPath = ...)`
   wrapper so the dispatch layer's `mixin fromJson` resolves uniformly.

### 1.6. Module Summary

All modules live under `src/jmap_client/mail/`.

| Module | Layer | Read-path contents |
|--------|-------|--------------------|
| `email.nim` | L1 | `Email`, `ParsedEmail`, `PlainSortProperty`, `KeywordSortProperty`, `EmailComparator`, `BodyValueScope`, `EmailBodyFetchOptions`, `isLeaf` |
| `snippet.nim` | L1 | `SearchSnippet` |
| `mail_filters.nim` | L1 | `EmailFilterCondition`, `EmailHeaderFilter` (also hosts `MailboxFilterCondition`) |
| `serde_email.nim` | L2 | `emailFromJson`, `parsedEmailFromJson`, `Email.toJson`, `ParsedEmail.toJson`, `emailComparatorFromJson`, `EmailComparator.toJson`, `EmailBodyFetchOptions.toExtras`, `EmailBodyFetchOptions.toJson`, shared helpers |
| `serde_snippet.nim` | L2 | `searchSnippetFromJson`, `SearchSnippet.toJson` |
| `serde_mail_filters.nim` | L2 | `EmailFilterCondition.toJson`, `EmailHeaderFilter.toJson`, extracted emit helpers |
| `mail_entities.nim` | L3 | Per-verb method-name resolvers, capability URIs, response/filter typedesc templates, registration calls for Email |
| `mail_builders.nim` | L3 | `addEmailGet`, `addEmailGetByRef`, `addThreadGetByRef`, `addEmailQuery`, `addEmailQueryChanges`, `addEmailQueryWithThreads`, compound chain types |
| `mail_methods.nim` | L3 | `addEmailParse`, `addSearchSnippetGet`, `addSearchSnippetGetByRef`, `addEmailQueryWithSnippets`, `EmailParseResponse`, `SearchSnippetGetResponse`, `EmailQuerySnippetChain`, typedesc-overload `fromJson` wrappers |

---

## 2. Email Entity — email.nim

**Module:** `src/jmap_client/mail/email.nim`

**RFC reference:** §4.1 (properties), §4.2 (Email/get).

The Email type is the server-shaped read model — a representation of a
message as returned by `Email/get`. Every field the wire admits absence on
is `Opt[T]`. `Email/get` supports property filtering, so any property may
be absent in a sparse response. The default-properties fetch
(`properties = Opt.none`) populates each `Opt` with `Opt.some`;
property-filtered fetches populate only the requested properties (D2).

**Principles:**
- **Code reads like the spec** — Fields map 1:1 to RFC §4.1 properties.
- **One type, two shapes** — The same `Email` value carries both the
  default-properties shape (every `Opt` populated) and the sparse shape
  (only requested properties populated). The wire grammar admits both;
  the type accommodates both without a phantom wrapper.

### 2.1. Type Definition

```nim
type Email* {.ruleOff: "objects".} = object
  ## Server-shaped Email read model (RFC 8621 §4.1).

  # -- Metadata (§4.1.1) -- server-set; absent under property filter
  id*: Opt[Id]                                   ## JMAP object id.
  blobId*: Opt[BlobId]                           ## Raw RFC 5322 octets.
  threadId*: Opt[Id]                             ## Thread this Email belongs to.
  mailboxIds*: Opt[MailboxIdSet]                 ## ≥1 Mailbox at all times when present (RFC §4.1.1 server invariant).
  keywords*: Opt[KeywordSet]                     ## Default-shape: ``Opt.some(empty set)``.
  size*: Opt[UnsignedInt]                        ## Raw message size in octets.
  receivedAt*: Opt[UTCDate]                      ## IMAP internal date.

  # -- Convenience headers (§4.1.2-4.1.3) -- Opt.none = header absent in message
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

  # -- Raw headers (§4.1.3) --
  headers*: seq[EmailHeader]                     ## All header fields in message order; @[] if absent.

  # -- Dynamic header properties (§4.1.3) --
  requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
    ## Parsed headers requested via ``header:Name:asForm`` (last instance).
  requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]
    ## Parsed headers requested via ``header:Name:asForm:all`` (all instances).

  # -- Body (§4.1.4) --
  bodyStructure*: Opt[EmailBodyPart]             ## Full MIME tree; ``Opt.none`` under property filter.
  bodyValues*: Table[PartId, EmailBodyValue]     ## Text part contents; empty if none fetched.
  textBody*: seq[EmailBodyPart]                  ## Leaf parts — text/plain preference.
  htmlBody*: seq[EmailBodyPart]                  ## Leaf parts — text/html preference.
  attachments*: seq[EmailBodyPart]               ## Leaf parts — non-body content.
  hasAttachment*: bool                           ## Server heuristic.
  preview*: string                               ## Up to 256 characters plaintext fragment.
```

**`fromAddr` naming:** `from` is a Nim reserved keyword. The architecture
doc mandates `fromAddr` consistently across Email, ParsedEmail,
EmailBlueprint, and EmailFilterCondition. The serde layer maps to/from the
RFC's `"from"` key transparently.

**`blobId` is `Opt[BlobId]`, not `Opt[Id]`:** `BlobId` is a distinct
opaque-token string defined in `identifiers.nim` (`==`/`$`/`hash` borrowed,
no `len`). Using the typed `BlobId` here parallels the use of `MailboxIdSet`
and `KeywordSet` over raw containers — newtype everything that has meaning.

**Field grouping rationale:**
- **Metadata** — Server-managed store properties. `Opt` because property
  filter can omit any of them; the default fetch populates all seven.
- **Convenience headers** — Parsed forms of common header fields.
  `Opt.none` means exclusively "this header field does not exist in the
  message" when the property was requested (D3).
- **Raw headers** — The `headers` escape hatch for full header access.
  `seq[EmailHeader]` — empty seq means no headers were returned (under a
  property filter, or no header fields exist).
- **Dynamic headers** — Caller-requested `header:Name:asForm` properties.
  Tables are empty when no dynamic headers were requested. `fromJson`
  routes these via prefix matching (D4).
- **Body** — `bodyStructure` is `Opt` because the property filter may
  omit it. The leaf-part lists, `bodyValues`, `hasAttachment`, and
  `preview` use natural-empty types (empty seq/Table, `false`, `""`)
  rather than `Opt`.

### 2.2. Construction

There is no smart constructor for `Email`. Construction paths are:

1. **Server JSON via `emailFromJson` / `Email.fromJson`** — the primary
   construction path. Lenient at the boundary (D15): trusts the RFC
   contract that `mailboxIds`, when present, is non-empty. No client-side
   validation re-check.
2. **Direct field construction** — for tests and synthetic Emails. Every
   `Opt` field can be `Opt.none`; field-syntax construction is unconstrained.

The RFC §4.1.1 invariant "an Email in the mail store MUST belong to one
or more Mailboxes" is a server contract, not an enforceable client
invariant on the read model — under a property filter the field can be
absent entirely. Write-path types (`EmailBlueprint`, `EmailCopyItem`,
`EmailImportItem` in Part E) use `NonEmptyMailboxIdSet` to encode the
invariant where it is enforceable.

### 2.3. Leaf-Only Body Lists

`textBody`, `htmlBody`, and `attachments` are guaranteed by the RFC to
contain only leaf parts (no `multipart/*` entries). The typed Email does
**not** enforce this invariant via a smart constructor (D6). It trusts
the server's contract — same reasoning as the lenient `mailboxIds`
behaviour.

A convenience predicate is provided for callers who wish to assert:

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
represents a parsed message blob without store metadata. Structurally
distinct from `Email` — six metadata fields are physically absent (not
`Opt.none`), and `threadId` is `Opt[Id]` (the server may not be able to
determine thread assignment for a blob).

**Decision D7:** Full field duplication — both `Email` and `ParsedEmail`
are independent flat object types with all fields declared directly. No
shared sub-object types. Shared serde helper procs for common field
groups (convenience headers, body fields, dynamic header routing) keep
parsing logic DRY without sacrificing type clarity.

"DRY — but duplicated appearance is not duplicated knowledge." The field
declarations look similar but belong to different domain aggregates with
different invariants. Factoring them into a shared sub-object would
create a type that lacks domain meaning.

### 3.1. Type Definition

```nim
type ParsedEmail* {.ruleOff: "objects".} = object
  ## Blob-backed Email for Email/parse responses (RFC 8621 §4.9).
  ## Missing id, blobId, mailboxIds, keywords, size, receivedAt —
  ## structurally absent, not ``Opt.none`` (D7, D20).

  # -- Metadata -- only threadId survives
  threadId*: Opt[Id]                             ## Server MAY provide if determinable; else none.

  # -- Convenience headers -- identical structure to Email
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

  # -- Raw headers --
  headers*: seq[EmailHeader]

  # -- Dynamic header properties --
  requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
  requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]

  # -- Body --
  bodyStructure*: Opt[EmailBodyPart]
  bodyValues*: Table[PartId, EmailBodyValue]
  textBody*: seq[EmailBodyPart]
  htmlBody*: seq[EmailBodyPart]
  attachments*: seq[EmailBodyPart]
  hasAttachment*: bool
  preview*: string
```

### 3.2. Field Comparison with Email

| Property Group | Email | ParsedEmail | Difference |
|----------------|-------|-------------|------------|
| Metadata | 7 fields, all `Opt` | `threadId: Opt[Id]` | 6 fields structurally absent |
| Convenience headers | 11 fields, all `Opt` | Identical | None |
| Raw headers | `headers: seq[EmailHeader]` | Identical | None |
| Dynamic headers | 2 tables | Identical | None |
| Body | 7 fields | Identical | None |

**`blobId` and `size` exclusion (D20):** RFC §4.9 lists four metadata
properties as null on parsed emails: `id`, `mailboxIds`, `keywords`,
`receivedAt`. It does not list `blobId` or `size` — they are technically
available if explicitly requested. ParsedEmail omits them for two reasons:
(1) `blobId` is redundant — the `EmailParseResponse.parsed` table is keyed
by `BlobId`, so the caller already has it; (2) `size` is derivable from the
blob itself. ParsedEmail models "what a parsed blob IS" rather than
mirroring the full Email type with holes.

**No smart constructor.** ParsedEmail is a read-only result from
`Email/parse`. The only "construction" is parsing from server JSON. No
client-side construction path exists, so no validation beyond what
`fromJson` provides.

---

## 4. EmailComparator — email.nim

**Module:** `src/jmap_client/mail/email.nim`

**RFC reference:** §4.4.2 (sorting).

RFC 8621 extends the standard Comparator (RFC 8620 §5.5) for Email/query
with a `keyword` property: three sort properties (`hasKeyword`,
`allInThreadHaveKeyword`, `someInThreadHaveKeyword`) require an
accompanying `Keyword` value. The remaining six (`receivedAt`, `size`,
`from`, `to`, `subject`, `sentAt`) do not.

The generic `Comparator` type in `framework.nim` cannot carry the extra
`keyword` field. Decision D8 models this as a case object with split
enums — making illegal states (keyword sort without a keyword, plain sort
with a keyword) unrepresentable at compile time.

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
    kspHasKeyword              = "hasKeyword"
    kspAllInThreadHaveKeyword  = "allInThreadHaveKeyword"
    kspSomeInThreadHaveKeyword = "someInThreadHaveKeyword"
```

**Two enums, not one:** The split encodes the structural difference. A
single `EmailSortProperty` enum with 9 variants would still require
runtime checking of whether the keyword field is present for keyword
sorts. Split enums push this check to the type system.

### 4.2. Case Object

```nim
type
  EmailComparatorKind* = enum
    eckPlain
    eckKeyword

  EmailComparator* {.ruleOff: "objects".} = object
    isAscending*: Opt[bool]                     ## Absent = server default (RFC: true).
    collation*: Opt[CollationAlgorithm]         ## RFC 4790 collation identifier.
    case kind*: EmailComparatorKind
    of eckPlain:
      property*: PlainSortProperty
    of eckKeyword:
      keywordProperty*: KeywordSortProperty
      keyword*: Keyword                         ## Required for keyword sorts.
```

**Shared fields before `case`:** `isAscending` and `collation` apply to
both branches — accessible without matching `kind`.

**`isAscending` is `Opt[bool]`:** So the serde layer can distinguish
"client explicitly set ascending" from "use server default." The RFC
default is `true`, but some servers may interpret absence differently.
`Opt.none` → omit from JSON; `Opt.some(true)` → emit `true`.

**`collation` is `Opt[CollationAlgorithm]`:** Typed sealed sum of the
four IANA-registered algorithms (`caAsciiCasemap`, `caOctet`,
`caAsciiNumeric`, `caUnicodeCasemap`) plus `caOther` for vendor
extensions, defined in `collation.nim`. Empty-string wire values are
treated as `Opt.none` (RFC-default sentinel).

### 4.3. Total Constructors

Both constructors are total — no `Result`, no validation. Every input
combination produces a valid `EmailComparator`.

```nim
func plainComparator*(
    property: PlainSortProperty,
    isAscending: Opt[bool] = Opt.none(bool),
    collation: Opt[CollationAlgorithm] = Opt.none(CollationAlgorithm),
): EmailComparator

func keywordComparator*(
    keywordProperty: KeywordSortProperty,
    keyword: Keyword,
    isAscending: Opt[bool] = Opt.none(bool),
    collation: Opt[CollationAlgorithm] = Opt.none(CollationAlgorithm),
): EmailComparator
```

**Principles:**
- **Make illegal states unrepresentable** — Keyword sort without keyword
  is a compile error (the `keyword` field only exists on the
  `eckKeyword` branch).
- **Constructors that can't fail, don't** — Both constructors are
  infallible. All validation is delegated to the field types
  (`PlainSortProperty`/`KeywordSortProperty` as enums; `Keyword`
  validated at construction; `CollationAlgorithm` smart-constructed).

---

## 5. EmailBodyFetchOptions — email.nim

**Module:** `src/jmap_client/mail/email.nim`

**RFC reference:** §4.2 (Email/get), §4.9 (Email/parse).

Both `Email/get` and `Email/parse` accept the same body-related parameters:
`bodyProperties`, `fetchTextBodyValues`, `fetchHTMLBodyValues`,
`fetchAllBodyValues`, and `maxBodyValueBytes`. The three `fetch*BodyValues`
booleans are mutually overlapping — "booleans are a code smell." Decision
D9 replaces them with a domain-meaningful enum.

### 5.1. BodyValueScope Enum

```nim
type BodyValueScope* = enum
  ## ``bvsNone`` must remain first (ordinal 0) so ``default()``
  ## produces correct RFC defaults.
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

The serde layer maps the enum back to the three RFC booleans at the
boundary. Every valid combination is a distinct enum variant — no
impossible states.

### 5.2. Type Definition

```nim
type EmailBodyFetchOptions* {.ruleOff: "objects".} = object
  ## ``default(EmailBodyFetchOptions)`` produces correct RFC defaults
  ## (no body properties override, no body values, no truncation).
  bodyProperties*: Opt[seq[PropertyName]]   ## Override default body part properties.
  fetchBodyValues*: BodyValueScope          ## Default: bvsNone.
  maxBodyValueBytes*: Opt[UnsignedInt]      ## Absent = no truncation.
```

**No smart constructor.** All field combinations are valid. `default(
EmailBodyFetchOptions)` produces correct RFC defaults via Nim
zero-initialisation: `Opt.none`, `bvsNone`, `Opt.none`.

---

## 6. EmailFilterCondition — mail_filters.nim

**Module:** `src/jmap_client/mail/mail_filters.nim` (shared with
`MailboxFilterCondition`).

**RFC reference:** §4.4.1 (filtering).

`EmailFilterCondition` is a query specification — a value object
describing filter criteria for `Email/query`. Like
`MailboxFilterCondition` (Design B §5), it is toJson-only (B11), has no
smart constructor (B16), and all field combinations are valid. Unlike
`MailboxFilterCondition`, no field needs `Opt[Opt[T]]` three-state
semantics — no Email filter field has a meaningful "filter for null"
state.

### 6.1. EmailHeaderFilter

The RFC `header` filter field is a 1–2 element array: the first element
is the header name (required, non-empty), the second is the value to
match (optional). This structural constraint (non-empty name) is enforced
via a smart constructor.

```nim
type EmailHeaderFilter* {.ruleOff: "objects".} = object
  ## Pattern A: ``name`` is module-private to enforce non-empty invariant.
  name: string              ## Module-private — non-empty.
  value*: Opt[string]       ## Match text, or none = existence check only.

func name*(f: EmailHeaderFilter): string =
  ## Read-only accessor for the sealed header name.
  f.name

func parseEmailHeaderFilter*(
    name: string, value: Opt[string] = Opt.none(string)
): Result[EmailHeaderFilter, ValidationError] =
  if name.len == 0:
    return err(validationError(
      "EmailHeaderFilter", "header name must not be empty", name))
  return ok(EmailHeaderFilter(name: name, value: value))
```

**Principles:**
- **Parse, don't validate** — Non-empty name enforced at construction time.
- **Pattern A where warranted** — One sealed field with one invariant.
  Email itself (28 fields, no fully-enforceable invariants) is unsealed;
  `EmailHeaderFilter` has the right ratio for Pattern A.

### 6.2. Type Definition

```nim
type EmailFilterCondition* {.ruleOff: "objects".} = object
  # -- Mailbox membership --
  inMailbox*: Opt[Id]                              ## Email must be in this Mailbox.
  inMailboxOtherThan*: Opt[seq[Id]]                ## Email must not be in these Mailboxes.

  # -- Date/size --
  before*: Opt[UTCDate]                            ## receivedAt < this date.
  after*: Opt[UTCDate]                             ## receivedAt ≥ this date.
  minSize*: Opt[UnsignedInt]                       ## size ≥ this value.
  maxSize*: Opt[UnsignedInt]                       ## size < this value.

  # -- Thread keyword filters --
  allInThreadHaveKeyword*: Opt[Keyword]
  someInThreadHaveKeyword*: Opt[Keyword]
  noneInThreadHaveKeyword*: Opt[Keyword]

  # -- Per-email keyword filters --
  hasKeyword*: Opt[Keyword]
  notKeyword*: Opt[Keyword]

  # -- Boolean filter --
  hasAttachment*: Opt[bool]

  # -- Text search --
  text*: Opt[string]                               ## Search From, To, Cc, Bcc, Subject, body.
  fromAddr*: Opt[string]                           ## Search From header (``from`` is a Nim keyword).
  to*: Opt[string]                                 ## Search To header.
  cc*: Opt[string]                                 ## Search Cc header.
  bcc*: Opt[string]                                ## Search Bcc header.
  subject*: Opt[string]                            ## Search Subject header.
  body*: Opt[string]                               ## Search body parts.

  # -- Header filter --
  header*: Opt[EmailHeaderFilter]                  ## Match header by name (and optionally value).
```

**20 fields total.** Keyword filter fields use typed `Keyword`, not
`string` — newtype-everything-that-has-meaning.

**`inMailboxOtherThan` non-empty enforcement (D16):** No enforcement. An
empty list is vacuous (matches everything) but not illegal — the RFC
does not prohibit it.

**Principles:**
- **Newtype everything that has meaning** — Keyword filter fields use
  `Keyword`; `inMailbox` uses `Id`.
- **DDD** — Value object, not entity. Construction is infallible.

---

## 7. SearchSnippet — snippet.nim

**Module:** `src/jmap_client/mail/snippet.nim`

**RFC reference:** §5 (SearchSnippet).

A `SearchSnippet` provides highlighted search result fragments for an
Email. Unlike most data types, SearchSnippet has no `id` property — it is
keyed by `emailId`.

### 7.1. Type Definition

```nim
type SearchSnippet* {.ruleOff: "objects".} = object
  ## Pure data carrier — no domain invariant, no smart constructor.
  emailId*: Id                    ## The Email this snippet describes.
  subject*: Opt[string]           ## Highlighted subject with <mark> tags, or none.
  preview*: Opt[string]           ## Highlighted body fragment with <mark> tags, or none.
```

**No smart constructor.** All field combinations valid. `Opt.none` means
"no matching content to highlight"; both fields null = server could not
determine snippets.

### 7.2. SearchSnippetGetResponse

Defined in `mail_methods.nim` alongside the `SearchSnippet/get` builder.

```nim
type SearchSnippetGetResponse* = object
  accountId*: AccountId
  list*: seq[SearchSnippet]       ## Snippets for requested Email ids.
  notFound*: seq[Id]              ## Email ids that could not be found.
```

**`notFound` is `seq[Id]`, not `Opt[seq[Id]]`** (D13). The RFC specifies
`Id[]|null`, but `fromJson` collapses both null and `[]` into an empty
seq via the shared `collapseNullToEmptySeq` helper. The wire distinction
is noise; the domain fact is a possibly-empty list.

### 7.3. EmailParseResponse

Defined in `mail_methods.nim` alongside the `Email/parse` builder.

```nim
type EmailParseResponse* = object
  accountId*: AccountId
  parsed*: Table[BlobId, ParsedEmail]   ## Blob id → parsed Email.
  notParseable*: seq[BlobId]            ## Blob ids that could not be parsed.
  notFound*: seq[BlobId]                ## Blob ids that could not be found.
```

**Typed `BlobId` keys and elements (D11).** Both the `parsed` table
keys and the failure lists use the typed `BlobId`. The wire JSON uses
plain strings; the serde layer parses them through `parseBlobId` (lenient
server-side parser).

**`notParseable` field name vs `"notParsable"` wire key:** The RFC spells
the wire field `"notParsable"` (one 'e'). The Nim field is
`notParseable` (British English, per coding conventions). The serde
layer reads from and writes to the RFC key `"notParsable"` only; the
Nim spelling is not accepted as an alias.

---

## 8. Serialisation

### 8.1. Email fromJson — serde_email.nim

**Module:** `src/jmap_client/mail/serde_email.nim`

**RFC reference:** §4.1 (properties), §4.2.1 (example).

Email `fromJson` uses a two-phase strategy (D4):

**Phase 1 — Structured extraction:** Direct key lookups (`node{"id"}`,
`node{"from"}`, etc.) for all known standard properties, all routed
through optional-field helpers (`parseOptId`, `parseOptBlobId`,
`parseOptUnsignedInt`, `parseOptUTCDate`, `parseOptMailboxIdSet`,
`parseOptKeywordSet`, etc.). Every field is `Opt`, so absent or null
keys yield `Opt.none` rather than an error — admitting sparse
property-filtered responses.

**Phase 2 — Dynamic discovery:** Single iteration over all keys in the
JSON object. Keys starting with `"header:"` are parsed via
`parseHeaderPropertyName` and routed to `requestedHeaders` (single
instance) or `requestedHeadersAll` (`:all` suffix) based on `isAll`. Keys
not matching the `"header:"` prefix are silently ignored (forward
compatibility with future RFC extensions).

```nim
func emailFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Email, SerdeViolation] =
  ?expectKind(node, JObject, path)

  # == Phase 1: Structured extraction ==
  let id          = ?parseOptId(node, "id", path)
  let blobId      = ?parseOptBlobId(node, "blobId", path)
  let threadId    = ?parseOptId(node, "threadId", path)
  let mailboxIds  = ?parseOptMailboxIdSet(node, "mailboxIds", path)
  let keywords    = ?parseOptKeywordSet(node, "keywords", path)
  let size        = ?parseOptUnsignedInt(node, "size", path)
  let receivedAt  = ?parseOptUTCDate(node, "receivedAt", path)
  let convHeaders = ?parseConvenienceHeaders(node, path)
  let hdrs        = ?parseRawHeaders(node, path)
  let bf          = ?parseBodyFields(node, path)

  # == Phase 2: Dynamic header discovery ==
  var reqHeaders = initTable[HeaderPropertyKey, HeaderValue]()
  var reqHeadersAll = initTable[HeaderPropertyKey, seq[HeaderValue]]()
  for key, val in node.pairs:
    if key.startsWith("header:"):
      let hpk = ?wrapInner(parseHeaderPropertyName(key), path / key)
      if hpk.isAll:
        reqHeadersAll[hpk] = ?parseHeaderValueArray(val, hpk.form, path / key)
      else:
        reqHeaders[hpk] = ?parseHeaderValue(hpk.form, val, path / key)

  return ok(Email(id: id, blobId: blobId, ...))

func fromJson*(
    T: typedesc[Email], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Email, SerdeViolation] =
  ## Typedesc-overload wrapper for the dispatch layer's ``mixin fromJson``.
  discard $T
  return emailFromJson(node, path)
```

**Optional-field helpers:** `serde_email.nim` defines a family of
internal helpers — `parseOptStringSeq`, `parseOptAddresses`,
`parseOptString`, `parseOptDate`, `parseOptId`, `parseOptBlobId`,
`parseOptUnsignedInt`, `parseOptUTCDate`, `parseOptMailboxIdSet`,
`parseOptKeywordSet`, `parseOptBodyPart`. Each takes
`(node, key, path)` and returns `Result[Opt[T], SerdeViolation]`,
collapsing absent/null to `Opt.none` and dispatching the typed
`fromJson` only when a value is present.

**`expectKind` + `wrapInner`:** Serde routines use `expectKind` for
JSON-kind validation and `wrapInner` to lift `ValidationError`-bearing
results from smart-constructor parsers (e.g. `parseHeaderPropertyName`)
into `SerdeViolation` at a specific path.

**No parallel set of known property names.** Phase 2 does not maintain a
set of "known properties" to skip. Phase 1 extracts known properties by
direct key lookup; Phase 2 discovers `header:*` keys by iteration. Keys
that are neither known standard properties nor `header:*` prefixed are
silently ignored. This mirrors the RFC structure: fixed properties by
name, dynamic extension by prefix.

### 8.2. ParsedEmail fromJson

Same two-phase strategy as Email, but Phase 1 extracts only `threadId`
(as `Opt[Id]`) instead of the full metadata group. The convenience
header, raw header, and body phases are identical — delegating to the
same shared helper procs.

```nim
func parsedEmailFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[ParsedEmail, SerdeViolation] =
  ?expectKind(node, JObject, path)
  let threadId    = ?parseOptId(node, "threadId", path)
  let convHeaders = ?parseConvenienceHeaders(node, path)
  let hdrs        = ?parseRawHeaders(node, path)
  let bf          = ?parseBodyFields(node, path)
  # Phase 2: dynamic header discovery — identical to Email
  ...
  return ok(ParsedEmail(threadId: threadId, ...))
```

### 8.3. Shared Serde Helpers (D7)

Three shared helper procs extract common field groups for both `Email`
and `ParsedEmail`. Field declarations are duplicated; parsing logic is
not. The helpers are non-exported — internal to `serde_email.nim`.

**`parseConvenienceHeaders`:**

```nim
type ConvenienceHeaders {.ruleOff: "objects".} = object
  messageId: Opt[seq[string]]
  inReplyTo: Opt[seq[string]]
  references: Opt[seq[string]]
  sender: Opt[seq[EmailAddress]]
  fromAddr: Opt[seq[EmailAddress]]
  to: Opt[seq[EmailAddress]]
  cc: Opt[seq[EmailAddress]]
  bcc: Opt[seq[EmailAddress]]
  replyTo: Opt[seq[EmailAddress]]
  subject: Opt[string]
  sentAt: Opt[Date]

func parseConvenienceHeaders(node: JsonNode, path: JsonPath):
    Result[ConvenienceHeaders, SerdeViolation]
  ## JSON ``"from"`` key → ``fromAddr`` field (``from`` is a Nim keyword).
```

**`parseBodyFields`:**

```nim
type BodyFields {.ruleOff: "objects".} = object
  bodyStructure: Opt[EmailBodyPart]
  bodyValues: Table[PartId, EmailBodyValue]
  textBody: seq[EmailBodyPart]
  htmlBody: seq[EmailBodyPart]
  attachments: seq[EmailBodyPart]
  hasAttachment: bool
  preview: string

func parseBodyFields(node: JsonNode, path: JsonPath):
    Result[BodyFields, SerdeViolation]
  ## bodyStructure: optional, absent/null → ``Opt.none``.
  ## bodyValues keys parsed via parsePartIdFromServer (D19 — typed PartId).
  ## hasAttachment: absent/null → false; non-bool rejected.
  ## preview: absent/null/non-string → "".
```

`parseBodyFields` delegates to two further helpers: `parseBodyValues`
(builds `Table[PartId, EmailBodyValue]` keyed via `parsePartIdFromServer`;
absent/non-object → empty table) and `parseBodyPartArray` (parses any
`Opt[seq[EmailBodyPart]]` field by name; absent/non-array → empty seq).
Both are reused for `textBody`, `htmlBody`, and `attachments` extraction.

**`parseRawHeaders`:**

```nim
func parseRawHeaders(node: JsonNode, path: JsonPath):
    Result[seq[EmailHeader], SerdeViolation]
  ## Absent/non-array key → empty seq (not an error).
```

**`parseHeaderValueArray`:**

```nim
func parseHeaderValueArray(node: JsonNode, form: HeaderForm, path: JsonPath):
    Result[seq[HeaderValue], SerdeViolation]
  ## Parses the JSON array for ``:all`` dynamic header properties.
  ## Each element parsed via parseHeaderValue with the given form.
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

  # Metadata — every field is Opt; absent emits null.
  node["id"]         = e.id.optToJsonOrNull()
  node["blobId"]     = e.blobId.optToJsonOrNull()
  node["threadId"]   = e.threadId.optToJsonOrNull()
  node["mailboxIds"] = e.mailboxIds.optToJsonOrNull()
  node["keywords"]   = e.keywords.optToJsonOrNull()
  node["size"]       = e.size.optToJsonOrNull()
  node["receivedAt"] = e.receivedAt.optToJsonOrNull()

  # Convenience headers — Opt.none → null
  emitOptStringSeqOrNull(node, "messageId", e.messageId)
  emitOptAddressesOrNull(node, "from",      e.fromAddr)    # fromAddr → "from" key
  ...

  # Body
  node["bodyStructure"] = e.bodyStructure.optToJsonOrNull()
  ...

  # Dynamic headers — N top-level keys
  for hpk, val in e.requestedHeaders:
    node[hpk.toPropertyString()] = val.toJson()
  for hpk, vals in e.requestedHeadersAll:
    var arr = newJArray()
    for v in vals: arr.add(v.toJson())
    node[hpk.toPropertyString()] = arr

  return node
```

`ParsedEmail.toJson` is structurally identical except that it emits only
`threadId` from the metadata group; the six absent metadata fields are
not emitted.

**Emit helpers:** `emitOptStringSeqOrNull` and `emitOptAddressesOrNull`
are internal helpers in `serde_email.nim` for `Opt[seq[X]]` fields.
Scalar `Opt` fields use `optToJsonOrNull` (from the shared `serde.nim`
module) and `optStringToJsonOrNull` (for `Opt[string]`).

**Dynamic header `:all` emission:** The `requestedHeadersAll` table
values are `seq[HeaderValue]`, serialised by building a `JArray`
element-by-element.

### 8.5. bodyValues Table Key — PartId (D19)

`bodyValues` uses `Table[PartId, EmailBodyValue]` — typed key. `PartId`
has `hash` borrowed via `defineStringDistinctOps`, so it works as a
`Table` key. Consistent with `MailboxIdSet` (`HashSet[Id]`, not
`HashSet[string]`).

`fromJson` parses table keys via `parsePartIdFromServer` (lenient, per
B15 convention). `toJson` emits keys via `$partId` (string conversion).

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
    node["keyword"]  = %($c.keyword)
  for v in c.isAscending: node["isAscending"] = %v
  for v in c.collation:   node["collation"]   = %($v)   # CollationAlgorithm.identifier
  return node
```

**fromJson:**

Synthesises the discriminant by inspecting the `property` name at the
parse boundary. If the property string matches a `KeywordSortProperty`
backing string, constructs `eckKeyword` (requiring a `keyword` field).
Otherwise, matches against `PlainSortProperty`.

```nim
func emailComparatorFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailComparator, SerdeViolation] =
  ?expectKind(node, JObject, path)

  # Required property string
  let propNode = ?fieldJString(node, "property", path)
  let propStr  = propNode.getStr("")

  # Optional shared fields
  let isAscending = ...  # via optJsonField + JBool
  let collation = block:
    # Empty string is the RFC-default sentinel; treat as Opt.none.
    let f = optJsonField(node, "collation", JString)
    if f.isSome:
      let raw = f.get().getStr("")
      if raw.len > 0:
        let alg = ?wrapInner(parseCollationAlgorithm(raw), path / "collation")
        Opt.some(alg)
      else:
        Opt.none(CollationAlgorithm)
    else:
      Opt.none(CollationAlgorithm)

  for ksp in KeywordSortProperty:
    if $ksp == propStr:
      let kwNode = ?fieldJString(node, "keyword", path)
      let kw = ?Keyword.fromJson(kwNode, path / "keyword")
      return ok(keywordComparator(ksp, kw, isAscending, collation))

  for psp in PlainSortProperty:
    if $psp == propStr:
      return ok(plainComparator(psp, isAscending, collation))

  return err(SerdeViolation(
    kind: svkEnumNotRecognised, path: path / "property",
    enumTypeLabel: "sort property", rawValue: propStr))
```

### 8.7. EmailFilterCondition toJson

toJson only — no fromJson (B11 convention). The implementation extracts
field-group serialisation into internal UFCS helpers to keep each function
under the nimalyzer complexity limit:

- `emitDateSizeFilters(node, fc)` — 4 date/size fields
- `emitKeywordFilters(node, fc)` — 5 keyword fields (thread + per-email)
- `emitTextSearchFilters(node, fc)` — 7 text search fields, including
  `fromAddr` → `"from"` mapping

`EmailHeaderFilter` has its own `toJson` function (serialises as a 1-or-2
element JSON array) rather than being inlined into
`EmailFilterCondition.toJson`.

```nim
func toJson*(ehf: EmailHeaderFilter): JsonNode =
  var arr = newJArray()
  arr.add(%ehf.name)
  for val in ehf.value: arr.add(%val)
  return arr

func toJson*(fc: EmailFilterCondition): JsonNode =
  var node = newJObject()
  for v in fc.inMailbox: node["inMailbox"] = v.toJson()
  for v in fc.inMailboxOtherThan:
    var arr = newJArray()
    for id in v: arr.add(id.toJson())
    node["inMailboxOtherThan"] = arr
  node.emitDateSizeFilters(fc)
  node.emitKeywordFilters(fc)
  for v in fc.hasAttachment: node["hasAttachment"] = %v
  node.emitTextSearchFilters(fc)
  for v in fc.header: node["header"] = v.toJson()
  return node
```

Keyword filter fields serialise via `$keyword` (distinct-string `$`
borrow); the resulting JSON value is a plain string.

### 8.8. EmailBodyFetchOptions Serde

Two serialisation functions: `toExtras` returns a `seq[(string, JsonNode)]`
of body-fetch keys for direct merging into builder argument objects, and
`toJson` builds a standalone `JsonNode` from the same `toExtras` output
(byte-identical).

```nim
func toExtras*(opts: EmailBodyFetchOptions): seq[(string, JsonNode)] =
  ## Insertion order: bodyProperties, fetchTextBodyValues?,
  ## fetchHTMLBodyValues?, fetchAllBodyValues?, maxBodyValueBytes.
  result = @[]
  for props in opts.bodyProperties:
    var arr = newJArray()
    for p in props: arr.add(p.toJson())
    result.add(("bodyProperties", arr))
  case opts.fetchBodyValues
  of bvsNone: discard
  of bvsText: result.add(("fetchTextBodyValues", %true))
  of bvsHtml: result.add(("fetchHTMLBodyValues", %true))
  of bvsTextAndHtml:
    result.add(("fetchTextBodyValues", %true))
    result.add(("fetchHTMLBodyValues", %true))
  of bvsAll: result.add(("fetchAllBodyValues", %true))
  for v in opts.maxBodyValueBytes:
    result.add(("maxBodyValueBytes", v.toJson()))

func toJson*(opts: EmailBodyFetchOptions): JsonNode =
  var node = newJObject()
  for (k, v) in opts.toExtras(): node[k] = v
  return node
```

**`toExtras` vs `toJson`:** Builders (`addEmailGet`, `addEmailParse`,
`addEmailQueryWithThreads`) feed `toExtras` directly into the generic
builder's `extras: seq[(string, JsonNode)]` parameter — no second
`JsonNode` allocation. `toJson` exists for standalone use (tests,
diagnostics).

No `fromJson` — body fetch options are request parameters, never
returned by the server.

### 8.9. SearchSnippet fromJson

```nim
func searchSnippetFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[SearchSnippet, SerdeViolation] =
  ?expectKind(node, JObject, path)
  let emailIdNode = ?fieldJString(node, "emailId", path)
  let emailId = ?Id.fromJson(emailIdNode, path / "emailId")
  let subject = ...  # via optJsonField + JString → Opt[string]
  let preview = ...  # via optJsonField + JString → Opt[string]
  ok(SearchSnippet(emailId: emailId, subject: subject, preview: preview))
```

`toJson` emits all three fields always (D5): `emailId` as a string,
`subject`/`preview` via `optStringToJsonOrNull`.

### 8.10. SearchSnippetGetResponse fromJson

```nim
func searchSnippetGetResponseFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[SearchSnippetGetResponse, SerdeViolation] =
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId = ?AccountId.fromJson(accountIdNode, path / "accountId")
  let listNode = node{"list"}
  let list =
    if listNode.isNil or listNode.kind != JArray:
      newSeq[SearchSnippet]()
    else:
      var snippets: seq[SearchSnippet] = @[]
      for i, elem in listNode.getElems(@[]):
        snippets.add(?searchSnippetFromJson(elem, path / "list" / i))
      snippets
  let notFound = ?collapseNullToEmptySeq(node, "notFound", parseIdFromServer, path)
  ok(SearchSnippetGetResponse(accountId: accountId, list: list, notFound: notFound))

func fromJson*(T: typedesc[SearchSnippetGetResponse], ...) ## typedesc-overload wrapper
```

**Lenient `list` handling:** `list` defaults to an empty seq when absent
or not a `JArray` (including null). Postel's law — the implementation is
lenient rather than erroring on a null `list`.

**`collapseNullToEmptySeq`:** Shared helper from `serde.nim` parsing
`T[]|null` — null or absent → `@[]`, present → parse each element via
the supplied per-element parser. Generic over `T` so both `Id` and
`BlobId` arrays share it.

### 8.11. EmailParseResponse fromJson

```nim
func emailParseResponseFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailParseResponse, SerdeViolation] =
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId = ?AccountId.fromJson(accountIdNode, path / "accountId")
  let parsed = ?parseKeyedTable[BlobId, ParsedEmail](
    node{"parsed"}, parseBlobId, parsedEmailFromJson, path / "parsed")
  let notParseable = ?collapseNullToEmptySeq(node, "notParsable", parseBlobId, path)
  let notFound     = ?collapseNullToEmptySeq(node, "notFound",    parseBlobId, path)
  ok(EmailParseResponse(
    accountId: accountId, parsed: parsed,
    notParseable: notParseable, notFound: notFound))

func fromJson*(T: typedesc[EmailParseResponse], ...) ## typedesc-overload wrapper
```

**`parseKeyedTable`:** Shared helper from `serde.nim` parsing a JSON
object into `Table[K, T]`. Keys parsed via `parseBlobId`; values via
`parsedEmailFromJson`. Nil or non-object input yields an empty table.

**RFC spelling mismatch:** The wire field is `"notParsable"` (one 'e');
the Nim field is `notParseable` (British English). The serde layer reads
exclusively from `"notParsable"` — the Nim spelling is not accepted as
an alias.

---

## 9. Builders

### 9.1. Entity Registration

**Module:** `src/jmap_client/mail/mail_entities.nim`

Email is registered with full method support — `/get`, `/changes`,
`/set`, `/query`, `/queryChanges`, `/copy`, `/import`. The registration
provides per-verb method-name resolvers and template-typed associations
for the generic dispatch layer.

```nim
# Per-verb method name resolvers — read path
func methodEntity*(T: typedesc[Email]): MethodEntity = meEmail
func getMethodName*(T: typedesc[Email]): MethodName = mnEmailGet
func changesMethodName*(T: typedesc[Email]): MethodName = mnEmailChanges
func queryMethodName*(T: typedesc[Email]): MethodName = mnEmailQuery
func queryChangesMethodName*(T: typedesc[Email]): MethodName = mnEmailQueryChanges

func capabilityUri*(T: typedesc[Email]): string = "urn:ietf:params:jmap:mail"

# Type associations consumed by generic builders
template changesResponseType*(T: typedesc[Email]): typedesc = ChangesResponse[Email]
template filterType*(T: typedesc[Email]): typedesc = EmailFilterCondition

registerJmapEntity(Email)
registerQueryableEntity(Email)
registerSettableEntity(Email)        # Part E — listed for completeness

# Chainable-method participation gates (RFC 8620 §3.7 back-reference chains)
registerChainableMethod(QueryResponse[Email])
registerChainableMethod(GetResponse[Email])         # chains OUT to Thread/get via rpListThreadId
registerChainableMethod(GetResponse[thread.Thread]) # chains OUT to Email/get via rpListEmailIds
```

Set/copy/import resolvers (`setMethodName`, `copyMethodName`,
`importMethodName`, `createType`, `updateType`, `setResponseType`,
`copyItemType`, `copyResponseType`) are also registered in this module
alongside `registerSettableEntity(Email)` but belong to Part E.

The three `registerChainableMethod` calls gate the §4.10 first-login
workflow at compile time: any builder that consumes a `ResultReference`
sourced from a non-registered method shape fails to compile. The
`Thread` qualifier (`thread.Thread`) disambiguates the local module
import — `mail_entities.nim` re-imports the unqualified `Thread` from
the entity registry alongside the JMAP `Thread` entity.

`SearchSnippet` and `VacationResponse` are deliberately **not**
registered (Decision A7) — they use custom builder functions in
`mail_methods.nim` instead, keyed directly on the relevant `MethodName`
enum variants.

### 9.2. addEmailGet

**Module:** `src/jmap_client/mail/mail_builders.nim`

```nim
func addEmailGet*(
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ResponseHandle[GetResponse[Email]]) =
  addGet[Email](b, accountId, ids, properties, extras = bodyFetchOptions.toExtras())
```

- Thin wrapper over the generic `addGet[Email]` (`builder.nim`) with
  body-fetch options merged via the generic's `extras: seq[(string,
  JsonNode)]` parameter.
- `default(EmailBodyFetchOptions).toExtras()` yields an empty seq — no
  extra keys, correct RFC default.
- `addGet[Email]` resolves `getMethodName(Email)`, `capabilityUri(Email)`
  via `mixin` from `mail_entities.nim`.
- Returns `(RequestBuilder, ResponseHandle[GetResponse[Email]])` — the
  immutable builder pattern (new builder + typed response handle).

### 9.3. addEmailGetByRef

**Module:** `src/jmap_client/mail/mail_builders.nim`

Sibling for RFC 8620 §3.7 back-reference chains.

```nim
func addEmailGetByRef*(
    b: RequestBuilder,
    accountId: AccountId,
    idsRef: ResultReference,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ResponseHandle[GetResponse[Email]])
```

Wraps `addEmailGet` with a `referenceTo[seq[Id]](idsRef)`-bound
`Referencable`; the generic `addGet[T]` routes `rkReference` variants to
the `#ids` wire key.

### 9.4. addThreadGetByRef

**Module:** `src/jmap_client/mail/mail_builders.nim`

Sibling of generic `addGet[Thread]` for back-reference chains. `Thread`
is read-only, so only `properties` is forwarded.

```nim
func addThreadGetByRef*(
    b: RequestBuilder,
    accountId: AccountId,
    idsRef: ResultReference,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[Thread]])
```

### 9.5. Email/changes — Generic Builder (D17)

No custom builder. Email/changes is "a standard /changes method" (RFC
§4.3) with no extensions. Callers use `addChanges[Email]` directly,
which template-resolves `changesResponseType(Email) =
ChangesResponse[Email]` via the `mail_entities.nim` association.

Precedent: only entities with extensions get custom builders (Mailbox
has `addMailboxChanges` because the response carries
`updatedProperties`).

### 9.6. addEmailQuery (D10)

**Module:** `src/jmap_client/mail/mail_builders.nim`

Email/query has two extensions beyond generic `/query`: typed
`EmailComparator` sort, and `collapseThreads: bool`. The generic
`addQuery[T, C, SortT]` is parameterised over the sort element type, so
no custom builder is needed for the sort plumbing — only for emitting
`collapseThreads`.

```nim
func addEmailQuery*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[EmailFilterCondition]] = Opt.none(Filter[EmailFilterCondition]),
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = false,
): (RequestBuilder, ResponseHandle[QueryResponse[Email]]) =
  addQuery[Email, EmailFilterCondition, EmailComparator](
    b, accountId, filter, sort, queryParams,
    extras = @[("collapseThreads", %collapseThreads)],
  )
```

- Three-parameter generic instantiation:
  `addQuery[Email, EmailFilterCondition, EmailComparator]`. The generic
  resolves `EmailComparator.toJson` and `EmailFilterCondition.toJson`
  via `mixin` at the instantiation site.
- `collapseThreads` is emitted unconditionally as an extra arg
  (`true`/`false`) — the wire shape is stable for round-trip testing.

### 9.7. addEmailQueryChanges (D18)

**Module:** `src/jmap_client/mail/mail_builders.nim`

Parallel to D10. Email/queryChanges (RFC §4.5) extends standard
`/queryChanges` with `collapseThreads: bool`.

```nim
func addEmailQueryChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filter: Opt[Filter[EmailFilterCondition]] = Opt.none(Filter[EmailFilterCondition]),
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
    collapseThreads: bool = false,
): (RequestBuilder, ResponseHandle[QueryChangesResponse[Email]]) =
  addQueryChanges[Email, EmailFilterCondition, EmailComparator](
    b, accountId, sinceQueryState, filter, sort, maxChanges, upToId, calculateTotal,
    extras = @[("collapseThreads", %collapseThreads)],
  )
```

---

## 10. Custom Methods and Compound Chains

### 10.1. addEmailParse (D11)

**Module:** `src/jmap_client/mail/mail_methods.nim`

**RFC reference:** §4.9.

```nim
func addEmailParse*(
    b: RequestBuilder,
    accountId: AccountId,
    blobIds: seq[BlobId],
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ResponseHandle[EmailParseResponse])
```

- Custom builder — Email/parse has no generic counterpart.
- `blobIds: seq[BlobId]` (typed) — Email/parse does not support result
  references on `blobIds`.
- `bodyFetchOptions.toExtras()` keys merged into request args after the
  standard frame (insertion order preserved).
- Returns `EmailParseResponse` handle. Callers receive `Table[BlobId,
  ParsedEmail]` — fully typed, no second parsing step.

### 10.2. addSearchSnippetGet (D12)

**Module:** `src/jmap_client/mail/mail_methods.nim`

**RFC reference:** §5.1.

```nim
func addSearchSnippetGet*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    firstEmailId: Id,
    restEmailIds: seq[Id] = @[],
): (RequestBuilder, ResponseHandle[SearchSnippetGetResponse])
```

- `filter` is **required** (not `Opt`) — search snippets are meaningless
  without a search filter.
- `emailIds` non-emptiness enforced structurally via the **cons-cell
  pattern**: `firstEmailId: Id, restEmailIds: seq[Id] = @[]`. Every call
  provides at least one email id. The builder concatenates `[firstEmailId]
  & restEmailIds` internally.
- Filter serialised via `serializeFilter(filter).toJsonNode()`; the
  `Filter[C].toJson` cascade resolves `EmailFilterCondition.toJson` via
  `mixin`.
- Builder is total: no `Result`, no validation. Every input combination
  valid by construction.

### 10.3. addSearchSnippetGetByRef

**Module:** `src/jmap_client/mail/mail_methods.nim`

Sibling for RFC 8620 §3.7 back-reference chains — `emailIds` sourced from
a previous invocation's response.

```nim
func addSearchSnippetGetByRef*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    emailIdsRef: ResultReference,
): (RequestBuilder, ResponseHandle[SearchSnippetGetResponse])
```

`filter` remains mandatory. The cons-cell non-emptiness discipline of
the literal-ids overload does not propagate — a back-reference always
resolves to whatever the referenced response contains, including possibly
an empty list.

### 10.4. addEmailQueryWithThreads — RFC 8621 §4.10 Chain

**Module:** `src/jmap_client/mail/mail_builders.nim`

Encodes the RFC 8621 §4.10 first-login workflow as a typed compound
chain: 4 invocations with back-references.

```nim
const DefaultDisplayProperties*: seq[string] = @[
  "threadId", "mailboxIds", "keywords", "hasAttachment", "from", "subject",
  "receivedAt", "size", "preview",
]

type EmailQueryThreadChain* {.ruleOff: "objects".} = object
  queryH*: ResponseHandle[QueryResponse[Email]]
  threadIdFetchH*: ResponseHandle[GetResponse[Email]]
  threadsH*: ResponseHandle[GetResponse[Thread]]
  displayH*: ResponseHandle[GetResponse[Email]]

type EmailQueryThreadResults* {.ruleOff: "objects".} = object
  query*: QueryResponse[Email]
  threadIdFetch*: GetResponse[Email]
  threads*: GetResponse[Thread]
  display*: GetResponse[Email]

func addEmailQueryWithThreads*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    sort: seq[EmailComparator] = @[],
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = true,
    displayProperties: seq[string] = DefaultDisplayProperties,
    displayBodyFetchOptions: EmailBodyFetchOptions = EmailBodyFetchOptions(
      fetchBodyValues: bvsAll, maxBodyValueBytes: Opt.some(UnsignedInt(256))),
): (RequestBuilder, EmailQueryThreadChain)

func getAll*(
    resp: Response, handles: EmailQueryThreadChain
): Result[EmailQueryThreadResults, MethodError]
```

- `filter` is mandatory (RFC §4.10 ¶1 — first-login always filters to a
  user-visible mailbox scope).
- `collapseThreads` defaults to `true` per RFC §4.10 example.
- Emits the exact 4-invocation back-reference chain from the RFC,
  byte-for-byte: `Email/query` → `Email/get(threadId only)` →
  `Thread/get` → `Email/get(display properties + body values)`.
- `ResultReference` paths sourced from `RefPath` constants (`rpIds`,
  `rpListThreadId`, `rpListEmailIds`) — no stringly-typed JSON Pointers.
- `getAll` is monomorphic over `EmailQueryThreadChain` — co-located with
  the builder rather than placed in `dispatch.nim` because there is no
  parametric shape to share with the dispatch layer.

### 10.5. addEmailQueryWithSnippets

**Module:** `src/jmap_client/mail/mail_methods.nim`

Compound Email/query + SearchSnippet/get chain (RFC 8621 §4.10 + §5.1).
Two invocations with a back-reference from the snippet request's
`emailIds` to the query's `/ids`.

```nim
type EmailQuerySnippetChain* =
  ChainedHandles[QueryResponse[Email], SearchSnippetGetResponse]

func addEmailQueryWithSnippets*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = false,
): (RequestBuilder, EmailQuerySnippetChain)
```

- `filter` is mandatory — snippets are meaningless without a query
  context.
- The filter is duplicated literally on the wire to both invocations
  rather than shared via a second back-reference (simplicity over
  wire-clever).
- `EmailQuerySnippetChain` is a domain-named alias of
  `ChainedHandles[A, B]` from `dispatch.nim`. Fields `first` / `second`
  inherit from the generic.

---

## 11. Module Organisation

### 11.1. File Layout (D14)

All read-path files live under `src/jmap_client/mail/`. Organisation
follows domain cohesion: entity + its method parameter types together
(parallels `mailbox.nim`).

| File | Read-path types and functions |
|------|-------------------------------|
| `email.nim` | `Email`, `ParsedEmail`, `PlainSortProperty`, `KeywordSortProperty`, `EmailComparatorKind`, `EmailComparator`, `BodyValueScope`, `EmailBodyFetchOptions`, `plainComparator`, `keywordComparator`, `isLeaf` |
| `snippet.nim` | `SearchSnippet` |
| `mail_filters.nim` | `EmailFilterCondition`, `EmailHeaderFilter` (also hosts `MailboxFilterCondition`) |
| `serde_email.nim` | `emailFromJson`, `parsedEmailFromJson`, `Email.toJson`, `ParsedEmail.toJson`, `emailComparatorFromJson`, `EmailComparator.toJson`, `EmailBodyFetchOptions.toExtras`, `EmailBodyFetchOptions.toJson`, internal helpers (`ConvenienceHeaders`, `BodyFields`, `parseConvenienceHeaders`, `parseBodyFields`, `parseBodyValues`, `parseBodyPartArray`, `parseRawHeaders`, `parseHeaderValueArray`, `parseOpt*` family, `emitOptStringSeqOrNull`, `emitOptAddressesOrNull`) |
| `serde_snippet.nim` | `searchSnippetFromJson`, `SearchSnippet.toJson` |
| `serde_mail_filters.nim` | `EmailFilterCondition.toJson`, `EmailHeaderFilter.toJson`, extracted helpers (`emitDateSizeFilters`, `emitKeywordFilters`, `emitTextSearchFilters`); also hosts `MailboxFilterCondition.toJson` |
| `mail_entities.nim` | Per-verb method-name resolvers, `capabilityUri`, type-association templates, `registerJmapEntity(Email)`, `registerQueryableEntity(Email)`, `registerChainableMethod(QueryResponse[Email])`, `registerChainableMethod(GetResponse[Email])`, `registerChainableMethod(GetResponse[thread.Thread])` |
| `mail_builders.nim` | `addEmailGet`, `addEmailGetByRef`, `addThreadGetByRef`, `addEmailQuery`, `addEmailQueryChanges`, `EmailQueryThreadChain`, `EmailQueryThreadResults`, `addEmailQueryWithThreads`, `getAll` |
| `mail_methods.nim` | `addEmailParse`, `addSearchSnippetGet`, `addSearchSnippetGetByRef`, `EmailParseResponse`, `SearchSnippetGetResponse`, typedesc-overload `fromJson` wrappers, `EmailQuerySnippetChain`, `addEmailQueryWithSnippets` |

`email.nim` also hosts the Part E write-path types (`EmailCreatedItem`,
`EmailImportResponse`, `EmailCopyItem`, `EmailImportItem`,
`NonEmptyEmailImportMap`) for module cohesion; their specifications live
in Part E. Similarly, `mail_builders.nim` hosts the Mailbox builders
(Part B) and Email write-path builders (Part E).

### 11.2. Re-Export Hubs

**`mail/types.nim`** re-exports `email`, `snippet`, `mail_filters`
alongside all other Layer 1 mail modules.

**`mail/serialisation.nim`** re-exports `serde_email`, `serde_snippet`,
`serde_mail_filters` alongside all other Layer 2 mail serde modules.

`mail_builders.nim` and `mail_methods.nim` re-export the relevant serde
modules whose `fromJson` overloads are needed at the dispatch call site
(generic responses resolve `T.fromJson` via `mixin` at the outer
instantiation site).

---

## 12. Test Specification

Test files live under `tests/` following the established naming
convention (t-prefix, domain-cohesive grouping).

| File | Coverage |
|------|----------|
| `tests/unit/mail/temail.nim` | `isLeaf` predicate; smart constructors for Part E types co-located in `email.nim` (`initNonEmptyEmailImportMap`) |
| `tests/serde/mail/tserde_email.nim` | `Email`, `ParsedEmail`, `EmailComparator`, `EmailBodyFetchOptions` serde — golden path, sparse property-filter shapes, dynamic header routing, missing/wrong-type fields, comparator discriminant synthesis |
| `tests/serde/mail/tserde_snippet.nim` | `SearchSnippet` and `SearchSnippetGetResponse` / `EmailParseResponse` fromJson; `notParsable` wire spelling |
| `tests/serde/mail/tserde_mail_filters.nim` | `EmailFilterCondition` + `EmailHeaderFilter` toJson (extends Mailbox filter tests) |
| `tests/serde/mail/tserde_email_adversarial.nim` | Boundary exploitation: two-phase parsing interference, dynamic header injection (empty name, too many segments, unknown form), comparator discriminant edge cases (case, whitespace, missing keyword), header filter character set, duplicate `bodyValues` keys, recursive multipart depth, Cyrillic homoglyph keys, large `size`, cross-field semantic contradictions |
| `tests/property/tprop_mail_d.nim` | Round-trip properties (Email, ParsedEmail, EmailComparator), totality on arbitrary `JsonNode`, filter-condition field-count, body-fetch-options structural correspondence |
| `tests/serde/mail/tserde_email_integration.nim` | Cross-component: shared helper parity between Email and ParsedEmail, full-Email round-trip, dynamic-header Phase 2 round-trip, builder body-fetch-options parity, builder–filter chain |
| `tests/protocol/tmail_builders.nim` | `addEmailGet`, `addEmailQuery`, `addEmailQueryChanges`, by-ref siblings, `addEmailQueryWithThreads` (extends Mailbox builders) |
| `tests/protocol/tmail_methods.nim` | `addEmailParse`, `addSearchSnippetGet`, `addSearchSnippetGetByRef`, `addEmailQueryWithSnippets` (extends VacationResponse tests) |

Tests use the shared `mfixtures` factories (`makeEmail`, `makeParsedEmail`,
`makeEmailComparator`, `makeKeywordComparator`, `makeEmailBodyFetchOptions`,
`makeEmailFilterCondition`, `makeSearchSnippet`, plus JSON variants) and
the shared `mproperty` generators (`genEmail`, `genParsedEmail`,
`genEmailComparator`, `genEmailBodyFetchOptions`,
`genEmailFilterCondition`, `genSearchSnippet`, plus shared composers
`genConvenienceHeaders`, `genBodyFields`).

---

## 13. Decision Traceability Matrix

| # | Decision | Chosen | Primary Principles |
|---|----------|--------|-------------------|
| D1 | Email field sealing | Plain public fields (Pattern A's 28-accessor cost outweighs the benefit; ProveInit prevents uninitialised use) | Code reads like the spec |
| D2 | Email field optionality | Every server-shaped field `Opt[T]`; default-properties shape populates each `Opt`, sparse property-filter shape populates only requested fields | Code reads like the spec, Postel's law, One type, two shapes |
| D3 | Convenience header `Opt` semantics | `Opt.none` = header absent in message (when the property was requested); requestor-side absence reflected by upstream `Email.{field}` being `Opt.none` because the property was filtered out | One source of truth, Code reads like the spec |
| D4 | Dynamic header fromJson routing | Two-phase: structured extraction by direct key lookup, then single iteration for `header:*` discovery | Code reads like the spec, Parse once at the boundary |
| D5 | Email toJson Opt body handling | Emit all domain fields always (`Opt.none` → null, empty seq → `[]`, empty Table → `{}`); dynamic headers as N top-level keys | One source of truth, Code reads like the spec |
| D6 | textBody/htmlBody/attachments leaf-only validation | Trust server (Postel's law); provide `isLeaf` convenience predicate | Postel's law, DDD |
| D7 | ParsedEmail code sharing with Email | Full field duplication (different domain aggregates); shared serde helper procs (`ConvenienceHeaders`, `BodyFields`, `parseConvenienceHeaders`, `parseBodyFields`, `parseRawHeaders`, `parseHeaderValueArray`) | DRY — duplicated appearance is not duplicated knowledge, DDD |
| D8 | EmailComparator structure | Case object + split enums (`PlainSortProperty`, `KeywordSortProperty`); both constructors total | Make illegal states unrepresentable, Total functions |
| D9 | EmailBodyFetchOptions | `BodyValueScope` enum (5 variants) replaces three RFC booleans; serde via `toExtras` (returns `seq[(string, JsonNode)]`) and standalone `toJson` | Booleans are a code smell, DRY, Make the right thing easy |
| D10 | addEmailQuery sort type | Custom builder around generic `addQuery[Email, EmailFilterCondition, EmailComparator]`; `mixin toJson` resolves both filter and sort serialisation; `collapseThreads` via `extras` | Make illegal states unrepresentable |
| D11 | Email/parse response structure | Dedicated `EmailParseResponse` with `Table[BlobId, ParsedEmail]`; typed `BlobId` keys and failure lists | Parse once at the boundary, Newtype everything that has meaning |
| D12 | SearchSnippet/get filter + emailIds | Required `filter` (not Opt); cons-cell `firstEmailId + restEmailIds` for non-empty enforcement on the literal-ids overload | Total functions, Make the right thing easy |
| D13 | SearchSnippet response structure | `notFound: seq[Id]` collapsing null/`[]` to empty seq via `collapseNullToEmptySeq` | Parse once at the boundary, Code reads like the spec |
| D14 | Module organisation | Domain cohesion: `email.nim` co-locates entity + read-path param types + write-path Part E types; `mail_filters.nim` co-locates Email and Mailbox filter conditions; `mail_builders.nim` and `mail_methods.nim` extend across parts | DDD, DRY |
| D15 | Email fromJson lenient behaviour | Lenient at server-to-client boundary — `Opt[MailboxIdSet]` admits null/absent; trust server contract that present values satisfy RFC §4.1.1 non-empty | Postel's law, Parse once at the boundary |
| D16 | EmailFilterCondition `inMailboxOtherThan` non-empty | No enforcement; empty list vacuous but not illegal | Filter = toJson-only value object |
| D17 | Email/changes builder | Generic `addChanges[Email]`; `changesResponseType(Email) = ChangesResponse[Email]` template-resolved | Code reads like the spec |
| D18 | Email/queryChanges builder | Custom `addEmailQueryChanges` parallel to D10 (`collapseThreads` extra + typed `EmailComparator` sort) | DRY |
| D19 | bodyValues Table key type | `Table[PartId, EmailBodyValue]` (typed `PartId` key with borrowed `hash`) | Newtype everything that has meaning |
| D20 | ParsedEmail blobId/size exclusion | Excluded — `blobId` redundant (response keyed by `BlobId`); `size` derivable from blob | DDD |
