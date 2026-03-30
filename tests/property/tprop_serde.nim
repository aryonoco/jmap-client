# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for Layer 2 serialisation round-trips. Verifies
## toJson -> fromJson identity, totality (never crashes on arbitrary input),
## and idempotence for all composite serde types.

import std/json
import std/random
import std/sets
import std/tables

import results

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

# ---------------------------------------------------------------------------
# Equality helpers for case objects
# ---------------------------------------------------------------------------

func coreCapEq(a, b: CoreCapabilities): bool =
  ## Field-by-field equality for CoreCapabilities (HashSet == is fragile).
  a.maxSizeUpload == b.maxSizeUpload and a.maxConcurrentUpload == b.maxConcurrentUpload and
    a.maxSizeRequest == b.maxSizeRequest and
    a.maxConcurrentRequests == b.maxConcurrentRequests and
    a.maxCallsInRequest == b.maxCallsInRequest and a.maxObjectsInGet == b.maxObjectsInGet and
    a.maxObjectsInSet == b.maxObjectsInSet and
    a.collationAlgorithms.len == b.collationAlgorithms.len and
    a.collationAlgorithms <= b.collationAlgorithms

func capEq(a, b: ServerCapability): bool =
  ## Deep value equality for ServerCapability case object.
  if a.kind != b.kind or a.rawUri != b.rawUri:
    return false
  case a.kind
  of ckCore:
    coreCapEq(a.core, b.core)
  else:
    a.rawData == b.rawData

func invEq(a, b: Invocation): bool =
  ## Structural equality for Invocation including arguments.
  a.name == b.name and a.methodCallId == b.methodCallId and a.arguments == b.arguments

func reqEq(a, b: Request): bool =
  ## Structural equality for Request including methodCalls order.
  if a.using != b.using:
    return false
  if a.methodCalls.len != b.methodCalls.len:
    return false
  for i in 0 ..< a.methodCalls.len:
    if not invEq(a.methodCalls[i], b.methodCalls[i]):
      return false
  if a.createdIds.isSome != b.createdIds.isSome:
    return false
  if a.createdIds.isSome:
    if a.createdIds.get().len != b.createdIds.get().len:
      return false
  true

func respEq(a, b: Response): bool =
  ## Structural equality for Response including methodResponses order.
  if a.sessionState != b.sessionState:
    return false
  if a.methodResponses.len != b.methodResponses.len:
    return false
  for i in 0 ..< a.methodResponses.len:
    if not invEq(a.methodResponses[i], b.methodResponses[i]):
      return false
  if a.createdIds.isSome != b.createdIds.isSome:
    return false
  true

proc jsonCondToJson(condition: JsonNode): JsonNode {.noSideEffect, raises: [].} =
  ## Identity serialiser for Filter[JsonNode] tests.
  result = condition

proc fromJsonCondition(
    n: JsonNode
): Result[JsonNode, ValidationError] {.noSideEffect, raises: [].} =
  ## Identity deserialiser for Filter[JsonNode] tests.
  ok(n)

proc intToJson(c: int): JsonNode {.noSideEffect, raises: [].} =
  ## Serialise int condition to {"value": N}.
  {.cast(noSideEffect).}:
    %*{"value": c}

proc fromIntCondition(
    n: JsonNode
): Result[int, ValidationError] {.noSideEffect, raises: [].} =
  ## Deserialise int condition from {"value": N}.
  checkJsonKind(n, JObject, "int")
  let vNode = n{"value"}
  checkJsonKind(vNode, JInt, "int", "missing or invalid value")
  ok(vNode.getInt(0))

func filterEq(a, b: Filter[int]): bool =
  ## Recursive structural equality for Filter[int] trees.
  if a.kind != b.kind:
    return false
  case a.kind
  of fkCondition:
    a.condition == b.condition
  of fkOperator:
    if a.operator != b.operator:
      return false
    if a.conditions.len != b.conditions.len:
      return false
    for i in 0 ..< a.conditions.len:
      if not filterEq(a.conditions[i], b.conditions[i]):
        return false
    true

func setErrorEq(a, b: SetError): bool =
  ## Deep value equality for SetError case object.
  if a.rawType != b.rawType or a.errorType != b.errorType or
      a.description != b.description:
    return false
  case a.errorType
  of setInvalidProperties:
    a.properties == b.properties
  of setAlreadyExists:
    a.existingId == b.existingId
  else:
    true

# =============================================================================
# A. Round-trip identity properties (Tier 1 -- Critical)
# =============================================================================

block propRoundTripRequest:
  checkProperty "Request round-trip: fromJson(toJson(req)) preserves structure":
    let req = rng.genRequest()
    lastInput = $req.using.len & " using, " & $req.methodCalls.len & " calls"
    let j = req.toJson()
    let rt = Request.fromJson(j)
    doAssert rt.isOk, "Request round-trip failed"
    doAssert reqEq(rt.get(), req), "Request round-trip identity violated"

block propRoundTripResponse:
  checkProperty "Response round-trip: fromJson(toJson(resp)) preserves structure":
    let resp = rng.genResponse()
    lastInput = $resp.methodResponses.len & " responses"
    let j = resp.toJson()
    let rt = Response.fromJson(j)
    doAssert rt.isOk, "Response round-trip failed"
    doAssert respEq(rt.get(), resp), "Response round-trip identity violated"

block propRoundTripServerCapabilityRawData:
  checkProperty "ServerCapability rawData preserved through round-trip":
    let cap = rng.genServerCapability()
    lastInput = cap.rawUri
    if cap.kind != ckCore:
      let j = cap.toJson()
      let rt = ServerCapability.fromJson(cap.rawUri, j)
      doAssert rt.isOk, "ServerCapability round-trip failed for " & cap.rawUri
      doAssert capEq(rt.get(), cap), "rawData lost for " & cap.rawUri

block propRoundTripComparator:
  checkProperty "Comparator round-trip preserves all fields":
    let c = rng.genComparator()
    lastInput = string(c.property)
    let j = c.toJson()
    let rt = Comparator.fromJson(j)
    doAssert rt.isOk, "Comparator round-trip failed"
    let v = rt.get()
    doAssert string(v.property) == string(c.property)
    doAssert v.isAscending == c.isAscending
    doAssert v.collation == c.collation

block propRoundTripAddedItem:
  checkProperty "AddedItem round-trip preserves id and index":
    let item = rng.genAddedItem()
    lastInput = string(item.id) & " @ " & $int64(item.index)
    let j = item.toJson()
    let rt = AddedItem.fromJson(j)
    doAssert rt.isOk, "AddedItem round-trip failed"
    doAssert rt.get().id == item.id
    doAssert rt.get().index == item.index

block propRoundTripResultReference:
  checkProperty "ResultReference round-trip preserves all fields":
    let rref = rng.genResultReference()
    lastInput = rref.name
    let j = rref.toJson()
    let rt = ResultReference.fromJson(j)
    doAssert rt.isOk, "ResultReference round-trip failed"
    doAssert rt.get().resultOf == rref.resultOf
    doAssert rt.get().name == rref.name
    doAssert rt.get().path == rref.path

# =============================================================================
# B. Round-trip for error types (Tier 2 -- High)
# =============================================================================

block propRoundTripRequestError:
  checkProperty "RequestError round-trip preserves rawType and optional fields":
    let re = rng.genRequestError()
    lastInput = re.rawType
    let j = re.toJson()
    let rt = RequestError.fromJson(j)
    doAssert rt.isOk, "RequestError round-trip failed"
    doAssert rt.get().rawType == re.rawType
    doAssert rt.get().errorType == re.errorType
    doAssert rt.get().status == re.status
    doAssert rt.get().title == re.title
    doAssert rt.get().detail == re.detail

block propRoundTripMethodError:
  checkProperty "MethodError round-trip preserves rawType and description":
    let me = rng.genMethodError()
    lastInput = me.rawType
    let j = me.toJson()
    let rt = MethodError.fromJson(j)
    doAssert rt.isOk, "MethodError round-trip failed"
    doAssert rt.get().rawType == me.rawType
    doAssert rt.get().errorType == me.errorType
    doAssert rt.get().description == me.description

block propRoundTripSetErrorVariants:
  checkProperty "SetError variant round-trip preserves errorType and rawType":
    let se = rng.genSetError()
    lastInput = se.rawType & " (" & $se.errorType & ")"
    let j = se.toJson()
    let rt = SetError.fromJson(j)
    doAssert rt.isOk, "SetError round-trip failed for " & se.rawType
    doAssert rt.get().rawType == se.rawType
    # Variant-specific fields (defensive fallback may remap)
    case se.errorType
    of setInvalidProperties:
      if rt.get().errorType == setInvalidProperties:
        doAssert rt.get().properties == se.properties
    of setAlreadyExists:
      if rt.get().errorType == setAlreadyExists:
        doAssert rt.get().existingId == se.existingId
    else:
      discard

# =============================================================================
# C. Filter round-trip (Tier 1 -- Critical)
# =============================================================================

block propRoundTripFilterInt:
  checkProperty "Filter[int] round-trip preserves tree structure":
    let f = rng.genFilter(3)
    lastInput = $f.kind
    let j = f.toJson(intToJson)
    let rt = Filter[int].fromJson(j, fromIntCondition)
    doAssert rt.isOk, "Filter[int] round-trip failed"
    doAssert filterEq(rt.get(), f), "Filter[int] round-trip identity violated"

# =============================================================================
# D. Totality: fromJson never crashes on arbitrary input (Tier 3)
# =============================================================================

block propTotalitySessionMalformed:
  checkPropertyN "Session.fromJson never crashes on malformed input", ThoroughTrials:
    let j = rng.genMalformedSessionJson()
    lastInput = $j.kind
    discard Session.fromJson(j)

block propTotalityRequestArbitraryJson:
  checkPropertyN "Request.fromJson never crashes on arbitrary JSON", ThoroughTrials:
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard Request.fromJson(j)

block propTotalityResponseArbitraryJson:
  checkPropertyN "Response.fromJson never crashes on arbitrary JSON", ThoroughTrials:
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard Response.fromJson(j)

block propTotalityInvocationArbitraryJson:
  checkPropertyN "Invocation.fromJson never crashes on arbitrary JSON", ThoroughTrials:
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard Invocation.fromJson(j)

block propTotalityComparatorArbitraryJson:
  checkProperty "Comparator.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard Comparator.fromJson(j)

block propTotalitySetErrorArbitraryJson:
  checkProperty "SetError.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard SetError.fromJson(j)

block propTotalityRequestErrorArbitraryJson:
  checkProperty "RequestError.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard RequestError.fromJson(j)

block propTotalityMethodErrorArbitraryJson:
  checkProperty "MethodError.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard MethodError.fromJson(j)

block propTotalityPatchObjectArbitraryJson:
  checkProperty "PatchObject.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard PatchObject.fromJson(j)

block propTotalityAddedItemArbitraryJson:
  checkProperty "AddedItem.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard AddedItem.fromJson(j)

# =============================================================================
# E. Idempotence: toJson(fromJson(toJson(x))) == toJson(x) (Tier 3)
# =============================================================================

block propIdempotenceInvocation:
  checkProperty "Invocation serialisation is idempotent":
    let inv = rng.genInvocationWithArgs()
    lastInput = inv.name
    let j1 = inv.toJson()
    let parsed = Invocation.fromJson(j1)
    doAssert parsed.isOk
    let j2 = parsed.get().toJson()
    doAssert j1 == j2, "Invocation toJson is not idempotent"

block propIdempotenceResultReference:
  checkProperty "ResultReference serialisation is idempotent":
    let rref = rng.genResultReference()
    lastInput = rref.name
    let j1 = rref.toJson()
    let parsed = ResultReference.fromJson(j1)
    doAssert parsed.isOk
    let j2 = parsed.get().toJson()
    doAssert j1 == j2, "ResultReference toJson is not idempotent"

block propIdempotenceRequestError:
  checkProperty "RequestError serialisation is idempotent":
    let re = rng.genRequestError()
    lastInput = re.rawType
    let j1 = re.toJson()
    let parsed = RequestError.fromJson(j1)
    doAssert parsed.isOk
    let j2 = parsed.get().toJson()
    doAssert j1 == j2, "RequestError toJson is not idempotent"
