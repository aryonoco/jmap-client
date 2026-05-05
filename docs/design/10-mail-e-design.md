# RFC 8621 JMAP Mail — Design E: EmailBlueprint Creation Aggregate

This document is the detailed specification for `EmailBlueprint` — the
creation model for client-constructed Emails — together with the supporting
vocabulary types it requires. It covers Layers 1 (L1 types) and 2 (L2 serde
— `toJson` only, unidirectional).

Part E is pure creation vocabulary. It defines the central aggregate
(`EmailBlueprint`) plus its supporting types and then specifies the
`toJson` serialiser that takes a blueprint to JMAP creation JSON. No
methods, no entity registration, no builders — `Email/set`, `Email/copy`,
`Email/import`, and EmailSubmission are deferred to Parts F, G, H, and I
respectively.

Builds on the cross-cutting architecture design
(`05-mail-architecture.md` §8.4–8.6), the existing RFC 8620 infrastructure
(`00-architecture.md` through `04-layer-4-design.md`), Design A
(`06-mail-a-design.md`), Design B (`07-mail-b-design.md`), Design C
(`08-mail-c-design.md` — `BlueprintBodyPart`, `HeaderPropertyKey`,
`HeaderValue`, `EmailBodyValue`, `PartId`, `EmailAddress`), and Design D
(`09-mail-d-design.md` — `Email` read model). Decisions from the
cross-cutting doc are referenced by section number.

---

## Table of Contents

1. [Scope](#1-scope)
2. [Creation Aggregate Overview](#2-creation-aggregate-overview)
3. [EmailBlueprint](#3-emailblueprint)
4. [Supporting Creation Types](#4-supporting-creation-types)
5. [Cross-Part Modifications](#5-cross-part-modifications)
6. [Test Specification](#6-test-specification)
7. [Decision Traceability Matrix](#7-decision-traceability-matrix)

---

## 1. Scope

### 1.1. Types Covered

| Type | Module | Rationale |
|------|--------|-----------|
| `EmailBlueprint` | `email_blueprint.nim` | Creation-model aggregate for `Email/set`. |
| `EmailBlueprintBody` | `email_blueprint.nim` | Case object whose discriminant encodes `bodyStructure` XOR flat-list at the type level. |
| `EmailBodyKind` | `email_blueprint.nim` | Discriminant for `EmailBlueprintBody` (`ebkStructured` vs `ebkFlat`). |
| `EmailBlueprintConstraint` | `email_blueprint.nim` | Enum of runtime cross-field constraints the smart constructor checks. |
| `EmailBlueprintError` | `email_blueprint.nim` | Case object discriminated by the constraint enum. |
| `EmailBlueprintErrors` | `email_blueprint.nim` | Pattern A sealed aggregate of errors carried on the err rail. |
| `BodyPartPath` | `email_blueprint.nim` | `distinct seq[int]`; tree path locating a multipart body part. |
| `BodyPartLocationKind` | `email_blueprint.nim` | Discriminant for `BodyPartLocation`. |
| `BodyPartLocation` | `email_blueprint.nim` | Case object naming an offending body part (inline / blob-ref / multipart). |
| `BlueprintBodyValue` | `body.nim` | Value-only sibling of `EmailBodyValue`; no creation-invalid flag fields. |
| `BlueprintLeafPart` | `body.nim` | Inner case object carrying the content half of a non-multipart `BlueprintBodyPart` (extracted so `strictCaseObjects` can track each discriminator independently). |
| `NonEmptyMailboxIdSet` | `mailbox.nim` | Parallel to `MailboxIdSet`; encodes "at least one" at the type level. |
| `BlueprintEmailHeaderName` | `headers.nim` | `distinct string`; lowercase header name valid for Email top-level `extraHeaders` (forbids `content-*`); identity is name-only. |
| `BlueprintBodyHeaderName` | `headers.nim` | `distinct string`; lowercase header name valid for `BlueprintBodyPart.extraHeaders` (forbids `content-transfer-encoding`); identity is name-only. |
| `BlueprintHeaderMultiValue` | `headers.nim` | Case object carrying form + a `NonEmptySeq[T]` of values for a single header field. |
| `NonEmptySeq[T]` | `primitives.nim` | Generic `distinct seq[T]` with at-least-one invariant. |

**Smart constructors and helpers:**

| Function | Module | Purpose |
|----------|--------|---------|
| `parseEmailBlueprint` | `email_blueprint.nim` | Single public smart constructor; accumulating error rail. |
| `flatBody`, `structuredBody` | `email_blueprint.nim` | Total helpers for constructing `EmailBlueprintBody` at call sites. |
| `parseNonEmptyMailboxIdSet` | `mailbox.nim` | Smart constructor for the non-empty mailbox-id set. |
| `parseBlueprintEmailHeaderName` | `headers.nim` | Strict smart constructor for the top-level header name. |
| `parseBlueprintBodyHeaderName` | `headers.nim` | Strict smart constructor for the body-part header name. |
| `parseNonEmptySeq[T]` | `primitives.nim` | Generic smart constructor rejecting empty seq. |
| `rawMulti`, `textMulti`, `addressesMulti`, `groupedAddressesMulti`, `messageIdsMulti`, `dateMulti`, `urlsMulti` | `headers.nim` | Per-form constructors for `BlueprintHeaderMultiValue` taking arbitrary seqs. |
| `rawSingle`, `textSingle`, `addressesSingle`, `groupedAddressesSingle`, `messageIdsSingle`, `dateSingle`, `urlsSingle` | `headers.nim` | Zero-ceremony constructors for the single-value common case. |

### 1.2. Deferred

**Part F (Email write method):** `Email/set` (create, update, destroy),
`EmailSetResponse`, typed set-error accessors for create
(`blobNotFound`, `tooManyKeywords`, `tooManyMailboxes`). Part F consumes
`EmailBlueprint` via `toJson` but does not modify it.

**Part G (`Email/copy` + compound handles):** `Email/copy`,
`EmailCopyItem`, the compound-handle pattern (debut), `addEmailCopyChained`.

**Part H (`Email/import`):** `Email/import`, `EmailImport` request item,
`addEmailImport` builder. Blob ingest is independent of `EmailBlueprint`.

**Part I (EmailSubmission):** `EmailSubmission`, `Envelope`,
`SubmissionAddress`, `DeliveryStatus`, `UndoStatus`, `SubmissionEmailRef`,
and EmailSubmission's methods.

**Blob handling** remains deferred to a separate future part per
architecture §4.6. `BlobId` continues to be a `distinct string` with no
length cap until the dedicated blob part introduces a richer type.

### 1.3. Relationship to Cross-Cutting Design

This document refines `05-mail-architecture.md` §8.4–8.6 into
implementation-ready specification for the creation-aggregate bounded
context. Several architectural sketches are tightened in this part:

- The `bodyValues: Table[PartId, EmailBodyValue]` field on
  `EmailBlueprint` from architecture §8.4 is **denormalised** into the
  body tree (§3.5, §5.1). `bodyValues` is a derived accessor, not a
  stored field. Constraint 8 (partId references must resolve) is
  thereby eliminated.
- `EmailBlueprint.mailboxIds` uses a `NonEmptyMailboxIdSet` (§4.2)
  rather than `MailboxIdSet`, encoding architecture §8.5's "at least
  one" invariant at the type level. `parseEmailBlueprint` accepts
  `NonEmptyMailboxIdSet` directly as its parameter.
- `EmailBlueprint.extraHeaders` and `BlueprintBodyPart.extraHeaders`
  use two name-only distinct-string key types
  (`BlueprintEmailHeaderName` / `BlueprintBodyHeaderName`) paired with
  a case-object value type (`BlueprintHeaderMultiValue`) that carries
  the form and a `NonEmptySeq[T]` of values. Three constraints become
  type-level: no two `extraHeaders` entries for the same header (Table
  key name-granularity identity), key/value form consistency (form
  lives once on the value), and "empty header" prevention
  (`NonEmptySeq[T]`). Constraints 4 and 9 stay type-level via the
  forbidden-name checks in the two Name smart constructors.
- `BlueprintBodyValue` (§4.1) strips the read-model flag fields
  (`isEncodingProblem`, `isTruncated`) from `EmailBodyValue`.
- `EmailBlueprintBody` (§3.2) is a case object whose discriminant
  makes `bodyStructure` XOR flat-list a compile-time fact.
  `parseEmailBlueprint` accepts `EmailBlueprintBody` as a single
  parameter rather than four independent body fields.
- The smart constructor's error rail carries a domain-specific triad
  (`EmailBlueprintConstraint` enum + `EmailBlueprintError` case object
  + `EmailBlueprintErrors` Pattern A sealed aggregate) rather than a
  generic `seq[ValidationError]`.

After all type-level eliminations the smart constructor handles **seven
runtime constraint classes**: the two flat-body content-type checks,
three "HeaderDuplicate" rules (Email top-level, bodyStructure root vs
top-level, within-body-part), the allowed-forms check, and the body-tree
depth check. Empty-mailboxIds, body-XOR violation, intra-Table header
duplicates, key/value form mismatch, flag fields true on body values,
Content-* at top level, and Content-Transfer-Encoding on body parts are
all unrepresentable at the type level.

### 1.4. General Conventions Applied

- **Pure L1/L2 code** — `{.push raises: [], noSideEffect.}` at the top
  of every module in this part. Only `func` is permitted (no `proc`).
- **`{.experimental: "strictCaseObjects".}`** is enabled in every src/
  module. All variant-field reads sit inside a `case` arm proving the
  discriminant; case objects expose hand-rolled `==` (auto-`==` rejects
  case objects via the parallel-`fields`-iterator failure).
- **Result-based error handling** — every smart constructor returns
  `Result`. No exceptions for domain-level failure.
- **`Opt[T]` for optional fields** — never `std/options`.
- **Typed errors on the error rail** — the aggregate error type
  (`EmailBlueprintErrors`) carries enumerated variants, never collapsed
  strings.
- **Pattern A sealing where invariants exist** — `EmailBlueprint`
  follows the `HeaderPropertyKey` precedent (Part C §2.3): module-
  private `raw*` fields with same-name UFCS accessors as the public
  API. `EmailBlueprintErrors` does the same for its underlying seq.
- **Strict on construction, lenient on reads** — the read-model
  `Email` in Part D accepts server-provided data per Postel's law;
  Part E enforces strict RFC §4.6 invariants on client-constructed
  blueprints. The two blueprint header-name parsers have **no**
  `*FromServer` lenient siblings: creation vocabulary is unidirectional.
- **Creation types serialise unidirectionally** — `toJson` only, no
  `fromJson`. Adding `fromJson` would create a second construction
  path bypassing the smart constructor, violating "constructors are
  privileges, not rights." (`BlueprintEmailHeaderName` and
  `BlueprintBodyHeaderName` host both directions only because the
  shared distinct-string template produces both — `fromJson` is
  inert in the creation path.)

### 1.5. Module Summary

| Module | Layer | Status | Contents |
|--------|-------|--------|----------|
| `email_blueprint.nim` | L1 | new | `EmailBlueprint`, `EmailBlueprintBody`, `EmailBodyKind`, `EmailBlueprintConstraint`, `EmailBlueprintError`, `EmailBlueprintErrors`, `BodyPartPath`, `BodyPartLocation`, `BodyPartLocationKind`, `parseEmailBlueprint`, `flatBody`, `structuredBody`, accessors, derived `bodyValues`, `message`. |
| `serde_email_blueprint.nim` | L2 | new | `toJson` for `EmailBlueprint`. |
| `mailbox.nim` | L1 | extended | `NonEmptyMailboxIdSet`, `parseNonEmptyMailboxIdSet` under a "Mailbox ID Collections" section. |
| `headers.nim` | L1 | extended | "Creation-Model Header Vocabulary" section: `BlueprintEmailHeaderName`, `BlueprintBodyHeaderName`, `BlueprintHeaderMultiValue`, the `*Multi` and `*Single` constructors, `defineNonEmptySeqOps` instantiations. |
| `serde_headers.nim` | L2 | extended | Distinct-string serde for the two name types; `composeHeaderKey`, `multiLen`, `blueprintMultiValueToJson` — the wire-composition primitives shared by `EmailBlueprint.toJson` and `BlueprintBodyPart.toJson`. |
| `primitives.nim` | L1 | extended | `NonEmptySeq[T]`, `parseNonEmptySeq[T]`, `defineNonEmptySeqOps[T]`, `head`. |
| `body.nim` | L1 | extended | `BlueprintBodyValue`, `BlueprintLeafPart`. `BlueprintBodyPart.extraHeaders` retyped to `Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]`; the leaf branch carries `leaf: BlueprintLeafPart`. The shared depth bound `MaxBodyPartDepth = 128` lives here. |
| `serde_body.nim` | L2 | extended | `BlueprintBodyValue.toJson`; `BlueprintBodyPart.toJson` emits `partId` only on inline leaves and uses `composeHeaderKey` / `blueprintMultiValueToJson` for body-part `extraHeaders`. The inline `value` is harvested separately by `EmailBlueprint.toJson`. |
| `mail/types.nim` | — | extended | Re-exports the new public types. |

---

## 2. Creation Aggregate Overview

### 2.1. Why a Cluster, Not a Single Type

`EmailBlueprint` is the central creation aggregate, but it does not stand
alone. Supporting types encode RFC 8621 §4.6 invariants at the type
level, collapsing what would otherwise be runtime constraints into
structural guarantees:

- **`EmailBlueprintBody`** (§3.2) — case object whose discriminant
  encodes `bodyStructure` XOR flat-list at the type level.
- **`BlueprintBodyValue`** (§4.1) — body-value creation type stripping
  the read-model flag fields. RFC §4.6 mandates both flags be false on
  creation; the stripped type makes flag-true unrepresentable.
- **`NonEmptyMailboxIdSet`** (§4.2) — `distinct HashSet[Id]` with
  at-least-one invariant.
- **`BlueprintEmailHeaderName`** (§4.3) — `distinct string`; lowercase
  header name forbidding `content-*`.
- **`BlueprintBodyHeaderName`** (§4.4) — `distinct string` forbidding
  `content-transfer-encoding`.
- **`BlueprintHeaderMultiValue`** (§4.5) — case object carrying form +
  a non-empty seq of values for a single header field. The form lives
  once, on the value's discriminant.
- **`NonEmptySeq[T]`** (§4.6) — generic `distinct seq[T]` with
  at-least-one invariant.

The aggregate is designed so the type system does as much of the work as
possible. What remains for the smart constructor is genuinely cross-field:
constraints that cannot be encoded structurally because they depend on
the simultaneous state of multiple fields.

### 2.2. The Strip-Pattern, Five Levels Deep

The design applies one pattern at five different levels of the aggregate
— from leaf values up to the smart constructor's signature. Each
application reduces creation-model complexity by removing state that
cannot legally exist at the creation boundary:

| Level | Pattern | Artefact | RFC invariant it encodes |
|-------|---------|----------|--------------------------|
| Leaf value | **Strip fields** — remove read-only flag fields that must be false on creation | `EmailBodyValue` → `BlueprintBodyValue` | RFC §4.6: `isEncodingProblem` and `isTruncated` MUST be false. |
| Map structure | **Relocate data** — co-locate the value with the partId that references it | `Table[PartId, BlueprintBodyValue]` on `EmailBlueprint` → `value` field on inline body parts | RFC §4.6: if `partId` given, MUST be present in `bodyValues`. |
| Header key names (and their form dimension) | **Forbid names and separate form from key** — name-only distinct-string keys reject context-forbidden names; form moves onto the paired value, so no key/value disagreement is representable and no two entries can share a name | `Table[HeaderPropertyKey, HeaderValue]` → `Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]` / `Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]` | RFC §4.6: no `Content-*` at top level, no `Content-Transfer-Encoding` on body parts, no duplicate header representation (intra-Table axis), and key/value form consistency. |
| Header value cardinality | **Non-empty collection** — use a generic `NonEmptySeq[T]` inside the multi-value type to prevent the "header exists with zero values" degenerate state | `seq[T]` → `NonEmptySeq[T]` inside `BlueprintHeaderMultiValue` | Implicit RFC well-formedness: a header property with no values has no wire expression. |
| Signature input | **Strip illegal combinations** — make smart-constructor parameters pre-validated at the type level so no runtime check for "mailboxIds empty" or "body-XOR violated" is reachable | `openArray[Id]` + four independent body fields → `NonEmptyMailboxIdSet` + `EmailBlueprintBody` case object | RFC §4.6: at least one Mailbox; `bodyStructure` XOR flat-list. |

Each application is principled on the same grounds:

- **Make illegal states unrepresentable.** A state that is forbidden on
  creation should not be expressible in the creation type.
- **Parse once at the boundary.** The strip happens at the earliest
  possible construction point — smart constructor, distinct type, or
  field-type choice — so every downstream consumer receives
  pre-validated data.
- **Different knowledge deserves different appearance.** The read model
  and the creation model are different aggregates with different
  invariants. Sharing types would force runtime checks that the type
  system could otherwise enforce.

### 2.3. Relationship to Part C

Part C introduced `BlueprintBodyPart` as the creation-model counterpart
to `EmailBodyPart`, stripping `EmailBodyPart.headers` (raw header seq)
at the type level. Part E extends this discipline two levels down:

- `BlueprintBodyValue` strips flag fields from `EmailBodyValue` (the
  leaf value level).
- `BlueprintBodyPart`'s leaf branch carries a co-located `value` via
  the inner `BlueprintLeafPart` case object, locating the `bodyValues`
  map's content in the tree (the structural level).
- `BlueprintBodyPart.extraHeaders` retypes to use
  `BlueprintBodyHeaderName`, forbidding `Content-Transfer-Encoding` at
  the key level (the header-key level).

These changes preserve Part C's stated design commitments — the
modifications are at field-type and field-presence level, not
construction-function level (no smart constructor on
`BlueprintBodyPart`).

---

## 3. EmailBlueprint

**Module:** `src/jmap_client/mail/email_blueprint.nim`

`EmailBlueprint` is the creation-model aggregate for `Email/set`. A
value of this type represents a validated, RFC 8621 §4.6-conforming
Email ready for submission. The name conveys "a complete, validated
email specification" — a domain concept, not a lifecycle annotation.

**Principles:** DDD (creation aggregate distinct from read aggregate),
parse-don't-validate (smart constructor is the sole boundary),
make-illegal-states-unrepresentable (case discriminant + Pattern A
sealing + strip-pattern types), Railway-Oriented Programming
(accumulating Result error rail).

### 3.1. Type Definition

`EmailBlueprint` uses **Pattern A sealing**: all fields are module-
private with a `raw*` prefix; the public API is a set of UFCS
accessors bearing the canonical (unprefixed) field names.

```nim
type EmailBodyKind* = enum
  ebkStructured    ## client provides full bodyStructure tree
  ebkFlat          ## client provides textBody / htmlBody / attachments

type EmailBlueprint* {.ruleOff: "objects".} = object
  rawMailboxIds: NonEmptyMailboxIdSet
  rawKeywords: KeywordSet
  rawReceivedAt: Opt[UTCDate]
  rawFromAddr: Opt[seq[EmailAddress]]
  rawTo: Opt[seq[EmailAddress]]
  rawCc: Opt[seq[EmailAddress]]
  rawBcc: Opt[seq[EmailAddress]]
  rawReplyTo: Opt[seq[EmailAddress]]
  rawSender: Opt[EmailAddress]              ## singular per RFC 5322 §3.6.2
  rawSubject: Opt[string]
  rawSentAt: Opt[Date]
  rawMessageId: Opt[seq[string]]
  rawInReplyTo: Opt[seq[string]]
  rawReferences: Opt[seq[string]]
  rawExtraHeaders: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]
  rawBody: EmailBlueprintBody
```

Key design properties:

- **Sealed fields + UFCS accessors.** Module-private `raw*` fields
  prevent direct construction outside `email_blueprint.nim`; the
  public API is same-name accessor funcs. Sealing makes the smart
  constructor a true boundary, not an advisory one.

- **Body as a single `rawBody: EmailBlueprintBody` field.**
  `EmailBlueprintBody` (§3.2) is a case object whose discriminant
  encodes the `ebkStructured` vs `ebkFlat` choice at the type level,
  forcing the body-XOR invariant to the signature boundary.

- **Singular `rawSender: Opt[EmailAddress]`.** RFC 5322 §3.6.2
  constrains `Sender:` to exactly one mailbox. Other address fields
  stay `Opt[seq[EmailAddress]]` because RFC 5322 permits
  mailbox-lists or address-lists there.

- **`fromAddr` naming.** Nim reserves `from` as a keyword; the field
  uses `fromAddr`. Serde maps `fromAddr` ↔ JMAP wire key `from`.

- **`rawReceivedAt: Opt[UTCDate]`.** `Opt.none` is a positively-
  meaningful state — "defer to the server's clock" — not mere
  absence. `Opt.some(t)` is "record this exact timestamp."

- **No `bodyValues` field.** The `bodyValues` map is a derived
  accessor (§3.5) walking the body tree to collect `(partId, value)`
  pairs from inline leaves. The body tree IS the bodyValues map.

### 3.2. EmailBlueprintBody

`EmailBlueprintBody` is a case object whose discriminant encodes the
`bodyStructure` XOR flat-list choice at the type level. It is the
signature-level application of the strip-pattern (§2.2 fifth row):
instead of `parseEmailBlueprint` taking four independent body
parameters and validating the XOR at runtime, it takes a single
`EmailBlueprintBody` value that cannot simultaneously be both kinds.

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

Public fields on both variants. The case discriminant is the seal —
populating fields from a different variant is a compile error — so no
further invariants need defending and no `raw*` prefix is required.

**Helpers for ergonomic construction:**

```nim
func flatBody*(
    textBody: Opt[BlueprintBodyPart] = Opt.none(BlueprintBodyPart),
    htmlBody: Opt[BlueprintBodyPart] = Opt.none(BlueprintBodyPart),
    attachments: seq[BlueprintBodyPart] = @[],
): EmailBlueprintBody

func structuredBody*(bodyStructure: BlueprintBodyPart): EmailBlueprintBody
```

Neither helper can fail; both are total. They name the two legal shapes
at call sites; callers may also use direct case-object syntax if they
prefer.

**Default body.** `parseEmailBlueprint`'s `body` parameter defaults to
`flatBody()` — the empty flat body (no `textBody`, no `htmlBody`, no
attachments). An email with no body content is legal per the RFC; this
is a positively valid state, not a degenerate one.

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

**Signature rationale:**

- **`mailboxIds: NonEmptyMailboxIdSet`** — the caller constructs it
  explicitly via `parseNonEmptyMailboxIdSet` before calling
  `parseEmailBlueprint`. The empty-mailboxIds failure mode never
  reaches the blueprint constructor.
- **`body: EmailBlueprintBody`** — single parameter carrying the body
  choice. The case discriminant precludes a "both paths populated"
  input. Default is `flatBody()`.
- **Named parameters with defaults.** A minimal text-only email reads:

  ```nim
  parseEmailBlueprint(
    mailboxIds = ?parseNonEmptyMailboxIdSet([inboxId]),
    body = flatBody(textBody = some(plainPart)),
  ).tryGet()
  ```

**Accumulating semantics.** The smart constructor runs every applicable
check and returns `err(EmailBlueprintErrors)` carrying every failing
constraint, not just the first. A caller with three problems learns
about all three in one call.

**Constraints checked** (after signature-level eliminations):

1. **Flat-body content types** — for an `ebkFlat` body, `textBody` (if
   `Opt.some`) has `contentType == "text/plain"` and `htmlBody` (if
   `Opt.some`) has `contentType == "text/html"`. Failures emit
   `ebcTextBodyNotTextPlain` / `ebcHtmlBodyNotTextHtml` carrying the
   observed content type.
2. **Email top-level header duplicates** — each convenience field
   (`fromAddr`, `to`, `cc`, `bcc`, `replyTo`, `sender`, `subject`,
   `sentAt`, `messageId`, `inReplyTo`, `references`) that is
   `Opt.some` does not have a corresponding `extraHeaders` entry.
   Header-name comparison uses RFC 5322 canonical lowercase spellings
   (`reply-to`, `message-id`, `in-reply-to`, `date` for `sentAt`).
   Each collision emits `ebcEmailTopLevelHeaderDuplicate{dupName}`.
3. **bodyStructure-vs-top-level (`ebkStructured` only)** — the
   bodyStructure ROOT's `extraHeaders` does not contain a name
   already set by the Email top level (convenience field or top-level
   `extraHeaders`). Scope is ROOT only per RFC §4.6 lines 2866–2868
   singular phrasing. Each collision emits
   `ebcBodyStructureHeaderDuplicate{bodyStructureDupName}`.
4. **Within-body-part duplicates** — walks every `BlueprintBodyPart`
   in the body tree (bodyStructure and its sub-parts for
   `ebkStructured`; `textBody`, `htmlBody`, and each element of
   `attachments` and their sub-parts for `ebkFlat`). For each part,
   computes the header set implied by its domain fields and flags any
   `extraHeaders` entry representing the same header. The implied
   header set is: `content-type` (always); `content-disposition` if
   `name.isSome` or `disposition.isSome`; `content-id` if
   `cid.isSome`; `content-language` if `language.isSome`;
   `content-location` if `location.isSome`. (`charset` does not add a
   distinct header — it folds into the `content-type` parameter
   space.) Each collision emits
   `ebcBodyPartHeaderDuplicate{where, bodyPartDupName}`.
5. **Allowed forms** — for each `extraHeaders` entry (top-level and
   within the body tree), the `(name, value.form)` pair is in the
   `allowedForms` table. The form comes directly from the
   `BlueprintHeaderMultiValue`'s discriminant; there is no separate
   key-form to reconcile. Failures emit
   `ebcAllowedFormRejected{rejectedName, rejectedForm}`.
6. **Body-part depth** — every body-part subtree is checked against
   `MaxBodyPartDepth = 128`. The walker reports the first offending
   subtree root only and stops recursing past it (a 1000-leaf
   subtree at depth 130 reports once, not 1000 times). Each
   violation emits `ebcBodyPartDepthExceeded{observedDepth,
   depthLocation}`.

The remaining RFC §4.6 constraints (mailboxIds ≥ 1; no `headers` array;
intra-Table extraHeaders duplicates; Content-* at top level; body-XOR;
flag-fields false; partId references resolve; no
Content-Transfer-Encoding on body parts; key/value form consistency)
are type-level — they cannot be expressed as input. Server-side
set-errors (`blobNotFound`, `tooManyKeywords`, `tooManyMailboxes`) are
deferred to Part F.

### 3.4. Error Vocabulary

The error vocabulary comprises five types: three for the error
aggregate itself plus two for locating body-part violations.

**Body-part locator types:**

```nim
type BodyPartPath* = distinct seq[int]
  ## Zero-indexed tree path locating a multipart BlueprintBodyPart
  ## within an EmailBlueprintBody.
  ##   ebkStructured: indices into bodyStructure's subParts, from root
  ##     (@[] = bodyStructure itself if it is multipart).
  ##   ebkFlat: first element is 0 (textBody), 1 (htmlBody), or
  ##     2+i (attachments[i]); subsequent elements walk subParts.

type BodyPartLocationKind* = enum
  bplInline      ## located by partId
  bplBlobRef     ## located by blobId
  bplMultipart   ## located by tree path

type BodyPartLocation* = object
  case kind*: BodyPartLocationKind
  of bplInline:    partId*: PartId
  of bplBlobRef:   blobId*: BlobId
  of bplMultipart: path*: BodyPartPath
```

`BodyPartPath` borrows `==`, `$`, `hash`, `len` from the underlying
seq. Indexed access (`[]`) takes a sealed `Idx` (validation.nim) so the
non-negativity invariant is type-level. `items` and `pairs` iterators
yield `int` / `(int, int)` respectively. Mutating operations are not
exposed.

**Error triad:**

```nim
type EmailBlueprintConstraint* = enum
  ebcEmailTopLevelHeaderDuplicate
  ebcBodyStructureHeaderDuplicate
  ebcBodyPartHeaderDuplicate
  ebcTextBodyNotTextPlain
  ebcHtmlBodyNotTextHtml
  ebcAllowedFormRejected
  ebcBodyPartDepthExceeded

type EmailBlueprintError* = object
  case constraint*: EmailBlueprintConstraint
  of ebcEmailTopLevelHeaderDuplicate:
    dupName*: string                  ## lowercase header name
  of ebcBodyStructureHeaderDuplicate:
    bodyStructureDupName*: string
  of ebcBodyPartHeaderDuplicate:
    where*: BodyPartLocation
    bodyPartDupName*: string
  of ebcTextBodyNotTextPlain:
    actualTextType*: string
  of ebcHtmlBodyNotTextHtml:
    actualHtmlType*: string
  of ebcAllowedFormRejected:
    rejectedName*: string
    rejectedForm*: HeaderForm
  of ebcBodyPartDepthExceeded:
    observedDepth*: int               ## first depth exceeding MaxBodyPartDepth
    depthLocation*: BodyPartLocation  ## offending subtree root

type EmailBlueprintErrors* {.ruleOff: "objects".} = object
  ## Pattern A sealed: the underlying seq is module-private; callers
  ## observe read-only via len / items / pairs / [] / head / == / $ /
  ## capacity. Non-empty whenever carried on the err rail — enforced
  ## by the constructor (empty seq would mean "no errors", which is
  ## the ok rail's job).
  errors: seq[EmailBlueprintError]
```

`EmailBlueprintError` and `BodyPartLocation` define explicit `==`
operators (auto-`==` rejects case objects). `EmailBlueprintErrors`
exposes:

- `len`, `==`, `$` — delegated to the underlying seq.
- `items`, `pairs` — yield errors in insertion order.
- `[](e, i: Idx)` — sealed indexed access; out-of-range raises
  `IndexDefect`.
- `head` — first error, guaranteed present by the non-empty invariant.
- `capacity` — exposes the underlying seq capacity for amortised-
  growth regression gates (the accumulation stress tests pin
  `capacity ≤ 2 × N`).

Pattern A sealing forecloses external construction of an empty
`EmailBlueprintErrors`; the only construction site is
`parseEmailBlueprint`, which only emits the err rail when at least one
error is present.

**`message` rendering.**

```nim
func message*(e: EmailBlueprintError): string
```

Total, pure rendering of `(constraint, payload)` to a human-readable
string. Caller-provided string slots (`dupName`, `actualTextType`, …)
flow through a private `clipForMessage` helper that:

1. Truncates to 512 bytes per slot (with a trailing `"..."` marker
   when truncation occurred).
2. Replaces every NUL byte with the literal escape `\x00`.

Each `message` invocation composes at most six clipped slots, keeping
output well under an 8 KiB total budget regardless of caller-controlled
payload size. NUL stripping keeps the output safe for C consumers and
log pipelines that treat `'\x00'` as a string terminator. The function
is total, pure, and bounded — load-bearing properties exercised by
property tests.

**Constraint → enforcement map** (final):

| RFC §4.6 constraint | Enforcement |
|---------------------|-------------|
| 1. `mailboxIds` ≥ 1 | Type-level via `NonEmptyMailboxIdSet` (§4.2) at the signature. |
| 2. No `headers` array | Type-level (field absent from `BlueprintBodyPart`). |
| 3a. No duplicate header within Email top level (convenience field ↔ extraHeaders entry) | Runtime: `ebcEmailTopLevelHeaderDuplicate`. |
| 3b. bodyStructure root cannot duplicate Email top-level headers | Runtime: `ebcBodyStructureHeaderDuplicate`. |
| 3c. No duplicate header within any single `EmailBodyPart` | Runtime: `ebcBodyPartHeaderDuplicate`. |
| 3d. No two `extraHeaders` entries for the same header name | Type-level via `BlueprintEmailHeaderName` / `BlueprintBodyHeaderName` Table-key identity (name-only, form on value). |
| 4. No `Content-*` at Email top level | Type-level via `BlueprintEmailHeaderName` (§4.3). |
| 5. `bodyStructure` XOR flat-list | Type-level via `EmailBlueprintBody` discriminant (§3.2) at the signature. |
| 5a. `ebkFlat` `textBody` must be `text/plain` | Runtime: `ebcTextBodyNotTextPlain`. |
| 5b. `ebkFlat` `htmlBody` must be `text/html` | Runtime: `ebcHtmlBodyNotTextHtml`. |
| 6. `bodyValues` flags false | Type-level via `BlueprintBodyValue` (§4.1). |
| 7. Allowed header forms (name + form pair) | Runtime: `ebcAllowedFormRejected`. |
| 8. partId refs resolve | Type-level via §5.1 denormalisation. |
| 9. No `Content-Transfer-Encoding` | Type-level via `BlueprintBodyHeaderName` (§4.4). |
| 10. `extraHeaders` key/value form consistency | Type-level via `BlueprintHeaderMultiValue` (§4.5) — form lives once, on the value. |
| Body tree depth | Runtime: `ebcBodyPartDepthExceeded` against `MaxBodyPartDepth = 128`. The bound is also enforced defensively by `serde_body.fromJson` for read-model parsing. |

### 3.5. Accessors

Pattern A sealing requires same-name UFCS accessors. One accessor per
`raw*` field:

```nim
func mailboxIds*(bp: EmailBlueprint): NonEmptyMailboxIdSet
func keywords*(bp: EmailBlueprint): KeywordSet
func receivedAt*(bp: EmailBlueprint): Opt[UTCDate]
func fromAddr*(bp: EmailBlueprint): Opt[seq[EmailAddress]]
func to*(bp: EmailBlueprint): Opt[seq[EmailAddress]]
func cc*(bp: EmailBlueprint): Opt[seq[EmailAddress]]
func bcc*(bp: EmailBlueprint): Opt[seq[EmailAddress]]
func replyTo*(bp: EmailBlueprint): Opt[seq[EmailAddress]]
func sender*(bp: EmailBlueprint): Opt[EmailAddress]
func subject*(bp: EmailBlueprint): Opt[string]
func sentAt*(bp: EmailBlueprint): Opt[Date]
func messageId*(bp: EmailBlueprint): Opt[seq[string]]
func inReplyTo*(bp: EmailBlueprint): Opt[seq[string]]
func references*(bp: EmailBlueprint): Opt[seq[string]]
func extraHeaders*(bp: EmailBlueprint):
    Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]
func body*(bp: EmailBlueprint): EmailBlueprintBody
func bodyKind*(bp: EmailBlueprint): EmailBodyKind   ## convenience pass-through
```

**Derived `bodyValues` accessor** (no stored field):

```nim
func bodyValues*(bp: EmailBlueprint): Table[PartId, BlueprintBodyValue]
```

Walks the body tree and collects one `(partId, value)` entry per
`bpsInline` leaf. `bpsBlobRef` leaves contribute no entry. Multipart
nodes recurse. Duplicate `partId`s across the tree resolve via Table
last-wins (documented gap, §7).

### 3.6. Serde — `toJson`

**Module:** `src/jmap_client/mail/serde_email_blueprint.nim`

`EmailBlueprint` serialises unidirectionally to JMAP creation JSON. No
`fromJson`; adding one would create a second construction path bypassing
`parseEmailBlueprint`.

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
  "header:x-custom:asText": "custom-value",
  "textBody": [{"partId": "1", "type": "text/plain"}],
  "bodyValues": {"1": {"value": "Hi there"}}
}
```

#### 3.6.1. Convenience field → JSON key mapping

Every typed convenience field maps to exactly one JMAP wire key and
covers exactly one RFC parsed-form. Callers wanting a different form
(e.g., `asGroupedAddresses` for `From` instead of `asAddresses`) cannot
use the convenience field — they must populate `extraHeaders` directly
with an appropriately-formed `BlueprintEmailHeaderName`.

| Blueprint field | Type | Wire JSON key | Duplicate-check name | RFC parsed-form covered |
|-----------------|------|---------------|----------------------|-------------------------|
| `fromAddr` | `Opt[seq[EmailAddress]]` | `"from"` | `from` | `asAddresses` |
| `to` | `Opt[seq[EmailAddress]]` | `"to"` | `to` | `asAddresses` |
| `cc` | `Opt[seq[EmailAddress]]` | `"cc"` | `cc` | `asAddresses` |
| `bcc` | `Opt[seq[EmailAddress]]` | `"bcc"` | `bcc` | `asAddresses` |
| `replyTo` | `Opt[seq[EmailAddress]]` | `"replyTo"` | `reply-to` | `asAddresses` |
| `sender` | `Opt[EmailAddress]` (singular) | `"sender"` | `sender` | `asAddresses` (single-element wire array) |
| `subject` | `Opt[string]` | `"subject"` | `subject` | `asText` |
| `sentAt` | `Opt[Date]` | `"sentAt"` | `date` | `asDate` |
| `messageId` | `Opt[seq[string]]` | `"messageId"` | `message-id` | `asMessageIds` |
| `inReplyTo` | `Opt[seq[string]]` | `"inReplyTo"` | `in-reply-to` | `asMessageIds` |
| `references` | `Opt[seq[string]]` | `"references"` | `references` | `asMessageIds` |

The "Duplicate-check name" column is the RFC 5322 canonical lowercase
spelling that the smart constructor uses to detect collisions with
`extraHeaders` entries (constraint 3a/3b). The wire key uses JMAP's
camelCase convention.

#### 3.6.2. `extraHeaders` serialisation

Each `extraHeaders` entry is emitted as an individual JSON property
whose key is composed by `composeHeaderKey(name, mv.form, isAll)`
(serde_headers.nim) and whose value is `blueprintMultiValueToJson(mv)`.
The wire key takes the form `"header:<name>[:as<Form>][:all]"` where:

- `<name>` is the lowercase header name (the wrapped string of the
  distinct-string key).
- `:as<Form>` is appended for any `form != hfRaw` (so `hfRaw` is the
  default and emits no form suffix, matching `toPropertyString`).
- `:all` is appended when `multiLen(mv) > 1`.

The wire value shape depends on the form and on cardinality:

- `hfRaw` / `hfText` — `len == 1` emits a plain JString; `len > 1`
  emits a JArray of JString.
- `hfAddresses` — `len == 1` emits a JArray of address objects;
  `len > 1` emits a JArray of JArrays of address objects.
- `hfGroupedAddresses` — `len == 1` emits a JArray of group objects;
  `len > 1` emits a JArray of JArrays of group objects.
- `hfMessageIds` / `hfUrls` — `len == 1` emits a flat JArray of
  JString; `len > 1` emits a JArray of JArrays of JString.
- `hfDate` — `len == 1` emits a JString (RFC 3339); `len > 1` emits
  a JArray of JString.

The smart-constructor `ebcEmailTopLevelHeaderDuplicate` and
`ebcBodyStructureHeaderDuplicate` checks guarantee that the convenience
channel and the `extraHeaders` channel are never both populated for the
same header, so emitted JSON never contains duplicate keys.

#### 3.6.3. `Opt.none` → key omission

`Opt.none` fields emit no key in the JSON output. This is a homomorphism
between two absence representations: `Opt.none` is the domain's
encoding of absence; JSON's encoding of absence is key omission.

This rule matches `BlueprintBodyPart.toJson` from Part C §3.6 — both
are creation-time types encoding the same semantic.

#### 3.6.4. Empty collections → key omission

Empty `keywords`, empty `extraHeaders`, empty derived `bodyValues`,
empty `attachments`, and `Opt.none` `textBody` / `htmlBody` all omit
their keys.

For non-Opt collection fields, the domain has no "absent" state — only
"empty" and "non-empty." RFC 8621 treats absent and empty as
interchangeable on creation. We pick absence uniformly because it
matches architecture §8.4's choice for `bodyValues`, saves wire bytes,
and stays consistent with the Opt-wrapped fields' homomorphism.

#### 3.6.5. Body serialisation

The body tree is serialised according to `bodyKind`:

- **`ebkStructured`**: emits a `"bodyStructure"` key containing the
  recursively-serialised `BlueprintBodyPart` tree.
- **`ebkFlat`**: emits `"textBody"` and `"htmlBody"` keys (each a
  single-element JSON array when `Opt.some`, omitted when `Opt.none`),
  and `"attachments"` as a JSON array (omitted when empty).

`BlueprintBodyPart.toJson` (in `serde_body.nim`) emits `partId` on
inline leaves but does **not** emit the co-located `value`. The
`EmailBlueprint.toJson` function then walks the tree separately
(`bodyValues` accessor) to harvest values into the top-level
`bodyValues` JSON object. The wire RFC has `partId` in the tree and
`value` in the separate top-level `bodyValues` map; the split between
the two `toJson` functions implements that split exactly.

`bodyValues` is emitted with keys equal to the stringified `PartId`s
and values equal to `BlueprintBodyValue.toJson` output (a JSON object
with a single `value` field). The key is omitted when no inline leaves
exist.

To keep the emission helper free of variant-field reads (FFI
panic-surface contract, §6), `EmailBlueprint.toJson` deconstructs the
`EmailBlueprintBody` case object at its own level and passes the
already-extracted `textBody` / `htmlBody` / `attachments` (or
`bodyStructure`) as plain parameters into the per-branch emitters.

---

## 4. Supporting Creation Types

This section defines the supporting types introduced by Part E.
Each exists for the same reason: to collapse what would otherwise be a
runtime RFC §4.6 constraint into a type-level fact, per the
strip-pattern (§2.2).

### 4.1. BlueprintBodyValue

**Module:** `src/jmap_client/mail/body.nim`.

**RFC reference:** §4.1.4 (EmailBodyValue); §4.6 creation constraint 6.

**Module placement.** `BlueprintBodyValue` is grouped logically with the
other "supporting creation types" in §4 but physically lives in
`body.nim` alongside `BlueprintBodyPart` and `BlueprintLeafPart`. Two
reasons drive this:

1. `body.nim`'s `BlueprintLeafPart.bpsInline` branch takes a
   `value: BlueprintBodyValue` field (§5.1), so the type must be
   visible to `body.nim`.
2. `email_blueprint.nim` imports `body.nim` for `BlueprintBodyPart`
   (§3.2). Defining `BlueprintBodyValue` in `email_blueprint.nim`
   would force `body.nim` to import `email_blueprint.nim` in return
   — a mutual import that Nim cannot resolve for object-field type
   checking.

A `BlueprintBodyValue` carries the text content of an inline body part
on creation. It is the creation-time sibling of `EmailBodyValue`,
stripped of the `isEncodingProblem` and `isTruncated` flag fields that
RFC §4.6 mandates be false on creation.

#### 4.1.1. Type Definition

```nim
type BlueprintBodyValue* {.ruleOff: "objects".} = object
  value*: string
```

Plain object with a single public field. No smart constructor — every
string is a valid value. The wire-shape symmetry with JMAP's
`{"value": "..."}` payload is preserved (Nim shape mirrors JSON shape).

#### 4.1.2. Rationale

The read-model `EmailBodyValue` carries two flag fields. On creation,
RFC §4.6 mandates both flags be false; keeping them on a creation type
would add fields with no meaningful semantic variation, require a
runtime check, and duplicate state across read and creation. Stripping
the fields collapses the check into the type.

#### 4.1.3. Serde — `toJson`

**Module:** `src/jmap_client/mail/serde_body.nim`.

```nim
func toJson*(v: BlueprintBodyValue): JsonNode = %*{"value": v.value}
```

Emits `{"value": "<string>"}`. Always exactly one key. No `fromJson`.

### 4.2. NonEmptyMailboxIdSet

**Module:** `src/jmap_client/mail/mailbox.nim`.

**RFC reference:** §4.1.1 (mailboxIds); §4.6 creation constraint 1.

A `NonEmptyMailboxIdSet` is a `distinct HashSet[Id]` guaranteed to
contain at least one element. Used by `EmailBlueprint.mailboxIds` to
encode RFC §4.6's "at least one Mailbox MUST be given" at the type
level.

#### 4.2.1. Type Definition

```nim
type NonEmptyMailboxIdSet* = distinct HashSet[Id]

defineNonEmptyHashSetDistinctOps(NonEmptyMailboxIdSet, Id)
```

The `defineNonEmptyHashSetDistinctOps` template (validation.nim) borrows
the read-model `defineHashSetDistinctOps` operations (`len`, `contains`,
`card`) and adds: `==` (delegated to the underlying HashSet), `$`,
`items` and `pairs` iterators. Mutating operations (`incl`, `excl`) are
deliberately **not** borrowed — mutation could violate the non-empty
invariant. `hash` is also absent: the Nim stdlib `HashSet.hash`
implementation reads `result` before initialising it, which fails the
project's `strictDefs` + `Uninit`-as-error under `{.borrow.}`. The
domain has no use for a non-empty mailbox-id set as a Table key.

#### 4.2.2. Smart Constructor

```nim
func parseNonEmptyMailboxIdSet*(
    ids: openArray[Id]
): Result[NonEmptyMailboxIdSet, ValidationError]
```

Validates `ids.len > 0`. Converts the openArray to an internal
`HashSet[Id]` (deduplicates), wraps via the distinct cast, returns
`ok`. Empty input returns `err(ValidationError)` with `typeName ==
"NonEmptyMailboxIdSet"`.

The error type is the codebase-standard `ValidationError` rather than
Part E's `EmailBlueprintError` — `NonEmptyMailboxIdSet` is a generally
reusable type, and its single-invariant failure does not benefit from
the aggregate error triad.

**Integration with `parseEmailBlueprint`.** Because
`parseEmailBlueprint` takes `mailboxIds: NonEmptyMailboxIdSet`
directly, the empty-mailboxIds failure mode never reaches the
blueprint constructor. The caller is responsible for constructing a
`NonEmptyMailboxIdSet` via `parseNonEmptyMailboxIdSet` first; the
empty case is handled at that prior boundary. The
`EmailBlueprintConstraint` enum therefore contains no
`ebcMailboxIdsEmpty` variant.

#### 4.2.3. Placement within mailbox.nim

`NonEmptyMailboxIdSet` lives alongside the existing `MailboxIdSet`
under an explicit "Mailbox ID Collections" section — two parallel
types with different invariants, kept side-by-side so the "same shape,
different contract" relationship is structurally visible:

```
## Mailbox ID Collections
##
## Two parallel types with different invariants, kept side-by-side so
## the "same shape, different contract" relationship is structurally
## visible.

# 1. MailboxIdSet — general-purpose, empty allowed (read models)
type MailboxIdSet* = distinct HashSet[Id]
defineHashSetDistinctOps(MailboxIdSet, Id)
func initMailboxIdSet*(...) ...

# 2. NonEmptyMailboxIdSet — creation-context, at-least-one enforced
type NonEmptyMailboxIdSet* = distinct HashSet[Id]
defineNonEmptyHashSetDistinctOps(NonEmptyMailboxIdSet, Id)
func parseNonEmptyMailboxIdSet*(...) ...
```

#### 4.2.4. Serde

`toJson` lives in `serde_mailbox.nim` and projects the backing set onto
the same `{"id": true, ...}` wire shape as `MailboxIdSet`. There is no
`fromJson` (creation types are unidirectional).

### 4.3. BlueprintEmailHeaderName

**Module:** `src/jmap_client/mail/headers.nim`, "Creation-Model Header
Vocabulary" section.

**RFC reference:** §4.1.3 (header-property syntax); §4.6 creation
constraint 4 ("`Content-*` headers MUST NOT be set on the Email
object itself"); §4.6 "no duplicate header representation" applied to
the intra-`extraHeaders` axis (Table key uniqueness).

A `BlueprintEmailHeaderName` is a lowercase RFC 5322-conforming header
name guaranteed not to begin with `content-`. Used as the key type of
`EmailBlueprint.extraHeaders`, where the Table key's name-granularity
identity encodes the intra-Table no-duplicates rule at the type level.
The form and `:all` semantics live on the paired
`BlueprintHeaderMultiValue` value (§4.5), not on the key.

#### 4.3.1. Type Definition

```nim
type BlueprintEmailHeaderName* = distinct string
defineStringDistinctOps(BlueprintEmailHeaderName)
```

Borrows `==`, `$`, `hash`, `len`. Equality is on the wrapped lowercase
string — two keys are equal iff their names match. The Table enforces
intra-extraHeaders uniqueness:
`parseBlueprintEmailHeaderName("X-Custom")` and
`parseBlueprintEmailHeaderName("x-custom")` produce equal values that
cannot coexist in the Table.

#### 4.3.2. Smart Constructor

```nim
func parseBlueprintEmailHeaderName*(
    name: string
): Result[BlueprintEmailHeaderName, ValidationError]
```

**Input contract:** accepts the header name in any case, without any
`header:` prefix or form suffix. Wire-format strings like
`"header:X-Custom:asText"` are rejected — the colon is not a valid
RFC 5322 `ftext` character. Callers constructing a name from a server-
provided wire string should use `parseHeaderPropertyName` (Part C §2.3)
and extract `.name`.

**Validates** (strict; this is client-constructed data):

1. Non-empty (`bnvEmpty`).
2. Every character is printable ASCII (octets 0x21–0x7E inclusive)
   (`bnvNonPrintable`).
3. No colon (`:`, octet 0x3A) — RFC 5322 §3.6.8 `ftext`
   (`bnvContainsColon`).
4. Normalised name does not begin with `"content-"` after lowercase
   normalisation — RFC 8621 §4.6 constraint 4 (`bnvContentPrefix`).

**Normalises** input to lowercase via `toLowerAscii` (locale-
independent byte-level operation; never `unicode.toLower`).

The `BlueprintNameViolation` enum (five variants total —
`bnvEmpty`, `bnvNonPrintable`, `bnvContainsColon` produced by the
common `detectBlueprintCommon` helper; `bnvContentPrefix` and
`bnvContentTransferEncoding` produced parser-specifically) and the
single `toValidationError(typeName: string, raw: string)` translator
form the shared boundary between the two parsers. The translator
takes the outer `typeName` as a parameter so each parser reports its
own type name while sharing the wire-message text.

There is **no** `parseBlueprintEmailHeaderNameFromServer` lenient
sibling. Creation vocabulary is unidirectional — admitting a lenient
parser would open a second construction path through the creation
aggregate.

#### 4.3.3. Serde

```nim
defineDistinctStringToJson(BlueprintEmailHeaderName)
defineDistinctStringFromJson(BlueprintEmailHeaderName,
                             parseBlueprintEmailHeaderName)
```

`toJson` projects the wrapped lowercase name directly to a JSON string.
At the `EmailBlueprint.toJson` layer, the wire-key form
`"header:<name>:as<Form>[:all]"` is constructed by `composeHeaderKey`
from the name and the paired `BlueprintHeaderMultiValue.form`. The
`fromJson` instantiation is generated by the shared template; it is
not exercised by the unidirectional creation path.

### 4.4. BlueprintBodyHeaderName

**Module:** `src/jmap_client/mail/headers.nim`, "Creation-Model Header
Vocabulary" section.

**RFC reference:** §4.1.3; §4.6 creation constraint 9
("`Content-Transfer-Encoding` MUST NOT be given in `EmailBodyPart`");
§4.6 intra-Table uniqueness.

A `BlueprintBodyHeaderName` is a lowercase RFC 5322-conforming header
name guaranteed not to be `content-transfer-encoding`. Used as the key
type of `BlueprintBodyPart.extraHeaders`.

```nim
type BlueprintBodyHeaderName* = distinct string
defineStringDistinctOps(BlueprintBodyHeaderName)

func parseBlueprintBodyHeaderName*(
    name: string
): Result[BlueprintBodyHeaderName, ValidationError]
```

Validation mirrors §4.3.2 (non-empty, printable ASCII, no colon,
lowercase normalisation, strict-only) but the forbidden-name rule
differs: exact match on `"content-transfer-encoding"` after
normalisation (`bnvContentTransferEncoding`). `Content-Type`,
`Content-Disposition`, etc. are permitted on body parts (RFC 2045
locates them there).

Serde mirrors §4.3.3.

#### 4.4.1. Comparison with BlueprintEmailHeaderName

| Aspect | `BlueprintEmailHeaderName` | `BlueprintBodyHeaderName` |
|--------|----------------------------|---------------------------|
| Used as key of | `EmailBlueprint.extraHeaders` | `BlueprintBodyPart.extraHeaders` |
| RFC rule encoded | §4.6 constraint 4 + intra-Table uniqueness | §4.6 constraint 9 + intra-Table uniqueness |
| Rejection criterion | name starts with `"content-"` | name equals `"content-transfer-encoding"` |
| Context | Email object top-level headers | MIME body-part headers |
| Underlying wrap | `distinct string` (name-only) | `distinct string` (name-only) |

The two distinct types are deliberately non-unified: cross-inserting
one context's name into the other context's Table is a compile error.

### 4.5. BlueprintHeaderMultiValue

**Module:** `src/jmap_client/mail/headers.nim`, "Creation-Model Header
Vocabulary" section.

**RFC reference:** §4.1.2 (parsed forms); §4.1.3 (`:all` suffix
semantics); §4.6 "no duplicate header representation" (intra-Table
axis).

A `BlueprintHeaderMultiValue` carries one or more values for a single
header field, all sharing one parsed form. It is the creation-model
counterpart to `HeaderValue` (Part C §2.4), extended along two
dimensions simultaneously: it carries a seq of values (to express the
`:all` suffix's multi-instance semantic), and it pairs with a
name-only Table key, so the form lives once on the value, not
redundantly on both sides.

#### 4.5.1. Type Definition

```nim
type BlueprintHeaderMultiValue* {.ruleOff: "objects".} = object
  ## seq.len == 1  → single-instance header (wire: "header:X[:asForm]").
  ## seq.len >  1  → multi-instance header (wire: "header:X:asForm:all").
  case form*: HeaderForm
  of hfRaw:              rawValues*:      NonEmptySeq[string]
  of hfText:             textValues*:     NonEmptySeq[string]
  of hfAddresses:        addressLists*:   NonEmptySeq[seq[EmailAddress]]
  of hfGroupedAddresses: groupLists*:     NonEmptySeq[seq[EmailAddressGroup]]
  of hfMessageIds:       messageIdLists*: NonEmptySeq[seq[string]]
  of hfDate:             dateValues*:     NonEmptySeq[Date]
  of hfUrls:             urlLists*:       NonEmptySeq[seq[string]]
```

Two type-level invariants are structurally enforced:

- **Form uniformity** — the case discriminant ensures every value in
  the object shares a single `HeaderForm`.
- **Non-emptiness** — each variant's outer seq is `NonEmptySeq[T]`
  (§4.6).

The seven variants share five distinct payload types
(`string`, `seq[string]`, `seq[EmailAddress]`, `seq[EmailAddressGroup]`,
`Date`), so `defineNonEmptySeqOps` is instantiated exactly five times
in `headers.nim` to cover all variants.

The hfMessageIds / hfDate / hfUrls variants drop the `Opt[...]`
wrapping that the read-model `HeaderValue` uses for server-side parse
failures (creation never signals a parse failure — if the client lacks
a valid value, they don't set the header).

#### 4.5.2. Constructors

Two families of constructors:

**`*Multi`** — take a seq of values and delegate to `parseNonEmptySeq`
for the non-empty invariant. One per form:

```nim
func rawMulti*(values: seq[string]):
    Result[BlueprintHeaderMultiValue, ValidationError]
func textMulti*(values: seq[string]):
    Result[BlueprintHeaderMultiValue, ValidationError]
func addressesMulti*(values: seq[seq[EmailAddress]]):
    Result[BlueprintHeaderMultiValue, ValidationError]
func groupedAddressesMulti*(values: seq[seq[EmailAddressGroup]]):
    Result[BlueprintHeaderMultiValue, ValidationError]
func messageIdsMulti*(values: seq[seq[string]]):
    Result[BlueprintHeaderMultiValue, ValidationError]
func dateMulti*(values: seq[Date]):
    Result[BlueprintHeaderMultiValue, ValidationError]
func urlsMulti*(values: seq[seq[string]]):
    Result[BlueprintHeaderMultiValue, ValidationError]
```

**`*Single`** — zero-ceremony total constructors for the common
single-value case. `@[value]` is statically non-empty so the helpers
take the direct distinct-coercion path (no `tryGet` / `Result`
ceremony needed):

```nim
func rawSingle*(value: string): BlueprintHeaderMultiValue
func textSingle*(value: string): BlueprintHeaderMultiValue
func addressesSingle*(value: seq[EmailAddress]): BlueprintHeaderMultiValue
func groupedAddressesSingle*(value: seq[EmailAddressGroup]):
    BlueprintHeaderMultiValue
func messageIdsSingle*(value: seq[string]): BlueprintHeaderMultiValue
func dateSingle*(value: Date): BlueprintHeaderMultiValue
func urlsSingle*(value: seq[string]): BlueprintHeaderMultiValue
```

Callers may also construct via the case object directly if they already
hold a `NonEmptySeq[T]`.

#### 4.5.3. Serde

`BlueprintHeaderMultiValue` has no standalone wire identity — its wire
key is composed at the consumer aggregate level. `serde_headers.nim`
exposes three public primitives:

```nim
func multiLen*(m: BlueprintHeaderMultiValue): int
  ## Length of the underlying NonEmptySeq for any variant.

func composeHeaderKey*[T: BlueprintEmailHeaderName or BlueprintBodyHeaderName](
    name: T, form: HeaderForm, isAll: bool
): string
  ## Compose "header:<name>[:as<Form>][:all]". Form suffix omitted for
  ## hfRaw (matches toPropertyString convention). :all appended iff
  ## the caller passes isAll=true (typically when multiLen > 1).

func blueprintMultiValueToJson*(m: BlueprintHeaderMultiValue): JsonNode
  ## Variant dispatcher; cardinality-aware per §3.6.2.
```

`composeHeaderKey` is generic over both blueprint header-name types
because the wire rule is one fact — the two name types share the
newtype for context safety, not for wire-shape divergence. The
dispatcher and the cardinality probes are public so both consumer
aggregates (`EmailBlueprint.toJson` and `BlueprintBodyPart.toJson`)
can compose the wire output uniformly.

There is no `fromJson`.

### 4.6. NonEmptySeq[T]

**Module:** `src/jmap_client/primitives.nim`.

`NonEmptySeq[T]` is a generic distinct seq with an at-least-one
invariant. Used by `BlueprintHeaderMultiValue` (§4.5) and available for
any future code path that requires a non-empty sequence.

#### 4.6.1. Type Definition

```nim
type NonEmptySeq*[T] = distinct seq[T]

template defineNonEmptySeqOps*(T: typedesc) =
  ## Borrows the read-only operations legitimate for NonEmptySeq[T].
  ## Mutating ops (add, setLen, del) intentionally absent.
  func `==`*(a, b: NonEmptySeq[T]): bool {.borrow.}
  func `$`*(a: NonEmptySeq[T]): string {.borrow.}
  func hash*(a: NonEmptySeq[T]): Hash {.borrow.}
  func len*(a: NonEmptySeq[T]): int {.borrow.}
  func `[]`*(a: NonEmptySeq[T], i: Idx): lent T
  func contains*(a: NonEmptySeq[T], x: T): bool
  iterator items*(a: NonEmptySeq[T]): T
  iterator pairs*(a: NonEmptySeq[T]): (int, T)
```

Indexed access (`[]`) takes a sealed `Idx` so non-negativity is
type-level. Upper-bound violations still raise `IndexDefect` (a
defect, not a `CatchableError`). `contains` has an explicit body
because `{.borrow.}` unwraps both distinct types and breaks when `T`
is itself distinct (e.g. `Date`).

#### 4.6.2. Smart Constructor

```nim
func parseNonEmptySeq*[T](s: seq[T]):
    Result[NonEmptySeq[T], ValidationError]
```

Rejects empty input. The `typeName` field on the returned
`ValidationError` is `"NonEmptySeq"` (not parametrised on `T`,
matching the codebase convention for distinct-type families).

#### 4.6.3. `head`

```nim
func head*[T](a: NonEmptySeq[T]): lent T
```

Top-level generic function, separate from the per-`T` template — `T`
is inferrable from the argument so no per-instantiation template
expansion is required. `head` is the canonical reader for the
"first element guaranteed present" idiom; it reads cleaner than
`a[idx(0)]` and avoids `tryGet`.

---

## 5. Cross-Part Modifications

Part E's decisions require additive modifications to earlier parts and
to the primitives module. This section catalogues each change so
implementers can locate them at a glance.

Modified modules span three parts:

- Part C (`body.nim`, `serde_body.nim`, `headers.nim`) — §5.1–§5.4
- Part B (`mailbox.nim`) — §5.5
- Layer 1 primitives (`primitives.nim`) — §5.6

### 5.1. body.nim — `BlueprintLeafPart` and the `value` field

**Module:** `src/jmap_client/mail/body.nim`.

`BlueprintBodyPart`'s leaf branch carries a separate `BlueprintLeafPart`
sub-object rather than inlining the inner case. Nim's `strictCaseObjects`
flow analysis does not propagate variant-field facts across nested case
objects on the same type — hoisting the inner case into its own type is
the structural fix that lets each discriminator be tracked independently.

```nim
type BlueprintLeafPart* {.ruleOff: "objects".} = object
  case source*: BlueprintPartSource
  of bpsInline:
    partId*: PartId
    value*: BlueprintBodyValue       ## co-located content (§5.1)
  of bpsBlobRef:
    blobId*: BlobId
    size*: Opt[UnsignedInt]          ## optional, ignored by server
    charset*: Opt[string]

type BlueprintBodyPart* {.ruleOff: "objects".} = object
  contentType*: string
  name*: Opt[string]
  disposition*: Opt[ContentDisposition]
  cid*: Opt[string]
  language*: Opt[seq[string]]
  location*: Opt[string]
  extraHeaders*: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]
  case isMultipart*: bool
  of true:
    subParts*: seq[BlueprintBodyPart]
  of false:
    leaf*: BlueprintLeafPart
```

The co-located `value: BlueprintBodyValue` field on `bpsInline`
removes the need for a separate `bodyValues: Table[PartId,
BlueprintBodyValue]` field on `EmailBlueprint`. References cannot be
unresolved because there is no separate structure for them to resolve
against — the value is structurally present at the inline part.

`charset` and `size` live exclusively on the `bpsBlobRef` branch —
they have no meaning for inline parts (whose content is the
`BlueprintBodyValue` directly) and no meaning for multipart containers.

**Module-level constants and shared types:**

```nim
const MaxBodyPartDepth* = 128
  ## Maximum nesting depth of a BlueprintBodyPart tree.
  ## parseEmailBlueprint enforces this via ebcBodyPartDepthExceeded;
  ## EmailBodyPart's read-side fromJson uses the same bound defensively
  ## per Postel's law.

type BlueprintPartSource* = enum
  bpsInline    ## partId → bodyValues lookup
  bpsBlobRef   ## blobId → uploaded blob reference
```

### 5.2. body.nim — extraHeaders retyped

`BlueprintBodyPart.extraHeaders` keys to a `BlueprintBodyHeaderName`
(name-only distinct string) and values to a `BlueprintHeaderMultiValue`
(case object carrying form + non-empty seq of values):

```nim
extraHeaders*: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]
```

Three constraints become type-level simultaneously: no
`Content-Transfer-Encoding` (constraint 9, on the key type); key/value
form consistency (form lives once, on the value); no duplicate header
in extraHeaders (the intra-Table axis — the Table key's identity is
name-only).

### 5.3. headers.nim — creation-model header vocabulary

`headers.nim` is split into two labelled sections:

```
## ──────────────────────────────────────────────
## Read-Model Header Vocabulary (Part C / D)
## ──────────────────────────────────────────────
## HeaderForm, HeaderPropertyKey, HeaderValue, EmailHeader,
## allowedForms, parseHeaderPropertyName, EmailHeader smart ctor, serde

## ──────────────────────────────────────────────
## Creation-Model Header Vocabulary (Part E §4.3–§4.5, §5.3)
## ──────────────────────────────────────────────
## BlueprintEmailHeaderName  (§4.3) + parseBlueprintEmailHeaderName
## BlueprintBodyHeaderName   (§4.4) + parseBlueprintBodyHeaderName
## BlueprintHeaderMultiValue (§4.5)
## defineNonEmptySeqOps instantiations (string, Date, seq[EmailAddress],
##                                      seq[EmailAddressGroup], seq[string])
## *Multi and *Single constructors (one per form)
```

The two parsers share a private `BlueprintNameViolation` enum (five
variants: `bnvEmpty`, `bnvNonPrintable`, `bnvContainsColon`,
`bnvContentPrefix`, `bnvContentTransferEncoding`),
`detectBlueprintCommon` helper, and `toValidationError(typeName,
raw)` translator (DRY across the two parsers).

The labelled-section pattern mirrors `mailbox.nim`'s treatment of
`MailboxIdSet` / `NonEmptyMailboxIdSet`: parallel worlds (read vs
creation) made structurally visible at the file level.

### 5.4. serde_headers.nim — composition primitives, and serde_body.nim — toJson split

**Module:** `src/jmap_client/mail/serde_headers.nim`.

Adds the public composition primitives `multiLen`, `composeHeaderKey`,
and `blueprintMultiValueToJson` (§4.5.3) plus distinct-string serde
for `BlueprintEmailHeaderName` and `BlueprintBodyHeaderName`. These are
the shared building blocks both consumer aggregates use to emit the
wire form.

**Module:** `src/jmap_client/mail/serde_body.nim`.

`BlueprintBodyPart.toJson` emits `partId` only on the `bpsInline`
branch and does **not** emit the co-located `value`. The value is
harvested separately by `EmailBlueprint.toJson` walking the tree and
collecting values into a top-level `bodyValues` JSON object (the
derived `bodyValues` accessor on `EmailBlueprint`).

`BlueprintBodyPart.toJson` also iterates `extraHeaders` and uses
`composeHeaderKey` / `blueprintMultiValueToJson` (from
`serde_headers.nim`) to emit the wire keys and values — the same
primitives `EmailBlueprint.toJson` uses for its own `extraHeaders`.

The split between part-level and aggregate-level JSON exactly matches
the wire RFC: `partId` lives in the body-part tree; `value` lives in
the separate top-level `bodyValues` map.

### 5.5. mailbox.nim — NonEmptyMailboxIdSet

Adds `NonEmptyMailboxIdSet`, `parseNonEmptyMailboxIdSet`, and the
associated borrowed operations under the "Mailbox ID Collections"
labelled section per §4.2.3. Additive — no existing call site is
affected; only Part E's new code (`EmailBlueprint.mailboxIds`)
depends on it.

### 5.6. primitives.nim — NonEmptySeq[T]

Adds the generic `NonEmptySeq[T]` distinct type, the
`parseNonEmptySeq[T]` smart constructor, the
`defineNonEmptySeqOps[T]` borrowed-operations template, and the
generic `head[T]` accessor (§4.6). Additive — initially used by
`BlueprintHeaderMultiValue` and available for any future non-empty
sequence invariant.

`NonEmptyMailboxIdSet` (§4.2) remains a `distinct HashSet[Id]`, not a
`distinct seq[Id]`, because its container kind is `HashSet` (different
operation set, no ordering); it does not collapse into
`NonEmptySeq[Id]`.

---

## 6. Test Specification

The test suite for Part E covers the smart constructor and supporting
types across five tiers. Tests are organised by category to mirror the
file layout and to keep file sizes within nimalyzer's complexity
budget.

### 6.1. Test Files

| File | Coverage |
|------|----------|
| `tests/unit/mail/temail_blueprint.nim` | `EmailBlueprint` smart constructor, accessors, derived `bodyValues`, `BlueprintBodyValue` single-field serde, and value-type non-aliasing observations on `NonEmptyMailboxIdSet` and `NonEmptySeq[T]`. |
| `tests/unit/mail/theaders_blueprint.nim` | `BlueprintEmailHeaderName`, `BlueprintBodyHeaderName`, `BlueprintHeaderMultiValue` — case-variant equality, forbidden-name rejection, character validation, `*Multi`/`*Single` constructor coverage. |
| `tests/unit/mail/tblueprint_error_triad.nim` | `BodyPartPath`, `BodyPartLocation`, `EmailBlueprintError.message` rendering — variant equality, depth-coupling, bounded clipping, NUL-stripping. |
| `tests/unit/mail/tblueprint_compile_time.nim` | `assertNotCompiles` scenarios pinning the type-level eliminations from §3.4: Pattern A sealing, body-XOR discriminant, signature-level input types, intra-Table dedup, mutating-op refusal, public export surface, absence of `ebcNoBodyContent` / `*FromServer` parsers. |
| `tests/unit/mail/tmailbox.nim` (extension) | `NonEmptyMailboxIdSet` smart constructor and dedup. |
| `tests/unit/tprimitives.nim` (extension) | `NonEmptySeq[T]` smart constructor and borrowed-op coverage. |
| `tests/serde/mail/tserde_email_blueprint.nim` | Top-level shape, convenience-field-to-wire-key mapping, body serialisation, `bodyValues` harvest. |
| `tests/serde/mail/tserde_email_blueprint_wire.nim` | RFC §4.6 wire-format conformance: no `Content-*` at top level, no `headers` array on body parts, the `:all` suffix, every form's wire shape. |
| `tests/serde/mail/tserde_email_blueprint_adversarial.nim` | Byte-level adversarial inputs through the serde path: NUL / CRLF / BOM / homoglyph payloads via convenience fields and `extraHeaders`; Turkish-locale invariance; JSON-injection probes. |
| `tests/property/tprop_mail_e.nim` | Eighteen properties: totality of `parseEmailBlueprint` and `toJson`, determinism, accumulating-error count and ordering, `toJson` shape invariants, key-omission, injectivity, `bodyValues`/tree correspondence, lowercase-normalisation idempotence, adversarial totality, `message` purity, harvest correctness, message bounded length, JSON re-parsability, `BodyPartPath` depth coupling, insertion-order-insensitive equality, hash-seed cross-process determinism. |
| `tests/stress/tadversarial_blueprint.nim` | Depth × breadth stress, hash-collision DoS probe, error-accumulation stress (10 000 violations of one variant), concurrent construction across threads, cross-process iteration-order determinism, ARC copy semantics on `NonEmptySeq`. |
| `tests/compliance/tffi_panic_surface.nim` | Compile-time macro contract: walks the AST of `email_blueprint.nim` and `serde_email_blueprint.nim` and rejects any case-object field access that does not sit inside a `case` branch on the matching discriminant. Defends the L1/L2 promise that no `FieldDefect` path is reachable through the creation aggregate (relevant to `--panics:on` — see `nim-ffi-boundary.md`). |
| `tests/compliance/tmail_e_reexport.nim` | Compile-time smoke test: every Part E public symbol named in §1.5 is referenced through `import jmap_client` via `static: doAssert declared(...)` blocks (types, functions, templates) and a `_touchAccessors` proc (UFCS accessor names). A missing `export` at any hop in the re-export chain (`jmap_client.nim` → `jmap_client/mail.nim` → `mail/types.nim` / `mail/serialisation.nim`) surfaces as a compile error. |

### 6.2. Test Categories

**Unit.** Specific scenarios per smart-constructor invariant and per
type. Each `EmailBlueprintConstraint` variant has at least one
positive-trigger scenario asserting the variant + payload via
`assertBlueprintErrContains`. Includes embedded `assertNotCompiles`
scenarios for type-level invariants.

**Serde.** `toJson` output shape per field, variant, and RFC
constraint. Adversarial serde scenarios use the `assertJsonStringEquals`
template to verify byte-level escaping of CRLF / NUL / BOM through
`std/json`.

**Property-based.** Eighteen properties using the project's
`mproperty.nim` infrastructure (fixed seed, edge-biased generators,
tiered trial counts). Each property names its generator, trial count,
and the principle defended.

**Adversarial.** Byte-level, structural, resource-exhaustion, and
FFI-panic-surface edge cases.

**Compliance.** Two compile-time gates: an AST-walking macro
(`tffi_panic_surface.nim`) that rejects any case-object field access
outside a matching `case` branch (the strongest form of the
panic-surface contract); and a re-export smoke test
(`tmail_e_reexport.nim`) that pins every §1.5 public symbol to the
top-level `jmap_client` import path so a missing `export` at any hop
fails to compile.

### 6.3. Test Infrastructure

Under `tests/mfixtures.nim` and `tests/mproperty.nim` Part E adds:

- **Factories** for every Part E type, covering the 7-step protocol
  (parse, make, toJson, unit, serde, property, gen):
  `makeBlueprintEmailHeaderName`, `makeBlueprintBodyHeaderName`,
  `makeBhmvRaw` / `makeBhmvText` / `makeBhmvAddresses` /
  `makeBhmvGroupedAddresses` / `makeBhmvMessageIds` / `makeBhmvDate` /
  `makeBhmvUrls` (one per `HeaderForm` variant) plus their
  `*Single` siblings (`makeBhmvRawSingle`, `makeBhmvTextSingle`, …),
  `makeNonEmptyMailboxIdSet` (2-element default to exercise dedup),
  `makeNonEmptySeq[T]`, `makeBlueprintBodyValue`,
  `makeBlueprintBodyPartInline`, `makeBlueprintBodyPartBlobRef`,
  `makeBlueprintBodyPartMultipart`, `makeEmailBlueprint` /
  `makeFullEmailBlueprint`, `makeFlatBody` / `makeStructuredBody`
  (thin wrappers around the module helpers, never bypassing them),
  `makeBlueprintWithDuplicateAt`, `makeBodyPartLocationInline` /
  `makeBodyPartLocationBlobRef` / `makeBodyPartLocationMultipart`
  (one per `BodyPartLocationKind` variant),
  `makeBlueprintEmailHeaderMap` / `makeBlueprintBodyHeaderMap`
  (collapses repeated inline Table construction into single calls),
  `makeBodyPartPath`, `makeSpineBodyPart`, plus the function-level
  helpers `withLocale` (sets `LC_CTYPE` for the Turkish-locale
  invariance probe) and `adversarialHashCollisionNames`.
- **Generators**: `genBlueprintEmailHeaderName` /
  `genInvalidBlueprintEmailHeaderName`,
  `genBlueprintBodyHeaderName` / its negative,
  `genBlueprintHeaderMultiValue`, `genNonEmptyMailboxIdSet`,
  `genNonEmptySeq[T]`, `genBlueprintBodyValue`,
  `genBlueprintBodyPart`, `genEmailBlueprintBody`,
  `genEmailBlueprint`, `genBlueprintErrorTrigger`,
  `genBodyPartPath` / `genBodyPartLocation`,
  `genEmailBlueprintError` / `genEmailBlueprintErrors`,
  `genEmailBlueprintDelta`, `genAdversarialBlueprintArgs`,
  `genBlueprintInsertionPermutation`. Adversarial generators reuse
  the existing `genMaliciousString`, `genArbitraryByte`, and
  `genLongArbitraryString` toolkit.
- **Equality helpers**: `emailBlueprintErrorEq`,
  `emailBlueprintErrorsSetEq` (set/multiset equality, ignores order
  — used for "all six variants present" assertions),
  `emailBlueprintErrorsOrderedEq` (ordered/element-wise equality —
  used for ordering-determinism properties), `bodyPartLocationEq`,
  `emailBlueprintBodyEq`, `blueprintBodyPartEq`,
  `blueprintHeaderMultiValueEq`, `emailBlueprintEq` (reuses the
  generic `convStringHeadersEq[T]` / `convAddressHeadersEq[T]` for
  the convenience-field decomposition), `nonEmptyMailboxIdSetEq`.
- **Assertion templates**: `assertBlueprintErr` (`Result` is err and
  contains a given variant), `assertBlueprintErrContains`
  (variant + field-level payload), `assertBlueprintErrCount`
  (exact-N accumulation), `assertBlueprintOkEq`,
  `assertJsonKeyAbsent`, `assertJsonHasHeaderKey` /
  `assertJsonMissingHeaderKey`, `assertBlueprintErrAny`
  (multiple distinct variants),
  `assertBoundedRatio` (HashDoS guard),
  `assertJsonStringEquals` (byte-level escape verification).

Every Part E type passes the seven-step protocol (parse / make /
toJson / unit / serde / property / gen). Every `make*` factory is
consumed by at least two scenarios.

---

## 7. Decision Traceability Matrix

The DTM lists every design decision with its considered options, the
chosen option, and the principles driving the choice. Decisions are
numbered and tagged with the original R-code where one exists.

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|----------|--------------------|--------|---------------------|
| E1 | Module placement for `EmailBlueprint` + serde | A) Extend `email.nim` + `serde_email.nim`, B) New `email_blueprint.nim` + `serde_email_blueprint.nim`, C) Type in new module, serde in existing | B — new dedicated modules with the explicit `email_` prefix for self-documentation | DDD; duplicated appearance ≠ duplicated knowledge; make the right thing easy. |
| E2 | `BlueprintBodyValue` type | A) Reuse `EmailBodyValue` + flag-false check, B) New `BlueprintBodyValue` (value-only), C) Reuse + reusable predicate | B — plain object `{ value: string }` mirroring the `BlueprintBodyPart`-vs-`EmailBodyPart` asymmetry one level down | Make illegal states unrepresentable; DDD; parse-don't-validate. |
| E3 | API surface | A) Smart ctor only, B) Smart ctor + fluent builder, C) Smart ctor + preset wrappers | A — single `parseEmailBlueprint` with named parameters | Constructors are privileges; parse once at the boundary; YAGNI. |
| E4 | Field sealing | A) Plain public, B) Pattern A sealed (`raw*` + UFCS), C) Mixed | B — Pattern A | Make illegal states unrepresentable; parse once at the boundary. |
| E5 | `from` field naming | A) `fromAddr`, B) Backtick `` `from` ``, C) `fromAddresses` | A — matches `contentType ↔ "type"` from Part C | DDD; code reads like the spec; one source of truth. |
| E6 | Sender cardinality | A) Uniform `Opt[seq[EmailAddress]]`, B) Singular `Opt[EmailAddress]`, C) Shared AtMostOne wrapper | B — singular per RFC 5322 §3.6.2; serde owns the wire asymmetry (single-element JArray) | Make illegal states unrepresentable; duplicated appearance ≠ duplicated knowledge. |
| E7 | `receivedAt` type | A) `Opt[UTCDate]`, B) `UTCDate` required, C) `Opt[UTCDate]` + helper | A — `Opt.none` = "defer to server clock" as a positively-meaningful state | Code reads like the spec; Postel's law; one source of truth. |
| E8 | Error accumulation | A) `Result[_, seq[ValidationError]]`, B) Single `ValidationError`, C) Extended `ValidationError` sum-type, D) Domain-specific triad | D — `EmailBlueprintConstraint` enum + `EmailBlueprintError` case object + `EmailBlueprintErrors` Pattern A sealed aggregate | Errors are part of the API; newtype everything that has meaning; make state transitions explicit. |
| E9 | `EmailBlueprintErrors` shape | A) `distinct seq[EmailBlueprintError]`, B) Pattern A sealed object with module-private seq, C) Plain public seq | B — sealed object exposing read-only `len` / `items` / `pairs` / `[]: Idx` / `head` / `==` / `$` / `capacity`. Empty-seq constructions outside the module fail to compile; the non-empty invariant is enforced by the smart constructor. | Make illegal states unrepresentable; constructors are privileges; one source of truth (the Pattern A boundary). |
| E10 | Error location representation | A) Just constraint + message, B) Optional per-location fields, C) Sum-type location field, D) Case object discriminated by the constraint enum | D — `EmailBlueprintError` is the case object; `BodyPartLocation` is a separate case object reused on the `ebcBodyPartHeaderDuplicate` and `ebcBodyPartDepthExceeded` variants. `message` is a pure func, not a stored field. | Make illegal states unrepresentable; one source of truth; code reads like the spec. |
| E11 | "At least one of textBody/htmlBody" constraint | A) Drop (RFC-faithful), B) Keep as `ebcNoBodyContent`, C) Separate optional validator | A — RFC §4.6 does not mandate it; an email with no body content is legal | Code reads like the spec; parse-don't-validate. |
| E12 | partId reference validation | A) Forward resolution only, B) Bidirectional, C) Forward + warning, D) Denormalise `bodyValues` into the tree | D — co-located `value: BlueprintBodyValue` on the `bpsInline` branch (via `BlueprintLeafPart`); `bodyValues` becomes a derived accessor; constraint 8 disappears | Make illegal states unrepresentable; one source of truth; parse once at the boundary. |
| E13 | Content-Transfer-Encoding + Content-* enforcement | A) Tree-walk in smart ctor, B) `BlueprintBodyPart` smart ctor, C) Distinct Table type, D) Two distinct header-name types | D — name-only `BlueprintEmailHeaderName` (forbids `content-*`) and `BlueprintBodyHeaderName` (forbids `content-transfer-encoding`); form lives on the paired `BlueprintHeaderMultiValue` value | Make illegal states unrepresentable; newtype everything that has meaning; parse once at the boundary. |
| E14 | `MailboxIdSet` at-least-one invariant | A) Smart ctor only, B) New `NonEmptyMailboxIdSet` distinct type at the signature, C) Tighten `MailboxIdSet` itself | B — `parseEmailBlueprint` takes `mailboxIds: NonEmptyMailboxIdSet` directly; the empty case is handled at the prior smart-ctor boundary | Make illegal states unrepresentable; Postel's law (`MailboxIdSet` stays lenient); newtype everything that has meaning. |
| E15 | `NonEmptyMailboxIdSet` home | A) `mail/mailbox.nim` alongside `MailboxIdSet`, B) `email_blueprint.nim` with the consumer, C) New `mail/mailbox_ids.nim` | A — under a labelled "Mailbox ID Collections" section so the parallel between the two types is structurally visible | DDD; duplicated appearance ≠ duplicated knowledge. |
| E16 | Convenience-field serde mapping | A) JMAP convenience keys, B) Wire `header:*` keys uniformly, C) Configurable per call | A — with explicit field-to-wire-key mapping table (§3.6.1) | Code reads like the spec; one source of truth; make the wrong thing hard. |
| E17 | `Opt.none` serde | A) Omit key, B) Emit `null`, C) Mixed per field | A — homomorphism between absence representations | One source of truth; code reads like the spec; parse once at the boundary. |
| E18 | Empty-collection serde | A) Omit all empty, B) Emit `{}`, C) Mixed | A — pick-one-form-per-fact (empty ≠ absent at the type level, but the wire treats them interchangeably; we pick absence uniformly) | One source of truth; YAGNI. |
| E19 | Body-XOR enforcement | A) Runtime check with new `ebcBodyPathConflict` variant, B) Separate error type for pre-checks, C) Case-object input type | C — `EmailBlueprintBody` case object with `flatBody()` / `structuredBody()` helpers | Make illegal states unrepresentable; make state transitions explicit; parse once at the boundary. |
| E20 | bodyStructure-vs-top-level duplicate scope (RFC §4.6 lines 2866–2868) | A) bodyStructure ROOT only, B) Whole bodyStructure subtree, C) Root + immediate children | A — ROOT only; matches the RFC's singular phrasing and the wire-level semantics where only the bodyStructure root's MIME headers merge with Email top-level headers on the message header block. Sub-parts have scoped header blocks inside MIME boundaries and are covered by the within-body-part check (E21). | Code reads like the spec; make the right thing easy; parse once at the boundary. |
| E21 | Locator payload for `ebcBodyPartHeaderDuplicate` | A) `partId: Opt[PartId]` + key, B) Path-based `path: seq[int]`, C) Just the key, D) Sum-type locator with variants per kind | D — `BodyPartLocation` case object with three variants (`bplInline` carries `partId: PartId`, `bplBlobRef` carries `blobId: BlobId`, `bplMultipart` carries `path: BodyPartPath`) | Make state transitions explicit; newtype everything that has meaning; make illegal states unrepresentable. |
| E22 | Three-variant "HeaderDuplicate" naming family | A) Two separate variants for the new gaps, B) One merged variant with a kind discriminator, C) Two new variants + rename of the existing variant into a shared family | C — `ebcEmailTopLevelHeaderDuplicate` (top-level), `ebcBodyStructureHeaderDuplicate` (bodyStructure root), `ebcBodyPartHeaderDuplicate` (within-body-part) form a "HeaderDuplicate" naming family matching the three runtime RFC duplicate axes | Code reads like the spec; return types are documentation; make the right thing easy (discoverability by naming family). |
| E23 | Intra-Table extraHeaders duplicates (RFC §4.6 applied to the Table-internal axis) | A) Runtime check with new `ebcExtraHeadersNameDuplicate`, B) Type-level via name-only key + form-on-value, C) New distinct Table type, D) Absorb into the HeaderDuplicate family | B — name-only `BlueprintEmailHeaderName` / `BlueprintBodyHeaderName` keys paired with `BlueprintHeaderMultiValue` (carries form + `NonEmptySeq[T]`). Eliminates four constraints simultaneously: intra-Table duplicates, Content-* at top level (E13), Content-Transfer-Encoding on body parts (E13), and key/value form consistency. | Make illegal states unrepresentable; newtype everything that has meaning; one source of truth (form has one home); DRY (`NonEmptySeq[T]` is generic); precedent scales (fifth strip-pattern application). |
| E24 | Body-tree depth enforcement | A) Wire-side limit only (`fromJson`), B) Construction-side check via `ebcBodyPartDepthExceeded`, C) Both | C — `MaxBodyPartDepth = 128` enforced by both `parseEmailBlueprint` (creation side, surfaces a typed error) and `serde_body.fromJson` (read side, defensive). The walker reports the first offending subtree only and halts there, so a 1000-leaf subtree at depth 130 reports once. The constant lives in `body.nim` so both sides share one source of truth. | Total functions; FFI panic-surface defence; one source of truth per fact. |
| E25 | Inner case extraction (`BlueprintLeafPart`) | A) Inline the inner case on `BlueprintBodyPart` itself, B) Hoist into a separate `BlueprintLeafPart` type | B — Nim's `strictCaseObjects` flow analysis does not propagate across nested case-object discriminators on the same type; hoisting the inner case into its own type lets each discriminator be tracked independently. | Make illegal states unrepresentable; FFI panic-surface defence; precedent scales. |
| E26 | `message` rendering bound | A) Unbounded `&` concatenation, B) Bounded clipping with NUL-stripping, C) Reject adversarial payloads at the variant boundary | B — `clipForMessage` truncates each user-controlled slot to 512 bytes and replaces NUL with the literal `\x00`; with at most six slots per variant the total stays well under 8 KiB | Total functions; bounded error rendering; FFI / log-injection defence. |
| E27 | Strict-only header-name parsers (no `*FromServer`) | A) Add `parseBlueprintEmailHeaderNameFromServer` for symmetry, B) Strict-only | B — creation vocabulary is unidirectional. Admitting a lenient parser would open a second construction path through the creation aggregate. The compile-time test suite includes `assertNotCompiles parseBlueprintEmailHeaderNameFromServer(...)` to pin this commitment. | Constructors are privileges; parse once at the boundary; one source of truth. |
| E28 | `BlueprintHeaderMultiValue` non-empty invariant | A) Per-variant smart constructor checks, B) Generic `NonEmptySeq[T]` newtype applied uniformly to all seven payloads | B — one generic newtype, instantiated five times across the five distinct payload types covering all seven variants | DRY; newtype everything that has meaning; precedent scales. |
| E29 | Wire-key composition home | A) Method on `BlueprintHeaderMultiValue`, B) Method on the name types, C) Public free function in `serde_headers.nim` shared by both consumers | C — `composeHeaderKey[T]` is generic over both blueprint header-name types; `multiLen` and `blueprintMultiValueToJson` are exposed alongside it. The wire rule is one fact and lives in one place. | One source of truth; DRY; code reads like the spec. |
| E30 | `bodyValues` harvest under duplicate `partId` | A) Add `ebcDuplicatePartId` smart-ctor variant, B) Document caller responsibility; pin current behaviour (last-wins via `Table` key collision); flag for Part F revisit, C) Validate at serde time and emit `null` for losing entries | B (provisional) — the design currently assumes callers construct trees with unique `PartId` values per leaf. Adding `ebcDuplicatePartId` would require walking the tree to enumerate inline `partId`s before constructing the result Table, duplicating logic the harvest accessor (§3.5) already implements. The current data-loss surface is documented and tested as a regression gate (loud byte-diff between two equal-up-to-insertion-order blueprints with duplicate inline partIds), so any future refactor that alters harvest ordering must either fix the data loss or update the test deliberately. The decision is provisional pending Part F's submission-error landscape. | Code reads like the spec (gap is documented, not hidden); one source of truth (avoid duplicating tree-walk logic premature to Part F's needs); YAGNI. |

---
