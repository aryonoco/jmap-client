# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Per-account capability schemas for RFC 8621 JMAP Mail. Surfaces the
## ``urn:ietf:params:jmap:mail`` and ``urn:ietf:params:jmap:submission``
## account-scope objects as typed Pattern-A values, and gathers each
## account capability entry under a single sealed case object whose
## payload arm carries the typed schema for implemented RFCs and an
## opaque ``JsonNode`` for unimplemented arms (P20 forward-compat).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sets
from std/json import JsonNode, newJObject, `$`

import results

import ./validation
import ./primitives
import ./capabilities
import ./submission_atoms

# ===========================================================================
# MailAccountCapabilities — RFC 8621 §1.3.1
# ===========================================================================

type MailAccountCapabilities* {.ruleOff: "objects".} = object
  ## Per-account Mail capability schema (RFC 8621 §1.3.1).
  ## Threading: value type, immutable after construction, freely
  ## shareable across threads.
  rawMaxMailboxesPerEmail: Opt[UnsignedInt]
  rawMaxMailboxDepth: Opt[UnsignedInt]
  rawMaxSizeMailboxName: Opt[UnsignedInt]
  rawMaxSizeAttachmentsPerEmail: UnsignedInt
  rawEmailQuerySortOptions: HashSet[string]
  rawMayCreateTopLevelMailbox: bool

func maxMailboxesPerEmail*(m: MailAccountCapabilities): Opt[UnsignedInt] =
  ## Null when no per-account limit; ``>= 1`` when present per RFC 8621
  ## §1.3.1.
  m.rawMaxMailboxesPerEmail

func maxMailboxDepth*(m: MailAccountCapabilities): Opt[UnsignedInt] =
  ## Null when no per-account depth limit.
  m.rawMaxMailboxDepth

func maxSizeMailboxName*(m: MailAccountCapabilities): Opt[UnsignedInt] =
  ## Octets. ``>= 100`` when present per RFC 8621 §1.3.1. Cyrus 3.12.2
  ## omits the field; the Postel-receive serde surfaces absence as
  ## ``Opt.none`` rather than synthesising a default.
  m.rawMaxSizeMailboxName

func maxSizeAttachmentsPerEmail*(m: MailAccountCapabilities): UnsignedInt =
  ## Maximum total attachment size per email in octets.
  m.rawMaxSizeAttachmentsPerEmail

func emailQuerySortOptions*(m: MailAccountCapabilities): HashSet[string] =
  ## Supported sort properties for ``Email/query`` calls.
  m.rawEmailQuerySortOptions

func mayCreateTopLevelMailbox*(m: MailAccountCapabilities): bool =
  ## Whether the client may create top-level mailboxes.
  m.rawMayCreateTopLevelMailbox

func parseMailAccountCapabilities*(
    maxMailboxesPerEmail: Opt[UnsignedInt],
    maxMailboxDepth: Opt[UnsignedInt],
    maxSizeMailboxName: Opt[UnsignedInt],
    maxSizeAttachmentsPerEmail: UnsignedInt,
    emailQuerySortOptions: HashSet[string],
    mayCreateTopLevelMailbox: bool,
): Result[MailAccountCapabilities, ValidationError] =
  ## RFC 8621 §1.3.1 invariants enforced at construction:
  ## ``maxMailboxesPerEmail`` (when present) ``>= 1``;
  ## ``maxSizeMailboxName`` (when present) ``>= 100``.
  for v in maxMailboxesPerEmail:
    if v.toInt64 < 1:
      return err(
        validationError(
          "MailAccountCapabilities", "maxMailboxesPerEmail must be >= 1", $v.toInt64
        )
      )
  for v in maxSizeMailboxName:
    if v.toInt64 < 100:
      return err(
        validationError(
          "MailAccountCapabilities", "maxSizeMailboxName must be >= 100", $v.toInt64
        )
      )
  ok(
    MailAccountCapabilities(
      rawMaxMailboxesPerEmail: maxMailboxesPerEmail,
      rawMaxMailboxDepth: maxMailboxDepth,
      rawMaxSizeMailboxName: maxSizeMailboxName,
      rawMaxSizeAttachmentsPerEmail: maxSizeAttachmentsPerEmail,
      rawEmailQuerySortOptions: emailQuerySortOptions,
      rawMayCreateTopLevelMailbox: mayCreateTopLevelMailbox,
    )
  )

# ===========================================================================
# SubmissionAccountCapabilities — RFC 8621 §1.3.2
# ===========================================================================

type SubmissionAccountCapabilities* {.ruleOff: "objects".} = object
  ## Per-account Submission capability schema (RFC 8621 §1.3.2).
  ## Threading: value type, immutable after construction, freely
  ## shareable across threads.
  rawMaxDelayedSend: UnsignedInt
  rawSubmissionExtensions: SubmissionExtensionMap

func maxDelayedSend*(s: SubmissionAccountCapabilities): UnsignedInt =
  ## Maximum delay in seconds for delayed send. ``0`` means delayed send
  ## is not supported.
  s.rawMaxDelayedSend

func submissionExtensions*(s: SubmissionAccountCapabilities): SubmissionExtensionMap =
  ## Server-advertised RFC 5321 ESMTP extension keywords with their args.
  s.rawSubmissionExtensions

func parseSubmissionAccountCapabilities*(
    maxDelayedSend: UnsignedInt, submissionExtensions: SubmissionExtensionMap
): Result[SubmissionAccountCapabilities, ValidationError] =
  ## RFC 8621 §1.3.2 has no further structural invariants beyond those
  ## carried by the field types — ``UnsignedInt`` enforces non-negative
  ## bounds, ``SubmissionExtensionMap`` enforces keyword validity. The
  ## ``Result``-returning signature matches the uniform L1 smart-
  ## constructor contract.
  ok(
    SubmissionAccountCapabilities(
      rawMaxDelayedSend: maxDelayedSend, rawSubmissionExtensions: submissionExtensions
    )
  )

# ===========================================================================
# AccountCapabilityEntry — per-account capability declaration
# ===========================================================================

type AccountCapabilityEntry* {.ruleOff: "objects".} = object
  ## Per-account capability declaration (RFC 8620 §2, RFC 8621 §1.3).
  ## Threading: value type, immutable after construction, freely
  ## shareable across threads.
  rawUri: string
  case kind*: CapabilityKind
  of ckMail:
    rawMail: MailAccountCapabilities ## RFC 8621 §1.3.1
  of ckSubmission:
    rawSubmission: SubmissionAccountCapabilities ## RFC 8621 §1.3.2
  of ckVacationResponse:
    # RFC 8621 §1.3.3: presence-only (empty object), no payload.
    discard
  of ckCore:
    rawCoreData: JsonNode
      ## P19 exception (A22b): ckCore is server-only at account scope; Postel-tolerated
  of ckWebsocket:
    rawWebsocketData: JsonNode
      ## P19 exception (A22b): ckWebsocket is session-scope only; Postel-tolerated
  of ckMdn:
    rawMdnData: JsonNode ## P19 exception (A22b): RFC 9007 forward-compat
  of ckSmimeVerify:
    rawSmimeVerifyData: JsonNode
      ## P19 exception (A22b): no published RFC, forward-compat
  of ckBlob:
    rawBlobData: JsonNode ## P19 exception (A22b): no published RFC, forward-compat
  of ckQuota:
    rawQuotaData: JsonNode ## P19 exception (A22b): RFC 8909 forward-compat
  of ckContacts:
    rawContactsData: JsonNode ## P19 exception (A22b): no published RFC, forward-compat
  of ckCalendars:
    rawCalendarsData: JsonNode ## P19 exception (A22b): no published RFC, forward-compat
  of ckSieve:
    rawSieveData: JsonNode ## P19 exception (A22b): no published RFC, forward-compat
  of ckUnknown:
    rawUnknownData: JsonNode ## P19 exception (A22b): vendor URN forward-compat

func uri*(e: AccountCapabilityEntry): string =
  ## Round-trip-stable wire URI.
  e.rawUri

func asMailAccountCapabilities*(
    e: AccountCapabilityEntry
): Opt[MailAccountCapabilities] =
  ## Some only when kind == ckMail.
  case e.kind
  of ckMail:
    Opt.some(e.rawMail)
  of ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn, ckSmimeVerify,
      ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
    Opt.none(MailAccountCapabilities)

func asSubmissionAccountCapabilities*(
    e: AccountCapabilityEntry
): Opt[SubmissionAccountCapabilities] =
  ## Some only when kind == ckSubmission.
  case e.kind
  of ckSubmission:
    Opt.some(e.rawSubmission)
  of ckMail, ckVacationResponse, ckCore, ckWebsocket, ckMdn, ckSmimeVerify, ckBlob,
      ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
    Opt.none(SubmissionAccountCapabilities)

func asRawData*(e: AccountCapabilityEntry): Opt[JsonNode] =
  ## Some for every ``rawXxxData``-bearing arm; none for ckMail,
  ## ckSubmission, ckVacationResponse.
  case e.kind
  of ckMail, ckSubmission, ckVacationResponse:
    Opt.none(JsonNode)
  of ckCore:
    Opt.some(e.rawCoreData)
  of ckWebsocket:
    Opt.some(e.rawWebsocketData)
  of ckMdn:
    Opt.some(e.rawMdnData)
  of ckSmimeVerify:
    Opt.some(e.rawSmimeVerifyData)
  of ckBlob:
    Opt.some(e.rawBlobData)
  of ckQuota:
    Opt.some(e.rawQuotaData)
  of ckContacts:
    Opt.some(e.rawContactsData)
  of ckCalendars:
    Opt.some(e.rawCalendarsData)
  of ckSieve:
    Opt.some(e.rawSieveData)
  of ckUnknown:
    Opt.some(e.rawUnknownData)

func parseAccountCapabilityEntry*(
    uri: string,
    mail: Opt[MailAccountCapabilities],
    submission: Opt[SubmissionAccountCapabilities],
    rawData: Opt[JsonNode],
): Result[AccountCapabilityEntry, ValidationError] =
  ## URI dispatches to the arm. ckMail requires ``mail.isSome``;
  ## ckSubmission requires ``submission.isSome``; ckVacationResponse is
  ## presence-only and silently drops any provided payload (Postel-
  ## receive). ``rawData``-bearing arms substitute ``newJObject()`` when
  ## ``rawData.isNone``.
  case parseCapabilityKind(uri)
  of ckMail:
    let m = mail.valueOr:
      return err(
        validationError(
          "AccountCapabilityEntry", "ckMail requires MailAccountCapabilities", uri
        )
      )
    ok(AccountCapabilityEntry(kind: ckMail, rawUri: uri, rawMail: m))
  of ckSubmission:
    let s = submission.valueOr:
      return err(
        validationError(
          "AccountCapabilityEntry",
          "ckSubmission requires SubmissionAccountCapabilities", uri,
        )
      )
    ok(AccountCapabilityEntry(kind: ckSubmission, rawUri: uri, rawSubmission: s))
  of ckVacationResponse:
    ok(AccountCapabilityEntry(kind: ckVacationResponse, rawUri: uri))
  of ckCore:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckCore, rawUri: uri, rawCoreData: d))
  of ckWebsocket:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckWebsocket, rawUri: uri, rawWebsocketData: d))
  of ckMdn:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckMdn, rawUri: uri, rawMdnData: d))
  of ckSmimeVerify:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckSmimeVerify, rawUri: uri, rawSmimeVerifyData: d))
  of ckBlob:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckBlob, rawUri: uri, rawBlobData: d))
  of ckQuota:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckQuota, rawUri: uri, rawQuotaData: d))
  of ckContacts:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckContacts, rawUri: uri, rawContactsData: d))
  of ckCalendars:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckCalendars, rawUri: uri, rawCalendarsData: d))
  of ckSieve:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckSieve, rawUri: uri, rawSieveData: d))
  of ckUnknown:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckUnknown, rawUri: uri, rawUnknownData: d))

func `==`*(a, b: AccountCapabilityEntry): bool =
  ## Arm-dispatched structural equality — Nim's auto-derived ``==`` uses a
  ## parallel ``fields`` iterator that rejects case objects.
  if a.kind != b.kind:
    return false
  if a.rawUri != b.rawUri:
    return false
  case a.kind
  of ckMail:
    case b.kind
    of ckMail:
      a.rawMail == b.rawMail
    of ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn, ckSmimeVerify,
        ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckSubmission:
    case b.kind
    of ckSubmission:
      a.rawSubmission == b.rawSubmission
    of ckMail, ckVacationResponse, ckCore, ckWebsocket, ckMdn, ckSmimeVerify, ckBlob,
        ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckVacationResponse:
    true
  of ckCore:
    case b.kind
    of ckCore:
      $a.rawCoreData == $b.rawCoreData
    of ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
        ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckWebsocket:
    case b.kind
    of ckWebsocket:
      $a.rawWebsocketData == $b.rawWebsocketData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckMdn, ckSmimeVerify, ckBlob,
        ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckMdn:
    case b.kind
    of ckMdn:
      $a.rawMdnData == $b.rawMdnData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckSmimeVerify,
        ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckSmimeVerify:
    case b.kind
    of ckSmimeVerify:
      $a.rawSmimeVerifyData == $b.rawSmimeVerifyData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn, ckBlob,
        ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckBlob:
    case b.kind
    of ckBlob:
      $a.rawBlobData == $b.rawBlobData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckQuota:
    case b.kind
    of ckQuota:
      $a.rawQuotaData == $b.rawQuotaData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckContacts:
    case b.kind
    of ckContacts:
      $a.rawContactsData == $b.rawContactsData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckCalendars, ckSieve, ckUnknown:
      false
  of ckCalendars:
    case b.kind
    of ckCalendars:
      $a.rawCalendarsData == $b.rawCalendarsData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckSieve, ckUnknown:
      false
  of ckSieve:
    case b.kind
    of ckSieve:
      $a.rawSieveData == $b.rawSieveData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars, ckUnknown:
      false
  of ckUnknown:
    case b.kind
    of ckUnknown:
      $a.rawUnknownData == $b.rawUnknownData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve:
      false

func `$`*(e: AccountCapabilityEntry): string =
  ## Diagnostic representation — kind tag plus the URI.
  "AccountCapabilityEntry(uri=" & e.rawUri & " kind=" & $e.kind & ")"

func hash*(e: AccountCapabilityEntry): Hash =
  ## Arm-dispatched hash. ``JsonNode`` has no stdlib ``hash``; the
  ## render-then-hash path preserves structural equivalence at the cost
  ## of one serialisation per hash. Hash sites are diagnostic, not hot.
  var h: Hash = 0
  h = h !& hash(e.rawUri)
  h = h !& hash(e.kind)
  case e.kind
  of ckMail:
    h = h !& hash(e.rawMail.maxSizeAttachmentsPerEmail.toInt64)
  of ckSubmission:
    h = h !& hash(e.rawSubmission.maxDelayedSend.toInt64)
  of ckVacationResponse:
    discard
  of ckCore:
    h = h !& hash($e.rawCoreData)
  of ckWebsocket:
    h = h !& hash($e.rawWebsocketData)
  of ckMdn:
    h = h !& hash($e.rawMdnData)
  of ckSmimeVerify:
    h = h !& hash($e.rawSmimeVerifyData)
  of ckBlob:
    h = h !& hash($e.rawBlobData)
  of ckQuota:
    h = h !& hash($e.rawQuotaData)
  of ckContacts:
    h = h !& hash($e.rawContactsData)
  of ckCalendars:
    h = h !& hash($e.rawCalendarsData)
  of ckSieve:
    h = h !& hash($e.rawSieveData)
  of ckUnknown:
    h = h !& hash($e.rawUnknownData)
  !$h
