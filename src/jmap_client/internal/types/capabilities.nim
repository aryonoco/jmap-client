# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP capability discovery types. Maps IANA-registered capability URIs to
## typed enums with lossless round-trip for vendor extensions.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/strutils
import std/sets
from std/json import JsonNode, newJObject, `$`

import results

import ./validation
import ./primitives
import ./collation
export collation

type CapabilityKind* = enum
  ## JMAP capability identifiers from the IANA registry.
  ## CRITICAL: must NOT be used as a Table key — multiple vendor extensions
  ## map to ckUnknown, causing collisions. Use raw URI strings for keying.
  ckMail = "urn:ietf:params:jmap:mail"
  ckCore = "urn:ietf:params:jmap:core"
  ckSubmission = "urn:ietf:params:jmap:submission"
  ckVacationResponse = "urn:ietf:params:jmap:vacationresponse"
  ckWebsocket = "urn:ietf:params:jmap:websocket"
  ckMdn = "urn:ietf:params:jmap:mdn"
  ckSmimeVerify = "urn:ietf:params:jmap:smimeverify"
  ckBlob = "urn:ietf:params:jmap:blob"
  ckQuota = "urn:ietf:params:jmap:quota"
  ckContacts = "urn:ietf:params:jmap:contacts"
  ckCalendars = "urn:ietf:params:jmap:calendars"
  ckSieve = "urn:ietf:params:jmap:sieve"
  ckUnknown

func parseCapabilityKind*(uri: string): CapabilityKind =
  ## Maps a capability URI string to an enum value.
  ## Total function: always succeeds. Unknown URIs map to ckUnknown.
  ## Uses strutils.parseEnum which matches against the string backing values.
  return strutils.parseEnum[CapabilityKind](uri, ckUnknown)

func capabilityUri*(kind: CapabilityKind): Opt[string] =
  ## Returns the IANA-registered URI for a known capability.
  ## Returns none for ckUnknown — callers must use rawUri from ServerCapability.
  ## Uses ``$`` on the string-backed enum, which returns the backing string.
  if kind == ckUnknown:
    return Opt.none(string)
  return Opt.some($kind)

type CoreCapabilities* {.ruleOff: "objects".} = object
  ## Server-advertised core limits and supported collations (RFC 8620 §2).
  ## Threading: value type, immutable after construction, freely
  ## shareable across threads.
  rawMaxSizeUpload: UnsignedInt
  rawMaxConcurrentUpload: UnsignedInt
  rawMaxSizeRequest: UnsignedInt
  rawMaxConcurrentRequests: UnsignedInt
  rawMaxCallsInRequest: UnsignedInt
  rawMaxObjectsInGet: UnsignedInt
  rawMaxObjectsInSet: UnsignedInt
  rawCollationAlgorithms: HashSet[CollationAlgorithm]

func maxSizeUpload*(c: CoreCapabilities): UnsignedInt =
  ## Max file size in octets for a single upload.
  c.rawMaxSizeUpload

func maxConcurrentUpload*(c: CoreCapabilities): UnsignedInt =
  ## Max concurrent requests to the upload endpoint.
  c.rawMaxConcurrentUpload

func maxSizeRequest*(c: CoreCapabilities): UnsignedInt =
  ## Max request size in octets for the API endpoint.
  c.rawMaxSizeRequest

func maxConcurrentRequests*(c: CoreCapabilities): UnsignedInt =
  ## Max concurrent requests to the API endpoint.
  c.rawMaxConcurrentRequests

func maxCallsInRequest*(c: CoreCapabilities): UnsignedInt =
  ## Max method calls per single API request.
  c.rawMaxCallsInRequest

func maxObjectsInGet*(c: CoreCapabilities): UnsignedInt =
  ## Max objects per single /get call.
  c.rawMaxObjectsInGet

func maxObjectsInSet*(c: CoreCapabilities): UnsignedInt =
  ## Max combined create/update/destroy per /set call.
  c.rawMaxObjectsInSet

func collationAlgorithms*(c: CoreCapabilities): lent HashSet[CollationAlgorithm] =
  ## RFC 4790 collation algorithm identifiers advertised by the server.
  ## Borrowed view (`lent`, P12) — read-only, no per-call deep copy of the
  ## sealed container.
  c.rawCollationAlgorithms

func parseCoreCapabilities*(
    maxSizeUpload: UnsignedInt,
    maxConcurrentUpload: UnsignedInt,
    maxSizeRequest: UnsignedInt,
    maxConcurrentRequests: UnsignedInt,
    maxCallsInRequest: UnsignedInt,
    maxObjectsInGet: UnsignedInt,
    maxObjectsInSet: UnsignedInt,
    collationAlgorithms: HashSet[CollationAlgorithm],
): Result[CoreCapabilities, ValidationError] =
  ## Inputs are already typed (``UnsignedInt`` is a validated distinct).
  ## Returns ``ok`` unconditionally; the ``Result`` shape matches the
  ## L1 smart-constructor contract uniformly so callers can compose with
  ## ``?`` / ``valueOr:``.
  ok(
    CoreCapabilities(
      rawMaxSizeUpload: maxSizeUpload,
      rawMaxConcurrentUpload: maxConcurrentUpload,
      rawMaxSizeRequest: maxSizeRequest,
      rawMaxConcurrentRequests: maxConcurrentRequests,
      rawMaxCallsInRequest: maxCallsInRequest,
      rawMaxObjectsInGet: maxObjectsInGet,
      rawMaxObjectsInSet: maxObjectsInSet,
      rawCollationAlgorithms: collationAlgorithms,
    )
  )

type ServerCapability* {.ruleOff: "objects".} = object
  ## Server-level capability declaration (RFC 8620 §2, RFC 8621 §1.3).
  ## Threading: value type, immutable after construction, freely
  ## shareable across threads.
  rawUri: string
  case kind*: CapabilityKind
  of ckCore:
    rawCore: CoreCapabilities
  of ckMail:
    discard
  of ckSubmission:
    discard
  of ckVacationResponse:
    discard
  of ckWebsocket:
    rawWebsocketData: JsonNode ## P19 exception (A22b): RFC 8887 forward-compat
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

func uri*(c: ServerCapability): string =
  ## Round-trip-stable wire URI.
  c.rawUri

func asCoreCapabilities*(c: ServerCapability): Opt[CoreCapabilities] =
  ## Some only when kind == ckCore; none for every other arm.
  case c.kind
  of ckCore:
    Opt.some(c.rawCore)
  of ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
      ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
    Opt.none(CoreCapabilities)

func asRawData*(c: ServerCapability): Opt[JsonNode] =
  ## Some for every ``rawXxxData``-bearing arm; none for ckCore and the
  ## three discard arms (ckMail / ckSubmission / ckVacationResponse —
  ## RFC 8621 §1.3 declares them empty at session scope).
  case c.kind
  of ckCore, ckMail, ckSubmission, ckVacationResponse:
    Opt.none(JsonNode)
  of ckWebsocket:
    Opt.some(c.rawWebsocketData)
  of ckMdn:
    Opt.some(c.rawMdnData)
  of ckSmimeVerify:
    Opt.some(c.rawSmimeVerifyData)
  of ckBlob:
    Opt.some(c.rawBlobData)
  of ckQuota:
    Opt.some(c.rawQuotaData)
  of ckContacts:
    Opt.some(c.rawContactsData)
  of ckCalendars:
    Opt.some(c.rawCalendarsData)
  of ckSieve:
    Opt.some(c.rawSieveData)
  of ckUnknown:
    Opt.some(c.rawUnknownData)

func parseServerCapability*(
    uri: string, core: Opt[CoreCapabilities], rawData: Opt[JsonNode]
): Result[ServerCapability, ValidationError] =
  ## URI dispatches to the arm. ckCore requires ``core.isSome`` (strict).
  ## Discard arms (ckMail/ckSubmission/ckVacationResponse) silently drop
  ## any provided payload (Postel-receive: RFC 8621 §1.3 declares them
  ## empty at session scope). ``rawData``-bearing arms substitute
  ## ``newJObject()`` when ``rawData.isNone``.
  case parseCapabilityKind(uri)
  of ckCore:
    let coreVal = core.valueOr:
      return err(
        validationError("ServerCapability", "ckCore requires CoreCapabilities", uri)
      )
    ok(ServerCapability(kind: ckCore, rawUri: uri, rawCore: coreVal))
  of ckMail:
    ok(ServerCapability(kind: ckMail, rawUri: uri))
  of ckSubmission:
    ok(ServerCapability(kind: ckSubmission, rawUri: uri))
  of ckVacationResponse:
    ok(ServerCapability(kind: ckVacationResponse, rawUri: uri))
  of ckWebsocket:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckWebsocket, rawUri: uri, rawWebsocketData: d))
  of ckMdn:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckMdn, rawUri: uri, rawMdnData: d))
  of ckSmimeVerify:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckSmimeVerify, rawUri: uri, rawSmimeVerifyData: d))
  of ckBlob:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckBlob, rawUri: uri, rawBlobData: d))
  of ckQuota:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckQuota, rawUri: uri, rawQuotaData: d))
  of ckContacts:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckContacts, rawUri: uri, rawContactsData: d))
  of ckCalendars:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckCalendars, rawUri: uri, rawCalendarsData: d))
  of ckSieve:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckSieve, rawUri: uri, rawSieveData: d))
  of ckUnknown:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckUnknown, rawUri: uri, rawUnknownData: d))

func `==`*(a, b: ServerCapability): bool =
  ## Arm-dispatched structural equality — Nim's auto-derived ``==`` uses
  ## a parallel ``fields`` iterator that rejects case objects.
  if a.kind != b.kind:
    return false
  if a.rawUri != b.rawUri:
    return false
  case a.kind
  of ckCore:
    case b.kind
    of ckCore:
      a.rawCore == b.rawCore
    of ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
        ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckMail, ckSubmission, ckVacationResponse:
    true
  of ckWebsocket:
    case b.kind
    of ckWebsocket:
      $a.rawWebsocketData == $b.rawWebsocketData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckMdn, ckSmimeVerify, ckBlob,
        ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckMdn:
    case b.kind
    of ckMdn:
      $a.rawMdnData == $b.rawMdnData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckSmimeVerify,
        ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckSmimeVerify:
    case b.kind
    of ckSmimeVerify:
      $a.rawSmimeVerifyData == $b.rawSmimeVerifyData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckBlob,
        ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckBlob:
    case b.kind
    of ckBlob:
      $a.rawBlobData == $b.rawBlobData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckQuota:
    case b.kind
    of ckQuota:
      $a.rawQuotaData == $b.rawQuotaData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckContacts:
    case b.kind
    of ckContacts:
      $a.rawContactsData == $b.rawContactsData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckCalendars, ckSieve, ckUnknown:
      false
  of ckCalendars:
    case b.kind
    of ckCalendars:
      $a.rawCalendarsData == $b.rawCalendarsData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckSieve, ckUnknown:
      false
  of ckSieve:
    case b.kind
    of ckSieve:
      $a.rawSieveData == $b.rawSieveData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars, ckUnknown:
      false
  of ckUnknown:
    case b.kind
    of ckUnknown:
      $a.rawUnknownData == $b.rawUnknownData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve:
      false

func `$`*(c: ServerCapability): string =
  ## Diagnostic representation — kind tag plus the URI.
  "ServerCapability(uri=" & c.rawUri & " kind=" & $c.kind & ")"

func hash*(c: ServerCapability): Hash =
  ## Arm-dispatched hash. ``JsonNode`` has no stdlib ``hash``; rendering
  ## via ``$`` then hashing preserves structural equivalence at the cost
  ## of one serialisation per hash. Hash sites are diagnostic, not hot.
  var h: Hash = 0
  h = h !& hash(c.rawUri)
  h = h !& hash(c.kind)
  case c.kind
  of ckCore:
    h = h !& hash(c.rawCore.maxSizeUpload.toInt64)
  of ckMail, ckSubmission, ckVacationResponse:
    discard
  of ckWebsocket:
    h = h !& hash($c.rawWebsocketData)
  of ckMdn:
    h = h !& hash($c.rawMdnData)
  of ckSmimeVerify:
    h = h !& hash($c.rawSmimeVerifyData)
  of ckBlob:
    h = h !& hash($c.rawBlobData)
  of ckQuota:
    h = h !& hash($c.rawQuotaData)
  of ckContacts:
    h = h !& hash($c.rawContactsData)
  of ckCalendars:
    h = h !& hash($c.rawCalendarsData)
  of ckSieve:
    h = h !& hash($c.rawSieveData)
  of ckUnknown:
    h = h !& hash($c.rawUnknownData)
  !$h

func hasCollation*(c: CoreCapabilities, algorithm: CollationAlgorithm): bool =
  ## Checks whether the server supports a given RFC 4790 collation algorithm.
  return algorithm in c.collationAlgorithms()

type CapabilityUri* {.ruleOff: "objects".} = object
  ## RFC 8620 §2 capability URI carrier. Used internally by every typed
  ## ``add<Entity><Method>`` builder to tag the request's ``using``
  ## field, and publicly as the ``capability`` parameter on
  ## ``addCapabilityInvocation`` for vendor URN escapes. Sealed
  ## Pattern-A object — ``rawValue`` is module-private. External
  ## consumers must go through ``parseCapabilityUri``.
  rawValue: string

defineSealedStringOps(CapabilityUri)

func parseCapabilityUri*(raw: string): Result[CapabilityUri, ValidationError] =
  ## Validates the URN envelope per RFC 8141: lenient-token shape (1..255
  ## octets, no control characters), ``urn:`` prefix, and a non-empty NID
  ## segment after the first colon. Vendor URNs (``urn:com:vendor:*``,
  ## ``urn:io:vendor:*``) and IETF URNs (``urn:ietf:params:jmap:*``) are
  ## both accepted. The convention "IETF capabilities go through the typed
  ## ``add<Entity><Method>`` family" is enforced by docstring + H11 lint,
  ## not by construction-time rejection.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "CapabilityUri", raw))
  if not raw.startsWith("urn:"):
    return err(validationError("CapabilityUri", "must be a URN", raw))
  let colon2 = raw.find(':', start = 4)
  if colon2 < 5:
    return err(validationError("CapabilityUri", "malformed urn: missing NID", raw))
  ok(CapabilityUri(rawValue: raw))
