# RFC 8621 JMAP Mail — Design E: EmailBlueprint Creation Aggregate

This document is the detailed specification for `EmailBlueprint` — the
creation model for client-constructed Emails — together with the supporting
vocabulary types it requires. It covers Layers 1 (L1 types) and 2 (L2 serde
— toJson only, unidirectional).

Part E is pure creation vocabulary. It defines the central aggregate
(`EmailBlueprint`) plus four supporting types and then specifies the two
`toJson` serialisers that take a blueprint to JMAP creation JSON. No
methods, no entity registration, no builders — Email/set, Email/copy,
Email/import, and EmailSubmission are deferred to Parts F, G, H, and I
respectively.

Builds on the cross-cutting architecture design
(`05-mail-architecture.md` §8.4–8.6), the existing RFC 8620 infrastructure
(`00-architecture.md` through `04-layer-4-design.md`), Design A
(`06-mail-a-design.md`), Design B (`07-mail-b-design.md`), Design C
(`08-mail-c-design.md` — `BlueprintBodyPart`, `HeaderPropertyKey`,
`HeaderValue`, `EmailBodyValue`, `PartId`, `EmailAddress`), and Design D
(`09-mail-d-design.md` — Email read model). Decisions from the
cross-cutting doc are referenced by section number.

---

## Table of Contents

1. [Scope](#1-scope)
2. [Creation Aggregate Overview](#2-creation-aggregate-overview)
3. [EmailBlueprint](#3-emailblueprint)
4. [Supporting Creation Types](#4-supporting-creation-types)
5. [Part C Modifications](#5-part-c-modifications)
6. [Test Specification](#6-test-specification)
7. [Decision Traceability Matrix](#7-decision-traceability-matrix)

---

## 1. Scope

### 1.1. Supporting Types Covered

| Type | Module | Rationale |
|------|--------|-----------|
| `EmailBlueprint` | `email_blueprint.nim` | Creation-model aggregate for Email/set |
| `EmailBlueprintBody` | `email_blueprint.nim` | Case-object wrapping the body input; discriminant encodes `bodyStructure` XOR flat-list at the type level |
| `BlueprintBodyValue` | `body.nim` (extended) | Value-only sibling of `EmailBodyValue`; no creation-invalid flag fields. Co-located with its consumer field `BlueprintBodyPart.bpsInline.value` (§5.1) so `email_blueprint.nim → body.nim` remains a one-way import |
| `NonEmptyMailboxIdSet` | `mailbox.nim` | Parallel to `MailboxIdSet`; encodes "at least one" at the type level |
| `BlueprintEmailHeaderName` | `headers.nim` | Distinct string; header name valid for Email top-level `extraHeaders` (forbids Content-*); identity on name only (intra-Table uniqueness) |
| `BlueprintBodyHeaderName` | `headers.nim` | Distinct string; header name valid for `BlueprintBodyPart.extraHeaders` (forbids Content-Transfer-Encoding); identity on name only |
| `BlueprintHeaderMultiValue` | `headers.nim` | Case object carrying form + non-empty seq of values for a single header field; paired with a Name key to form an extraHeaders entry |
| `NonEmptySeq[T]` | `primitives.nim` (extended) | Generic `distinct seq[T]` with at-least-one invariant; used by `BlueprintHeaderMultiValue` (seven variants); available for future parts |
| `EmailBlueprintConstraint` | `email_blueprint.nim` | Enum of runtime cross-field constraints the smart constructor checks |
| `EmailBlueprintError` | `email_blueprint.nim` | Case-object error discriminated by the constraint enum |
| `EmailBlueprintErrors` | `email_blueprint.nim` | Distinct `seq[EmailBlueprintError]`, invariant non-empty on the err rail |
| `BodyPartPath` | `email_blueprint.nim` | Distinct `seq[int]`; tree path locating a multipart body part |
| `BodyPartLocation` | `email_blueprint.nim` | Case object naming an offending body part (inline/blob-ref/multipart) for `ebcBodyPartHeaderDuplicate` |
| `EmailBodyKind` | `email_blueprint.nim` | Discriminant for `EmailBlueprintBody` (`ebkStructured` vs `ebkFlat`) |
| `parseEmailBlueprint` | `email_blueprint.nim` | Single public constructor — accumulating error rail |
| `flatBody`, `structuredBody` | `email_blueprint.nim` | Total helpers for constructing `EmailBlueprintBody` at call sites |
| `parseNonEmptyMailboxIdSet` | `mailbox.nim` | Smart constructor for the new distinct set |
| `parseBlueprintEmailHeaderName` | `headers.nim` | Strict smart constructor for the top-level header name; lowercase-normalises, rejects `content-*` |
| `parseBlueprintBodyHeaderName` | `headers.nim` | Strict smart constructor for the body-part header name; lowercase-normalises, rejects `content-transfer-encoding` |
| `parseNonEmptySeq` | `primitives.nim` | Generic smart constructor rejecting empty seq |
| `rawMulti`, `textMulti`, `addressesMulti`, ... | `headers.nim` | Per-form ergonomic constructors for `BlueprintHeaderMultiValue` |

### 1.2. Deferred

**Part F (Email write method):** `Email/set` (create, update, destroy),
`EmailSetResponse`, typed set-error accessors for create
(`blobNotFound`, `tooManyKeywords`, `tooManyMailboxes`). Part F consumes
`EmailBlueprint` via `toJson` but does not modify it.

**Part G (Email/copy + compound handles):** `Email/copy`, `EmailCopyItem`,
compound-handle pattern (debut), `addEmailCopyChained`. The compound-handle
infrastructure introduced in Part G is later reused by Part I.

**Part H (Email/import):** `Email/import`, `EmailImport` request item,
`addEmailImport` builder. Blob ingest is independent of `EmailBlueprint`.

**Part I (EmailSubmission):** `EmailSubmission`, `Envelope`,
`SubmissionAddress`, `DeliveryStatus`, `UndoStatus`, `SubmissionEmailRef`,
and EmailSubmission's methods.

**Blob handling** remains deferred to a separate future part per
architecture §4.6. `BlobId` continues to be `Id` until the dedicated blob
part introduces a distinct type.

### 1.3. Relationship to Cross-Cutting Design

This document refines `05-mail-architecture.md` §8.4–8.6 into
implementation-ready specification for the creation-aggregate bounded
context. Several architectural sketches are tightened in this part:

- The `bodyValues: Table[PartId, EmailBodyValue]` field on
  `EmailBlueprint` from architecture §8.4 is **denormalised** into the
  body tree (§3.1, §5.1). `bodyValues` becomes a derived accessor, not a
  stored field. Constraint 8 from architecture §8.5 is thereby eliminated.
- `EmailBlueprint.mailboxIds` uses a new `NonEmptyMailboxIdSet` type
  (§4.2) rather than `MailboxIdSet`, encoding architecture §8.5's
  "at least one" invariant at the type level. `parseEmailBlueprint`
  accepts `NonEmptyMailboxIdSet` directly as its parameter; the caller
  is required to construct it explicitly via `parseNonEmptyMailboxIdSet`.
  Constraint 1 is thereby eliminated from the smart constructor.
- `EmailBlueprint.extraHeaders` and `BlueprintBodyPart.extraHeaders` use
  two new distinct **name-only** key types `BlueprintEmailHeaderName`
  and `BlueprintBodyHeaderName` (§4.3, §4.4, §5.3), paired with a new
  case-object value type `BlueprintHeaderMultiValue` (§4.5) that
  carries the form and a `NonEmptySeq[T]` (§4.6) of values. Compared to
  the earlier "distinct HeaderPropertyKey" design, this name-only key
  design eliminates three additional constraints at the type level:
  constraint 3d (no two extraHeaders entries for the same header — the
  Table key's name-granularity identity), constraint 10 (key/value
  form consistency — form now lives once, on the value), and an
  implicit "empty header" state (prevented by `NonEmptySeq[T]`).
  Constraints 4 and 9 continue to be type-level via the forbidden-name
  checks in the two Name smart constructors.
- `BlueprintBodyValue` (§4.1) strips the read-model flag fields
  (`isEncodingProblem`, `isTruncated`) from `EmailBodyValue`. Constraint
  6 is thereby eliminated.
- A new `EmailBlueprintBody` case object (§3.2) wraps the body input.
  Its discriminant (`kind: EmailBodyKind`) makes the "bodyStructure XOR
  flat-list" constraint a compile-time fact. `parseEmailBlueprint`
  accepts `EmailBlueprintBody` as a single parameter rather than four
  independent body fields. Constraint 5 (the body-XOR) is thereby
  eliminated from the smart constructor.
- The smart constructor's error rail carries a domain-specific triad
  (`EmailBlueprintConstraint` enum, `EmailBlueprintError` case object,
  `EmailBlueprintErrors` distinct non-empty seq) rather than a generic
  `seq[ValidationError]`.

**Eight type-level eliminations** (constraints 1, 2, 3d, 4, 5, 6, 8,
9, 10 — counting "no `headers` array" as the structural absence of a
field; counting signature-level mailboxIds and body shapes separately;
counting intra-Table name uniqueness and key/value form consistency
both as consequences of the name-only-key + form-on-value
redesign) reduce architecture §8.5's nine runtime constraints to
**six** runtime enum variants. The runtime variants cover: the two
`ebkFlat` content-type checks, the allowed-forms check, and three
"HeaderDuplicate" variants covering RFC §4.6's three
cross-representation duplicate rules (Email top-level, bodyStructure
root vs Email top-level, within-body-part). Three duplicate rules
plus one intra-Table axis were identified during post-write RFC audits —
see DTM rows E25, E26, and E28 for details.

### 1.4. General Conventions Applied

- **Pure L1/L2 code** — `{.push raises: [], noSideEffect.}` at the top of
  every module in this part. Only `func` permitted (no `proc`).
- **Result-based error handling** — every smart constructor returns
  `Result`. No exceptions for domain-level failure.
- **Opt[T] for optional fields** — never `std/options`.
- **Typed errors on the error rail** — the aggregate error type
  (`EmailBlueprintErrors`) carries enumerated variants, never collapsed
  strings.
- **Pattern A sealing where invariants exist** — `EmailBlueprint` follows
  the `HeaderPropertyKey` precedent (Part C §2.3): module-private `raw*`
  fields with same-name UFCS accessors as the public API.
- **Strict on construction, lenient on reads** — the read-model Email in
  Part D accepts server-provided data per Postel's law; Part E enforces
  strict RFC §4.6 invariants on client-constructed blueprints.
- **Creation types serialise unidirectionally** — `toJson` only, no
  `fromJson`. `fromJson` would create a second construction path,
  violating "constructors are privileges, not rights."

### 1.5. Module Summary

| Module | Layer | Status | Contents |
|--------|-------|--------|----------|
| `email_blueprint.nim` | L1 | **new** | `EmailBlueprint`, `EmailBlueprintBody`, `EmailBodyKind`, `EmailBlueprintConstraint`, `EmailBlueprintError`, `EmailBlueprintErrors`, `BodyPartPath`, `BodyPartLocation`, `BodyPartLocationKind`, `parseEmailBlueprint`, `flatBody`, `structuredBody`, accessors, `bodyValues` |
| `serde_email_blueprint.nim` | L2 | **new** | `toJson` for `EmailBlueprint` |
| `mailbox.nim` | L1 | extended | `NonEmptyMailboxIdSet`, `parseNonEmptyMailboxIdSet` added under a "Mailbox ID Collections" section |
| `headers.nim` | L1 | extended | Under a new "Creation-Model Header Vocabulary" labelled section: `BlueprintEmailHeaderName`, `BlueprintBodyHeaderName`, `BlueprintHeaderMultiValue`, per-form helper constructors (`rawMulti`, `textMulti`, ...), smart constructors |
| `serde_headers.nim` | L2 | extended | Serde for the two new distinct-string name types; wire-key composition for `BlueprintHeaderMultiValue` (handled at the consumer layer — see `serde_email_blueprint.nim` and `serde_body.nim`) |
| `primitives.nim` | L1 | extended | `NonEmptySeq[T]`, `parseNonEmptySeq[T]`, `defineNonEmptySeqOps[T]` template |
| `body.nim` | L1 | modified | Hosts new `BlueprintBodyValue` (§4.1); `BlueprintBodyPart.bpsInline` gains `value: BlueprintBodyValue`; `extraHeaders` retyped to `Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]` |
| `serde_body.nim` | L2 | modified | Hosts `BlueprintBodyValue.toJson` (§4.1.3); `BlueprintBodyPart.toJson` emits `partId` only on inline parts; the `value` is harvested separately by `EmailBlueprint.toJson` |
| `types.nim` | — | extended | Re-exports the new public types |

---

## 2. Creation Aggregate Overview

### 2.1. Why a Cluster, Not a Single Type

`EmailBlueprint` is the central creation aggregate, but it does not stand
alone. Seven supporting types encode RFC 8621 §4.6 invariants at the
type level, collapsing what would otherwise be runtime constraints
into structural guarantees:

- **`EmailBlueprintBody`** (§3.2) — case object whose discriminant
  encodes `bodyStructure` XOR flat-list at the type level. Collapses
  "bodyStructure XOR textBody/htmlBody/attachments" (RFC §4.6
  constraint 5) into a type-level fact.
- **`BlueprintBodyValue`** (§4.1) — body-value creation type stripping
  the read-model flag fields. Collapses "isEncodingProblem and
  isTruncated must be false" (architecture §8.5 constraint 6) into a
  type-level fact.
- **`NonEmptyMailboxIdSet`** (§4.2) — distinct `HashSet[Id]` with
  at-least-one invariant. Collapses "mailboxIds must contain at least
  one entry" (architecture §8.5 constraint 1) into a type-level fact.
- **`BlueprintEmailHeaderName`** (§4.3) — `distinct string`; lowercase
  header name forbidding `content-*`. Collapses constraint 4 AND
  constraint 3d (no two extraHeaders entries for the same header —
  via the Table-key name-only identity).
- **`BlueprintBodyHeaderName`** (§4.4) — `distinct string` forbidding
  `content-transfer-encoding`, same name-only identity pattern.
  Collapses constraint 9 AND constraint 3d for body parts.
- **`BlueprintHeaderMultiValue`** (§4.5) — case object carrying form +
  a non-empty seq of values for a single header field. Collapses the
  former constraint 10 (key/value form consistency) into a type-level
  single-source-of-truth: form lives exactly once, on the value's
  discriminant.
- **`NonEmptySeq[T]`** (§4.6) — generic `distinct seq[T]` with
  at-least-one invariant. Collapses "header property with no values"
  into a type-level impossibility wherever used.

The aggregate is designed so the type system does as much of the work as
possible. What remains for the smart constructor is genuinely cross-field:
constraints that cannot be encoded structurally because they depend on the
simultaneous state of multiple fields.

### 2.2. The Strip-Pattern, Five Levels Deep

The design applies one pattern five times at different levels of the
aggregate — from leaf values up to the smart constructor's signature.
Each application reduces creation-model complexity by removing state
that cannot legally exist at the creation boundary:

| Level | Pattern | Artefact | RFC invariant it encodes |
|-------|---------|----------|--------------------------|
| Leaf value | **Strip fields** — remove read-only flag fields that must be false on creation | `EmailBodyValue` → `BlueprintBodyValue` | RFC §4.6: "isEncodingProblem and isTruncated MUST be false" |
| Map structure | **Relocate data** — co-locate the value with the partId that references it | `Table[PartId, BlueprintBodyValue]` on EmailBlueprint → `value` field on inline body parts | RFC §4.6: "if partId given, MUST be present in bodyValues" |
| Header key names (and their form dimension) | **Forbid names and separate form from key** — introduce name-only distinct string keys that reject context-forbidden names AND move form onto the paired value, so no key/value form disagreement is representable and no two entries can share a name | `Table[HeaderPropertyKey, HeaderValue]` → `Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]` / `Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]` | RFC §4.6: "no Content-* at top level", "no Content-Transfer-Encoding on body parts", "no duplicate header representation" (intra-Table axis), and key/value form consistency |
| Header value cardinality | **Non-empty collection** — use a generic `NonEmptySeq[T]` inside the multi-value type to prevent the "header exists with zero values" degenerate state | `seq[T]` → `NonEmptySeq[T]` inside `BlueprintHeaderMultiValue` (seven payloads) | Implicit RFC well-formedness: a header property with no values has no wire expression |
| Signature input | **Strip illegal combinations** — make smart-constructor parameters pre-validated at the type level so no runtime check for "mailboxIds empty" or "body-XOR violated" is reachable | `openArray[Id]` + four independent body fields → `NonEmptyMailboxIdSet` + `EmailBlueprintBody` case object | RFC §4.6: "at least one Mailbox" and "bodyStructure XOR flat-list" |

Each application is principled on the same grounds:

- **Make illegal states unrepresentable.** A state that is forbidden on
  creation should not be expressible in the creation type. The type system
  enforces what a runtime check would otherwise have to verify repeatedly.
- **Parse once at the boundary.** The strip or the rename happens at the
  earliest possible construction point — smart constructor, distinct type,
  or field-type choice — so every downstream consumer receives
  pre-validated data.
- **Different knowledge deserves different appearance.** The read model
  and the creation model are different aggregates. Sharing a type for both
  would collapse two distinct sets of invariants into one and force
  runtime checks that the type system could otherwise enforce.

### 2.3. Relationship to Part C

Part C introduced `BlueprintBodyPart` as the creation-model counterpart to
`EmailBodyPart`, stripping `EmailBodyPart.headers` (raw header seq) at the
type level because creation uses `extraHeaders` instead. Part E extends
this discipline two levels down:

- `BlueprintBodyValue` strips flag fields from `EmailBodyValue` (the leaf
  value level).
- `BlueprintBodyPart.bpsInline` gains a `value` field, relocating the
  previously-separate `bodyValues` map into the tree (the structural
  level).
- `BlueprintBodyPart.extraHeaders` retypes to use
  `BlueprintBodyHeaderName`, forbidding Content-Transfer-Encoding at the
  key level (the header-key level).

Two of these three changes require additive modifications to Part C
(§5 of this document). The modifications preserve Part C's stated design
commitments (§3.5's "no smart constructor on BlueprintBodyPart" stands,
because the additions are at field-type and field-presence level, not
construction-function level).

---

## 3. EmailBlueprint

**Module:** `src/jmap_client/mail/email_blueprint.nim`

`EmailBlueprint` is the creation-model aggregate for Email/set. A
`EmailBlueprint` value represents a validated, RFC 8621 §4.6-conforming
Email ready for submission. The name conveys "a complete, validated email
specification" — a domain concept, not a lifecycle annotation.

**Principles:** DDD (creation aggregate distinct from read aggregate),
Parse-don't-validate (smart constructor is the sole boundary),
Make-illegal-states-unrepresentable (case discriminant + Pattern A sealing
+ strip-pattern types), Railway-Oriented Programming (accumulating
Result error rail).

### 3.1. Type Definition

`EmailBlueprint` uses **Pattern A sealing** following the
`HeaderPropertyKey` precedent (Part C §2.3): all fields are module-private
with a `raw*` prefix; public API is a set of UFCS accessors bearing the
canonical (unprefixed) field names.

**Top-level type:**

```nim
type EmailBodyKind* = enum
  ebkStructured    ## client provides full bodyStructure tree
  ebkFlat          ## client provides textBody/htmlBody/attachments

type EmailBlueprint* {.ruleOff: "objects".} = object
  # Mailbox membership — type-level at-least-one invariant
  rawMailboxIds: NonEmptyMailboxIdSet

  # Labelling
  rawKeywords: KeywordSet

  # Timestamp — Opt.none means "defer to server clock"
  rawReceivedAt: Opt[UTCDate]

  # Header convenience fields (typed; one RFC parsed-form per field)
  rawFromAddr: Opt[seq[EmailAddress]]        ## "from", asAddresses
  rawTo: Opt[seq[EmailAddress]]              ## "to", asAddresses
  rawCc: Opt[seq[EmailAddress]]              ## "cc", asAddresses
  rawBcc: Opt[seq[EmailAddress]]             ## "bcc", asAddresses
  rawReplyTo: Opt[seq[EmailAddress]]         ## "replyTo", asAddresses
  rawSender: Opt[EmailAddress]               ## "sender", singular (R2-3)
  rawSubject: Opt[string]                    ## "subject", asText
  rawSentAt: Opt[Date]                       ## "sentAt", asDate
  rawMessageId: Opt[seq[string]]             ## "messageId", asMessageIds
  rawInReplyTo: Opt[seq[string]]             ## "inReplyTo", asMessageIds
  rawReferences: Opt[seq[string]]            ## "references", asMessageIds

  # Dynamic headers, typed keys forbid Content-* at top level
  rawExtraHeaders: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]

  # Body — `EmailBlueprintBody` is a case object (§3.2) whose
  # discriminant makes "bodyStructure XOR flat-list" type-level.
  rawBody: EmailBlueprintBody
```

**Key design decisions:**

- **Sealed fields + UFCS accessors** (R2-1). Module-private `raw*` fields
  prevent direct construction outside `email_blueprint.nim`; public API is
  same-name accessor funcs. Matches `HeaderPropertyKey` (Part C §2.3).
  Without sealing, a caller could bypass `parseEmailBlueprint` by writing
  `EmailBlueprint(rawMailboxIds: ..., rawBody: ...)` with hand-crafted
  body contents — valid Nim that could skirt the cross-field header
  duplicate check. Sealing makes the smart constructor a true boundary,
  not an advisory one.

- **Body as a single `rawBody: EmailBlueprintBody` field.**
  `EmailBlueprintBody` (§3.2) is a case object whose discriminant
  encodes the `ebkStructured` vs `ebkFlat` choice at the type level.
  Moving the body into a separate type (rather than inlining the case
  discriminant on `EmailBlueprint` itself) does two things: it forces
  the body-XOR invariant to the signature boundary (preventing
  `parseEmailBlueprint` from having to check it at runtime), and it
  names the creation-body concept as a first-class type that callers
  construct explicitly via helpers.

- **Singular `rawSender: Opt[EmailAddress]`** (R2-3). RFC 5322 §3.6.2
  constrains `Sender:` to exactly one mailbox (not a list). The type
  reflects the domain invariant. Serde emits a single-element wire array.
  Other address fields stay `Opt[seq[EmailAddress]]` because RFC 5322
  permits mailbox-lists or address-lists there. **Different knowledge
  deserves different appearance.**

- **`fromAddr` naming** (R2-2). Nim reserves `from` as a keyword; the
  field uses `fromAddr`. Serde maps `fromAddr` ↔ JMAP wire key `from`.
  The pattern matches `contentType ↔ "type"` from Part C §3.2: JMAP's
  wire key is not the source of truth for the domain model; the concept
  (RFC 5322 §3.6.2 from-address) is.

- **`rawReceivedAt: Opt[UTCDate]`** (R2-4). `Opt.none` is a
  positively-meaningful state — "defer to the server's clock" — not mere
  absence. `Opt.some(t)` is "record this exact timestamp." **Whose clock**
  is load-bearing (network latency, clock drift); forcing `UTCDate` would
  make the "defer to server" semantic unexpressible.

- **No `bodyValues` field.** The `bodyValues` map is a derived accessor
  (§3.5), walking the body tree to collect `(partId, value)` pairs from
  inline leaves. The body tree IS the bodyValues map; they cannot disagree
  because they are the same data. Architecture §8.4's `bodyValues` table
  is denormalised via the Part C extension in §5.1.

**Principles:**
- **Make illegal states unrepresentable** — case discriminant, singular
  sender, Pattern A sealing, and denormalisation each encode a different
  RFC invariant structurally.
- **One source of truth per fact** — each RFC invariant maps to exactly
  one enforcement mechanism (type, discriminant, or named smart-ctor
  check).
- **Parse once at the boundary** — `parseEmailBlueprint` is the sole
  construction path; once constructed, the value is immutable and
  trustworthy.
- **DDD** — the creation aggregate does not share invariants with the
  read model.

### 3.2. EmailBlueprintBody

`EmailBlueprintBody` is a case object whose discriminant encodes the
`bodyStructure` XOR flat-list choice at the type level. It is the
signature-level application of the strip-pattern (§2.2 fourth row):
instead of `parseEmailBlueprint` taking four independent body parameters
and validating the XOR at runtime, it takes a single `EmailBlueprintBody`
value that cannot simultaneously be both kinds.

**Type definition:**

```nim
type EmailBlueprintBody* = object
  case kind*: EmailBodyKind
  of ebkStructured:
    bodyStructure*: BlueprintBodyPart
  of ebkFlat:
    textBody*: Opt[BlueprintBodyPart]      ## at most one text/plain
    htmlBody*: Opt[BlueprintBodyPart]      ## at most one text/html
    attachments*: seq[BlueprintBodyPart]   ## zero or more
```

Public fields (no `raw*` prefix, no Pattern A sealing). The case
discriminant already makes both-variants-populated unrepresentable;
there are no further invariants to defend. Per "constructors that can't
fail, don't," direct public-field access is correct.

**Helpers for ergonomic construction:**

```nim
func flatBody*(
    textBody: Opt[BlueprintBodyPart] = Opt.none(BlueprintBodyPart),
    htmlBody: Opt[BlueprintBodyPart] = Opt.none(BlueprintBodyPart),
    attachments: seq[BlueprintBodyPart] = @[],
): EmailBlueprintBody =
  EmailBlueprintBody(
    kind: ebkFlat,
    textBody: textBody,
    htmlBody: htmlBody,
    attachments: attachments,
  )

func structuredBody*(
    bodyStructure: BlueprintBodyPart,
): EmailBlueprintBody =
  EmailBlueprintBody(kind: ebkStructured, bodyStructure: bodyStructure)
```

Neither helper can fail; they are total (return-type is
`EmailBlueprintBody`, not `Result`). They exist purely for call-site
ergonomics:

```nim
# With helpers — concise, intent-revealing:
body = flatBody(textBody = some(plainPart))
body = structuredBody(rootMultipart)

# Without helpers — explicit but verbose:
body = EmailBlueprintBody(
  kind: ebkFlat, textBody: some(plainPart),
  htmlBody: Opt.none(BlueprintBodyPart), attachments: @[])
```

The helpers are not smart constructors — they are variant-specific
factory functions. Callers may still use the raw object-construction
syntax when they prefer it; the helpers simply name the two legal
shapes.

**Default body:** `parseEmailBlueprint`'s `body` parameter defaults to
`flatBody()` — the empty flat body (no textBody, no htmlBody, no
attachments). Per R3-2b this is a valid state; an email with no body
content is legal per the RFC.

**Rationale:**

- **Make illegal states unrepresentable.** Populating both
  `bodyStructure` and any flat-list field simultaneously is a compile
  error — the case object refuses it. No runtime check; no error-enum
  variant; no scenario to test.
- **One source of truth per fact.** "Body is structured XOR flat" lives
  in `EmailBlueprintBody.kind`. Nowhere else.
- **Return types are documentation the compiler checks.**
  `parseEmailBlueprint`'s signature declares `body: EmailBlueprintBody`
  — a reader sees "this parameter carries a body whose kind is one of
  two things" from the type alone.
- **Make state transitions explicit in the type.** CLAUDE.md literally:
  "Not User with a status field — three types or a sum type." The
  previous four-independent-parameters design had an implicit state
  machine in the legal-combinations of populated fields; the case
  object makes it explicit.
- **Precedent scales** — this is the signature-level application of the
  strip-pattern (§2.2 fourth row), matching the three structural
  applications at value/map/header-key level.

### 3.3. Smart Constructor

```nim
func parseEmailBlueprint*(
    mailboxIds: NonEmptyMailboxIdSet,
    body: EmailBlueprintBody = flatBody(),
    keywords: KeywordSet = initKeywordSet(@[]),
    receivedAt: Opt[UTCDate] = Opt.none(UTCDate),
    fromAddr: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    to: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    cc: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    bcc: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    replyTo: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    sender: Opt[EmailAddress] = Opt.none(EmailAddress),
    subject: Opt[string] = Opt.none(string),
    sentAt: Opt[Date] = Opt.none(Date),
    messageId: Opt[seq[string]] = Opt.none(seq[string]),
    inReplyTo: Opt[seq[string]] = Opt.none(seq[string]),
    references: Opt[seq[string]] = Opt.none(seq[string]),
    extraHeaders: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue] =
        initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue](),
): Result[EmailBlueprint, EmailBlueprintErrors]
```

**Signature rationale (R1-3, R3-1, signature-level strip-pattern):**

- **`mailboxIds: NonEmptyMailboxIdSet`** — the caller constructs it
  explicitly via `parseNonEmptyMailboxIdSet` before calling
  `parseEmailBlueprint`. The empty-mailboxIds failure mode is handled
  at the `NonEmptyMailboxIdSet` boundary, not inside
  `parseEmailBlueprint`. This is a deliberate reversal of R3-5's
  original "openArray[Id] so caller ergonomics are unchanged"
  formulation: the ergonomic cost (one extra `?` unwrap at the call
  site) is traded for type-level elimination of the empty-input failure
  class, matching how R1-2, R3-3, and R3-4 traded similar costs for
  the same gain at other levels.
- **`body: EmailBlueprintBody`** — single parameter carrying the body
  choice. The case discriminant precludes a "both paths populated"
  input. Default is `flatBody()` (empty flat body, R3-2b-legal).
- **Named parameters with defaults** — R1-3's chosen ergonomics
  vehicle, unchanged. A minimal text-only email reads:

  ```nim
  parseEmailBlueprint(
    mailboxIds = ?parseNonEmptyMailboxIdSet([inboxId]),
    body = flatBody(textBody = some(plainPart)),
  ).tryGet()
  ```

  Four named arguments (the `?` unwrap on mailboxIds is one; the
  helper call is another; everything else is named parameters). Close
  to builder ergonomics, none of the mutability or illegal-state cost.

**Accumulating semantics:** the smart constructor runs all applicable
checks and returns `err(EmailBlueprintErrors)` carrying every failing
constraint, not the first one. A caller with three problems learns about
three problems in one call.

**Constraints checked** (after signature-level eliminations — the
mailboxIds non-empty and body-XOR invariants are already guaranteed
by the input types):

1. `textBody` (if present in an `ebkFlat` body) has
   `contentType == "text/plain"`.
2. `htmlBody` (if present in an `ebkFlat` body) has
   `contentType == "text/html"`.
3a. **Email top-level duplicates:** each convenience field (fromAddr, to,
    cc, bcc, replyTo, sender, subject, sentAt, messageId, inReplyTo,
    references) that is `Opt.some` does not have a corresponding
    `extraHeaders` entry for the same header
    (`ebcEmailTopLevelHeaderDuplicate`, RFC §4.6 lines 2844-2846 applied
    to the Email object).
3b. **bodyStructure-vs-top-level (ebkStructured only):** the bodyStructure
    ROOT's `extraHeaders` does not contain a key that represents a header
    already set by the Email top-level (via a convenience field or via
    top-level `extraHeaders`). Scope is ROOT only per RFC §4.6 lines
    2866-2868 singular phrasing; sub-parts of a multipart bodyStructure
    are outside this check (they belong to 3c).
    (`ebcBodyStructureHeaderDuplicate`.)
3c. **Within-body-part duplicates:** walk every `BlueprintBodyPart` in
    the body tree (bodyStructure and its sub-parts for ebkStructured;
    textBody, htmlBody, and each element of attachments and their
    sub-parts for ebkFlat). For each body part, compute the header set
    implied by its domain fields (`contentType`, `disposition`, `cid`,
    `language`, `location`, `name`, `charset`) and flag any
    `extraHeaders` entry that represents the same header.
    (`ebcBodyPartHeaderDuplicate`, RFC §4.6 lines 2844-2846 applied to
    "particular EmailBodyPart.")
4. For each `extraHeaders` entry (both top-level and within the body
   tree), the `(name, value.form)` pair is in the AllowedHeaderForms
   table (Part C §2.6's `validateHeaderForm`, constraint 7). The form
   comes directly from the `BlueprintHeaderMultiValue` value's
   discriminant; there is no separate key-form to reconcile (see
   §4.5 for why).

Constraints 1 (mailboxIds ≥ 1), 2 (no headers array), 4 (Content-*
top level), 5 (body-XOR), 6 (flags-false), 8 (partId refs), 9 (CTE)
are all type-level per R3-5 + signature-level strip, the absence of a
`headers` field, R3-4, the signature-level strip, R1-2, R3-3, and R3-4
respectively. Constraints 11–14 (`blobNotFound`, `tooManyKeywords`,
`tooManyMailboxes`, server-settable fields) are server-side set-errors
deferred to Part F.

**Principles:**
- **Parse once at the boundary** — all invariants either structural or
  checked here; post-construction code trusts the value.
- **Total functions** — every input maps to `ok(EmailBlueprint)`
  or `err(EmailBlueprintErrors)`.
- **Railway-Oriented Programming** — the accumulating error pattern stays
  on a single railway; a single call returns the full error picture.
- **Constructors are privileges, not rights** — the only path. No
  construction via brace syntax (Pattern A sealing); no fluent builder
  (R1-3).

### 3.4. Error Triad

The error vocabulary comprises five types: three for the error
aggregate itself plus two for locating body-part violations.

**Body-part locator types** (used by `ebcBodyPartHeaderDuplicate`):

```nim
type BodyPartPath* = distinct seq[int]
  ## Zero-indexed tree path locating a multipart BlueprintBodyPart
  ## within an EmailBlueprintBody. Interpretation:
  ## - ebkStructured: indices into bodyStructure's subParts, from root
  ##   (@[] = bodyStructure itself if it is multipart).
  ## - ebkFlat: first element is 0 (textBody), 1 (htmlBody), or
  ##   2+i (attachments[i]); subsequent elements walk subParts.

type BodyPartLocationKind* = enum
  bplInline
  bplBlobRef
  bplMultipart

type BodyPartLocation* = object
  ## Names the body part at which a constraint was violated.
  ## Case discriminant reflects Part C's BlueprintBodyPart structure:
  ## inline leaves carry a partId; blob-ref leaves carry a blobId;
  ## multipart nodes have no identifier and are located by tree path.
  case kind*: BodyPartLocationKind
  of bplInline:
    partId*: PartId
  of bplBlobRef:
    blobId*: Id
  of bplMultipart:
    path*: BodyPartPath
```

**Error triad:**

```nim
type EmailBlueprintConstraint* = enum
  ## Three "HeaderDuplicate" variants cover RFC §4.6's three
  ## distinct cross-axis duplicate rules (see constraint map below).
  ## Within-extraHeaders duplicates and key/value form-mismatch are
  ## type-level impossibilities and therefore have no runtime variant.
  ebcEmailTopLevelHeaderDuplicate
  ebcBodyStructureHeaderDuplicate
  ebcBodyPartHeaderDuplicate
  ebcTextBodyNotTextPlain
  ebcHtmlBodyNotTextHtml
  ebcAllowedFormRejected

type EmailBlueprintError* = object
  case constraint*: EmailBlueprintConstraint
  of ebcEmailTopLevelHeaderDuplicate:
    dupName*: string                      ## Email top-level: convenience field ↔ top-level extraHeaders (lowercase header name)
  of ebcBodyStructureHeaderDuplicate:
    bodyStructureDupName*: string         ## bodyStructure ROOT's extraHeaders ↔ Email top-level header (lowercase name)
  of ebcBodyPartHeaderDuplicate:
    where*: BodyPartLocation              ## which body part in the tree
    bodyPartDupName*: string              ## body-part domain field ↔ its own extraHeaders (lowercase name)
  of ebcTextBodyNotTextPlain:
    actualTextType*: string               ## observed contentType
  of ebcHtmlBodyNotTextHtml:
    actualHtmlType*: string               ## observed contentType
  of ebcAllowedFormRejected:
    rejectedName*: string                 ## header name (lowercase)
    rejectedForm*: HeaderForm             ## the form that isn't permitted for this name

type EmailBlueprintErrors* = distinct seq[EmailBlueprintError]
  ## Invariant: non-empty whenever carried on the err rail of
  ## parseEmailBlueprint. Enforced by the smart constructor: empty seq
  ## would mean "no errors," which is the ok rail's job.

func message*(e: EmailBlueprintError): string =
  ## Human-readable rendering, derived from (constraint, variant data).
  ## Pure; compiler enforces arm exhaustiveness.
  case e.constraint
  of ebcEmailTopLevelHeaderDuplicate:
    "duplicate header representation at Email top level: convenience " &
    "field and extraHeaders entry for " & e.dupName & " cannot both be set"
  of ebcBodyStructureHeaderDuplicate:
    "bodyStructure root extraHeaders entry for " & e.bodyStructureDupName &
    " duplicates a header already defined on the Email top level"
  of ebcBodyPartHeaderDuplicate:
    "body part carries duplicate representations of header " &
    e.bodyPartDupName & " (domain field and extraHeaders entry)"
  of ebcTextBodyNotTextPlain:
    "ebkFlat textBody must be text/plain; found " & e.actualTextType
  of ebcHtmlBodyNotTextHtml:
    "ebkFlat htmlBody must be text/html; found " & e.actualHtmlType
  of ebcAllowedFormRejected:
    "header form " & $e.rejectedForm & " not allowed for header name " &
    e.rejectedName
```

**Rationale:**

- **Errors are part of the API. Name variants, never collapse to strings.**
  The enum names each failure mode; callers pattern-match on `constraint`
  rather than parsing `message`. The plain `ValidationError` used
  elsewhere in the codebase is partially collapsed; the enum fixes that
  for the aggregate context.

- **Case object discriminated by the constraint enum** (R3-2a). A
  variant's fields physically don't exist on other variants.
  `ebcEmailTopLevelHeaderDuplicate` cannot carry `actualTextType`; the
  compiler refuses. No convention needed to keep data consistent with
  the error kind.

- **`EmailBlueprintErrors` as a distinct non-empty seq** (R3-1). "The
  aggregate of errors from one blueprint construction" is a meaningful
  domain concept; the distinct type names it. Plain `seq[EmailBlueprintError]`
  would leave the aggregate nameless and the non-empty invariant implicit.

- **`message` as a pure func, not a stored field.** `(constraint, data)`
  already fully determines the rendering. A stored `message` would be a
  redundant source of truth — two representations of the same fact. The
  func centralises rendering in one place; compiler-checked exhaustiveness
  ensures no variant is forgotten; callers who care only about the
  machine-readable constraint ignore the rendering entirely.

- **Precedent scales.** Parts F–I each introduce their own constraint
  enum + error case object + errors-newtype triad. Errors genuinely differ
  between aggregates, and the type system should reflect that rather than
  collapsing all errors into a universal shape.

**Constraint → enforcement map** (final, post all type-level
eliminations):

| RFC §4.6 constraint | Enforcement |
|---------------------|-------------|
| 1. mailboxIds ≥ 1 | Type-level via `NonEmptyMailboxIdSet` (§4.2) — enforced at the signature (`mailboxIds: NonEmptyMailboxIdSet`) |
| 2. No `headers` array | Type-level (field absent from `EmailBlueprint`) |
| 3a. No duplicate header within Email top level (convenience field ↔ extraHeaders entry) | Runtime: `ebcEmailTopLevelHeaderDuplicate` |
| 3b. bodyStructure root cannot duplicate Email top-level headers (RFC lines 2866-2868) | Runtime: `ebcBodyStructureHeaderDuplicate` |
| 3c. No duplicate header within any single EmailBodyPart (domain field ↔ extraHeaders entry, RFC lines 2844-2846, "or particular EmailBodyPart") | Runtime: `ebcBodyPartHeaderDuplicate` |
| 3d. No two extraHeaders entries for the same header name (intra-Table axis, RFC lines 2844-2846 applied to extraHeaders) | Type-level via `BlueprintEmailHeaderName` / `BlueprintBodyHeaderName` as Table keys (name-only, form on value) |
| 4. No Content-* at Email top level | Type-level via `BlueprintEmailHeaderName` (§4.3) |
| 5. bodyStructure XOR flat-list | Type-level via `EmailBlueprintBody` case discriminant (§3.2) — enforced at the signature (`body: EmailBlueprintBody`) |
| 5a. ebkFlat textBody must be text/plain | Runtime: `ebcTextBodyNotTextPlain` |
| 5b. ebkFlat htmlBody must be text/html | Runtime: `ebcHtmlBodyNotTextHtml` |
| 5c. "At least one of textBody/htmlBody" (arch only, not RFC) | **Dropped** per R3-2b |
| 6. bodyValues flags false | Type-level via `BlueprintBodyValue` (§4.1) |
| 7. Allowed header forms (name + form pair) | Runtime: `ebcAllowedFormRejected` |
| 8. partId refs resolve | Type-level via §5.1 denormalisation |
| 9. No Content-Transfer-Encoding | Type-level via `BlueprintBodyHeaderName` (§4.4) |
| 10 (was new). extraHeaders key/value form consistency | Type-level via `BlueprintHeaderMultiValue` (§4.5) — the form lives once, on the value; there is no separate key-form to disagree with |

**Six runtime enum variants; eight type-level eliminations** (including
the "no `headers` array" field-absence; signature-level `mailboxIds` and
`body` shapes; intra-Table name uniqueness via name-only keys; and
key/value form-consistency via single-source form on
`BlueprintHeaderMultiValue`). The three "HeaderDuplicate" variants form
a naming family, one per runtime RFC duplicate axis (Email top-level,
bodyStructure-vs-top-level, within-body-part). The fourth duplicate axis
(intra-Table) is type-level because it admits no runtime reporting
scenario — the Table cannot contain two keys with the same name. The
type system does the majority of the work; the smart constructor
handles the genuinely cross-field constraints that no single field type
can capture.

### 3.5. Accessors

Pattern A sealing requires same-name UFCS accessors. One accessor per
`raw*` field, each a one-liner:

```nim
func mailboxIds*(bp: EmailBlueprint): NonEmptyMailboxIdSet =
  bp.rawMailboxIds

func keywords*(bp: EmailBlueprint): KeywordSet = bp.rawKeywords
func receivedAt*(bp: EmailBlueprint): Opt[UTCDate] = bp.rawReceivedAt
func fromAddr*(bp: EmailBlueprint): Opt[seq[EmailAddress]] = bp.rawFromAddr
func to*(bp: EmailBlueprint): Opt[seq[EmailAddress]] = bp.rawTo
# ... (one per convenience field — cc, bcc, replyTo, sender, subject,
# sentAt, messageId, inReplyTo, references, extraHeaders)

# Body accessor — returns the EmailBlueprintBody case object
# unchanged; callers navigate from there (bp.body.kind,
# bp.body.textBody, etc., guarded by the compiler's case-object rules)
func body*(bp: EmailBlueprint): EmailBlueprintBody = bp.rawBody

# Convenience pass-throughs (optional; reach through rawBody):
func bodyKind*(bp: EmailBlueprint): EmailBodyKind = bp.rawBody.kind
```

**Derived `bodyValues` accessor** (R3-3, crucial): no stored field; walks
the tree to collect `(partId, value)` pairs from inline leaves:

```nim
func bodyValues*(bp: EmailBlueprint): Table[PartId, BlueprintBodyValue] =
  ## Derived map. Collects one (partId, value) entry per inline leaf
  ## in the body tree (bodyStructure for ebkStructured; textBody,
  ## htmlBody, and each element of attachments for ebkFlat, each walked
  ## recursively via sub-parts).
  ##
  ## Since inline body parts carry their value in-place (see §5.1),
  ## this accessor is the canonical way to materialise the bodyValues
  ## map for serde or inspection purposes.
```

**Principles:**

- **Make the right thing easy** — UFCS accessors let callers write
  `bp.mailboxIds` exactly as they would for plain public fields. The
  sealing is invisible at the call site.
- **One source of truth per fact** — `bodyValues` is derived, not stored;
  it cannot disagree with the tree because it IS the tree, projected.

### 3.6. Serde — toJson

**Module:** `src/jmap_client/mail/serde_email_blueprint.nim`

`EmailBlueprint` serialises unidirectionally to JMAP creation JSON. No
`fromJson`. Adding one would create a second construction path bypassing
`parseEmailBlueprint`, violating R1-3.

```nim
func toJson*(bp: EmailBlueprint): JsonNode
```

**Wire format (canonical example):**

```json
{
  "mailboxIds": {"mb-inbox": true},
  "keywords": {"$seen": true},
  "receivedAt": "2026-04-12T12:00:00Z",
  "from": [{"name": "Alice", "email": "alice@example.com"}],
  "to": [{"name": "Bob", "email": "bob@example.com"}],
  "subject": "Hello",
  "header:X-Custom:asText": "custom-value",
  "textBody": [{"partId": "1", "type": "text/plain"}],
  "bodyValues": {"1": {"value": "Hi there"}}
}
```

#### 3.6.1. Convenience field → JSON key mapping (R4-1)

Every typed convenience field maps to exactly one JMAP wire key and
covers exactly one RFC parsed-form. Callers wanting a different form
(e.g., `asGroupedAddresses` for From instead of `asAddresses`) cannot
use the convenience field — they must populate `extraHeaders` directly
with an appropriately-formed `BlueprintEmailHeaderName`.

| Blueprint field | Type | Wire JSON key | RFC parsed-form covered |
|-----------------|------|---------------|-------------------------|
| `fromAddr` | `Opt[seq[EmailAddress]]` | `"from"` | `asAddresses` |
| `to` | `Opt[seq[EmailAddress]]` | `"to"` | `asAddresses` |
| `cc` | `Opt[seq[EmailAddress]]` | `"cc"` | `asAddresses` |
| `bcc` | `Opt[seq[EmailAddress]]` | `"bcc"` | `asAddresses` |
| `replyTo` | `Opt[seq[EmailAddress]]` | `"replyTo"` | `asAddresses` |
| `sender` | `Opt[EmailAddress]` (singular, R2-3) | `"sender"` | `asAddresses` (single-element wire array) |
| `subject` | `Opt[string]` | `"subject"` | `asText` |
| `sentAt` | `Opt[Date]` | `"sentAt"` | `asDate` (alias for `header:Date:asDate`) |
| `messageId` | `Opt[seq[string]]` | `"messageId"` | `asMessageIds` |
| `inReplyTo` | `Opt[seq[string]]` | `"inReplyTo"` | `asMessageIds` |
| `references` | `Opt[seq[string]]` | `"references"` | `asMessageIds` |

**Rationale for explicit naming:** Without this table, a reader might
assume "`fromAddr` serialises to `from`, so I can use it for grouped
addresses too." The table forestalls that misreading. The type system
already encodes the parsed-form constraint (`fromAddr` is
`Opt[seq[EmailAddress]]`, not `Opt[seq[EmailAddressGroup]]`); the table
names what the type encoded.

**`extraHeaders` serialisation:** each entry is emitted as an individual
JSON property whose key is `toPropertyString(key)` (Part C §2.3's wire
serialisation for `HeaderPropertyKey`, which composes through the
distinct-type wrapper `BlueprintEmailHeaderName`) and whose value is
`toJson(headerValue)` (Part C §2.7). The R3-1
`ebcEmailTopLevelHeaderDuplicate` smart-ctor check guarantees that the
convenience channel and the extraHeaders channel are never populated for
the same header, so emitted JSON never contains duplicate keys.

#### 3.6.2. Opt.none → key omission (R4-2, homomorphism)

`Opt.none` fields emit no key in the JSON output. This is not a policy
choice; it is a homomorphism:

> `Opt.none` is the domain's encoding of absence. JSON's encoding of
> absence is key omission. `EmailBlueprint.toJson` maps domain absence
> to wire absence — it does not invent a value for absence. The serde
> function is a homomorphism between two absence representations, not a
> policy judgment between two equivalent outputs.

This rule matches `BlueprintBodyPart.toJson` from Part C §3.6 verbatim —
not by coincidence, but because both are creation-time types encoding
the same semantic.

#### 3.6.3. Empty collections → key omission (R4-3)

Empty `keywords`, empty `extraHeaders`, and empty derived `bodyValues`
omit their keys.

For non-Opt collection fields (`keywords`, `extraHeaders`, derived
`bodyValues`), the domain has no "absent" state — only "empty" and
"non-empty." RFC 8621 §4.1.1 / §4.6 treat absent and empty as
interchangeable on creation. By **one source of truth per fact**, we pick
one wire representation for "empty" and use it uniformly. We pick
absence because:

1. Architecture §8.4 already chose this for `bodyValues`; extending it
   keeps a single rule.
2. Wire economy — the extra `{}` bytes encode no fact the server uses.
3. Uniformity with Opt-typed fields: callers see absence on the wire
   regardless of whether the underlying domain type was Opt-wrapped or
   bare.

**Explicitly rejected alternative:** making `keywords: Opt[KeywordSet]`
would preserve the R4-2 strict homomorphism by letting the domain
distinguish "unspecified" from "explicitly empty." Rejected because:

- **YAGNI** — neither the RFC nor any downstream caller can act on the
  distinction.
- API complexity — every caller would navigate two flavours of "no
  keywords."
- Contradicts Part B §2 (Decision B2): `KeywordSet` is deliberately
  designed to allow empty as a valid state.

Future readers should not reopen this question.

#### 3.6.4. Body serialisation

The body tree is serialised according to `bodyKind`:

- **`ebkStructured`**: emits `"bodyStructure"` key containing the
  recursively-serialised `BlueprintBodyPart` tree. The body-part
  `toJson` function in `serde_body.nim` handles each node; it emits
  `partId` on inline leaves but **does not** emit the co-located
  `value` field (see §5.4 for the split). The `EmailBlueprint.toJson`
  function walks the tree separately to harvest values into the
  top-level `bodyValues` object.

- **`ebkFlat`**: emits `"textBody"`, `"htmlBody"` keys (each a
  single-element JSON array if `Opt.some`, omitted if `Opt.none`), and
  `"attachments"` as a JSON array (possibly empty — but empty is
  omitted per §3.5.3). The same value-harvesting walk runs across all
  three fields.

- **`bodyValues` key**: emitted with keys equal to the `PartId` strings
  found at inline leaves and values equal to
  `BlueprintBodyValue.toJson` output (a JSON object with a single
  `value` field — see §4.1.3). Omitted when no inline leaves exist.

**Principles:**

- **Make illegal states unrepresentable** — the serde layer cannot emit
  a bodyValues entry whose partId has no corresponding inline leaf,
  because there is no separate map to go out of sync with; the walk IS
  the construction.
- **Parse once at the boundary** — serde owns the wire/domain asymmetry
  (denormalisation for bodyValues, single-element-array for sender,
  etc.). Interior code sees the domain shape; wire code sees the wire
  shape.

---

## 4. Supporting Creation Types

This section defines the four supporting types introduced by Part E.
Each exists for the same reason: to collapse what would otherwise be a
runtime RFC §4.6 constraint into a type-level fact, per the strip-pattern
(§2.2).

### 4.1. BlueprintBodyValue

**Module:** `src/jmap_client/mail/body.nim` (extended).

**RFC reference:** §4.1.4 (EmailBodyValue); §4.6 creation constraint 6.

**Module placement:** `BlueprintBodyValue` is grouped logically with the
other "supporting creation types" in §4, but physically lives in `body.nim`
alongside `BlueprintBodyPart`. Two independent reasons drive this:

1. `body.nim`'s `BlueprintBodyPart.bpsInline` branch takes a
   `value: BlueprintBodyValue` field (§5.1), so the type must be visible to
   `body.nim` — either defined there, or imported from elsewhere.
2. `email_blueprint.nim` imports `body.nim` for `BlueprintBodyPart` (§3.2).
   Defining `BlueprintBodyValue` in `email_blueprint.nim` would force
   `body.nim` to import `email_blueprint.nim` in return — a mutual import
   that Nim cannot resolve for object-field type checking.

Hosting the leaf type with the dependent module keeps `email_blueprint.nim
→ body.nim` a one-way import. This is the only §4 type that does not live
in a module its name suggests; the choice follows the dependency graph, not
the conceptual grouping.

A `BlueprintBodyValue` carries the text content of an inline body part on
creation. It is the creation-time sibling of `EmailBodyValue` from Part C
§3.3, stripped of the `isEncodingProblem` and `isTruncated` flag fields
that RFC §4.6 mandates be false on creation.

#### 4.1.1. Type Definition

```nim
type BlueprintBodyValue* = object
  value*: string
```

Plain object with a single public field. No smart constructor — every
string is a valid value. Per "constructors that can fail, don't,"
public-field construction is correct.

Not a distinct string. A plain object preserves the wire-shape symmetry
with JMAP's `{"value": "..."}` payload: Nim shape mirrors JSON shape,
toJson stays trivial, no wrapping ceremony at serde.

#### 4.1.2. Rationale

The read-model `EmailBodyValue` carries two flag fields:

```nim
# Part C §3.3 (read model):
type EmailBodyValue* = object
  value*: string
  isEncodingProblem*: bool
  isTruncated*: bool
```

On creation, RFC §4.6 mandates both flags be false. The flags would
therefore always carry the same (false) value in creation payloads — zero
information. Keeping them on a creation type would:

- Add fields with no meaningful semantic variation.
- Require a runtime check to reject flags-true values.
- Duplicate state across read and creation (the types would accept the
  same illegal inputs; only the creation-ctor check would distinguish).

Stripping the fields collapses the check into the type. The
`BlueprintBodyValue` type cannot represent a "flags-true" body value at
all, making the illegal state unrepresentable.

This is the same pattern as `BlueprintBodyPart` (Part C §3.5) stripping
`EmailBodyPart.headers` one level up. Creation and read are different
aggregates with different invariants. **Different knowledge deserves
different appearance.**

#### 4.1.3. Serde — toJson

**Module:** `src/jmap_client/mail/serde_body.nim` (extended) — paired with
the type's L1 home, per the convention used elsewhere in `body.nim` /
`serde_body.nim`. `serde_email_blueprint.nim` imports `serde_body` for the
harvest in §5.4.

```nim
func toJson*(v: BlueprintBodyValue): JsonNode =
  result = %*{"value": v.value}
```

Emits `{"value": "<string>"}`. Always exactly one key. No flags to emit;
no conditional emission paths.

No `fromJson`. Creation types are unidirectional per R1-3.

#### 4.1.4. Consequences

- The `bodyValues` map type diverges between read and create:
  - Read: `Table[PartId, EmailBodyValue]` (carries flags)
  - Create: `Table[PartId, BlueprintBodyValue]` (value-only)
- A read-model body value (which might have `isEncodingProblem=true`)
  cannot accidentally be fed into a blueprint — the types don't unify.
- Architecture §8.5 constraint 6 ("bodyValues entries:
  isEncodingProblem and isTruncated must both be false") disappears
  from the smart constructor. One fewer validator, one fewer test, one
  fewer runtime check.

**Principles:**
- **Make illegal states unrepresentable** — the flags cannot be set.
- **One source of truth per fact** — the RFC rule IS the type; no
  parallel runtime check.
- **Constructors that can't fail, don't** — every string is valid.
- **DDD** — creation and read aggregates are different.

### 4.2. NonEmptyMailboxIdSet

**Module:** `src/jmap_client/mail/mailbox.nim` (extended)

**RFC reference:** §4.1.1 (mailboxIds); §4.6 creation constraint 1.

A `NonEmptyMailboxIdSet` is a distinct `HashSet[Id]` guaranteed to
contain at least one element. Used by `EmailBlueprint.mailboxIds` to
encode RFC §4.6's "at least one Mailbox MUST be given" at the type
level.

#### 4.2.1. Type Definition

```nim
type NonEmptyMailboxIdSet* = distinct HashSet[Id]
```

Borrowed read-only operations (`==`, `$`, `hash`, `items`, `len`,
`contains`, `iterator pairs`) via `defineHashSetDistinctOps(NonEmptyMailboxIdSet)`
(a template parallel to `defineStringDistinctOps` from
`primitives.nim`). Mutating operations (`incl`, `excl`) are deliberately
not borrowed — mutation could violate the non-empty invariant.

#### 4.2.2. Smart Constructor

```nim
func parseNonEmptyMailboxIdSet*(
    ids: openArray[Id],
): Result[NonEmptyMailboxIdSet, ValidationError]
```

Validates: `ids.len > 0`. Converts the openArray to an internal
`HashSet[Id]`, wraps via the distinct cast, returns `ok`. An empty input
returns `err(ValidationError)`.

Post-construction `doAssert`: verifies `result.HashSet[Id].len > 0`.

The error type is the codebase-standard `ValidationError` rather than
Part E's `EmailBlueprintError` — `NonEmptyMailboxIdSet` is a generally
reusable type (not blueprint-specific), and its single-invariant failure
doesn't benefit from the aggregate error triad.

**Integration with parseEmailBlueprint:** because `parseEmailBlueprint`
takes `mailboxIds: NonEmptyMailboxIdSet` directly (not `openArray[Id]`,
per the signature-level strip-pattern — see §3.3 rationale), the
empty-mailboxIds failure mode **never reaches** `parseEmailBlueprint`.
The caller is responsible for constructing a `NonEmptyMailboxIdSet` via
`parseNonEmptyMailboxIdSet` before calling the blueprint constructor;
the empty case is handled at that prior boundary. The
`EmailBlueprintConstraint` enum therefore contains no
`ebcMailboxIdsEmpty` variant — the invariant is satisfied by the input
type, not by a runtime check.

#### 4.2.3. Placement within mailbox.nim

`NonEmptyMailboxIdSet` lives in `mail/mailbox.nim` alongside the
existing `MailboxIdSet`, organised under an explicit labelled section:

```
## Mailbox ID Collections

# 1. MailboxIdSet — general-purpose, empty allowed (read models)
type MailboxIdSet* = distinct HashSet[Id]
defineHashSetDistinctOps(MailboxIdSet)
func initMailboxIdSet*(...) ...

# 2. NonEmptyMailboxIdSet — creation-context, at-least-one enforced
type NonEmptyMailboxIdSet* = distinct HashSet[Id]
defineHashSetDistinctOps(NonEmptyMailboxIdSet)
func parseNonEmptyMailboxIdSet*(...) ...
```

The two types as a labelled pair make the "parallel types, different
invariants" relationship structurally visible inside the file,
reinforcing the decision for future readers.

#### 4.2.4. Rationale

- **Make illegal states unrepresentable.** The empty-set invariant is
  type-level, not runtime. Any `NonEmptyMailboxIdSet` value in scope is
  provably non-empty.
- **Reads stay lenient.** `MailboxIdSet` remains unmodified. Server-
  provided `Email.mailboxIds` (Part D read model), `MailboxChangesResponse`
  deletions, and every other read-side holder continue to accept empty
  sets per Postel's law. No audit of existing uses required.
- **Names the domain concept.** "A mailbox membership that is
  guaranteed non-empty" is a first-class creation concept. Honours
  "newtype everything that has meaning."
- **Matches existing codebase precedent.** `Id`, `PartId`, `Date` are
  all structural single-invariant newtypes; `NonEmptyMailboxIdSet`
  extends the pattern.
- **Makes illegal inputs uninhabitable at the signature.**
  `parseEmailBlueprint`'s `mailboxIds: NonEmptyMailboxIdSet` parameter
  refuses empty inputs at compile time. Callers unwrap the smart-ctor
  result once (via `?` or `tryGet`) at the `parseNonEmptyMailboxIdSet`
  site — one additional step traded for the type-level elimination of
  an entire failure class from `parseEmailBlueprint`'s error rail.
  Parallel to the `EmailBlueprintBody` signature-level move (§3.2,
  E24).

### 4.3. BlueprintEmailHeaderName

**Module:** `src/jmap_client/mail/headers.nim` (extended, under the
"Creation-Model Header Vocabulary" labelled section introduced by
this part).

**RFC reference:** §4.1.3 (header-property syntax); §4.6 creation
constraint 4 ("Content-* headers MUST NOT be set on the Email object
itself"); §4.6 creation constraint "no duplicate header representation"
applied to the intra-extraHeaders axis (Table key uniqueness).

A `BlueprintEmailHeaderName` is a lowercase, RFC 5322 conforming header
name guaranteed not to begin with `content-`. It is used as the key
type of `EmailBlueprint.extraHeaders`, where the Table key's
name-granularity identity encodes RFC §4.6 constraint 3d
(no two extraHeaders entries for the same header) at the type level.
The form and :all semantics live on the paired
`BlueprintHeaderMultiValue` value (§4.5), not on the key.

#### 4.3.1. Type Definition

```nim
type BlueprintEmailHeaderName* = distinct string
```

Borrowed operations via `defineStringDistinctOps(BlueprintEmailHeaderName)`
(the same template used by `Id`, `PartId`, etc.): `==`, `$`, `hash`,
`len`. Equality is on the wrapped lowercase string — two keys are
equal iff their names match. This is how the Table enforces intra-
extraHeaders uniqueness: `parseBlueprintEmailHeaderName("X-Custom")` and
`parseBlueprintEmailHeaderName("x-custom")` produce equal values that
cannot coexist in the Table.

#### 4.3.2. Smart Constructor

```nim
func parseBlueprintEmailHeaderName*(
    name: string,
): Result[BlueprintEmailHeaderName, ValidationError]
```

**Input contract:** accepts the header name in any case, without any
`header:` prefix or form suffix. Wire-format strings like
`"header:X-Custom:asText"` are **rejected** — the `:` is not a valid
RFC 5322 `ftext` character. Callers constructing a name from a
server-provided wire string should use Part C's
`parseHeaderPropertyName` and extract the `.name` accessor.

**Validates** (strict; this is client-constructed data, not server data):

1. Non-empty.
2. Every character is printable ASCII (octets 0x21-0x7E inclusive, i.e.,
   33-126).
3. No colon (`:`, octet 0x3A) — per RFC 5322 §3.6.8 `ftext` definition.
4. Normalised name does not begin with `"content-"` (after lowercase
   normalisation) — RFC 8621 §4.6 constraint 4.

**Normalises** input to lowercase, mirroring `parseHeaderPropertyName`
(Part C §2.3): any input case produces the same canonical form, so
`==` and `hash` see three spellings of the same name as identical.

Post-construction `doAssert` verifies `result.string.len > 0` and the
content-prefix negation (belt-and-braces against future refactors).

**Strict/lenient split** (third application of the codebase pattern —
parallel to `parseId` vs `parseIdFromServer`, `parsePartId` vs
`parsePartIdFromServer`): `parseBlueprintEmailHeaderName` is strict
because it validates client-constructed input; server-provided data
uses `parseHeaderPropertyName` (Part C §2.3), which is lenient per
Postel's law.

#### 4.3.3. Serde

Serde uses the distinct-string templates already in use for
`Id` / `PartId`:

```nim
defineDistinctStringToJson(BlueprintEmailHeaderName)
defineDistinctStringFromJson(BlueprintEmailHeaderName,
                             parseBlueprintEmailHeaderName)
```

`toJson` projects the wrapped lowercase name directly to a JSON string.
At the EmailBlueprint.toJson layer, the wire-key form
`"header:<name>:as<Form>"` (with optional `":all"` when the paired
`BlueprintHeaderMultiValue`'s seq has >1 element) is constructed by
composing the name with the form from the paired value — see §3.6 and
§4.5 for the composition rule.

`fromJson` exists for round-trip completeness but is not exercised by
Part E's unidirectional creation path.

#### 4.3.4. Rationale

The pattern is the third application of the strip-pattern (§2.2),
applied to the name space of valid header keys plus a signature-level
strip of the (form, isAll) dimensions into the paired value. RFC §4.6
says Content-* names are forbidden at Email top level AND no two
extraHeaders properties may represent the same header field. Encoding
both via the type means:

- **Illegal states unrepresentable (constraint 4).** Inserting a
  Content-Type entry into `EmailBlueprint.extraHeaders` is a compile
  error — the name cannot survive `parseBlueprintEmailHeaderName`.
- **Illegal states unrepresentable (constraint 3d / intra-Table
  duplicates).** Table-key identity is name-only (form and :all live
  on the paired `BlueprintHeaderMultiValue` value), so two entries
  representing the same header field cannot coexist in the Table —
  the second insert overwrites the first.
- **Parse once at the boundary.** Every downstream consumer
  (parseEmailBlueprint, toJson, Parts F/G/H/I) receives pre-validated,
  canonical-case names. No re-validation.
- **Constructors are privileges.** The only way to obtain a
  `BlueprintEmailHeaderName` is through `parseBlueprintEmailHeaderName`.
  Distinct types cannot be constructed by brace syntax outside their
  defining module.
- **Make the right thing easy.** Callers write
  `parseBlueprintEmailHeaderName("X-Custom")` — one call, just the name.
  They don't encode wire-format decisions into the key.
- **Newtype everything that has meaning.** "A header name valid for
  Email top-level creation" is a meaningful domain concept with a
  distinct rule; it deserves a distinct type.

### 4.4. BlueprintBodyHeaderName

**Module:** `src/jmap_client/mail/headers.nim` (extended, under the
"Creation-Model Header Vocabulary" section).

**RFC reference:** §4.1.3; §4.6 creation constraint 9
("Content-Transfer-Encoding MUST NOT be given in EmailBodyPart"); §4.6
intra-Table uniqueness (same as §4.3).

A `BlueprintBodyHeaderName` is a lowercase, RFC 5322 conforming header
name guaranteed not to be `content-transfer-encoding`. Used as the key
type of `BlueprintBodyPart.extraHeaders`.

#### 4.4.1. Type Definition

```nim
type BlueprintBodyHeaderName* = distinct string
```

Borrowed operations via `defineStringDistinctOps(BlueprintBodyHeaderName)`,
same as §4.3.1. Equality is name-only; the Table enforces
intra-extraHeaders uniqueness structurally.

#### 4.4.2. Smart Constructor

```nim
func parseBlueprintBodyHeaderName*(
    name: string,
): Result[BlueprintBodyHeaderName, ValidationError]
```

Validation mirrors §4.3.2 (non-empty, printable ASCII, no colon,
lowercase normalisation, strict/lenient split) but the forbidden-name
rule differs: exact match on `"content-transfer-encoding"` after
normalisation. Content-Type, Content-Disposition, etc., are permitted
on body parts (indeed, they are where those headers belong per RFC 2045).

#### 4.4.3. Serde

Same pattern as `BlueprintEmailHeaderName` (§4.3.3): distinct-string
templates, name-only wire projection, wire-key composition at the
consumer layer (§3.6 and §4.5).

#### 4.4.4. Rationale

Same principles as `BlueprintEmailHeaderName` (§4.3.4) applied to a
different exclusion rule. The two distinct types are deliberately
non-unified:

- They encode different RFC rules (constraint 4 vs constraint 9).
- They apply at different structural levels (Email top level vs body
  part).
- `BlueprintEmailHeaderName` and `BlueprintBodyHeaderName` are distinct
  at the Nim type level, so cross-inserting one context's name into the
  other context's Table is a compile error. "Different knowledge
  deserves different appearance" — the two distinct types are the
  appearance side; the two distinct RFC rules are the knowledge side.

#### 4.4.5. Comparison with BlueprintEmailHeaderName

| Aspect | `BlueprintEmailHeaderName` | `BlueprintBodyHeaderName` |
|--------|----------------------------|---------------------------|
| Used as key of | `EmailBlueprint.extraHeaders` | `BlueprintBodyPart.extraHeaders` |
| RFC rule encoded | §4.6 constraint 4 + §4.6 intra-Table uniqueness | §4.6 constraint 9 + §4.6 intra-Table uniqueness |
| Rejection criterion | name starts with `"content-"` | name equals `"content-transfer-encoding"` |
| Context | Email object top-level headers | MIME body-part headers |
| Underlying wrap | `distinct string` (name-only) | `distinct string` (name-only) |
| Introduced in | Part E §4.3 | Part E §4.4 |

### 4.5. BlueprintHeaderMultiValue

**Module:** `src/jmap_client/mail/headers.nim` (extended, under the
"Creation-Model Header Vocabulary" section).

**RFC reference:** §4.1.2 (parsed forms); §4.1.3 (`:all` suffix
semantics); §4.6 creation constraint "no duplicate header representation"
(intra-Table axis).

A `BlueprintHeaderMultiValue` carries one or more values for a single
header field, all sharing one parsed form. It is the creation-model
counterpart to `HeaderValue` (Part C §2.4), extended along two
dimensions simultaneously: (1) it carries a seq of values rather than
one (to express the `:all` suffix's multi-instance semantic), and (2)
it pairs with a name-only Table key rather than a HeaderPropertyKey,
so the form lives once, on the value, not redundantly on both sides.

#### 4.5.1. Type Definition

```nim
type BlueprintHeaderMultiValue* = object
  ## One or more values for a single header field, all sharing one form.
  ## seq.len == 1  → single-instance header (wire: "header:X:asForm").
  ## seq.len >  1  → multi-instance header (wire: "header:X:asForm:all").
  ## Form is once per object, not per value — no cross-element mismatch.
  case form*: HeaderForm
  of hfRaw:              rawValues*:      NonEmptySeq[string]
  of hfText:             textValues*:     NonEmptySeq[string]
  of hfAddresses:        addressLists*:   NonEmptySeq[seq[EmailAddress]]
  of hfGroupedAddresses: groupLists*:     NonEmptySeq[seq[EmailAddressGroup]]
  of hfMessageIds:       messageIdLists*: NonEmptySeq[seq[string]]
  of hfDate:             dateValues*:     NonEmptySeq[Date]
  of hfUrls:             urlLists*:       NonEmptySeq[seq[string]]
```

Public fields (no Pattern A sealing). Two type-level invariants are
structurally enforced:

- **Form uniformity** — the case discriminant ensures every value in the
  object shares a single `HeaderForm`. Cross-element form disagreement
  is impossible; this eliminates the former
  `ebcExtraHeaderFormMismatch` runtime check.
- **Non-emptiness** — each variant's outer seq is `NonEmptySeq[T]`
  (§4.6), guaranteed to contain at least one value. An "empty header"
  (a name without any values) cannot exist.

The form pattern mirrors `HeaderValue` from Part C §2.4 with two
differences: each variant's inner payload is wrapped in `NonEmptySeq[T]`,
and the hfMessageIds / hfDate / hfUrls variants drop the `Opt[...]`
wrapping that the read model uses for server-side parse failures
(creation never signals a parse failure — if the client doesn't have a
valid value, they don't set the header).

#### 4.5.2. Helper constructors

Construction is ergonomic via per-form helpers that take regular seqs
and delegate to `parseNonEmptySeq` (§4.6):

```nim
func rawMulti*(
    values: seq[string],
): Result[BlueprintHeaderMultiValue, ValidationError] =
  let ne = ? parseNonEmptySeq(values)
  ok(BlueprintHeaderMultiValue(form: hfRaw, rawValues: ne))

func textMulti*(
    values: seq[string],
): Result[BlueprintHeaderMultiValue, ValidationError] = ...
# (one per form; mechanical)
```

No single top-level constructor — the form-specific helpers match
the variant shape. Alternatively, callers can construct via the case
object directly if they already hold a `NonEmptySeq[T]` (e.g., from an
earlier call), though the helpers are the ergonomic path.

**Single-value common case:** for the overwhelmingly common case of one
value, helpers with `Single` variants provide a zero-ceremony path:

```nim
func rawSingle*(value: string): BlueprintHeaderMultiValue =
  BlueprintHeaderMultiValue(
    form: hfRaw,
    rawValues: NonEmptySeq[string].parseNonEmptySeq(@[value]).tryGet,
  )
# (and similar textSingle, subjectSingle, etc.)
```

`tryGet` is safe here because `@[value]` is known non-empty.

#### 4.5.3. Serde

`toJson` on `BlueprintHeaderMultiValue` is not a standalone public
function — `BlueprintHeaderMultiValue` has no wire identity
independently of its paired name. The wire-key composition happens at
the consumer layer (§3.6 for `EmailBlueprint.toJson`; similarly for
`BlueprintBodyPart.toJson` in §5.4). The composition rule:

- Wire key: `"header:<name>:as<form-suffix>"`, with `":all"` appended
  iff the `NonEmptySeq`'s `.len > 1`.
- Wire value: the single element (when `.len == 1`) serialised per
  `HeaderValue`-style rules, or a JSON array of elements (when `.len > 1`).

`<form-suffix>` is derived from `form` via the established HeaderForm
→ string mapping (Part C §2.1: `hfRaw`→`"asRaw"`, etc.).

No `fromJson` — creation types are unidirectional.

#### 4.5.4. Rationale

- **Make illegal states unrepresentable.** Form uniformity and
  non-emptiness are structural, not runtime. Two variants (the former
  `ebcExtraHeaderFormMismatch` enum variant and an "empty extraHeaders
  entry" runtime check) are eliminated at the type level.
- **One source of truth per fact.** Form is stored exactly once — on
  the `BlueprintHeaderMultiValue` value. The Table key carries only
  the name. No possibility of key-vs-value form disagreement because
  there is only one place form lives.
- **Code reads like the spec.** The wire format uses
  `header:X:asForm[:all]`; the type mirrors this: name (on key), form
  (on value), multi-value semantic (on value via seq.len).
- **DRY.** `NonEmptySeq[T]` (§4.6) is used seven times across
  BlueprintHeaderMultiValue's variants — one generic type, seven
  instantiations. No per-variant duplication.
- **Precedent scales.** Fifth application of the strip-pattern (§2.2
  sidebar): BlueprintHeaderMultiValue strips form-on-key and
  non-empty-invariant into type-level structure, parallel to the
  four earlier applications.

### 4.6. NonEmptySeq[T]

**Module:** `src/jmap_client/primitives.nim` (extended).

`NonEmptySeq[T]` is a generic distinct seq with an at-least-one
invariant. Used by `BlueprintHeaderMultiValue` (§4.5) and available for
any future code path that requires a non-empty sequence.

#### 4.6.1. Type Definition

```nim
type NonEmptySeq*[T] = distinct seq[T]
```

Borrowed read-only operations via a new template
`defineNonEmptySeqOps[T]` (analogous to `defineStringDistinctOps` and
`defineHashSetDistinctOps`): `==`, `$`, `hash`, `len`, `contains`,
`iterator items`, `iterator pairs`, `[]` (non-mutating index access).

Mutating operations (`add`, `setLen`, `del`) are **not** borrowed —
mutation could violate the non-empty invariant.

#### 4.6.2. Smart Constructor

```nim
func parseNonEmptySeq*[T](
    s: seq[T],
): Result[NonEmptySeq[T], ValidationError]
```

Validates `s.len > 0`. Returns `err(ValidationError)` with
`typeName: "NonEmptySeq"` for empty input.

#### 4.6.3. Rationale

- **Make illegal states unrepresentable — in a reusable form.** The
  non-empty invariant is type-level. Any `NonEmptySeq[T]` value in
  scope is provably non-empty.
- **Newtype everything that has meaning — generically.**
  `NonEmptyMailboxIdSet` (§4.2) is the concrete sibling for mailbox
  ids; `NonEmptySeq[T]` is the generic analogue. Same pattern,
  extended, not invented.
- **DRY.** Used seven times within `BlueprintHeaderMultiValue` (§4.5)
  without per-variant duplication of the invariant.
- **Precedent scales.** Future design parts (F–I) can use
  `NonEmptySeq[T]` wherever a non-empty-list invariant arises without
  introducing further specialised distinct types.

---

## 5. Cross-Part Modifications

Part E's decisions require additive modifications to earlier parts and
to the primitives module. This section catalogues each change
explicitly so implementers can locate them at a glance and so future
readers do not need to reconstruct the delta by diffing design
documents.

Modified modules span three parts:

- Part C (body.nim, serde_body.nim, headers.nim) — §5.1–§5.4
- Part B (mailbox.nim) — §5.5
- Layer 1 primitives (primitives.nim) — §5.6

Most modifications are **additive** at the type level (no fields
removed, no types removed). Two §5.2 changes are additionally
**construction-site breaking** at the source level (existing
brace-syntax constructions of `BlueprintBodyPart` and all inserts into
`BlueprintBodyPart.extraHeaders` require migration).

### 5.1. body.nim — value field on bpsInline

**Module:** `src/jmap_client/mail/body.nim`.

**Change:** Add a `value: BlueprintBodyValue` field to the `bpsInline`
branch of `BlueprintBodyPart`.

**Before (Part C §3.5):**

```nim
of bpsInline:
  partId*: PartId
```

**After:**

```nim
of bpsInline:
  partId*: PartId
  value*: BlueprintBodyValue   ## co-located with its partId
```

**Rationale:** R3-3. Co-locating the value with the partId removes the
need for a separate `bodyValues: Table[PartId, BlueprintBodyValue]`
field on `EmailBlueprint`. References cannot be unresolved because
there is no separate structure for them to resolve against — the value
is structurally present at the inline part. Constraint 8 ("partId
references must resolve to bodyValues") disappears.

**Call-site impact:** existing code that constructs
`BlueprintBodyPart(source: bpsInline, partId: X)` without a `value`
field will no longer compile. All such constructions must be updated
to include `value`. Part C's tests (scenarios in §4.9) that exercise
this branch need the added field.

**Serde impact:** see §5.4.

### 5.2. body.nim — extraHeaders retyped

**Module:** `src/jmap_client/mail/body.nim`.

**Change:** Both parameters of `BlueprintBodyPart.extraHeaders` change.
The key type becomes `BlueprintBodyHeaderName` (name-only distinct
string); the value type becomes `BlueprintHeaderMultiValue` (case
object carrying form + non-empty seq of values).

**Before (Part C §3.5):**

```nim
extraHeaders*: Table[HeaderPropertyKey, HeaderValue]
```

**After:**

```nim
extraHeaders*: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]
```

**Rationale:** R3-4 + E28 (post-RFC-audit). Three constraints become
type-level simultaneously: no Content-Transfer-Encoding (constraint 9,
on the key type); key/value form consistency (constraint 10, now
impossible — form lives once, on the value); no duplicate header in
extraHeaders (constraint 3d, the intra-Table axis — the Table key's
identity is name-only).

**Call-site impact:** every insert site into body-part extraHeaders
must be updated. A typical migration:

```nim
# Before:
bp.extraHeaders[headerKey] = headerValue

# After:
let name = ? parseBlueprintBodyHeaderName("X-Custom")
let value = ? textMulti(@["v"])   # or rawMulti, etc.
bp.extraHeaders[name] = value
```

Part C tests that populate `extraHeaders` require rewriting against
the new Name / BlueprintHeaderMultiValue pair.

### 5.3. headers.nim — creation-model header vocabulary

**Module:** `src/jmap_client/mail/headers.nim`.

**Change:** Add a new "Creation-Model Header Vocabulary" labelled
section (parallel to the existing read-model contents), housing three
new types and their smart constructors. Specified in full in §4.3,
§4.4, and §4.5 of this document.

```
## ──────────────────────────────────────────────
## Read-Model Header Vocabulary
## ──────────────────────────────────────────────
# (existing) HeaderForm, HeaderPropertyKey, HeaderValue, EmailHeader,
# allowedForms, parseHeaderPropertyName, EmailHeader smart ctor, serde

## ──────────────────────────────────────────────
## Creation-Model Header Vocabulary
## ──────────────────────────────────────────────
# (new in Part E)
# BlueprintEmailHeaderName (§4.3) + parseBlueprintEmailHeaderName
# BlueprintBodyHeaderName  (§4.4) + parseBlueprintBodyHeaderName
# BlueprintHeaderMultiValue (§4.5) + rawMulti / textMulti / ...
```

The labelled-section pattern mirrors R3-5a's treatment of
`MailboxIdSet` / `NonEmptyMailboxIdSet` in `mailbox.nim`: two
parallel worlds (read vs creation) made structurally visible at
the file level rather than only at the type name level.

**Rationale:** R3-4 + E28. See §4.3, §4.4, and §4.5 for detailed
per-type rationale.

**Call-site impact:** none for existing code — the new types are
additive. Only Part E's new code (and the retyped `extraHeaders`
fields in §5.2 and on `EmailBlueprint`) depends on them.

### 5.4. serde_body.nim — toJson split

**Module:** `src/jmap_client/mail/serde_body.nim`.

**Change:** `BlueprintBodyPart.toJson` emits `partId` only on the
`bpsInline` branch; it does **not** emit the co-located `value`. The
value is harvested separately by `EmailBlueprint.toJson`, which walks
the tree and collects values into a top-level `bodyValues` JSON object.

**Before (Part C §3.6):**

`BlueprintBodyPart.toJson` emitted the part's structure — `partId` on
inline leaves — with the separate `bodyValues` map provided by the
enclosing EmailBlueprint's field.

**After:**

`BlueprintBodyPart.toJson` still emits `partId` on inline leaves and
does not emit `value`. The `value` is reachable from the tree (§5.1)
but excluded from the part-level JSON so the wire format stays RFC-
compliant — the RFC wire JSON has partId in the tree and value in the
separate top-level `bodyValues` map.

```nim
# Pseudocode for the inline branch of BlueprintBodyPart.toJson:
of false:   # leaf
  case bp.source
  of bpsInline:
    result["partId"] = %($bp.partId)
    # bp.value is NOT emitted here — see EmailBlueprint.toJson
  of bpsBlobRef:
    result["blobId"] = %($bp.blobId)
    # (charset, size emitted per Part C §3.6)
```

`EmailBlueprint.toJson` performs the harvest:

```nim
# Pseudocode sketch:
proc harvestBodyValues(bp: BlueprintBodyPart,
                        out: var JsonNode) =
  case bp.isMultipart
  of true:
    for child in bp.subParts: harvestBodyValues(child, out)
  of false:
    case bp.source
    of bpsInline:
      out[$bp.partId] = bp.value.toJson
    of bpsBlobRef:
      discard   # blob-ref leaves have no inline value

# In EmailBlueprint.toJson, after emitting the body tree:
let values = newJObject()
case bp.bodyKind
of ebkStructured:
  harvestBodyValues(bp.bodyStructure, values)
of ebkFlat:
  for b in bp.textBody: harvestBodyValues(b, values)
  for b in bp.htmlBody: harvestBodyValues(b, values)
  for part in bp.attachments: harvestBodyValues(part, values)
if values.len > 0:
  result["bodyValues"] = values
```

**Rationale:** R3-3 requires the wire format to stay unchanged while the
domain model is denormalised. The split between
`BlueprintBodyPart.toJson` (emits tree shape) and
`EmailBlueprint.toJson` (emits tree + harvested bodyValues) is
precisely the serde owning the wire/domain asymmetry — the same
principle as singular-sender's single-element wire array (§3.6).

**Test impact:** Part C's `BlueprintBodyPart.toJson` serde tests need to
reflect that the `value` field is not emitted at the part level. Part E
includes new integration tests exercising the
`EmailBlueprint.toJson` ↔ harvested `bodyValues` path.

### 5.5. mailbox.nim — NonEmptyMailboxIdSet

**Module:** `src/jmap_client/mail/mailbox.nim`.

**Change:** Add `NonEmptyMailboxIdSet`, `parseNonEmptyMailboxIdSet`,
and associated borrowed operations. Organise the two mailbox-ID set
types under a shared labelled section per §4.2.3.

**Rationale:** R3-5, R3-5a. See §4.2 for detailed rationale.

**Call-site impact:** none for existing code — the new type is additive.
Only Part E's new code (`EmailBlueprint.mailboxIds`) depends on it.

### 5.6. primitives.nim — NonEmptySeq[T]

**Module:** `src/jmap_client/primitives.nim`.

**Change:** Add the generic `NonEmptySeq[T]` distinct type,
`parseNonEmptySeq[T]` smart constructor, and the
`defineNonEmptySeqOps[T]` borrowed-operations template. Specified in
full in §4.6 of this document.

**Rationale:** E28 (post-RFC-audit). `BlueprintHeaderMultiValue` (§4.5)
requires a non-empty-seq invariant on seven variant payloads;
introducing the invariant once, generically, in primitives.nim
satisfies DRY while applying "newtype everything that has meaning"
uniformly. `NonEmptyMailboxIdSet` (§4.2, E14) remains unchanged — it
is a distinct `HashSet[Id]` (a different container kind), not a
distinct seq, so it does not collapse into `NonEmptySeq[Id]`.

**Call-site impact:** none for existing code — the new type is
additive. Initially used only by `BlueprintHeaderMultiValue`; future
design parts may adopt it wherever a non-empty-list invariant arises.

---

## 6. Test Specification

Numbered test scenarios for implementation plan reference. Self-contained
numbering from 1 per R5-3, following Parts C and D. Alphabetic suffixes
(`4a`, `11b`) reserved for expansions within a scenario.

This section has been through **two** rounds of post-audit review.

The **first audit** was a three-perspective cycle (adversarial,
completeness, infrastructure) that surfaced systematic gaps around the
error-triad value types, the `message` renderer, FFI panic safety,
hash-collision resistance, error-accumulation stress, and the Part D
§12.14 test-infrastructure precedent. That audit produced the five-
category structure below and populated §6.1.0, §6.1.6, §6.3.2, §6.3.3,
§6.4.4, and §6.5.

The **second audit** was a further three-perspective review
(adversarial / ergonomic / formal-coverage) that found:
- Five "cannot-fail" tautologies in the first-audit adversarial
  scenarios (99c, 99d, 72a, 11b unbounded, 102 grep-based) — now loud
  regression gates.
- A K-2 ordering contradiction: sc 101 wanted set-style equality while
  property 94 wanted ordered equality under the same helper. Split
  into K-2 (set-style) and K-9 (ordered).
- Ten trivial or duplicated scenarios (8, 11, 13, 14, 15, 16, 19, 22,
  28, 37m, 37n, 37o, 71, 74, 80, 100b, 100c) — merged into neighbours
  or removed because the compiler, a property, or a peer scenario
  already covers them.
- Five uncovered R-decisions: R1-1 public export surface (sc 48j),
  R2-2 identifier-to-wire-key aliasing (sc 1a), R3-2b `ebcNoBodyContent`
  absence (sc 48k), R2-4 UTC-suffix pattern (sc 58a), and the
  strict-only parser commitment (sc 32c).
- Three dangling cross-references (72a→E30, I-2 consumer 34, L-6
  consumer 54) — fixed.
- Ten new adversarial scenarios (98d–98f, 99f, 100e, 101c, 102c, 102d,
  104c) and five new properties (97a–97e) covering locale invariance,
  homoglyph bypass, hash-DoS assertion, integer-overflow surface, BOM/
  NUL byte-preservation, bounded error rendering, JSON re-parsability,
  `BodyPartPath` depth-coupling (promised in sc 37r but previously
  unscheduled), and insertion-order insensitivity of value equality.
- File-cohesion cleanup: collapsed two sub-40-line files into siblings;
  split `tadversarial.nim` and `tserde_email_blueprint.nim` to stay
  under the nimalyzer complexity threshold; replaced the grep-based
  sc 102 with a compile-time macro.
- Five new infrastructure rows (I-15–I-19, J-16, K-9, L-7–L-9) and
  eight existing-row edits (I-2/I-4/I-11, J-5/J-8/J-13/J-15, L-1/L-6)
  closing 20-consumer duplications, convention gaps, and precedent
  mis-citations.

The restructured specification has five categories:

1. **Unit** (§6.1) — specific scenarios per smart-constructor
   invariant and per decision. Includes embedded `assertNotCompiles`
   scenarios for type-level invariants (§6.1.6).
2. **Serde** (§6.2) — `toJson` output shape per field, variant, and
   RFC constraint.
3. **Property-based** (§6.3) — thirteen principle-grounded properties
   (seven foundational per R5-1, three completeness-audit supplements,
   three adversarial per post-audit).
   Each property names its generator, trial count, principle defended,
   and R-decision guarded (Part D §12.12 precedent).
4. **Adversarial** (§6.4) — byte-level, structural, resource-exhaustion,
   and FFI-panic-surface scenarios. Follows the conventions of
   `tests/serde/tserde_adversarial.nim` and
   `tests/stress/tadversarial.nim`.
5. **Test infrastructure** (§6.5 — new) — factories, generators,
   equality helpers, assertion templates, test-file assignments, and
   the 7-step fixture-protocol compliance table. Without this
   subsection every scenario must reinvent scaffolding, violating the
   "duplicated appearance ≠ duplicated knowledge" principle in the
   direction where the knowledge IS shared.

### 6.1. Unit (scenarios 1–59)

Organised by type / decision.

#### 6.1.0. Eliminations documented in types (no runtime scenario)

Nine RFC §4.6 / architecture §8.5 invariants are eliminated at the type
level per §1.3, plus one structural well-formedness invariant
(non-empty header values) eliminated by `NonEmptySeq[T]`. The
constructions that would violate them do not compile; a runtime
scenario is unconstructible. Each row is cross-referenced to its
compile-time guard so a reader can follow the defence without
rediscovering the elimination:

| Eliminated invariant | Type-level mechanism | Compile-time guard |
|----------------------|---------------------|--------------------|
| Empty `mailboxIds` (constraint 1) | `NonEmptyMailboxIdSet` signature-level input type | §6.1.3 scenario 25 (parse boundary) + §6.1.6 scenario 48a |
| No `headers` array on `BlueprintBodyPart` (constraint 2) | `headers` field stripped from `BlueprintBodyPart`; only `extraHeaders` Table field is present (Part C §3.5) | §6.2.4 scenario 76 (serde verifies absence of `"headers"` key) |
| Intra-Table duplicate name in `extraHeaders` (constraint 3d) | name-only Table key (§4.3 / §4.4) | §6.1.6 scenario 48e |
| Content-* at Email top level (constraint 4) | `BlueprintEmailHeaderName` forbids `content-*` | §6.1.4 scenarios 29, 29a, 32, 32a |
| Body-XOR violation (constraint 5) | `EmailBlueprintBody` case object | §6.1.6 scenarios 48b, 48c, 48h |
| `BlueprintBodyValue` flag fields (constraint 6) | fields stripped from the type | §6.1.6 scenario 38 (merged pair) |
| `bodyValues` / tree disagreement (constraint 8) | `bodyValues` is derived, not stored | §6.1.7 scenarios 49, 50, 50a, 50b + property 92 (§6.3.2) |
| Content-Transfer-Encoding on body parts (constraint 9) | `BlueprintBodyHeaderName` forbids the exact name | §6.1.5 scenario 35 (consolidated) |
| Key/value form disagreement (constraint 10) | form lives once, on the value's discriminant | §6.1.6 scenario 48d |
| `extraHeaders` empty-value state (structural) | `NonEmptySeq[T]` invariant on the value's payload | §6.1.5b scenario 37e, §6.1.6 scenarios 48f, 48g |

(Scenarios 2, 4, 10, 10a, 23, and 60 from the pre-audit layout have
been subsumed into the above table. Keeping them as numbered "N/A" rows
inflated the scenario count without adding runnable assertions.)

#### 6.1.1. `EmailBlueprint` smart constructor (scenarios 1–18)

| # | Scenario | Expected |
|---|----------|----------|
| 1 | `parseEmailBlueprint(mailboxIds = ?parseNonEmptyMailboxIdSet([inboxId]))` with all other defaults | `ok`; `body.kind == ebkFlat`; `body.textBody` and `body.htmlBody` are `Opt.none`; `body.attachments.len == 0` |
| 1a | Public naming contract (R2-2 / E5): `assertCompiles bp.fromAddr` AND `assertNotCompiles bp.`from`` (Nim keyword) AND `assertCompiles bp.mailboxIds` — pins the identifier-to-wire-key aliasing decision against an accidental rename regression | All three compile assertions hold |
| 3 | `parseEmailBlueprint(mailboxIds = ..., body = structuredBody(rootPart))` | `ok`; `body.kind == ebkStructured`; `body.bodyStructure` equals `rootPart` via `blueprintBodyPartEq` (§6.5.4 K-5) |
| 5 | `body = flatBody(textBody = some(part))` where `part.contentType == "text/html"` | `err` with exactly one `ebcTextBodyNotTextPlain`; `actualTextType == "text/html"` — pin variant *and* payload via `assertBlueprintErrContains` (§6.5.5 L-2) |
| 6 | `body = flatBody(htmlBody = some(part))` where `part.contentType == "text/plain"` | `err` with exactly one `ebcHtmlBodyNotTextHtml`; `actualHtmlType == "text/plain"` |
| 7 | `fromAddr = some(...)` AND `extraHeaders` contains an entry keyed by `parseBlueprintEmailHeaderName("From")` | `err` with `ebcEmailTopLevelHeaderDuplicate`; `dupName == "from"` (lowercase canonical) |
| 7a | `body = structuredBody(rootPart)` where `rootPart.extraHeaders` contains an entry keyed by `parseBlueprintBodyHeaderName("Subject")` AND Email top-level has `subject = some("X")` | `err` with `ebcBodyStructureHeaderDuplicate`; `bodyStructureDupName == "subject"` (Gap 1 / RFC lines 2866-2868) |
| 7b | `body = structuredBody(rootPart)` where both `rootPart.extraHeaders` AND Email-top-level `extraHeaders` contain an entry keyed by `"From"` | `err` with `ebcBodyStructureHeaderDuplicate`; `bodyStructureDupName == "from"` — same name in both Tables |
| 7c | `bodyStructure` root has a header name NOT present at Email top level (e.g., `"X-Custom"`) | `ok` — no duplicate |
| 7d | `ebkStructured` with a multipart root whose SUB-PART (not root) shares a header name with an Email top-level header | `ok` — scope is ROOT only per RFC's singular phrasing; sub-parts are covered by 7e–7h (within-body-part check) |
| 7e | `BlueprintBodyPart` with `contentType = "text/plain"` AND `extraHeaders` keyed by `parseBlueprintBodyHeaderName("Content-Type")` | `err` with `ebcBodyPartHeaderDuplicate`; `where` locates the offending part; `bodyPartDupName == "content-type"` (Gap 2 / RFC lines 2844-2846) |
| 7f | `BlueprintBodyPart` with `disposition = some("attachment")` AND `extraHeaders` keyed by `parseBlueprintBodyHeaderName("Content-Disposition")` | `err` with `ebcBodyPartHeaderDuplicate`; `where.kind` matches the part kind; `bodyPartDupName == "content-disposition"` |
| 7g | Within-body-part duplicate on a multipart node (no `partId`) at a 3-level tree | `err` with `ebcBodyPartHeaderDuplicate`; `where.kind == bplMultipart`; `where.path == BodyPartPath(@[0, 2])` — pins the path encoding claim from §3.4 |
| 7h | Within-body-part duplicate on a blob-ref leaf at depth 2 | `err` with `ebcBodyPartHeaderDuplicate`; `where.kind == bplBlobRef`; `where.blobId` matches the referenced blob |
| 7i | `structuredBody(rootMultipart)` where `rootMultipart.extraHeaders` has TWO entries, one keyed by `"From"` and one by `"Subject"`, both duplicating top-level convenience fields | `err` accumulating TWO `ebcBodyStructureHeaderDuplicate` entries; `bodyStructureDupName` stored lowercase (`"from"`, `"subject"`); assertion via `assertBlueprintErrCount(expr, 2)` (§6.5.5 L-3) |
| 7j | `sentAt = some(date)` AND `extraHeaders[parseBlueprintEmailHeaderName("date")] = dateMulti(@[d2])` | `err` with `ebcEmailTopLevelHeaderDuplicate`; `dupName == "date"` — verifies the `sentAt`/`Date` alias collision per §3.6.1's convenience-field table |
| 7k | `ebkFlat` with duplicate `Content-Type` inside `attachments[2]`'s nested multipart at depth 2 | `err` with `ebcBodyPartHeaderDuplicate`; first path element is `4` per §3.4's `ebkFlat` encoding (0=textBody, 1=htmlBody, 2+i=attachments[i]) |
| 7l | `BodyPartLocation` round-trip equality: construct the expected `BodyPartLocation` for each of the three `BodyPartLocationKind` variants and assert `bodyPartLocationEq` (§6.5.4 K-3) holds | `ok` for all three — pins the K-3 helper's behaviour for the three variant shapes |
| 9 | `extraHeaders` entry with a name/form pair not in `AllowedHeaderForms` (e.g., `Subject` with `hfAddresses`) | `err` with `ebcAllowedFormRejected`; `rejectedName == "subject"`; `rejectedForm == hfAddresses` |
| 11a | For each of the 6 `EmailBlueprintConstraint` variants, build a minimal failing blueprint, then call `message(e)` on the produced error | Returns a non-empty string; mentions the variant's characteristic payload (e.g., `dupName`, `actualTextType`); the 6 rendered messages are pairwise distinct |
| 11b | `message(e)` called twice on the same `EmailBlueprintError` whose payload carries adversarial data (NUL, CRLF, 100 KB string) | Returns byte-identical string both times; `message(e).len ≤ 8 KiB` (log-injection / memory-exhaustion bound); `'\x00' notin message(e)` (prevents C-consumer truncation via NUL); no panic; no side effect (verifies the L1 `{.push raises: [], noSideEffect.}` contract) |
| 12 | All 11 convenience fields populated with distinct marker values via `makeFullEmailBlueprint` (§6.5.2 I-10) AND `keywords = initKeywordSet([seenKw])` AND `receivedAt = Opt.none(UTCDate)` on one variant / `some(specificDate)` on another / `sender = some(bob)` on a third | `ok`; every UFCS accessor returns the expected marker (collapses ex-13/14/15/16); the per-row wire-key pinning lives in §6.2.2 (not duplicated here) |
| 17 | `body = flatBody(attachments = @[a1, a2])` — only attachments, per R3-2b | `ok`; `body.kind == ebkFlat`; `body.attachments.len == 2`; `body.textBody` and `body.htmlBody` are `Opt.none` |
| 18 | `body = flatBody()` — fully empty flat body, per R3-2b | `ok`; `toJson` emits NO `textBody`, `htmlBody`, `attachments`, or `bodyValues` keys (all four absent per R4-2/R4-3) |

(Scenario 20 — "same-input determinism" — removed; covered exclusively
by property 87 (§6.3.1). Scenarios 2, 4, 10, 10a subsumed into §6.1.0.
Second-audit removals: sc 8 and 11 — both accumulation scenarios dominated
by sc 101 (all-six-variants-simultaneously, §6.4.3) plus property 88;
sc 13, 14, 15, 16 — trivial accessor reassertions now folded into sc 12's
marker-tuple pattern; sc 19 — duplicated sc 49's multipart-harvest claim,
kept at §6.1.7 where derived-accessor tests belong.)

#### 6.1.2. `BlueprintBodyValue` (scenario 21)

| # | Scenario | Expected |
|---|----------|----------|
| 21 | `BlueprintBodyValue(value: "Hello")` — `toJson` output | `{"value": "Hello"}` (pins the single-field serde shape) |

(Scenario 22 — empty-string `toJson` — removed in the second audit;
`%*{"value": v.value}` is a one-line pass-through with no branch to
verify. The empty-string preservation invariant is documented as a
non-test note in §4.1.3. Scenario 23 — "round-trip not attempted" —
removed in the first audit; commitment already stated in §4.1.3. A
test row MUST correspond to a runnable assertion.)

#### 6.1.3. `NonEmptyMailboxIdSet` (scenarios 24–27)

| # | Scenario | Expected |
|---|----------|----------|
| 24 | `parseNonEmptyMailboxIdSet([id1])` | `ok` with `len == 1` |
| 25 | `parseNonEmptyMailboxIdSet([])` | `err(ValidationError)` with `typeName == "NonEmptyMailboxIdSet"` |
| 26 | `parseNonEmptyMailboxIdSet([id1, id2, id1])` — duplicates collapsed | `ok`; `len == 2` |
| 27 | Two `NonEmptyMailboxIdSet` values constructed from equal input seqs satisfy `==` and `hash` equality under `nonEmptyMailboxIdSetEq` (§6.5.4 K-8) | both hold — distinct type must not interfere with set equality |
| 27a | `assertNotCompiles`: given `let s = ?parseNonEmptyMailboxIdSet([id1])`, attempting `s.incl(id2)`, `s.excl(id1)`, `s.clear()` | All three fail to compile (§4.2.1: "Mutating operations are deliberately not borrowed") |

#### 6.1.4. `BlueprintEmailHeaderName` (scenarios 28a–32c)

Input contract (E28): name-only, no `header:` prefix, no form suffix.
Validates non-empty, printable ASCII (33–126), no colon, not `content-*`
after ASCII lowercase normalisation.

| # | Scenario | Expected |
|---|----------|----------|
| 28a | Case-variant equality table: `parseBlueprintEmailHeaderName` applied to `"X-Custom"`, `"x-custom"`, `"X-CUSTOM"` | All three `ok`; each stores `"x-custom"` after ASCII lowercase normalisation; all three results pairwise equal under `==`; all three hashes pairwise equal (consolidated scenario replacing the pre-audit 28/28a/28b triad; second audit folds the sole-`"X-Custom"` sc 28 into this row to avoid a standalone case-variant restatement) |
| 29 | `parseBlueprintEmailHeaderName("Content-Type")` | `err(ValidationError)` — `content-*` forbidden |
| 29a | Forbidden-prefix variant table: `parseBlueprintEmailHeaderName` applied to `"Content-Disposition"`, `"CONTENT-TYPE"`, `"content-type"` | All three `err` — post-normalisation prefix match (consolidates 29a/29b) |
| 30 | Wire-format / colon rejection table: `parseBlueprintEmailHeaderName("header:X-Custom:asText")`, `parseBlueprintEmailHeaderName("X:Custom")` | Both `err` — colon is not valid in RFC 5322 `ftext`. Callers with wire strings use `parseHeaderPropertyName` (Part C §2.3) and pass `.name` |
| 31 | Character-validation rejection table (one byte per row): `""`, `"X-Has Space"` (0x20), `"X-Has\tTab"` (0x09), `"X-Del\x7F"` (DEL), `"X-\x00NUL"` (NUL), `"X-UTF8-\xC3\xA9"` (high byte) | All `err` — consolidates 31/31a/31b/31c/31d as a table-driven scenario |
| 32 | Prefix-boundary table: `parseBlueprintEmailHeaderName("Content")` (no hyphen), `"contents"` (no hyphen after prefix), `"content-"` (minimum forbidden value) | First two `ok`, third `err` — pins the `startsWith("content-")` check exactly |
| 32a | `parseBlueprintEmailHeaderName` iterated over every byte 0..255 in position 0 and in the middle of a 10-char name | `ok` iff byte ∈ {0x21..0x7E}; `err` otherwise. Exactly 94 accepted bytes per position, 162 rejected — pins the printable-ASCII predicate against off-by-one errors on 0x20 / 0x7F (adversarial boundary per A-11) |
| 32c | `assertNotCompiles parseBlueprintEmailHeaderNameFromServer("X-Custom")` (and the symmetric body variant) | Does not compile — pins the **strict-only** naming commitment: no lenient server-side sibling exists for either blueprint header-name type. The creation vocabulary is unidirectional (R1-3); Postel's-law lenient parsing is for read-model types only (§1.4). A future accidental add of a `*FromServer` parser would open a second construction path through the creation aggregate, violating "constructors are privileges, not rights." |

#### 6.1.5. `BlueprintBodyHeaderName` (scenarios 33–37b)

Input contract (E28): name-only; printable ASCII 33–126; no colon; not
equal to `content-transfer-encoding` after ASCII lowercase normalisation.
`Content-Type`, `Content-Disposition`, etc. are permitted on body parts.

| # | Scenario | Expected |
|---|----------|----------|
| 33 | Allowed-name table: `parseBlueprintBodyHeaderName` applied to `"Content-Type"`, `"Content-Disposition"`, `"Content-Language"`, `"X-Custom"` | All `ok` — consolidates 33/33a/33b/34 |
| 35 | Exact-name rejection table: `parseBlueprintBodyHeaderName` applied to `"Content-Transfer-Encoding"`, `"CONTENT-TRANSFER-ENCODING"`, `"content-transfer-encoding"`, `"Content-transfer-Encoding"` (irregular mixed case) | All `err` — consolidates 35/35a/35b plus A-12's mixed-case boundary |
| 35c | `parseBlueprintBodyHeaderName("Content-Transfer-Encoding-X")` — not an exact name match | `ok` |
| 35d | `parseBlueprintBodyHeaderName("\xC3\x83\xC2\xA7ontent-Type")` — UTF-8 homoglyph visually approximating "Content-Type" | `err` — printable-ASCII check fires before the exact-name check; adversarial prefix bypass attempt rejected (A-12) |
| 36 | Character-validation rejection table (body scope): `""`, `"X-Has Space"`, `"X-Has\tTab"`, `"header:X-Custom:asText"` | All `err` — consolidates 36/36a/37/37a plus the wire-format colon rejection |
| 37b | Case equivalence: `parseBlueprintBodyHeaderName("X-Custom")` and `parseBlueprintBodyHeaderName("x-custom")` | Both `ok`; equal under `==`; hashes equal |

#### 6.1.5a. `BlueprintHeaderMultiValue` (scenarios 37c–37h)

| # | Scenario | Expected |
|---|----------|----------|
| 37c | `rawMulti(@["v1"])` | `ok`; `form == hfRaw`; `rawValues.len == 1` (single-instance wire form) |
| 37d | `rawMulti(@["v1", "v2"])` | `ok`; `rawValues.len == 2` (multi-instance `:all` wire form) |
| 37e | `rawMulti(@[])` | `err` — delegates to `parseNonEmptySeq` which rejects empty input |
| 37f | Per-form helper coverage table: `textMulti`, `addressesMulti`, `groupedAddressesMulti`, `messageIdsMulti`, `dateMulti`, `urlsMulti` | Each produces `ok`; each sets `form` to its corresponding `HeaderForm`; `.len == 1` in the minimal case |
| 37g | `rawSingle("value")` — zero-ceremony helper for single-valued hfRaw | `ok` without `Result` wrapping; `form == hfRaw`; `.len == 1` |
| 37h | Direct case-object construction: `BlueprintHeaderMultiValue(form: hfRaw, rawValues: ?parseNonEmptySeq(@["v"]))` | `ok`; structurally equal to `rawMulti(@["v"]).get()` via `blueprintHeaderMultiValueEq` (§6.5.4 K-6) |

#### 6.1.5b. `NonEmptySeq[T]` (scenarios 37i–37l)

| # | Scenario | Expected |
|---|----------|----------|
| 37i | `parseNonEmptySeq(@[1, 2, 3])` | `ok`; `len == 3`; iteration yields `1, 2, 3` in order; `ne[0] == 1`; `ne[2] == 3` |
| 37j | `parseNonEmptySeq[string](@[])` | `err(ValidationError)`; `typeName == "NonEmptySeq"` |
| 37k | Two `NonEmptySeq[int]` constructed from equal input seqs | Equal under `==`; equal under `hash` (verifies borrowed read-only ops) |
| 37l | `assertNotCompiles`: `ne.add(x)`, `ne.setLen(0)`, `ne.del(0)` | All three fail to compile (§4.6.1: mutating ops deliberately un-borrowed — the invariant is preserved by construction, enforced by compile error on mutation) |

(Scenario 37m — `$ne` borrowed representation — removed in the second
audit; the `defineNonEmptySeqOps[T]` template borrows `$` from `seq[T].$`,
which the Nim standard library already guarantees produces a non-empty
string for any non-empty seq. No project-owned branch to verify.)

#### 6.1.5c. `BodyPartPath` / `BodyPartLocation` value types (scenarios 37p–37r)

| # | Scenario | Expected |
|---|----------|----------|
| 37p | `BodyPartLocation(kind: bplInline, partId: p)` vs `BodyPartLocation(kind: bplBlobRef, blobId: p)` (where `p` has structurally equal bytes) | Not equal under `bodyPartLocationEq` (§6.5.4 K-3) — discriminant differs even though payload bytes coincide |
| 37q | `parseEmailBlueprint` with a tree whose deepest duplicate sits at `BodyPartPath(@[0, 1, 2, 3, 4])` (depth-5 path) | `err` with `where.path.seq.len == 5`; no path element negative; first element < number of root's children |
| 37r | Depth-coupling invariant: for any valid blueprint-and-violation pair, the emitted `where.path.seq.len ≤ MaxBodyPartDepth` (128) | Holds across all scenarios exercised by §6.1.1 and §6.4; pinned as property 97d in §6.3.4 |

(Scenarios 37n, 37o — removed in the second audit as trivial restatements
of Nim's borrowed-`==` / borrowed-`hash` / value-type-is-not-nil
guarantees on a `distinct seq[int]`. The overflow-and-adversarial-payload
probe formerly implied by 37n is now scenario 99f (§6.4.2). The empty-path
"root multipart" semantic is design documentation in §3.4, not an
assertion.)

#### 6.1.6. Compile-time assertions (embedded per R5-2)

| # | Scenario | Expected |
|---|----------|----------|
| 38 | Flag-field stripping pair: `BlueprintBodyValue(value: "x", isEncodingProblem: false)` AND `BlueprintBodyValue(value: "x", isTruncated: false)` | Both fail to compile (`assertNotCompiles`) — R1-2; consolidates pre-audit 38 and 39 |
| 40 | Direct `EmailBlueprint(rawMailboxIds: ..., ...)` construction outside `email_blueprint.nim` | Does not compile — R2-1 (Pattern A sealing) |
| 41 | `BlueprintBodyPart(isMultipart: false, source: bpsInline, partId: x)` — missing mandatory `value` field | Does not compile — R3-3 |
| 42 | Header-key cross-context table: `Table[BlueprintEmailHeaderName, ...]` refuses `BlueprintBodyHeaderName` key; `Table[BlueprintBodyHeaderName, ...]` refuses `BlueprintEmailHeaderName` key; bare `HeaderPropertyKey` rejected by both | All fail to compile — R3-4 / E28 cross-context; consolidates pre-audit 42, 43, 44 |
| 45 | Writing `bp.rawMailboxIds` (or any `raw*` field) outside `email_blueprint.nim` | Does not compile — Pattern A sealing |
| 46 | Runtime case-object guard pair: `bp.body.bodyStructure` when `bp.body.kind == ebkFlat` AND `bp.body.textBody` when `bp.body.kind == ebkStructured` | Both raise `FieldDefect` at runtime (Nim's discriminant guard is runtime, not compile-time); consolidates pre-audit 46 and 47. See §6.4.4 scenario 102 for the static-analysis test preventing L1/L2 interior code from triggering this path |
| 48 | Empty `EmailBlueprintErrors` on the err rail | `doAssert` fails in `parseEmailBlueprint` internals — the invariant is non-empty by construction (R3-1) |
| 48a | `parseEmailBlueprint(mailboxIds = @[id1], ...)` — passing a plain `seq[Id]` instead of `NonEmptyMailboxIdSet` | Does not compile — signature-level strip (R3-5) |
| 48b | `EmailBlueprintBody(kind: ebkStructured, bodyStructure: X, textBody: some(Y))` — populating a flat-kind field in a structured-kind body | Does not compile — case discriminant (R3-4-body) |
| 48c | `EmailBlueprintBody(kind: ebkFlat, textBody: some(X), bodyStructure: Y)` — mirror of 48b | Does not compile — case discriminant |
| 48d | `BlueprintHeaderMultiValue(form: hfText, rawValues: ne)` — form discriminant does not match the active field | Does not compile — E28 / case-object discriminant rule |
| 48e | Intra-Table name dedup: insert two `(name, value)` pairs where names are byte-distinct but equal after lowercase normalisation | Table semantics: the second insert overwrites the first; `table.len == 1`; `toJson` emits exactly one entry using the LAST value. No leakage of the first value |
| 48f | `parseNonEmptySeq[string](@[])` | Returns `err(ValidationError)` at runtime (E28 / §4.6) — boundary refusal, not a compile error |
| 48g | `BlueprintHeaderMultiValue(form: hfRaw, rawValues: @[])` — attempting bare empty `seq[string]` bypassing `parseNonEmptySeq` | Does not compile — the field type is `NonEmptySeq[string]`, not `seq[string]`; distinct-type assignment rule refuses the plain seq |
| 48h | `parseEmailBlueprint(mailboxIds = ..., body = rootPart)` — passing a bare `BlueprintBodyPart` instead of `EmailBlueprintBody` | Does not compile — signature-level strip (E24), parallel to 48a |
| 48i | `var body = flatBody(); body.kind = ebkStructured; body.bodyStructure = rootPart` — discriminant reassignment post-construction | Does not compile — Nim forbids cross-variant discriminant reassignment outside object construction. **Explicit Nim-version regression guard** under the R5-2 compile-boundary exception (CLAUDE.md "make illegal states unrepresentable"): if a future Nim version loosens this rule, the test fails loud and drives an immediate project response. Not a triviality. |
| 48j | Public export surface compile contract (R1-1 / E1): from a sibling test module, `assertCompiles` the full enumerated import `from jmap_client/mail/email_blueprint import parseEmailBlueprint, flatBody, structuredBody, EmailBlueprint, EmailBlueprintBody, EmailBlueprintError, EmailBlueprintErrors, EmailBlueprintConstraint, mailboxIds, body, fromAddr, subject` | Compiles. Pins every public identifier the design commits to exporting; an accidental visibility demotion breaks the test. Lives in `tblueprint_compile_time.nim`. |
| 48k | `assertNotCompiles EmailBlueprintError(constraint: ebcNoBodyContent, ...)` — ex-variant for the dropped "at least one of textBody/htmlBody" invariant (R3-2b / E11) | Does not compile — the enum variant `ebcNoBodyContent` must not exist. Pins R3-2b against accidental re-introduction; complements scenarios 17 and 18 (positive attachments-only and empty-body success) with an explicit negative-compile guard. |
| 48l | `assertNotCompiles: EmailBlueprintErrors(@[])` outside `email_blueprint.nim` | Does not compile — the distinct-seq constructor is module-private; R3-1's non-empty invariant is enforced by (a) private constructor, (b) the internal `doAssert` in sc 48. This is the external-boundary counterpart to 48's internal audit probe. |

#### 6.1.7. Accessors and derived `bodyValues` (scenarios 49–50b)

| # | Scenario | Expected |
|---|----------|----------|
| 49 | `bp.bodyValues` on a blueprint with two inline parts in a multipart tree (partIds `"1"` and `"2"`) | Table with exactly two entries, keyed by `PartId("1")` and `PartId("2")`; each value equals the `BlueprintBodyValue` stored at the corresponding leaf via `blueprintBodyPartEq`-consistent comparison |
| 50 | `bp.bodyValues` on a blueprint with no inline parts (all blob-ref) | Empty table; no `bodyValues` key emitted by `toJson` (generalised at the serde tier by property 90 in §6.3.1) |
| 50a | `bp.bodyValues` after mutating the source tree construction (rebuilding with a different inline leaf payload) | Table reflects the new state — verifies the derived-accessor claim that `bodyValues` IS the tree projected, not a cached copy |
| 50b | Correspondence invariant: `bp.bodyValues.pairs` equals the `(partId, value)` pairs obtained by walking the body tree manually and harvesting inline leaves | Exact equality — no extraneous entries, no missing entries (pinned as property 92 in §6.3.2) |

### 6.2. Serde (scenarios 51–84)

Every serde scenario receives the golden JSON via a fixture derived
through `makeEmailBlueprint().toJson()` where appropriate, following
Part D §12.14's `makeEmailJson` / `makeParsedEmailJson` precedent. See
§6.5.2 I-14.

#### 6.2.1. Top-level shape (scenarios 51–59)

| # | Scenario | Expected |
|---|----------|----------|
| 51 | Minimal blueprint (mailboxIds only) → `toJson` | `{"mailboxIds": {<id>: true}}` — no other top-level keys |
| 52 | Blueprint with `keywords = initKeywordSet([seen])` | JSON contains `"keywords": {"$seen": true}` |
| 53 | Blueprint with empty keywords | `"keywords"` key **absent** (R4-3); `assertJsonKeyAbsent` (§6.5.5 L-5) |
| 54 | Blueprint with empty `extraHeaders` | No top-level `"header:*"` keys; `assertJsonKeyAbsent` iterates over the expected prefix |
| 55 | Blueprint with `fromAddr = some(@[alice])` | `"from"` present; JArray length 1; element has `email` and `name` keys |
| 56 | Blueprint with `sender = some(bob)` | `"sender"` present; **exactly 1-element JArray** (pin the length constraint explicitly; E6 RFC 5322 §3.6.2 mandates one mailbox) |
| 57 | Blueprint with `sender = Opt.none` | `"sender"` key **absent** (R4-2) — not `"sender": []`, not `"sender": null` |
| 58 | Blueprint with `receivedAt = some(utcDate)` | `"receivedAt": "2026-..."` (ISO 8601 UTC form) |
| 58a | `receivedAt = some(utcDate)` — wire string pattern | Matches `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$` — pins E7's UTC-suffix requirement (literal `Z`), distinguishing UTC from any numeric offset the `UTCDate` type might accidentally admit. Defends R2-4 at the wire level. |
| 59 | Blueprint with `receivedAt = Opt.none` | `"receivedAt"` key **absent** (R4-2) |

(Pre-audit scenario 60 subsumed into §6.1.0 — smart ctor prevents the
construction, no serde path to test.)

#### 6.2.2. Convenience field mapping (scenarios 61–66)

Each row asserts BOTH the JMAP wire key AND the exact wire payload
shape. Pre-audit scenarios 62 and 65 grouped multiple fields into a
single row; the post-audit layout pins each row individually so a serde
regression mis-routing one field to another's key is caught.

| # | Blueprint field set | Expected JSON key | Expected JSON value shape |
|---|---------------------|-------------------|---------------------------|
| 61 | `fromAddr = some(@[alice])` | `"from"` | JArray of 1 address object |
| 62a | `to = some(@[a, b])` | `"to"` | JArray of 2 address objects |
| 62b | `cc = some(@[a, b])` | `"cc"` | JArray of 2 address objects |
| 62c | `bcc = some(@[a, b])` | `"bcc"` | JArray of 2 address objects |
| 62d | `replyTo = some(@[a, b])` | `"replyTo"` | JArray of 2 address objects |
| 62e | `sender = some(bob)` | `"sender"` | 1-element JArray (singular cardinality) |
| 63 | `subject = some("hello")` | `"subject"` | JString `"hello"` |
| 64 | `sentAt = some(date)` | `"sentAt"` | JString (ISO 8601) |
| 65a | `messageId = some(@["<id1@host>"])` | `"messageId"` | JArray of 1 JString |
| 65b | `inReplyTo = some(@["<id0@host>"])` | `"inReplyTo"` | JArray of 1 JString |
| 65c | `references = some(@["<id-1@host>"])` | `"references"` | JArray of 1 JString |
| 66 | `extraHeaders` entry with name `"X-Custom"` and `rawMulti(@["v"])` | property key `"header:X-Custom:asRaw"`; JString `"v"` (single-instance) |
| 66a | `extraHeaders` entry with name `"X-Custom"` and `rawMulti(@["v1", "v2"])` | property key `"header:X-Custom:asRaw:all"`; JArray of 2 JStrings (multi-instance `:all` suffix) |

#### 6.2.3. Body serialisation (scenarios 67–73a)

| # | Scenario | Expected |
|---|----------|----------|
| 67 | `ebkStructured` with a single leaf `bodyStructure` | `"bodyStructure"` present with `{"partId": ..., "type": ...}`; `textBody`, `htmlBody`, `attachments` keys ALL absent (pin all three via `assertJsonKeyAbsent`) |
| 68 | `ebkFlat` with `textBody = some(part)` only | `"textBody"`: 1-element JArray; `"htmlBody"` absent; `"attachments"` absent if empty |
| 69 | `ebkFlat` with both `textBody = some` AND `htmlBody = some` | Both keys present; `"attachments"` absent if empty |
| 70 | `ebkFlat` with non-empty `attachments` | `"attachments"` present with JArray; each element has either `partId` (inline) or `blobId` (blob-ref) per §6.2.4 |
| 72 | `bodyValues` harvest: single inline leaf with `partId = "1"` and `value = "hi"` | Top-level `"bodyValues": {"1": {"value": "hi"}}` |
| 72a | `bodyValues` harvest with TWO inline leaves sharing the same `PartId("1")` (two leaves, one key) | JSON `"bodyValues"` has exactly ONE entry at key `"1"` (last-wins Table semantics). **Documents the currently-unchecked data-loss surface**: the design does not presently include an `ebcDuplicatePartId` smart-ctor variant. Downstream callers constructing blueprints are responsible for PartId uniqueness. Flagged as a future-design question; see §7 row E30. Paired with the loud-failure guard in sc 72b. |
| 72b | Order-dependent byte-diff pin: construct blueprints B1 and B2, **equal under `emailBlueprintEq` (K-7)** except the two duplicate-PartId inline leaves are inserted in opposite order; emit `B1.toJson` and `B2.toJson` | **Byte output differs.** Converts 72a's silent-data-loss vector into a loud regression gate: every future refactor that alters harvest ordering MUST either (a) fix the data loss by introducing `ebcDuplicatePartId`, or (b) update this scenario deliberately. Assertion: `$B1.toJson != $B2.toJson`. |
| 73 | `bodyValues` with multiple inline leaves at varying depths | One entry per inline leaf; keys are stringified `PartId` values; values match the in-place `BlueprintBodyValue` payloads |
| 73a | `bodyValues` harvest over a depth-5 structured tree with inline leaves at depths 1, 3, and 5 | `bodyValues` object contains 3 entries, keyed by the three `partId`s; values match the in-place payloads; pinned by correspondence property 92 |

(Scenarios 71 and 74 — removed in the second audit; generalised by
property 90 (`toJson` key-omission on `Opt.none` / empty collections),
unit scenario 18 (flatBody empty ⇒ all four body keys absent), and
unit scenario 50 (`bodyValues` empty table on blob-ref-only body). No
unit/serde-level pin lost.)

#### 6.2.4. RFC §4.6 wire-format conformance (scenarios 75–84)

| # | Scenario | Expected |
|---|----------|----------|
| 75 | Construct a maximally-populated blueprint (mailboxIds + all convenience + extraHeaders + flat body with attachments); serialise; byte-scan the top-level JSON object's keys | No key starts with `"Content-"`. Pins the type-level elimination with a concrete assertion rather than a "structurally impossible" note |
| 76 | `BlueprintBodyPart` JSON output | No `"headers"` array (pre-parsed header seq); only discrete `"header:*"` keys (§3.6 / Part C §3.6 rule) |
| 77 | `ebkStructured` blueprint serialised | Top-level `"bodyStructure"` present AND none of `"textBody"`, `"htmlBody"`, `"attachments"` present — pinned by discriminant + test |
| 78 | Inline body-part JSON | Has `"partId"`; does NOT have `"blobId"`, `"charset"`, or `"size"` (Part C §3.6's toJson rule) |
| 79 | Blob-ref body-part JSON | Has `"blobId"`; does NOT have `"partId"`; may have `"charset"`, `"size"` |
| 81 | ASCII-lowercase normalisation of header-name table keys across serde | Every emitted `"header:..."` key's name component is all-lowercase, regardless of the input casing the caller used at construction time (idempotent via property 93) |
| 82 | Blueprint with `extraHeaders` entry using `hfAddresses` form and two values (`:all` semantics) | Property key is `"header:<name>:asAddresses:all"`; JArray has 2 elements; each element is a JArray of address objects |
| 83 | Blueprint with `extraHeaders` entry using `hfGroupedAddresses` form | Property key `"header:<name>:asGroupedAddresses"`; value is JArray of group objects each with `"name"` and `"addresses"` keys |
| 84 | Blueprint with `extraHeaders` entry using `hfUrls`, `hfMessageIds`, `hfDate` — one scenario per form | Each form's property-key suffix and JSON value shape matches the §3.6.1 mapping; pinned via `assertJsonHasHeaderKey` (§6.5.5 L-6) |

### 6.3. Property-Based (eighteen properties)

Property-based tests use the `mproperty.nim` infrastructure (fixed seed,
edge-biased generators, tiered trial counts). Each property names its
generator, trial count, the principle it defends, and the R-decision it
guards (Part D §12.12 three-column precedent).

Eighteen properties total: seven foundational (85–91, from R5-1), three
first-audit supplementary (92–94), three first-audit adversarial (95–97),
and five second-audit additions (98–102) closing gaps around hash-seed
non-determinism, bounded error rendering, JSON re-parsability, the
promised-but-missing depth-coupling invariant, and insertion-order
insensitivity of value equality.

#### 6.3.1. Foundational properties (seven from R5-1)

| # | Property | Generator(s) | Trials | Principle defended | R-decision |
|---|----------|-------------|--------|--------------------|-----------|
| 85 | **Totality of `parseEmailBlueprint`**: never raises on any input (openArray-and-Opt fuzz, malformed headers, oversized trees) | `genEmailBlueprintArgs` (J-10 composed with adversarial-biased sub-generators) | `DefaultTrials = 500` | Total functions; parse once at the boundary | R1-3 |
| 86 | **Totality of `toJson`**: never raises on any valid `EmailBlueprint` | `genEmailBlueprint` (J-10) | `DefaultTrials = 500` | Total functions | R1-1, R4-2, R4-3 |
| 87 | **Determinism**: same named-parameter tuple → byte-identical Result | `genEmailBlueprintArgs`; call twice, compare | `DefaultTrials = 500` | One source of truth per fact | R1-3 |
| 88 | **Error accumulation — count, uniqueness, and stable ordering**: M independent constraint violations produce exactly M entries in `EmailBlueprintErrors`, no duplicates, no extras, AND the seq ordering is stable across runs (sorted by constraint enum ordinal, then by variant payload) | `genBlueprintErrorTrigger` (J-11, bijection between variant and trial for trials 0–5) | `DefaultTrials = 500` | Errors are part of the API; name variants | R3-1 |
| 89 | **`toJson` shape invariants**: every top-level key belongs to the R4-1 convenience set or matches `header:*`; `bodyStructure` and flat-list fields are mutually exclusive; `bodyValues` keys are exactly the `partId`s at inline leaves | `genEmailBlueprint` | `DefaultTrials = 500` | Make the wrong thing hard; code reads like the spec | R3-3, R4-1 |
| 90 | **`toJson` key-omission**: `Opt.none` fields and empty collections never appear as keys | `genEmailBlueprint` with bias toward `Opt.none` and empty collections | `DefaultTrials = 500` | Make illegal states unrepresentable; one source of truth | R4-2, R4-3 |
| 91 | **`toJson` injectivity**: distinct blueprints (by value equality on the public accessor set, via `emailBlueprintEq` K-7) produce distinct JSON (by canonical form) | `genEmailBlueprint` × `genEmailBlueprintDelta` (adds one minimally-distinguishable field to a base blueprint) | `ThoroughTrials = 2000` | One source of truth per fact; DRY | all field serde decisions |

#### 6.3.2. Post-audit supplementary properties

These three properties fill gaps identified by the completeness audit
(T-1, T-2, T-3) that the foundational seven did not cover.

| # | Property | Generator(s) | Trials | Principle defended |
|---|----------|-------------|--------|--------------------|
| 92 | **`bodyValues` / tree correspondence**: `bp.bodyValues.pairs` equals the `(partId, value)` pairs from walking the tree and harvesting inline leaves — no extras, no missing entries | `genBlueprintBodyPart` (J-8) composed under `genEmailBlueprint` | `DefaultTrials = 500` | Denormalisation correctness (DTM E12) — the derived accessor IS the tree projected, not a cached copy |
| 93 | **Lowercase-normalisation idempotence** on header names (both types): for any valid input `s`, the three constructions `parseBlueprintEmailHeaderName(s)`, `parseBlueprintEmailHeaderName(s.toUpperAscii)`, `parseBlueprintEmailHeaderName(s.toLowerAscii)` produce pairwise-equal values and pairwise-equal hashes. The identical claim holds under `parseBlueprintBodyHeaderName`. Also: `parse*HeaderName(parse*HeaderName(s).string)` = `parse*HeaderName(s)` for both types (pure fixed-point). Expanded in the second audit to cover **both** Name types, subsuming unit sc 37b. | `genValidBlueprintHeaderName` (J-1) and `genValidBlueprintBodyHeaderName` (J-3) | `DefaultTrials = 500` each (2 × 500 trials) | Equality / hash contract; normalisation is a pure fixed-point |
| 94 | **Error-ordering determinism**: for any blueprint producing M violations, two independent `parseEmailBlueprint` calls return `EmailBlueprintErrors` that are element-wise identical (not just set-equal) | `genBlueprintErrorTrigger` | `DefaultTrials = 500` | Total functions; no hidden non-determinism (e.g., Table iteration order) |

#### 6.3.3. Adversarial properties (post-audit)

These three properties complement the scenario-driven adversarial tests
in §6.4 by covering the same attack classes under randomised input.

| # | Property | Generator(s) | Trials | Attack class defended against |
|---|----------|-------------|--------|-------------------------------|
| 95 | **Totality under adversarial generator**: `parseEmailBlueprint` never raises on inputs drawn from edge-biased adversarial generators — CRLF / NUL / BOM / high-byte EmailAddress names, `receivedAt` at UTCDate boundary, `extraHeaders` with 0/1/1k/10k entries, bodyStructure depth in {0, 128, 129, 256} | `genAdversarialBlueprintArgs` (composes `genMaliciousString`, `genArbitraryByte`, boundary-biased seq lengths) | `ThoroughTrials = 2000` | Fuzz-harness totality; FFI panic risk |
| 96 | **`message` purity and idempotence** under adversarial `EmailBlueprintError` payloads: for each of the 6 variants with malicious payload, two calls return byte-identical strings and no side effect observed | `genEmailBlueprintError` (J-13) biased to adversarial payloads (NUL, CRLF, 100 KB strings, high-byte sequences) | `DefaultTrials = 500` | Logging-path non-determinism; FFI `{.raises: [].}` contract |
| 97 | **Harvest correctness under pathological trees**: for every tree structure producible by `genBlueprintBodyPart(rng, depth)`, the emitted `"bodyValues"` JSON object has exactly one entry per `bpsInline` leaf (no duplicates, no extras, no missing) — complements scenario 72a's documented gap at the property level | `genBlueprintBodyPart` composed with `genEmailBlueprintBody` | `DefaultTrials = 500` | Silent data loss through Table key collision during harvest |

#### 6.3.4. Second-audit properties (hash-seed, bounded rendering, JSON re-parsability, depth coupling, insertion-order insensitivity)

Five further adversarial / invariant properties added after the
second-audit cycle. Alphabetic suffixes (97a–97e) keep the numbering
inside §6.3 without colliding with §6.4's scenario space (which starts
at 98).

| # | Property | Generator(s) | Trials | Attack class / principle defended |
|---|----------|-------------|--------|-------------------------------|
| 97a | **Table iteration-order determinism across processes**: for any blueprint, `toJson` output is byte-identical when emitted from two fresh OS processes using the same input but **different** `std/tables` hash seeds (set via `NIM_HASH_SEED=0` vs default at spawn time). Tests that emitted `"header:*"` key ordering is a pure function of blueprint logical content, not ambient hash-seed state | `genEmailBlueprint` (J-10); testament matrix spawns two executables | `ThoroughTrials = 2000` | Hash-seed-driven non-determinism exfiltration into FFI consumers that do byte-level output comparison; R4-1 / R4-2 |
| 97b | **`message()` bounded output length** under adversarial `EmailBlueprintError` payloads: `message(e).len ≤ 8 KiB` for every variant and every payload drawn from `genEmailBlueprintError` biased toward 64 KB adversarial strings. Complements property 96 (determinism) with a size bound — prevents log-injection / memory-exhaustion via unbounded rendering through the FFI `{.raises: [].}` contract | `genEmailBlueprintError` (J-13) biased adversarial | `DefaultTrials = 500` | Logging-path resource exhaustion; C-consumer buffer overflow surface |
| 97c | **`toJson` + `parseJson` lossless re-parsability**: for every `EmailBlueprint` producible by `genEmailBlueprint`, `parseJson($bp.toJson)` succeeds and the resulting JSON tree is value-equal to the direct `bp.toJson` tree. Defends the commitment that `toJson` output is itself well-formed JSON under every adversarial input that survives `parseEmailBlueprint` — even though no `fromJson` exists (R1-3) | `genEmailBlueprint` (J-10) | `ThoroughTrials = 2000` | JSON-injection via convenience-field byte leakage bypassing `std/json` escape logic; defends R1-3 from a malformed-JSON escape hatch |
| 97d | **`BodyPartPath` depth coupling** (promised in sc 37r, previously unscheduled): for every blueprint-and-violation pair drawn from `genBlueprintBodyPart`, the `where.path.seq.len ≤ MaxBodyPartDepth` (128) holds. Every element ≥ 0; first element strictly less than the root's child count | `genBlueprintBodyPart` composed with a constraint-violation-injection shim | `DefaultTrials = 500` | Off-by-one in path encoding producing out-of-range integer indices reachable by FFI downstream; totality |
| 97e | **Insertion-order insensitivity of `emailBlueprintEq`**: for every pair `(bp, permuted(bp))` where `permuted` reconstructs the blueprint with identical logical content but shuffled `extraHeaders` insertion order, `emailBlueprintEq(bp, permuted(bp))` holds. Complements property 97a at the *value-equality* level — caller caching / idempotence-key systems depend on this | `genEmailBlueprint` + `genBlueprintInsertionPermutation` (J-16) | `DefaultTrials = 500` | Non-determinism in equality testing; one source of truth per fact |

#### 6.3.5. Edge-bias discipline

Every generator lists its "does NOT generate" negative cases in its
docstring (per `mproperty.nim` lines 1–14). Early trials (trial index
< 6) cover boundary states before random sampling begins:

- **Minimal blueprint**: mailboxIds with exactly one Id; everything else `Opt.none` / empty.
- **Maximal blueprint**: all 11 convenience fields `Opt.some`; extraHeaders with one entry per form (6 variants); ebkFlat with both textBody and htmlBody and two attachments.
- **Boundary body structures**: depth-0 leaf, depth-128 boundary, depth-129 over-limit rejection.
- **Boundary cardinalities**: mailboxIds with exactly one Id; extraHeaders.len ∈ {0, 1, 10000}; NonEmptySeq.len ∈ {1, 2}.
- **Constraint-violation coverage**: one trial per `EmailBlueprintConstraint` variant.

#### 6.3.6. Explicitly not included

- **Round-trip via synthetic `fromJson`.** No `fromJson` exists for
  `EmailBlueprint` (R1-3 commitment); round-trip is not a defensible
  property at this scope.
- **Server integration.** Moved to Part F's integration tier. Part E's
  property suite covers exactly the type-system and serde surface Part E
  owns.

### 6.4. Adversarial

Byte-level, structural, resource-exhaustion, and FFI-panic-surface edge
cases. Numbered 98 onward to follow §6.3's tenth property (97) without
collision. Follows the conventions of `tests/serde/tserde_adversarial.nim`
and `tests/stress/tadversarial.nim`.

#### 6.4.1. Smart-constructor byte-level boundary

| # | Scenario | Expected |
|---|----------|----------|
| 98 | `parseBlueprintBodyHeaderName("Content-Transfer-Encoding\x00")` — NUL byte in name (no wire prefix under E28) | `err`; NUL rejected by the character-validation rule (33–126) BEFORE the exact-name match can run. Assert the `ValidationError.message` substring identifies the character-check predicate, not the exact-name predicate, to pin the rule order |
| 98a | Symmetric NUL-position variants: `parseBlueprintBodyHeaderName("\x00Content-Transfer-Encoding")`, `"Content-\x00Transfer-Encoding"`, `"X-Custom\x00"` | All three `err` — proves the NUL check is name-agnostic (fires regardless of position) |
| 98b | `parseBlueprintBodyHeaderName("Content-Transfer-Encoding" & "\xC0\xBA")` — overlong UTF-8 encoding of colon appended | `err` — the 0xC0, 0xBA bytes are non-ASCII and fail printable-ASCII validation |
| 98c | `parseBlueprintEmailHeaderName("X-Ĭ")` — Turkish dotless I (locale-sensitive case mapping in `std/unicode.toLower`; `std/strutils.toLowerAscii` is locale-independent) | `err` — the multi-byte UTF-8 bytes fail printable-ASCII *before* any lowercase runs; proves the implementation uses `toLowerAscii` (byte-level), not `unicode.toLower` (locale-dependent). **Tightened in the second audit**: the same test also pins `doAssert "\xC4\xAC".toLowerAscii == "\xC4\xAC"` — documents the identity of `toLowerAscii` on every non-ASCII byte so a reader can see at a glance that the implementation is safe under any locale |
| 98d | NUL-position mirror table for `parseBlueprintEmailHeaderName`: `"Content-Type\x00"`, `"\x00Content-Type"`, `"x-cus\x00tom"`, `"x-custom\x7F"` (DEL) | All four `err`; assert each `ValidationError.message` names the character-check predicate (not the `content-*` prefix predicate) — pins that NUL/DEL rejection precedes prefix checking. Prevents an adversary from inferring whether a given name is forbidden by prefix (timing / message side channel). Symmetric counterpart to sc 98a |
| 98e | Turkish-locale invariance: spawn the test harness with `LC_CTYPE=tr_TR.UTF-8` via the `withLocale` helper (§6.5.2 I-18); run both header-name parsers over a table of ASCII inputs (`"CONTENT-TYPE"`, `"X-Custom"`, `"content-transfer-encoding"`, `"Content-Transfer-Encoding"`) and over the Turkish capital-I-with-dot `"X-İ"` (U+0130, bytes 0xC4 0xB0) | Under `tr_TR`: ASCII inputs produce byte-identical Result/`ValidationError.message` compared to the default-locale run (pinned via `assertEq` on the serialised Result); `"X-İ"` rejects on the byte-check rule (non-ASCII bytes 0xC4 0xB0). Drives a regression gate if the implementation ever imports `std/unicode.toLower` |
| 98f | Homoglyph prefix bypass: `parseBlueprintEmailHeaderName` applied to `"FROM\u200B"` (zero-width space, high bytes 0xE2 0x80 0x8B), `"\u0192rom"` (LATIN SMALL LETTER F WITH HOOK), `"\xC4\xA8rom"` (I-with-tilde start byte sequence) | All `err` — the printable-ASCII check (33–126) fires before the `content-*` prefix check and before any normalisation. Pins that no homoglyph sequence can reach the collision path that would trigger `ebcEmailTopLevelHeaderDuplicate` through a name that looks like `"from"` |

#### 6.4.2. Structural and resource boundaries

| # | Scenario | Expected |
|---|----------|----------|
| 99 | `parseEmailBlueprint` with a bodyStructure 129 levels deep | `err` from `BlueprintBodyPart` depth limit (Part C §3.6 `MaxBodyPartDepth`) — propagates out |
| 99a | `parseEmailBlueprint` with a bodyStructure at depth EXACTLY 128 | `ok` — boundary success |
| 99b | `parseEmailBlueprint` with 10,000 sibling parts at a single level | `ok`; documents memory implication; pinned memory budget: no panic / no OOM on a 512 MB test worker |
| 99c | Cross-product depth × breadth: depth 8, breadth 1000 at every level | **`ok`** (single outcome — no "or err" branch: a test that can succeed under two outcomes cannot fail). Assert peak allocation `≤ 256 MiB` measured via `getOccupiedMem()` before and after `parseEmailBlueprint`. If this bound is ever exceeded, the test fails loud and drives an explicit design decision about introducing a resource-limit variant. Converts the first-audit "documents a gap" note into a loud regression gate |
| 99d | `parseEmailBlueprint` with `extraHeaders` containing 10,000 `BlueprintEmailHeaderName` values whose `std/hashes.hash(string)` collide — collision strings sourced from `adversarialHashCollisionNames(10_000)` (§6.5.2 I-19), which either (a) produces true collisions against Nim's current Farm-Hash-based implementation, or (b) falls back to near-collisions that stress bucket chaining. Time two runs: run A is 10,000 distinct non-colliding names; run B is the colliding set | **`ok`**; `table.len == 10_000`; `assertBoundedRatio(timeRunB, timeRunA, maxRatio = 4.0)` via L-8 — asserts no Ω(n²) HashDoS cliff. Unconditional assertion (no "if seeded" branch); if the bound is exceeded, the test fails and drives Part F mitigation work. Replaces the first-audit conditional formulation |
| 99f | `BodyPartPath` numeric-overflow surface: construct `BodyPartPath(@[-1])`, `BodyPartPath(@[int.high])`, `BodyPartPath(@[0, int.low, 1])` via the distinct cast (bypassing any future `parseBodyPartPath`); pair each with an `ebcBodyPartHeaderDuplicate` carrying that path; call `message(e)` | `message(e).len < 4 KiB` on every input; no panic; no `RangeDefect`. Pins the claim that `message` is total and bounded under adversarial path content, regardless of the integer content inside the distinct seq |
| 100 | `parseEmailBlueprint` with an EmailAddress `name` containing CRLF: `Opt.some("Alice\r\nBcc: attacker@evil")` (header injection attempt) | `ok` — `EmailAddress` (Part A) has no CRLF restriction on `name`. **Tightened in the second audit**: assert `"\\r\\n"` (JSON-escaped CRLF) appears in `$bp.toJson` exactly at the expected position, and the literal bytes `0x0D 0x0A` do NOT appear in the emitted string. Pins that `std/json` escapes CRLF — if this ever regresses, the test fails and a real RFC 5322 header-injection path has opened. **Documents FFI downstream responsibility** for the separate RFC 5322 rendering stage |
| 100a | `parseEmailBlueprint` with an EmailAddress `name` of 100 KB containing interleaved NUL, CRLF, BOM bytes | `ok`; `toJson` preserves every byte. **Tightened in the second audit**: use L-9 `assertJsonStringEquals` to verify the exact escaped-byte sequence appears in the emitted string; assert the literal raw bytes do NOT appear in `$bp.toJson` (all escaped by `std/json`). Documents FFI sanitisation surface |
| 100d | `parseEmailBlueprint` with `messageId = some(@["", "<valid@id>"])` — mixed empty-string and valid message-id entries (includes the empty-only case formerly in sc 100c; second audit merged these) | `ok`; all bytes preserved; 2-element JArray with first element `""` and second element `"<valid@id>"`; server may reject at submission, but Part E does not |
| 100e | BOM-and-NUL MessageId round-trip: `messageId = some(@["<id1@example>\r\nEvil-Header: x", "\xEF\xBB\xBF<bom@h>", "\x00@host>"])` | `ok`; `toJson` emits a 3-element JArray; L-9 `assertJsonStringEquals` verifies every adversarial byte (CRLF, BOM, NUL) is escaped per `std/json` rules; the raw `0x00` / `0x0D` / `0x0A` bytes do NOT appear in `$bp.toJson`. Documents FFI downstream responsibility *by name* (not just "preserves bytes"): Layer 5 consumers rendering the `Message-Id:` header line must re-escape against RFC 5322 ftext / folding rules |

(Scenarios 100b and 100c — removed in the second audit. 100b (control
characters in subject) is subsumed by property 95's adversarial
generator over every convenience string field. 100c (empty
message-id singleton) is merged into 100d, which now covers the mixed
"empty + valid" case. Scenario 99e — originally proposed as a
separate bounded-ratio assertion — has been folded into 99d, which
is now the one concrete assertion rather than a pair of
overlapping rows.)

#### 6.4.3. Error-accumulation stress

| # | Scenario | Expected |
|---|----------|----------|
| 101 | Blueprint triggering all six `EmailBlueprintConstraint` variants simultaneously | `err` with exactly 6 entries in `EmailBlueprintErrors`, one per variant; set-equal under `emailBlueprintErrorsSetEq` (K-2); the seq order is stable (pin via property 94 at the property level — which uses the ordered K-9 variant) |
| 101a | Blueprint triggering `ebcBodyPartHeaderDuplicate` 10,000 times — multipart root with 10,000 leaf children, each with an independent Content-Type / extraHeaders conflict | `err` with `EmailBlueprintErrors.len == 10_000`; no panic; no OOM. **Tightened in the second audit**: additionally assert the underlying seq's capacity is `≤ 2 × 10_000` (accessible via the distinct-seq cast `seq[EmailBlueprintError](errors).capacity`). Pins the amortised-growth claim with a concrete upper bound — a regression to `O(n²)` growth through per-error reallocation would fail loud |
| 101b | Blueprint triggering `ebcEmailTopLevelHeaderDuplicate` 10,000 times — `extraHeaders` with 10,000 entries each colliding with a convenience field (synthetic: one convenience field, 10,000 extraHeaders all named `"from"` — except intra-Table dedup collapses these to 1 entry per 48e; so actually 10,000 DISTINCT colliding convenience-field names) | Pin current behaviour: since Email has 11 convenience fields, max `ebcEmailTopLevelHeaderDuplicate` accumulation in one invocation is 11. Documents the realistic ceiling |
| 101c | Blueprint triggering `ebcAllowedFormRejected` 10,000 times: 10,000 `extraHeaders` entries with distinct names (`"x-a0"`..`"x-a9999"`, all valid under `parseBlueprintEmailHeaderName`) paired with a `BlueprintHeaderMultiValue` whose form is not in `AllowedHeaderForms` for that name | `err`; `EmailBlueprintErrors.len == 10_000`; peak RSS bounded (reuse 101a's budget); every entry carries a distinct `rejectedName` (no aliasing across errors); the underlying seq's capacity `≤ 2 × 10_000` (mirrors 101a's amortised-growth guarantee). Closes the per-variant accumulation-cap gap left by 101a (body parts) and 101b (top-level duplicates ceiling at 11) |

#### 6.4.4. FFI panic-surface probes (post-audit additions)

These scenarios defend the L5 FFI rule that all exports be `{.raises: [].}`
and that no L1/L2 code path can raise `FieldDefect` — because
`--panics:on` turns `FieldDefect` into a fatal `rawQuit(1)` with no
unwinding (see `.claude/rules/nim-ffi-boundary.md`).

| # | Scenario | Expected |
|---|----------|----------|
| 102 | **Compile-time macro test** (second audit — replaces the first-audit grep-based formulation which was a smoke-check, not a contract): a Nim macro walks the AST of `email_blueprint.nim` and `serde_email_blueprint.nim` and, for every case-object field access (`.bodyStructure`, `.textBody`, `.htmlBody`, `.attachments`, `.partId`, `.blobId`, `.path`, `.rawValues`, `.textValues`, …), verifies that access sits inside a `case` branch on the correct discriminant. The macro runs at compile time, so a violation is a compile error, not a runtime log line. Grep was false-positive-prone (substring matches in helper names). The compile-time approach makes interior `FieldDefect` reachability a non-compilation — the strongest form of the R5-2 compile-boundary contract. Lives in `tests/compliance/tffi_panic_surface.nim` (macro implementation may delegate to a helper module importing `std/macros`). Alternative deployment if the macro proves too ambitious: move to a `just` CI recipe that parses the sources with the Nim frontend and produces a structured report — MUST NOT be a grep |
| 102a | Concurrent `EmailBlueprint` construction and serialisation from two threads, each building 10,000 DISTINCT blueprints with partially overlapping identifiers; each thread reads the JSON emitted by the other via a shared channel | Both threads complete without data race, no std/tables rehash corruption, no `JsonNode` ref aliasing. Replaces pre-audit scenario 100's "disjoint inputs" tautology |
| 102b | Value-type non-aliasing: construct `NonEmptyMailboxIdSet` from `@[id1]`, copy; mutate the local `id1` variable (if its storage were mutable — verify `Id` is `distinct string` so it is not); observe the set's stored Id unchanged | Pass. Documents that `Id` is a value type and `NonEmptyMailboxIdSet`'s storage does not alias caller state. Replaces pre-audit scenario 99's duplicate-of-45 content. **Merged with the second-audit aliasing probe**: additionally, after `let ne = parseNonEmptySeq(@["v"]).get(); let raw = seq[string](ne); raw.setLen(0)` assert `ne.len == 1` — proves distinct-seq unwrapping does not alias the stored payload. (Second audit merges the separate `tblueprint_value_aliasing.nim` file into this scenario — §6.5.1 no longer lists that file.) |
| 102c | **Iteration-order determinism across processes**: build a blueprint `B1` whose `extraHeaders` is inserted in order `(A, B, C)`; in a FRESH OS process (spawned via testament magic `matrix: ["-d:release", "-d:danger"]`), build `B2` whose `extraHeaders` has the identical final set inserted `(C, B, A)`. Emit `$B1.toJson` in process 1 and `$B2.toJson` in process 2; compare via shared file | **Byte-identical.** If this fails, hash-seed or insertion-order state has leaked into the wire output — a real non-determinism foothold for FFI consumers that do byte-level equality. Complements property 97a at the scenario level with an explicit pair-of-processes pin |
| 102d | **ARC copy semantics on `NonEmptySeq[T]`**: construct `let ne = parseNonEmptySeq(@["v"]).get()`; unwrap via the distinct cast `let raw = seq[string](ne)`; mutate `raw` (`.setLen(0)`, `.add("evil")`); observe `ne` | `ne.len == 1`; `ne[0] == "v"`; proves the distinct cast produces a value-typed copy under ARC and the invariant non-empty state cannot be broken through unwrapping. Complements 48g (`assertNotCompiles` on bare-seq assignment into the field) with a runtime observation on the copy path |

#### 6.4.5. Serde adversarial

| # | Scenario | Expected |
|---|----------|----------|
| 103 | `toJson` on a blueprint with bodyStructure at depth 128 (boundary), called twice | `ok` both times; outputs byte-identical; no stack overflow (property 95 generalises this) |
| 103a | `toJson` on a depth-5 spine with 128 inline leaves distributed along the spine | Output contains 128 entries in `bodyValues`; harvest recursion is bounded; no stack exhaustion |
| 104 | `toJson` on a blueprint with every `Opt` field `some` and every collection non-empty (`makeFullEmailBlueprint` with all variants exercised) | Full-featured JSON; all 11+ convenience keys emitted; `extraHeaders` serialised with correct `:all` suffix per R4-1 |
| 104a | Serde single-field injectivity: blueprints A and B identical except B has one additional `extraHeaders` entry — assert `A.toJson != B.toJson` byte-wise | Always unequal (pinned as property 91 under `ThoroughTrials`) |
| 104b | Intra-Table dedup wire safety: Table with 2 inserts for names that normalise-equal but byte-differ; `toJson` must emit exactly ONE entry keyed by the canonical lowercase form; the earlier value MUST NOT leak into the output | Exactly one `"header:..."` entry; value matches the LAST insert |
| 104c | JSON-injection via convenience-field byte leakage: `subject = some("\"],\"mailboxIds\":{\"evil\":true},\"zzz\":[\"")` — adversarial quote / bracket / comma sequence in a convenience field that is emitted as a plain JSON string | `ok`; `toJson` emits exactly one `"subject"` key; `parseJson($bp.toJson)` (round-trip through `std/json`) produces a JSON object whose `"mailboxIds"` key is the legitimate one (not the injected `{"evil":true}`). Pins that `std/json` escape logic is not bypassable through crafted payload bytes. Complements property 97c at the scenario level |

### 6.5. Test Infrastructure (new subsection)

Part D §12.14 established the precedent that a Part enumerating new
types must explicitly specify the shared fixtures, generators, equality
helpers, assertion templates, and test-file placements that the test
scenarios depend on. Part E did not have this subsection in its
pre-audit layout; §6.5 closes that gap.

The 7-step protocol at the head of `tests/mfixtures.nim` mandates, for
every new type: (1) `parse*` smart constructor, (2) `make*` factory,
(3) `toJson`/`fromJson`, (4) unit tests, (5) serde tests, (6) property
tests, (7) `gen*` generator. Part E introduces ~14 types; the matrix
in §6.5.6 confirms each step is specified below.

#### 6.5.1. Test-file assignment

Second audit: collapsed two standalone sub-40-line files into sibling
files per the project's cohesion convention (no single-scenario or
two-scenario files); split `tadversarial.nim` (already 1404 lines) to
avoid pushing it past the nimalyzer `complexity` threshold;
disambiguated the 102 mechanism (compile-time macro, not grep — see
scenario 102).

| File | Scenarios | Line budget | Rationale |
|------|-----------|-------------|-----------|
| `tests/unit/mail/temail_blueprint.nim` | 1, 1a, 3, 5–7l, 9, 11a, 11b, 12, 17, 18, 21, 49, 50, 50a, 50b, 102b (aliasing), 102d | ~420 | `EmailBlueprint` smart-ctor + accessors + `BlueprintBodyValue` single-field serde + value-type-non-aliasing. Parallels Part D `temail.nim`. Second audit merges the ex-`tblueprint_body_value.nim` (sc 21) and ex-`tblueprint_value_aliasing.nim` (sc 102b / 102d) into this file — neither was large enough to justify a standalone file. |
| `tests/unit/mail/tmailbox.nim` (extend) | 24–27, 27a | +~80 | `NonEmptyMailboxIdSet` lives in `mailbox.nim` (§4.2.3); co-locate tests with `MailboxIdSet`. |
| `tests/unit/mail/theaders_blueprint.nim` (new, split from extension) | 28a, 29, 29a, 30, 31, 32, 32a, 32c, 33, 35, 35c, 35d, 36, 37b, 37c–37h | ~260 | `BlueprintEmailHeaderName`, `BlueprintBodyHeaderName`, `BlueprintHeaderMultiValue` — the pre-existing `theaders.nim` is 274 lines; extending it by 250 would push it past nimalyzer complexity thresholds. Second audit splits into a sibling file. |
| `tests/unit/tprimitives.nim` (extend) | 37i, 37j, 37k, 37l | +~45 | `NonEmptySeq[T]` lives in `primitives.nim` (§4.6). |
| `tests/unit/mail/tblueprint_error_triad.nim` | 37p, 37q, 37r | ~60 | `BodyPartPath`, `BodyPartLocation`, `EmailBlueprintError.message` renderer. 11a/11b live in `temail_blueprint.nim` (accessor-adjacent). |
| `tests/unit/mail/tblueprint_compile_time.nim` | 38, 40, 41, 42, 45, 46, 48, 48a–48l | ~190 | `assertNotCompiles` scenarios; MUST live outside `email_blueprint.nim` to verify module-scope privacy (scenario 45 in particular). Includes 48j (public export surface) and 48k (`ebcNoBodyContent` absence). |
| `tests/serde/mail/tserde_email_blueprint.nim` | 51–73a (top-level + convenience + body) | ~450 | Mirrors `tserde_email.nim`. |
| `tests/serde/mail/tserde_email_blueprint_wire.nim` (new) | 75–84 (RFC §4.6 conformance) | ~150 | Split off from `tserde_email_blueprint.nim` at §6.2.4 boundary to keep individual files under 450 lines — avoids the megatest dispatch issues seen around `tserde_email.nim`. |
| `tests/serde/mail/tserde_email_blueprint_adversarial.nim` | 98–100e, 104–104c | ~220 | Adversarial serde; mirrors `tserde_email_adversarial.nim`. |
| `tests/property/tprop_mail_e.nim` | 85–97, 97a–97e | ~430 | Properties; mirrors `tprop_mail_c.nim` / `tprop_mail_d.nim`. Includes the five second-audit properties 97a–97e. |
| `tests/stress/tadversarial_blueprint.nim` (new, split from extension) | 99–99f, 101, 101a, 101b, 101c, 102a, 102c | ~220 | Depth/breadth/HashDoS/concurrency/cross-process-determinism. Pre-existing `tadversarial.nim` (1404 lines) would cross the complexity budget with another +150 added; second audit splits into a Part-E-specific sibling. |
| `tests/compliance/tffi_panic_surface.nim` (new) | 102 | ~100 | **Compile-time macro** contract (not a grep): a Nim macro walking `email_blueprint.nim` / `serde_email_blueprint.nim` ASTs at compile time, rejecting any case-object field access outside a matching `case` branch. If the macro approach proves too ambitious in implementation, deploy instead as a `just` CI recipe running the Nim frontend over the sources and emitting a structured report — but NOT a grep. |

#### 6.5.2. Factory fixtures (`mfixtures.nim` additions)

Placed after the existing "Mail Part D factories" section (line 376 of
`mfixtures.nim`), under a new "Mail Part E factories" heading.

| Factory | Type | Default | Scenarios consuming |
|---------|------|---------|---------------------|
| **I-1** `makeBlueprintEmailHeaderName(s = "x-custom")` | `BlueprintEmailHeaderName` | `x-custom` | 7, 7a, 7b, 7c, 11a, 54, 66, 101, 101b, 101c |
| **I-2** `makeBlueprintBodyHeaderName(s = "x-body-custom")` | `BlueprintBodyHeaderName` | `x-body-custom` | 7e, 7f, 7g, 7h, 33, 37b, 42 |
| **I-3** `makeBhmvRaw(values)`, `makeBhmvText(values)`, `makeBhmvRawSingle(value)` (plus per-form siblings) | `BlueprintHeaderMultiValue` | 1-element `["v1"]` | 7a–7d, 11a, 37c–37h, 48d, 48e, 48g, 54, 66, 66a, 82, 83, 84, 101, 101c |
| **I-4** `makeNonEmptyMailboxIdSet(ids = @[makeId("mbx1"), makeId("mbx2")])` | `NonEmptyMailboxIdSet` | **2-element** (second-audit change — 2-element default exercises HashSet dedup semantics on every scenario that uses the factory; a 1-element default was a footgun for sc 26 and for any test that assumed `len == 2`) | 1, 3, 5–7l, 9, 12, 17, 18, 24, 26, 51, 52, 85–97e |
| **I-5** `makeNonEmptySeq[T](s: seq[T])` | `NonEmptySeq[T]` | caller-supplied | 37c–37h, 37i–37l, 48f, 48g |
| **I-6** `makeBlueprintBodyValue(value = "hi")` | `BlueprintBodyValue` | `"hi"` | 21, 49, 50, 72, 73 |
| **I-7** `makeBlueprintBodyPartInline(partId, contentType, value, extraHeaders)` | `BlueprintBodyPart` inline leaf | partId="1", contentType="text/plain", value="hi", empty extraHeaders | 7e–7h, 49, 50, 67–73a, 99, 99a |
| **I-8** `makeBlueprintBodyPartBlobRef(blobId, contentType, extraHeaders)` | `BlueprintBodyPart` blob-ref | blobId="blob1", contentType="image/png" | 50, 70, 79, 99b, 99c |
| **I-9** `makeBlueprintBodyPartMultipart(subParts, contentType, extraHeaders)` | `BlueprintBodyPart` multipart | empty children, contentType="multipart/mixed" | 3, 7a, 7d, 7g, 7k, 49, 67, 99–99c |
| **I-10** `makeEmailBlueprint()` + `makeFullEmailBlueprint()` | `EmailBlueprint` | minimal (mailboxIds only) AND full (all 11 convenience + all 6 forms + flat body with 2 attachments + 2 inline bodyValues) | 1, 12, 51, 52, 53, 54, 55–59, 75, 85–91, 97a–97e, 104 |
| **I-11** `makeFlatBody(textBody, htmlBody, attachments)` / `makeStructuredBody(root)` | `EmailBlueprintBody` | flat empty / structured root | 1, 3, 5, 6, 17, 18, 67–70. **Second-audit clarification**: these are **thin wrappers** around the module-level smart-ctor helpers `flatBody()` / `structuredBody()` (§3.2), not hand-rolled case-object construction. The wrapper exists only to supply test-friendly defaults; it must not duplicate or bypass the module helper. |
| **I-12** `makeBlueprintWithDuplicateAt(dupName, dupKind, loc)` | `Result[EmailBlueprint, EmailBlueprintErrors]` | `"from"`, `ebcEmailTopLevelHeaderDuplicate`, no location | 7, 7a, 7b, 7e, 7f, 7g, 7h, 7i, 7j, 7k, 11a, 101 — single factory collapses the duplicate-trigger scenarios into one-liners |
| **I-13** `makeBodyPartLocation` (inline/blobRef/multipart variants) | `BodyPartLocation` | per-variant defaults | 7e–7h, 37l, 37p, 101 |
| **I-14** `makeEmailBlueprintJson()` | `JsonNode` (derived from `makeEmailBlueprint().toJson()`) | — | 51, 54, 75, 76, 98, 104 — matches Part D's derived-fixture precedent |
| **I-15** `makeBlueprintEmailHeaderMap(entries: openArray[(string, BlueprintHeaderMultiValue)])` and `makeBlueprintBodyHeaderMap(entries)` | `Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]` / body-variant | empty Table | 7, 7a, 7b, 7e, 7f, 7g, 7h, 7i, 7j, 7k, 11a, 54, 66, 66a, 82, 83, 84, 101, 101a, 101b, 101c — 20+ consumers; second-audit addition closes the high-duplication gap where every scenario previously hand-built the Table inline. The helper calls `parseBlueprintEmailHeaderName(name).get()` per entry and asserts the result is `ok` before insertion. |
| **I-16** `makeBodyPartPath(s: seq[int] = @[])` | `BodyPartPath` | empty seq (root-multipart semantic per §3.4) | 7g, 37p, 37q, 37r, 99f — satisfies §6.5.6 row-11 step-2 requirement. Without this, `BodyPartPath` has no `make*` factory and the 7-step protocol matrix has a gap. |
| **I-17** `makeSpineBodyPart(depth: int, leafKind: BodyPartLocationKind = bplInline)` | `BlueprintBodyPart` | depth=3, leafKind=bplInline | 7g, 7k, 73a, 99, 99a — deterministic spine constructor for scenario-driven tests. Parallels the **randomised** `genDeepBodyStructure` / `genBlueprintBodyPart` (J-8) but with a fixed depth and a single leaf path. Fills the gap where scenarios needed a pinned-depth tree at the fixture level rather than a random one. |
| **I-18** `withLocale(locale: string, body: untyped)` | template (sets `LC_CTYPE` / `LC_ALL` via `putEnv` for the duration of `body`; restores previous on exit) | no default locale | 98e — the Turkish-locale harness for scenario 98e. Template form keeps line numbers pointing at the calling scenario on assertion failure. |
| **I-19** `adversarialHashCollisionNames(n: int): seq[string]` | pure function | — | 99d — produces `n` distinct strings whose `std/hashes.hash(string)` value collides under Nim's current Farm-Hash implementation (or, if the seed is randomised at runtime, fall back to near-collisions that share a low-order-bit bucket). Function-level; not a `make*` factory. |

#### 6.5.3. Generators (`mproperty.nim` additions)

Each generator's docstring lists the covered and explicitly-NOT-covered
inputs (the header-comment protocol at `mproperty.nim` lines 1–14).

| Generator | Type produced | Edge-bias (early trials) | Required for property |
|-----------|--------------|--------------------------|----------------------|
| **J-1** `genBlueprintEmailHeaderName(rng, trial)` | `BlueprintEmailHeaderName` | 0=`"a"` (min); 1=max-length printable-no-colon; 2–4=mixed case; 5=`"content"` (no hyphen, allowed) | 85, 89, 93 |
| **J-2** `genInvalidBlueprintEmailHeaderName(rng, trial)` | `string` | 0=`""`; 1=`"Content-Type"`; 2=`"header:...:asText"`; 3=`"X-Has Space"`; 4=NUL-containing; 5=`"content-"` | 85 (negative branch) |
| **J-3** `genBlueprintBodyHeaderName` / `genInvalidBlueprintBodyHeaderName` | analogous to J-1/J-2 | 0=`"Content-Type"` (ok on body); 1=`"Content-Disposition"`; 2=`"X-Custom"`; 3=`"Content-Transfer-Encoding-X"` (not exact, ok) | 85, 93 |
| **J-4** `genBlueprintHeaderMultiValue(rng, form, trial)` | `BlueprintHeaderMultiValue` | 0–3=len 1 per form; 4–6=len 2 per form (exercises `:all` suffix) | 85, 88, 89, 91 |
| **J-5** `genNonEmptyMailboxIdSet(rng, trial)` | `NonEmptyMailboxIdSet` | 0=`@[id1]`; 1=`@[id1,id2,id1]` (dedup to 2); trials 2..20 elements. **Header comment MUST state** (per `mproperty.nim` lines 1–14): "Covers non-empty sets from 1 to 20 distinct Ids with duplicate-collapse behaviour; Does NOT cover empty seqs (rejected by the smart constructor), invalid Ids, or sizes > 20 elements" | 85, 86, 87, 89 |
| **J-6** `genNonEmptySeq[T](rng, genElem, trial)` | `NonEmptySeq[T]` | 0=len 1; 1=len 2; higher=up to 10 | composed into J-4 |
| **J-7** `genBlueprintBodyValue(rng, trial)` | `BlueprintBodyValue` | 0=`""`; 1=`"\x00\x01"`; 2=64 KB; 3=`"Hello"` | 86 |
| **J-8** `genBlueprintBodyPart(rng, maxDepth)` | `BlueprintBodyPart` | depth-1 leaves first; recursion capped at `MaxBodyPartDepth = 128`. **Second-audit clarification**: reuses `genBodyPartSharedFields` (mproperty.nim:1454) for the shared MIME metadata (contentType, name, size, charset, disposition, cid, language, location) — diverges only at the `source` discriminant (`bpsInline` / `bpsBlobRef` / `bpsMultipart`). Not a from-scratch generator | 85, 86, 89, 91, 92, 97, 97d |
| **J-9** `genEmailBlueprintBody(rng, trial)` | `EmailBlueprintBody` | 0=`flatBody()` (empty); 1=`structuredBody(multipart)`; 2=`flatBody(textBody=some, htmlBody=some, 2 attachments)` | 85, 86, 89, 91 |
| **J-10** `genEmailBlueprint(rng, trial)` | `EmailBlueprint` | 0=`makeEmailBlueprint()`; 1=`makeFullEmailBlueprint()`; 2..N=random composition | 86, 87, 89, 90, 91, 95, 97a, 97c, 97e |
| **J-11** `genBlueprintErrorTrigger(rng, constraint)` | blueprint args + expected `EmailBlueprintConstraint` | bijection trials 0–5 = one variant each; trial 6 = all 6 simultaneously | 88, 94 |
| **J-12** `genBodyPartPath(rng, trial)` + `genBodyPartLocation(rng, trial)` | `BodyPartPath`, `BodyPartLocation` | 0=`@[]` (root multipart); 1=`@[0]`; 2=`@[0,1,2]` | 88, 96 (error payloads), 97d |
| **J-13** `genEmailBlueprintError(rng)` + `genEmailBlueprintErrors(rng)` | error variant values | uniform over 6 variants; payloads drawn explicitly from the existing adversarial-string toolkit: `genMaliciousString` (mproperty.nim:410) for name fields, `genArbitraryByte` for single-byte positions, and `genLongArbitraryString` for the 100 KB stress case used by property 97b. **MUST NOT reimplement these locally**; the existing generators are load-bearing across all adversarial-property tests | 88, 94, 96, 97b |
| **J-14** `genEmailBlueprintDelta(rng, base)` | `(base, base+one-field)` pair | one additional `extraHeaders` entry OR one Opt field flipped | 91 (single-field-difference injectivity) |
| **J-15** `genAdversarialBlueprintArgs(rng, trial)` | `EmailBlueprint` constructor args | composes malicious-byte strings, boundary-depth, boundary-cardinality | **Trials: ThoroughTrials (2000)** — matches property 95's trial count; second-audit column addition, previously unspecified. Consumed by: 95 |
| **J-16** `genBlueprintInsertionPermutation(rng, base)` | `(base, permuted(base))` pair with identical logical content but shuffled `extraHeaders` insertion order | trial 0: reverse order; trial 1–5: random permutations | 97e (insertion-order-insensitive equality) — second-audit addition |

#### 6.5.4. Equality helpers (`mfixtures.nim` additions)

Case objects and distinct-seq types lack reliable auto-`==`. Following
the `capEq`, `setErrorEq`, `headerValueEq`, `bodyPartEq`, `emailEq`,
`emailComparatorEq` precedents.

| Helper | Type compared | Precedent | Scenarios requiring it |
|--------|--------------|-----------|------------------------|
| **K-1** `emailBlueprintErrorEq(a, b): bool` | `EmailBlueprintError` (case object, 6 variants) | `setErrorEq` (mfixtures.nim:697) | 5, 6, 7, 7a, 7b, 7e–7l, 11a, 101 |
| **K-2** `emailBlueprintErrorsSetEq(a, b): bool` | `EmailBlueprintErrors` (distinct seq); **set/multiset equality** — ignores ordering. **Second-audit split** (formerly named `emailBlueprintErrorsEq`): the first-audit helper conflated set-style (needed by sc 101 which asserts variant coverage regardless of order) with ordered equality (needed by property 94 which asserts *ordering determinism*). No existing `m*.nim` helper did set-style seq equality, so K-2 introduces a new pattern — documented explicitly to prevent future misuse | `capsEq` (mfixtures.nim:630) for the per-element recursion into K-1; no existing precedent for the set/multiset comparison | 7i, 101, 101a, 101b, 101c |
| **K-3** `bodyPartLocationEq(a, b): bool` | `BodyPartLocation` (case object, 3 variants) | `headerValueEq` (mfixtures.nim:714) | 7e–7h, 37l, 37p, 101; plus K-1 recursion |
| **K-4** `emailBlueprintBodyEq(a, b): bool` | `EmailBlueprintBody` (case object, 2 variants); recursive into K-5 | `emailComparatorEq` (mfixtures.nim:847) | 3, 17, 18, 67–70; property 91 |
| **K-5** `blueprintBodyPartEq(a, b): bool` | `BlueprintBodyPart` (nested case on `isMultipart` × `source`); recursive; decomposes into `blueprintBodyPartCoreFieldsEq` + `blueprintBodyPartOptFieldsEq` sub-helpers | `bodyPartEq` (mfixtures.nim:745) | 3, 49, 67, 72, 73, 73a; property 91 |
| **K-6** `blueprintHeaderMultiValueEq(a, b): bool` | `BlueprintHeaderMultiValue` (case object, 7 forms) | `headerValueEq` | 37c–37h, 48d, 54, 66, 66a |
| **K-7** `emailBlueprintEq(a, b): bool` | `EmailBlueprint`; decomposes into metadata (manual — unwraps distinct HashSet types), convenience headers, body, extraHeaders. **Second-audit clarification**: REUSES the existing generic `convStringHeadersEq[T]` and `convAddressHeadersEq[T]` helpers in `mfixtures.nim:801`/`806` — they are generic on T and already work for every type with matching field names. The Blueprint variant differs from `Email` only in `receivedAt: Opt[UTCDate]` (vs. `UTCDate` required), which is handled in the metadata sub-helper. Must NOT reimplement parallel helpers | `emailEq` (mfixtures.nim:827) | 12, 72b, 87, 91, 97e |
| **K-8** `nonEmptyMailboxIdSetEq(a, b): bool` | `NonEmptyMailboxIdSet` (distinct `HashSet[Id]`) | Parallel to `mailboxIds` unwrap in `emailMetadataEq` (mfixtures.nim:822–824) | 24, 26, 27; property 87 |
| **K-9** `emailBlueprintErrorsOrderedEq(a, b): bool` | `EmailBlueprintErrors` (distinct seq); **ordered / element-wise equality** — explicitly compares seq ordering. Second-audit addition: resolves the first-audit contradiction between set-style and ordered needs (see K-2 note). Property 94 ("error-ordering determinism") specifically requires ordered comparison; using K-2's set-style helper here would mask ordering non-determinism | `capsEq` (mfixtures.nim:630) | property 94 only |

#### 6.5.5. Assertion templates (`massertions.nim` additions)

Following the `assertCapOkEq` (massertions.nim:122), `assertSetOkEq`
(line 127), and `assertJsonFieldEq` (line 114) precedents: templates
ensure line numbers point to the calling test on failure.

| Template | Purpose | Scenarios consuming |
|----------|---------|---------------------|
| **L-1** `assertBlueprintErr(expr, variant)` | `Result[_, EmailBlueprintErrors]` is `Err` AND contains at least one entry of `variant`. **Second-audit clarification**: internally delegates the "is err" check to the existing `assertErr` template (massertions.nim:26) for consistency; only the variant-search logic is new. Not a reinvention of `assertErrType` | 5, 6, 7, 7a–7h, 9, 35, 35d, 98 — 15 scenarios |
| **L-2** `assertBlueprintErrContains(expr, variant, field, expected)` | L-1 + field-level payload check (e.g., `dupName == "from"`) | 5, 6, 7, 7a–7l, 9, 99f — 15 scenarios |
| **L-3** `assertBlueprintErrCount(expr, n)` | exact-N accumulation | 7i, 101, 101a, 101b, 101c |
| **L-4** `assertBlueprintOkEq(expr, expected)` | variant of `assertCapOkEq` using `emailBlueprintEq` (K-7) | 1, 3, 12, 17, 18 |
| **L-5** `assertJsonKeyAbsent(node, key)` | symmetric complement to `assertJsonFieldEq`. Closes a 17-site code-duplication gap: existing tests inlined `doAssert j{"x"}.isNil` 17+ times across `tprop_mail_d.nim` and elsewhere | 51, 53, 57, 59, 67, 77, 79 — 7 scenarios |
| **L-6** `assertJsonHasHeaderKey(node, name, form, isAll = false)` / `assertJsonMissingHeaderKey` | verify `"header:Name:asForm[:all]"` wire keys. **Second-audit fix**: dropped sc 54 from this row — sc 54's "no top-level `header:*` keys" assertion is covered by L-5 (`assertJsonKeyAbsent`) with a prefix iteration, not by L-6 | 66, 66a, 76, 82, 83, 84, 98, 104b |
| **L-7** `assertBlueprintErrAny(expr, variants: set[EmailBlueprintConstraint])` | `Result[_, EmailBlueprintErrors]` is `Err` AND contains at least one entry per variant in the supplied set. Second-audit addition: covers the "multiple distinct variants, unknown exact count" case where L-1 (single variant) and L-3 (exact N) don't fit | 101 (all 6), 101a/101b/101c (tightened assertions) |
| **L-8** `assertBoundedRatio(slowExpr, fastExpr, maxRatio)` | Time two expressions and assert the slow/fast ratio is below a bound. Prevents Ω(n²) / HashDoS cliffs with a concrete numeric gate rather than a "documents the surface" note. Second-audit addition | 99d (HashDoS) |
| **L-9** `assertJsonStringEquals(node, key, exactBytes: string)` | Verify a `JsonNode`'s string-valued field is byte-identical to an expected payload — including escape-sequence matching. Fails-loud on any serializer-introduced folding or escape change. Second-audit addition; prevents a class of silent regressions where `std/json` behaviour drifts | 100, 100a, 100e, 104c |

#### 6.5.6. Seven-step fixture-protocol compliance

Every Part E type passes the 7-step protocol in `mfixtures.nim` header:

| # | Type | parse (1) | make (2) | toJson (3) | unit (4) | serde (5) | property (6) | gen (7) |
|---|------|-----------|----------|------------|----------|-----------|--------------|---------|
| 1 | `EmailBlueprint` | §3.3 | I-10 | §3.6 (no fromJson, R1-3) | §6.5.1 temail_blueprint.nim | tserde_email_blueprint.nim | 85–91, 95–97, 97a, 97c, 97e | J-10, J-15 |
| 2 | `EmailBlueprintBody` | case object (no parse) | I-11 (thin wrapper around module helpers `flatBody()` / `structuredBody()`) | §3.6 inside `EmailBlueprint.toJson` | 48b/48c | — | 86, 89 | J-9 |
| 3 | `BlueprintBodyValue` | plain object (no parse — auto `==` suffices; single `string` field has no Table/seq/case that would need a K-n helper) | I-6 | §4.1.3 | 21 | §6.2.3 | 86 | J-7 |
| 4 | `NonEmptyMailboxIdSet` | §4.2.2 | I-4 (2-element default) | used inside `EmailBlueprint.toJson` | 24–27a | — | 85, 86, 87 | J-5 |
| 5 | `BlueprintEmailHeaderName` | §4.3.2 | I-1 | §4.3.3 | 28a–32c | §6.2 indirect | 85, 93 | J-1, J-2 |
| 6 | `BlueprintBodyHeaderName` | §4.4.2 | I-2 | §4.4.3 | 33–37b | §6.2 indirect | 85, 93 | J-3 |
| 7 | `BlueprintHeaderMultiValue` | §4.5.2 helpers | I-3 | §4.5.3 (composed) | 37c–37h | 66, 66a, 82–84 | 86 | J-4 |
| 8 | `NonEmptySeq[T]` | §4.6.2 | I-5 | — | 37i–37l | — | 85 indirect | J-6 |
| 9 | `EmailBlueprintError` | implicit via `parseEmailBlueprint` | (covered by K-1 construction) | — | 5–11b, 101 | — | 88, 94, 96, 97b | J-13 |
| 10 | `EmailBlueprintErrors` | implicit (distinct seq) | (covered by K-2 set-style and K-9 ordered) | — | 7i, 48, 101, 101a, 101b, 101c | — | 88, 94 | J-13 (dual-purpose: also generates collections of errors) |
| 11 | `BodyPartPath` | distinct seq (no parse — invariant is "any seq[int] is valid", covered by second-audit I-16 `makeBodyPartPath` factory for protocol step 2) | I-16 | — | 37p, 37q, 37r, 99f | — | 88, 96, 97d | J-12 |
| 12 | `BodyPartLocation` | case object | I-13 | — | 7e–7h, 37l, 37p, 101 | — | 88 | J-12 |
| 13 | `EmailBlueprintConstraint` (enum) | N/A | N/A | — | used throughout §6.1.1 | — | 88, 94 | J-11 (trial-variant bijection) + pure enum iteration |
| 14 | `EmailBodyKind` (enum) | N/A | N/A | — | 3, 18, 48b, 48c, 67 | — | — | composed into J-9 |

No type has a gap in the protocol. Every `make*` factory in I-1 … I-19
is consumed by at least two scenarios (I-18 `withLocale` and I-19
`adversarialHashCollisionNames` are function-level helpers rather than
factories; the "at-least-two-consumers" rule applies to `make*`
factories specifically per Part D §12.14 precedent). No dead factories.

---

## 7. Decision Traceability Matrix

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|----------|--------------------|--------|---------------------|
| E1 (R1-1) | Module placement for EmailBlueprint + serde | A) Extend email.nim + serde_email.nim, B) New email_blueprint.nim + serde_email_blueprint.nim, C) Type in new module, serde in existing | B — new dedicated modules, explicit `email_` prefix for self-documentation | DDD, duplicated appearance ≠ duplicated knowledge, make the right thing easy |
| E2 (R1-2) | BlueprintBodyValue type | A) Reuse EmailBodyValue + flag-false check in blueprint ctor, B) New BlueprintBodyValue (value-only), C) Reuse + reusable predicate | B — new plain object `{ value: string }`; mirrors BlueprintBodyPart-vs-EmailBodyPart asymmetry one level down | Make illegal states unrepresentable, DDD, parse-don't-validate |
| E3 (R1-3) | API surface | A) Smart ctor only, B) Smart ctor + fluent builder, C) Smart ctor + preset wrappers | A — single parseEmailBlueprint with named parameters | Constructors are privileges, parse once at the boundary, YAGNI |
| E4 (R2-1) | Field sealing | A) Plain public (IdentityCreate precedent), B) Pattern A sealed (HeaderPropertyKey precedent), C) Mixed | B — Pattern A with `raw*` prefix + UFCS accessors | Make illegal states unrepresentable, parse once at the boundary |
| E5 (R2-2) | `from` field naming | A) `fromAddr`, B) Backtick `` `from` ``, C) `fromAddresses` (plural) | A — matches contentType ↔ "type" pattern from Part C §3.2 | DDD, code reads like the spec, one source of truth |
| E6 (R2-3) | Sender cardinality | A) Uniform `Opt[seq[EmailAddress]]`, B) Singular `Opt[EmailAddress]`, C) Shared AtMostOne wrapper | B — singular per RFC 5322 §3.6.2 semantic; serde owns the wire asymmetry | Make illegal states unrepresentable, duplicated appearance ≠ duplicated knowledge |
| E7 (R2-4) | receivedAt type | A) `Opt[UTCDate]`, B) `UTCDate` required, C) `Opt[UTCDate]` + helper | A — Opt.none = "defer to server clock" as a positively-meaningful state | Code reads like the spec, Postel's law, one source of truth |
| E8 (R3-1) | Error accumulation | A) `Result[_, seq[ValidationError]]` (accumulate), B) Single `ValidationError` (short-circuit), C) Extended ValidationError sum-type | A refined — domain-specific triad: EmailBlueprintConstraint enum + EmailBlueprintError + EmailBlueprintErrors distinct non-empty seq | Errors are part of the API, newtype everything that has meaning, make state transitions explicit |
| E9 (R3-2) | ValidationError shape for constraint errors | subsumed by E8 | — | — |
| E10 (R3-2a) | Error location representation | A) Just constraint + message, B) Optional per-location fields, C) Sum-type location field, D — refined) Case object discriminated by constraint | Refined C — case object on EmailBlueprintError itself; `message` as pure func not stored field. **Post-audit rename (see E27):** the variant originally named `ebcDuplicateHeaderRepresentation` is renamed to `ebcEmailTopLevelHeaderDuplicate` to participate in a three-variant "HeaderDuplicate" naming family alongside Gap 1 and Gap 2 variants. | Make illegal states unrepresentable, one source of truth, code reads like the spec |
| E11 (R3-2b) | "At least one of textBody/htmlBody" constraint | A) Drop (RFC-faithful), B) Keep as ebcNoBodyContent variant, C) Separate optional validator | A — RFC §4.6 does not mandate; architecture §8.5's addition overridden | Code reads like the spec, parse-don't-validate |
| E12 (R3-3) | partId reference validation | A) Forward resolution only, B) Bidirectional (reject orphans), C) Forward + warning — refined) Denormalise bodyValues into the tree | Refined — add `value: BlueprintBodyValue` field to bpsInline; `bodyValues` becomes derived accessor; constraint 8 and ebcPartIdReferenceUnresolved eliminated | Make illegal states unrepresentable, one source of truth, parse once at the boundary |
| E13 (R3-4) | Content-Transfer-Encoding enforcement + Content-* at top-level enforcement | A) Tree-walk in smart ctor, B) BlueprintBodyPart smart ctor, C) Distinct Table type — D refined) Two distinct header-key types | D — two distinct types (originally `distinct HeaderPropertyKey`) forbidding Content-* (top-level) and Content-Transfer-Encoding (body parts); constraints 4 AND 9 eliminated at the type level. **Superseded by E28:** the wrapping moves from `distinct HeaderPropertyKey` (key carried name + form + isAll) to `distinct string` (key carries only the name; form + :all live on the paired `BlueprintHeaderMultiValue` value). The forbidden-name rules carry forward unchanged; only the key's internal structure is restructured. See E28 for the redesign's provenance and rationale. | Make illegal states unrepresentable, newtype everything that has meaning, parse once at the boundary |
| E14 (R3-5) | MailboxIdSet at-least-one invariant | A) Smart ctor only, B) New NonEmptyMailboxIdSet distinct type, C) Tighten MailboxIdSet itself | B — distinct `HashSet[Id]` parallel to MailboxIdSet; smart ctor rejects empty. **Signature adjustment:** `parseEmailBlueprint` takes `mailboxIds: NonEmptyMailboxIdSet` directly (not openArray[Id] as originally framed), completing the type-level strip rather than adapting the failure at the blueprint boundary. See E24 for the parallel body-input decision. | Make illegal states unrepresentable, Postel's law (keep MailboxIdSet lenient), newtype everything that has meaning, parse once at the boundary |
| E15 (R3-5a) | NonEmptyMailboxIdSet home | A) mail/mailbox.nim alongside MailboxIdSet, B) email_blueprint.nim with the consumer, C) new mail/mailbox_ids.nim | A — under labelled "Mailbox ID Collections" section so the parallel between the two types is structurally visible | DDD, duplicated appearance ≠ duplicated knowledge |
| E16 (R4-1) | Convenience field serde mapping | A) JMAP convenience keys, B) Wire `header:*` keys uniformly, C) Configurable per call | A — with explicit convenience-field ↔ JSON-key ↔ RFC parsed-form mapping table in §3.5.1 | Code reads like the spec, one source of truth, make the wrong thing hard |
| E17 (R4-2) | Opt.none serde | A) Omit key, B) Emit null, C) Mixed per field | A — framed as homomorphism between absence representations; cross-reference to Part C §3.6's identical rule | One source of truth, code reads like the spec, parse once at the boundary |
| E18 (R4-3) | Empty-collection serde | A) Omit all empty, B) Emit `{}`, C) Mixed (bodyValues omit, others emit) | A — framed as pick-one-form-per-fact (not strict homomorphism — empty ≠ absent); `Opt[KeywordSet]` alternative explicitly rejected | One source of truth, YAGNI, consistency with architecture §8.4 precedent |
| E19 (R5-1) | Property-based test strategy | A) Generate-then-emit (no round-trip), B) Server-integration round-trip, C) Skip property tests — refined) Seven principle-grounded properties each naming defended principle and guarded R-decision | Refined A — seven properties: totality ×2, determinism, error accumulation, shape invariants, key omission, injectivity | Total functions, errors are part of the API, one source of truth |
| E20 (R5-2) | Test categories | A) Unit + serde + property + adversarial, B) Drop adversarial, C) Unit + serde only | A — with assertNotCompiles embedded in the unit category per Part C §4.7 precedent | Make illegal states unrepresentable, DRY (don't fragment tests from types they defend) |
| E21 (R5-3) | Test numbering | A) Self-contained 1..N, B) Global continuation from Part D, C) Alphabetic per-section | A — restart from 1; suffixes reserved for scenario expansions | DRY, one convention across parts |
| E22 (R6-1) | Decision Traceability Matrix content | A) Full DTM per Parts C/D, B) Part E-specific only with cross-references, C) No DTM | A — every R-decision and sub-decision gets a row | One source of truth, code reads like the spec, DRY |
| E23 (R6-2) | Section structure | A) Parts A/D entity-centric, B) Part C vocabulary template, C) Custom creation-aggregate framing | C — §1 Scope, §2 Creation Aggregate Overview, §3 EmailBlueprint, §4 Supporting Types, §5 Part C Modifications, §6 Tests, §7 DTM | DDD, code reads like the spec, make the right thing easy (readers see aggregate framing before type details) |
| E24 (post-audit) | Body-XOR enforcement in parseEmailBlueprint signature | A) Runtime check with new `ebcBodyPathConflict` variant, B) Separate error type for pre-checks, C) **Case-object input type (`EmailBlueprintBody`) making XOR type-level** | C — new `EmailBlueprintBody` case object with `flatBody()` / `structuredBody()` helpers. `parseEmailBlueprint` takes `body: EmailBlueprintBody` as a single parameter; the case discriminant makes both-variants-populated a compile error. Fourth application of the strip-pattern (signature level), parallel to E14's signature-level strip for mailboxIds. **This row was added during a post-write audit** that surfaced the gap where `parseEmailBlueprint`'s original 4-independent-body-parameters signature could receive a body-XOR violation with no error-enum variant to report it. | Make illegal states unrepresentable, make state transitions explicit, parse once at the boundary, precedent scales (strip-pattern fourth application) |
| E25 (RFC audit, Gap 1) | Scope of "bodyStructure root vs Email top-level duplicate" check (RFC §4.6 lines 2866-2868) | A) **bodyStructure ROOT only**, B) Whole bodyStructure subtree, C) Root + immediate children of a root multipart | A — ROOT only; matches RFC's singular "the bodyStructure EmailBodyPart" phrasing and the wire-level semantics where only the bodyStructure root's MIME headers merge with Email top-level headers on the message header block. Sub-parts have scoped header blocks inside MIME boundaries and are covered by E26's within-part check instead. Gap originally identified by a post-write RFC audit that found the constraint was unenforced. | Code reads like the spec, make the right thing easy, parse once at the boundary |
| E26 (RFC audit, Gap 2) | Locator payload for `ebcBodyPartHeaderDuplicate` (within-body-part duplicate, RFC §4.6 lines 2844-2846 "or particular EmailBodyPart") | A) `partId: Opt[PartId]` + key, B) Path-based `path: seq[int]`, C) Just the key with no location, D) Sum-type locator with variants per kind | Refined D — `BodyPartLocation` case object with three variants (bplInline/bplBlobRef/bplMultipart), each carrying exactly its identifier: `partId: PartId`, `blobId: Id`, `path: BodyPartPath` (a `distinct seq[int]` newtype). Original Option D presentation had two bugs (bplBlobRef incorrectly carried Opt[PartId], and bplMultipart used bare seq[int]); these were corrected before commitment. Gap originally identified by a post-write RFC audit that found no walk catches within-body-part duplicates (Part C §3.5 commits to no smart constructor on BlueprintBodyPart). | Make state transitions explicit in the type, newtype everything that has meaning, make illegal states unrepresentable |
| E27 (RFC audit, variant shape) | How to shape the new duplicate-check variants alongside the existing one | A) Two separate variants (new only), B) One merged variant with a kind discriminator, C) **Two separate new variants plus rename of the existing variant into a shared naming family** | C — rename `ebcDuplicateHeaderRepresentation` → `ebcEmailTopLevelHeaderDuplicate`; add `ebcBodyStructureHeaderDuplicate` (Gap 1, E25) and `ebcBodyPartHeaderDuplicate` (Gap 2, E26). The three variants form a "HeaderDuplicate" naming family matching the three distinct RFC duplicate rules. Gap-1 variant carries `bodyStructureDupName` (lowercase header name); Gap-2 variant carries `where: BodyPartLocation` plus `bodyPartDupName`. **Field naming updated by E28:** the Gap-1/Gap-2 variants originally carried `bodyStructureDupKey` / `bodyPartDupKey` (`HeaderPropertyKey` values) under the E13 header-key design; under E28's name-only redesign these became `bodyStructureDupName` / `bodyPartDupName` (plain lowercase strings, matching the new Name types' identity). Rejected alternatives: single merged variant would reintroduce an `Opt[BodyPartLocation]` "meaningful only sometimes" pattern — reopens the R3-2a case-object decision. | Code reads like the spec, return types are documentation, make the right thing easy (discoverability by naming family), errors are part of the API |
| E28 (RFC audit, Gap 3) | How to enforce "no two extraHeaders entries for the same header name" (intra-Table axis, RFC §4.6 lines 2844-2846 applied to the Table-internal axis) | A) Runtime check with new `ebcExtraHeadersNameDuplicate` variant, B) **Type-level via key redesign — name-only keys paired with a HeaderMultiValue that carries form**, C) New distinct Table type, D) Absorb into existing HeaderDuplicate family | Refined B — introduce three new types: `BlueprintEmailHeaderName` / `BlueprintBodyHeaderName` (name-only `distinct string`, replacing the `distinct HeaderPropertyKey` design from E13/R3-4) and `BlueprintHeaderMultiValue` (case object carrying form + `NonEmptySeq[T]` of values). Add generic `NonEmptySeq[T]` to `primitives.nim` for reusable non-empty-seq invariant. Refinement over plain B: apply a generic `NonEmptySeq[T]` newtype uniformly to all seven HeaderMultiValue payloads, placing the non-emptiness invariant type-level rather than at a per-HMV smart constructor. Organise headers.nim under labelled "Read-Model" / "Creation-Model" section headers (matching R3-5a mailbox.nim convention). Rename from user's draft `HeaderMultiValue` to `BlueprintHeaderMultiValue` for Blueprint* prefix consistency (R1-2, R3-4, EmailBlueprintBody). Strict/lenient split on Name smart constructors (strict client-side, mirroring parseId/parsePartId). **Eliminates four constraints at the type level in one redesign:** constraint 3d (intra-Table duplicates), constraint 4 (Content-* at top level) and constraint 9 (Content-Transfer-Encoding on body parts) — retained from E13 via the forbidden-name checks — and constraint 10 (key/value form consistency — now impossible because form has one home). The original E13 design (distinct HeaderPropertyKey key types) is **superseded**: BlueprintEmailHeaderKey / BlueprintBodyHeaderKey no longer exist. **Two post-audit rounds identified this gap:** a first pass (E25/E26/E27) caught Gaps 1 and 2 (cross-axis duplicates); this second pass caught the intra-Table axis. | Make illegal states unrepresentable (four constraints eliminated), newtype everything that has meaning, one source of truth per fact (form has one home), DRY (NonEmptySeq[T] is generic), precedent scales (fifth application of the strip-pattern — §2.2 level "Header key names and their form dimension") |
| E29 (post-audit, test-spec restructure) | Test specification structure | A) Keep Part E pre-audit layout (4 categories: unit, serde, property, adversarial; no shared test-infrastructure subsection), B) **Add §6.5 Test Infrastructure subsection following Part D §12.14 precedent; consolidate N/A scenarios into §6.1.0 prose; merge duplicate compile-time pairs (38+39, 42+43+44, 46+47); deduplicate scenarios 21/22, 27, 45/99; tighten under-specified scenarios (12, 18, 49); expand R4-1 mapping to per-row assertions; add scenarios for `BodyPartPath`/`BodyPartLocation`/`message`/`NonEmptySeq[T]`; add three completeness-audit properties (88, 93, 94); add three adversarial properties (95, 96, 97); add FFI panic-surface scenarios (102, 102a, 102b); rewrite scenario 100 from "disjoint inputs" tautology to actual two-thread contention test; add hash-collision DoS probe (99d); add error-accumulation stress (101a, 101b); add CRLF/NUL injection scenarios (100, 100a)** | B — three independent post-audit reviewers (red-team / completeness / infrastructure) converged on the gaps; convergence across distinct lenses signals genuine issues rather than reviewer bias. The §6.5 subsection alone enumerates 14 factories, 15 generators, 8 equality helpers, 6 assertion templates, and 13 test-file assignments — every shared scaffolding artefact every scenario depends on. Without §6.5, every test file would reinvent fixtures, generators, and equality helpers inline, violating "DRY — but duplicated appearance is not duplicated knowledge" in the direction where the knowledge IS shared. The pre-audit layout had 100 numbered scenarios; the post-audit layout has ~120 unique runnable assertions plus 6 numbered slots removed for being non-tests. | Errors are part of the API (variant payloads pinned not just type), totality (FFI panic surface defended), make the right thing easy (factories collapse 14 duplicate-at-location scenarios into one-liners), DRY, code reads like the spec (test-infrastructure precedent followed) |
| E30 (post-audit, documented gap) | `bodyValues` harvest under duplicate `partId` | A) Add `ebcDuplicatePartId` smart-ctor variant (pre-flight check rejects construction), B) **Document caller responsibility; pin current behaviour (last-wins via Table key collision) in scenario 72a; flag for Part F revisit**, C) Validate at serde time and emit `null` for losing entries | B (provisional) — the design currently assumes callers construct trees with unique `PartId` values per leaf. Adding `ebcDuplicatePartId` would require walking the tree to enumerate inline `partId`s before constructing the result Table, duplicating logic the harvest accessor (§3.5) already implements. Scenario 72a documents the current data-loss surface explicitly so the gap is visible to Part F's `Email/set` author, who can either (a) lift the variant into Part E retroactively, or (b) add a Part F-level submission guard. The decision is provisional pending Part F's submission-error landscape. Second audit adds sc 72b as a loud-failure regression gate on top of the provisional decision. | Code reads like the spec (gap is documented, not hidden), one source of truth per fact (avoid duplicating tree-walk logic premature to Part F's needs), YAGNI (no enum variant added until a use case demands it) |
| E31 (second post-audit cycle) | Whether the first-audit §6 layout was a final state or an intermediate one | A) Freeze §6 at the E29 layout; B) **Run a second three-perspective audit (adversarial / ergonomic / formal-coverage) and apply its findings**; C) Wait for Part F and batch-audit both | B — a second independent three-lens audit ran after the first-audit §6 was considered complete. The three lenses (red-team adversarial, test-infrastructure ergonomic, formal-coverage completeness) each surfaced distinct classes of issue that the first audit had not found: (a) five first-audit scenarios that could not fail ("cannot-fail" tautologies: sc 99c / 99d / 72a undefended / 11b unbounded / 102 grep-based), (b) a type-level contradiction in K-2 (sc 101 wanted set-style equality while property 94 wanted ordered — same helper name was load-bearing for both), (c) five undefended R-decisions (R1-1, R2-2, R2-4, R3-2b, strict-only naming), (d) ten scenarios that duplicated or trivialised each other (sc 8, 11, 13, 14, 15, 16, 19, 22, 28, 37m, 37n, 37o, 71, 74, 80, 100b, 100c), and (e) 20-consumer duplication in Table-construction inlining that warranted a new factory (I-15). Outputs of this cycle: ten new adversarial scenarios (98d–98f, 99f, 100e, 101c, 102c, 102d, 104c), five new properties (97a–97e), five new infrastructure rows (I-15–I-19, K-9, L-7–L-9), and eight existing-row edits. Eight of the changes convert "documents a gap" non-tests into loud regression gates. Net effect: ~120 first-audit scenarios → ~130 second-audit scenarios, with duplicates removed and every surviving scenario a runnable assertion. | Errors are part of the API (K-2/K-9 split makes ordering intent explicit), make illegal states unrepresentable (new `assertNotCompiles` guards for ebcNoBodyContent and FromServer parsers), totality (bounded message rendering, depth coupling), DRY in the direction where knowledge IS shared (I-15 header-map factory replaces 20 inline Table builds), one source of truth per fact (insertion-order insensitivity property), no test without a runnable assertion (sc 80, 99c "or" branch, 99d conditional, 11b unbounded all converted or removed) |

---
