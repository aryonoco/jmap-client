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
  ## Returns none for ckUnknown — callers must use uri from ServerCapability.
  ## Uses ``$`` on the string-backed enum, which returns the backing string.
  if kind == ckUnknown:
    return Opt.none(string)
  return Opt.some($kind)

type CoreCapabilities* {.ruleOff: "objects".} = object
  ## Server-advertised core limits and supported collations (RFC 8620 §2).
  ## All fields are public read fields: the numeric limits are already
  ## validated ``UnsignedInt`` distincts, so direct construction cannot
  ## forge an illegal value. ``parseCoreCapabilities`` remains the
  ## convenience constructor.
  ## Threading: value type, immutable after construction, freely
  ## shareable across threads.
  maxSizeUpload*: UnsignedInt ## max file size in octets for a single upload
  maxConcurrentUpload*: UnsignedInt ## max concurrent requests to upload endpoint
  maxSizeRequest*: UnsignedInt ## max request size in octets for the API endpoint
  maxConcurrentRequests*: UnsignedInt ## max concurrent requests to API endpoint
  maxCallsInRequest*: UnsignedInt ## max method calls per single API request
  maxObjectsInGet*: UnsignedInt ## max objects per single /get call
  maxObjectsInSet*: UnsignedInt ## max create/update/destroy per /set call
  collationAlgorithms*: HashSet[CollationAlgorithm]
    ## RFC 4790 collation algorithm identifiers advertised by the server

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
      maxSizeUpload: maxSizeUpload,
      maxConcurrentUpload: maxConcurrentUpload,
      maxSizeRequest: maxSizeRequest,
      maxConcurrentRequests: maxConcurrentRequests,
      maxCallsInRequest: maxCallsInRequest,
      maxObjectsInGet: maxObjectsInGet,
      maxObjectsInSet: maxObjectsInSet,
      collationAlgorithms: collationAlgorithms,
    )
  )

type ServerCapability* {.ruleOff: "objects".} = object
  ## Server-level capability declaration (RFC 8620 §2, RFC 8621 §1.3).
  ## kind↔uri consistency is parseServerCapability-guaranteed (Tier-C).
  ## Threading: value type, immutable after construction, freely
  ## shareable across threads.
  uri*: string
  case kind*: CapabilityKind
  of ckCore:
    core*: CoreCapabilities
  of ckMail:
    discard
  of ckSubmission:
    discard
  of ckVacationResponse:
    discard
  of ckWebsocket:
    websocketData*: JsonNode ## P19 exception (A22b): RFC 8887 forward-compat
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

func asCoreCapabilities*(c: ServerCapability): Opt[CoreCapabilities] =
  ## Some only when kind == ckCore; none for every other arm.
  case c.kind
  of ckCore:
    Opt.some(c.core)
  of ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
      ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
    Opt.none(CoreCapabilities)

func asRawData*(c: ServerCapability): Opt[JsonNode] =
  ## Some for every ``xxxData``-bearing arm; none for ckCore and the
  ## three discard arms (ckMail / ckSubmission / ckVacationResponse —
  ## RFC 8621 §1.3 declares them empty at session scope).
  case c.kind
  of ckCore, ckMail, ckSubmission, ckVacationResponse:
    Opt.none(JsonNode)
  of ckWebsocket:
    Opt.some(c.websocketData)
  of ckMdn:
    Opt.some(c.mdnData)
  of ckSmimeVerify:
    Opt.some(c.smimeVerifyData)
  of ckBlob:
    Opt.some(c.blobData)
  of ckQuota:
    Opt.some(c.quotaData)
  of ckContacts:
    Opt.some(c.contactsData)
  of ckCalendars:
    Opt.some(c.calendarsData)
  of ckSieve:
    Opt.some(c.sieveData)
  of ckUnknown:
    Opt.some(c.unknownData)

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
    ok(ServerCapability(kind: ckCore, uri: uri, core: coreVal))
  of ckMail:
    ok(ServerCapability(kind: ckMail, uri: uri))
  of ckSubmission:
    ok(ServerCapability(kind: ckSubmission, uri: uri))
  of ckVacationResponse:
    ok(ServerCapability(kind: ckVacationResponse, uri: uri))
  of ckWebsocket:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckWebsocket, uri: uri, websocketData: d))
  of ckMdn:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckMdn, uri: uri, mdnData: d))
  of ckSmimeVerify:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckSmimeVerify, uri: uri, smimeVerifyData: d))
  of ckBlob:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckBlob, uri: uri, blobData: d))
  of ckQuota:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckQuota, uri: uri, quotaData: d))
  of ckContacts:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckContacts, uri: uri, contactsData: d))
  of ckCalendars:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckCalendars, uri: uri, calendarsData: d))
  of ckSieve:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckSieve, uri: uri, sieveData: d))
  of ckUnknown:
    let d = rawData.valueOr:
      newJObject()
    ok(ServerCapability(kind: ckUnknown, uri: uri, unknownData: d))

func `==`*(a, b: ServerCapability): bool =
  ## Arm-dispatched structural equality — Nim's auto-derived ``==`` uses
  ## a parallel ``fields`` iterator that rejects case objects.
  if a.kind != b.kind:
    return false
  if a.uri != b.uri:
    return false
  case a.kind
  of ckCore:
    case b.kind
    of ckCore:
      a.core == b.core
    of ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
        ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckMail, ckSubmission, ckVacationResponse:
    true
  of ckWebsocket:
    case b.kind
    of ckWebsocket:
      $a.websocketData == $b.websocketData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckMdn, ckSmimeVerify, ckBlob,
        ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckMdn:
    case b.kind
    of ckMdn:
      $a.mdnData == $b.mdnData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckSmimeVerify,
        ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckSmimeVerify:
    case b.kind
    of ckSmimeVerify:
      $a.smimeVerifyData == $b.smimeVerifyData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckBlob,
        ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckBlob:
    case b.kind
    of ckBlob:
      $a.blobData == $b.blobData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckQuota, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckQuota:
    case b.kind
    of ckQuota:
      $a.quotaData == $b.quotaData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckContacts, ckCalendars, ckSieve, ckUnknown:
      false
  of ckContacts:
    case b.kind
    of ckContacts:
      $a.contactsData == $b.contactsData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckCalendars, ckSieve, ckUnknown:
      false
  of ckCalendars:
    case b.kind
    of ckCalendars:
      $a.calendarsData == $b.calendarsData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckSieve, ckUnknown:
      false
  of ckSieve:
    case b.kind
    of ckSieve:
      $a.sieveData == $b.sieveData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars, ckUnknown:
      false
  of ckUnknown:
    case b.kind
    of ckUnknown:
      $a.unknownData == $b.unknownData
    of ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn,
        ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve:
      false

func `$`*(c: ServerCapability): string =
  ## Diagnostic representation — kind tag plus the URI.
  "ServerCapability(uri=" & c.uri & " kind=" & $c.kind & ")"

func hash*(c: ServerCapability): Hash =
  ## Arm-dispatched hash. ``JsonNode`` has no stdlib ``hash``; rendering
  ## via ``$`` then hashing preserves structural equivalence at the cost
  ## of one serialisation per hash. Hash sites are diagnostic, not hot.
  var h: Hash = 0
  h = h !& hash(c.uri)
  h = h !& hash(c.kind)
  case c.kind
  of ckCore:
    h = h !& hash(c.core.maxSizeUpload.toInt64)
  of ckMail, ckSubmission, ckVacationResponse:
    discard
  of ckWebsocket:
    h = h !& hash($c.websocketData)
  of ckMdn:
    h = h !& hash($c.mdnData)
  of ckSmimeVerify:
    h = h !& hash($c.smimeVerifyData)
  of ckBlob:
    h = h !& hash($c.blobData)
  of ckQuota:
    h = h !& hash($c.quotaData)
  of ckContacts:
    h = h !& hash($c.contactsData)
  of ckCalendars:
    h = h !& hash($c.calendarsData)
  of ckSieve:
    h = h !& hash($c.sieveData)
  of ckUnknown:
    h = h !& hash($c.unknownData)
  !$h

func hasCollation*(c: CoreCapabilities, algorithm: CollationAlgorithm): bool =
  ## Checks whether the server supports a given RFC 4790 collation algorithm.
  return algorithm in c.collationAlgorithms

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
