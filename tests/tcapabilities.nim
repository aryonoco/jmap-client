# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for CapabilityKind parsing, URI round-trip, and CoreCapabilities queries.

import std/sets
import std/json

import pkg/results

import jmap_client/primitives
import jmap_client/capabilities

import ./mfixtures

# --- parseCapabilityKind ---

block parseCapabilityKindCore:
  doAssert parseCapabilityKind("urn:ietf:params:jmap:core") == ckCore

block parseCapabilityKindMail:
  doAssert parseCapabilityKind("urn:ietf:params:jmap:mail") == ckMail

block parseCapabilityKindVendorUri:
  doAssert parseCapabilityKind("https://vendor.example/ext") == ckUnknown

block parseCapabilityKindEmpty:
  doAssert parseCapabilityKind("") == ckUnknown

# --- capabilityUri ---

block capabilityUriCore:
  let result = capabilityUri(ckCore)
  doAssert result.isOk
  doAssert result.get() == "urn:ietf:params:jmap:core"

block capabilityUriMail:
  let result = capabilityUri(ckMail)
  doAssert result.isOk
  doAssert result.get() == "urn:ietf:params:jmap:mail"

block capabilityUriCalendars:
  let result = capabilityUri(ckCalendars)
  doAssert result.isOk
  doAssert result.get() == "urn:ietf:params:jmap:calendars"

block capabilityUriUnknown:
  doAssert capabilityUri(ckUnknown).isErr

# --- CoreCapabilities + hasCollation ---

block coreCapabilitiesHasCollation:
  let zero = parseUnsignedInt(0).get()
  let caps = CoreCapabilities(
    maxSizeUpload: zero,
    maxConcurrentUpload: zero,
    maxSizeRequest: zero,
    maxConcurrentRequests: zero,
    maxCallsInRequest: zero,
    maxObjectsInGet: zero,
    maxObjectsInSet: zero,
    collationAlgorithms: toHashSet(["i;ascii-casemap", "i;unicode-casemap"]),
  )
  doAssert caps.hasCollation("i;ascii-casemap")
  doAssert not caps.hasCollation("i;nonexistent")

block hasCollationEmptySet:
  let zero = parseUnsignedInt(0).get()
  let caps = CoreCapabilities(
    maxSizeUpload: zero,
    maxConcurrentUpload: zero,
    maxSizeRequest: zero,
    maxConcurrentRequests: zero,
    maxCallsInRequest: zero,
    maxObjectsInGet: zero,
    maxObjectsInSet: zero,
    collationAlgorithms: initHashSet[string](),
  )
  doAssert not caps.hasCollation("i;ascii-casemap")

# --- ServerCapability construction ---

block serverCapabilityCore:
  let zero = parseUnsignedInt(0).get()
  let caps = CoreCapabilities(
    maxSizeUpload: zero,
    maxConcurrentUpload: zero,
    maxSizeRequest: zero,
    maxConcurrentRequests: zero,
    maxCallsInRequest: zero,
    maxObjectsInGet: zero,
    maxObjectsInSet: zero,
    collationAlgorithms: initHashSet[string](),
  )
  let sc =
    ServerCapability(rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: caps)
  doAssert sc.rawUri == "urn:ietf:params:jmap:core"
  doAssert sc.kind == ckCore

block serverCapabilityElse:
  let sc = ServerCapability(
    rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: newJNull()
  )
  doAssert sc.rawUri == "urn:ietf:params:jmap:mail"
  doAssert sc.kind == ckMail

block serverCapabilityUnknown:
  let sc = ServerCapability(
    rawUri: "https://vendor.example/ext", kind: ckUnknown, rawData: newJNull()
  )
  doAssert sc.rawUri == "https://vendor.example/ext"
  doAssert sc.kind == ckUnknown

# --- Missing variant coverage ---

block parseCapabilityKindAllKnown:
  doAssert parseCapabilityKind("urn:ietf:params:jmap:submission") == ckSubmission
  doAssert parseCapabilityKind("urn:ietf:params:jmap:vacationresponse") ==
    ckVacationResponse
  doAssert parseCapabilityKind("urn:ietf:params:jmap:websocket") == ckWebsocket
  doAssert parseCapabilityKind("urn:ietf:params:jmap:mdn") == ckMdn
  doAssert parseCapabilityKind("urn:ietf:params:jmap:smimeverify") == ckSmimeVerify
  doAssert parseCapabilityKind("urn:ietf:params:jmap:blob") == ckBlob
  doAssert parseCapabilityKind("urn:ietf:params:jmap:quota") == ckQuota
  doAssert parseCapabilityKind("urn:ietf:params:jmap:contacts") == ckContacts
  doAssert parseCapabilityKind("urn:ietf:params:jmap:calendars") == ckCalendars
  doAssert parseCapabilityKind("urn:ietf:params:jmap:sieve") == ckSieve

block capabilityUriAllKnown:
  doAssert capabilityUri(ckSubmission).get() == "urn:ietf:params:jmap:submission"
  doAssert capabilityUri(ckVacationResponse).get() ==
    "urn:ietf:params:jmap:vacationresponse"
  doAssert capabilityUri(ckWebsocket).get() == "urn:ietf:params:jmap:websocket"
  doAssert capabilityUri(ckMdn).get() == "urn:ietf:params:jmap:mdn"
  doAssert capabilityUri(ckSmimeVerify).get() == "urn:ietf:params:jmap:smimeverify"
  doAssert capabilityUri(ckBlob).get() == "urn:ietf:params:jmap:blob"
  doAssert capabilityUri(ckQuota).get() == "urn:ietf:params:jmap:quota"
  doAssert capabilityUri(ckContacts).get() == "urn:ietf:params:jmap:contacts"
  doAssert capabilityUri(ckCalendars).get() == "urn:ietf:params:jmap:calendars"
  doAssert capabilityUri(ckSieve).get() == "urn:ietf:params:jmap:sieve"

block capabilityUriRoundTrip:
  for kind in [
    ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
    ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve,
  ]:
    let uri = capabilityUri(kind).get()
    doAssert parseCapabilityKind(uri) == kind

block coreCapabilitiesRealisticValues:
  let caps = realisticCoreCaps()
  doAssert caps.maxSizeUpload == parseUnsignedInt(50_000_000).get()
  doAssert caps.maxCallsInRequest == parseUnsignedInt(32).get()
  doAssert caps.hasCollation("i;ascii-casemap")
  doAssert caps.hasCollation("i;unicode-casemap")

block serverCapabilityRawUriPreserved:
  let sc = ServerCapability(
    rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: zeroCoreCaps()
  )
  doAssert sc.rawUri == "urn:ietf:params:jmap:core"

block parseCapabilityKindCaseNormalisation:
  ## nimIdentNormalize: first char is case-sensitive, rest is case-insensitive.
  ## Same first char ('u') with different case in the rest still resolves.
  doAssert parseCapabilityKind("urn:ietf:params:jmap:CORE") == ckCore
  ## Different first char ('U' vs 'u') does NOT match.
  doAssert parseCapabilityKind("URN:IETF:PARAMS:JMAP:CORE") == ckUnknown

block capabilityKindStringBacking:
  doAssert $ckCore == "urn:ietf:params:jmap:core"
  doAssert $ckMail == "urn:ietf:params:jmap:mail"
  doAssert $ckSubmission == "urn:ietf:params:jmap:submission"
  doAssert $ckVacationResponse == "urn:ietf:params:jmap:vacationresponse"
  doAssert $ckWebsocket == "urn:ietf:params:jmap:websocket"
  doAssert $ckMdn == "urn:ietf:params:jmap:mdn"
  doAssert $ckSmimeVerify == "urn:ietf:params:jmap:smimeverify"
  doAssert $ckBlob == "urn:ietf:params:jmap:blob"
  doAssert $ckQuota == "urn:ietf:params:jmap:quota"
  doAssert $ckContacts == "urn:ietf:params:jmap:contacts"
  doAssert $ckCalendars == "urn:ietf:params:jmap:calendars"
  doAssert $ckSieve == "urn:ietf:params:jmap:sieve"

block serverCapabilityVendorExtension:
  let data = %*{"maxFoo": 42, "version": "1.0"}
  let sc = ServerCapability(
    rawUri: "https://vendor.example/ext", kind: ckUnknown, rawData: data
  )
  doAssert sc.rawUri == "https://vendor.example/ext"
  doAssert sc.kind == ckUnknown
