# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for CapabilityKind parsing, URI round-trip, and CoreCapabilities queries.

import std/options
import std/sets
import std/json

import jmap_client/primitives
import jmap_client/capabilities

import ../massertions
import ../mfixtures

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
  doAssert result.isSome
  doAssert result.get() == "urn:ietf:params:jmap:core"

block capabilityUriMail:
  let result = capabilityUri(ckMail)
  doAssert result.isSome
  doAssert result.get() == "urn:ietf:params:jmap:mail"

block capabilityUriCalendars:
  let result = capabilityUri(ckCalendars)
  doAssert result.isSome
  doAssert result.get() == "urn:ietf:params:jmap:calendars"

block capabilityUriUnknown:
  assertNone capabilityUri(ckUnknown)

# --- CoreCapabilities + hasCollation ---

block coreCapabilitiesHasCollation:
  let zero = parseUnsignedInt(0)
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
  let zero = parseUnsignedInt(0)
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
  let zero = parseUnsignedInt(0)
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
  ## Table-driven: every known capability URI maps to its expected kind.
  const cases = [
    ("urn:ietf:params:jmap:core", ckCore),
    ("urn:ietf:params:jmap:mail", ckMail),
    ("urn:ietf:params:jmap:submission", ckSubmission),
    ("urn:ietf:params:jmap:vacationresponse", ckVacationResponse),
    ("urn:ietf:params:jmap:websocket", ckWebsocket),
    ("urn:ietf:params:jmap:mdn", ckMdn),
    ("urn:ietf:params:jmap:smimeverify", ckSmimeVerify),
    ("urn:ietf:params:jmap:blob", ckBlob),
    ("urn:ietf:params:jmap:quota", ckQuota),
    ("urn:ietf:params:jmap:contacts", ckContacts),
    ("urn:ietf:params:jmap:calendars", ckCalendars),
    ("urn:ietf:params:jmap:sieve", ckSieve),
  ]
  for (uri, expected) in cases:
    assertEq parseCapabilityKind(uri), expected

block capabilityUriAllKnown:
  ## Table-driven: every known kind maps back to its canonical URI.
  const cases = [
    (ckCore, "urn:ietf:params:jmap:core"),
    (ckMail, "urn:ietf:params:jmap:mail"),
    (ckSubmission, "urn:ietf:params:jmap:submission"),
    (ckVacationResponse, "urn:ietf:params:jmap:vacationresponse"),
    (ckWebsocket, "urn:ietf:params:jmap:websocket"),
    (ckMdn, "urn:ietf:params:jmap:mdn"),
    (ckSmimeVerify, "urn:ietf:params:jmap:smimeverify"),
    (ckBlob, "urn:ietf:params:jmap:blob"),
    (ckQuota, "urn:ietf:params:jmap:quota"),
    (ckContacts, "urn:ietf:params:jmap:contacts"),
    (ckCalendars, "urn:ietf:params:jmap:calendars"),
    (ckSieve, "urn:ietf:params:jmap:sieve"),
  ]
  for (kind, expectedUri) in cases:
    assertSomeEq capabilityUri(kind), expectedUri

block capabilityUriRoundTrip:
  for kind in [
    ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
    ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve,
  ]:
    let uri = capabilityUri(kind).get()
    doAssert parseCapabilityKind(uri) == kind

block coreCapabilitiesRealisticValues:
  let caps = realisticCoreCaps()
  doAssert caps.maxSizeUpload == parseUnsignedInt(50_000_000)
  doAssert caps.maxCallsInRequest == parseUnsignedInt(32)
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
  ## Table-driven: $ on string-backed enums returns the backing value.
  const cases = [
    (ckCore, "urn:ietf:params:jmap:core"),
    (ckMail, "urn:ietf:params:jmap:mail"),
    (ckSubmission, "urn:ietf:params:jmap:submission"),
    (ckVacationResponse, "urn:ietf:params:jmap:vacationresponse"),
    (ckWebsocket, "urn:ietf:params:jmap:websocket"),
    (ckMdn, "urn:ietf:params:jmap:mdn"),
    (ckSmimeVerify, "urn:ietf:params:jmap:smimeverify"),
    (ckBlob, "urn:ietf:params:jmap:blob"),
    (ckQuota, "urn:ietf:params:jmap:quota"),
    (ckContacts, "urn:ietf:params:jmap:contacts"),
    (ckCalendars, "urn:ietf:params:jmap:calendars"),
    (ckSieve, "urn:ietf:params:jmap:sieve"),
  ]
  for (kind, expectedStr) in cases:
    assertEq $kind, expectedStr

block serverCapabilityVendorExtension:
  let data = %*{"maxFoo": 42, "version": "1.0"}
  let sc = ServerCapability(
    rawUri: "https://vendor.example/ext", kind: ckUnknown, rawData: data
  )
  doAssert sc.rawUri == "https://vendor.example/ext"
  doAssert sc.kind == ckUnknown
