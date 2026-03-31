# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for CapabilityKind parsing and URI round-trips.

import std/json
import std/random
import std/sets

import results

import jmap_client/capabilities
import ../mproperty

block propCapabilityKindTotality:
  checkProperty "parseCapabilityKind never crashes on arbitrary string":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseCapabilityKind(s)

block propCapabilityKindKnownRoundTrip:
  for kind in [
    ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
    ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve,
  ]:
    let uri = capabilityUri(kind).get()
    doAssert parseCapabilityKind(uri) == kind

block propCapabilityKindUnknownReturnsNone:
  doAssert capabilityUri(ckUnknown).isNone

block propCapabilityKindAllKnownHaveUri:
  for kind in CapabilityKind:
    if kind != ckUnknown:
      doAssert capabilityUri(kind).isSome

# --- CoreCapabilities and ServerCapability generator properties ---

block propCoreCapabilitiesFieldsNonNegative:
  checkProperty "genCoreCapabilities fields are non-negative":
    let caps = genCoreCapabilities(rng)
    doAssert int64(caps.maxSizeUpload) >= 0
    doAssert int64(caps.maxConcurrentUpload) >= 0
    doAssert int64(caps.maxSizeRequest) >= 0
    doAssert int64(caps.maxConcurrentRequests) >= 0
    doAssert int64(caps.maxCallsInRequest) >= 0
    doAssert int64(caps.maxObjectsInGet) >= 0
    doAssert int64(caps.maxObjectsInSet) >= 0

block propServerCapabilityRawUriNonEmpty:
  checkProperty "genServerCapability rawUri always non-empty":
    let sc = genServerCapability(rng)
    lastInput = sc.rawUri
    doAssert sc.rawUri.len > 0

block propServerCapabilityKindMatchesUri:
  checkProperty "genServerCapability kind matches parseCapabilityKind(rawUri)":
    let sc = genServerCapability(rng)
    lastInput = sc.rawUri
    doAssert sc.kind == parseCapabilityKind(sc.rawUri)

block propServerCapabilityCoreHasCoreData:
  checkProperty "genServerCapability ckCore variant has accessible core fields":
    let sc = genServerCapability(rng)
    lastInput = sc.rawUri
    case sc.kind
    of ckCore:
      doAssert int64(sc.core.maxSizeUpload) >= 0
    else:
      doAssert sc.rawData != nil

block propCoreCapabilitiesHasCollationConsistency:
  checkProperty "hasCollation agrees with set membership":
    let caps = genCoreCapabilities(rng)
    for alg in caps.collationAlgorithms:
      doAssert hasCollation(caps, alg)
    doAssert not hasCollation(caps, "i;nonexistent-collation-xyz")

block propCoreCapabilitiesCollationAlgorithmsValid:
  checkProperty "genCoreCapabilities collation strings are non-empty":
    let caps = genCoreCapabilities(rng)
    for alg in caps.collationAlgorithms:
      doAssert alg.len > 0
