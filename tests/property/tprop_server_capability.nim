# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for ServerCapability round-trip identity across
## all 13 CapabilityKind arms at session scope.

import std/json
import std/random
import std/sets

import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

import ../mproperty
import ../mtestblock

testCase propServerCapabilityRoundTrip:
  checkProperty "ServerCapability round-trip preserves the capability":
    let cap = rng.genServerCapability()
    lastInput = cap.uri
    let rt = ServerCapability.fromJson(cap.uri, cap.toJson())
    doAssert rt.isOk, "fromJson failed for " & cap.uri
    doAssert rt.get() == cap, "round-trip mismatch for " & cap.uri

testCase propServerCapabilityEveryArmExercised:
  ## Across enough trials, the generator hits every arm. Verify each
  ## arm at session scope explicitly. Discard arms (ckMail/ckSubmission/
  ## ckVacationResponse) drop payload; check that round-trip preserves
  ## the kind/uri identity.
  let coreCaps = parseCoreCapabilities(
      parseUnsignedInt(1).get(),
      parseUnsignedInt(1).get(),
      parseUnsignedInt(1).get(),
      parseUnsignedInt(1).get(),
      parseUnsignedInt(1).get(),
      parseUnsignedInt(1).get(),
      parseUnsignedInt(1).get(),
      initHashSet[capabilities.CollationAlgorithm](),
    )
    .get()
  let coreCap = parseServerCapability(
      "urn:ietf:params:jmap:core", Opt.some(coreCaps), Opt.none(JsonNode)
    )
    .get()
  doAssert coreCap == ServerCapability.fromJson(coreCap.uri, coreCap.toJson()).get()

  const discardUris = [
    "urn:ietf:params:jmap:mail", "urn:ietf:params:jmap:submission",
    "urn:ietf:params:jmap:vacationresponse",
  ]
  for uri in discardUris:
    let cap =
      parseServerCapability(uri, Opt.none(CoreCapabilities), Opt.none(JsonNode)).get()
    let rt = ServerCapability.fromJson(uri, cap.toJson()).get()
    doAssert rt == cap, "discard-arm round-trip mismatch for " & uri

  const rawUris = [
    "urn:ietf:params:jmap:websocket", "urn:ietf:params:jmap:mdn",
    "urn:ietf:params:jmap:smimeverify", "urn:ietf:params:jmap:blob",
    "urn:ietf:params:jmap:quota", "urn:ietf:params:jmap:contacts",
    "urn:ietf:params:jmap:calendars", "urn:ietf:params:jmap:sieve",
    "https://vendor.example/x",
  ]
  for uri in rawUris:
    let cap = parseServerCapability(
        uri, Opt.none(CoreCapabilities), Opt.some(%*{"key": "value"})
      )
      .get()
    let rt = ServerCapability.fromJson(uri, cap.toJson()).get()
    doAssert rt == cap, "rawXxxData-arm round-trip mismatch for " & uri
