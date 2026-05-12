# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for CapabilityKind parsing and URI round-trips.

import std/json
import std/random
import std/sets

import jmap_client/internal/types/capabilities
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
    doAssert int64(caps.maxSizeUpload) >= 0
    doAssert int64(caps.maxConcurrentUpload) >= 0
    doAssert int64(caps.maxSizeRequest) >= 0
    doAssert int64(caps.maxConcurrentRequests) >= 0
    doAssert int64(caps.maxCallsInRequest) >= 0
    doAssert int64(caps.maxObjectsInGet) >= 0
    doAssert int64(caps.maxObjectsInSet) >= 0

testCase propServerCapabilityRawUriNonEmpty:
  checkProperty "genServerCapability rawUri always non-empty":
    let sc = genServerCapability(rng)
    lastInput = sc.rawUri
    doAssert sc.rawUri.len > 0

testCase propServerCapabilityKindMatchesUri:
  checkProperty "genServerCapability kind matches parseCapabilityKind(rawUri)":
    let sc = genServerCapability(rng)
    lastInput = sc.rawUri
    doAssert sc.kind == parseCapabilityKind(sc.rawUri)

testCase propServerCapabilityCoreHasCoreData:
  checkProperty "genServerCapability ckCore variant has accessible core fields":
    let sc = genServerCapability(rng)
    lastInput = sc.rawUri
    case sc.kind
    of ckCore:
      doAssert int64(sc.core.maxSizeUpload) >= 0
    else:
      doAssert sc.rawData != nil

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
