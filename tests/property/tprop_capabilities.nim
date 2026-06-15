# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for CapabilityKind parsing and URI round-trips.

import std/json
import std/random
import std/sets

import jmap_client/internal/types/capabilities
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation
import ../mproperty
import ../mtestblock

testCase propCapabilityKindTotality:
  checkProperty "parseCapabilityKind never crashes on arbitrary string":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseCapabilityKind(s)

testCase propCapabilityKindKnownRoundTrip:
  for kind in [
    ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
    ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve,
  ]:
    let uri = capabilityUri(kind).get()
    doAssert parseCapabilityKind(uri) == kind

testCase propCapabilityKindUnknownReturnsNone:
  doAssert capabilityUri(ckUnknown).isNone

testCase propCapabilityKindAllKnownHaveUri:
  for kind in CapabilityKind:
    if kind != ckUnknown:
      doAssert capabilityUri(kind).isSome

# --- CoreCapabilities and ServerCapability generator properties ---

testCase propCoreCapabilitiesFieldsNonNegative:
  checkProperty "genCoreCapabilities fields are non-negative":
    let caps = genCoreCapabilities(rng)
    doAssert caps.maxSizeUpload.toInt64 >= 0
    doAssert caps.maxConcurrentUpload.toInt64 >= 0
    doAssert caps.maxSizeRequest.toInt64 >= 0
    doAssert caps.maxConcurrentRequests.toInt64 >= 0
    doAssert caps.maxCallsInRequest.toInt64 >= 0
    doAssert caps.maxObjectsInGet.toInt64 >= 0
    doAssert caps.maxObjectsInSet.toInt64 >= 0

testCase propServerCapabilityRawUriNonEmpty:
  checkProperty "genServerCapability uri always non-empty":
    let sc = genServerCapability(rng)
    lastInput = sc.uri
    doAssert sc.uri.len > 0

testCase propServerCapabilityKindMatchesUri:
  checkProperty "genServerCapability kind matches parseCapabilityKind(uri)":
    let sc = genServerCapability(rng)
    lastInput = sc.uri
    doAssert sc.kind == parseCapabilityKind(sc.uri)

testCase propServerCapabilityCoreHasCoreData:
  checkProperty "genServerCapability ckCore variant has accessible core data":
    let sc = genServerCapability(rng)
    lastInput = sc.uri
    case sc.kind
    of ckCore:
      let coreOpt = sc.asCoreCapabilities()
      doAssert coreOpt.isSome
      doAssert coreOpt.get().maxSizeUpload.toInt64 >= 0
    of ckMail, ckSubmission, ckVacationResponse:
      # discard arms — asRawData returns none, no payload
      doAssert sc.asRawData().isNone
    of ckWebsocket, ckMdn, ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars,
        ckSieve, ckUnknown:
      doAssert sc.asRawData().isSome
      doAssert sc.asRawData().get() != nil

testCase propCoreCapabilitiesHasCollationConsistency:
  checkProperty "hasCollation agrees with set membership":
    let caps = genCoreCapabilities(rng)
    for alg in caps.collationAlgorithms:
      doAssert hasCollation(caps, alg)
    # The generator draws from the four IANA identifiers only — any caOther
    # value is guaranteed to be outside the generated set.
    doAssert not hasCollation(
      caps, parseCollationAlgorithm("i;nonexistent-collation-xyz").get()
    )

testCase propCoreCapabilitiesCollationAlgorithmsValid:
  checkProperty "genCoreCapabilities collation identifiers are non-empty":
    let caps = genCoreCapabilities(rng)
    for alg in caps.collationAlgorithms:
      doAssert ($alg).len > 0
