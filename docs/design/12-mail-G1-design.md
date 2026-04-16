# RFC 8621 JMAP Mail — Design G1: EmailSubmission — Specification

Part G opens the submission lifecycle. Parts A–F1 delivered Mailbox, Thread,
Email (read path, query, creation, copy, import), Identity, VacationResponse,
and the typed update algebra that replaced `PatchObject`. Part G wires those
foundations into the final major RFC 8621 entity: **EmailSubmission** (§7) —
the object that represents "a message has been submitted for delivery."

This document (G1) is the type-level specification. Part G2 (test
specification) is deferred to a separate companion document.

Part G also introduces the library's first use of **GADT-style phantom state
indexing** adapted to Nim's type system: `EmailSubmission[S: static UndoStatus]`
with an `AnyEmailSubmission` existential wrapper at the serde boundary. This
lets the type system enforce that cancellation is only attempted on pending
submissions — moving the invariant from runtime checks into the type. The
design extends the compound-handle pattern from F1's `EmailCopyHandles` into
the cross-entity form `EmailSubmissionHandles`, where the two handles span
`EmailSubmission/set` and an implicit `Email/set`.

## Table of Contents

- §1. Scope
- §2. Envelope + Address Vocabulary
- §3. UndoStatus / DeliveryStatus Vocabulary
- §4. EmailSubmission Entity Read Model
- §5. EmailSubmissionBlueprint (Creation)
- §6. EmailSubmissionUpdate + Update Algebra
- §7. Serde (SerdeViolation + JsonPath)
- §8. Method Builders
- §9. Cross-Entity Compound Builder
- §10. SetError Extensions Reference
- §11. Capability Refinements
- §12. Roadmap Appendix
- §13. Decision Traceability Matrix

---

## 1. Scope

### 1.1. Methods Covered

| Method | RFC 8621 | Builder | Response type | Notes |
|--------|----------|---------|---------------|-------|
| `EmailSubmission/get` | §7.1 | `addEmailSubmissionGet` | `GetResponse[AnyEmailSubmission]` | Standard `/get`. |
| `EmailSubmission/changes` | §7.2 | `addEmailSubmissionChanges` | `ChangesResponse` | Standard `/changes`. |
| `EmailSubmission/query` | §7.3 | `addEmailSubmissionQuery` | `QueryResponse` | Typed `EmailSubmissionFilterCondition` + `EmailSubmissionComparator`. |
| `EmailSubmission/queryChanges` | §7.4 | `addEmailSubmissionQueryChanges` | `QueryChangesResponse` | Standard `/queryChanges`. |
| `EmailSubmission/set` | §7.5 | `addEmailSubmissionSet` | `EmailSubmissionSetResponse` | Simple overload; no `onSuccess*` args. |
| `EmailSubmission/set` (compound) | §7.5 | `addEmailSubmissionAndEmailSet` | `EmailSubmissionHandles` → `EmailSubmissionResults` | Compound: triggers implicit `Email/set` via `onSuccessUpdateEmail` / `onSuccessDestroyEmail` (G20, G22). |

### 1.2. Supporting Types Introduced

| Type | Module | Rationale |
|------|--------|-----------|
| `RFC5321Mailbox` | `submission_envelope.nim` | Distinct string for RFC 5321 `Mailbox` production (`Local-part "@" ( Domain / address-literal )`). Separates SMTP mailbox grammar from RFC 5322 addr-spec at the type level (G6). |
| `RFC5321Keyword` | `submission_envelope.nim` | Distinct string for RFC 5321 `esmtp-keyword` grammar. Used for SMTP extension parameter names and submission capability keys (G8, G25). |
| `SubmissionAddress` | `submission_envelope.nim` | `RFC5321Mailbox` + `Opt[SubmissionParams]`. RFC §7's Envelope Address type — distinct from `EmailAddress`; parameters nullable per RFC (G6, G34). |
| `SubmissionParamKind` | `submission_envelope.nim` | 12-variant sealed enum (11 well-known SMTP extensions + `spkExtension` catch-all). |
| `SubmissionParam` | `submission_envelope.nim` | Case object with per-variant typed payloads (enums, distinct newtypes, dates) (G8c). |
| `SubmissionParamKey` | `submission_envelope.nim` | Case-object identity key for `SubmissionParams` Table (G8a). |
| `SubmissionParams` | `submission_envelope.nim` | `distinct OrderedTable[SubmissionParamKey, SubmissionParam]`. Structural uniqueness (G8a). |
| `ReversePath` | `submission_envelope.nim` | Two-variant sum: `rpkNullPath` (SMTP `<>`, with `Opt[SubmissionParams]`) or `rpkMailbox` (`SubmissionAddress`). Models `Reverse-path = Path / "<>"` at `Envelope.mailFrom` (G32). |
| `Envelope` | `submission_envelope.nim` | `mailFrom: ReversePath` + `rcptTo: NonEmptyRcptList`. |
| `NonEmptyRcptList` | `submission_envelope.nim` | `distinct seq[SubmissionAddress]` with strict/lenient parser pair (G7). |
| `UndoStatus` | `submission_status.nim` | 3-variant string-backed enum: `usPending`, `usFinal`, `usCanceled`. Also serves as the phantom type parameter for `EmailSubmission` (G3). |
| `DeliveredState` | `submission_status.nim` | 5-variant enum (4 RFC-defined + `dsOther` catch-all) with `ParsedDeliveredState` wrapper (G10). |
| `DisplayedState` | `submission_status.nim` | 3-variant enum (2 RFC-defined + `dpOther` catch-all) with `ParsedDisplayedState` wrapper (G11). |
| `SmtpReply` | `submission_status.nim` | Distinct string; smart constructor validates surface shape (G12). |
| `DeliveryStatus` | `submission_status.nim` | `smtpReply: SmtpReply` + `delivered: ParsedDeliveredState` + `displayed: ParsedDisplayedState`. |
| `DeliveryStatusMap` | `submission_status.nim` | `distinct Table[RFC5321Mailbox, DeliveryStatus]` (G9). |
| `EmailSubmission[S: static UndoStatus]` | `email_submission.nim` | GADT-style phantom-parameterised read model (G2, G3). |
| `AnyEmailSubmission` | `email_submission.nim` | Existential wrapper: case object discriminated on `UndoStatus`, carrying phantom-indexed branches (G2). |
| `EmailSubmissionBlueprint` | `email_submission.nim` | Creation model: `identityId` + `emailId` + `Opt[Envelope]`. Accumulating-error smart constructor (G13, G14, G15). |
| `EmailSubmissionUpdate` | `email_submission.nim` | Single-variant case object (`esuSetUndoStatusToCanceled`) with protocol-primitive + phantom-typed domain-named constructors (G16). |
| `NonEmptyEmailSubmissionUpdates` | `email_submission.nim` | `distinct Table[Id, EmailSubmissionUpdate]` (G17). |
| `EmailSubmissionFilterCondition` | `email_submission.nim` | Typed filter with `Opt[NonEmptyIdSeq]` list fields + `Opt[UndoStatus]` (G18). |
| `NonEmptyIdSeq` | `email_submission.nim` | `distinct seq[Id]` with non-empty smart constructor (G18). |
| `EmailSubmissionSortProperty` | `email_submission.nim` | 4-variant enum (3 RFC-mandated + `esspOther` catch-all) with `EmailSubmissionComparator` (G19). |
| `EmailSubmissionSetResponse` | `email_submission.nim` | Response for `EmailSubmission/set`. |
| `EmailSubmissionHandles` | `email_submission.nim` | Compound-handle record: `submission: ResponseHandle[...]` + `emailSet: NameBoundHandle[...]` (G21). |
| `EmailSubmissionResults` | `email_submission.nim` | Extraction target of `getBoth(EmailSubmissionHandles)` (G21). |
| `IdOrCreationRef` | `email_submission.nim` | Two-variant sum: existing `Id` or `CreationId` reference. Models RFC 8620 §5.3 creation references in `onSuccess*` keys — distinct from `Referencable[T]` which models §3.7 result references (G35). |
| `SubmissionExtensionMap` | `mail_capabilities.nim` (amended) | `distinct OrderedTable[RFC5321Keyword, seq[string]]`. Tightens existing `SubmissionCapabilities` (G25). |

Supporting enums and distinct newtypes for SMTP parameter payloads:
`BodyEncoding`, `DsnRetType`, `DsnNotifyFlag`, `OrcptAddrType`,
`DeliveryByMode`, `HoldForSeconds`, `MtPriority` — all in
`submission_envelope.nim` (G8b, G8c).

### 1.3. Deferred

- **Part G2 (Test Specification):** Companion document for EmailSubmission
  unit, serde, property, and compliance tests. Scoped out of G1 by user
  request.
- **Generic `CompoundHandles[A, B]`:** F1's Rule-of-Three (F3) still
  holds — two compound-handle sites (`EmailCopyHandles`,
  `EmailSubmissionHandles`) is under threshold. Part H or later may promote
  to generic once a third instance materialises (G21).
- **`SmtpReply` structured parser:** G12 adopted a distinct-string approach
  with Reply-code range validation. A future refinement may add
  `parseSmtpReplyStructured` returning a
  `(ReplyCode, Opt[EnhancedStatusCode], String)` tuple per RFC 3463.

### 1.4. RFC §7 Constraint Table

| RFC ref | Constraint | Nim type |
|---------|-----------|----------|
| §7 ¶3 | `identityId` MUST reference a valid Identity in the account | `Id` (referential; server-authoritative) |
| §7 ¶3 | `emailId` MUST reference a valid Email in the account | `Id` (referential; server-authoritative) |
| §7 ¶3 | `threadId` is immutable, server-set | Not in `EmailSubmissionBlueprint`; only on read model |
| §7 ¶4 | `envelope` is immutable; if null, server synthesises from Email headers | `Opt[Envelope]` on blueprint (G14); `Opt[Envelope]` on entity |
| §7 ¶5 | `envelope.mailFrom` cardinality: exactly 1; MAY be empty string (null reverse path); parameters permitted on null path (RFC 5321 §4.1.1.2) | `ReversePath` (`rpkNullPath` carrying `Opt[SubmissionParams]`, or `rpkMailbox` carrying `SubmissionAddress`) (G32) |
| §7 ¶5 | `envelope.rcptTo` cardinality: 1..N | `NonEmptyRcptList` (distinct seq + smart ctor) (G7) |
| §7 ¶5 | `envelope.Address.email` is RFC 5321 Mailbox | `RFC5321Mailbox` (distinct string) (G6) |
| §7 ¶5 | `envelope.Address.parameters` is `Object|null` | `Opt[SubmissionParams]` on `SubmissionAddress` (G34) |
| §7 ¶5 | `envelope.Address.parameters` keys are RFC 5321 esmtp-keywords | `SubmissionParamKey` + `RFC5321Keyword` (G8, G8a) |
| §7 ¶7 | `undoStatus` values: "pending", "final", "canceled" | `UndoStatus` enum (also phantom type parameter) (G3) |
| §7 ¶7 | Only transition: "pending" → "canceled" via client update | `cancelUpdate(s: EmailSubmission[usPending])` typed arrow (G4) |
| §7 ¶8 | `deliveryStatus` is per-recipient, keyed on email address | `DeliveryStatusMap` (distinct Table keyed on `RFC5321Mailbox`) (G9) |
| §7 ¶8 | `delivered` values: "queued", "yes", "no", "unknown" | `DeliveredState` enum + `dsOther` catch-all (G10) |
| §7 ¶8 | `displayed` values: "unknown", "yes" | `DisplayedState` enum + `dpOther` catch-all (G11) |
| §7 ¶8 | `smtpReply` is structured SMTP reply text | `SmtpReply` (distinct string, validated) (G12) |
| §7 ¶9 | `dsnBlobIds`, `mdnBlobIds` are server-set arrays | `seq[BlobId]` on read model only |
| §7.5 ¶1 | Only `undoStatus` updatable post-create | `EmailSubmissionUpdate` single variant (G16) |
| §7.5 ¶3 | `onSuccessUpdateEmail` applies PatchObject to Email on success | `Table[IdOrCreationRef, EmailUpdateSet]` (G22, G35) |
| §7.5 ¶3 | `onSuccessDestroyEmail` destroys Email on success | `seq[IdOrCreationRef]` (G22, G35) |
| §7.5 ¶5 | SetError `invalidEmail` includes problematic property names | Existing `setInvalidEmail` + `invalidEmailPropertyNames*: seq[string]` (G23) |
| §7.5 ¶5 | SetError `tooManyRecipients` includes max count | Existing `setTooManyRecipients` + `maxRecipientCount*: UnsignedInt` (G23) |
| §7.5 ¶5 | SetError `noRecipients` when rcptTo empty | Existing `setNoRecipients` (G23) |
| §7.5 ¶5 | SetError `invalidRecipients` includes bad addresses | Existing `setInvalidRecipients` + `invalidRecipients*: seq[string]` (G23) |
| §7.5 ¶5 | SetError `forbiddenMailFrom` when SMTP MAIL FROM disallowed | Existing `setForbiddenMailFrom` (G23) |
| §7.5 ¶5 | SetError `forbiddenFrom` when RFC 5322 From disallowed | Existing `setForbiddenFrom` (G23) |
| §7.5 ¶5 | SetError `forbiddenToSend` when user lacks send permission | Existing `setForbiddenToSend` (G23) |
| §7.5 ¶6 | SetError `cannotUnsend` when cancel fails | Existing `setCannotUnsend` (G23) |
| §1.3.2 | Capability `maxDelayedSend` is `UnsignedInt` seconds | Existing `SubmissionCapabilities.maxDelayedSend` |
| §1.3.2 | Capability `submissionExtensions` is EHLO-name → args map | `SubmissionExtensionMap` (distinct OrderedTable) (G25) |

### 1.5. Module Summary

| Module | Layer | Status | Contents |
|--------|-------|--------|----------|
| `submission_envelope.nim` | L1 | **New** | `RFC5321Mailbox`, `RFC5321Keyword`, `SubmissionAddress`, `SubmissionParamKind`, `SubmissionParam`, `SubmissionParamKey`, `SubmissionParams`, `ReversePath`, `Envelope`, `NonEmptyRcptList`, all parameter-payload enums/newtypes (`BodyEncoding`, `DsnRetType`, `DsnNotifyFlag`, `OrcptAddrType`, `DeliveryByMode`, `HoldForSeconds`, `MtPriority`). |
| `submission_status.nim` | L1 | **New** | `UndoStatus`, `DeliveredState`, `ParsedDeliveredState`, `DisplayedState`, `ParsedDisplayedState`, `SmtpReply`, `DeliveryStatus`, `DeliveryStatusMap`. |
| `email_submission.nim` | L1 | **New** | `EmailSubmission[S: static UndoStatus]`, `AnyEmailSubmission`, `IdOrCreationRef`, `EmailSubmissionBlueprint`, `EmailSubmissionUpdate`, `NonEmptyEmailSubmissionUpdates`, `EmailSubmissionFilterCondition`, `NonEmptyIdSeq`, `EmailSubmissionSortProperty`, `EmailSubmissionComparator`, `EmailSubmissionSetResponse`, `EmailSubmissionHandles`, `EmailSubmissionResults`. |
| `serde_email_submission.nim` | L2 | **New** | Serde for all three L1 modules. `SerdeViolation` + `JsonPath` throughout. Single or split TBD at implementation. |
| `submission_builders.nim` | L3 | **New** | Builders for all 5 methods + compound `addEmailSubmissionAndEmailSet`. Entity registration for EmailSubmission. |
| `mail_capabilities.nim` | L1 | **Amended** | `SubmissionCapabilities.submissionExtensions` tightened from `OrderedTable[string, seq[string]]` to `SubmissionExtensionMap` (G25). |
| `mail_entities.nim` | L3 | **Extended** | EmailSubmission entity registration (capability URI, method namespace). |
| `serialisation.nim` | — | **Extended** | Re-export of new serde module(s). |

---

## 2. Envelope + Address Vocabulary

All types in this section live in `submission_envelope.nim` under
`{.push raises: [], noSideEffect.}`.

### 2.1. RFC5321Mailbox

RFC 8621 §7's `Address.email` field uses the RFC 5321 `Mailbox` production
(`Local-part "@" ( Domain / address-literal )`, §4.1.2) — distinct from the
RFC 5322 `addr-spec` used in Email headers (`EmailAddress.email`). The
distinct newtype prevents cross-use at the type level (G6).

```nim
type RFC5321Mailbox* = distinct string

func `==`*(a, b: RFC5321Mailbox): bool {.borrow.}
func `$`*(a: RFC5321Mailbox): string {.borrow.}
func hash*(a: RFC5321Mailbox): Hash {.borrow.}

func parseRFC5321Mailbox*(raw: string): Result[RFC5321Mailbox, ValidationError]
func parseRFC5321MailboxFromServer*(raw: string): Result[RFC5321Mailbox, ValidationError]
```

The strict parser validates the full RFC 5321 `Mailbox` grammar at
client-construction time: `Dot-string` and `Quoted-string` local-parts,
`Domain` and `address-literal` (IPv4, IPv6, General-address-literal) domain
forms. The lenient parser validates structural shape only (non-empty, no
control characters, contains `@`) for server-received data — Postel's law.
Neither parser handles the enclosing `Path` production (`"<" [ A-d-l ":" ]
Mailbox ">"`); source routes are part of `Path`, not `Mailbox`, and are
irrelevant at the JMAP layer.

### 2.2. RFC5321Keyword

SMTP extension keywords (`esmtp-keyword` per RFC 5321 §4.1.2:
`(ALPHA / DIGIT) *(ALPHA / DIGIT / "-")`). Used as parameter names in
`SubmissionParam.spkExtension` and as capability keys in
`SubmissionExtensionMap` (G8, G25).

```nim
type RFC5321Keyword* = distinct string

func `==`*(a, b: RFC5321Keyword): bool
func `$`*(a: RFC5321Keyword): string {.borrow.}
func hash*(a: RFC5321Keyword): Hash

func parseRFC5321Keyword*(raw: string): Result[RFC5321Keyword, ValidationError]
```

Validates: starts with ASCII letter or digit, followed by
letters/digits/hyphens, length >= 1. Single parser — no strict/lenient pair
(the grammar is unambiguous; server-sent and client-sent values share the
same constraints). Note: `esmtp-keyword`'s trailing `*(ALPHA / DIGIT / "-")`
permits trailing hyphens, unlike `Ldh-str` (`*( ALPHA / DIGIT / "-" )
Let-dig`) which must end with a letter or digit. The `RFC5321Mailbox` parser
must enforce the stricter `Ldh-str` rule for `Standardized-tag` inside
`General-address-literal`, while `RFC5321Keyword` uses the more permissive
`esmtp-keyword` production.

`==` and `hash` are case-insensitive (ASCII case-fold), matching RFC 5321
§2.4 ("extension name keywords are not case sensitive") and §4.1.1.1 ("EHLO
keywords… MUST always be recognized and processed in a case-insensitive
manner"). This ensures correct Table lookups in `SubmissionExtensionMap` and
`SubmissionParamKey` regardless of server casing.

### 2.3. SubmissionParam — Typed Sealed Sum + Extension Arm

SMTP parameters are typed per-extension rather than collapsed to strings.
Known extensions get typed payloads; unknown extensions carry a validated
`RFC5321Keyword` name and an optional string value (G8, G8b, G8c).

```nim
type
  BodyEncoding* = enum
    beSevenBit    = "7BIT"
    beEightBit    = "8BITMIME"
    beBinaryMime  = "BINARYMIME"

  DsnRetType* = enum
    retFull = "FULL"
    retHdrs = "HDRS"

  DsnNotifyFlag* = enum
    dnfNever    = "NEVER"
    dnfSuccess  = "SUCCESS"
    dnfFailure  = "FAILURE"
    dnfDelay    = "DELAY"

  OrcptAddrType* = distinct string

  DeliveryByMode* = enum
    dbmReturnImmediate = "R"
    dbmNotifyImmediate = "N"
    dbmReturnTrace     = "RT"
    dbmNotifyTrace     = "NT"

  HoldForSeconds* = distinct UnsignedInt
  MtPriority*     = distinct int

  SubmissionParamKind* = enum
    spkBody       = "BODY"
    spkSmtpUtf8   = "SMTPUTF8"
    spkSize       = "SIZE"
    spkEnvid      = "ENVID"
    spkRet        = "RET"
    spkNotify     = "NOTIFY"
    spkOrcpt      = "ORCPT"
    spkHoldFor    = "HOLDFOR"
    spkHoldUntil  = "HOLDUNTIL"
    spkBy         = "BY"
    spkMtPriority = "MT-PRIORITY"
    spkExtension

  SubmissionParam* {.ruleOff: "objects".} = object
    case kind*: SubmissionParamKind
    of spkBody:       bodyEncoding*: BodyEncoding
    of spkSmtpUtf8:   discard
    of spkSize:       sizeOctets*: UnsignedInt
    of spkEnvid:      envid*: string
    of spkRet:        retType*: DsnRetType
    of spkNotify:     notifyFlags*: set[DsnNotifyFlag]
    of spkOrcpt:      origAddrType*: OrcptAddrType
                      origRecipient*: string
    of spkHoldFor:    holdForSeconds*: HoldForSeconds
    of spkHoldUntil:  holdUntil*: UTCDate
    of spkBy:         byDeadline*: JmapInt
                      byMode*: DeliveryByMode
    of spkMtPriority: priority*: MtPriority
    of spkExtension:  extName*: RFC5321Keyword
                      extValue*: Opt[string]
```

`HoldForSeconds` and `MtPriority` are distinct newtypes with smart
constructors — not `range[T]`, which would cause fatal `RangeDefect` on
invalid input rather than returning a `Result`.

```nim
func parseHoldForSeconds*(raw: UnsignedInt): Result[HoldForSeconds, ValidationError]
func parseMtPriority*(raw: int): Result[MtPriority, ValidationError]
```

NOTIFY mutual exclusion: `dnfNever` is mutually exclusive with
`{dnfSuccess, dnfFailure, dnfDelay}`. Enforced in the `spkNotify` smart
constructor, not structurally split into a case object. The invariant is
narrow (one rule) and a structural split would add ceremony without payoff.

### 2.4. SubmissionParams — ADT-Keyed Table

The parameter collection uses a single `OrderedTable` keyed on a case-object
identity type. Structural uniqueness: the Table itself forbids duplicate
entries. Wire-order fidelity: `OrderedTable` preserves insertion order (G8a).

```nim
type
  SubmissionParamKey* {.ruleOff: "objects".} = object
    case kind*: SubmissionParamKind
    of spkExtension: extName*: RFC5321Keyword
    else: discard

  SubmissionParams* = distinct OrderedTable[SubmissionParamKey, SubmissionParam]

func hash(k: SubmissionParamKey): Hash =
  case k.kind
  of spkExtension: hash((spkExtension.ord, k.extName.string))
  else:            hash(k.kind.ord)

func `==`(a, b: SubmissionParamKey): bool =
  if a.kind != b.kind: false
  else:
    case a.kind
    of spkExtension: a.extName == b.extName
    else: true

func paramKey*(p: SubmissionParam): SubmissionParamKey =
  case p.kind
  of spkExtension: SubmissionParamKey(kind: spkExtension, extName: p.extName)
  else:            SubmissionParamKey(kind: p.kind)

func parseSubmissionParams*(
    items: openArray[SubmissionParam]
): Result[SubmissionParams, seq[ValidationError]]
```

The key is derived from the value via `paramKey` — "derived-not-stored"
(Pattern 6). The Table indexes by derived identity; the value carries the
full payload.

`SubmissionAddress.parameters` is `Opt[SubmissionParams]` (G34), matching
the RFC's `Object|null`. `Opt.none` represents absent/null parameters;
`Opt.some` with an empty `SubmissionParams` represents the empty `{}`
JSON object — the serde layer distinguishes both cases per the codebase's
standard `Opt[T]` convention.

### 2.5. SubmissionAddress + Envelope

```nim
type
  SubmissionAddress* {.ruleOff: "objects".} = object
    mailbox*:    RFC5321Mailbox
    parameters*: Opt[SubmissionParams]

  ReversePathKind* = enum
    rpkNullPath      ## SMTP null reverse path <>; wire: empty string; may carry Mail-parameters
    rpkMailbox       ## Valid RFC 5321 Mailbox with optional parameters

  ReversePath* {.ruleOff: "objects".} = object
    ## Models SMTP Reverse-path = Path / "<>" (RFC 5321 §4.1.2).
    ## Distinguished from SubmissionAddress so rcptTo (Forward-path only)
    ## cannot admit empty addresses (G32).
    case kind*: ReversePathKind
    of rpkNullPath: nullPathParams*: Opt[SubmissionParams]
    of rpkMailbox:  sender*: SubmissionAddress

  NonEmptyRcptList* = distinct seq[SubmissionAddress]

  Envelope* {.ruleOff: "objects".} = object
    mailFrom*: ReversePath
    rcptTo*:   NonEmptyRcptList
```

Smart constructors for `ReversePath`:

```nim
func nullReversePath*(
    params: Opt[SubmissionParams] = Opt.none(SubmissionParams)
): ReversePath =
  ## Infallible constructor for the SMTP null reverse path <>.
  ReversePath(kind: rpkNullPath, nullPathParams: params)

func reversePath*(addr: SubmissionAddress): ReversePath =
  ## Infallible wrapper: lifts a validated SubmissionAddress into ReversePath.
  ReversePath(kind: rpkMailbox, sender: addr)
```

`NonEmptyRcptList` has a strict/lenient parser pair (G7):

```nim
func parseNonEmptyRcptList*(
    items: openArray[SubmissionAddress]
): Result[NonEmptyRcptList, seq[ValidationError]]

func parseNonEmptyRcptListFromServer*(
    items: openArray[SubmissionAddress]
): Result[NonEmptyRcptList, ValidationError]
```

The strict parser (client construction) rejects empty AND duplicate
recipients via `validateUniqueByIt`. The lenient parser (server receipt)
rejects only empty — Postel's law.

---

## 3. UndoStatus / DeliveryStatus Vocabulary

All types in this section live in `submission_status.nim` under
`{.push raises: [], noSideEffect.}`.

### 3.1. UndoStatus

Three mutually exclusive states. Also serves as the phantom type parameter
for the GADT-style `EmailSubmission[S: static UndoStatus]` (G3).

```nim
type UndoStatus* = enum
  usPending  = "pending"
  usFinal    = "final"
  usCanceled = "canceled"
```

State transitions: `usPending` → `usFinal` (server-initiated, unrecallable),
`usPending` → `usCanceled` (client-initiated via update). Both `usFinal`
and `usCanceled` are terminal.

### 3.2. DeliveredState + DisplayedState

Server-sent per-recipient enums with catch-all for forwards compatibility
(G10, G11). Pattern mirrors `MethodErrorType` / `SetErrorType`.

```nim
type DeliveredState* = enum
  dsQueued  = "queued"
  dsYes     = "yes"
  dsNo      = "no"
  dsUnknown = "unknown"
  dsOther

type ParsedDeliveredState* {.ruleOff: "objects".} = object
  state*:      DeliveredState
  rawBacking*: string

type DisplayedState* = enum
  dpUnknown = "unknown"
  dpYes     = "yes"
  dpOther

type ParsedDisplayedState* {.ruleOff: "objects".} = object
  state*:      DisplayedState
  rawBacking*: string
```

### 3.3. SmtpReply

Distinct string; smart constructor validates Reply-code per RFC 5321 §4.2
(`Reply-code = %x32-35 %x30-35 %x30-39`; first digit 2–5, second digit
0–5, third digit 0–9), optionally followed by SP or hyphen and text.
Multiline replies (continuation lines with hyphen separator) are accepted.
Deeper structural parsing (enhanced status code decomposition per RFC 3463)
deferred (G12).

```nim
type SmtpReply* = distinct string

func `==`*(a, b: SmtpReply): bool {.borrow.}
func `$`*(a: SmtpReply): string {.borrow.}
func hash*(a: SmtpReply): Hash {.borrow.}

func parseSmtpReply*(raw: string): Result[SmtpReply, ValidationError]
```

### 3.4. DeliveryStatus + DeliveryStatusMap

Per-recipient delivery state. The map is keyed on `RFC5321Mailbox` matching
the envelope `rcptTo` addresses (G9).

```nim
type DeliveryStatus* {.ruleOff: "objects".} = object
  smtpReply*: SmtpReply
  delivered*: ParsedDeliveredState
  displayed*: ParsedDisplayedState

type DeliveryStatusMap* = distinct Table[RFC5321Mailbox, DeliveryStatus]
```

Domain-specific operations attach to the distinct type:

```nim
func countDelivered*(m: DeliveryStatusMap): int
func anyFailed*(m: DeliveryStatusMap): bool
```

---

## 4. EmailSubmission Entity Read Model

All types in this section live in `email_submission.nim` under
`{.push raises: [], noSideEffect.}`.

### 4.1. GADT-Style Phantom State Indexing

RFC §7's `undoStatus` determines which operations are valid on a submission.
The flat-record approach pushes that invariant into documentation and runtime
checks. The phantom-typed approach (G2, G3) lifts it into the type system:
`cancel` only accepts `EmailSubmission[usPending]`; the compiler rejects
attempts to cancel a final or already-canceled submission.

The Nim adaptation of Haskell's GADT + DataKinds idiom:

```nim
type EmailSubmission*[S: static UndoStatus] {.ruleOff: "objects".} = object
  id*:             Id
  identityId*:     Id
  emailId*:        Id
  threadId*:       Id
  envelope*:       Opt[Envelope]
  sendAt*:         UTCDate
  deliveryStatus*: Opt[DeliveryStatusMap]
  dsnBlobIds*:     seq[BlobId]
  mdnBlobIds*:     seq[BlobId]
```

The `static UndoStatus` generic parameter is the DataKinds encoding: the
enum IS the type parameter. One source of truth — adding a hypothetical
`usScheduled` variant forces compile errors at every `case` site for
`AnyEmailSubmission.state` and every typed transition function.

### 4.2. AnyEmailSubmission — Existential Wrapper

The Nim analogue of Haskell's `SomeEmailSubmission`. Runtime dispatch happens
once at the serde boundary; consumers pattern-match once at the use site.

```nim
type AnyEmailSubmission* {.ruleOff: "objects".} = object
  case state*: UndoStatus
  of usPending:  pending*:  EmailSubmission[usPending]
  of usFinal:    final*:    EmailSubmission[usFinal]
  of usCanceled: canceled*: EmailSubmission[usCanceled]
```

**Boundary pattern.** `fromJson` produces `AnyEmailSubmission`. Consumers
pattern-match:

```nim
case sub.state
of usPending:
  let upd = cancelUpdate(sub.pending)
  # ...
of usFinal:
  # render as sent
of usCanceled:
  # render as canceled
```

### 4.3. Typed Transition Functions

Pure L1 helpers build update records from phantom-constrained inputs (G4).
Callers use the generic `addEmailSubmissionSet` builder with the helper's
output.

```nim
func cancelUpdate*(s: EmailSubmission[usPending]): EmailSubmissionUpdate =
  setUndoStatusToCanceled()
```

---

## 5. EmailSubmissionBlueprint (Creation)

### 5.1. Shape

RFC §7.5 allows three client-settable fields on create: `identityId`,
`emailId`, `envelope`. All others are server-set. Named "Blueprint" to match
the `EmailBlueprint` convention and signal construction-with-rules (G13).

```nim
type EmailSubmissionBlueprint* {.ruleOff: "objects".} = object
  identityId*: Id
  emailId*:    Id
  envelope*:   Opt[Envelope]
```

`envelope: Opt[Envelope]` — `None` means "defer to server synthesis per
RFC §7.5" (G14). No client-side synthesis helper; the server is the
authoritative envelope computer.

### 5.2. Smart Constructor

Accumulating-error pattern matching `EmailBlueprint` (G15):

```nim
func parseEmailSubmissionBlueprint*(
    identityId: Id,
    emailId:    Id,
    envelope:   Opt[Envelope] = Opt.none(Envelope),
): Result[EmailSubmissionBlueprint, seq[ValidationError]]
```

Validates: `identityId` and `emailId` are structurally valid `Id` values.
If `envelope` is provided, its inner `SubmissionAddress` / `NonEmptyRcptList`
/ `SubmissionParams` invariants are already enforced by their own smart
constructors — the Blueprint constructor need not re-check them.

---

## 6. EmailSubmissionUpdate + Update Algebra

### 6.1. Single-Variant Case Object

RFC §7.5 ¶3: only `undoStatus` is post-create mutable, and only `pending` →
`canceled`. Full F1 parity: case object + protocol-primitive +
phantom-typed domain-named constructor (G16).

```nim
type EmailSubmissionUpdateVariantKind* = enum
  esuSetUndoStatusToCanceled

type EmailSubmissionUpdate* {.ruleOff: "objects".} = object
  case kind*: EmailSubmissionUpdateVariantKind
  of esuSetUndoStatusToCanceled: discard

func setUndoStatusToCanceled*(): EmailSubmissionUpdate =
  EmailSubmissionUpdate(kind: esuSetUndoStatusToCanceled)

func cancelUpdate*(s: EmailSubmission[usPending]): EmailSubmissionUpdate =
  setUndoStatusToCanceled()
```

### 6.2. NonEmptyEmailSubmissionUpdates

`distinct Table[Id, EmailSubmissionUpdate]` enforcing non-emptiness at the
type level. Per-id uniqueness is structural (Table keys) (G17).

```nim
type NonEmptyEmailSubmissionUpdates* =
  distinct Table[Id, EmailSubmissionUpdate]

func parseNonEmptyEmailSubmissionUpdates*(
    items: openArray[(Id, EmailSubmissionUpdate)]
): Result[NonEmptyEmailSubmissionUpdates, ValidationError]
```

---

## 7. Serde (SerdeViolation + JsonPath)

All serde follows the `c8f45b3` pattern (G26): every `fromJson` signature
carries `path: JsonPath = emptyJsonPath()` and returns
`Result[T, SerdeViolation]`. Single `toValidationError(sv, rootType)`
translator at the L2/L3 boundary.

### 7.1. AnyEmailSubmission Deserialisation

`fromJson` dispatches once on `undoStatus` at the serde boundary, then
constructs the appropriate phantom-indexed branch:

```nim
func fromJson*(
    _: typedesc[AnyEmailSubmission],
    node: JsonNode,
    path: JsonPath = emptyJsonPath()
): Result[AnyEmailSubmission, SerdeViolation] =
  let statusNode = ? fieldJString(node, "undoStatus", path)
  let status = ? parseUndoStatus(statusNode.getStr, path / "undoStatus")
  case status
  of usPending:
    let s = ? fromJsonShared[usPending](node, path)
    ok(AnyEmailSubmission(state: usPending, pending: s))
  of usFinal:
    let s = ? fromJsonShared[usFinal](node, path)
    ok(AnyEmailSubmission(state: usFinal, final: s))
  of usCanceled:
    let s = ? fromJsonShared[usCanceled](node, path)
    ok(AnyEmailSubmission(state: usCanceled, canceled: s))
```

`fromJsonShared` is a generic helper parameterised on `S: static UndoStatus`
that parses the shared fields into `EmailSubmission[S]`.

### 7.2. Envelope + Parameters Serde

`toJson` for `SubmissionParams` iterates the `OrderedTable`, emitting each
parameter as a key-value pair in a JSON object. The key is the
string-backed `SubmissionParamKind` for known variants, or `extName` for
extensions.

`fromJson` for `SubmissionParams` must reverse: parse each key into a
`SubmissionParamKind` (falling back to `spkExtension` for unrecognised
keys), then parse the value according to the variant.

xtext-encoded wire strings (ENVID, ORCPT recipient) are decoded at the serde
boundary (G27/G8c); interior holds plain unicode.

> **Finding flagged during Step 1 (2026-04-16) — re-examine at Step 10 planning.**
> RFC 8621 §7 (lines 4207–4210) explicitly says *"any xtext or unitext encodings
> are removed (see [RFC3461] and [RFC6533]) and JSON string encoding is applied"*
> for JMAP `Address` parameters. This suggests a pure-JMAP client does **not**
> xtext-encode on send or xtext-decode on receive — the server performs that
> translation at the SMTP boundary. If this reading is correct, the G27/G8c
> xtext-at-serde-boundary decision would contradict the wire contract and the
> `xtextEncode` / `xtextDecode` helpers called for in `implementation-12.md`
> Step 10 would be out of scope (or scoped only to SMTP-adjacent testing).
> The Step 10 implementer should confirm against RFC 8621 §7 and RFC 3461 §4
> before building xtext helpers; the final call sits with that author, not
> with Step 1.

`toJson`/`fromJson` for `ReversePath`: the wire format is the RFC §7
`Address` object in both cases. `rpkNullPath` serialises with `email` set
to the empty string `""` and optional `parameters`; `rpkMailbox` delegates
to `SubmissionAddress` serde. `fromJson` dispatches on the `email` field:
empty string → `rpkNullPath` (with optional parameters parsed from the same
object), non-empty → parse as `RFC5321Mailbox` → `rpkMailbox`.

### 7.3. Creation and Filter Serialisation

`EmailSubmissionBlueprint`, `EmailSubmissionFilterCondition`, and
`EmailSubmissionComparator` are `toJson`-only — they flow client → server
and the server never sends them back.

`NonEmptyEmailSubmissionUpdates` serialises to `Table[Id, PatchObject]` on
the wire — the `toJson` translates the single variant
`esuSetUndoStatusToCanceled` into the PatchObject
`{ "undoStatus": "canceled" }`.

`toJson`-only for `IdOrCreationRef` (map-key serialisation in the compound
builder's `onSuccessUpdateEmail` / `onSuccessDestroyEmail`): `icrDirect`
serialises as the `Id` string value; `icrCreation` serialises as
`"#" & string(creationId)` per RFC 8620 §5.3. No `fromJson` — the server
never sends these keys back.

---

## 8. Method Builders

All builders live in `submission_builders.nim`.

### 8.1. Standard Methods

```nim
func addEmailSubmissionGet*(
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[seq[Id]] = Opt.none(seq[Id]),
    properties: Opt[seq[PropertyName]] = Opt.none(seq[PropertyName]),
): (RequestBuilder, ResponseHandle[GetResponse[AnyEmailSubmission]])

func addEmailSubmissionChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[ChangesResponse])

func addEmailSubmissionQuery*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[EmailSubmissionFilterCondition]] = ...,
    sort: Opt[seq[EmailSubmissionComparator]] = ...,
    position: Opt[int] = ...,
    anchor: Opt[Id] = ...,
    anchorOffset: Opt[int] = ...,
    limit: Opt[UnsignedInt] = ...,
    calculateTotal: Opt[bool] = ...,
): (RequestBuilder, ResponseHandle[QueryResponse])

func addEmailSubmissionQueryChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[EmailSubmissionFilterCondition]] = ...,
    sort: Opt[seq[EmailSubmissionComparator]] = ...,
    sinceQueryState: JmapState,
    maxChanges: Opt[MaxChanges] = ...,
    upToId: Opt[Id] = ...,
    calculateTotal: Opt[bool] = ...,
): (RequestBuilder, ResponseHandle[QueryChangesResponse])
```

### 8.2. Simple Set

```nim
func addEmailSubmissionSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, EmailSubmissionBlueprint]] = ...,
    update: Opt[NonEmptyEmailSubmissionUpdates] = ...,
    destroy: Opt[seq[Id]] = ...,
): (RequestBuilder, ResponseHandle[EmailSubmissionSetResponse])
```

### 8.3. EmailSubmissionFilterCondition

```nim
type NonEmptyIdSeq* = distinct seq[Id]

func parseNonEmptyIdSeq*(items: openArray[Id]):
    Result[NonEmptyIdSeq, ValidationError]

type EmailSubmissionFilterCondition* {.ruleOff: "objects".} = object
  identityIds*: Opt[NonEmptyIdSeq]
  emailIds*:    Opt[NonEmptyIdSeq]
  threadIds*:   Opt[NonEmptyIdSeq]
  undoStatus*:  Opt[UndoStatus]
  before*:      Opt[UTCDate]
  after*:       Opt[UTCDate]
```

**Strictness note (G37):** The RFC allows empty arrays for `identityIds`,
`emailIds`, and `threadIds`. This design wraps them in
`Opt[NonEmptyIdSeq]` — an intentional "make the wrong thing hard" choice.
An empty filter list matches nothing, which is almost certainly a caller
error. `Opt.none` provides the "no constraint on this property" case.

`undoStatus` is typed against the `UndoStatus` enum. Since this field is
client-sent, the `dsOther`/`dpOther` catch-all pattern from G10/G11 does not
apply (G18).

### 8.4. EmailSubmissionComparator

```nim
type EmailSubmissionSortProperty* = enum
  esspEmailId  = "emailId"
  esspThreadId = "threadId"
  esspSentAt   = "sentAt"
  esspOther

type EmailSubmissionComparator* {.ruleOff: "objects".} = object
  property*:    EmailSubmissionSortProperty
  rawProperty*: string
  isAscending*: bool
  collation*:   Opt[string]
```

Note: the RFC's sort property literal is `sentAt`, even though the entity
property is named `sendAt`. The wire token is authoritative (G19).

---

## 9. Cross-Entity Compound Builder

### 9.0. IdOrCreationRef — Creation Reference Keys

RFC 8621 §7.5's `onSuccessUpdateEmail` and `onSuccessDestroyEmail` use map
keys that are either an existing EmailSubmission `Id` or a `#`-prefixed
creation id from the same `/set` call (RFC 8620 §5.3). This is a
**creation reference**, not a **result reference** (RFC 8620 §3.7).

- Creation reference (§5.3): `"#k1490"` — a string key; the `#` prefix
  means "resolve this creation id after the creates in this same `/set`
  call succeed." No `resultOf`/`name`/`path` structure.
- Result reference (§3.7): `"#ids": {"resultOf": "c0", "name": "Foo/get",
  "path": "/ids"}` — a JSON object replacing a field value; resolves the
  output of a previous method call in the batch.

`Referencable[T]` models result references. `IdOrCreationRef` models
creation references (G35, G36).

```nim
type
  IdOrCreationRefKind* = enum
    icrDirect      ## Existing EmailSubmission Id
    icrCreation    ## Creation reference (wire: "#" + creationId)

  IdOrCreationRef* {.ruleOff: "objects".} = object
    ## Either an existing EmailSubmission Id or a creation-id reference
    ## to a submission being created in the same /set call. Wire format:
    ## direct ids serialise as their string value; creation references
    ## serialise as "#" & string(creationId).
    case kind*: IdOrCreationRefKind
    of icrDirect:   id*: Id
    of icrCreation: creationId*: CreationId

func directRef*(id: Id): IdOrCreationRef =
  IdOrCreationRef(kind: icrDirect, id: id)

func creationRef*(cid: CreationId): IdOrCreationRef =
  IdOrCreationRef(kind: icrCreation, creationId: cid)
```

### 9.1. addEmailSubmissionAndEmailSet

Named per F1's AND-connector convention (`addEmailCopyAndDestroy`) (G20).
Triggers an implicit `Email/set` after `EmailSubmission/set` succeeds,
driven by `onSuccessUpdateEmail` and/or `onSuccessDestroyEmail`.

```nim
func addEmailSubmissionAndEmailSet*(
    b: RequestBuilder,
    accountId: AccountId,
    create: Opt[Table[CreationId, EmailSubmissionBlueprint]] = ...,
    update: Opt[NonEmptyEmailSubmissionUpdates] = ...,
    destroy: Opt[seq[Id]] = ...,
    onSuccessUpdateEmail: Opt[Table[IdOrCreationRef, EmailUpdateSet]] = ...,
    onSuccessDestroyEmail: Opt[seq[IdOrCreationRef]] = ...,
    ifInState: Opt[JmapState] = ...,
): (RequestBuilder, EmailSubmissionHandles)
```

`onSuccessUpdateEmail` values are typed `EmailUpdateSet` — F1's typed update
algebra reused directly (G22). The typical flow — send a message, remove
`$draft`, move from Drafts to Sent — composes from existing `EmailUpdate`
constructors:

```nim
let updates = initEmailUpdateSet(@[
  removeKeyword(kwDraft),
  removeFromMailbox(draftsId),
  addToMailbox(sentId),
]).get()

let (req, handles) = b.addEmailSubmissionAndEmailSet(
  accountId = acc,
  create = { creationRef: blueprint }.toTable,
  onSuccessUpdateEmail = { creationRef(submissionCid): updates }.toTable,
)
```

### 9.2. EmailSubmissionHandles + getBoth

Specific compound-handle record; F1's Rule-of-Three (F3) holds — two
compound-handle sites is under the generic-promotion threshold (G21).

```nim
type EmailSubmissionHandles* {.ruleOff: "objects".} = object
  submission*: ResponseHandle[EmailSubmissionSetResponse]
  emailSet*:   NameBoundHandle[EmailSetResponse]

type EmailSubmissionResults* {.ruleOff: "objects".} = object
  submission*: EmailSubmissionSetResponse
  emailSet*:   EmailSetResponse

func getBoth*(
    resp: Response, handles: EmailSubmissionHandles
): Result[EmailSubmissionResults, MethodError]
```

---

## 10. SetError Extensions Reference

All 8 EmailSubmission-specific `SetErrorType` variants plus the standard
`tooLarge` (reused with submission-specific `maxSize` payload per RFC 8621
§7.5) already exist in `errors.nim` from commit `a23f39a` (G23). No new
variants or accessors needed (G24).

| Method | RFC-listed error | Existing enum variant | Payload accessor |
|--------|-----------------|----------------------|-----------------|
| `/set` create | `invalidEmail` | `setInvalidEmail` | `invalidEmailProperties(se)` |
| `/set` create | `tooManyRecipients` | `setTooManyRecipients` | `maxRecipients(se)` |
| `/set` create | `noRecipients` | `setNoRecipients` | *(none — payload-less)* |
| `/set` create | `invalidRecipients` | `setInvalidRecipients` | `invalidRecipientAddresses(se)` |
| `/set` create | `forbiddenMailFrom` | `setForbiddenMailFrom` | *(none)* |
| `/set` create | `forbiddenFrom` | `setForbiddenFrom` | *(none)* |
| `/set` create | `forbiddenToSend` | `setForbiddenToSend` | *(none)* |
| `/set` create | `tooLarge` | `setTooLarge` | `maxSize(se)` |
| `/set` update | `cannotUnsend` | `setCannotUnsend` | *(none)* |

---

## 11. Capability Refinements

### 11.1. SubmissionExtensionMap

Existing `SubmissionCapabilities.submissionExtensions` tightened from
`OrderedTable[string, seq[string]]` to a distinct wrapper keyed on
`RFC5321Keyword` (G25). This is a retroactive refinement to the Part A
capability model, consistent with the codebase's directional shift toward
validated newtypes.

```nim
type SubmissionExtensionMap* = distinct OrderedTable[RFC5321Keyword, seq[string]]

type SubmissionCapabilities* {.ruleOff: "objects".} = object
  maxDelayedSend*:       UnsignedInt
  submissionExtensions*: SubmissionExtensionMap
```

---

## 12. Roadmap Appendix

The following RFC 8621 pieces remain undesigned after Part G1:

| Concept | RFC § | Size | One-line scope |
|---------|-------|------|----------------|
| Email/parse | §4.9 | Medium | Stateless verb; parse raw RFC 5322 → Email structure without storage. Orthogonal to write path. |
| SearchSnippet/get builder | §5.1 | Small | Read type designed in Part D; only the method builder (`addSearchSnippetGet`) is missing. |
| EmailDelivery push type | §1.5 | Tiny | No methods; just a typed push-notification state entry for battery-constrained polling. |
| Advanced Email/query filters | §4.4.1 | Medium | Filter-algebra extension: full boolean nesting (`allOf`/`anyOf`/`not`), `hasKeyword` inversion, `minSize`/`maxSize`. Core `Filter[C]` framework handles nesting; mail needs variant expansion on `EmailFilterCondition`. |

These can be delivered as Part H (or ad-hoc patches) and do not block
EmailSubmission implementation.

---

## 13. Decision Traceability Matrix

| # | Decision | Options Considered | Chosen | Primary Principles |
|---|----------|-------------------|--------|-------------------|
| G1 | Module organisation | (A) single file, (B) three L1 files by concern, (C) two files | **B** — three files: `submission_envelope.nim`, `submission_status.nim`, `email_submission.nim` | Single responsibility; mirrors Email's 5-file family |
| G2 | Entity shape | (A) flat record, (B) case object on UndoStatus, (C) GADT-style phantom + AnyEmailSubmission wrapper | **C** — phantom-typed `EmailSubmission[S: static UndoStatus]` + existential wrapper | Make state transitions explicit in the type; types tell the truth |
| G3 | UndoStatus + phantom encoding | (A) empty-object markers unbound, (B) union-constrained, (C) `static UndoStatus` generic (DataKinds) | **C** — `[S: static UndoStatus]`; enum IS the phantom | One source of truth per fact |
| G4 | Transition API surface | (A) L1 typed helper only, (B) L3 typed builder, (C) both, (D) none | **A** — `cancelUpdate(s: EmailSubmission[usPending])` at L1 | Functional core, imperative shell |
| G5 | Envelope module placement | Resolved by G1 | `submission_envelope.nim` | — |
| G6 | Address type | (A) reuse EmailAddress, (B) new SubmissionAddress plain string, (C) new + distinct RFC5321Mailbox | **C** — distinct `RFC5321Mailbox` + `SubmissionAddress` | Newtype everything; parse don't validate |
| G7 | rcptTo non-emptiness | (A) distinct seq strict/lenient pair, (B) distinct seq single strict, (C) plain seq in Envelope | **A** — `NonEmptyRcptList` with strict/lenient parsers | Newtype everything; Postel's law |
| G8 | Parameters map (high-level) | (A) raw table, (B) distinct table + validated keys, (C) distinct + key newtype | **Typed sealed sum + extension arm** (beyond A/B/C) | Maximal type safety for known; open-world for unknown |
| G8a | Params container | (i) distinct seq, (ii) split table, (iii) single Table keyed on ADT | **(iii)** — `distinct OrderedTable[SubmissionParamKey, SubmissionParam]` | Make illegal states unrepresentable (structural uniqueness) |
| G8b | Known-parameter set | (A) RFC 8621 strict, (B) + BODY + SMTPUTF8, (C) narrow | **B** — 11 typed variants + extension arm | Practical coverage |
| G8c | Per-param payloads | Full draft: enums, distinct newtypes, flat composites, xtext-decoded | **Accept as drafted** | Parse don't validate; avoid range[T] |
| G9 | DeliveryStatus map key | (A) string, (B) RFC5321Mailbox, (C) distinct DeliveryStatusMap | **C** — `distinct Table[RFC5321Mailbox, DeliveryStatus]` | Newtype everything |
| G10 | `delivered` enum | (A) closed, (B) + dsOther catch-all, (C) sealed sum empty branches | **B** — 4 RFC-defined + `dsOther` + `ParsedDeliveredState` | Postel's law; MethodError/SetError precedent |
| G11 | `displayed` enum | (A) closed, (B) + dpOther catch-all | **B** — symmetric with G10 | Consistency |
| G12 | smtpReply type | (A) plain string, (B) distinct + smart ctor, (C) fully parsed | **B** — `distinct SmtpReply` | Newtype everything; defer speculative parsing |
| G13 | Creation model naming | (A) EmailSubmissionCreate, (B) EmailSubmissionBlueprint, (C) NewEmailSubmission | **B** — Blueprint | Signals construction-with-rules |
| G14 | Envelope default-synthesis | (A) pass-through Opt, (B) require client-side, (C) + helper | **A** — `Opt[Envelope]`; None = server synthesises | Postel's law; DRY; one source of truth |
| G15 | Blueprint error mode | (A) accumulating, (B) fail-fast | **A** — `seq[ValidationError]` | EmailBlueprint F1 precedent |
| G16 | Update algebra shape | (A) single-variant case, (B) empty marker, (C) function-only, (D) F1-parity | **D** — case object + protocol-primitive + domain-named | F1 parity; forwards-compatible |
| G17 | UpdateSet inclusion | (A) skip, (B) trivial set, (C) NonEmpty wrapper | **C** — `NonEmptyEmailSubmissionUpdates` | Newtype everything |
| G18 | Filter condition typing | (A) plain, (B) typed undoStatus, (C) + NonEmptyIdSeq | **C** — typed undoStatus + `NonEmptyIdSeq` | Make the wrong thing hard |
| G19 | Sort comparator typing | (A) string, (B) enum + catch-all, (C) closed enum | **B** — `EmailSubmissionSortProperty` + `esspOther` | Forward compatibility |
| G20 | Compound builder naming | (A) addEmailSubmissionAndEmailSet, (B) Send, (C) verbose, (D) SendAndFile | **A** — AND-connector | F1 naming convention |
| G21 | Compound handle shape | (A) specific EmailSubmissionHandles, (B) generic CompoundHandles | **A** — specific | F1 Rule-of-Three (F3) |
| G22 | onSuccess* value args | (A) typed EmailUpdateSet, (B) raw JsonNode, (C) domain helpers | **A** — reuses F1 typed update algebra; key type corrected from `Referencable[Id]` to `IdOrCreationRef` by G35 | DRY; type safety |
| G23 | New SetError variants | Yes / No | **No** — all 8 extra + standard `tooLarge` exist from `a23f39a` | — |
| G24 | Payload-less accessors | Yes / No | **No** — nothing to extract | — |
| G25 | SubmissionExtensions typing | (A) keep raw, (B) upgrade + distinct, (C) upgrade keys only | **B** — `SubmissionExtensionMap` | One type for one concept |
| G26 | Serde pattern | Confirm SerdeViolation + JsonPath | **Confirmed** | `c8f45b3` pattern |
| G27 | Envelope fromJson synthesis | Confirm no synthesis | **Confirmed** — `Opt.none` when null | Server-authoritative |
| G28 | Constraint table columns | 2-col / 3-col / 4-col | **3-col** — RFC ref / Constraint / Nim type | — |
| G29 | Roadmap appendix format | Table / paragraph / list | **Table** — concept / RFC § / size / scope | — |
| G30 | DTM columns | F1 / simplified / + files | **F1** — 5 columns | Consistency |
| G31 | Doc depth target | Match F1 / proportional / whatever | **Whatever it takes** | — |
| G32 | Envelope.mailFrom type | (A) SubmissionAddress (rejects empty), (B) Opt[RFC5321Mailbox] (loses params), (C) ReversePath sum (null parameterless), (C′) ReversePath sum (null with params) | **C′** — `ReversePath(rpkNullPath + Opt[SubmissionParams] \| rpkMailbox)` | Make illegal states unrepresentable; RFC fidelity — SMTP null path permits Mail-parameters (RFC 5321 §4.1.1.2); RFC 8621 §7 ¶5 ENVID note |
| G33 | ReversePath placement | (A) On SubmissionAddress (pollutes rcptTo), (B) On Envelope.mailFrom field | **B** — field-level sum; SubmissionAddress unchanged | rcptTo never admits empty |
| G34 | Parameters nullability | (A) Non-optional SubmissionParams, (B) Opt[SubmissionParams] | **B** — `Opt[SubmissionParams]` | RFC fidelity (`Object\|null`); codebase `Opt[Table]` precedent |
| G35 | onSuccess* key type | (A) Referencable[Id] (result-ref shape), (B) plain string, (C) IdOrCreationRef sum | **C** — `IdOrCreationRef(icrDirect \| icrCreation)` | RFC 8620 §5.3 vs §3.7 are distinct mechanisms |
| G36 | IdOrCreationRef vs Referencable | (A) Extend Referencable with third arm, (B) Separate type | **B** — different wire format, different semantics | One type for one concept |
| G37 | Filter list empty-rejection | (A) Opt[seq[Id]] (permits empty), (B) Opt[NonEmptyIdSeq] (rejects empty) | **B** — intentional strictness | Make the wrong thing hard |
