# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Layer 2 serde tests for CoreCapabilities and ServerCapability
## round-trip, structural, golden, and edge-case tests.

import std/json
import std/sets
import std/tables

import jmap_client/serde_session
import jmap_client/primitives
import jmap_client/capabilities
import jmap_client/validation
import jmap_client/session

import ../massertions
import ../mfixtures
import ../mproperty

# =============================================================================
# A. CoreCapabilities
# =============================================================================

block roundTripCoreCapabilitiesZero:
  let original = zeroCoreCaps()
  assertOkEq CoreCapabilities.fromJson(original.toJson()), original

block roundTripCoreCapabilitiesRealistic:
  let original = realisticCoreCaps()
  assertOkEq CoreCapabilities.fromJson(original.toJson()), original

block coreCapabilitiesToJsonFieldNames:
  let caps = realisticCoreCaps()
  let j = caps.toJson()
  doAssert j{"maxSizeUpload"} != nil
  doAssert j{"maxConcurrentUpload"} != nil
  doAssert j{"maxSizeRequest"} != nil
  # Must be plural, not singular
  doAssert j{"maxConcurrentRequests"} != nil
  doAssert j{"maxConcurrentRequest"}.isNil
  doAssert j{"maxCallsInRequest"} != nil
  doAssert j{"maxObjectsInGet"} != nil
  doAssert j{"maxObjectsInSet"} != nil
  doAssert j{"collationAlgorithms"} != nil
  doAssert j{"collationAlgorithms"}.kind == JArray
  for elem in j{"collationAlgorithms"}.getElems(@[]):
    doAssert elem.kind == JString

block coreCapabilitiesDeserValid:
  let j = %*{
    "maxSizeUpload": 50000000,
    "maxConcurrentUpload": 8,
    "maxSizeRequest": 10000000,
    "maxConcurrentRequests": 8,
    "maxCallsInRequest": 32,
    "maxObjectsInGet": 256,
    "maxObjectsInSet": 128,
    "collationAlgorithms": ["i;ascii-numeric"],
  }
  let caps = CoreCapabilities.fromJson(j).get()
  assertEq int64(caps.maxSizeUpload), 50000000'i64
  assertEq int64(caps.maxCallsInRequest), 32'i64
  doAssert caps.collationAlgorithms.contains("i;ascii-numeric")

block coreCapabilitiesDeserMissingField:
  let j = %*{
    "maxConcurrentUpload": 8,
    "maxSizeRequest": 10000000,
    "maxConcurrentRequests": 8,
    "maxCallsInRequest": 32,
    "maxObjectsInGet": 256,
    "maxObjectsInSet": 128,
    "collationAlgorithms": [],
  }
  assertErr CoreCapabilities.fromJson(j)

block coreCapabilitiesDeserWrongKindString:
  let j = %*{
    "maxSizeUpload": "string",
    "maxConcurrentUpload": 8,
    "maxSizeRequest": 10000000,
    "maxConcurrentRequests": 8,
    "maxCallsInRequest": 32,
    "maxObjectsInGet": 256,
    "maxObjectsInSet": 128,
    "collationAlgorithms": [],
  }
  assertErr CoreCapabilities.fromJson(j)

block coreCapabilitiesDeserNegativeValue:
  let j = %*{
    "maxSizeUpload": -1,
    "maxConcurrentUpload": 8,
    "maxSizeRequest": 10000000,
    "maxConcurrentRequests": 8,
    "maxCallsInRequest": 32,
    "maxObjectsInGet": 256,
    "maxObjectsInSet": 128,
    "collationAlgorithms": [],
  }
  assertErr CoreCapabilities.fromJson(j)

block coreCapabilitiesDeserEmptyCollation:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  let r = CoreCapabilities.fromJson(j).get()
  assertEq r.collationAlgorithms.len, 0

block coreCapabilitiesDeserCollationNonString:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [42],
  }
  assertErrContains CoreCapabilities.fromJson(j),
    "collationAlgorithms element must be string"

block coreCapabilitiesDeserCollationWrongKind:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": "notarray",
  }
  assertErrContains CoreCapabilities.fromJson(j),
    "missing or invalid collationAlgorithms"

block coreCapabilitiesDeserNotObjectOrNil:
  assertErr CoreCapabilities.fromJson(%*[1, 2, 3])
  const nilNode: JsonNode = nil
  assertErr CoreCapabilities.fromJson(nilNode)

block coreCapabilitiesDeserSingularOnly:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequest": 5,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  let r = CoreCapabilities.fromJson(j).get()
  assertEq int64(r.maxConcurrentRequests), 5'i64

block coreCapabilitiesDeserBothDifferentValues:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 10,
    "maxConcurrentRequest": 5,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  let r = CoreCapabilities.fromJson(j).get()
  # Plural form takes precedence
  assertEq int64(r.maxConcurrentRequests), 10'i64

block coreCapabilitiesDeserNeitherPresent:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  assertErrContains CoreCapabilities.fromJson(j), "missing maxConcurrentRequests"

# =============================================================================
# B. ServerCapability
# =============================================================================

block roundTripServerCapabilityCkCore:
  let original = makeCoreServerCap(realisticCoreCaps())
  assertCapOkEq ServerCapability.fromJson(original.rawUri, original.toJson()).get(),
    original

block serverCapabilityDeserCkCoreValid:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  let r = ServerCapability.fromJson("urn:ietf:params:jmap:core", j).get()
  doAssert r.kind == ckCore
  assertEq r.rawUri, "urn:ietf:params:jmap:core"

block serverCapabilityDeserCkCoreMissingField:
  let j = %*{"maxSizeUpload": 1}
  assertErrType ServerCapability.fromJson("urn:ietf:params:jmap:core", j), "UnsignedInt"

block serverCapabilityDeserUnknownUri:
  let data = %*{"maxFoosFinangled": 42}
  let cap = ServerCapability.fromJson("https://vendor.example/ext", data).get()
  doAssert cap.kind == ckUnknown
  assertEq cap.rawUri, "https://vendor.example/ext"
  doAssert cap.rawData{"maxFoosFinangled"} != nil

block serverCapabilityDeserKnownNonCoreUri:
  let r = ServerCapability.fromJson("urn:ietf:params:jmap:mail", newJObject()).get()
  doAssert r.kind == ckMail

block serverCapabilityToJsonCkCoreStructure:
  let cap = makeCoreServerCap(realisticCoreCaps())
  let j = cap.toJson()
  doAssert j.kind == JObject
  doAssert j{"maxSizeUpload"} != nil

block serverCapabilityToJsonNilVsNonNilRawData:
  let nilCap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: nil)
  let nilResult = nilCap.toJson()
  doAssert nilResult.kind == JObject
  assertEq nilResult.getFields().len, 0
  let data = %*{"custom": true}
  let dataCap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: data)
  doAssert dataCap.toJson() == data

block serverCapabilityCoreBranchInvalidCoreData:
  ## Passing a JArray instead of JObject for ckCore capability data must return err.
  let data = %*[1, 2, 3]
  assertErrContains ServerCapability.fromJson("urn:ietf:params:jmap:core", data),
    "core capability data must be JSON object"

# =============================================================================
# C. ServerCapability variant round-trips and edge cases
# =============================================================================

block serverCapabilityAllVariantsDeserRoundTrip:
  ## Verifies every non-core CapabilityKind deserialises and round-trips.
  let testData = %*{"vendorExtension": true, "nested": {"key": "val"}}
  let variants = [
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
  for (uri, expectedKind) in variants:
    let r = ServerCapability.fromJson(uri, testData).get()
    doAssert r.kind == expectedKind, "wrong kind for " & uri
    assertEq r.rawUri, uri
    # Verify rawData preserved (deep copy)
    let rtJson = r.toJson()
    doAssert rtJson{"vendorExtension"} != nil, "rawData lost for " & uri
    assertEq rtJson{"vendorExtension"}.getBool(false), true
    doAssert rtJson{"nested"} != nil, "nested data lost for " & uri

block serverCapabilityArcSharedRefSafety:
  ## Validates Phase 1A fix: two capabilities sharing the same JsonNode ref
  ## must not cause ARC double-free on destruction.
  let sharedData = %*{"shared": 42, "nested": {"a": 1}}
  # Both capabilities point to the same JsonNode — ownData() must deep-copy
  let r1 = ServerCapability.fromJson("urn:ietf:params:jmap:mail", sharedData).get()
  let r2 = ServerCapability.fromJson("urn:ietf:params:jmap:contacts", sharedData).get()
  # Verify they are independent copies, not the same ref
  let json1 = r1.toJson()
  let json2 = r2.toJson()
  assertEq json1{"shared"}.getBiggestInt(0), 42
  assertEq json2{"shared"}.getBiggestInt(0), 42
  # If they survived to here without crash, ARC ref management is safe

block coreCapabilitiesDeserMaxUnsignedIntBoundary:
  ## Boundary: 2^53-1 at CoreCapabilities level within Session context.
  const maxVal = 9007199254740991'i64 # 2^53-1
  let j = %*{
    "maxSizeUpload": maxVal,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  let r = CoreCapabilities.fromJson(j).get()
  assertEq int64(r.maxSizeUpload), maxVal

block coreCapabilitiesCollationDuplicatesDeduplication:
  ## HashSet deduplicates collation algorithms.
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": ["i;ascii-casemap", "i;ascii-casemap", "i;octet"],
  }
  let r = CoreCapabilities.fromJson(j).get()
  assertEq r.collationAlgorithms.len, 2

block serverCapabilityNestedRawDataRoundTrip:
  let data = %*{"foo": {"bar": [1, 2, {"baz": true}]}}
  let cap = ServerCapability.fromJson("https://vendor.example/ext", data).get()
  let rt = ServerCapability.fromJson(cap.rawUri, cap.toJson()).get()
  doAssert rt.rawData == data

block serverCapabilityJNullData:
  ## Documents behaviour when server sends null for capability data.
  ## JNull is non-nil, stored as-is in rawData.
  let r = ServerCapability.fromJson("urn:ietf:params:jmap:mail", newJNull()).get()
  doAssert r.rawData.kind == JNull

# =============================================================================
# D. Deep-copy mutation isolation
# =============================================================================

block serverCapabilityOwnDataMutationIsolation:
  ## Deserialise a ServerCapability for a non-core kind from a shared JsonNode,
  ## then mutate the original JsonNode and verify the capability's rawData
  ## field is unaffected (proving ownData deep-copies).
  let sharedData = %*{"key": "original", "nested": {"inner": 42}}
  let cap = ServerCapability.fromJson("urn:ietf:params:jmap:mail", sharedData).get()
  # Mutate the original shared JsonNode
  sharedData["key"] = %"mutated"
  sharedData["nested"]["inner"] = %999
  sharedData["newField"] = %"added"
  # Verify the capability's rawData is unaffected by the mutation
  assertEq cap.rawData{"key"}.getStr(""), "original"
  assertEq cap.rawData{"nested"}{"inner"}.getBiggestInt(0), 42
  doAssert cap.rawData{"newField"}.isNil,
    "newly added field must not appear in deep-copied rawData"

# =============================================================================
# E. Collection scale tests (CoreCapabilities)
# =============================================================================

block collationAlgorithmsLarge1000:
  ## CoreCapabilities with 1000 collation algorithm strings round-trips
  ## preserving the count.
  var j = validCoreCapsJson()
  var algArr = newJArray()
  for i in 0 ..< 1000:
    algArr.add(%("alg" & $i))
  j["collationAlgorithms"] = algArr
  let r = CoreCapabilities.fromJson(j).get()
  assertEq r.collationAlgorithms.len, 1000
  # Round-trip
  let rt = CoreCapabilities.fromJson(r.toJson()).get()
  assertEq rt.collationAlgorithms.len, 1000

# =============================================================================
# F. Property-based round-trip tests
# =============================================================================

checkProperty "CoreCapabilities round-trip":
  let caps = rng.genCoreCapabilities()
  assertOkEq CoreCapabilities.fromJson(caps.toJson()), caps

checkProperty "ServerCapability round-trip":
  let cap = rng.genServerCapability()
  assertCapOkEq ServerCapability.fromJson(cap.rawUri, cap.toJson()).get(), cap

# =============================================================================
# G. Equality helper verification
# =============================================================================

block equalityHelperCapEqDifferentKind:
  ## Verify capEq returns false for capabilities with different kinds.
  let coreCap = makeCoreServerCap(zeroCoreCaps())
  let mailCap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: newJObject()
  )
  doAssert not capEq(coreCap, mailCap), "capEq must return false for different kinds"

# =============================================================================
# H. Phase 3D: CoreCapabilities per-field missing tests
# Each test removes one required field and asserts err.
# =============================================================================

block coreCapsMissingMaxSizeUpload:
  var j = validCoreCapsJson()
  j.delete("maxSizeUpload")
  assertErr CoreCapabilities.fromJson(j)

block coreCapsMissingMaxConcurrentUpload:
  var j = validCoreCapsJson()
  j.delete("maxConcurrentUpload")
  assertErr CoreCapabilities.fromJson(j)

block coreCapsMissingMaxSizeRequest:
  var j = validCoreCapsJson()
  j.delete("maxSizeRequest")
  assertErr CoreCapabilities.fromJson(j)

block coreCapsMissingMaxConcurrentRequests:
  ## Removing both plural and singular forms must cause err.
  var j = validCoreCapsJson()
  j.delete("maxConcurrentRequests")
  # validCoreCapsJson uses plural form; verify it is now absent
  doAssert j{"maxConcurrentRequests"}.isNil
  doAssert j{"maxConcurrentRequest"}.isNil
  assertErrContains CoreCapabilities.fromJson(j), "missing maxConcurrentRequests"

block coreCapsMissingMaxCallsInRequest:
  var j = validCoreCapsJson()
  j.delete("maxCallsInRequest")
  assertErr CoreCapabilities.fromJson(j)

block coreCapsMissingMaxObjectsInGet:
  var j = validCoreCapsJson()
  j.delete("maxObjectsInGet")
  assertErr CoreCapabilities.fromJson(j)

block coreCapsMissingMaxObjectsInSet:
  var j = validCoreCapsJson()
  j.delete("maxObjectsInSet")
  assertErr CoreCapabilities.fromJson(j)

block coreCapsMissingCollationAlgorithms:
  var j = validCoreCapsJson()
  j.delete("collationAlgorithms")
  assertErrContains CoreCapabilities.fromJson(j),
    "missing or invalid collationAlgorithms"

# =============================================================================
# I. Phase 3I: AccountCapabilityEntry boundary tests
# =============================================================================

block accountCapabilityEntryEmptyUriRejectsMutation:
  ## Empty URI string must be rejected by AccountCapabilityEntry.fromJson.
  ## This test kills the mutation that removes the len==0 guard.
  assertErrContains AccountCapabilityEntry.fromJson("", newJObject()), "empty"

block accountCapabilityEntryNilDataToJson:
  ## Constructing an AccountCapabilityEntry with data: nil and calling toJson
  ## must produce a valid JObject (not crash). This kills the mutation that
  ## removes the nil-to-empty-object guard in toJson.
  let entry =
    AccountCapabilityEntry(kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: nil)
  let j = entry.toJson()
  doAssert j != nil, "toJson on nil-data entry must not return nil"
  doAssert j.kind == JObject, "toJson on nil-data entry must return JObject"

# =============================================================================
# toJson ownership: returned JsonNode must be independent of internal state
# =============================================================================

block serverCapabilityToJsonReturnsIndependentCopy:
  ## Mutating the JsonNode returned by toJson must not corrupt the capability.
  let vendorData = newJObject()
  vendorData["original"] = %"value"
  let cap = ServerCapability(
    rawUri: "urn:vendor:example", kind: ckUnknown, rawData: vendorData.copy()
  )
  let j = cap.toJson()
  j["injected"] = %"corrupted"
  doAssert cap.rawData{"injected"}.isNil,
    "toJson must return an independent copy — mutation must not propagate"
  doAssert cap.rawData{"original"}.getStr("") == "value", "original data must be intact"

block accountCapabilityEntryToJsonReturnsIndependentCopy:
  ## Mutating the JsonNode returned by toJson must not corrupt the entry.
  let entryData = newJObject()
  entryData["original"] = %"value"
  let entry = AccountCapabilityEntry(
    kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: entryData.copy()
  )
  let j = entry.toJson()
  j["injected"] = %"corrupted"
  doAssert entry.data{"injected"}.isNil,
    "toJson must return an independent copy — mutation must not propagate"
  doAssert entry.data{"original"}.getStr("") == "value", "original data must be intact"
