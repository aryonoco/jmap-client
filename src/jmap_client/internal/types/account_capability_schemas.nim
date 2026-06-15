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
  ## Tier-C: numeric bounds (>=1 / >=100) are enforced by
  ## parseMailAccountCapabilities; raw construction is out-of-contract.
  ## Threading: value type, immutable after construction, freely
  ## shareable across threads.
  maxMailboxesPerEmail*: Opt[UnsignedInt]
    ## null when no per-account limit; ``>= 1`` when present (RFC 8621 §1.3.1)
  maxMailboxDepth*: Opt[UnsignedInt] ## null when no per-account depth limit
  maxSizeMailboxName*: Opt[UnsignedInt]
    ## octets; ``>= 100`` when present (RFC 8621 §1.3.1). Cyrus 3.12.2 omits
    ## the field; the Postel-receive serde surfaces absence as ``Opt.none``
    ## rather than synthesising a default.
  maxSizeAttachmentsPerEmail*: UnsignedInt
    ## maximum total attachment size per email in octets
  emailQuerySortOptions*: HashSet[string]
    ## supported sort properties for ``Email/query`` calls
  mayCreateTopLevelMailbox*: bool ## whether the client may create top-level mailboxes

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
      maxMailboxesPerEmail: maxMailboxesPerEmail,
      maxMailboxDepth: maxMailboxDepth,
      maxSizeMailboxName: maxSizeMailboxName,
      maxSizeAttachmentsPerEmail: maxSizeAttachmentsPerEmail,
      emailQuerySortOptions: emailQuerySortOptions,
      mayCreateTopLevelMailbox: mayCreateTopLevelMailbox,
    )
  )

# ===========================================================================
# SubmissionAccountCapabilities — RFC 8621 §1.3.2
# ===========================================================================

type SubmissionAccountCapabilities* {.ruleOff: "objects".} = object
  ## Per-account Submission capability schema (RFC 8621 §1.3.2).
  ## Both fields are public read fields carrying already-validated types,
  ## so direct construction cannot forge an illegal value.
  ## ``parseSubmissionAccountCapabilities`` remains the convenience
  ## constructor.
  ## Threading: value type, immutable after construction, freely
  ## shareable across threads.
  maxDelayedSend*: UnsignedInt
    ## maximum delay in seconds for delayed send; ``0`` means unsupported
  submissionExtensions*: SubmissionExtensionMap
    ## server-advertised RFC 5321 ESMTP extension keywords with their args

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
      maxDelayedSend: maxDelayedSend, submissionExtensions: submissionExtensions
    )
  )

# ===========================================================================
# AccountCapabilityEntry — per-account capability declaration
# ===========================================================================

type AccountCapabilityEntry* {.ruleOff: "objects".} = object
  ## Per-account capability declaration (RFC 8620 §2, RFC 8621 §1.3).
  ## kind↔uri consistency is parseAccountCapabilityEntry-guaranteed (Tier-C).
  ## Threading: value type, immutable after construction, freely
  ## shareable across threads.
  uri*: string
  case kind*: CapabilityKind
  of ckMail:
    mail*: MailAccountCapabilities ## RFC 8621 §1.3.1
  of ckSubmission:
    submission*: SubmissionAccountCapabilities ## RFC 8621 §1.3.2
  of ckVacationResponse:
    # RFC 8621 §1.3.3: presence-only (empty object), no payload.
    discard
  of ckCore:
    coreData*: JsonNode
      ## P19 exception (A22b): ckCore is server-only at account scope; Postel-tolerated
  of ckWebsocket:
    websocketData*: JsonNode
      ## P19 exception (A22b): ckWebsocket is session-scope only; Postel-tolerated
  of ckMdn:
    mdnData*: JsonNode ## P19 exception (A22b): RFC 9007 forward-compat
  of ckSmimeVerify:
    smimeVerifyData*: JsonNode ## P19 exception (A22b): no published RFC, forward-compat
  of ckBlob:
    blobData*: JsonNode ## P19 exception (A22b): no published RFC, forward-compat
  of ckQuota:
    quotaData*: JsonNode ## P19 exception (A22b): RFC 8909 forward-compat
  of ckContacts:
    contactsData*: JsonNode ## P19 exception (A22b): no published RFC, forward-compat
  of ckCalendars:
    calendarsData*: JsonNode ## P19 exception (A22b): no published RFC, forward-compat
  of ckSieve:
    sieveData*: JsonNode ## P19 exception (A22b): no published RFC, forward-compat
  of ckUnknown:
    unknownData*: JsonNode ## P19 exception (A22b): vendor URN forward-compat

func asMailAccountCapabilities*(
    e: AccountCapabilityEntry
): Opt[MailAccountCapabilities] =
  ## Some only when kind == ckMail.
  case e.kind
  of ckMail:
    Opt.some(e.mail)
  of ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn, ckSmimeVerify,
      ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
    Opt.none(MailAccountCapabilities)

func asSubmissionAccountCapabilities*(
    e: AccountCapabilityEntry
): Opt[SubmissionAccountCapabilities] =
  ## Some only when kind == ckSubmission.
  case e.kind
  of ckSubmission:
    Opt.some(e.submission)
  of ckMail, ckVacationResponse, ckCore, ckWebsocket, ckMdn, ckSmimeVerify, ckBlob,
      ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
    Opt.none(SubmissionAccountCapabilities)

func asRawData*(e: AccountCapabilityEntry): Opt[JsonNode] =
  ## Some for every ``xxxData``-bearing arm; none for ckMail,
  ## ckSubmission, ckVacationResponse.
  case e.kind
  of ckMail, ckSubmission, ckVacationResponse:
    Opt.none(JsonNode)
  of ckCore:
    Opt.some(e.coreData)
  of ckWebsocket:
    Opt.some(e.websocketData)
  of ckMdn:
    Opt.some(e.mdnData)
  of ckSmimeVerify:
    Opt.some(e.smimeVerifyData)
  of ckBlob:
    Opt.some(e.blobData)
  of ckQuota:
    Opt.some(e.quotaData)
  of ckContacts:
    Opt.some(e.contactsData)
  of ckCalendars:
    Opt.some(e.calendarsData)
  of ckSieve:
    Opt.some(e.sieveData)
  of ckUnknown:
    Opt.some(e.unknownData)

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
    ok(AccountCapabilityEntry(kind: ckMail, uri: uri, mail: m))
  of ckSubmission:
    let s = submission.valueOr:
      return err(
        validationError(
          "AccountCapabilityEntry",
          "ckSubmission requires SubmissionAccountCapabilities", uri,
        )
      )
    ok(AccountCapabilityEntry(kind: ckSubmission, uri: uri, submission: s))
  of ckVacationResponse:
    ok(AccountCapabilityEntry(kind: ckVacationResponse, uri: uri))
  of ckCore:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckCore, uri: uri, coreData: d))
  of ckWebsocket:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckWebsocket, uri: uri, websocketData: d))
  of ckMdn:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckMdn, uri: uri, mdnData: d))
  of ckSmimeVerify:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckSmimeVerify, uri: uri, smimeVerifyData: d))
  of ckBlob:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckBlob, uri: uri, blobData: d))
  of ckQuota:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckQuota, uri: uri, quotaData: d))
  of ckContacts:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckContacts, uri: uri, contactsData: d))
  of ckCalendars:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckCalendars, uri: uri, calendarsData: d))
  of ckSieve:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckSieve, uri: uri, sieveData: d))
  of ckUnknown:
    let d = rawData.valueOr:
      newJObject()
    ok(AccountCapabilityEntry(kind: ckUnknown, uri: uri, unknownData: d))

func `==`*(a, b: AccountCapabilityEntry): bool =
  ## Arm-dispatched structural equality — Nim's auto-derived ``==`` uses a
  ## parallel ``fields`` iterator that rejects case objects.
  if a.kind != b.kind:
    return false
  if a.uri != b.uri:
    return false
  case a.kind
  of ckMail:
    case b.kind
    of ckMail:
      a.mail == b.mail
    of ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn, ckSmimeVerify,
        ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckSubmission:
    case b.kind
    of ckSubmission:
      a.submission == b.submission
    of ckMail, ckVacationResponse, ckCore, ckWebsocket, ckMdn, ckSmimeVerify, ckBlob,
        ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckVacationResponse:
    true
  of ckCore:
    case b.kind
    of ckCore:
      $a.coreData == $b.coreData
    of ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
        ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckWebsocket:
    case b.kind
    of ckWebsocket:
      $a.websocketData == $b.websocketData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckMdn, ckSmimeVerify, ckBlob,
        ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckMdn:
    case b.kind
    of ckMdn:
      $a.mdnData == $b.mdnData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckSmimeVerify,
        ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckSmimeVerify:
    case b.kind
    of ckSmimeVerify:
      $a.smimeVerifyData == $b.smimeVerifyData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn, ckBlob,
        ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckBlob:
    case b.kind
    of ckBlob:
      $a.blobData == $b.blobData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckQuota:
    case b.kind
    of ckQuota:
      $a.quotaData == $b.quotaData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckContacts:
    case b.kind
    of ckContacts:
      $a.contactsData == $b.contactsData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckCalendars, ckSieve, ckUnknown:
      false
  of ckCalendars:
    case b.kind
    of ckCalendars:
      $a.calendarsData == $b.calendarsData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckSieve, ckUnknown:
      false
  of ckSieve:
    case b.kind
    of ckSieve:
      $a.sieveData == $b.sieveData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars, ckUnknown:
      false
  of ckUnknown:
    case b.kind
    of ckUnknown:
      $a.unknownData == $b.unknownData
    of ckMail, ckSubmission, ckVacationResponse, ckCore, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve:
      false

func `$`*(e: AccountCapabilityEntry): string =
  ## Diagnostic representation — kind tag plus the URI.
  "AccountCapabilityEntry(uri=" & e.uri & " kind=" & $e.kind & ")"

func hash*(e: AccountCapabilityEntry): Hash =
  ## Arm-dispatched hash. ``JsonNode`` has no stdlib ``hash``; the
  ## render-then-hash path preserves structural equivalence at the cost
  ## of one serialisation per hash. Hash sites are diagnostic, not hot.
  var h: Hash = 0
  h = h !& hash(e.uri)
  h = h !& hash(e.kind)
  case e.kind
  of ckMail:
    h = h !& hash(e.mail.maxSizeAttachmentsPerEmail.toInt64)
  of ckSubmission:
    h = h !& hash(e.submission.maxDelayedSend.toInt64)
  of ckVacationResponse:
    discard
  of ckCore:
    h = h !& hash($e.coreData)
  of ckWebsocket:
    h = h !& hash($e.websocketData)
  of ckMdn:
    h = h !& hash($e.mdnData)
  of ckSmimeVerify:
    h = h !& hash($e.smimeVerifyData)
  of ckBlob:
    h = h !& hash($e.blobData)
  of ckQuota:
    h = h !& hash($e.quotaData)
  of ckContacts:
    h = h !& hash($e.contactsData)
  of ckCalendars:
    h = h !& hash($e.calendarsData)
  of ckSieve:
    h = h !& hash($e.sieveData)
  of ckUnknown:
    h = h !& hash($e.unknownData)
  !$h
