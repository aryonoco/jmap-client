# RFC 8621 JMAP Mail — Design G1: EmailSubmission

Part G covers the submission lifecycle. Parts A–F2 deliver Mailbox, Thread,
Email (read path, query, creation, copy, import), Identity, VacationResponse,
and the typed update algebra. Part G wires those foundations into the final
major RFC 8621 entity: **EmailSubmission** (§7) — the object that represents
"a message has been submitted for delivery."

Part G also exercises the library's **GADT-style phantom state indexing**:
`EmailSubmission[S: static UndoStatus]` with an `AnyEmailSubmission`
existential wrapper at the serde boundary. This lets the type system enforce
that cancellation is only attempted on pending submissions — moving the
invariant from runtime checks into the type. The cross-entity compound-handle
pair (`EmailSubmissionHandles` / `EmailSubmissionResults`) reuses the generic
`CompoundHandles[A, B]` / `CompoundResults[A, B]` from `dispatch.nim`,
spanning `EmailSubmission/set` and an implicit `Email/set`.

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
| `EmailSubmission/changes` | §7.2 | `addEmailSubmissionChanges` | `ChangesResponse[AnyEmailSubmission]` | Standard `/changes`. |
| `EmailSubmission/query` | §7.3 | `addEmailSubmissionQuery` | `QueryResponse[AnyEmailSubmission]` | Typed `EmailSubmissionFilterCondition` + `EmailSubmissionComparator`. |
| `EmailSubmission/queryChanges` | §7.4 | `addEmailSubmissionQueryChanges` | `QueryChangesResponse[AnyEmailSubmission]` | Standard `/queryChanges`. |
| `EmailSubmission/set` | §7.5 | `addEmailSubmissionSet` | `EmailSubmissionSetResponse` | Simple overload; no `onSuccess*` args. |
| `EmailSubmission/set` (compound) | §7.5 | `addEmailSubmissionAndEmailSet` | `EmailSubmissionHandles` → `EmailSubmissionResults` | Compound: triggers implicit `Email/set` via `onSuccessUpdateEmail` / `onSuccessDestroyEmail` (G20, G22). |

### 1.2. Supporting Types Introduced

| Type | Module | Rationale |
|------|--------|-----------|
| `RFC5321Mailbox` | `submission_mailbox.nim` | Distinct string for RFC 5321 `Mailbox` production (`Local-part "@" ( Domain / address-literal )`). Separates SMTP mailbox grammar from RFC 5322 addr-spec at the type level (G6). |
| `RFC5321Keyword` | `submission_atoms.nim` | Distinct string for RFC 5321 `esmtp-keyword` grammar. Used for SMTP extension parameter names and submission capability keys (G8, G25). |
| `OrcptAddrType` | `submission_atoms.nim` | Distinct string sharing the esmtp-keyword grammar (RFC 3461 §4.2 `addr-type` atom of `ORCPT=`). Byte-equal, not case-folded. |
| `SubmissionAddress` | `submission_envelope.nim` | `RFC5321Mailbox` + `Opt[SubmissionParams]`. RFC §7's Envelope Address type — distinct from `EmailAddress`; parameters nullable per RFC (G6, G34). |
| `SubmissionParamKind` | `submission_param.nim` | 12-variant sealed enum (11 well-known SMTP extensions + `spkExtension` catch-all). |
| `SubmissionParam` | `submission_param.nim` | Case object with per-variant typed payloads (enums, distinct newtypes, dates) (G8c). |
| `SubmissionParamKey` | `submission_param.nim` | Case-object identity key for `SubmissionParams` Table (G8a). |
| `SubmissionParams` | `submission_param.nim` | `distinct OrderedTable[SubmissionParamKey, SubmissionParam]`. Structural uniqueness (G8a). |
| `ReversePath` | `submission_envelope.nim` | Two-variant sum: `rpkNullPath` (SMTP `<>`, with `Opt[SubmissionParams]`) or `rpkMailbox` (`SubmissionAddress`). Models `Reverse-path = Path / "<>"` at `Envelope.mailFrom` (G32). |
| `Envelope` | `submission_envelope.nim` | `mailFrom: ReversePath` + `rcptTo: NonEmptyRcptList`. |
| `NonEmptyRcptList` | `submission_envelope.nim` | `distinct seq[SubmissionAddress]` with strict/lenient parser pair (G7). |
| `UndoStatus` | `submission_status.nim` | 3-variant string-backed enum: `usPending`, `usFinal`, `usCanceled`. Also serves as the phantom type parameter for `EmailSubmission` (G3). |
| `DeliveredState` | `submission_status.nim` | 5-variant enum (4 RFC-defined + `dsOther` catch-all) with `ParsedDeliveredState` wrapper (G10). |
| `DisplayedState` | `submission_status.nim` | 3-variant enum (2 RFC-defined + `dpOther` catch-all) with `ParsedDisplayedState` wrapper (G11). |
| `ReplyCode` | `submission_status.nim` | `distinct uint16` — RFC 5321 §4.2.3 three-digit Reply-code, validated at parse time (G12, H19). |
| `StatusCodeClass` | `submission_status.nim` | RFC 3463 §3.1 class digit, string-backed (`"2"`, `"4"`, `"5"`). |
| `SubjectCode` / `DetailCode` | `submission_status.nim` | `distinct uint16` for RFC 3463 §4 sub-codes, bounded 0..999. |
| `EnhancedStatusCode` | `submission_status.nim` | RFC 3463 §2 `class.subject.detail` triple. |
| `ParsedSmtpReply` | `submission_status.nim` | RFC 5321 §4.2 multi-line Reply parsed once with optional RFC 3463 §2 enhanced-status-code triple from the final line; `raw` preserves ingress bytes for canonicalisation round-trip (G12, H23). |
| `DeliveryStatus` | `submission_status.nim` | `smtpReply: ParsedSmtpReply` + `delivered: ParsedDeliveredState` + `displayed: ParsedDisplayedState`. |
| `DeliveryStatusMap` | `submission_status.nim` | `distinct Table[RFC5321Mailbox, DeliveryStatus]` (G9). |
| `EmailSubmission[S: static UndoStatus]` | `email_submission.nim` | GADT-style phantom-parameterised read model (G2, G3). |
| `AnyEmailSubmission` | `email_submission.nim` | Existential wrapper: case object discriminated on `UndoStatus`, carrying private phantom-indexed branches with same-name `asPending`/`asFinal`/`asCanceled` accessors (G2, G38). |
| `EmailSubmissionBlueprint` | `email_submission.nim` | Creation model: `identityId` + `emailId` + `Opt[Envelope]`. Pattern-A sealed (G13, G14, G15, G38). |
| `EmailSubmissionUpdate` | `email_submission.nim` | Single-variant case object (`esuSetUndoStatusToCanceled`) with protocol-primitive + phantom-typed domain-named constructors (G16). |
| `NonEmptyEmailSubmissionUpdates` | `email_submission.nim` | `distinct Table[Id, EmailSubmissionUpdate]` (G17). |
| `EmailSubmissionFilterCondition` | `email_submission.nim` | Typed filter with `Opt[NonEmptyIdSeq]` list fields + `Opt[UndoStatus]` (G18). |
| `NonEmptyIdSeq` | `email_submission.nim` | `distinct seq[Id]` with non-empty smart constructor (G18). |
| `EmailSubmissionSortProperty` | `email_submission.nim` | 4-variant enum (3 RFC-mandated + `esspOther` catch-all) with `EmailSubmissionComparator` (G19). |
| `EmailSubmissionCreatedItem` | `email_submission.nim` | Server-set subset returned in the `/set` `created` map: `id` (always) plus `Opt[Id]` `threadId`, `Opt[UTCDate]` `sendAt`, `Opt[UndoStatus]` `undoStatus` — Postel's-law accommodation across server divergence (G39). |
| `EmailSubmissionSetResponse` | `email_submission.nim` | Type alias `SetResponse[EmailSubmissionCreatedItem]` — response for `EmailSubmission/set` (G39). |
| `IdOrCreationRef` | `email_submission.nim` | Two-variant sum: existing `Id` or `CreationId` reference. Models RFC 8620 §5.3 creation references in `onSuccess*` keys — distinct from `Referencable[T]` which models §3.7 result references (G35). |
| `NonEmptyOnSuccessUpdateEmail` | `email_submission.nim` | `distinct Table[IdOrCreationRef, EmailUpdateSet]` — empty and duplicate-key shapes are unrepresentable; `Opt.none` is the sole "no extras" encoding (G22). |
| `NonEmptyOnSuccessDestroyEmail` | `email_submission.nim` | `distinct seq[IdOrCreationRef]` — non-empty, dup-free (G22). |
| `EmailSubmissionHandles` | `email_submission.nim` | Alias of `CompoundHandles[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]` — fields `primary`/`implicit` (G21). |
| `EmailSubmissionResults` | `email_submission.nim` | Alias of `CompoundResults[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]` — extraction target of the generic `getBoth[A, B]` (G21). |
| `SubmissionExtensionMap` | `mail_capabilities.nim` | `distinct OrderedTable[RFC5321Keyword, seq[string]]` (G25). |

Supporting enums and distinct newtypes for SMTP parameter payloads:
`BodyEncoding`, `DsnRetType`, `DsnNotifyFlag`, `DeliveryByMode`,
`HoldForSeconds`, `MtPriority` — all in `submission_param.nim` (G8b, G8c).
`OrcptAddrType` lives in `submission_atoms.nim` because it shares the
RFC 5321 `esmtp-keyword` lexical shape with `RFC5321Keyword`.

### 1.3. Deferred

- **Part G2 (Test Specification):** Companion document for EmailSubmission
  unit, serde, property, and compliance tests — scoped out of G1.
- **Generic `CompoundHandles[A, B]`** is already implemented at
  `dispatch.nim`; `EmailSubmissionHandles` is a type alias over it.

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
| §7 ¶8 | `smtpReply` is structured SMTP reply text | `ParsedSmtpReply` (RFC 5321 §4.2 + RFC 3463 §2 enhanced status code) (G12, H23) |
| §7 ¶9 | `dsnBlobIds`, `mdnBlobIds` are server-set arrays | `seq[BlobId]` on read model only |
| §7.5 ¶1 | Only `undoStatus` updatable post-create | `EmailSubmissionUpdate` single variant (G16) |
| §7.5 ¶3 | `onSuccessUpdateEmail` applies PatchObject to Email on success | `NonEmptyOnSuccessUpdateEmail` = `distinct Table[IdOrCreationRef, EmailUpdateSet]` (G22, G35) |
| §7.5 ¶3 | `onSuccessDestroyEmail` destroys Email on success | `NonEmptyOnSuccessDestroyEmail` = `distinct seq[IdOrCreationRef]` (G22, G35) |
| §7.5 ¶5 | SetError `invalidEmail` includes problematic property names | `setInvalidEmail` + `invalidEmailPropertyNames*: seq[string]` (G23) |
| §7.5 ¶5 | SetError `tooManyRecipients` includes max count | `setTooManyRecipients` + `maxRecipientCount*: UnsignedInt` (G23) |
| §7.5 ¶5 | SetError `noRecipients` when rcptTo empty | `setNoRecipients` (G23) |
| §7.5 ¶5 | SetError `invalidRecipients` includes bad addresses | `setInvalidRecipients` + `invalidRecipients*: seq[string]` (G23) |
| §7.5 ¶5 | SetError `forbiddenMailFrom` when SMTP MAIL FROM disallowed | `setForbiddenMailFrom` (G23) |
| §7.5 ¶5 | SetError `forbiddenFrom` when RFC 5322 From disallowed | `setForbiddenFrom` (G23) |
| §7.5 ¶5 | SetError `forbiddenToSend` when user lacks send permission | `setForbiddenToSend` (G23) |
| §7.5 ¶6 | SetError `cannotUnsend` when cancel fails | `setCannotUnsend` (G23) |
| §1.3.2 | Capability `maxDelayedSend` is `UnsignedInt` seconds | `SubmissionCapabilities.maxDelayedSend` |
| §1.3.2 | Capability `submissionExtensions` is EHLO-name → args map | `SubmissionExtensionMap` (distinct OrderedTable) (G25) |

### 1.5. Module Summary

| Module | Layer | Contents |
|--------|-------|----------|
| `submission_atoms.nim` | L1 | `RFC5321Keyword`, `OrcptAddrType` — distinct strings sharing the RFC 5321 `esmtp-keyword` lexical shape. Case-insensitive equality for `RFC5321Keyword`; byte-equal for `OrcptAddrType`. |
| `submission_mailbox.nim` | L1 | `RFC5321Mailbox` — distinct string + strict/lenient parser pair for the full RFC 5321 §4.1.2 `Mailbox` grammar (`Local-part "@" ( Domain / address-literal )`, IPv4/IPv6/General-address-literal covered). |
| `submission_param.nim` | L1 | `BodyEncoding`, `DsnRetType`, `DsnNotifyFlag`, `DeliveryByMode`, `HoldForSeconds`, `MtPriority`, `SubmissionParamKind`, `SubmissionParam`, `SubmissionParamKey`, `SubmissionParams`, and the parameter smart constructors (`bodyParam`, `notifyParam`, `orcptParam`, etc.). |
| `submission_envelope.nim` | L1 | `SubmissionAddress`, `ReversePathKind`, `ReversePath`, `NonEmptyRcptList`, `Envelope`, reverse-path smart constructors. Re-exports `submission_atoms`, `submission_mailbox`, and `submission_param` so a single `import ./submission_envelope` surfaces every public name in the envelope L1 family. |
| `submission_status.nim` | L1 | `UndoStatus`, `DeliveredState`, `ParsedDeliveredState`, `DisplayedState`, `ParsedDisplayedState`, `ReplyCode`, `StatusCodeClass`, `SubjectCode`, `DetailCode`, `EnhancedStatusCode`, `SmtpReplyViolation`, `ParsedSmtpReply`, `parseSmtpReply`, `renderSmtpReply`, `DeliveryStatus`, `DeliveryStatusMap`. |
| `email_submission.nim` | L1 | `EmailSubmission[S: static UndoStatus]`, `AnyEmailSubmission`, `IdOrCreationRef`, `EmailSubmissionBlueprint`, `EmailSubmissionUpdate`, `NonEmptyEmailSubmissionUpdates`, `EmailSubmissionFilterCondition`, `NonEmptyIdSeq`, `EmailSubmissionSortProperty`, `EmailSubmissionComparator`, `EmailSubmissionCreatedItem`, `EmailSubmissionSetResponse`, `NonEmptyOnSuccessUpdateEmail`, `NonEmptyOnSuccessDestroyEmail`, `EmailSubmissionHandles`, `EmailSubmissionResults`. |
| `serde_submission_envelope.nim` | L2 | Serde for `SubmissionAddress`, `ReversePath`, `Envelope`, `NonEmptyRcptList`, and the `SubmissionParam` / `SubmissionParamKey` / `SubmissionParams` family. `SerdeViolation` + `JsonPath`. |
| `serde_submission_status.nim` | L2 | Serde for `UndoStatus`, `ParsedDeliveredState`, `ParsedDisplayedState`, `DeliveryStatus`, `DeliveryStatusMap` (and exported `parseUndoStatus`). |
| `serde_email_submission.nim` | L2 | Serde for `AnyEmailSubmission` (existential dispatch via `fromJsonShared[S]`), `EmailSubmissionCreatedItem`, `EmailSubmissionBlueprint`, `EmailSubmissionUpdate`, `NonEmptyEmailSubmissionUpdates`, `EmailSubmissionFilterCondition`, `EmailSubmissionComparator`, `IdOrCreationRef`, and the two `NonEmptyOnSuccess*` containers. |
| `submission_builders.nim` | L3 | Builders for all 5 methods + compound `addEmailSubmissionAndEmailSet`. |
| `mail_capabilities.nim` | L1 | `SubmissionCapabilities.submissionExtensions: SubmissionExtensionMap` — distinct wrapper keyed on `RFC5321Keyword` (G25). |
| `mail_entities.nim` | L3 | EmailSubmission entity registration: `methodEntity`, `getMethodName`, `changesMethodName`, `setMethodName`, `queryMethodName`, `queryChangesMethodName`, `capabilityUri`, plus the typed associated-type templates (`changesResponseType`, `filterType`, `createType`, `updateType`, `setResponseType`) and the entity registrations (`registerJmapEntity`, `registerQueryableEntity`, `registerSettableEntity`, `registerCompoundMethod`). |
| `serialisation.nim` | — | Re-export of the three new serde modules. |

---

## 2. Envelope + Address Vocabulary

All types in this section live under `{.push raises: [], noSideEffect.}` and
are split by concern across four L1 files — `submission_mailbox.nim`
(§2.1), `submission_atoms.nim` (§2.2), `submission_param.nim` (§2.3–§2.4),
and `submission_envelope.nim` (§2.5). `submission_envelope.nim` re-exports
the other three so downstream importers see a single surface.

### 2.1. RFC5321Mailbox (`submission_mailbox.nim`)

RFC 8621 §7's `Address.email` field uses the RFC 5321 `Mailbox` production
(`Local-part "@" ( Domain / address-literal )`, §4.1.2) — distinct from the
RFC 5322 `addr-spec` used in Email headers (`EmailAddress.email`). The
distinct newtype prevents cross-use at the type level (G6).

```nim
type RFC5321Mailbox* = distinct string

defineStringDistinctOps(RFC5321Mailbox)

func parseRFC5321Mailbox*(raw: string): Result[RFC5321Mailbox, ValidationError]
func parseRFC5321MailboxFromServer*(raw: string): Result[RFC5321Mailbox, ValidationError]
```

The strict parser validates the full RFC 5321 `Mailbox` grammar at
client-construction time: `Dot-string` and `Quoted-string` local-parts,
`Domain` and `address-literal` (IPv4, all four IPv6 forms — `IPv6-full`,
`IPv6-comp`, `IPv6v4-full`, `IPv6v4-comp` — and General-address-literal)
domain forms. RFC §4.5.3.1.1 / §4.5.3.1.2 length caps are enforced
(local-part ≤ 64, domain ≤ 255). The lenient parser validates structural
shape only (1..255 octets, no control characters, contains `@`) for
server-received data — Postel's law. Neither parser handles the enclosing
`Path` production (`"<" [ A-d-l ":" ] Mailbox ">"`); source routes are part
of `Path`, not `Mailbox`, and are irrelevant at the JMAP layer.

### 2.2. RFC5321Keyword + OrcptAddrType (`submission_atoms.nim`)

SMTP extension keywords (`esmtp-keyword` per RFC 5321 §4.1.1.1:
`(ALPHA / DIGIT) *(ALPHA / DIGIT / "-")`). Used as parameter names in
`SubmissionParam.spkExtension` and as capability keys in
`SubmissionExtensionMap` (G8, G25).

```nim
type RFC5321Keyword* = distinct string

func `==`*(a, b: RFC5321Keyword): bool       # case-insensitive (RFC 5321 §2.4)
func `$`*(a: RFC5321Keyword): string {.borrow.}  # preserves original casing
func hash*(a: RFC5321Keyword): Hash          # case-fold hash
func len*(a: RFC5321Keyword): int {.borrow.}

func parseRFC5321Keyword*(raw: string): Result[RFC5321Keyword, ValidationError]
```

Validates: starts with ASCII letter or digit, followed by
letters/digits/hyphens, length 1..64 octets (defensive cap — the RFC is
silent on an explicit maximum). Single parser — no strict/lenient pair (the
grammar is unambiguous; server-sent and client-sent values share the same
constraints).

`==` and `hash` are case-insensitive (ASCII case-fold), matching RFC 5321
§2.4 ("extension name keywords are not case sensitive") and §4.1.1.1 ("EHLO
keywords… MUST always be recognized and processed in a case-insensitive
manner"). This ensures correct Table lookups in `SubmissionExtensionMap` and
`SubmissionParamKey` regardless of server casing. `$` preserves the original
casing for diagnostic round-trip.

`OrcptAddrType` shares the same lexical grammar but is byte-equal — RFC 3461
does not mandate case-folding for the addr-type atom of `ORCPT=`, so
`==`/`hash`/`$` come through `defineStringDistinctOps`.

```nim
type OrcptAddrType* = distinct string

defineStringDistinctOps(OrcptAddrType)

func parseOrcptAddrType*(raw: string): Result[OrcptAddrType, ValidationError]
```

Each parser routes its structural failures through a module-private
`*Violation` enum (`KeywordViolation` for `RFC5321Keyword`,
`OrcptAddrTypeViolation` for `OrcptAddrType`) and a dedicated
`toValidationError` translator overload (functional-core Pattern 5 —
translation at the boundary).

### 2.3. SubmissionParam — Typed Sealed Sum + Extension Arm (`submission_param.nim`)

SMTP parameters are typed per-extension rather than collapsed to strings.
Known extensions get typed payloads; unknown extensions carry a validated
`RFC5321Keyword` name and an optional string value (G8, G8b, G8c).

```nim
type
  BodyEncoding* = enum
    beSevenBit     = "7BIT"
    beEightBitMime = "8BITMIME"
    beBinaryMime   = "BINARYMIME"

  DsnRetType* = enum
    retFull = "FULL"
    retHdrs = "HDRS"

  DsnNotifyFlag* = enum
    dnfNever    = "NEVER"
    dnfSuccess  = "SUCCESS"
    dnfFailure  = "FAILURE"
    dnfDelay    = "DELAY"

  DeliveryByMode* = enum
    dbmReturn      = "R"
    dbmNotify      = "N"
    dbmReturnTrace = "RT"
    dbmNotifyTrace = "NT"

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
    of spkOrcpt:      orcptAddrType*: OrcptAddrType
                      orcptOrigRecipient*: string
    of spkHoldFor:    holdFor*: HoldForSeconds
    of spkHoldUntil:  holdUntil*: UTCDate
    of spkBy:         byDeadline*: JmapInt
                      byMode*: DeliveryByMode
    of spkMtPriority: mtPriority*: MtPriority
    of spkExtension:  extName*: RFC5321Keyword
                      extValue*: Opt[string]
```

`HoldForSeconds` and `MtPriority` are distinct newtypes with smart
constructors — not `range[T]`, which would cause fatal `RangeDefect` on
invalid input rather than returning a `Result`.

```nim
func parseHoldForSeconds*(raw: UnsignedInt): Result[HoldForSeconds, ValidationError]
func parseMtPriority*(raw: int):              Result[MtPriority, ValidationError]
```

`parseHoldForSeconds` is total — `UnsignedInt` already enforces the JSON-
safe `0..2^53-1` bound at its own smart constructor, so the wrapper has
nothing to reject. The `Result`-returning signature is uniform with the
other `parse*` functions so callers compose with `?`/`valueOr:`.
`parseMtPriority` enforces the inclusive `-9..9` bound of RFC 6710 §2.

NOTIFY mutual exclusion: `dnfNever` is mutually exclusive with
`{dnfSuccess, dnfFailure, dnfDelay}`. Enforced in the `notifyParam` smart
constructor, not structurally split into a case object. The invariant is
narrow (one rule) and a structural split would add ceremony without payoff.

```nim
func notifyParam*(flags: set[DsnNotifyFlag]): Result[SubmissionParam, ValidationError]
```

Twelve smart constructors (one per variant) live alongside in alphabetical
order: `bodyParam`, `byParam`, `envidParam`, `extensionParam`,
`holdForParam`, `holdUntilParam`, `mtPriorityParam`, `notifyParam`,
`orcptParam`, `retParam`, `sizeParam`, `smtpUtf8Param`. An arm-dispatched
`==` lives on `SubmissionParam` because Nim's auto-derived `==` rejects
case objects (parallel-fields-iterator compile error).

### 2.4. SubmissionParams — ADT-Keyed Table (`submission_param.nim`)

The parameter collection uses a single `OrderedTable` keyed on a case-object
identity type. Structural uniqueness: the Table itself forbids duplicate
entries. Wire-order fidelity: `OrderedTable` preserves insertion order (G8a).

```nim
type
  SubmissionParamKey* {.ruleOff: "objects".} = object
    case kind*: SubmissionParamKind
    of spkExtension:
      extName*: RFC5321Keyword
    of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt,
        spkHoldFor, spkHoldUntil, spkBy, spkMtPriority:
      discard

  SubmissionParams* = distinct OrderedTable[SubmissionParamKey, SubmissionParam]

func `==`*(a, b: SubmissionParamKey): bool   # arm-dispatched; spkExtension
                                             # compares extName case-insensitively
func hash*(k: SubmissionParamKey): Hash      # arm-dispatched; mixes kind ord
                                             # into spkExtension hash
func paramKey*(p: SubmissionParam): SubmissionParamKey   # derived-not-stored
                                                          # (Pattern 6)

func `==`*(a, b: SubmissionParams): bool {.borrow.}
func `$`*(a: SubmissionParams): string {.borrow.}

func parseSubmissionParams*(
    items: openArray[SubmissionParam]
): Result[SubmissionParams, seq[ValidationError]]
```

Non-extension arms are enumerated explicitly rather than collapsed to
`else: discard` — `nim-functional-core.md`'s "never a `case` with catch-all
`else` when variants are finite" rule applies throughout L1–L3.

The key is derived from the value via `paramKey` (functional-core
Pattern 6 — "derived-not-stored"). The Table indexes by derived identity;
the value carries the full payload. `parseSubmissionParams` accumulates
duplicate-key violations via a two-`HashSet` kernel (`seen` /
`reported`) so each repeated key is reported exactly once.

`SubmissionAddress.parameters` is `Opt[SubmissionParams]` (G34), matching
the RFC's `Object|null`. `Opt.none` represents absent/null parameters;
`Opt.some` with an empty `SubmissionParams` represents the empty `{}`
JSON object — the serde layer distinguishes both cases per the codebase's
standard `Opt[T]` convention.

### 2.5. SubmissionAddress + Envelope (`submission_envelope.nim`)

```nim
type
  SubmissionAddress* {.ruleOff: "objects".} = object
    mailbox*:    RFC5321Mailbox
    parameters*: Opt[SubmissionParams]

  ReversePathKind* = enum
    rpkNullPath      ## SMTP null reverse path <>; wire: empty string;
                     ## may carry Mail-parameters
    rpkMailbox       ## Valid RFC 5321 Mailbox with optional parameters

  ReversePath* {.ruleOff: "objects".} = object
    case kind*: ReversePathKind
    of rpkNullPath: nullPathParams*: Opt[SubmissionParams]
    of rpkMailbox:  sender*:         SubmissionAddress

  NonEmptyRcptList* = distinct seq[SubmissionAddress]

  Envelope* {.ruleOff: "objects".} = object
    mailFrom*: ReversePath
    rcptTo*:   NonEmptyRcptList
```

Smart constructors for `ReversePath`:

```nim
func nullReversePath*(
    params: Opt[SubmissionParams] = Opt.none(SubmissionParams)
): ReversePath
  ## Infallible constructor for the SMTP null reverse path <>.

func reversePath*(address: SubmissionAddress): ReversePath
  ## Infallible wrapper: lifts a validated SubmissionAddress into ReversePath.
```

Arm-dispatched `==` lives on `ReversePath` (auto-derived `==` fails for
case objects).

`NonEmptyRcptList` exposes `==` / `$` / `len` as borrowed templates plus
explicit `[]` (int-indexed) and `items` / `pairs` iterators; the strict /
lenient parser pair (G7) covers client and server sides:

```nim
func parseNonEmptyRcptList*(
    items: openArray[SubmissionAddress]
): Result[NonEmptyRcptList, seq[ValidationError]]

func parseNonEmptyRcptListFromServer*(
    items: openArray[SubmissionAddress]
): Result[NonEmptyRcptList, ValidationError]
```

The strict parser (client construction) rejects empty AND duplicate
recipients keyed on `RFC5321Mailbox` via `validateUniqueByIt`. The lenient
parser (server receipt) rejects only empty — Postel's law.

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
and `usCanceled` are terminal. The string ↔ variant mapping lives in the
serde layer (`parseUndoStatus`); `UndoStatus` itself has no L1 smart
constructor — duplicating one would create two sources of truth with no L1
consumer.

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

func parseDeliveredState*(raw: string): ParsedDeliveredState   # total
func parseDisplayedState*(raw: string): ParsedDisplayedState   # total
```

Both parsers are total: case-sensitive match against the RFC-defined
backing strings; unrecognised input falls through to `dsOther` / `dpOther`
with `rawBacking` preserving the original token.

### 3.3. SmtpReply — Reply-line + Enhanced Status Code

The wire `smtpReply` field is parsed once at the serde boundary into a
fully-decomposed structure: RFC 5321 §4.2 multi-line Reply lines plus an
optional RFC 3463 §2 enhanced-status-code triple from the final line. The
`raw` field preserves the ingress bytes (for diagnostic fidelity); the
structured fields support equality and rendering (G12, H23).

```nim
type
  ReplyCode*       = distinct uint16   ## RFC 5321 §4.2.3 three-digit code
  StatusCodeClass* = enum               ## RFC 3463 §3.1 class digit
    sccSuccess           = "2"
    sccTransientFailure  = "4"
    sccPermanentFailure  = "5"
  SubjectCode*     = distinct uint16   ## RFC 3463 §4 subject sub-code (0..999)
  DetailCode*      = distinct uint16   ## RFC 3463 §4 detail sub-code (0..999)

  EnhancedStatusCode* {.ruleOff: "objects".} = object
    klass*:   StatusCodeClass
    subject*: SubjectCode
    detail*:  DetailCode

  ParsedSmtpReply* {.ruleOff: "objects".} = object
    replyCode*: ReplyCode
    enhanced*:  Opt[EnhancedStatusCode]
    text*:      string
    raw*:       string
```

A module-public `SmtpReplyViolation` enum names every structural and
enhanced-grammar failure mode (10 surface variants from G1, plus 5
enhanced-status-code variants from H1). The translator
`toValidationError(v: SmtpReplyViolation, raw: string): ValidationError`
is the sole domain-to-wire bridge (Pattern 5 — adding a violation forces
a compile error there and nowhere else).

```nim
func parseSmtpReply*(raw: string):  Result[ParsedSmtpReply, ValidationError]
func renderSmtpReply*(p: ParsedSmtpReply): string
```

`parseSmtpReply` runs the layered pipeline: emptiness, global byte-set
(`textstring` per §4.2.1 plus CR/LF), CRLF→LF normalisation, line splitting,
per-line surface grammar (`Reply-code` digit ranges, separator dispatch),
Reply-code consistency across lines, optional enhanced-triple per line,
enhanced-code consistency, and final assembly. Each phase is an L1 helper
(`detectReplyCodeGrammar`, `detectSeparator`, `detectClassDigit`,
`detectSubjectInRange`, `detectDetailInRange`, `detectConsistentItems`,
`detectEnhancedTriple`, etc.) so the composer reads as the RFC's layered
pipeline and `detectConsistentItems` is reused for both Reply-code and
enhanced-code consistency (one helper, two call sites).

`renderSmtpReply` emits the canonical LF form (H24): single-line reply as
`"<code> [<enhanced> ]<text>"`; multi-line as `"<code>-<line>\n…\n<code>
[<enhanced> ]<final>"`. Not equal to `p.raw` in general — `raw` preserves
ingress bytes (including CRLF); `renderSmtpReply` emits LF-only with no
trailing whitespace.

### 3.4. DeliveryStatus + DeliveryStatusMap

Per-recipient delivery state. The map is keyed on `RFC5321Mailbox` matching
the envelope `rcptTo` addresses (G9).

```nim
type DeliveryStatus* {.ruleOff: "objects".} = object
  smtpReply*: ParsedSmtpReply
  delivered*: ParsedDeliveredState
  displayed*: ParsedDisplayedState

type DeliveryStatusMap* = distinct Table[RFC5321Mailbox, DeliveryStatus]

func `==`*(a, b: DeliveryStatusMap): bool {.borrow.}
func `$`*(a: DeliveryStatusMap):     string {.borrow.}

func countDelivered*(m: DeliveryStatusMap): int
func anyFailed*(m: DeliveryStatusMap):     bool
```

`countDelivered` returns the number of recipients with
`delivered.state == dsYes`; `anyFailed` short-circuits true on the first
recipient with `delivered.state == dsNo`. Both iterate the underlying
`Table` via an explicit unwrap-cast (mutable stdlib containers don't borrow
subscripts cleanly, so domain operations stay on the distinct type).

---

## 4. EmailSubmission Entity Read Model

All types in this section live in `email_submission.nim` under
`{.push raises: [], noSideEffect.}`.

### 4.1. GADT-Style Phantom State Indexing

RFC §7's `undoStatus` determines which operations are valid on a submission.
A flat-record approach pushes that invariant into documentation and runtime
checks. The phantom-typed approach (G2, G3) lifts it into the type system:
`cancel` only accepts `EmailSubmission[usPending]`; the compiler rejects
attempts to cancel a final or already-canceled submission.

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

### 4.2. AnyEmailSubmission — Existential Wrapper (Pattern A Sealed)

`AnyEmailSubmission` is the runtime existential: pattern-match on `.state`
once, recover the phantom-indexed branch via the `as*` accessor.

```nim
type AnyEmailSubmission* {.ruleOff: "objects".} = object
  case state*: UndoStatus
  of usPending:  rawPending:  EmailSubmission[usPending]
  of usFinal:    rawFinal:    EmailSubmission[usFinal]
  of usCanceled: rawCanceled: EmailSubmission[usCanceled]

func toAny*(s: EmailSubmission[usPending]):  AnyEmailSubmission
func toAny*(s: EmailSubmission[usFinal]):    AnyEmailSubmission
func toAny*(s: EmailSubmission[usCanceled]): AnyEmailSubmission

func asPending*(s:  AnyEmailSubmission): Opt[EmailSubmission[usPending]]
func asFinal*(s:    AnyEmailSubmission): Opt[EmailSubmission[usFinal]]
func asCanceled*(s: AnyEmailSubmission): Opt[EmailSubmission[usCanceled]]

func `==`*(a, b: AnyEmailSubmission): bool   # arm-dispatched
```

Branch fields are module-private (`rawPending` etc.); construction is gated
by the `toAny` overload family (one per phantom instantiation), and read
access is via `asPending` / `asFinal` / `asCanceled`. The discriminator
`state` stays exported because callers `case` on it before projecting
through an accessor. Pattern A sealing mirrors `EmailSubmissionBlueprint` —
a wrong-branch read cannot be written. Under `--panics:on` the alternative
(a runtime `FieldDefect`) would be fatal and uncatchable across the FFI
boundary.

**Boundary pattern.** `fromJson` produces `AnyEmailSubmission`. Consumers
case once and project:

```nim
case sub.state
of usPending:
  for s in sub.asPending:
    let upd = cancelUpdate(s)
    # ...
of usFinal:
  for s in sub.asFinal:
    discard s   # render as sent
of usCanceled:
  for s in sub.asCanceled:
    discard s   # render as canceled
```

### 4.3. Typed Transition Functions

Pure L1 helpers build update records from phantom-constrained inputs (G4).
Callers use the generic `addEmailSubmissionSet` builder with the helper's
output.

```nim
func cancelUpdate*(s: EmailSubmission[usPending]): EmailSubmissionUpdate =
  discard s
  setUndoStatusToCanceled()
```

The `s` parameter is unused at runtime — the phantom binds at the call
site to carry the compile-time guarantee.
`cancelUpdate(EmailSubmission[usFinal])` and
`cancelUpdate(EmailSubmission[usCanceled])` are compile errors.

---

## 5. EmailSubmissionBlueprint (Creation)

### 5.1. Shape

RFC §7.5 allows three client-settable fields on create: `identityId`,
`emailId`, `envelope`. All others are server-set. Named "Blueprint" to match
the `EmailBlueprint` convention and signal construction-with-rules (G13).

```nim
type EmailSubmissionBlueprint* {.ruleOff: "objects".} = object
  rawIdentityId: Id
  rawEmailId:    Id
  rawEnvelope:   Opt[Envelope]

func identityId*(bp: EmailSubmissionBlueprint): Id           = bp.rawIdentityId
func emailId*(bp:    EmailSubmissionBlueprint): Id           = bp.rawEmailId
func envelope*(bp:   EmailSubmissionBlueprint): Opt[Envelope] = bp.rawEnvelope
```

Pattern A sealing (G38): fields are module-private with a `raw` prefix,
and same-name UFCS accessors provide the public read surface. Callers
cannot construct a record literal-wise and sidestep
`parseEmailSubmissionBlueprint`. This mirrors F1's `EmailBlueprint` and
`EmailCreate`.

`envelope: Opt[Envelope]` — `None` means "defer to server synthesis per
RFC §7.5 ¶4" (G14). No client-side synthesis helper; the server is the
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

`identityId`, `emailId`, and the inner `Envelope` invariants are already
enforced by their own smart constructors (`parseId`, `parseRFC5321Mailbox`,
`parseSubmissionParams`, `parseNonEmptyRcptList`); the Blueprint constructor
has nothing left to reject. The `Result[T, seq[ValidationError]]` signature
is uniform with `EmailBlueprint` so callers compose identically.

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

func setUndoStatusToCanceled*(): EmailSubmissionUpdate
func cancelUpdate*(s: EmailSubmission[usPending]): EmailSubmissionUpdate
```

The sealed-sum shape exists for forwards compatibility. The serde
`toJson(EmailSubmissionUpdate)` carries a module-scope `when` guard that
fails the build the moment a second `EmailSubmissionUpdateVariantKind`
variant is introduced — that is the signal to rewrite the body as a `case`
dispatch.

### 6.2. NonEmptyEmailSubmissionUpdates

`distinct Table[Id, EmailSubmissionUpdate]` enforcing non-emptiness at the
type level. Per-id uniqueness is structural (Table keys) (G17).

```nim
type NonEmptyEmailSubmissionUpdates* =
  distinct Table[Id, EmailSubmissionUpdate]

func parseNonEmptyEmailSubmissionUpdates*(
    items: openArray[(Id, EmailSubmissionUpdate)]
): Result[NonEmptyEmailSubmissionUpdates, seq[ValidationError]]
```

Accumulating error rail through `validateUniqueByIt`: every empty/duplicate
violation surfaces in a single `Err` pass, and each repeated `Id` key is
reported exactly once regardless of occurrence count.

---

## 7. Serde (SerdeViolation + JsonPath)

All serde follows the codebase-wide pattern (G26): every `fromJson`
signature carries `path: JsonPath = emptyJsonPath()` and returns
`Result[T, SerdeViolation]`. Single `toValidationError(sv, rootType)`
translator at the L2/L3 boundary.

Serde is split into three L2 files — `serde_submission_envelope.nim`
(envelope, addresses, params), `serde_submission_status.nim` (status enums
+ `DeliveryStatus`), and `serde_email_submission.nim` (entity + existential
dispatch + blueprint + update + filter + comparator +
`EmailSubmissionCreatedItem` + `IdOrCreationRef` + the `NonEmptyOnSuccess*`
containers). One serde module per L1 concern, symmetric with mail's
existing `serde_*` layout.

### 7.1. AnyEmailSubmission Deserialisation

`fromJson` peeks at `undoStatus` once at the serde boundary, picks the
phantom branch, then delegates the shared field list to a private generic
helper:

```nim
func fromJson*(
    T:    typedesc[AnyEmailSubmission],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[AnyEmailSubmission, SerdeViolation] =
  ?expectKind(node, JObject, path)
  let statusNode = ?fieldJString(node, "undoStatus", path)
  let status     = ?parseUndoStatus(statusNode.getStr(""), path / "undoStatus")
  case status
  of usPending:
    let s = ?fromJsonShared[usPending](node, path)
    return ok(toAny(s))
  of usFinal:
    let s = ?fromJsonShared[usFinal](node, path)
    return ok(toAny(s))
  of usCanceled:
    let s = ?fromJsonShared[usCanceled](node, path)
    return ok(toAny(s))
```

`fromJsonShared[S: static UndoStatus]` parses the shared field list once,
monomorphising at dispatch. The phantom erases at runtime, so the three
instantiations compile to effectively the same body differing only in
return-type metadata. Construction flows through the `toAny` overload
family — the canonical gateway for the sealed `AnyEmailSubmission`.

`parseUndoStatus(raw, path)` is exported from `serde_submission_status.nim`
so the entity dispatcher and `fromJson(UndoStatus)` share the same
closed-enum recogniser without a double `JString` kind check. Unknown
values surface as `svkEnumNotRecognised` — `UndoStatus` is RFC-closed, so
this is a protocol violation, not a forwards-compatibility concern.

### 7.2. Envelope + Parameters Serde

`SubmissionParams.toJson` iterates the `OrderedTable`, emitting each
parameter as a key-value pair in a JSON object. The wire key is the
string-backed `SubmissionParamKind` for known variants, or `extName` for
extensions.

`SubmissionParams.fromJson` reverses: each `(key, value)` pair is dispatched
to the matching variant parser via case-insensitive match against `$kind`,
falling back to `parseParamExtension` for unrecognised keys. The resulting
list is funnelled through `parseSubmissionParams` so the L1 invariants (no
duplicate keys) hold for the returned value.

`paramValueToJson` emits the wire value side of one parameter. RFC 8621
§7.3.2 constrains values to `String|null`; numeric parameters (SIZE,
HOLDFOR, BY deadline, MT-PRIORITY) ride as JSON strings of decimal digits,
never JSON ints. NOTIFY flag sets join via `notifyFlagsToWire`; ORCPT and
BY use the `<addr-type>;<orig-recipient>` and `<deadline>;<mode>` shapes
respectively. Reverse parsers mirror these splits.

> **xtext / unitext at the JMAP boundary.** RFC 8621 §7.3.2 (lines
> 4207–4210) explicitly says *"any xtext or unitext encodings are removed
> (see [RFC3461] and [RFC6533]) and JSON string encoding is applied"* for
> JMAP `Address` parameters. The server handles the SMTP-side translation;
> the JMAP wire already carries plain UTF-8 JSON strings on both ingress
> and egress. Consequently `ENVID`, `ORCPT.orig-recipient`, and every
> other parameter string in the L1 model carry plain UTF-8 bytes, and
> `serde_submission_envelope.nim` ships **without** xtext/unitext helpers.

`toJson`/`fromJson` for `ReversePath`: the wire format is the RFC §7
`Address` object in both cases. `rpkNullPath` serialises with `email` set
to the empty string `""` and optional `parameters`; `rpkMailbox` delegates
to `SubmissionAddress` serde. `fromJson` dispatches on the `email` field:
empty string → `rpkNullPath` (with optional parameters parsed from the same
object), non-empty → parse as `RFC5321Mailbox` → `rpkMailbox`.

### 7.3. Creation, Update, Filter, and IdOrCreationRef Serialisation

`EmailSubmissionBlueprint`, `EmailSubmissionFilterCondition`, and
`EmailSubmissionComparator` are `toJson`-only — they flow client → server
and the server never sends them back.

`NonEmptyEmailSubmissionUpdates.toJson` emits the wire shape
`{subId: {patchKey: patchVal, ...}, ...}`. The L1 container maps one
`EmailSubmissionUpdate` per id, so each inner PatchObject has exactly one
key — today `"undoStatus": "canceled"`.

`IdOrCreationRef` exports two serde helpers: `idOrCreationRefWireKey` (raw
string form: the `Id` verbatim or `"#"` + `CreationId`) for Table-key
stringification, and `toJson` (JSON string form of the wire key) for use
when an `IdOrCreationRef` appears as a list element rather than a map key.
No `fromJson` — the server never sends these keys back.

`NonEmptyOnSuccessUpdateEmail.toJson` flattens to RFC 8621 §7.5 ¶3 wire
shape `{idOrCreationRefKey: patchObj, ...}` via `idOrCreationRefWireKey` +
`EmailUpdateSet.toJson`; `NonEmptyOnSuccessDestroyEmail.toJson` emits the
JSON array shape `[idOrCreationRefKey, ...]`.

### 7.4. EmailSubmissionCreatedItem — Postel's Law on the Create Response

`EmailSubmission/set` returns a `created` map whose values are the
server-authoritative subset of `EmailSubmission` fields. The shape models
real-world server divergence:

```nim
type EmailSubmissionCreatedItem* {.ruleOff: "objects".} = object
  id*:         Id
  threadId*:   Opt[Id]
  sendAt*:     Opt[UTCDate]
  undoStatus*: Opt[UndoStatus]
```

`fromJson` for `EmailSubmissionCreatedItem` requires only `id`; `threadId`,
`sendAt`, and `undoStatus` are `Opt[T]` because servers diverge on what
they include in the create acknowledgement:

- **Stalwart 0.15.5** emits only `{"id": "<id>"}` — strict-RFC §7.5 ¶2
  minimum.
- **Cyrus 3.12.2** emits `{"id", "undoStatus", "sendAt"}` —
  `imap/jmap_mail_submission.c` returns the full server-set state inline
  because Cyrus's submission lifecycle is fire-and-forget: the server may
  have already finalised and discarded the record by the time the client
  could call `/get`, so the create response must carry the live state to
  be useful.
- **James 3.9** TBD — defers to live `/get`.

Capturing `undoStatus` from the create response lets callers avoid a
futile `/get` poll on Cyrus while gracefully accepting a sparse response
on Stalwart. Postel's-law accommodation per `nim-conventions.md`'s
"Serde Conventions" — be lenient on receive. The `mixin`-resolved
`SetResponse[EmailSubmissionCreatedItem].fromJson` drives this at the
generic dispatch site.

---

## 8. Method Builders

All builders live in `submission_builders.nim`.

### 8.1. Standard Methods

```nim
func addEmailSubmissionGet*(
    b: RequestBuilder,
    accountId: AccountId,
    ids:        Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]]           = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[AnyEmailSubmission]])

func addEmailSubmissionChanges*(
    b: RequestBuilder,
    accountId:  AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[ChangesResponse[AnyEmailSubmission]])

func addEmailSubmissionQuery*(
    b: RequestBuilder,
    accountId:   AccountId,
    filter:      Opt[Filter[EmailSubmissionFilterCondition]] =
                   Opt.none(Filter[EmailSubmissionFilterCondition]),
    sort:        Opt[seq[EmailSubmissionComparator]] =
                   Opt.none(seq[EmailSubmissionComparator]),
    queryParams: QueryParams = QueryParams(),
): (RequestBuilder, ResponseHandle[QueryResponse[AnyEmailSubmission]])

func addEmailSubmissionQueryChanges*(
    b: RequestBuilder,
    accountId:       AccountId,
    sinceQueryState: JmapState,
    filter:          Opt[Filter[EmailSubmissionFilterCondition]] =
                       Opt.none(Filter[EmailSubmissionFilterCondition]),
    sort:            Opt[seq[EmailSubmissionComparator]] =
                       Opt.none(seq[EmailSubmissionComparator]),
    maxChanges:      Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId:          Opt[Id]         = Opt.none(Id),
    calculateTotal:  bool            = false,
): (RequestBuilder, ResponseHandle[QueryChangesResponse[AnyEmailSubmission]])
```

`ids` on `addEmailSubmissionGet` and `destroy` on both `/set` overloads
take `Referencable[seq[Id]]` so the caller may supply either a literal
id list or a result reference resolving to an id list from a sibling
method call (RFC 8620 §3.7). `properties` is `seq[string]` because
`addGet` is property-name type-agnostic.

`addEmailSubmissionQuery` bundles window parameters (`position`,
`anchor`, `anchorOffset`, `limit`, `calculateTotal`) into `QueryParams` —
the same bundle is used across every `add*Query` in the codebase.
`addEmailSubmissionQueryChanges` omits the window parameters per
RFC 8620 §5.6 ("queryChanges" does not accept them) and carries
`calculateTotal` as a non-optional `bool` defaulting to `false`.

### 8.2. Simple Set

```nim
func addEmailSubmissionSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create:    Opt[Table[CreationId, EmailSubmissionBlueprint]] =
                 Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    update:    Opt[NonEmptyEmailSubmissionUpdates] =
                 Opt.none(NonEmptyEmailSubmissionUpdates),
    destroy:   Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): (RequestBuilder, ResponseHandle[EmailSubmissionSetResponse])
```

Thin wrapper over `addSet[AnyEmailSubmission, EmailSubmissionBlueprint,
NonEmptyEmailSubmissionUpdates, EmailSubmissionSetResponse]`. For the
`onSuccessUpdateEmail` / `onSuccessDestroyEmail` extensions, use
`addEmailSubmissionAndEmailSet` (§9.1).

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

`NonEmptyIdSeq` exposes `==`, `$`, `len`, and an `Idx`-typed `[]` plus a
semantic `head` accessor and an `items` iterator. The `Idx` parameter on
`[]` lifts the non-negative precondition to the type system.

`parseNonEmptyIdSeq` rejects empty input only — RFC 8621 §7.3 filter list
semantics permit any combination of duplicates, so the constructor matches
`parseNonEmptySeq` (single `ValidationError`, non-empty check only).

**Strictness note (G37):** The RFC allows empty arrays for `identityIds`,
`emailIds`, and `threadIds`. This design wraps them in
`Opt[NonEmptyIdSeq]` — an intentional "make the wrong thing hard" choice.
An empty filter list matches nothing, which is almost certainly a caller
error. `Opt.none` provides the "no constraint on this property" case.

`undoStatus` is typed against the `UndoStatus` enum. Since this field is
client-sent, the `dsOther`/`dpOther` catch-all pattern from G10/G11 does
not apply (G18).

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
  collation*:   Opt[CollationAlgorithm]

func parseEmailSubmissionComparator*(
    rawProperty: string,
    isAscending: bool                    = true,
    collation:   Opt[CollationAlgorithm] = Opt.none(CollationAlgorithm),
): Result[EmailSubmissionComparator, ValidationError]
```

The smart constructor resolves the wire token to a known
`EmailSubmissionSortProperty` variant, falling back to `esspOther` with the
raw token preserved on `rawProperty`. The wire token is always emitted
verbatim from `rawProperty` — for known properties it equals
`$property`; for `esspOther` it is the only authoritative value.

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
    case kind*: IdOrCreationRefKind
    of icrDirect:   id*:         Id
    of icrCreation: creationId*: CreationId

func directRef*(id: Id):           IdOrCreationRef
func creationRef*(cid: CreationId): IdOrCreationRef

func `==`*(a, b: IdOrCreationRef): bool   # arm-dispatched
func hash*(k: IdOrCreationRef):    Hash   # arm-dispatched, mixes kind ord
```

Arm-dispatched `==` and `hash` are required: cross-arm values compare
unequal even on coincident payload strings (an `icrDirect` with `Id("abc")`
and an `icrCreation` with `CreationId("abc")` are not the same key). The
`hash` mixes the discriminator ordinal into the payload hash so coincident
payload strings land in different buckets — without it,
`Table[IdOrCreationRef, _]` lookups in the compound builder would silently
break.

### 9.1. NonEmptyOnSuccessUpdateEmail / NonEmptyOnSuccessDestroyEmail

The two compound extras carry their own non-empty + dup-free type. Empty
and duplicate-key shapes are unrepresentable; `Opt.none` is the sole
"no extras" encoding (G22).

```nim
type NonEmptyOnSuccessUpdateEmail*  = distinct Table[IdOrCreationRef, EmailUpdateSet]
type NonEmptyOnSuccessDestroyEmail* = distinct seq[IdOrCreationRef]

func parseNonEmptyOnSuccessUpdateEmail*(
    items: openArray[(IdOrCreationRef, EmailUpdateSet)]
): Result[NonEmptyOnSuccessUpdateEmail, seq[ValidationError]]

func parseNonEmptyOnSuccessDestroyEmail*(
    items: openArray[IdOrCreationRef]
): Result[NonEmptyOnSuccessDestroyEmail, seq[ValidationError]]
```

Both constructors run `validateUniqueByIt` so empty input AND duplicate
keys/elements accumulate into a single `Err` pass — silent last-wins
shadowing at Table construction would swallow caller data.

### 9.2. addEmailSubmissionAndEmailSet

Named per F1's AND-connector convention (`addEmailCopyAndDestroy`) (G20).
Triggers an implicit `Email/set` after `EmailSubmission/set` succeeds,
driven by `onSuccessUpdateEmail` and/or `onSuccessDestroyEmail`.

```nim
func addEmailSubmissionAndEmailSet*(
    b: RequestBuilder,
    accountId: AccountId,
    create:                 Opt[Table[CreationId, EmailSubmissionBlueprint]] =
                              Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    update:                 Opt[NonEmptyEmailSubmissionUpdates] =
                              Opt.none(NonEmptyEmailSubmissionUpdates),
    destroy:                Opt[Referencable[seq[Id]]] =
                              Opt.none(Referencable[seq[Id]]),
    onSuccessUpdateEmail:   Opt[NonEmptyOnSuccessUpdateEmail] =
                              Opt.none(NonEmptyOnSuccessUpdateEmail),
    onSuccessDestroyEmail:  Opt[NonEmptyOnSuccessDestroyEmail] =
                              Opt.none(NonEmptyOnSuccessDestroyEmail),
    ifInState:              Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, EmailSubmissionHandles)
```

The two compound extras arrive as `NonEmpty*` wrappers, each toJson-mapped
through `idOrCreationRefWireKey` for keys and `EmailUpdateSet.toJson` for
patch values. The typical flow — send a message, remove `$draft`, move from
Drafts to Sent — composes from existing `EmailUpdate` constructors:

```nim
let updates = initEmailUpdateSet(@[
  removeKeyword(kwDraft),
  removeFromMailbox(draftsId),
  addToMailbox(sentId),
]).get()

let onUpdate = parseNonEmptyOnSuccessUpdateEmail(@[
  (creationRef(submissionCid), updates),
]).get()

let (req, handles) = b.addEmailSubmissionAndEmailSet(
  accountId            = acc,
  create               = { creationRef: blueprint }.toTable,
  onSuccessUpdateEmail = Opt.some(onUpdate),
)
```

### 9.3. EmailSubmissionCreatedItem + EmailSubmissionHandles + getBoth

`EmailSubmission/set` returns a `created` map keyed by `CreationId` with
`EmailSubmissionCreatedItem` payloads. The shape and Postel's-law rationale
are described in §7.4.

`undoStatus` IS carried on `EmailSubmissionCreatedItem` as
`Opt[UndoStatus]`: a delay-send-disabled server may flip the value to
`final` or `canceled` immediately, and a server like Cyrus may discard the
record before any subsequent `/get`. Capturing the live state at create
time (when present) lets callers avoid a futile poll while gracefully
accepting absence.

The compound handle pair aliases the generic from `dispatch.nim` (RFC 8620
§5.4 implicit-call dispatch):

```nim
type EmailSubmissionHandles* =
  CompoundHandles[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]

type EmailSubmissionResults* =
  CompoundResults[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]
```

Field access is `handles.primary` (the declared `EmailSubmission/set`
response) and `handles.implicit` (the server-emitted `Email/set` follow-up,
sharing the parent call-id with a method-name filter per RFC 8620 §5.4).
The `mnEmailSet` filter is set on construction so the extractor needs no
call-site argument.

The generic extractor lives in `dispatch.nim`:

```nim
func getBoth*[A, B](
    resp: Response, handles: CompoundHandles[A, B]
): Result[CompoundResults[A, B], MethodError]
```

`mixin fromJson` defers serde lookup until call-site instantiation, where
`SetResponse[EmailCreatedItem].fromJson` and
`EmailSubmissionSetResponse.fromJson` are in scope (the two are re-exported
from `submission_builders.nim` so consumers get them through a single
import). `registerCompoundMethod(EmailSubmissionSetResponse,
SetResponse[EmailCreatedItem])` in `mail_entities.nim` compile-checks the
participation gate at module load.

---

## 10. SetError Extensions Reference

All 8 EmailSubmission-specific `SetErrorType` variants plus the standard
`tooLarge` (reused with submission-specific `maxSize` payload per RFC 8621
§7.5) live in `errors.nim`. Mail-layer typed accessors are in
`mail_errors.nim` (G23). No new variants or accessors are needed (G24).

| Method | RFC-listed error | Enum variant | Payload accessor |
|--------|-----------------|---------------|-----------------|
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

`SubmissionCapabilities.submissionExtensions` is a distinct wrapper keyed
on `RFC5321Keyword` (G25). `RFC5321Keyword`'s case-insensitive `==` and
`hash` give the underlying `OrderedTable` structural uniqueness and
wire-order fidelity automatically.

```nim
type SubmissionExtensionMap* = distinct OrderedTable[RFC5321Keyword, seq[string]]

func `==`*(a, b: SubmissionExtensionMap): bool   {.borrow.}
func `$`*(a:    SubmissionExtensionMap): string {.borrow.}

type SubmissionCapabilities* {.ruleOff: "objects".} = object
  maxDelayedSend*:       UnsignedInt
  submissionExtensions*: SubmissionExtensionMap
```

`parseSubmissionCapabilities` (in `serde_mail_capabilities.nim`) is the
construction gateway: keys are validated via `parseRFC5321Keyword`, values
are JSON arrays of strings.

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
| G1 | Module organisation | (A) single file, (B) small L1 split by concern, (C) large L1 split with serde mirror | **C** — five L1 files (`submission_atoms.nim`, `submission_mailbox.nim`, `submission_param.nim`, `submission_envelope.nim`, `submission_status.nim`) plus `email_submission.nim`; three serde files mirroring the envelope / status / entity split (`serde_submission_envelope.nim`, `serde_submission_status.nim`, `serde_email_submission.nim`) | Single responsibility; mirrors Email's multi-file family; splits heavy RFC 5321 Mailbox parser from lightweight esmtp-keyword atoms |
| G2 | Entity shape | (A) flat record, (B) case object on UndoStatus, (C) GADT-style phantom + AnyEmailSubmission wrapper | **C** — phantom-typed `EmailSubmission[S: static UndoStatus]` + Pattern-A-sealed existential wrapper | Make state transitions explicit in the type; types tell the truth |
| G3 | UndoStatus + phantom encoding | (A) empty-object markers unbound, (B) union-constrained, (C) `static UndoStatus` generic (DataKinds) | **C** — `[S: static UndoStatus]`; enum IS the phantom | One source of truth per fact |
| G4 | Transition API surface | (A) L1 typed helper only, (B) L3 typed builder, (C) both, (D) none | **A** — `cancelUpdate(s: EmailSubmission[usPending])` at L1 | Functional core, imperative shell |
| G6 | Address type | (A) reuse EmailAddress, (B) new SubmissionAddress plain string, (C) new + distinct RFC5321Mailbox | **C** — distinct `RFC5321Mailbox` + `SubmissionAddress` | Newtype everything; parse don't validate |
| G7 | rcptTo non-emptiness | (A) distinct seq strict/lenient pair, (B) distinct seq single strict, (C) plain seq in Envelope | **A** — `NonEmptyRcptList` with strict/lenient parsers | Newtype everything; Postel's law |
| G8 | Parameters map (high-level) | (A) raw table, (B) distinct table + validated keys, (C) distinct + key newtype | **Typed sealed sum + extension arm** (beyond A/B/C) | Maximal type safety for known; open-world for unknown |
| G8a | Params container | (i) distinct seq, (ii) split table, (iii) single Table keyed on ADT | **(iii)** — `distinct OrderedTable[SubmissionParamKey, SubmissionParam]` | Make illegal states unrepresentable (structural uniqueness) |
| G8b | Known-parameter set | (A) RFC 8621 strict, (B) + BODY + SMTPUTF8, (C) narrow | **B** — 11 typed variants + extension arm | Practical coverage |
| G8c | Per-param payloads | Full draft: enums, distinct newtypes, flat composites, plain UTF-8 strings | **Accept as drafted** | Parse don't validate; avoid range[T] |
| G9 | DeliveryStatus map key | (A) string, (B) RFC5321Mailbox, (C) distinct DeliveryStatusMap | **C** — `distinct Table[RFC5321Mailbox, DeliveryStatus]` | Newtype everything |
| G10 | `delivered` enum | (A) closed, (B) + dsOther catch-all, (C) sealed sum empty branches | **B** — 4 RFC-defined + `dsOther` + `ParsedDeliveredState` | Postel's law; MethodError/SetError precedent |
| G11 | `displayed` enum | (A) closed, (B) + dpOther catch-all | **B** — symmetric with G10 | Consistency |
| G12 | smtpReply type | (A) plain string, (B) distinct + smart ctor, (C) fully parsed (RFC 5321 §4.2 + RFC 3463 §2 enhanced status code) | **C** — `ParsedSmtpReply` with `replyCode`, `enhanced`, `text`, `raw`; `parseSmtpReply` / `renderSmtpReply` round-trip | Parse once at the boundary; preserve ingress for diagnostics |
| G13 | Creation model naming | (A) EmailSubmissionCreate, (B) EmailSubmissionBlueprint, (C) NewEmailSubmission | **B** — Blueprint | Signals construction-with-rules |
| G14 | Envelope default-synthesis | (A) pass-through Opt, (B) require client-side, (C) + helper | **A** — `Opt[Envelope]`; None = server synthesises | Postel's law; DRY; one source of truth |
| G15 | Blueprint error mode | (A) accumulating, (B) fail-fast | **A** — `seq[ValidationError]` | EmailBlueprint F1 precedent |
| G16 | Update algebra shape | (A) single-variant case, (B) empty marker, (C) function-only, (D) F1-parity | **D** — case object + protocol-primitive + domain-named | F1 parity; forwards-compatible |
| G17 | UpdateSet inclusion | (A) skip, (B) trivial set, (C) NonEmpty wrapper | **C** — `NonEmptyEmailSubmissionUpdates` | Newtype everything |
| G18 | Filter condition typing | (A) plain, (B) typed undoStatus, (C) + NonEmptyIdSeq | **C** — typed undoStatus + `NonEmptyIdSeq` | Make the wrong thing hard |
| G19 | Sort comparator typing | (A) string, (B) enum + catch-all, (C) closed enum | **B** — `EmailSubmissionSortProperty` + `esspOther` | Forward compatibility |
| G20 | Compound builder naming | (A) addEmailSubmissionAndEmailSet, (B) Send, (C) verbose, (D) SendAndFile | **A** — AND-connector | F1 naming convention |
| G21 | Compound handle shape | (A) bespoke EmailSubmissionHandles record, (B) generic `CompoundHandles[A, B]` alias | **B** — type alias of `CompoundHandles[EmailSubmissionSetResponse, SetResponse[EmailCreatedItem]]`; fields `primary` / `implicit` | One generic dispatch path; no per-entity duplication; `getBoth[A, B]` is generic in `dispatch.nim` |
| G22 | onSuccess* value args | (A) typed EmailUpdateSet, (B) raw JsonNode, (C) NonEmpty wrappers around typed values with IdOrCreationRef keys | **C** — `NonEmptyOnSuccessUpdateEmail` (`distinct Table[IdOrCreationRef, EmailUpdateSet]`) and `NonEmptyOnSuccessDestroyEmail` (`distinct seq[IdOrCreationRef]`) | DRY; type safety; empty/duplicate shapes unrepresentable |
| G23 | New SetError variants | Yes / No | **No** — all 8 EmailSubmission-specific variants plus standard `tooLarge` already live in `errors.nim` with payload accessors in `mail_errors.nim` | Reuse existing surface |
| G24 | Payload-less accessors | Yes / No | **No** — nothing to extract | — |
| G25 | SubmissionExtensions typing | (A) keep raw, (B) upgrade + distinct, (C) upgrade keys only | **B** — `SubmissionExtensionMap` | One type for one concept |
| G26 | Serde error rail | (A) string errors, (B) typed `SerdeViolation` + `JsonPath` | **B** — every `fromJson` takes `path: JsonPath = emptyJsonPath()` and returns `Result[T, SerdeViolation]`; single `toValidationError(sv, rootType)` at the L2/L3 boundary | Parse-don't-validate; uniform codebase serde contract |
| G27 | Envelope fromJson synthesis | (A) synthesise defaults client-side, (B) pass `Opt.none` through when null | **B** — `Opt.none` when the wire carries `null` | Server is the authoritative envelope computer |
| G32 | Envelope.mailFrom type | (A) SubmissionAddress (rejects empty), (B) Opt[RFC5321Mailbox] (loses params), (C) ReversePath sum (null parameterless), (C′) ReversePath sum (null with params) | **C′** — `ReversePath(rpkNullPath + Opt[SubmissionParams] \| rpkMailbox)` | Make illegal states unrepresentable; RFC fidelity — SMTP null path permits Mail-parameters (RFC 5321 §4.1.1.2); RFC 8621 §7 ¶5 ENVID note |
| G33 | ReversePath placement | (A) On SubmissionAddress (pollutes rcptTo), (B) On Envelope.mailFrom field | **B** — field-level sum; SubmissionAddress unchanged | rcptTo never admits empty |
| G34 | Parameters nullability | (A) Non-optional SubmissionParams, (B) Opt[SubmissionParams] | **B** — `Opt[SubmissionParams]` | RFC fidelity (`Object\|null`); codebase `Opt[Table]` precedent |
| G35 | onSuccess* key type | (A) Referencable[Id] (result-ref shape), (B) plain string, (C) IdOrCreationRef sum | **C** — `IdOrCreationRef(icrDirect \| icrCreation)` | RFC 8620 §5.3 vs §3.7 are distinct mechanisms |
| G36 | IdOrCreationRef vs Referencable | (A) Extend Referencable with third arm, (B) Separate type | **B** — different wire format, different semantics | One type for one concept |
| G37 | Filter list empty-rejection | (A) Opt[seq[Id]] (permits empty), (B) Opt[NonEmptyIdSeq] (rejects empty) | **B** — intentional strictness | Make the wrong thing hard |
| G38 | Sealed-record field access | (A) public fields, (B) Pattern A sealing (private `raw*` fields + UFCS / projection accessors) | **B** — applied to both `EmailSubmissionBlueprint` (UFCS accessors) and `AnyEmailSubmission` (`asPending` / `asFinal` / `asCanceled` returning `Opt[EmailSubmission[S]]`) | Smart constructors cannot be sidestepped by a record literal; safe variant projection without `FieldDefect` panics |
| G39 | `/set` response payload typing | (A) bespoke `EmailSubmissionSetResponse` record, (B) generic `SetResponse[EmailSubmissionCreatedItem]` type alias with `Opt`-wrapped server-divergent fields | **B** — `SetResponse[T]` generic instantiated with `EmailSubmissionCreatedItem` (`id` plus `Opt[Id]` `threadId`, `Opt[UTCDate]` `sendAt`, `Opt[UndoStatus]` `undoStatus`) | One generic response envelope across all `/set` methods; Postel's law accommodates Stalwart-minimum vs Cyrus-fire-and-forget vs James acknowledgement shapes |
