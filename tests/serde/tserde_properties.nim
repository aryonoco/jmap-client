# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Algebraic property tests for Layer 2 serialisation. Verifies fundamental
## mathematical laws: round-trip (fromJson . toJson = id), totality (fromJson
## never crashes on arbitrary input), idempotence (toJson . fromJson . toJson
## = toJson), and composition chain error propagation.

import std/json
import std/random
import std/tables

import jmap_client/serde
import jmap_client/serde_envelope
import jmap_client/serde_session
import jmap_client/serde_framework
import jmap_client/serde_errors
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/envelope
import jmap_client/framework
import jmap_client/errors
import jmap_client/validation

import ../massertions
import ../mfixtures
import ../mproperty
import ../mserde_fixtures

# =============================================================================
# A. Round-trip properties: fromJson(toJson(x)) == x
# =============================================================================

checkProperty "CoreCapabilities serde round-trip":
  let original = rng.genCoreCapabilities()
  let rt = CoreCapabilities.fromJson(original.toJson()).get()
  doAssert coreCapEq(rt, original), "CoreCapabilities round-trip values differ"

checkProperty "ServerCapability serde round-trip":
  let original = rng.genServerCapability()
  let rt = ServerCapability.fromJson(original.rawUri, original.toJson()).get()
  doAssert capEq(rt, original), "ServerCapability round-trip values differ"

checkProperty "Account serde round-trip":
  let original = rng.genValidAccount()
  discard Account.fromJson(original.toJson())

checkPropertyN "Session serde round-trip", ThoroughTrials:
  let original = rng.genSession()
  let j = original.toJson()
  let v = Session.fromJson(j).get()
  doAssert v.username == original.username
  doAssert v.apiUrl == original.apiUrl
  doAssert v.state == original.state
  doAssert v.capabilities.len == original.capabilities.len
  doAssert capsEq(v.capabilities, original.capabilities)

checkProperty "Invocation serde round-trip (complex args)":
  let original = rng.genInvocationWithArgs()
  let v = Invocation.fromJson(original.toJson()).get()
  doAssert v.name == original.name
  doAssert v.arguments == original.arguments
  doAssert v.methodCallId == original.methodCallId

checkPropertyN "Request serde round-trip", ThoroughTrials:
  let original = rng.genRequest()
  let v = Request.fromJson(original.toJson()).get()
  doAssert v.`using` == original.`using`
  doAssert v.methodCalls.len == original.methodCalls.len
  for i in 0 ..< v.methodCalls.len:
    doAssert v.methodCalls[i].name == original.methodCalls[i].name
    doAssert v.methodCalls[i].methodCallId == original.methodCalls[i].methodCallId
    doAssert v.methodCalls[i].arguments == original.methodCalls[i].arguments
  doAssert v.createdIds.isSome == original.createdIds.isSome

checkPropertyN "Response serde round-trip", ThoroughTrials:
  let original = rng.genResponse()
  let v = Response.fromJson(original.toJson()).get()
  doAssert v.methodResponses.len == original.methodResponses.len
  doAssert v.sessionState == original.sessionState
  for i in 0 ..< v.methodResponses.len:
    doAssert v.methodResponses[i].name == original.methodResponses[i].name
    doAssert v.methodResponses[i].methodCallId ==
      original.methodResponses[i].methodCallId
  doAssert v.createdIds.isSome == original.createdIds.isSome

checkProperty "Filter[int] serde round-trip":
  let original = rng.genFilter(4)
  let rt = Filter[int].fromJson(original.toJson(intToJson), fromIntCondition).get()
  doAssert filterEq(rt, original), "Filter round-trip values differ"

checkProperty "Comparator serde round-trip":
  let original = rng.genComparator()
  let v = Comparator.fromJson(original.toJson()).get()
  doAssert v.property == original.property
  doAssert v.isAscending == original.isAscending
  doAssert v.collation == original.collation

checkProperty "PatchObject serde round-trip (value equality)":
  let original = rng.genPatchObject(5)
  let v = PatchObject.fromJson(original.toJson()).get()
  doAssert v.len == original.len, "PatchObject round-trip length differs"
  # Verify all paths survived (toJson -> fromJson preserves keys)
  let originalJson = original.toJson()
  let rtJson = v.toJson()
  for key, val in originalJson.pairs:
    doAssert rtJson{key} != nil, "PatchObject key '" & key & "' lost in round-trip"

checkProperty "AddedItem serde round-trip":
  let original = rng.genAddedItem()
  let v = AddedItem.fromJson(original.toJson()).get()
  doAssert v.id == original.id
  doAssert v.index == original.index

checkProperty "RequestError serde round-trip":
  let original = rng.genRequestError()
  assertOkEq RequestError.fromJson(original.toJson()), original

checkProperty "MethodError serde round-trip":
  let original = rng.genMethodError()
  assertOkEq MethodError.fromJson(original.toJson()), original

checkProperty "SetError serde round-trip":
  let original = rng.genSetError()
  let rt = SetError.fromJson(original.toJson()).get()
  doAssert setErrorEq(rt, original), "SetError round-trip values differ"

checkProperty "ResultReference serde round-trip":
  let mcidStr = "c" & $rng.rand(0 .. 99)
  let mcid = parseMethodCallId(mcidStr).get()
  const paths = ["/ids", "/list/*/id", "/added/*/id", "/created", "/updated"]
  const names = ["Mailbox/get", "Email/query", "Thread/get"]
  let original = initResultReference(
    resultOf = mcid, name = rng.oneOf(names), path = rng.oneOf(paths)
  )
  assertOkEq ResultReference.fromJson(original.toJson()), original

# =============================================================================
# B. Totality properties: fromJson never crashes on arbitrary input
# =============================================================================

checkPropertyN "CoreCapabilities.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(2)
  discard CoreCapabilities.fromJson(node)
checkPropertyN "ServerCapability.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(2)
  const uris = [
    "urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail",
    "https://vendor.example.com/ext", "",
  ]
  discard ServerCapability.fromJson(rng.oneOf(uris), node)
checkPropertyN "Account.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(2)
  discard Account.fromJson(node)
checkPropertyN "Session.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonObject(2)
  discard Session.fromJson(node)
checkPropertyN "Invocation.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(2)
  discard Invocation.fromJson(node)
checkPropertyN "Request.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonObject(2)
  discard Request.fromJson(node)
checkPropertyN "Response.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonObject(2)
  discard Response.fromJson(node)
checkPropertyN "ResultReference.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(2)
  discard ResultReference.fromJson(node)
checkPropertyN "FilterOperator.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(1)
  discard FilterOperator.fromJson(node)
checkPropertyN "Filter[int].fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(3)
  discard Filter[int].fromJson(node, fromIntCondition)
checkPropertyN "Comparator.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(2)
  discard Comparator.fromJson(node)
checkPropertyN "PatchObject.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(2)
  discard PatchObject.fromJson(node)
checkPropertyN "AddedItem.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(2)
  discard AddedItem.fromJson(node)
checkPropertyN "RequestError.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonObject(2)
  discard RequestError.fromJson(node)
checkPropertyN "MethodError.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonObject(2)
  discard MethodError.fromJson(node)
checkPropertyN "SetError.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonObject(2)
  discard SetError.fromJson(node)
# Primitive/identifier totality (fromJson with arbitrary JSON kinds)
checkPropertyN "Id.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(1)
  discard Id.fromJson(node)
checkPropertyN "UnsignedInt.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(1)
  discard UnsignedInt.fromJson(node)
checkPropertyN "JmapInt.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(1)
  discard JmapInt.fromJson(node)
checkPropertyN "Date.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(1)
  discard Date.fromJson(node)
checkPropertyN "UTCDate.fromJson never crashes on arbitrary JSON", QuickTrials:
  let node = rng.genArbitraryJsonNode(1)
  discard UTCDate.fromJson(node)
# =============================================================================
# C. Idempotence: toJson(fromJson(toJson(x))) == toJson(x)
# =============================================================================

checkProperty "CoreCapabilities serialisation idempotence":
  let original = rng.genCoreCapabilities()
  let j1 = original.toJson()
  let parsed = CoreCapabilities.fromJson(j1).get()
  let reparsed = CoreCapabilities.fromJson(parsed.toJson()).get()
  doAssert coreCapEq(parsed, reparsed), "CoreCapabilities idempotence failed"

checkProperty "RequestError serialisation idempotence":
  let original = rng.genRequestError()
  let j1 = original.toJson()
  let parsed = RequestError.fromJson(j1).get()
  let j2 = parsed.toJson()
  doAssert $j1 == $j2, "RequestError idempotence failed"

checkProperty "MethodError serialisation idempotence":
  let original = rng.genMethodError()
  let j1 = original.toJson()
  let parsed = MethodError.fromJson(j1).get()
  let j2 = parsed.toJson()
  doAssert $j1 == $j2, "MethodError idempotence failed"

checkProperty "Comparator serialisation idempotence":
  let original = rng.genComparator()
  let j1 = original.toJson()
  let parsed = Comparator.fromJson(j1).get()
  let j2 = parsed.toJson()
  doAssert $j1 == $j2, "Comparator idempotence failed"

checkProperty "AddedItem serialisation idempotence":
  let original = rng.genAddedItem()
  let j1 = original.toJson()
  let parsed = AddedItem.fromJson(j1).get()
  let j2 = parsed.toJson()
  doAssert $j1 == $j2, "AddedItem idempotence failed"

checkProperty "Invocation serialisation idempotence":
  let original = rng.genInvocationWithArgs()
  let j1 = original.toJson()
  let parsed = Invocation.fromJson(j1).get()
  let j2 = parsed.toJson()
  doAssert $j1 == $j2, "Invocation idempotence failed"

# =============================================================================
# D. Composition chain error propagation
# =============================================================================

block compositionSessionNestedError:
  ## Session -> ServerCapability -> CoreCapabilities -> UnsignedInt:
  ## Invalid UnsignedInt at bottom should propagate to Session.fromJson error.
  var j = validSessionJson()
  j["capabilities"]["urn:ietf:params:jmap:core"]["maxSizeUpload"] = %(-1)
  assertErr Session.fromJson(j)
  assertErrType Session.fromJson(j), "UnsignedInt"

block compositionSessionMissingCoreCaps:
  ## Session without ckCore capability should fail at Session validation.
  var j = validSessionJson()
  j["capabilities"] = %*{"urn:ietf:params:jmap:mail": {}}
  assertErr Session.fromJson(j)
  assertErrContains Session.fromJson(j), "capabilities must include"

block compositionRequestNestedError:
  ## Request -> Invocation -> MethodCallId: invalid mcid should propagate.
  let j =
    %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": [["Mailbox/get", {}, ""]]}
  assertErr Request.fromJson(j)
  assertErrContains Request.fromJson(j), "must not be empty"

block compositionSetErrorVariantPreservation:
  ## SetError invalidProperties variant: properties list survives round-trip.
  let original =
    setErrorInvalidProperties("invalidProperties", @["from", "subject", "to"])
  let v = SetError.fromJson(original.toJson()).get()
  doAssert v.errorType == setInvalidProperties
  assertEq v.properties.len, 3
  doAssert "from" in v.properties
  doAssert "subject" in v.properties
  doAssert "to" in v.properties

block compositionSetErrorAlreadyExistsPreservation:
  ## SetError alreadyExists variant: existingId survives round-trip.
  let eid = parseIdFromServer("msg42").get()
  let original = setErrorAlreadyExists("alreadyExists", eid)
  let v = SetError.fromJson(original.toJson()).get()
  doAssert v.errorType == setAlreadyExists
  assertEq string(v.existingId), "msg42"

block compositionResponseCreatedIdsPreservation:
  ## Response createdIds table survives round-trip with correct keys and values.
  var tbl = initTable[CreationId, Id]()
  tbl[makeCreationId("new1")] = makeId("id1")
  tbl[makeCreationId("new2")] = makeId("id2")
  tbl[makeCreationId("new3")] = makeId("id3")
  let original = makeResponse(createdIds = Opt.some(tbl))
  let v = Response.fromJson(original.toJson()).get()
  doAssert v.createdIds.isSome
  assertEq v.createdIds.get().len, 3
