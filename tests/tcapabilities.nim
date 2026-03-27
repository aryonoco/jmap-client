# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for CapabilityKind parsing, URI round-trip, and CoreCapabilities queries.

import std/sets
import std/json

import pkg/results

import jmap_client/primitives
import jmap_client/capabilities

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
