# RFC 8621 JMAP Mail — Cross-Cutting Architecture Design

This document captures the architectural decisions that affect all entity types
in the RFC 8621 (JMAP Mail) implementation. It is the single reference for
cross-cutting concerns; per-entity implementation details live in the
companion design documents `06-mail-a-design.md` through `13-mail-H1-design.md`.

The design builds on the existing RFC 8620 (JMAP Core) infrastructure documented
in `00-architecture.md` through `04-layer-4-design.md`. All five layers, the
three-railway error model, the generic builder/dispatch pattern, and the
type-safety conventions carry forward unchanged. This document specifies how
mail-specific types, serialisation, protocol methods, and builder extensions
plug into that infrastructure.

**Living document.** This document records the chosen option for each
decision, retains the rejected alternatives in the options-analysis tables
for context, and reflects the source code under `src/jmap_client/mail/`
as the source of truth.

## Table of Contents

1. [Scope](#1-scope)
2. [Governing Principles](#2-governing-principles)
3. [Module Layout](#3-module-layout)
4. [Knowledge Boundary Principle](#4-knowledge-boundary-principle)
5. [Keyword Type](#5-keyword-type)
6. [Header Parsed Forms](#6-header-parsed-forms)
7. [Body Structure](#7-body-structure)
8. [Email Type, Creation Type, and Update Algebra](#8-email-type-and-creation-type)
9. [Entity-Specific Builder Overloads](#9-entity-specific-builder-overloads)
10. [Custom Methods](#10-custom-methods)
11. [Compound and Chained Handles](#11-compound-handles)
12. [Filter Conditions](#12-filter-conditions)
13. [Per-Entity Summary](#13-per-entity-summary)
14. [Appendix A — Decision Traceability Matrix](#appendix-a-decision-traceability-matrix)

---

## 1. Scope

**Full RFC 8621** — all seven data types, all methods, all properties:

| Data Type          | Complexity | Key Challenge                                           |
|--------------------|------------|---------------------------------------------------------|
| Mailbox            | Moderate   | MailboxRights, query with tree sorting, `/set` extras   |
| Thread             | Simple     | 2 properties, only `/get` and `/changes`                |
| Email              | Very high  | 30+ properties, MIME tree, header parsed forms, create   |
| SearchSnippet      | Simple     | Non-standard `/get`, no state, required filter          |
| Identity           | Simple     | 7 properties, standard methods                          |
| EmailSubmission    | High       | Implicit chaining, envelope, delivery status            |
| VacationResponse   | Simple     | Singleton pattern, only `/get` and `/set`               |

Three capability URIs:

- `urn:ietf:params:jmap:mail` — Mailbox, Thread, Email, SearchSnippet
- `urn:ietf:params:jmap:submission` — Identity, EmailSubmission
- `urn:ietf:params:jmap:vacationresponse` — VacationResponse

---

## 2. Governing Principles

The following principles from the core architecture govern every decision in
this document. Each decision section traces back to the specific principles
that drive it.

- **Parse, don't validate** — Smart constructors produce well-typed Result
  values. After construction, the value is canonical and valid. The parsing
  boundary is at the layer that owns the domain knowledge.
- **Make illegal states unrepresentable** — Distinct types, case objects, and
  smart constructors prevent invalid values from existing. Prefer type-level
  constraints over runtime validation.
- **Railway-Oriented Programming** — Three railways (construction, transport,
  per-method) compose via the `?` operator. Error types are specific and
  actionable.
- **Total functions** — Every function maps every input to a result. No partial
  functions, no panics, no unhandled cases. `{.push raises: [].}` on every
  module.
- **Functional Core, Imperative Shell** — All mail modules are pure (Layer 1
  types, Layer 2 serde, Layer 3 builders). The imperative shell is core's
  `client.nim`. Mail never touches it.
- **Immutability by default** — All types are value objects, constructed once
  and never modified. Builder functions take values and return
  `(RequestBuilder, ResponseHandle[T])` tuples — no `var` parameters,
  no in-place mutation (matching core's tuple-returning `func` builders;
  see core `00-architecture.md` §3.3).
- **DRY** — Shared abstractions defined once. Duplication is acceptable only
  when documented as a conscious trade-off.
- **Domain-Driven Design** — Core owns core knowledge, mail owns mail
  knowledge. Types model domain concepts, not wire format. API names reflect
  domain intent, not protocol encoding.
- **Open-Closed Principle** — Core types are stable and closed for
  modification. Mail extends through composition, parsing, and new modules —
  never by modifying core types.

---

## 3. Module Layout

### 3.1. Decision

All RFC 8621 modules live under `src/jmap_client/mail/` with a `mail.nim`
re-export hub at the directory level. This parallels core's flat structure
under `src/jmap_client/` with `types.nim` as its hub.

### 3.2. Options Analysed

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Flat alongside core** | `src/jmap_client/mailbox.nim`, `email.nim`, etc. | Simple, matches existing layout. Directory grows to ~40 files — hard to navigate. No separation between core and mail. |
| **B) Nested under `mail/`** | `src/jmap_client/mail/mailbox.nim`, etc. with `mail.nim` hub. | Clean core/mail separation. Scales for future RFCs (`contacts/`, `calendars/`). Single import path (`import jmap_client/mail`). |
| **C) Nested by layer** | `src/jmap_client/mail/types/`, `mail/serde/`, etc. | More structure but overkill for this project size. Adds depth without proportional benefit. |

### 3.3. Decision: Option B

**Principles:** DDD (core/mail knowledge boundary), Open-Closed (core directory
unchanged), scalability for future RFC extensions.

### 3.4. Module Tree

```
src/jmap_client/mail/
├── mail.nim                            # (top-level under src/jmap_client/) — re-export hub
│
│  # Re-export hubs (per-layer)
├── types.nim                           # Re-export hub for all Layer 1 mail types
├── serialisation.nim                   # Re-export hub for all Layer 2 mail serde
│
│  # Shared sub-types (Layer 1)
├── keyword.nim                         # Keyword distinct type, KeywordSet, system constants
├── addresses.nim                       # EmailAddress, EmailAddressGroup
├── headers.nim                         # EmailHeader, HeaderForm, HeaderPropertyKey,
│                                       #   HeaderValue, BlueprintEmailHeaderName,
│                                       #   BlueprintBodyHeaderName, BlueprintHeaderMultiValue
├── body.nim                            # PartId, ContentDisposition, EmailBodyPart (read),
│                                       #   EmailBodyValue, BlueprintBodyPart (case),
│                                       #   BlueprintLeafPart (nested case), BlueprintBodyValue
│
│  # Entity types (Layer 1)
├── thread.nim                          # Thread (sealed; parseThread)
├── identity.nim                        # Identity, IdentityCreate, IdentityCreatedItem,
│                                       #   IdentityUpdate (5 variants), IdentityUpdateSet,
│                                       #   NonEmptyIdentityUpdates
├── mailbox.nim                         # Mailbox, MailboxRole (case object),
│                                       #   MailboxRights (clustered booleans),
│                                       #   MailboxIdSet, NonEmptyMailboxIdSet,
│                                       #   MailboxCreate, MailboxCreatedItem,
│                                       #   MailboxUpdate (5 variants), NonEmptyMailboxUpdates
├── mailbox_changes_response.nim        # MailboxChangesResponse (extends ChangesResponse[Mailbox]
│                                       #   with updatedProperties)
├── email.nim                           # Email, ParsedEmail, EmailComparator (case),
│                                       #   PlainSortProperty, KeywordSortProperty,
│                                       #   BodyValueScope, EmailBodyFetchOptions,
│                                       #   EmailCreatedItem, EmailImportResponse,
│                                       #   EmailCopyItem, EmailImportItem, NonEmptyEmailImportMap
├── email_blueprint.nim                 # EmailBlueprint (sealed Pattern A) + parseEmailBlueprint,
│                                       #   EmailBlueprintBody (ebkStructured/ebkFlat case),
│                                       #   flatBody/structuredBody constructors,
│                                       #   BodyPartPath, BodyPartLocation,
│                                       #   EmailBlueprintConstraint, EmailBlueprintError,
│                                       #   EmailBlueprintErrors (sealed accumulator)
├── email_update.nim                    # EmailUpdate (6 variants), EmailUpdateSet,
│                                       #   NonEmptyEmailUpdates; smart + convenience constructors
├── snippet.nim                         # SearchSnippet
├── vacation.nim                        # VacationResponse, VacationResponseUpdate (6 variants),
│                                       #   VacationResponseUpdateSet,
│                                       #   const VacationResponseSingletonId
│
│  # EmailSubmission split (Layer 1)
├── submission_atoms.nim                # RFC5321Keyword (case-insensitive), OrcptAddrType
├── submission_mailbox.nim              # RFC5321Mailbox with full §4.1.2 grammar
│                                       #   (IPv4, IPv6, General-address-literal)
├── submission_param.nim                # SubmissionParam (12 variants), SubmissionParamKey,
│                                       #   SubmissionParams, BodyEncoding, DsnRetType,
│                                       #   DsnNotifyFlag, DeliveryByMode, HoldForSeconds,
│                                       #   MtPriority + 12 smart constructors
├── submission_envelope.nim             # Envelope, ReversePath (case), SubmissionAddress,
│                                       #   NonEmptyRcptList; re-exports the four leaf modules
├── submission_status.nim               # UndoStatus, ParsedDeliveredState (case+raw),
│                                       #   ParsedDisplayedState (case+raw), ReplyCode,
│                                       #   StatusCodeClass, EnhancedStatusCode,
│                                       #   ParsedSmtpReply, DeliveryStatus, DeliveryStatusMap
├── email_submission.nim                # EmailSubmission[S: static UndoStatus] (phantom GADT),
│                                       #   AnyEmailSubmission (sealed Pattern A existential),
│                                       #   EmailSubmissionBlueprint (sealed Pattern A),
│                                       #   EmailSubmissionUpdate, NonEmptyEmailSubmissionUpdates,
│                                       #   EmailSubmissionFilterCondition,
│                                       #   EmailSubmissionSortProperty (esspEmailId/...),
│                                       #   EmailSubmissionComparator,
│                                       #   EmailSubmissionCreatedItem,
│                                       #   EmailSubmissionSetResponse alias,
│                                       #   EmailSubmissionHandles / EmailSubmissionResults aliases,
│                                       #   IdOrCreationRef (case: icrDirect / icrCreation),
│                                       #   NonEmptyOnSuccessUpdateEmail,
│                                       #   NonEmptyOnSuccessDestroyEmail,
│                                       #   NonEmptyIdSeq
│
│  # Mail-specific framework types (Layer 1)
├── mail_capabilities.nim               # MailCapabilities, SubmissionCapabilities,
│                                       #   SubmissionExtensionMap
├── mail_filters.nim                    # MailboxFilterCondition (Opt[Opt[T]] three-state),
│                                       #   EmailHeaderFilter, EmailFilterCondition.
│                                       # Note: EmailSubmissionFilterCondition lives in
│                                       #   email_submission.nim, not here.
│
│  # Serialisation (Layer 2)
├── serde_keyword.nim                   # KeywordSet ↔ {kw: true, ...}
├── serde_addresses.nim
├── serde_headers.nim                   # HeaderValue 7-form dispatch, composeHeaderKey,
│                                       #   blueprintMultiValueToJson
├── serde_body.nim                      # EmailBodyPart with MaxBodyPartDepth recursion limit,
│                                       #   BlueprintBodyPart toJson with key omission for
│                                       #   bpsInline (no charset/size/blobId)
├── serde_mailbox.nim                   # Mailbox + MailboxIdSet + MailboxRights + role +
│                                       #   creation + update wire-patch flatten
├── serde_thread.nim
├── serde_email.nim                     # Email/ParsedEmail two-phase fromJson;
│                                       #   EmailComparator dispatch; EmailBodyFetchOptions
│                                       #   toExtras (request args helper);
│                                       #   EmailCreatedItem; EmailImportItem;
│                                       #   NonEmptyEmailImportMap; EmailImportResponse
├── serde_email_blueprint.nim           # EmailBlueprint → Email/set create wire shape;
│                                       #   harvests bpsInline value into top-level bodyValues
├── serde_email_update.nim              # EmailUpdate → JSON-Pointer-keyed patch entries;
│                                       #   NonEmptyEmailUpdates → {emailId: patchObj, ...}
├── serde_email_submission.nim          # AnyEmailSubmission dispatch on undoStatus peek;
│                                       #   EmailSubmissionBlueprint toJson;
│                                       #   EmailSubmissionUpdate, IdOrCreationRef,
│                                       #   NonEmptyOnSuccess* serde;
│                                       #   EmailSubmissionFilterCondition + Comparator toJson
├── serde_identity.nim
├── serde_identity_update.nim           # IdentityUpdate → patch entries; NonEmptyIdentityUpdates
├── serde_vacation.nim                  # VacationResponse with synthetic singleton id;
│                                       #   VacationResponseUpdate patch entries
├── serde_snippet.nim
├── serde_mail_capabilities.nim         # parseMailCapabilities, parseSubmissionCapabilities
├── serde_mail_filters.nim              # MailboxFilterCondition Opt[Opt[T]] three-way;
│                                       #   EmailHeaderFilter; EmailFilterCondition; toJson-only
├── serde_submission_envelope.nim       # SubmissionParam parsers (12 variants), Envelope,
│                                       #   ReversePath, NonEmptyRcptList, SubmissionAddress
├── serde_submission_status.nim         # UndoStatus, DeliveryStatus, DeliveryStatusMap,
│                                       #   ParsedDeliveredState, ParsedDisplayedState
│
│  # Entity registration + builder extensions (Layer 3)
├── mail_errors.nim                     # Typed accessors over core SetError
│                                       #   (notFoundBlobIds, maxSize, maxRecipients,
│                                       #   invalidRecipientAddresses, invalidEmailProperties).
│                                       # No MailSetErrorType enum — variants live in core (§4.3).
├── mail_entities.nim                   # registerJmapEntity for 4 entity types
│                                       #   (Thread, Identity, Mailbox, Email),
│                                       #   registerJmapEntity for AnyEmailSubmission,
│                                       #   registerCompoundMethod / registerChainableMethod calls
├── mail_builders.nim                   # Mailbox builders (addMailboxChanges/Query/QueryChanges/Set)
│                                       #   + Email builders (addEmailGet/GetByRef/Query/QueryChanges
│                                       #   /Set/Copy/CopyAndDestroy) + addThreadGetByRef +
│                                       #   addEmailQueryWithThreads (4-handle chain) +
│                                       #   EmailCopyHandles / EmailCopyResults aliases +
│                                       #   EmailQueryThreadChain / EmailQueryThreadResults +
│                                       #   DefaultDisplayProperties const
├── mail_methods.nim                    # addVacationResponseGet / addVacationResponseSet,
│                                       #   addEmailParse, addEmailImport,
│                                       #   addSearchSnippetGet + addSearchSnippetGetByRef,
│                                       #   addEmailQueryWithSnippets +
│                                       #   EmailQuerySnippetChain alias +
│                                       #   EmailParseResponse, SearchSnippetGetResponse
├── identity_builders.nim               # addIdentityGet/Changes/Set
└── submission_builders.nim             # addEmailSubmissionGet/Changes/Query/QueryChanges/Set,
                                        #   addEmailSubmissionAndEmailSet (compound)
```

### 3.5. Dependency Flow

```
keyword.nim         addresses.nim                     (no dependencies on each other)
    │                    │
    │       ┌────────────┘
    │       ▼
    │   headers.nim ──► addresses.nim
    │       │
    │       │     body.nim ──► headers.nim
    │       │         │
    │       └────┬────┘
    │            ▼
    ├────► email.nim         ──► keyword, addresses, headers, body, errors,
    │                              framework, identifiers
    ├────► email_blueprint   ──► addresses, body, headers, keyword, mailbox
    ├────► email_update      ──► keyword, mailbox
    │
    ├────► mailbox.nim        ──► validation, primitives
    ├────► mailbox_changes_response ──► mailbox + core methods/serialisation
    │
    │      thread.nim         (standalone)
    │      snippet.nim        (standalone)
    │      vacation.nim       (standalone)
    │
    ├────► identity.nim       ──► addresses
    │
    │      submission_atoms.nim   (standalone)
    │      submission_mailbox.nim (standalone)
    │      submission_param.nim   ──► submission_atoms
    │      submission_envelope    ──► submission_mailbox + atoms + param
    │                                  (re-exports the leaves)
    │      submission_status.nim  ──► submission_envelope (for RFC5321Mailbox)
    │
    ├────► email_submission.nim   ──► submission_envelope, submission_status,
    │                                  email, email_update, methods, dispatch
    │
    ├────► mail_filters.nim       ──► keyword, mailbox
    │      mail_capabilities.nim  ──► submission_atoms
    │
    │  Serde modules: each serde_X.nim imports X.nim + core serde helpers.
    │  Shared sub-type serde (serde_addresses, serde_keyword, serde_headers,
    │    serde_body) is imported directly by entity serde modules.
    │  Mail-internal cross-imports allowed (e.g. serde_email imports
    │    serde_addresses, serde_keyword, serde_mailbox, serde_headers,
    │    serde_body).
    │
    │  Layer 3 modules: import Layer 1 types + Layer 2 serde + core protocol.
    └────► mail_entities, mail_builders, mail_methods, identity_builders,
           submission_builders, mail_errors
```

All mail modules import from core (`types`, `validation`, `serialisation`,
`methods`, `dispatch`, `builder`, `entity`). No circular dependencies within
mail. Entity serde modules import core's `serde` helpers and response
types where needed — e.g. `serde_email.nim` imports `../serde_errors` for
`SetError` parsing inside `EmailImportResponse.createResults`. Re-implementing
those helpers per entity would violate DRY without a corresponding gain in
layer purity, so mail serde is permitted to reach into the core serde layer.

### 3.6. Test Layout

```
tests/
├── unit/mail/             # Per-entity smart-constructor and invariant tests
│   (one file per L1 mail module)
├── serde/mail/            # Round-trip and structural JSON tests
├── property/              # Property tests share one tprop_mail_<letter>.nim
│                          # file per design slice (tprop_mail_c through
│                          # tprop_mail_g) rather than a property/mail/ dir
├── compliance/            # tregression, trfc_8620, tscenarios,
│                          # tmail_e_reexport, tffi_panic_surface — flat,
│                          # no compliance/mail/ subdirectory
└── protocol/              # tmail_builders, tmail_entities, tmail_methods,
                            # tmail_method_errors, tidentity_builders
```

The `unit/mail/` and `serde/mail/` subdirectories mirror the source module
structure (one test file per source file). Property and compliance tests
are flat by design — properties that span multiple entities live in a
single `tprop_mail_<letter>.nim` per design slice, and compliance is
organised by RFC scenario rather than by entity.

### 3.7. Sub-Type Organisation

The shared sub-types are organised by semantic domain, not by parent entity:

| Module | Types | Rationale |
|--------|-------|-----------|
| `addresses.nim` | `EmailAddress`, `EmailAddressGroup` | Used by Email, Identity, EmailSubmission. About addresses, not any single entity. |
| `headers.nim` | `EmailHeader`, `HeaderPropertyKey`, `HeaderValue`, `AllowedHeaderForms` | About parsed header forms. One-way dependency on `addresses.nim` (Addresses/GroupedAddresses forms produce `EmailAddress`/`EmailAddressGroup`). |
| `body.nim` | `EmailBodyPart` (read), `BlueprintBodyPart` (creation), `EmailBodyValue`, `PartId` | About MIME structure. Separate bounded context from headers. |

**Principles:** DDD (bounded contexts), single-responsibility (each module has
one focus), one-way dependencies (no cycles).

Headers and body structure are deliberately separated into distinct
modules even though both contribute to MIME assembly: `HeaderValue` is
about "parsed header forms", which is a different bounded context from
"MIME tree structure". The split keeps each module focused on one
domain concept.

---

## 4. Knowledge Boundary Principle

### 4.1. Decision

Core types are stable and closed. Mail-specific knowledge is parsed and
classified at the mail layer, never pushed into core. The same pattern applies
consistently across three extension points: capabilities, errors, and method
extensions.

### 4.2. Capabilities Boundary

**Options analysed:**

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Add typed variants to `ServerCapability`** | Extend case object with `ckMail: MailCapabilities`, etc. | Typed access. But core has compile-time knowledge of mail — violates Open-Closed. Every future RFC modifies the same case object. |
| **B) Keep raw, parse on demand** | Mail capability data stays as `rawData: JsonNode`. Standalone parsing in mail module. | Core stable. Clean knowledge boundary. One extra call for consumers. |

**Decision: Option B.**

- Core Layer 2 (`serde_session.nim`) parses `ServerCapability` with
  `rawData: JsonNode` for non-core URIs. This is correct — core genuinely
  doesn't know what `maxMailboxDepth` means.
- Mail Layer 1 (`mail_capabilities.nim`) defines `MailCapabilities` and
  `SubmissionCapabilities` as plain public-field objects (no smart
  constructors — follows the `CoreCapabilities` pattern in core).
  Validation happens in the serde layer's parsing functions.
- Mail Layer 2 (`serde_mail_capabilities.nim`) provides
  `parseMailCapabilities(cap: ServerCapability, path: JsonPath): Result[MailCapabilities, SerdeViolation]`
  and `parseSubmissionCapabilities(cap: ServerCapability, path: JsonPath): Result[SubmissionCapabilities, SerdeViolation]`.
  The error rail is `SerdeViolation` because parsing reaches into the
  capability's `rawData: JsonNode` — a structural-JSON failure is the
  natural outcome.
- Consumer calls `parseMailCapabilities` once after session fetch, holds typed
  value thereafter.

**Principles:**
- **DDD** — Core doesn't know what `maxMailboxDepth` means. Mail owns that
  knowledge.
- **Parse, don't validate** — `parseMailCapabilities` transforms raw JSON into
  typed `MailCapabilities` at the mail serde layer. After that call, you hold
  validated data. The parsing boundary moves to the layer that owns the domain
  knowledge, but it doesn't disappear.
- **Open-Closed** — Core is closed for modification. Mail extends through
  composition (parsing raw JSON) without changing `ServerCapability`.
- **Functional Core** — Both `ServerCapability` (core) and `MailCapabilities`
  (mail) are pure value types. The parsing function is a pure `func`.

### 4.3. Errors Boundary

**Options analysed:**

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Extend core `SetErrorType` enum** | Add RFC 8621 error codes to `SetErrorType`. | One parser, one exhaustive case. Core gains compile-time knowledge of every RFC's error variants. |
| **B) `setUnknown` + raw string matching** | Mail code does `if error.rawType == "mailboxHasChild"`. | No core changes. But stringly-typed — exactly the pattern the project avoids. |
| **C) Mail-layer parallel enum with parsing** | Mail module defines `MailSetErrorType` enum and `parseMailSetErrorType(rawType: string)`. | Keeps core closed. Mail has typed classification. Splits exhaustiveness across two enums and two parsers. |

**Decision: Option A.** `SetError` is the data type returned to library
callers on the per-item Result rail (Decision 1.6C / 3.9B) and the case
object must be **exhaustive at the parse boundary**. Splitting that
exhaustiveness across two enums (core + mail) creates two parsing sites
that must stay in lock-step — the classic two-source-of-truth problem.
The simpler model — one enum, one parser, payload variants for the
variants that need them — wins; the Open-Closed cost on core
`errors.nim` (it gains a variant when an RFC adds one) is the price.

The variants on core's `SetErrorType` (see core
`00-architecture.md` §1.8.1) are:

- RFC 8620 §5.3: `setForbidden`, `setOverQuota`, `setTooLarge`,
  `setRateLimit`, `setNotFound`, `setInvalidPatch`, `setWillDestroy`,
  `setInvalidProperties`, `setAlreadyExists`, `setSingleton`.
- RFC 8621 §2 (Mailbox/set): `setMailboxHasChild`, `setMailboxHasEmail`.
- RFC 8621 §4 / §4.8 (Email/set, Email/import): `setBlobNotFound`,
  `setTooManyKeywords`, `setTooManyMailboxes`.
- RFC 8621 §6 (Identity/set): `setInvalidEmail`.
- RFC 8621 §7 (EmailSubmission/set): `setTooManyRecipients`,
  `setNoRecipients`, `setInvalidRecipients`, `setForbiddenMailFrom`,
  `setForbiddenFrom`, `setForbiddenToSend`, `setCannotUnsend`.
- Open-world fallback: `setUnknown`.

`SetError` is a case object in core. The variants that carry
mail-mandated payload fields are typed:

```nim
case errorType*: SetErrorType
of setBlobNotFound:         notFound: seq[BlobId]
of setInvalidEmail:         invalidEmailPropertyNames: seq[string]
of setTooManyRecipients:    maxRecipientCount: UnsignedInt
of setInvalidRecipients:    invalidRecipients: seq[string]
of setTooLarge:             maxSizeOctets: Opt[UnsignedInt]
of setInvalidProperties:    properties: seq[string]
of setAlreadyExists:        existingId: Id
else: discard
```

Construction of payload-bearing variants goes through typed core
helpers (`setErrorBlobNotFound`, `setErrorInvalidEmail`, etc.). The
generic `setError(rawType, …)` defensively maps a payload-bearing
`rawType` arriving without payload data to `setUnknown` so the case
object invariant holds.

**Principles:**
- **Make illegal states unrepresentable** — `SetErrorType` is closed and
  its case object branches are exhaustive. Pattern matching covers every
  variant.
- **Railway-Oriented Programming** — `SetError` flows on the per-item
  Result rail (Decision 1.6C / 3.9B).
- **Total functions** — `parseSetErrorType` is total; unknown values map
  to `setUnknown`.
- **Open-Closed (re-scoped)** — Core `errors.nim` gains a variant when
  a new RFC adds one. This cost is documented here so the trade-off is
  recoverable when future RFCs are considered.

### 4.3.1. Mail-Layer Typed Accessors

`mail_errors.nim` is a Layer 3 module that provides domain-named
accessors over the core case object — not a parallel enum. Each
accessor is a one-line case match returning the variant's payload as
`Opt[T]`, returning `Opt.none` when the SetError is the wrong variant:

| Wire error type     | Accessor                                                | Return type           | RFC clause |
|---------------------|---------------------------------------------------------|-----------------------|------------|
| `blobNotFound`      | `notFoundBlobIds(se: SetError)`                         | `Opt[seq[BlobId]]`    | RFC 8621 §4.6 / §4.8 |
| `tooLarge`          | `maxSize(se: SetError)`                                 | `Opt[UnsignedInt]`    | RFC 8621 §7.5 |
| `tooManyRecipients` | `maxRecipients(se: SetError)`                           | `Opt[UnsignedInt]`    | RFC 8621 §7.5 |
| `invalidRecipients` | `invalidRecipientAddresses(se: SetError)`               | `Opt[seq[string]]`    | RFC 8621 §7.5 |
| `invalidEmail`      | `invalidEmailProperties(se: SetError)`                  | `Opt[seq[string]]`    | RFC 8621 §7.5 |

`mail_errors.nim` depends on `errors.nim` rather than defining new
types and re-exports nothing. Callers import it explicitly when they
want the mail-domain vocabulary.

**Principles:**
- **Parse, don't validate** — consumers receive typed
  `Opt[seq[BlobId]]`, not raw `JsonNode` requiring manual parsing.
- **Total functions** — `Opt[T]` return handles both compliant servers
  (that include the field) and non-compliant ones (that omit it).
- **DDD** — the accessor names speak the mail vocabulary, even though
  the type lives in core.

Variants without dedicated payload fields (e.g. `setMailboxHasChild`,
`setForbiddenToSend`) need no accessor — `errorType` and `description`
suffice.

### 4.4. Method Extensions Boundary

**Options analysed:**

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Entity-specific builder functions in mail module** | `addEmailGet`, `addMailboxQuery`, etc. call core's internal `addInvocation`. | Type-safe, discoverable. No core changes. Mail owns mail knowledge. |
| **B) Extend core builder with generic "custom args"** | Add `extras: Opt[JsonNode]` parameter to generic builder methods. | Flexible but untyped. Loses the compile-time safety the project values. |

**Decision: Option A.**

- Core Layer 3 (`builder.nim`) owns generic `addGet[T]`, `addQuery[T, C]`,
  etc. and the internal `addInvocation` mechanism.
- Mail Layer 3 (`mail_builders.nim`) provides entity-specific overloads
  (`addEmailGet`, `addMailboxQuery`, `addEmailQuery`) with extra parameters.
- Mail Layer 3 (`mail_methods.nim`) provides custom methods
  (`addEmailImport`, `addEmailParse`, `addSearchSnippetGet`) and singleton
  builder functions (`addVacationResponseGet`, `addVacationResponseSet`)
  with bespoke request/response types.
- Entities without extensions (`Thread`, `Identity`) use the core generic
  builder unchanged.

**Principles:**
- **DDD** — `addEmailGet` lives in the mail module because it encodes
  mail-specific knowledge (`bodyProperties`, `fetchTextBodyValues`). Core's
  `addGet[T]` doesn't know those exist.
- **Immutability by default** — Builder overloads produce immutable
  `Invocation` values and return phantom-typed `ResponseHandle[T]`. No
  mutable state beyond the builder's accumulation.
- **DRY** — Mail builder functions call into core's `addInvocation` mechanism.
  Capability deduplication, call ID generation, and invocation accumulation
  are written once in core, reused by every mail method.

---

## 5. Keyword Type

### 5.1. Decision

`Keyword` is a distinct validated type with a smart constructor that validates
and normalises to lowercase during construction. System keywords are
compile-time constants.

### 5.2. Type Definition

```nim
type Keyword* = distinct string
```

Borrowed operations via `defineStringDistinctOps(Keyword)`: `==`, `$`, `hash`,
`len`.

### 5.3. Smart Constructor

`parseKeyword(raw: string): Result[Keyword, ValidationError]`:
- Validates: 1–255 bytes, ASCII `%x21–%x7E`
- Rejects forbidden characters: `( ) { ] % * " \`
- **Normalises to lowercase** during construction

After construction, `Keyword` is always lowercase, always valid. No downstream
code ever needs to worry about case.

**Principles:**
- **Parse, don't validate** — The smart constructor transforms input into
  canonical form, not just checks it. This is the principle at its purest.
- **Total functions** — Maps every input to `ok(Keyword)` or
  `err(ValidationError)`.

Lenient variant `parseKeywordFromServer(raw: string): Result[Keyword, ValidationError]`
for server data — wider accepted input set, still total, still normalises to
lowercase, never silently swallows errors.

### 5.4. Forbidden Characters Constant

```nim
const KeywordForbiddenChars*: set[char] = {'(', ')', '{', ']', '%', '*', '"', '\\'}
```

Defined once, used by both `parseKeyword` and `parseKeywordFromServer`. Same
pattern as `Base64UrlChars` in `primitives.nim`.

**Principle:** DRY — single source of truth for the forbidden character set.

### 5.5. System Keyword Constants

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
are provably valid.

**Principles:**
- **DRY** — Define once, use everywhere.
- **Make illegal states unrepresentable** — Pre-validated at compile time.
  The common case is ergonomic.

### 5.6. KeywordSet

`KeywordSet = distinct HashSet[Keyword]` — not `Table[Keyword, bool]`.

The RFC mandates that all values in the `keywords` map MUST be `true`. The
`bool` carries no information. A `HashSet[Keyword]` makes the "value is always
true" invariant unrepresentable rather than validated. The serde layer parses
`{"$seen": true, "$flagged": true}` into `KeywordSet`, rejecting any entry
with `false`.

Borrowed operations come from `defineHashSetDistinctOps(KeywordSet, Keyword)`
(read-only API — `len`, `contains`, `card`, `==`, `$`, `items`, `pairs`).
Public construction goes through `initKeywordSet(openArray[Keyword])`. There
is no public `incl`/`excl` borrow — the type is constructed once and used
as a value, mirroring §1.5 (parse, don't validate).

**Principles:**
- **Make illegal states unrepresentable** — Eliminates an entire class of
  invalid state (a keyword mapped to `false`) at the type level.
- **DDD** — The domain model doesn't mirror the wire format. The serde layer
  handles the `Table[Keyword, bool]` JSON representation.
- **Immutability by default** — `KeywordSet` is an immutable value type.
  Constructed once via `initKeywordSet` and treated as a snapshot.

---

## 6. Header Parsed Forms

### 6.1. Decision

Dynamic header requests return a typed `HeaderValue` case object. The serde
layer determines the correct variant from the property name suffix and parses
into the corresponding type. No JSON blobs leak into the domain model.

### 6.2. Options Analysed

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) String-keyed JsonNode map** | `Table[string, JsonNode]` with full property name as key. | Simple, flexible. No type safety. Parsing is the consumer's problem. |
| **B) Typed header value enum** | Case object `HeaderValue` with variants for each parsed form. Requested headers in `Table[HeaderPropertyKey, HeaderValue]`. | Type-safe. Parse-don't-validate at the serde boundary. More complex but complexity contained in serde. |
| **C) Convenience properties only** | Only model RFC 8621 convenience shortcuts as typed fields. Dynamic `header:X:asY` syntax stored as raw JSON. | Covers 95% of use cases. But unvalidated JSON in domain model for the remaining 5%. |

**Decision: Option B, with convenience properties as first-class fields.**

The user's argument was decisive: "parse, don't validate applied consistently"
— every parsed form that comes back from the server gets parsed into a proper
type at the deserialisation boundary. The complexity is real but contained in
the serde layer where it belongs. The domain types themselves are clean.

### 6.3. Three Tiers of Header Access

1. **Convenience fields** on `Email` (`from`, `to`, `subject`, `sentAt`, etc.)
   — first-class, always parsed when present in the response. These are the
   primary API for the vast majority of clients.

2. **Dynamic parsed headers** via `requestedHeaders: Table[HeaderPropertyKey, HeaderValue]`
   — typed, form-aware. When you ask for `header:X:asAddresses`, the
   deserialiser parses into `HeaderValue(form: hfAddresses, ...)`. Used for
   custom headers or headers not covered by convenience fields.

3. **Raw headers** via `headers: Opt[seq[EmailHeader]]` — the escape hatch.
   Raw string values for all header fields. This is the RFC's "Raw" form.

### 6.4. HeaderValue Case Object

```nim
type HeaderForm* = enum
  hfRaw, hfText, hfAddresses, hfGroupedAddresses, hfMessageIds, hfDate, hfUrls

type HeaderValue* = object
  case form*: HeaderForm
  of hfRaw:              rawValue*: string
  of hfText:             textValue*: string
  of hfAddresses:        addresses*: seq[EmailAddress]
  of hfGroupedAddresses: groups*: seq[EmailAddressGroup]
  of hfMessageIds:       messageIds*: Opt[seq[string]]   # null if parsing failed
  of hfDate:             date*: Opt[Date]                 # null if parsing failed
  of hfUrls:             urls*: Opt[seq[string]]          # null if parsing failed
```

**Principles:**
- **Make illegal states unrepresentable** — Each form has exactly the fields
  it needs. No optional fields on variants where the data is always present.
- **Total functions** — Pattern matching on the `form` discriminant is
  exhaustive. The compiler warns if a branch is missed.

### 6.5. HeaderPropertyKey

A structured type replacing raw string keys:

```nim
type HeaderPropertyKey* = object
  name*: string         # e.g., "From", "X-Custom"
  form*: HeaderForm     # e.g., hfAddresses
  isAll*: bool          # :all suffix
```

**Principles:**
- **Make illegal states unrepresentable** — The form is stated once (in the
  key). A smart constructor for inserting a header entry enforces that the
  `HeaderValue` variant matches the key's `form`. You cannot store an
  `hfDate` value under an `hfAddresses` key.
- **Parse, don't validate** — `parseHeaderPropertyName` produces
  `Result[HeaderPropertyKey, ValidationError]`, not a tuple. The raw string
  `"header:From:asAddresses:all"` goes in, a validated `HeaderPropertyKey`
  comes out. After that, no code ever re-parses the string. Named types are
  the parsed form; tuples are anonymous.

`parseHeaderPropertyName(prop: string): Result[HeaderPropertyKey, ValidationError]`:
- Validates: `header:` prefix, non-empty header name, valid form suffix
- Handles: `header:Name`, `header:Name:asForm`, `header:Name:all`,
  `header:Name:asForm:all`
- **Total** — handles every input: missing prefix, unknown form suffix, empty
  name. All map to `err(ValidationError)`.

### 6.6. AllowedHeaderForms

`headers.nim` exposes `func allowedForms(name: string): set[HeaderForm]`
returning the permitted form-set for a given (lowercased) header name,
plus `func validateHeaderForm(key: HeaderPropertyKey): Result[HeaderPropertyKey, ValidationError]`
which checks a parsed `HeaderPropertyKey` against the allowed-forms map
and returns the same key on success. The mapping is kept as a private
const table inside the module — callers query it through the accessor
rather than reading the table directly.

The shape (RFC 8621 §4.1.2):

| Header name        | Permitted forms                                                     |
|--------------------|---------------------------------------------------------------------|
| `from`/`sender`/`reply-to`/`to`/`cc`/`bcc` | `hfAddresses`, `hfGroupedAddresses`, `hfRaw`        |
| `subject`          | `hfText`, `hfRaw`                                                   |
| `date`             | `hfDate`, `hfRaw`                                                   |
| `message-id`/`in-reply-to`/`references` | `hfMessageIds`, `hfRaw`                                |
| `list-id`/`list-archive`/`list-help`/`list-owner`/`list-post`/`list-subscribe`/`list-unsubscribe` | `hfUrls`, `hfRaw` |
| Other / unknown    | every `HeaderForm` (RFC permits any form on custom headers)         |

**Principles:**
- **DRY** — Defined once inside `headers.nim`. Both validation and
  documentation generation derive from `allowedForms`.
- **Total functions** — Unknown header names return the full set. Known
  headers with forbidden forms cause `validateHeaderForm` to return
  `err(ValidationError)`.

### 6.9. Blueprint Header Construction

The creation-side header surface is split from the read model
(`HeaderPropertyKey` / `HeaderValue`) so RFC 8621 §4.1.2.4
creation-time invariants — top-level vs body-part allowed-name sets,
and value cardinality matching the `:all` suffix — are lifted to the
type level. `headers.nim` declares three blueprint-specific types:

```nim
type BlueprintEmailHeaderName* = distinct string  # validated for top-level
type BlueprintBodyHeaderName*  = distinct string  # validated for body parts

type BlueprintHeaderMultiValue* = object
  case form*: HeaderForm
  of hfRaw:              rawValues*:        NonEmptySeq[string]
  of hfText:             textValues*:       NonEmptySeq[string]
  of hfAddresses:        addressLists*:     NonEmptySeq[seq[EmailAddress]]
  of hfGroupedAddresses: groupLists*:       NonEmptySeq[seq[EmailAddressGroup]]
  of hfMessageIds:       messageIdLists*:   NonEmptySeq[seq[string]]
  of hfDate:             dateValues*:       NonEmptySeq[Date]
  of hfUrls:             urlLists*:         NonEmptySeq[seq[string]]
```

The two `Blueprint*HeaderName` types are validated separately because the
top-level and body-part allowed sets differ. `parseBlueprintEmailHeaderName`
forbids the `content-*` family entirely (RFC 8621 §4.6 constraint 4 —
JMAP manages those headers itself); `parseBlueprintBodyHeaderName` forbids
only the exact name `content-transfer-encoding` (RFC 8621 §4.6
constraint 9). Both normalise to lowercase and reject empty / non-printable
/ colon-bearing input. There is no `*FromServer` lenient sibling — the
creation vocabulary is unidirectional (server never sends these names back).

`BlueprintHeaderMultiValue` is the value side. The seven variants
correspond to the seven `HeaderForm` values; each carries a
`NonEmptySeq[T]` to express the RFC's "one or more values" rule (the
`:all` suffix produces multiple wire entries from a single Nim value).
Two construction families per form:

- `<form>Single(value): BlueprintHeaderMultiValue` — single-value
  smart constructor, infallible.
- `<form>Multi(values): Result[BlueprintHeaderMultiValue, ValidationError]`
  — multi-value smart constructor, fails when `values` is empty.

The serde layer (`serde_headers.nim`) provides
`composeHeaderKey(name, form, isAll)` to build the wire property string
(`"header:<name>[:as<Form>][:all]"`, omitting the form suffix for
`hfRaw`) and `blueprintMultiValueToJson` to serialise the value (single
→ scalar or 1-elem array, multiple → array).

**Principles:**
- **Make illegal states unrepresentable** — Empty value lists are
  unrepresentable (`NonEmptySeq[T]`). Top-level vs body-part header
  validation is split at the type level.
- **Parse, don't validate** — Smart constructors validate at the
  boundary; downstream code holds well-typed values.
- **DRY** — `composeHeaderKey` is the single wire-key composition site;
  callers do not concatenate strings ad-hoc.

### 6.7. Serde Layer

`serde_headers.nim` — the parsing boundary for header values.

The deserialiser:
1. Calls `?parseHeaderPropertyName(prop)` to extract `HeaderPropertyKey`
2. Calls `?parseHeaderValue(key.form, jsonNode)` to parse into the correct
   `HeaderValue` variant
3. Inserts into the typed map with key–value consistency enforced

Each step returns `Result`, each can fail independently with a specific
`ValidationError`. The railway is clean.

The `Opt[Opt[T]]` pattern does not apply to headers (headers are always
present or absent, never `null`). The three-way dispatch documented in
§12.6 is specific to filter conditions.

### 6.8. Email Fields for Dynamic Headers

```nim
# On the Email type:
requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]
```

Named `requestedHeaders` (not `dynamicHeaders`) because they are
"client-requested parsed header views" — not all headers (that's
`headers: Opt[seq[EmailHeader]]`), but the specific parsed views the client
asked for.

**Principles:**
- **DDD** — The name expresses what the field represents: requested header
  projections.
- **Immutability by default** — Both tables are immutable once constructed.
  The serde layer builds them and seals them.

---

## 7. Body Structure

### 7.1. Decision

`EmailBodyPart` is a case object discriminated by `isMultipart`. The RFC's
invariant ("partId and blobId are null if and only if the part is multipart/*")
is enforced at the type level.

### 7.2. Options Analysed

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) All fields optional** | `subParts: Opt[seq[EmailBodyPart]]`, `partId: Opt[string]`, etc. | Simple. But permits invalid combinations (e.g., multipart node with `partId`). |
| **B) Case object by multipart** | Discriminant `isMultipart`. Leaf fields on `false` branch, `subParts` on `true` branch. Shared fields in common area. | Compiler-enforced invariant. Exhaustive pattern matching. No invalid combinations possible. |
| **C) Separate types** | `EmailBodyPartNode` and `EmailBodyPartLeaf` unified under variant. | Same structural idea as B with different naming. |

**Decision: Option B.**

**Principles:**
- **Make illegal states unrepresentable** — The case discriminant encodes
  the RFC invariant directly. Leaf nodes always have `partId`/`blobId`.
  Multipart nodes always have `subParts`. All nodes have `size` (RFC
  unconditional). No runtime checks needed downstream.
- **Parse, don't validate** — The serde layer inspects the `type` field
  (or presence of `subParts`), picks the correct discriminant, and constructs
  the right variant. By the time you hold an `EmailBodyPart`, the invariant
  is guaranteed.
- **Total functions** — Any function operating on `EmailBodyPart` can
  pattern-match on the discriminant exhaustively. The compiler warns if a
  branch is missed.

### 7.3. Type Definition

```nim
type PartId* = distinct string  # unique within an Email

type ContentDispositionKind* = enum
  cdInline = "inline"
  cdAttachment = "attachment"
  cdExtension                  # vendor / RFC-specified extension

type ContentDisposition* = object
  case rawKind: ContentDispositionKind
  of cdExtension: rawIdentifier: string  # module-private; preserved verbatim
  of cdInline, cdAttachment: discard

type EmailBodyPart* = object
  ## Shared fields (all parts):
  headers*: seq[EmailHeader]
  name*: Opt[string]              # decoded filename
  contentType*: string            # e.g., "text/plain", "multipart/mixed"
  charset*: Opt[string]           # null for non-text/*, "us-ascii" default for text/*
  disposition*: Opt[ContentDisposition]  # typed (not Opt[string])
  cid*: Opt[string]               # Content-Id without angle brackets
  language*: Opt[seq[string]]     # Content-Language tags
  location*: Opt[string]          # Content-Location URI
  size*: UnsignedInt              # RFC unconditional — all parts, including multipart

  case isMultipart*: bool
  of true:
    subParts*: seq[EmailBodyPart] # recursive children
  of false:
    partId*: PartId               # unique within the Email
    blobId*: BlobId               # reference to content blob (typed BlobId, not Id)
```

`ContentDisposition` is a typed case object — the RFC vocabulary
(`inline`, `attachment`) is closed for known cases, plus `cdExtension`
preserves vendor-specific dispositions verbatim. The same pattern as
`MailboxRole` (§13.1) and `CapabilityKind` (core §1.2). Public constants
`dispositionInline` and `dispositionAttachment` cover the two
RFC-mandated values; vendor strings flow through
`parseContentDisposition`.

`blobId: BlobId` (not `Id`) — the project added a typed `BlobId =
distinct string` in core's `identifiers.nim`, so blob references and
entity IDs cannot be silently exchanged.

### 7.4. PartId Distinct Type

`PartId = distinct string` — same pattern as `Id`, `Keyword`. Prevents
accidentally using an arbitrary string as a body values lookup key.

Smart constructor `parsePartId(raw: string): Result[PartId, ValidationError]`
validates non-empty.

### 7.5. contentType and isMultipart Consistency

The `isMultipart` discriminant and `contentType` string encode overlapping
information. `isMultipart` is the canonical discriminant; `contentType` is the
full MIME type string. The serde layer **derives** `isMultipart` from
`contentType` — they are not independently specified. This avoids any future
temptation to set them inconsistently.

**Principle:** DRY — one source of truth for "is this a multipart part?".

### 7.6. Recursive Depth Limit

The serde layer's `fromJson` for `EmailBodyPart` handles arbitrarily deep
nesting. The depth bound is the public constant
`const MaxBodyPartDepth* = 128` exposed from `body.nim`. Beyond the
bound, `fromJson` returns `err(SerdeViolation(kind: svkDepthExceeded,
maxDepth: 128, ...))`. This keeps the function total even against
adversarial input.

**Principle:** Total functions — every input maps to a result, including
pathologically deep trees.

### 7.7. Flat List Invariant

The `Email` type carries `textBody`, `htmlBody`, `attachments` as
`seq[EmailBodyPart]` (not `Opt[seq[...]]` — empty sequences represent
absence, the same way `headers` does). These flat lists must only
contain leaf parts (never multipart nodes). The serde layer validates
this during construction — any multipart entry in a flat list is
rejected with `err(SerdeViolation)`.

`func isLeaf(part: EmailBodyPart): bool` is exported from `body.nim`
as the canonical predicate (`not part.isMultipart`).

The invariant is "guaranteed by construction" — after parsing, the flat
lists are guaranteed to contain only leaf parts.

**Principle:** Make illegal states unrepresentable — while Nim's type
system can't express "a seq containing only the `isMultipart: false`
variant" without a separate type, the serde-time check enforces it.

### 7.8. EmailBodyValue and BlueprintBodyValue

Read model:

```nim
type EmailBodyValue* = object
  value*: string              # decoded text content
  isEncodingProblem*: bool    # default false
  isTruncated*: bool          # default false
```

Creation companion:

```nim
type BlueprintBodyValue* = object
  value*: string              # decoded text content; no flags
```

The two are deliberately separate types. The read model carries the
two server-set flags (`isEncodingProblem`, `isTruncated`) so the client
can observe them. The creation model has neither flag — the RFC
mandates both be `false` on creation, and a separate type makes that
unrepresentable rather than validated.

### 7.9. Immutability of Recursive Tree

`seq[EmailBodyPart]` in `subParts` is a value type under Nim's ARC memory
management. The recursive tree is fully immutable once constructed. This is
worth noting explicitly since recursive immutable trees are sometimes a concern
in other languages — in Nim with ARC, value semantics apply throughout.

---

## 8. Email Type, Creation Type, and Update Algebra

### 8.1. Decision

The Email data type is split into four distinct types, one per
direction-of-flow:

- `Email` — read model for `Email/get` and `Email/changes` responses
  (store-backed).
- `ParsedEmail` — read model for `Email/parse` responses (blob-backed,
  no store metadata).
- `EmailBlueprint` — creation model for `Email/set` create. Sealed
  Pattern A Layer 1 aggregate built via `parseEmailBlueprint`; the
  body is a separate `EmailBlueprintBody` case object discriminating
  `ebkStructured` / `ebkFlat` (§8.4–8.5).
- `EmailUpdate` / `NonEmptyEmailUpdates` — typed update algebra for
  `Email/set` update (closed sum-type ADT) (§8.7).

### 8.2. Email (Read Model)

```nim
type Email* = object
  # Metadata — every field Opt because client controls property selection.
  # Stalwart 0.15.5 omits some server-set fields on creation echoes; the
  # uniform Opt[T] shape accommodates this without per-field special cases.
  id*: Opt[Id]
  blobId*: Opt[BlobId]
  threadId*: Opt[Id]
  mailboxIds*: Opt[MailboxIdSet]
  keywords*: Opt[KeywordSet]
  size*: Opt[UnsignedInt]
  receivedAt*: Opt[UTCDate]

  # Convenience header fields (typed parsed views; Opt[T] = absent or null)
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

  # Raw headers — empty seq when not requested
  headers*: seq[EmailHeader]

  # Requested parsed header views
  requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
  requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]

  # Body
  bodyStructure*: Opt[EmailBodyPart]
  bodyValues*: Table[PartId, EmailBodyValue]
  textBody*: seq[EmailBodyPart]      # leaf parts only, guaranteed by construction
  htmlBody*: seq[EmailBodyPart]      # leaf parts only, guaranteed by construction
  attachments*: seq[EmailBodyPart]   # leaf parts only, guaranteed by construction
  hasAttachment*: bool
  preview*: string
```

**Key design notes:**

- **All metadata fields are `Opt[T]`** — `id`, `blobId`, `size`,
  `receivedAt`, etc. are all `Opt`. Two reasons: (a) clients control
  property selection on `/get`, so any field can be absent under a
  property filter; (b) Stalwart 0.15.5 omits server-set fields on
  `/set` create echoes that the RFC technically mandates. The uniform
  `Opt[T]` shape avoids per-field special cases under either condition.

- **Empty seq vs `Opt`** — collections (`headers`, `textBody`,
  `htmlBody`, `attachments`, `bodyValues`) use empty sequences to
  represent absence. `bodyStructure` and the metadata fields use
  `Opt[T]`. The split is deliberate: a property-not-requested
  `bodyStructure` is genuinely absent (we did not ask for it), but a
  property-not-requested body list naturally maps to "no parts".

- **`MailboxIdSet`** instead of `Table[Id, bool]` — same principle as
  `KeywordSet`. The `bool` carries no information (RFC mandates always
  `true`).

- **`fromAddr`** — avoids the `from` keyword collision. The same naming
  convention is applied consistently to `EmailFilterCondition.fromAddr`.

- **All body list fields** are guaranteed to contain only leaf parts by
  the serde layer.

- **Email mutability:** Only `mailboxIds` and `keywords` are mutable
  after creation. The `EmailUpdate` ADT (§8.7) restricts updates to
  exactly those two property families. The `Email` type itself is an
  immutable read model.

### 8.3. ParsedEmail

A distinct type from store-backed `Email`. Metadata fields that are
structurally absent on a parsed blob (from `Email/parse`) are not present
on the type, rather than being `Opt.none` on a shared type.

```nim
type ParsedEmail* = object
  # Metadata — only threadId is meaningful (server may infer it)
  threadId*: Opt[Id]

  # Header and body fields — identical shape to Email
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
  headers*: seq[EmailHeader]
  requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
  requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]
  bodyStructure*: Opt[EmailBodyPart]
  bodyValues*: Table[PartId, EmailBodyValue]
  textBody*: seq[EmailBodyPart]
  htmlBody*: seq[EmailBodyPart]
  attachments*: seq[EmailBodyPart]
  hasAttachment*: bool
  preview*: string
```

`ParsedEmail` omits the six store-only metadata fields that exist on
`Email` (`id`, `blobId`, `mailboxIds`, `keywords`, `size`, `receivedAt`).
Everything below the metadata uses the same shape and `Opt`/empty-seq
discipline as `Email`.

**Principles:**
- **Parse, don't validate** — These aren't "optional in the normal sense";
  they're "structurally absent because this is a parsed blob, not a store
  object." A distinct type makes this semantic difference visible.
- **DDD** — A "parsed blob" and a "stored email" are different aggregates
  with different invariants. Collapsing them into one type with "some fields
  are always none" is a modelling compromise that obscures the domain.

**Conscious trade-off:** The header and body fields are duplicated between
`Email` and `ParsedEmail`. This is acceptable because the `Opt` wrapping and
differing metadata fields make a shared base type impractical without
sacrificing type safety. The duplication is structural, not behavioural.

### 8.4. BlueprintBodyPart (Creation-Specific Body Part)

RFC 8621 §4.6 imposes creation-specific constraints on body parts that
differ fundamentally from the read model:

- `partId` XOR `blobId` (not both; `partId` means "bodyValues lookup key",
  `blobId` means "uploaded blob reference")
- `charset` MUST be omitted if `partId` is given
- `size` MUST be omitted if `partId` is given; if `blobId` is given,
  optional and ignored by the server
- `Content-Transfer-Encoding` header MUST NOT be given

The read-model `EmailBodyPart` keeps `partId` and `blobId` on the same
branch (both always present). The creation constraints are fundamentally
different, so the leaf shape is factored into a separate nested case
object — the constraints become unrepresentable rather than validated:

```nim
type BlueprintPartSource* = enum
  bpsInline    # partId → bodyValues lookup
  bpsBlobRef   # blobId → uploaded blob reference

type BlueprintLeafPart* = object
  case source*: BlueprintPartSource
  of bpsInline:
    partId*: PartId               # no charset, no size, no blobId
    value*: BlueprintBodyValue    # value harvested into top-level bodyValues
  of bpsBlobRef:
    blobId*: BlobId
    size*: Opt[UnsignedInt]       # optional, ignored by server
    charset*: Opt[string]

type BlueprintBodyPart* = object
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

Three structural choices on this type:

1. **`leaf: BlueprintLeafPart`** is a separate nested case object rather
   than an inline branch. Strict-flow analysis does not propagate nested
   case-object facts across types (verified empirically — see
   `nim-type-safety.md` Rule 4), so hoisting the inner case into its own
   type lets the compiler track each discriminator independently. It
   also lets `EmailBlueprintError` name a body-part location
   (`BodyPartLocation` — see §8.5) without dragging the whole
   `BlueprintBodyPart` shape into the error ADT.
2. **`value: BlueprintBodyValue` lives on the leaf**. The serde layer
   harvests `bpsInline` part values into a top-level `bodyValues` JSON
   object at emission time. Callers do not pass a separate `bodyValues`
   table to the `EmailBlueprint` API — they put each inline value next
   to the part it belongs to. This eliminates the "partId without
   bodyValues entry" failure mode at the type level.
3. **`extraHeaders: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]`**
   uses the typed body-header-name and multi-value types from §6.9,
   not the read-model `HeaderPropertyKey` / `HeaderValue`. The two
   namespaces are split because the top-level and body-part allowed
   header sets differ.

**Serde note:** `serde_body.nim` and `serde_email_blueprint.nim` use
key-omission for absent fields (not `null` emission). Inline parts
(`bpsInline`) emit `partId` only — no `charset`, `size`, or `blobId`
keys — and the inline value is harvested into the top-level
`bodyValues` object on the wire.

### 8.5. EmailBlueprint Construction (parser-built, sealed errors)

`EmailBlueprint` is a sealed Layer 1 aggregate constructed exclusively
through the smart constructor `parseEmailBlueprint`. The aggregate's
fields are module-private (`raw*` prefix) with same-name UFCS
accessors, so direct brace construction outside `email_blueprint.nim`
is a compile error — Pattern A sealing forces the constructor to be
the sole boundary. The error rail accumulates every constraint
violation in one pass.

```nim
type EmailBlueprint* = object
  rawMailboxIds: NonEmptyMailboxIdSet
  rawKeywords:   KeywordSet
  rawReceivedAt: Opt[UTCDate]
  rawFromAddr:   Opt[seq[EmailAddress]]
  rawTo:         Opt[seq[EmailAddress]]
  rawCc:         Opt[seq[EmailAddress]]
  rawBcc:        Opt[seq[EmailAddress]]
  rawReplyTo:    Opt[seq[EmailAddress]]
  rawSender:     Opt[EmailAddress]   # singular per RFC 5322 §3.6.2
  rawSubject:    Opt[string]
  rawSentAt:     Opt[Date]
  rawMessageId:  Opt[seq[string]]
  rawInReplyTo:  Opt[seq[string]]
  rawReferences: Opt[seq[string]]
  rawExtraHeaders: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]
  rawBody:       EmailBlueprintBody
```

The body case object encodes the RFC's "bodyStructure XOR flat-list"
choice at the type level:

```nim
type EmailBodyKind* = enum
  ebkStructured  # client provides a full bodyStructure tree
  ebkFlat        # client provides textBody / htmlBody / attachments

type EmailBlueprintBody* = object
  case kind*: EmailBodyKind
  of ebkStructured:
    bodyStructure*: BlueprintBodyPart
  of ebkFlat:
    textBody*:    Opt[BlueprintBodyPart]   # at most one text/plain leaf
    htmlBody*:    Opt[BlueprintBodyPart]   # at most one text/html leaf
    attachments*: seq[BlueprintBodyPart]
```

Two infallible body constructors: `flatBody(...)` (default — empty
flat body is valid) and `structuredBody(root)`.

The smart constructor signature:

```nim
func parseEmailBlueprint*(
    mailboxIds: NonEmptyMailboxIdSet,
    body: EmailBlueprintBody = flatBody(),
    keywords: KeywordSet = initKeywordSet(@[]),
    receivedAt: Opt[UTCDate] = …,
    fromAddr, to, cc, bcc, replyTo: Opt[seq[EmailAddress]] = …,
    sender: Opt[EmailAddress] = …,
    subject: Opt[string] = …,
    sentAt: Opt[Date] = …,
    messageId, inReplyTo, references: Opt[seq[string]] = …,
    extraHeaders: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue] = …,
): Result[EmailBlueprint, EmailBlueprintErrors]
```

Six signature-level invariants are pre-discharged by input types and need
no runtime check (RFC 8621 §4.6 numbering): mailboxIds non-empty (#1),
no top-level `headers` array (#2 — field absent), no `Content-*`
top-level keys (#4 — `BlueprintEmailHeaderName` rejects `content-*`),
bodyStructure XOR flat (#5 — `EmailBlueprintBody` discriminant), body
values flags-false (#6 — `BlueprintBodyValue` strips them), no
`Content-Transfer-Encoding` on body parts (#9 —
`BlueprintBodyHeaderName` rejects it).

Seven runtime constraints flow through the error rail. Each variant
carries the payload needed to point the caller at the offending input:

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
    dupName*: string
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
    observedDepth*: int
    depthLocation*: BodyPartLocation
```

Constraint meanings:

1. **`ebcEmailTopLevelHeaderDuplicate`** — convenience field (e.g.
   `fromAddr`) and an `extraHeaders` entry for the same header
   (e.g. `header:From:asAddresses`) are mutually exclusive.
2. **`ebcBodyStructureHeaderDuplicate`** — `bodyStructure` root's
   `extraHeaders` cannot duplicate a header already implied at the Email
   top level (convenience field or top-level `extraHeaders` entry).
3. **`ebcBodyPartHeaderDuplicate`** — within a body part, an
   `extraHeaders` entry duplicates a header implied by the part's
   domain fields (`contentType`, `disposition`, `cid`, `language`,
   `location`).
4. **`ebcTextBodyNotTextPlain`** — `ebkFlat.textBody` parts must have
   `contentType == "text/plain"`.
5. **`ebcHtmlBodyNotTextHtml`** — `ebkFlat.htmlBody` parts must have
   `contentType == "text/html"`.
6. **`ebcAllowedFormRejected`** — top-level or body-part `extraHeaders`
   form forbidden by `allowedForms` for the given header name.
7. **`ebcBodyPartDepthExceeded`** — body tree depth exceeds
   `MaxBodyPartDepth = 128`. Reported once per offending subtree root,
   not once per leaf.

Body-part errors carry a `BodyPartLocation` (defined in
`email_blueprint.nim`) naming where in the tree the failure occurred:

```nim
type BodyPartPath* = distinct seq[int]   # tree path; root = @[]

type BodyPartLocationKind* = enum
  bplInline       # leaf located by partId
  bplBlobRef      # leaf located by blobId
  bplMultipart    # multipart container located by tree path

type BodyPartLocation* = object
  case kind*: BodyPartLocationKind
  of bplInline:    partId*:   PartId
  of bplBlobRef:   blobId*:   BlobId
  of bplMultipart: path*:     BodyPartPath
```

For `ebkFlat`, the path's first index encodes the slot: `0` for
`textBody`, `1` for `htmlBody`, `2 + i` for `attachments[i]`.

Errors accumulate; the parser does not short-circuit. The error rail
type `EmailBlueprintErrors` is a Pattern A sealed accumulator —
private `errors: seq[EmailBlueprintError]` field with `len`, `items`,
`pairs`, `[]: Idx`, `head`, `==`, `$`, and `capacity` accessors. The
non-empty invariant is constructor-enforced (an empty seq would mean
"no errors", which is the ok rail's job). A per-error `message` accessor
returns a bounded, NUL-stripped human-readable rendering for diagnostics
and log emission.

A derived `bodyValues(bp)` accessor walks the body tree and projects
each `bpsInline` leaf into a `Table[PartId, BlueprintBodyValue]`. One
source of truth — `bodyValues` IS the tree projected, so the two
cannot disagree. Duplicate `partId` across the tree resolves via
`Table` last-wins (documented gap; the serde layer sees one entry per
partId by construction).

**Principles:**
- **Make illegal states unrepresentable** — Six type-level invariants
  pre-discharge most RFC §4.6 constraints. Body-shape variants
  (`bpsInline`/`bpsBlobRef`/`isMultipart`/`ebkStructured`/`ebkFlat`)
  eliminate further classes, leaving only seven cross-field runtime
  constraints.
- **Total functions** — Construction accumulates all errors. Every
  input maps to a successful `EmailBlueprint` or a non-empty
  `EmailBlueprintErrors` accumulator.
- **Sealed accumulator** — `EmailBlueprintErrors` has private storage;
  callers iterate via `items` / `pairs` / `[]: Idx` and use the
  per-error `message` accessor to format. This keeps the public
  surface stable while letting the internal shape evolve.
- **Pattern A sealing** — `EmailBlueprint` itself uses the same sealing
  pattern; brace-construction outside the module is a compile error,
  and the smart constructor is the sole construction boundary.

### 8.6. EmailBlueprint Scoping

`EmailBlueprint` is for `Email/set` create only.

`Email/import` has its own type — `EmailImportItem` (defined in
`email.nim`) carrying `blobId: BlobId`, `mailboxIds: NonEmptyMailboxIdSet`,
`keywords: KeywordSet`, `receivedAt: Opt[UTCDate]`. Imports go through
`NonEmptyEmailImportMap = distinct Table[CreationId, EmailImportItem]`
to enforce non-empty creation maps.

`Email/copy` has its own type — `EmailCopyItem` (also in `email.nim`)
carrying `id: Id` (source email), `mailboxIds: Opt[NonEmptyMailboxIdSet]`,
`keywords: Opt[KeywordSet]`, `receivedAt: Opt[UTCDate]`. RFC 8621 §4.7
restricts copy creation to overriding exactly these three properties;
the typed entry constrains to that set.

The three creation-flow types (`EmailBlueprint`, `EmailImportItem`,
`EmailCopyItem`) have overlapping but distinct shapes; they are
deliberately separate per the DDD principle of giving each domain
operation its own type.

### 8.7. EmailUpdate (Update Algebra)

`Email/set` update goes through a closed sum-type ADT rather than a
generic `PatchObject`:

```nim
type EmailUpdateVariantKind* = enum
  euAddKeyword
  euRemoveKeyword
  euSetKeywords
  euAddToMailbox
  euRemoveFromMailbox
  euSetMailboxIds

type EmailUpdate* = object
  case kind*: EmailUpdateVariantKind
  of euAddKeyword, euRemoveKeyword: keyword*: Keyword
  of euSetKeywords:                 keywords*: KeywordSet
  of euAddToMailbox, euRemoveFromMailbox: mailboxId*: Id
  of euSetMailboxIds:               mailboxes*: NonEmptyMailboxIdSet

type EmailUpdateSet* = distinct seq[EmailUpdate]
type NonEmptyEmailUpdates* = distinct Table[Id, EmailUpdateSet]
```

Smart constructors fall into two families:

- **Protocol primitives** (one per variant): `addKeyword`,
  `removeKeyword`, `setKeywords`, `addToMailbox`, `removeFromMailbox`,
  `setMailboxIds`. These map 1:1 to the JMAP wire patch shapes for
  RFC 8621 §4.6 keyword and mailbox updates.
- **Domain-named convenience constructors**: `markRead`, `markUnread`,
  `markFlagged`, `markUnflagged`, `moveToMailbox(id)`. Each desugars
  to a protocol primitive (e.g. `markRead = addKeyword(kwSeen)`) and
  reads as the user intent at the call site.

`initEmailUpdateSet` enforces that a single `Id`'s update set obeys the
RFC 8620 §5.3 "no full-replace alongside sub-path write under the same
parent" rule — for example, you cannot combine `setKeywords(...)` with
`addKeyword(...)` against the same email. The whole-container
`NonEmptyEmailUpdates` enforces that the container itself is non-empty.

The wire patch shape is JSON-Pointer-keyed under `/keywords/<keyword>`
and `/mailboxIds/<mailboxId>` (one entry per `EmailUpdate` for the
set/add/remove primitives, one full-replace key for the
`Set*`/`SetMailboxIds` variants). `serde_email_update.nim` produces
this shape with proper RFC 6901 escaping for keyword tokens.

**Principles:**
- **Make illegal states unrepresentable** — Closed sum type covers
  every legitimate Email patch shape; conflict detection rejects
  illegal combinations.
- **DDD** — Domain-named convenience constructors mirror the actual
  user vocabulary ("mark as read", "move to trash") rather than the
  wire vocabulary.
- **DRY** — Each primitive is one line; convenience constructors
  reuse the primitives.

---

## 9. Entity-Specific Builder Overloads

### 9.1. Decision

For each entity whose standard method has extra parameters, provide a named
builder function in the mail module. Entities without extensions use the core
generic builder unchanged. Entity-specific overloads return entity-specific
response types when the response shape differs from the standard generic
(e.g., `MailboxChangesResponse`), or the standard generic otherwise
(e.g., `GetResponse[Email]`).

### 9.2. Pattern

All entity-specific builder overloads:
- Live under `src/jmap_client/mail/`. The split is by entity rather than
  by method category: Mailbox, Thread, and Email builders sit in
  `mail_builders.nim`; Identity in `identity_builders.nim`;
  EmailSubmission in `submission_builders.nim`; VacationResponse,
  Email/parse, Email/import, SearchSnippet, and the cross-entity
  compound helpers in `mail_methods.nim`.
- Call core's `addInvocation` (or one of its overloads) to accumulate
  the `Invocation`.
- Are `func` (pure). `mixin C.toJson` resolves the filter-condition
  serialiser at the caller's instantiation site, so no callback
  parameter is required to keep the body pure.
- Return `(RequestBuilder, ResponseHandle[T])` tuples. Compound and
  chained helpers return paired handles (see §11).

### 9.3. Overloads

**Email/get → `addEmailGet`:**
```nim
func addEmailGet*(
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = …,
    properties: Opt[seq[string]] = …,
    bodyFetchOptions: EmailBodyFetchOptions = …,
): (RequestBuilder, ResponseHandle[GetResponse[Email]])
```

The body-fetch options control which body content the server returns;
the response envelope shape is the standard generic `GetResponse[Email]`.

**Email/get by back-reference → `addEmailGetByRef`:**
```nim
func addEmailGetByRef*(
    b: RequestBuilder,
    accountId: AccountId,
    idsRef: ResultReference,
    properties: Opt[seq[string]] = …,
    bodyFetchOptions: EmailBodyFetchOptions = …,
): (RequestBuilder, ResponseHandle[GetResponse[Email]])
```

Used inside chained helpers (and by callers wiring custom chains) when
the email IDs come from a previous invocation's result reference rather
than a literal list.

**Thread/get by back-reference → `addThreadGetByRef`:**
```nim
func addThreadGetByRef*(
    b: RequestBuilder,
    accountId: AccountId,
    idsRef: ResultReference,
    properties: Opt[seq[string]] = …,
): (RequestBuilder, ResponseHandle[GetResponse[Thread]])
```

Companion to `addEmailGetByRef`, used in `addEmailQueryWithThreads`
(§11.11) for the thread-IDs hop.

**EmailBodyFetchOptions** (defined in `email.nim`):
```nim
type BodyValueScope* = enum
  bvsNone
  bvsText
  bvsHtml
  bvsTextAndHtml
  bvsAll

type EmailBodyFetchOptions* = object
  bodyProperties*: Opt[seq[PropertyName]]
  fetchBodyValues*: BodyValueScope    # replaces three booleans
  maxBodyValueBytes*: Opt[UnsignedInt]
```

A single `BodyValueScope` enum replaces the RFC's three booleans
(`fetchTextBodyValues`, `fetchHTMLBodyValues`, `fetchAllBodyValues`).
Five enum variants cover the meaningful combinations
(none / text / html / both / all); the "both booleans true" redundant
case becomes `bvsAll` (the canonical RFC mapping).
`serde_email.toExtras` projects the enum back to the three booleans on
the wire so the request shape stays RFC-conformant; the user never
sees the booleans. `default(EmailBodyFetchOptions)` (i.e. `bvsNone`,
no body properties override, no truncation) emits `{}` and matches
the RFC defaults.

**QueryParams** is a core type (`framework.nim`) shared across all
query overloads — see core `00-architecture.md` §1.5.5.

**EmailComparator — mail-specific sort type:**

RFC §4.4.2 requires keyword-based sort properties (`hasKeyword`,
`allInThreadHaveKeyword`, `someInThreadHaveKeyword`) to carry an
additional `keyword` property on the Comparator object. Core's
`Comparator` has no `keyword` field. `EmailComparator` is a
discriminated case object so the `hasKeyword` ↔ `keyword: Keyword`
correspondence is a type-level invariant rather than a smart-constructor
check:

```nim
type PlainSortProperty* = enum
  pspReceivedAt = "receivedAt"
  pspSize       = "size"
  pspFrom       = "from"
  pspTo         = "to"
  pspSubject    = "subject"
  pspSentAt     = "sentAt"

type KeywordSortProperty* = enum
  kspHasKeyword              = "hasKeyword"
  kspAllInThreadHaveKeyword  = "allInThreadHaveKeyword"
  kspSomeInThreadHaveKeyword = "someInThreadHaveKeyword"

type EmailComparatorKind* = enum eckPlain, eckKeyword

type EmailComparator* = object
  isAscending*: Opt[bool]
  collation*: Opt[CollationAlgorithm]
  case kind*: EmailComparatorKind
  of eckPlain:
    property*: PlainSortProperty
  of eckKeyword:
    keywordProperty*: KeywordSortProperty
    keyword*: Keyword
```

Two construction helpers:

- `plainComparator(property, isAscending, collation)` — produces an
  `eckPlain` comparator. Cannot accidentally take a `Keyword`.
- `keywordComparator(keywordProperty, keyword, isAscending, collation)`
  — produces an `eckKeyword` comparator. Cannot omit the `keyword`.

The serde layer (`serde_email.emailComparatorFromJson` /
`toJson(c: EmailComparator)`) emits the property string and (when
present) the keyword as sibling fields per RFC §4.4.2.

**Principles:**
- **DDD** — keyword-on-sort is mail-domain knowledge. Core doesn't know
  what `$flagged` means.
- **Open-Closed** — Core `Comparator` is unchanged. Mail provides
  `EmailComparator` as a parallel typed sort element.
- **Make illegal states unrepresentable** — Type-level. Keyword-less
  `hasKeyword` sorts and keyword-bearing `receivedAt` sorts are
  uncompilable.

**Mailbox/query → `addMailboxQuery`:**
```nim
func addMailboxQuery*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[MailboxFilterCondition]] = …,
    sort: Opt[seq[Comparator]] = …,
    queryParams: QueryParams = QueryParams(),
    sortAsTree: bool = false,
    filterAsTree: bool = false,
): (RequestBuilder, ResponseHandle[QueryResponse[Mailbox]])
```

**Mailbox/queryChanges → `addMailboxQueryChanges`:**
Same parameters as `/query` plus `sinceQueryState`, `maxChanges`,
`upToId`, `calculateTotal`.

**Email/query → `addEmailQuery`:**
```nim
func addEmailQuery*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[EmailFilterCondition]] = …,
    sort: Opt[seq[EmailComparator]] = …,
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = false,
): (RequestBuilder, ResponseHandle[QueryResponse[Email]])
```

`func` (not `proc`) — `mixin EmailFilterCondition.toJson` resolves the
filter-condition serialiser at the caller's instantiation site without
a callback parameter.

**Email/queryChanges → `addEmailQueryChanges`:**
Adds `collapseThreads` to standard `/queryChanges` parameters. Sort
parameter uses `Opt[seq[EmailComparator]]` (same as `addEmailQuery`).

**Email/copy:**
- `addEmailCopy` — simple `/copy`, returns
  `(RequestBuilder, ResponseHandle[CopyResponse[EmailCreatedItem]])`.
- `addEmailCopyAndDestroy` — compound `/copy` + implicit destroy,
  returns `(RequestBuilder, EmailCopyHandles)`. See §11.4.

**Mailbox/changes → `addMailboxChanges`:**
Returns `(RequestBuilder, ResponseHandle[MailboxChangesResponse])`. The
extended response includes `updatedProperties: Opt[seq[string]]`.

**Mailbox/set → `addMailboxSet`:**
```nim
func addMailboxSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = …,
    create: Opt[Table[CreationId, MailboxCreate]] = …,
    update: Opt[NonEmptyMailboxUpdates] = …,
    destroy: Opt[Referencable[seq[Id]]] = …,
    onDestroyRemoveEmails: bool = false,
): (RequestBuilder, ResponseHandle[SetResponse[MailboxCreatedItem]])
```

The `create` map takes `MailboxCreate` (typed creation model — see
§13.1), not `Mailbox`. The `update` map takes `NonEmptyMailboxUpdates`
(typed update algebra), not `PatchObject`. The response carries
`MailboxCreatedItem` (the server-set subset).

`onDestroyRemoveEmails` (RFC 8621 §2.5): when `true`, emails solely in
a destroyed mailbox are also destroyed. When `false` (default), the
server returns a `setMailboxHasEmail` `SetError` for non-empty
mailboxes.

**Email/set → `addEmailSet`:**
```nim
func addEmailSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = …,
    create: Opt[Table[CreationId, EmailBlueprint]] = …,
    update: Opt[NonEmptyEmailUpdates] = …,
    destroy: Opt[Referencable[seq[Id]]] = …,
): (RequestBuilder, ResponseHandle[SetResponse[EmailCreatedItem]])
```

`create` takes `EmailBlueprint`; `update` takes `NonEmptyEmailUpdates`
(see §8.7); the response carries `EmailCreatedItem`.

**VacationResponse/get → `addVacationResponseGet`:**
```nim
func addVacationResponseGet*(
    b: RequestBuilder,
    accountId: AccountId,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[VacationResponse]])
```

Omits `ids` — always fetches the singleton. Lives in `mail_methods.nim`.

**VacationResponse/set → `addVacationResponseSet`:**
```nim
func addVacationResponseSet*(
    b: RequestBuilder,
    accountId: AccountId,
    update: VacationResponseUpdateSet,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[SetResponse[VacationResponse]])
```

Takes `VacationResponseUpdateSet` (the typed update algebra — see
§13.7), not `PatchObject`. The `"singleton"` id is hardcoded internally
via `VacationResponseSingletonId`. No `create`/`destroy` parameters —
the RFC forbids both for the singleton. Lives in `mail_methods.nim`.

**Note:** VacationResponse is NOT registered with `registerJmapEntity`.
Only two of six standard methods are valid, so custom builder functions
prevent invalid method calls at compile time.

**Identity/set → `addIdentitySet` (in `identity_builders.nim`):**
```nim
func addIdentitySet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = …,
    create: Opt[Table[CreationId, IdentityCreate]] = …,
    update: Opt[NonEmptyIdentityUpdates] = …,
    destroy: Opt[Referencable[seq[Id]]] = …,
): (RequestBuilder, ResponseHandle[SetResponse[IdentityCreatedItem]])
```

**Principle:** Make illegal states unrepresentable — every typed
update algebra (`NonEmpty*Updates`) is non-empty by construction, every
typed create model has a smart constructor enforcing required fields.

### 9.4. Entities Using the Generic Builder

- Thread is registered with `registerJmapEntity` and uses core's
  generic `addGet[Thread]` and `addChanges[Thread]` directly. A
  `addThreadGetByRef` wrapper exists for back-reference chains
  (§11.10).
- Identity has its own `addIdentityGet` / `addIdentityChanges` /
  `addIdentitySet` wrappers (in `identity_builders.nim`) for ergonomic
  reasons, but they delegate straight to core's generic builders
  without any RFC-specific extension parameters.

### 9.5. Dispatch Confirmation

Entity-specific response types (`MailboxChangesResponse`) and standard
generics (`GetResponse[Email]`) work with the existing phantom-typed dispatch.
The railway from `ResponseHandle[GetResponse[Email]]` through
`get[GetResponse[Email]]` to `Result[GetResponse[Email], MethodError]` uses
the same mechanism as core's generic dispatch — no core modifications required.

**Principle:** DRY — core provides the dispatch mechanism, mail provides the
types. The phantom type parameterisation handles the rest.

---

## 10. Custom Methods

### 10.1. Decision

Non-standard methods (`Email/import`, `Email/parse`, `SearchSnippet/get`)
and singleton builder functions (`VacationResponse/get`,
`VacationResponse/set`) get custom builder functions in `mail_methods.nim`
with bespoke request/response types. They compose with the existing builder
infrastructure (addInvocation, ResponseHandle, get[T]) without modifying
core.

### 10.2. Options Analysed

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Custom builder functions** | Standalone functions with bespoke types, calling core's `addInvocation`. | Type-safe, discoverable. ResponseHandle[T] phantom typing prevents wrong extraction. No core changes. |
| **B) Extend core builder** | Generic "custom method" support in Layer 3. | Over-engineering for three methods. Adds complexity to core without proportional benefit. |

**Decision: Option A.**

**Principles:**
- **DDD** — These methods belong to the mail domain, not core. Core provides
  the generic mechanism; mail provides the domain-specific methods.
- **Make illegal states unrepresentable** — `addEmailImport` returns
  `ResponseHandle[EmailImportResponse]`, not `ResponseHandle[GetResponse[Email]]`.
  The phantom type prevents wrong extraction at compile time.
- **Total functions** — Builder functions return `ResponseHandle[T]`
  (infallible). `get[T]` returns `Result[T, MethodError]` (total).
- **Railway-Oriented Programming** — Track 0 (construction), Track 1
  (transport), Track 2 (method errors) all work unchanged.

### 10.3. Email/import

**Request types** (defined in `email.nim`):

```nim
type EmailImportItem* = object
  blobId*: BlobId
  mailboxIds*: NonEmptyMailboxIdSet  # at least one — type-level guarantee
  keywords*: KeywordSet              # default: empty (allowed)
  receivedAt*: Opt[UTCDate]          # default: server time

type NonEmptyEmailImportMap* = distinct Table[CreationId, EmailImportItem]
```

There is no separate `EmailImportRequest` envelope object — the
builder takes the parameters directly. The non-empty creation map is
type-enforced via `NonEmptyEmailImportMap`.

**Response type** (defined in `email.nim`):

```nim
type EmailImportResponse* = object
  accountId*: AccountId
  oldState*: Opt[JmapState]
  newState*: Opt[JmapState]   # Stalwart 0.15.5 omits when only failures populated
  createResults*: Table[CreationId, Result[EmailCreatedItem, SetError]]
```

The `createResults` map carries `Result[EmailCreatedItem, SetError]`.
`EmailCreatedItem` is the shared four-field server-set shape (RFC §4.6 /
§4.7 / §4.8):

```nim
type EmailCreatedItem* = object
  id*: Id
  blobId*: BlobId
  threadId*: Id
  size*: UnsignedInt
```

Used identically for `Email/set` create (`SetResponse[EmailCreatedItem]`),
`Email/copy` create (`CopyResponse[EmailCreatedItem]`), and
`Email/import` create (`EmailImportResponse.createResults`). The shape
is small and uniform enough that typing it pays back across the three
operations.

**Builder:**
```nim
func addEmailImport*(
    b: RequestBuilder,
    accountId: AccountId,
    emails: NonEmptyEmailImportMap,
    ifInState: Opt[JmapState] = …,
): (RequestBuilder, ResponseHandle[EmailImportResponse])
```

**Duplicate detection:** RFC §4.8 permits servers to reject duplicate
imports with `alreadyExists` (a core `SetErrorType` variant carrying
typed `existingId: Id`). Some servers enforce duplicate detection,
others do not; consumers must handle both outcomes. All RFC 8621
SetError variants live on core's `SetErrorType` (§4.3).

### 10.4. Email/parse

**Response type** (defined in `mail_methods.nim`):

```nim
type EmailParseResponse* = object
  accountId*: AccountId
  parsed*: Table[BlobId, ParsedEmail]   # blobId → ParsedEmail
  notParseable*: seq[BlobId]            # wire key "notParsable" (RFC typo)
  notFound*: seq[BlobId]
```

The `notParseable` Nim field maps to the RFC's wire key `notParsable`
(the RFC has the typo, the Nim field corrects it; the serde layer
translates).

**Builder:**
```nim
func addEmailParse*(
    b: RequestBuilder,
    accountId: AccountId,
    blobIds: seq[BlobId],
    properties: Opt[seq[string]] = …,
    bodyFetchOptions: EmailBodyFetchOptions = …,
): (RequestBuilder, ResponseHandle[EmailParseResponse])
```

`blobIds: seq[BlobId]` — typed (not `seq[Id]`). Returns `ParsedEmail`
values (not `Email`) inside the response (different aggregate, different
invariants — see §8.3).

### 10.5. SearchSnippet/get

**Response type** (defined in `mail_methods.nim`):

```nim
type SearchSnippetGetResponse* = object
  accountId*: AccountId
  list*: seq[SearchSnippet]
  notFound*: seq[Id]
  # No state — stateless by design
```

**Builder:**
```nim
func addSearchSnippetGet*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    firstEmailId: Id,
    restEmailIds: seq[Id],
): (RequestBuilder, ResponseHandle[SearchSnippetGetResponse])
```

The "at-least-one-emailId" invariant is encoded in the parameter list:
`firstEmailId: Id` is required, `restEmailIds: seq[Id]` is the
zero-or-more remainder. This eliminates the need for a runtime
non-empty check at the smart-constructor boundary — the type
signature makes empty input uncompilable.

A back-reference variant is also provided for wiring to a previous
query result:

```nim
func addSearchSnippetGetByRef*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    emailIdsRef: ResultReference,
): (RequestBuilder, ResponseHandle[SearchSnippetGetResponse])
```

Used inside `addEmailQueryWithSnippets` (§11.11) to chain query → snippet
in a single request.

Key differences from standard `/get`:
- `filter` is required (not `Opt`) — a null filter produces vacuous
  results.
- No `state` in response — stateless derived data.
- `SearchSnippet` has no `id` property (keyed by `emailId`).

**Duplicate emailIds:** Passed through to server (which handles deduplication
per RFC). Builder behaviour is defined and total.

**Method-level errors:** `requestTooLarge` and `unsupportedFilter` are core
`MethodErrorType` variants (defined in RFC 8620's error space). No
mail-specific error classification needed; standard
`Result[T, MethodError]` railway.

### 10.6. Railway Consistency

Across all three custom methods:
- Builder functions return `ResponseHandle[T]` (infallible)
- `get[T](response, handle)` returns `Result[T, MethodError]`
- Response types carry per-item errors as data (`notCreated`, `notParseable`,
  `notFound`) on the success rail
- Smart constructors on request types accumulate errors
  (`Result[T, seq[ValidationError]]`)
- All types are immutable value objects, constructed once and passed by value

---

## 11. Compound and Chained Handles

### 11.1. Decision

Generic compound and chained handle types live in core's `dispatch.nim`.
Mail's compound and chained helpers all flow through these generics
rather than entity-specific paired types:

```nim
type NameBoundHandle*[T] = object  # callId + methodName for §5.4 dispatch
  callId*: MethodCallId
  methodName*: MethodName

type CompoundHandles*[A, B] = object
  primary*: ResponseHandle[A]      # primary invocation's response
  implicit*: NameBoundHandle[B]    # implicit invocation sharing the call ID

type CompoundResults*[A, B] = object
  primary*: A
  implicit*: B

type ChainedHandles*[A, B] = object
  first*: ResponseHandle[A]        # first invocation
  second*: ResponseHandle[B]       # second invocation, separate call ID

type ChainedResults*[A, B] = object
  first*: A
  second*: B

func getBoth[A, B](resp: Response, handles: CompoundHandles[A, B]
                   ): Result[CompoundResults[A, B], MethodError]
func getBoth[A, B](resp: Response, handles: ChainedHandles[A, B]
                   ): Result[ChainedResults[A, B], MethodError]
```

Compound vs chained:

- **Compound** — two invocations share a single `MethodCallId` because
  the server treats them as one method (RFC 8620 §5.4). The implicit
  invocation's response carries a different method *name* under the same
  call ID; `NameBoundHandle[B]` carries the call ID *and* the expected
  method name so dispatch can disambiguate.
- **Chained** — two invocations have separate call IDs and the second
  references the first via a JMAP back-reference. Both handles are
  ordinary `ResponseHandle`.

`registerCompoundMethod(Primary, Implicit)` and
`registerChainableMethod(Primary)` are the compile-time registration
templates that participate in entity-framework type checking.

Mail uses these generic types via domain-named aliases (e.g.
`EmailCopyHandles = CompoundHandles[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]`).
The aliases preserve readability at the call site; the generics own
the dispatch logic.

### 11.2. Options Analysed

| Option | Description | Trade-offs |
|--------|-------------|------------|
| **A) Explicit helper for each compound** | One named function per RFC compound (`addEmailSubmissionSetWithImplicitEmailSet`, etc.). | Verbose names. No shared dispatch machinery. |
| **B) Compound-handle pair, per-method paired types** | Each compound returns its own paired handle type (e.g. `EmailSubmissionSetHandles`). | Domain-named handles, but the paired types repeat the same shape per method. |
| **Modified B — overloaded by operation, paired handles via generic core type** | Domain-named *aliases* over `CompoundHandles[A, B]` / `ChainedHandles[A, B]`. | Single dispatch implementation in core; mail keeps the readable alias names. |

**Decision: Modified B.** Aliases pay for themselves at the call site
without duplicating the dispatch implementation.

### 11.3. EmailSubmission/set + implicit Email/set (§7.5 ¶3)

RFC 8621 §7.5 ¶3 defines the implicit `Email/set` that runs after
`EmailSubmission/set` when `onSuccessUpdateEmail` or
`onSuccessDestroyEmail` is non-empty. Both invocations share the
parent call ID; the wire protocol treats them as one bundled method.

**Type alias** (in `submission_builders.nim`):
```nim
type EmailSubmissionHandles* =
  CompoundHandles[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]
```

**Simple overload:**
```nim
func addEmailSubmissionSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = …,
    create: Opt[Table[CreationId, EmailSubmissionBlueprint]] = …,
    update: Opt[NonEmptyEmailSubmissionUpdates] = …,
    destroy: Opt[Referencable[seq[Id]]] = …,
): (RequestBuilder, ResponseHandle[EmailSubmissionSetResponse])
```

**Compound overload:**
```nim
func addEmailSubmissionAndEmailSet*(
    b: RequestBuilder,
    accountId: AccountId,
    create: Opt[Table[CreationId, EmailSubmissionBlueprint]] = …,
    update: Opt[NonEmptyEmailSubmissionUpdates] = …,
    destroy: Opt[Referencable[seq[Id]]] = …,
    onSuccessUpdateEmail: Opt[NonEmptyOnSuccessUpdateEmail] = …,
    onSuccessDestroyEmail: Opt[NonEmptyOnSuccessDestroyEmail] = …,
    ifInState: Opt[JmapState] = …,
): (RequestBuilder, EmailSubmissionHandles)
```

The compound name `addEmailSubmissionAndEmailSet` reads as the actual
operation — submit and apply side-effects — and matches
`addEmailCopyAndDestroy` (§11.4) for naming consistency.

Three creation models:

- `EmailSubmissionBlueprint` — sealed Pattern A creation type
  (module-private `raw*` fields with same-name UFCS accessors), built
  via `parseEmailSubmissionBlueprint(identityId, emailId, envelope)`
  which returns `Result[EmailSubmissionBlueprint, seq[ValidationError]]`.
- `NonEmptyOnSuccessUpdateEmail = distinct Table[IdOrCreationRef, EmailUpdateSet]`
  — non-empty by construction; the on-success update map uses the
  same `EmailUpdateSet` algebra as `Email/set` (§8.7).
- `NonEmptyOnSuccessDestroyEmail = distinct seq[IdOrCreationRef]` —
  non-empty by construction.

### 11.4. Email/copy + implicit Email/set (§4.7)

RFC 8621 §4.7 defines `onSuccessDestroyOriginal: bool` on
`Email/copy`. When `true`, the server destroys the original after a
successful copy and produces an implicit `Email/set` destroy response
sharing the parent call ID.

**Type aliases** (in `mail_builders.nim`):
```nim
type EmailCopyHandles* =
  CompoundHandles[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]
type EmailCopyResults* =
  CompoundResults[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]
```

**Simple overload:**
```nim
func addEmailCopy*(
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, EmailCopyItem],
    ifFromInState: Opt[JmapState] = …,
    ifInState: Opt[JmapState] = …,
): (RequestBuilder, ResponseHandle[CopyResponse[EmailCreatedItem]])
```

Default `destroyMode` is `keepOriginals()` from core's
`methods.CopyDestroyMode`.

**Compound overload:**
```nim
func addEmailCopyAndDestroy*(
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, EmailCopyItem],
    ifFromInState: Opt[JmapState] = …,
    ifInState: Opt[JmapState] = …,
    destroyFromIfInState: Opt[JmapState] = …,
): (RequestBuilder, EmailCopyHandles)
```

Routes through core's `addCopy` with `destroyMode =
destroyAfterSuccess(destroyFromIfInState)`. Returns a
`CompoundHandles` whose `implicit` is filtered by `mnEmailSet` so
extraction picks the implicit `Email/set` destroy response.

### 11.5. EmailCopyItem (typed creation entry)

```nim
type EmailCopyItem* = object
  id*: Id
  mailboxIds*: Opt[NonEmptyMailboxIdSet]  # override destination mailboxes
  keywords*: Opt[KeywordSet]              # override keywords
  receivedAt*: Opt[UTCDate]               # override received date
```

`mailboxIds` uses `NonEmptyMailboxIdSet` (not `MailboxIdSet`) — when
the caller overrides the mailbox set, it must be non-empty;
`Opt.none` keeps the source mailbox set intact.

`Opt.none` on each field means "keep the source value";
`Opt.some(value)` means "override". When all three override fields
are `Opt.none`, the serde layer emits `{}` (copy with no overrides —
the most common case).

### 11.6. IdOrCreationRef

Keys in `onSuccessUpdateEmail` and elements of `onSuccessDestroyEmail`
are either creation references (`#creationId`) or direct Email IDs.
The structured case object lives in `email_submission.nim` because the
shape is also useful for any other compound that mixes IDs and
creation references:

```nim
type IdOrCreationRefKind* = enum
  icrDirect      # references a persisted Id
  icrCreation    # forward-references a sibling create

type IdOrCreationRef* = object
  case kind*: IdOrCreationRefKind
  of icrDirect:    id*:         Id
  of icrCreation:  creationId*: CreationId
```

Smart constructors `directRef(id: Id)` and `creationRef(cid: CreationId)`
are infallible. Arm-dispatched `==` and `hash` honour the
`a == b ⇒ hash(a) == hash(b)` Table contract: a `directRef(Id("abc"))`
and a `creationRef(CreationId("abc"))` mix the discriminator ordinal
into the hash so they land in different buckets even when payload
strings coincide.

The wire form is rendered by `idOrCreationRefWireKey` (in
`serde_email_submission.nim`): the underlying `Id` verbatim for
`icrDirect`, or `"#"` concatenated with the underlying `CreationId`
for `icrCreation`. The `"#"` prefix is a wire concern — added at
serialisation time, not stored on the `CreationId`.

**Principles:**
- **Make illegal states unrepresentable** — Eliminates malformed
  `#`-prefixed strings at the type level.
- **Parse, don't validate** — Parsed at the serde boundary
  (`"#foo"` → `icrCreation`, `"msg123"` → `icrDirect`); after
  parsing, no code ever inspects string prefixes.

### 11.7. Response Location

Compound dispatch uses `NameBoundHandle[B].methodName` to filter the
implicit response by name. Both invocations share the parent call
ID; the method name in the invocation tuple distinguishes them. No
core changes were needed beyond the addition of `NameBoundHandle`
and the corresponding `get[T]` overload.

### 11.8. getBoth

`getBoth` is the generic core extractor — the same function works
for `EmailCopyHandles`, `EmailSubmissionHandles`, and any other
`CompoundHandles[A, B]` / `ChainedHandles[A, B]`. There are no
mail-specific `getBoth` overloads; callers use the core generic.

**Principles:**
- **Total functions** — `getBoth` defines behaviour for every
  response shape (including a missing implicit response, which
  flows through as a `MethodError` rather than a panic).
- **Railway-Oriented Programming** — First error short-circuits via
  `?`. The railway doesn't fork.
- **DRY** — One `getBoth` implementation for both compound and
  chained pairs (two overloads, same body shape).

### 11.9. Mail-side aliases over the generics

| Mail-side type             | Definition                                                                                                       |
|----------------------------|------------------------------------------------------------------------------------------------------------------|
| `QueryGetHandles[T]`       | Lives in core's `convenience.nim` — generic over the queried entity.                                             |
| `EmailCopyHandles`         | `CompoundHandles[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]`                                 |
| `EmailCopyResults`         | `CompoundResults[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]`                                 |
| `EmailSubmissionHandles`   | `CompoundHandles[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]`                                     |
| `EmailSubmissionResults`   | `CompoundResults[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]`                                     |
| `EmailQuerySnippetChain`   | `ChainedHandles[QueryResponse[Email], SearchSnippetGetResponse]`                                                 |

`getBoth` is one generic implementation in core. New compound
methods elsewhere in the library (or in extension RFCs) get the same
machinery without entity-specific paired types.

### 11.10. ChainedHandles in mail (§4.10 workflows)

`ChainedHandles[A, B]` (and a custom four-handle record
`EmailQueryThreadChain`) underpin two RFC 8621 §4.10 first-login
workflow helpers:

- `addEmailQueryWithSnippets` (in `mail_methods.nim`) — chains
  `Email/query` to `SearchSnippet/get` via a `/ids` back-reference;
  returns `EmailQuerySnippetChain =
  ChainedHandles[QueryResponse[Email], SearchSnippetGetResponse]`.
- `addEmailQueryWithThreads` (in `mail_builders.nim`) — chains
  four invocations (Email/query → Email/get for thread IDs →
  Thread/get → Email/get for display properties) to implement the
  RFC §4.10 example. The generic two-element `ChainedHandles[A, B]`
  is not expressive enough for four steps, so this helper returns a
  custom `EmailQueryThreadChain` record with four named
  `ResponseHandle` fields (`queryH`, `threadIdFetchH`, `threadsH`,
  `displayH`) plus a co-located `getAll` extractor returning
  `EmailQueryThreadResults`.

The `addEmailQueryWithThreads` helper:
- `filter` is mandatory (RFC §4.10 ¶1 — first-login always filters
  to a user-visible mailbox scope).
- `collapseThreads` defaults to `true` (RFC §4.10 example).
- `displayProperties` defaults to `DefaultDisplayProperties`
  (the nine fields enumerated in the RFC: `threadId`, `mailboxIds`,
  `keywords`, `hasAttachment`, `from`, `subject`, `receivedAt`,
  `size`, `preview`).
- `displayBodyFetchOptions` defaults to `bvsAll` body values with
  256-byte truncation.

Back-reference paths come from typed `RefPath` constants
(`rpIds`, `rpListThreadId`, `rpListEmailIds`) — no stringly-typed
JSON Pointers at the call site.

---

## 12. Filter Conditions

### 12.1. Decision

Three filter condition types, one per queryable entity. Filter conditions are
query specifications (value objects), not domain entities — they don't need
smart constructors beyond what types enforce, with one exception
(`EmailHeaderFilter`).

### 12.2. Options Analysed

No option analysis needed — the approach follows directly from the existing
`Filter[C]` generic in core. The design decisions are about the condition
types themselves and their field types.

### 12.3. MailboxFilterCondition

```nim
type MailboxFilterCondition* = object
  parentId*: Opt[Opt[Id]]               # three-state: absent / null / value
  name*: Opt[string]                    # contains match
  role*: Opt[Opt[MailboxRole]]          # three-state: absent / null / value (typed)
  hasAnyRole*: Opt[bool]
  isSubscribed*: Opt[bool]
```

`role` is `Opt[Opt[MailboxRole]]` (typed — `MailboxRole` from
`mailbox.nim`) rather than `Opt[Opt[string]]`. The type promotes the
filter to the same well-known/vendor-extension model as the entity
itself, and the `mrOther` catch-all preserves vendor role strings
verbatim through filter round-trips.

**The `Opt[Opt[T]]` pattern:** RFC 8621 distinguishes between "this filter
property is not specified" (omit from JSON) and "this filter property matches
null" (include as `null` in JSON). For `parentId` and `role`, `null` is a
meaningful filter value (top-level mailboxes, no-role mailboxes):
- `Opt.none` = not filtering on this property
- `Opt.some(Opt.none)` = filtering for null
- `Opt.some(Opt.some(value))` = filtering for specific value

The double-wrapping looks unusual but encodes a real three-state domain.

### 12.4. EmailFilterCondition

```nim
type EmailFilterCondition* = object
  inMailbox*: Opt[Id]
  inMailboxOtherThan*: Opt[seq[Id]]       # non-empty when present
  before*: Opt[UTCDate]
  after*: Opt[UTCDate]
  minSize*: Opt[UnsignedInt]
  maxSize*: Opt[UnsignedInt]
  allInThreadHaveKeyword*: Opt[Keyword]
  someInThreadHaveKeyword*: Opt[Keyword]
  noneInThreadHaveKeyword*: Opt[Keyword]
  hasKeyword*: Opt[Keyword]
  notKeyword*: Opt[Keyword]
  hasAttachment*: Opt[bool]
  text*: Opt[string]
  fromAddr*: Opt[string]                  # consistent with Email.fromAddr naming
  to*: Opt[string]
  cc*: Opt[string]
  bcc*: Opt[string]
  subject*: Opt[string]
  body*: Opt[string]
  header*: Opt[EmailHeaderFilter]
```

**`fromAddr`** — consistent naming with `Email.fromAddr` for the `from`
keyword collision. Applied everywhere.

**`Keyword` type on filter fields** — `hasKeyword`, `notKeyword`, etc. use
`Opt[Keyword]`, not `Opt[string]`. The `Keyword` type provides validation.
No per-field validation needed.

**`inMailboxOtherThan`** — when present, must be non-empty (empty exclusion
is a no-op). Validated at construction or documented as contract.

### 12.5. EmailHeaderFilter

The RFC's `header` filter takes a `String[]` of 1–2 elements. A structured
type eliminates empty arrays, 3+ elements, and untyped positional semantics:

```nim
type EmailHeaderFilter* = object
  name*: string                  # required, non-empty
  value*: Opt[string]            # optional value to match
```

**This is the one filter type that needs a smart constructor** — `name` must
be non-empty.

**Principle:** Make illegal states unrepresentable — structured type instead
of `String[]` with positional semantics.

### 12.6. EmailSubmissionFilterCondition

```nim
type EmailSubmissionFilterCondition* = object
  identityIds*: Opt[NonEmptyIdSeq]   # non-empty by type
  emailIds*: Opt[NonEmptyIdSeq]      # non-empty by type
  threadIds*: Opt[NonEmptyIdSeq]     # non-empty by type
  undoStatus*: Opt[UndoStatus]
  before*: Opt[UTCDate]
  after*: Opt[UTCDate]
```

**Location** — `EmailSubmissionFilterCondition` lives in
`email_submission.nim`, not in `mail_filters.nim`. Dependency
ordering: the filter type depends on `UndoStatus` (defined in
`submission_status.nim`) and on `NonEmptyIdSeq` (defined in
`email_submission.nim`). Putting the filter into `mail_filters.nim`
would introduce a backward dependency into the submission graph, and
`mail_filters.nim` is otherwise free of submission-specific types.

**`NonEmptyIdSeq`** — defined in `email_submission.nim`. Constructed
via `parseNonEmptyIdSeq(items: openArray[Id])`. Encodes "non-empty
when present" at the type level. The filter condition cannot represent
a present-but-empty ID list. Sealed `len`, `[]: Idx`, `head`, `items`
read surface; mutating operations are deliberately not borrowed.

**`UndoStatus` enum** — defined in `submission_status.nim`:

```nim
type UndoStatus* = enum
  usPending  = "pending"
  usFinal    = "final"
  usCanceled = "canceled"
```

Closed three-value enum with no catch-all. RFC 8621 §7 mandates
exactly these three values and treats unknown ones as a protocol
violation; the parser fails on unknown `undoStatus` rather than
silently accepting them. `UndoStatus` doubles as the phantom-type
parameter of `EmailSubmission[S: static UndoStatus]` (§13.6).

**`EmailSubmissionComparator`** — lives in `email_submission.nim`,
separate from the protocol-level `Comparator` because the
`EmailSubmission/query` sort property names are entity-specific
(`emailId`, `threadId`, `sentAt` per RFC §7.4):

```nim
type EmailSubmissionSortProperty* = enum
  esspEmailId  = "emailId"
  esspThreadId = "threadId"
  esspSentAt   = "sentAt"
  esspOther                          # vendor-extension catch-all

type EmailSubmissionComparator* = object
  property*:    EmailSubmissionSortProperty
  rawProperty*: string                # round-trip carrier; authoritative for esspOther
  isAscending*: bool
  collation*:   Opt[CollationAlgorithm]
```

`parseEmailSubmissionComparator(rawProperty, isAscending, collation)`
classifies the wire token and stores it verbatim in `rawProperty`.
The serde layer always emits `rawProperty` on the wire — for the
three RFC-defined properties it equals `$property`; for `esspOther`
it carries the only authoritative value. `EmailSubmission/query`
preserves the RFC's wire-token / entity-field-name mismatch
(`sentAt` on the wire ↔ `sendAt` on the entity).

**Principles preserved:**
- **Make illegal states unrepresentable** — `Opt[UndoStatus]` instead
  of `Opt[string]`. Empty ID lists unrepresentable.
- **DDD** — `UndoStatus` and the filter live with the entity, not
  with the cross-entity filter module.

### 12.7. Opt[Opt[T]] Serde Three-Way Dispatch

The `Opt[Opt[T]]` deserialisation for `parentId` and `role` requires explicit
three-way dispatch:
- Absent key in JSON → `Opt.none` (not filtering)
- Present key with `null` value → `Opt.some(Opt.none)` (filtering for null)
- Present key with value → `Opt.some(Opt.some(parsed))` (filtering for value)

This must be explicitly implemented and thoroughly tested in
`serde_mail_filters.nim`.

### 12.8. Filter Conditions as Value Objects

Filter conditions are query specifications, not domain entities:
- They describe criteria, they have no identity, they're equal by structure
- They don't need id fields or smart constructors beyond what the types enforce
- Construction is infallible (all fields are `Opt` — assembling a query, not
  validating data)
- The railway matters at the serde boundary (`fromJson` returns `Result`), not
  at the construction boundary

The one exception is `EmailHeaderFilter`, which needs a smart constructor for
the non-empty name constraint.

**Principles:**
- **DDD** — Value objects, not entities.
- **Railway-Oriented Programming** — Construction is infallible. The railway
  applies at the serde boundary where JSON is parsed into these types.

### 12.9. Integration with Filter[C]

These plug directly into core's `Filter[C]` generic:
- `Filter[MailboxFilterCondition]` for `addMailboxQuery`
- `Filter[EmailFilterCondition]` for `addEmailQuery` and `addSearchSnippetGet`
- `Filter[EmailSubmissionFilterCondition]` for `addEmailSubmissionQuery`

Core provides the recursive tree structure (`Filter[C]`, `FilterOperator`).
Mail provides the condition types and their `toJson` callbacks. The `toJson`
callbacks are `func` (pure, `{.noSideEffect.}`).

### 12.10. DRY Considerations

- `before: Opt[UTCDate]` / `after: Opt[UTCDate]` appear on both
  `EmailFilterCondition` and `EmailSubmissionFilterCondition`. A `DateRange`
  value object could be shared. Noted as potential extraction — deferred
  unless the pattern appears a third time.
- Keyword filter fields (`hasKeyword`, `notKeyword`,
  `allInThreadHaveKeyword`, `someInThreadHaveKeyword`,
  `noneInThreadHaveKeyword`) all use `Opt[Keyword]` — the `Keyword` type
  itself provides the DRY validation.

---

## 13. Per-Entity Summary

Quick reference for each entity's methods, key properties, and design notes.

### 13.1. Mailbox

| Aspect | Detail |
|--------|--------|
| Module | `mailbox.nim` (read/role/rights/create/update), `mailbox_changes_response.nim` (extended /changes response) |
| Methods | `/get`, `/changes` (extra: `updatedProperties`), `/query` (extra: `sortAsTree`, `filterAsTree`), `/queryChanges`, `/set` (extra: `onDestroyRemoveEmails`) |
| Read model | `Mailbox` (id, name, parentId, role, sortOrder, count fields, myRights, isSubscribed) |
| Created-item model | `MailboxCreatedItem` (id required; count fields and myRights `Opt[T]` for Stalwart leniency) |
| Create model | `MailboxCreate` (name + optional parentId/role/sortOrder/isSubscribed; smart constructor enforces non-empty name) |
| Update algebra | `MailboxUpdate` (5 variants: setName, setParentId, setRole, setSortOrder, setIsSubscribed); `MailboxUpdateSet`; `NonEmptyMailboxUpdates` (whole-container, non-empty by type) |
| Key sub-types | `MailboxRole` (case object: 10 IANA + `mrOther` extension), `MailboxRights` (clustered booleans — Decision B6), `MailboxIdSet` (distinct HashSet[Id]), `NonEmptyMailboxIdSet` |
| Filter conditions | `MailboxFilterCondition` — `parentId: Opt[Opt[Id]]`, `role: Opt[Opt[MailboxRole]]`, `name`, `hasAnyRole`, `isSubscribed` |
| Sort properties | `sortOrder`, `name` (uses core protocol-level `Comparator`) |
| Builder overloads | `addMailboxQuery` (sortAsTree, filterAsTree), `addMailboxQueryChanges`, `addMailboxChanges` (returns `MailboxChangesResponse`), `addMailboxSet` (onDestroyRemoveEmails) |
| Roles | Typed enum `MailboxRoleKind` (10 RFC values) + `mrOther` for vendor extensions; constants `roleInbox`, `roleDrafts`, etc. |
| Design notes | `MailboxRole` is a typed case object — sealed Pattern A (private `rawKind` / `rawIdentifier` fields with `kind`, `identifier`, `$`, `==`, `hash` accessors) so vendor extensions round-trip losslessly. `MailboxRights` is the canonical clustered-bool exception (nine independent ACL flags — see core architecture §6.4). |

### 13.2. Thread

| Aspect | Detail |
|--------|--------|
| Module | `thread.nim` |
| Methods | `/get`, `/changes` |
| Type | `Thread` (sealed; module-private `rawId`, `rawEmailIds`; constructed via `parseThread(id, emailIds)` which enforces non-empty `emailIds`) |
| Builder | Uses generic `addGet[Thread]`, `addChanges[Thread]` — no extensions; also `addThreadGetByRef` for back-reference chains |
| Design notes | Simplest entity. No filter, no query, no set. Sealed read model with public `id()` and `emailIds()` accessors. |

### 13.3. Email

| Aspect | Detail |
|--------|--------|
| Modules | `email.nim` (read/parse/comparator/created-item/copy/import), `email_blueprint.nim` (creation error vocabulary), `email_update.nim` (update algebra) |
| Methods | `/get` (extra: body fetch options), `/changes`, `/query` (extra: `collapseThreads`), `/queryChanges` (extra: `collapseThreads`), `/set`, `/copy` (compound: `onSuccessDestroyOriginal`), `/import`, `/parse` |
| Read models | `Email` (store-backed), `ParsedEmail` (blob-backed via `Email/parse`) |
| Created-item model | `EmailCreatedItem` (4 fields: id, blobId, threadId, size — shared by /set, /copy, /import) |
| Creation models | `EmailBlueprint` (full create), `EmailImportItem` (import via blob), `EmailCopyItem` (cross-account copy) |
| Update algebra | `EmailUpdate` (6 variants), `EmailUpdateSet`, `NonEmptyEmailUpdates`. Smart constructors: `addKeyword`, `removeKeyword`, `setKeywords`, `addToMailbox`, `removeFromMailbox`, `setMailboxIds`. Convenience: `markRead`, `markUnread`, `markFlagged`, `markUnflagged`, `moveToMailbox(id)`. |
| Key sub-types | `EmailAddress`, `EmailAddressGroup`, `EmailHeader`, `HeaderForm`, `HeaderPropertyKey`, `HeaderValue`, `BlueprintEmailHeaderName`, `BlueprintBodyHeaderName`, `BlueprintHeaderMultiValue`, `EmailBodyPart` (read), `BlueprintBodyPart` (creation), `BlueprintLeafPart` (nested case), `EmailBodyValue`, `BlueprintBodyValue`, `PartId`, `ContentDisposition`, `KeywordSet`, `MailboxIdSet`, `NonEmptyMailboxIdSet`, `EmailComparator` (typed case), `EmailBodyFetchOptions`, `BodyValueScope` |
| Filter conditions | `EmailFilterCondition` (in `mail_filters.nim`) — 20 fields including thread-keyword filters, `EmailHeaderFilter` |
| Sort properties | `EmailComparator` typed case object: `eckPlain` (`PlainSortProperty`: receivedAt, size, from, to, subject, sentAt) or `eckKeyword` (`KeywordSortProperty`: hasKeyword, allInThreadHaveKeyword, someInThreadHaveKeyword) with required `keyword: Keyword` |
| Builder overloads | `addEmailGet`, `addEmailGetByRef`, `addEmailQuery`, `addEmailQueryChanges`, `addEmailSet`, `addEmailCopy`, `addEmailCopyAndDestroy` (compound, §11.4), `addEmailQueryWithThreads` (4-handle chain, §11.10) |
| Custom methods | `addEmailImport`, `addEmailParse`, `addEmailQueryWithSnippets` (chained: query + SearchSnippet/get) |
| Mutability | Only `mailboxIds` and `keywords` mutable after creation, enforced by the closed `EmailUpdate` ADT |
| Design notes | Most complex entity. Four distinct types across read/parse/create directions. `EmailComparator` is a typed case object discriminated on `eckPlain` / `eckKeyword`. `EmailBlueprint` is a sealed Pattern A Layer 1 aggregate built via `parseEmailBlueprint(...)` returning `Result[EmailBlueprint, EmailBlueprintErrors]`; the body is a separate `EmailBlueprintBody` case object (`ebkStructured` / `ebkFlat`). |

### 13.4. SearchSnippet

| Aspect | Detail |
|--------|--------|
| Module | `snippet.nim` |
| Properties | `emailId: Id`, `subject: Opt[string]`, `preview: Opt[string]` |
| Methods | Custom `/get` variant (required filter, no state) |
| Custom methods | `addSearchSnippetGet` (firstEmailId + restEmailIds), `addSearchSnippetGetByRef` (back-reference variant) |
| Design notes | No `id` property. Stateless derived data. Uses `Filter[EmailFilterCondition]` (same as Email/query). Subject/preview contain HTML `<mark>` tags. The non-empty emailIds invariant is encoded in the parameter list (`firstEmailId: Id` plus `restEmailIds: seq[Id]`) rather than enforced by a runtime smart constructor. |

### 13.5. Identity

| Aspect | Detail |
|--------|--------|
| Modules | `identity.nim` (types + update algebra), `identity_builders.nim` (Layer 3 builders), `serde_identity_update.nim` (update serde) |
| Methods | `/get`, `/changes`, `/set` |
| Read model | `Identity` (id, name, email, replyTo, bcc, textSignature, htmlSignature, mayDelete) |
| Created-item model | `IdentityCreatedItem` (id required; mayDelete `Opt[bool]` for Stalwart leniency) |
| Create model | `IdentityCreate` (email + optional name/replyTo/bcc/signatures; smart constructor enforces non-empty email) |
| Update algebra | `IdentityUpdate` (5 variants: setName, setReplyTo, setBcc, setTextSignature, setHtmlSignature), `IdentityUpdateSet`, `NonEmptyIdentityUpdates` |
| Builder | `addIdentityGet`, `addIdentityChanges`, `addIdentitySet` (in `identity_builders.nim`) |
| Design notes | `email` is immutable after creation (no `setEmail` variant in `IdentityUpdate`). `IdentityCreate` is a distinct creation type. |

### 13.6. EmailSubmission

| Aspect | Detail |
|--------|--------|
| Modules | `email_submission.nim` (entity, blueprint, update, filter, comparator, created-item, set-response, IdOrCreationRef, NonEmptyOnSuccess*), `submission_atoms.nim` (RFC5321Keyword, OrcptAddrType), `submission_mailbox.nim` (RFC5321Mailbox), `submission_param.nim` (12-variant SubmissionParam), `submission_envelope.nim` (Envelope, ReversePath, NonEmptyRcptList), `submission_status.nim` (UndoStatus, DeliveryStatus, ParsedSmtpReply), `submission_builders.nim` (Layer 3 builders) |
| Methods | `/get`, `/changes`, `/query`, `/queryChanges`, `/set`, `/set` compound (§11.3) |
| Read model | `EmailSubmission[S: static UndoStatus]` — phantom-indexed GADT; existential wrapper `AnyEmailSubmission` (case discriminated on `state: UndoStatus`) for storage paths that don't statically know the state |
| Created-item model | `EmailSubmissionCreatedItem` (`id: Id` plus optional `threadId`, `sendAt`, `undoStatus`; servers diverge on what they emit — Stalwart 0.15.5 emits only `id`, Cyrus 3.12.2 emits all four for fire-and-forget lifecycle clients) |
| Create model | `EmailSubmissionBlueprint` (sealed Pattern A — module-private `raw*` fields with same-name UFCS accessors; constructed via `parseEmailSubmissionBlueprint(identityId, emailId, envelope)` returning `Result[EmailSubmissionBlueprint, seq[ValidationError]]`) |
| Update algebra | `EmailSubmissionUpdate` (one variant: `esuSetUndoStatusToCanceled`; the only legal update). `cancelUpdate(s: EmailSubmission[usPending])` is type-safe — only pending submissions can be cancelled. `NonEmptyEmailSubmissionUpdates` for the whole container. |
| Filter conditions | `EmailSubmissionFilterCondition` — `identityIds: Opt[NonEmptyIdSeq]`, `emailIds`, `threadIds`, `undoStatus`, date range. **Lives in `email_submission.nim`**, not `mail_filters.nim`. |
| Sort properties | `EmailSubmissionComparator` plain record (lives in `email_submission.nim`): `property: EmailSubmissionSortProperty` (`esspEmailId`/`esspThreadId`/`esspSentAt`/`esspOther`) plus `rawProperty: string` round-trip carrier, `isAscending: bool`, `collation: Opt[CollationAlgorithm]`. Wire token `sentAt` deliberately ≠ entity field `sendAt` (RFC quirk). |
| Builder overloads | `addEmailSubmissionGet`, `addEmailSubmissionChanges`, `addEmailSubmissionQuery`, `addEmailSubmissionQueryChanges`, `addEmailSubmissionSet` (plain), `addEmailSubmissionAndEmailSet` (compound with implicit Email/set) |
| Design notes | Phantom-indexed GADT lifts RFC §7 "only pending may be cancelled" into the type system. `AnyEmailSubmission` is a Pattern A sealed existential wrapper (private `rawPending` / `rawFinal` / `rawCanceled` fields, exposed via `asPending` / `asFinal` / `asCanceled` projecting to `Opt[EmailSubmission[S]]`). `IdOrCreationRef` handles `#creationId` vs direct-ID keys. Compound handle uses generic `CompoundHandles[A, B]` from core. |

**Sub-type design decisions:**

**`UndoStatus`** — closed three-value enum (no catch-all):

```nim
type UndoStatus* = enum
  usPending = "pending"
  usFinal = "final"
  usCanceled = "canceled"
```

RFC §7 mandates exactly three values; an unknown value is a parse
error, not a forward-compatibility concern. Doubles as the phantom
type parameter of `EmailSubmission[S: static UndoStatus]`.

**`DeliveredState` and `DisplayedState`** — open-world enums with
`*Other` catch-all and lossless raw preservation via wrapper types:

```nim
type DeliveredState* = enum
  dsQueued = "queued"
  dsYes    = "yes"
  dsNo     = "no"
  dsUnknown = "unknown"
  dsOther                  # vendor extension; raw preserved alongside

type ParsedDeliveredState* = object
  state*: DeliveredState
  rawBacking*: string

type DisplayedState* = enum
  dpUnknown = "unknown"
  dpYes     = "yes"
  dpOther                  # vendor extension; raw preserved alongside

type ParsedDisplayedState* = object
  state*: DisplayedState
  rawBacking*: string
```

Both live in `submission_status.nim`. `dsOther`/`dpOther` carry the
verbatim wire string in the wrapper's `rawBacking` field — same
lossless round-trip pattern as `MailboxRole`.

**`DeliveryStatus`** — composite of three parsed values:

```nim
type DeliveryStatus* = object
  smtpReply*: ParsedSmtpReply       # RFC 5321 §4.2 reply code + RFC 3463 enhanced status
  delivered*: ParsedDeliveredState
  displayed*: ParsedDisplayedState
```

`ParsedSmtpReply` holds a typed `ReplyCode` (3-digit), an optional
`EnhancedStatusCode` (class.subject.detail), the human-readable text,
and the verbatim raw line. The enhanced-status grammar lives in
`submission_status.nim` (`StatusCodeClass`, `SubjectCode`,
`DetailCode`).

**`SubmissionAddress`** (`submission_envelope.nim`) — distinct from
`EmailAddress`. The RFC's envelope `Address` is an RFC 5321 mailbox,
not an RFC 5322 address; the type uses a validated `RFC5321Mailbox`
rather than a plain string:

```nim
type SubmissionAddress* = object
  mailbox*:    RFC5321Mailbox       # RFC 5321 §4.1.2 (full grammar)
  parameters*: Opt[SubmissionParams]
```

`RFC5321Mailbox` is validated against the full RFC 5321 §4.1.2
grammar — `Local-part "@" ( Domain / address-literal )` with
length caps from §4.5.3.1.1 / §4.5.3.1.2 — covering IPv4, all four
IPv6 forms (full / comp / v4-full / v4-comp), and General-address-literal.

`SubmissionParams = distinct OrderedTable[SubmissionParamKey, SubmissionParam]`
is a duplicate-free, wire-order-preserving bag of typed
`SubmissionParam` values. Twelve variants — eleven IANA-registered
(`BODY`, `SMTPUTF8`, `SIZE`, `ENVID`, `RET`, `NOTIFY`, `ORCPT`,
`HOLDFOR`, `HOLDUNTIL`, `BY`, `MT-PRIORITY`) plus `spkExtension` for
unregistered / vendor tokens. `SubmissionParamKey` projects each
parameter to its uniqueness axis (kind-only for the well-known arms;
kind + `RFC5321Keyword` for `spkExtension`). Twelve smart
constructors live in `submission_param.nim` —
`bodyParam` / `byParam` / `envidParam` / `extensionParam` /
`holdForParam` / `holdUntilParam` / `mtPriorityParam` / `notifyParam` /
`orcptParam` / `retParam` / `sizeParam` / `smtpUtf8Param`. Most are
infallible; `notifyParam` and `parseSubmissionParams` accumulate
errors.

**`Envelope`** carries `mailFrom: ReversePath` (case object: null
path with optional params, or concrete mailbox) and `rcptTo:
NonEmptyRcptList` (non-empty by type — sealed via
`parseNonEmptyRcptList` for client construction and
`parseNonEmptyRcptListFromServer` for Postel-lenient receive).

### 13.7. VacationResponse

| Aspect | Detail |
|--------|--------|
| Module | `vacation.nim` |
| Methods | `/get`, `/set` (update only — no create, no destroy) |
| Properties | `isEnabled: bool`, `fromDate: Opt[UTCDate]`, `toDate: Opt[UTCDate]`, `subject: Opt[string]`, `textBody: Opt[string]`, `htmlBody: Opt[string]`. No `id` field — the `"singleton"` id is the constant `VacationResponseSingletonId` (`"singleton"`); serde validates on deserialise and emits on serialise. |
| Update algebra | `VacationResponseUpdate` (6 variants — one per property), `VacationResponseUpdateSet`. Constructors: `setIsEnabled`, `setFromDate`, `setToDate`, `setSubject`, `setTextBody`, `setHtmlBody`. |
| Entity registration | NOT registered with `registerJmapEntity`. Custom builder functions prevent invalid method calls at compile time. |
| Builder functions | `addVacationResponseGet` (omits `ids` — always fetches singleton), `addVacationResponseSet` (takes `VacationResponseUpdateSet`, singleton id hardcoded internally). Both in `mail_methods.nim`. |
| Design notes | Singleton pattern — exactly one per account. The builder takes a typed `VacationResponseUpdateSet`, consistent with the typed update algebras used by every other entity (§8.7). |

---

## Appendix A: Decision Traceability Matrix

| # | Decision | Options | Chosen | Primary Principles |
|---|----------|---------|--------|-------------------|
| 1 | Module location | A) Flat, B) Nested `mail/`, C) Nested by layer | B | DDD, Open-Closed |
| 2 | Sub-type organisation | A) One shared module, B) By semantic domain, C) In parent entity | B (addresses + headers + body) | DDD, SRP |
| 3 | Capabilities boundary | A) Typed variants on core, B) Raw + parse on demand | B | DDD, Parse-don't-validate, Open-Closed |
| 4 | Errors boundary | A) Extend core enum, B) String matching, C) Mail-layer enum | **A** — RFC 8621 SetError variants in core; mail provides typed accessors only | Make illegal states unrepresentable, ROP, Total functions, DRY (one parser) |
| 5 | Method extensions | A) Mail builder functions, B) Core extras param | A | DDD, DRY, Immutability |
| 6 | Header parsed forms | A) JsonNode map, B) Typed HeaderValue, C) Convenience only | B + convenience fields | Parse-don't-validate, Make illegal states unrepresentable |
| 7 | Body structure | A) All optional, B) Case object by multipart, C) Separate types | B | Make illegal states unrepresentable, Parse-don't-validate, Total functions |
| 8 | Email creation type | A) Plain record with `Opt[T]` everywhere, B) Sealed Pattern A aggregate built via `parseEmailBlueprint` accumulating constraint errors, with body XOR encoded in a separate `EmailBlueprintBody` case object | **B** — `EmailBlueprint` (sealed L1) + `EmailBlueprintBody` (`ebkStructured` / `ebkFlat`) + `EmailBlueprintConstraint` / `EmailBlueprintError` / sealed `EmailBlueprintErrors` accumulator | Make illegal states unrepresentable, Total functions, Parse-don't-validate |
| 9 | Non-standard methods | A) Custom builder functions, B) Extend core builder | A | DDD, Make illegal states unrepresentable, ROP |
| 10 | EmailSubmission chaining | A) Explicit helper, B) Per-method paired type, Modified B) Aliases over generic `CompoundHandles[A, B]` | **Modified B** — `addEmailSubmissionAndEmailSet` returns `EmailSubmissionHandles`, an alias for `CompoundHandles[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]` | DDD, Make illegal states unrepresentable, DRY |
| 11 | Keyword type | Distinct type with lowercase normalisation + system constants | `Keyword = distinct string` | Parse-don't-validate, Make illegal states unrepresentable, DRY |
| 12 | Email read model sets | `Table[K, bool]` vs `HashSet[K]` | `MailboxIdSet`, `KeywordSet` (distinct HashSet) | Make illegal states unrepresentable, DDD |
| 13 | ParsedEmail vs Email | Shared type with Opt.none vs distinct type | Distinct `ParsedEmail` | Parse-don't-validate, DDD |
| 14 | EmailBlueprint naming | Lifecycle name vs domain name | `EmailBlueprint` (domain concept) | DDD |
| 15 | EmailBlueprint errors | Short-circuit vs accumulate | Sealed `EmailBlueprintErrors` accumulator with read-only iteration | Total functions, ROP |
| 16 | VacationResponse builder | A) Register + generic builder, B) Custom get/set only (not registered) | B (`addVacationResponseGet`, `addVacationResponseSet` in `mail_methods.nim`; singleton id hardcoded; no create/destroy; takes `VacationResponseUpdateSet`) | Make illegal states unrepresentable, DDD |
| 17 | QueryParams DRY | A) Repeat the four `/query` params on each builder, B) Single `QueryParams` value object | **B** — `QueryParams` lives in core `framework.nim` and is shared across `addMailboxQuery`, `addEmailQuery`, `addEmailSubmissionQuery` | DRY |
| 18 | EmailBodyFetchOptions DRY | Repeated params vs value object | `EmailBodyFetchOptions` value object with `BodyValueScope` enum (replaces three booleans) | DRY, Make illegal states unrepresentable |
| 19 | Id-or-creation-ref key | A) String with `#` prefix, B) Case type | **B** — `IdOrCreationRef` case object (`icrDirect` / `icrCreation`); arm-dispatched `==` and `hash` mix the discriminator ordinal so coincident payload strings hash into different buckets | Make illegal states unrepresentable, Parse-don't-validate |
| 20 | UndoStatus | A) String, B) Closed enum, C) Open-world enum with catch-all | **B** — closed three-value enum (`usPending` / `usFinal` / `usCanceled`) in `submission_status.nim`; doubles as the phantom-type parameter of `EmailSubmission[S: static UndoStatus]` | Make illegal states unrepresentable, DDD |
| 21 | Filter conditions as smart-constructed | Smart constructors vs plain construction | Plain construction (value objects). Exception: `EmailHeaderFilter` | DDD (value objects), ROP |
| 22 | Opt[Opt[T]] for null-filterable fields | Opt[T] vs Opt[Opt[T]] vs sentinel | `Opt[Opt[T]]` | Make illegal states unrepresentable |
| 23 | Mailbox/set builder overload | Generic /set vs entity-specific with onDestroyRemoveEmails | `addMailboxSet` with extra param | DDD, Make illegal states unrepresentable |
| 24 | Email/copy compound handle | A) Single builder accepting a destroy flag, B) Two builders (simple + compound) with paired handle for the compound | **B** — `addEmailCopy` returns `ResponseHandle[CopyResponse[EmailCreatedItem]]`; `addEmailCopyAndDestroy` returns `EmailCopyHandles = CompoundHandles[CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem]]` | DDD, Make illegal states unrepresentable, DRY |
| 25 | `size` unconditional on `EmailBodyPart` | A) Leaf-only, B) Shared | B (RFC §4.1.4 unconditional) | Total functions |
| 26 | RFC 8621 SetError integration | A) Mail enum + parser, B) Variants on core `SetErrorType` with payload-bearing case branches | **B** — same decision as #4; mail-side accessors in `mail_errors.nim` provide domain-named projection | Make illegal states unrepresentable, ROP, DRY |
| 27 | Inline body values placement on `EmailBlueprint` | A) Top-level `bodyValues` table; B) Per-leaf `value` field, harvested at serde | B — leaf carries `BlueprintBodyValue`; serde produces top-level wire `bodyValues` | Make illegal states unrepresentable |
| 28 | Email sort with keyword property | A) Core Comparator, B) Core extras, C) `EmailComparator` composing `Comparator`, D) Discriminated case object | **D** — `EmailComparator` case object (`eckPlain` / `eckKeyword`) with type-level keyword/property correspondence | DDD, Open-Closed, Make illegal states unrepresentable |
| 29 | Creation body part type | A) Reuse read model, B) Flat 3-way type, C) Nested case object | C — preserves `isMultipart` structure, factors `BlueprintLeafPart` out for error addressing | Make illegal states unrepresentable, DDD |
| 30 | `EmailGetResponse` vs `GetResponse[Email]` | A) Custom type, B) Standard generic | B (response envelope identical) | DRY |
| 31 | `EmailCopyItem` typed creation entry | A) Untyped JSON, B) Typed `EmailCopyItem` | B — `mailboxIds: Opt[NonEmptyMailboxIdSet]` (typed non-empty) | Make illegal states unrepresentable, DDD |
| 32 | Email/import response item shape | A) Full `Email`, B) `Result[JsonNode, SetError]`, C) Typed `EmailCreatedItem` shared with /set and /copy | **C** — `Result[EmailCreatedItem, SetError]` shared across /set, /copy, /import | DRY, Make illegal states unrepresentable, Parse-don't-validate |
| 33 | DeliveredState / DisplayedState | A) String, B) Enum with catch-all + raw preservation | **B** — open-world enums with `dsOther`/`dpOther` catch-alls; `Parsed*State` wrapper preserves raw | Make illegal states unrepresentable, DDD |
| 34 | SubmissionAddress vs EmailAddress | A) Reuse EmailAddress, B) Distinct type with typed `RFC5321Mailbox` and typed `SubmissionParams` | **B** — full RFC 5321 grammar (IPv4 / four IPv6 forms / General-address-literal); `SubmissionParams` is a duplicate-free bag of typed 12-variant `SubmissionParam` keyed on `SubmissionParamKey` | DDD, Make illegal states unrepresentable |
| 35 | EmailSubmission identity | A) Plain object with `undoStatus: UndoStatus` field, B) Phantom-indexed GADT | **B** — `EmailSubmission[S: static UndoStatus]` + sealed Pattern A existential `AnyEmailSubmission` lift the "only pending may be cancelled" RFC §7 invariant into the type system; `cancelUpdate(s: EmailSubmission[usPending])` is type-safe | Make illegal states unrepresentable, DDD |
| 36 | Submission file split | A) Single `submission.nim`, B) Six files | **B** — `submission_atoms`, `submission_mailbox`, `submission_param`, `submission_envelope`, `submission_status`, `email_submission` | DDD, SRP |
| 37 | Update algebras | A) `PatchObject`, B) Closed sum-type ADT per entity with `NonEmptyXxxUpdates` aggregator | **B** — `EmailUpdate`, `MailboxUpdate`, `IdentityUpdate`, `EmailSubmissionUpdate`, `VacationResponseUpdate`, each aggregated into `NonEmptyXxxUpdates` | Make illegal states unrepresentable, DDD, Parse-don't-validate |
| 38 | `MailboxRole` representation | A) `string`, B) Typed case object with `mrOther` extension catch-all | **B** — typed `MailboxRoleKind` enum + `mrOther` rawIdentifier; constants for ten IANA roles | Make illegal states unrepresentable, DDD |
| 39 | Compound / chained handles | A) Per-method paired types, B) Generic `CompoundHandles[A, B]` / `ChainedHandles[A, B]` in core with mail-side aliases | **B** — generic types in core dispatch; mail uses aliases (`EmailCopyHandles`, `EmailSubmissionHandles`, `EmailQuerySnippetChain`); the four-handle `EmailQueryThreadChain` is a custom record because the two-element generic is not expressive enough | DRY, Open-Closed |
| 40 | Builder accumulation | A) `var RequestBuilder` mutation, B) Pure tuple-returning funcs | **B** — `(RequestBuilder, ResponseHandle[T])` tuples; matches core's immutable-builder convention | Immutability by default, Functional core |
| 41 | `ContentDisposition` | A) `Opt[string]`, B) Typed case object with extension catch-all | **B** — `cdInline` / `cdAttachment` / `cdExtension` (raw preserved); constants for the two RFC values | Make illegal states unrepresentable, DDD |
| 42 | Blueprint header surface | A) Reuse `Table[HeaderPropertyKey, HeaderValue]`, B) Separate `BlueprintEmailHeaderName` / `BlueprintBodyHeaderName` distinct types + `BlueprintHeaderMultiValue` (7-variant) | **B** — top-level vs body-part allowed sets differ; `NonEmptySeq[T]` per variant for `:all` cardinality | Make illegal states unrepresentable, Parse-don't-validate |
| 43 | `Email` field optionality | A) Required-where-RFC-mandates, B) `Opt[T]` uniformly across metadata | **B** — accommodates client-controlled property selection and Stalwart server omissions | Total functions, Postel's law on receive |
| 44 | `EmailSubmissionComparator` shape | A) Discriminated case (mirroring `EmailComparator`), B) Plain record with `property` enum + `rawProperty` round-trip carrier | **B** — RFC §7.4 sort properties carry no extra payload, so the case object brings no invariant; the plain record with an open-world `esspOther` catch-all preserves vendor extensions losslessly | DDD, Total functions |
