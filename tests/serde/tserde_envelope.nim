# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for Layer 2 envelope serialisation: Invocation, Request, Response,
## ResultReference, and Referencable[T] dispatch tests.

import std/json
import std/random
import std/strutils
import std/tables

import results

import jmap_client/serde
import jmap_client/serde_envelope
import jmap_client/serde_errors
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/envelope
import jmap_client/errors
import jmap_client/validation

import ../massertions
import ../mfixtures
import ../mproperty

# ---------------------------------------------------------------------------
# Helper definitions
# ---------------------------------------------------------------------------

func fromDirectInt(n: JsonNode): Result[int, ValidationError] =
  ## Parse a JSON integer for Referencable[int] tests.
  checkJsonKind(n, JInt, "int")
  ok(n.getInt(0))

# Golden and valid Request/Response JSON fixtures are in mfixtures.nim:
# goldenRequestJson(), goldenResponseJson(), validRequestJson(), validResponseJson()

# =============================================================================
# A. Round-trip tests
# =============================================================================

block roundTripInvocation:
  let original = makeInvocation()
  assertOkEq Invocation.fromJson(original.toJson()), original

block roundTripInvocationComplexArguments:
  {.cast(noSideEffect).}:
    let args = %*{
      "accountId": "A1", "list": [1, 2, 3], "filter": {"nested": {"deep": newJNull()}}
    }
    let original =
      Invocation(name: "Email/get", arguments: args, methodCallId: makeMcid("c1"))
    let rt = Invocation.fromJson(original.toJson())
    doAssert rt.isOk, "complex arguments round-trip failed"
    let v = rt.get()
    doAssert v.name == original.name
    doAssert v.arguments == original.arguments
    doAssert v.methodCallId == original.methodCallId

block roundTripRequest:
  let original = makeRequest()
  let r = Request.fromJson(original.toJson())
  doAssert r.isOk, "Request round-trip failed"
  let v = r.get()
  assertEq v.`using`, original.`using`
  assertEq v.methodCalls.len, original.methodCalls.len
  doAssert v.createdIds.isNone == original.createdIds.isNone

block roundTripRequestWithCreatedIds:
  var tbl = initTable[CreationId, Id]()
  tbl[makeCreationId("k1")] = makeId("id1")
  tbl[makeCreationId("k2")] = makeId("id2")
  tbl[makeCreationId("k3")] = makeId("id3")
  let original = makeRequest(createdIds = Opt.some(tbl))
  let rt = Request.fromJson(original.toJson())
  assertOk rt
  let v = rt.get()
  doAssert v.createdIds.isSome
  assertEq v.createdIds.get().len, 3

block roundTripResponse:
  let original = makeResponse()
  let r = Response.fromJson(original.toJson())
  doAssert r.isOk, "Response round-trip failed"
  let v = r.get()
  assertEq v.methodResponses.len, original.methodResponses.len
  assertEq v.sessionState, original.sessionState
  doAssert v.createdIds.isNone == original.createdIds.isNone

block roundTripResponseWithCreatedIds:
  var tbl = initTable[CreationId, Id]()
  tbl[makeCreationId("k1")] = makeId("id1")
  tbl[makeCreationId("k2")] = makeId("id2")
  tbl[makeCreationId("k3")] = makeId("id3")
  let original = makeResponse(createdIds = Opt.some(tbl))
  let rt = Response.fromJson(original.toJson())
  assertOk rt
  let v = rt.get()
  doAssert v.createdIds.isSome
  assertEq v.createdIds.get().len, 3

block roundTripResultReference:
  let original = makeResultReference()
  assertOkEq ResultReference.fromJson(original.toJson()), original

block roundTripResultReferenceAllPaths:
  let paths = [
    RefPathIds, RefPathListIds, RefPathAddedIds, RefPathCreated, RefPathUpdated,
    RefPathUpdatedProperties,
  ]
  for path in paths:
    let rref =
      ResultReference(resultOf: makeMcid("c0"), name: "Mailbox/get", path: path)
    assertOkEq ResultReference.fromJson(rref.toJson()), rref

# =============================================================================
# B. toJson structural correctness
# =============================================================================

block invocationToJsonIsArray:
  let inv = makeInvocation()
  let j = inv.toJson()
  doAssert j.kind == JArray
  assertEq j.len, 3
  doAssert j.getElems(@[])[0].kind == JString
  doAssert j.getElems(@[])[1].kind == JObject
  doAssert j.getElems(@[])[2].kind == JString

block invocationToJsonElementValues:
  let inv = makeInvocation("Email/get", makeMcid("c5"))
  let j = inv.toJson()
  let elems = j.getElems(@[])
  assertEq elems[0].getStr(""), "Email/get"
  assertEq elems[2].getStr(""), "c5"

block requestToJsonFieldNames:
  let req = makeRequest()
  let j = req.toJson()
  doAssert j{"using"} != nil
  doAssert j{"using"}.kind == JArray
  doAssert j{"methodCalls"} != nil
  doAssert j{"methodCalls"}.kind == JArray
  doAssert j{"createdIds"}.isNil

block requestToJsonCreatedIdsPresent:
  var tbl = initTable[CreationId, Id]()
  tbl[makeCreationId("k1")] = makeId("id1")
  let req = makeRequest(createdIds = Opt.some(tbl))
  let j = req.toJson()
  doAssert j{"createdIds"} != nil
  doAssert j{"createdIds"}.kind == JObject

block responseToJsonFieldNames:
  let resp = makeResponse()
  let j = resp.toJson()
  doAssert j{"methodResponses"} != nil
  doAssert j{"methodResponses"}.kind == JArray
  doAssert j{"sessionState"} != nil
  doAssert j{"sessionState"}.kind == JString
  doAssert j{"createdIds"}.isNil

block resultReferenceToJsonFieldNames:
  let rref = makeResultReference()
  let j = rref.toJson()
  doAssert j{"resultOf"} != nil
  doAssert j{"resultOf"}.kind == JString
  doAssert j{"name"} != nil
  doAssert j{"name"}.kind == JString
  doAssert j{"path"} != nil
  doAssert j{"path"}.kind == JString

# =============================================================================
# C. Golden tests (RFC examples)
# =============================================================================

block requestDeserGoldenRfc:
  let j = goldenRequestJson()
  let r = Request.fromJson(j)
  assertOk r
  let req = r.get()
  assertEq req.`using`.len, 2
  assertEq req.`using`[0], "urn:ietf:params:jmap:core"
  assertEq req.`using`[1], "urn:ietf:params:jmap:mail"
  assertEq req.methodCalls.len, 3
  assertEq req.methodCalls[0].name, "method1"
  assertEq req.methodCalls[0].methodCallId, parseMethodCallId("c1").get()
  assertEq req.methodCalls[0].arguments{"arg1"}.getStr(""), "arg1data"
  assertEq req.methodCalls[1].name, "method2"
  assertEq req.methodCalls[2].name, "method3"
  doAssert req.createdIds.isNone

block requestGoldenRoundTrip:
  let j = goldenRequestJson()
  let first = Request.fromJson(j).get()
  let second = Request.fromJson(first.toJson())
  assertOk second
  let v = second.get()
  assertEq v.`using`, first.`using`
  assertEq v.methodCalls.len, first.methodCalls.len
  for i in 0 ..< v.methodCalls.len:
    assertEq v.methodCalls[i].name, first.methodCalls[i].name
    assertEq v.methodCalls[i].methodCallId, first.methodCalls[i].methodCallId

block responseDeserGoldenRfc:
  let j = goldenResponseJson()
  let r = Response.fromJson(j)
  assertOk r
  let resp = r.get()
  assertEq resp.methodResponses.len, 4
  assertEq resp.methodResponses[0].name, "method1"
  assertEq resp.methodResponses[0].methodCallId, parseMethodCallId("c1").get()
  assertEq resp.methodResponses[2].name, "anotherResponseFromMethod2"
  assertEq resp.methodResponses[2].methodCallId, parseMethodCallId("c2").get()
  assertEq resp.methodResponses[3].name, "error"
  assertEq resp.methodResponses[3].methodCallId, parseMethodCallId("c3").get()
  # Phase 2B: verify error invocation arguments (RFC 3.4.1)
  assertEq resp.methodResponses[3].arguments{"type"}.getStr(""), "unknownMethod"
  assertEq resp.sessionState, parseJmapState("75128aab4b1b").get()
  doAssert resp.createdIds.isNone

block responseGoldenRoundTrip:
  let j = goldenResponseJson()
  let first = Response.fromJson(j).get()
  let second = Response.fromJson(first.toJson())
  assertOk second
  let v = second.get()
  assertEq v.methodResponses.len, first.methodResponses.len
  assertEq v.sessionState, first.sessionState
  for i in 0 ..< v.methodResponses.len:
    assertEq v.methodResponses[i].name, first.methodResponses[i].name
    assertEq v.methodResponses[i].methodCallId, first.methodResponses[i].methodCallId

# =============================================================================
# D. Edge-case deserialization
# =============================================================================

# --- Invocation ---

block invocationDeserObjectInsteadOfArray:
  {.cast(noSideEffect).}:
    assertErr Invocation.fromJson(%*{"name": "x", "args": {}, "id": "c1"})

block invocationDeserTwoElements:
  {.cast(noSideEffect).}:
    assertErr Invocation.fromJson(%*["Mailbox/get", {}])

block invocationDeserFourElements:
  {.cast(noSideEffect).}:
    assertErr Invocation.fromJson(%*["Mailbox/get", {}, "c1", "extra"])

block invocationDeserIntMethodName:
  {.cast(noSideEffect).}:
    assertErr Invocation.fromJson(%*[42, {}, "c1"])

block invocationDeserStringArguments:
  {.cast(noSideEffect).}:
    assertErr Invocation.fromJson(%*["Mailbox/get", "notobject", "c1"])

block invocationDeserIntCallId:
  {.cast(noSideEffect).}:
    assertErr Invocation.fromJson(%*["Mailbox/get", {}, 42])

block invocationDeserEmptyMethodName:
  {.cast(noSideEffect).}:
    assertErrContains Invocation.fromJson(%*["", {}, "c1"]), "must not be empty"

block invocationDeserEmptyCallId:
  {.cast(noSideEffect).}:
    assertErrContains Invocation.fromJson(%*["Mailbox/get", {}, ""]),
      "must not be empty"

block invocationDeserNil:
  const nilNode: JsonNode = nil
  assertErr Invocation.fromJson(nilNode)

block invocationDeserJNull:
  assertErr Invocation.fromJson(newJNull())

# --- Request ---

block requestDeserMissingUsing:
  {.cast(noSideEffect).}:
    let j = %*{"methodCalls": [["Mailbox/get", {}, "c0"]]}
    assertErrContains Request.fromJson(j), "missing or invalid using"

block requestDeserMissingMethodCalls:
  {.cast(noSideEffect).}:
    let j = %*{"using": ["urn:ietf:params:jmap:core"]}
    assertErrContains Request.fromJson(j), "missing or invalid methodCalls"

block requestDeserUsingNotArray:
  {.cast(noSideEffect).}:
    let j = %*{
      "using": "urn:ietf:params:jmap:core", "methodCalls": [["Mailbox/get", {}, "c0"]]
    }
    assertErr Request.fromJson(j)

block requestDeserMethodCallsNotArray:
  {.cast(noSideEffect).}:
    let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": {}}
    assertErr Request.fromJson(j)

block requestDeserUsingElementNotString:
  {.cast(noSideEffect).}:
    let j = %*{"using": [42], "methodCalls": [["Mailbox/get", {}, "c0"]]}
    assertErrContains Request.fromJson(j), "using element must be string"

block requestDeserNotObject:
  {.cast(noSideEffect).}:
    assertErr Request.fromJson(%*[1, 2, 3])

block requestDeserNil:
  const nilNode: JsonNode = nil
  assertErr Request.fromJson(nilNode)

block requestDeserEmptyMethodCalls:
  {.cast(noSideEffect).}:
    let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": []}
    let r = Request.fromJson(j)
    assertOk r
    assertEq r.get().methodCalls.len, 0

block requestDeserEmptyUsing:
  {.cast(noSideEffect).}:
    let j = %*{"using": [], "methodCalls": [["Mailbox/get", {}, "c0"]]}
    let r = Request.fromJson(j)
    assertOk r
    assertEq r.get().`using`.len, 0

block requestDeserDeepInvalidInvocation:
  {.cast(noSideEffect).}:
    let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": [["", {}, "c0"]]}
    let r = Request.fromJson(j)
    assertErr r
    assertErrContains r, "must not be empty"

# --- Response ---

block responseDeserMissingMethodResponses:
  {.cast(noSideEffect).}:
    let j = %*{"sessionState": "s1"}
    assertErrContains Response.fromJson(j), "missing or invalid methodResponses"

block responseDeserMissingSessionState:
  {.cast(noSideEffect).}:
    let j = %*{"methodResponses": [["Mailbox/get", {}, "c0"]]}
    assertErrContains Response.fromJson(j), "missing or invalid sessionState"

block responseDeserMethodResponsesNotArray:
  {.cast(noSideEffect).}:
    let j = %*{"methodResponses": {}, "sessionState": "s1"}
    assertErr Response.fromJson(j)

block responseDeserSessionStateNotString:
  {.cast(noSideEffect).}:
    let j = %*{"methodResponses": [["Mailbox/get", {}, "c0"]], "sessionState": 42}
    assertErr Response.fromJson(j)

block responseDeserNotObject:
  {.cast(noSideEffect).}:
    assertErr Response.fromJson(%*[1, 2, 3])

block responseDeserNil:
  const nilNode: JsonNode = nil
  assertErr Response.fromJson(nilNode)

block responseDeserEmptyMethodResponses:
  {.cast(noSideEffect).}:
    let j = %*{"methodResponses": [], "sessionState": "s1"}
    let r = Response.fromJson(j)
    assertOk r
    assertEq r.get().methodResponses.len, 0

block responseDeserDeepInvalidInvocation:
  {.cast(noSideEffect).}:
    let j = %*{"methodResponses": [["", {}, "c0"]], "sessionState": "s1"}
    let r = Response.fromJson(j)
    assertErr r
    assertErrContains r, "must not be empty"

# --- ResultReference ---

block resultReferenceDeserMissingResultOf:
  {.cast(noSideEffect).}:
    let j = %*{"name": "Mailbox/get", "path": "/ids"}
    assertErrContains ResultReference.fromJson(j), "missing or invalid resultOf"

block resultReferenceDeserMissingName:
  {.cast(noSideEffect).}:
    let j = %*{"resultOf": "c0", "path": "/ids"}
    assertErrContains ResultReference.fromJson(j), "missing or invalid name"

block resultReferenceDeserMissingPath:
  {.cast(noSideEffect).}:
    let j = %*{"resultOf": "c0", "name": "Mailbox/get"}
    assertErrContains ResultReference.fromJson(j), "missing or invalid path"

block resultReferenceDeserEmptyName:
  {.cast(noSideEffect).}:
    let j = %*{"resultOf": "c0", "name": "", "path": "/ids"}
    assertErrContains ResultReference.fromJson(j), "must not be empty"

block resultReferenceDeserEmptyPath:
  {.cast(noSideEffect).}:
    let j = %*{"resultOf": "c0", "name": "Mailbox/get", "path": ""}
    assertErrContains ResultReference.fromJson(j), "must not be empty"

block resultReferenceDeserNotObject:
  {.cast(noSideEffect).}:
    assertErr ResultReference.fromJson(%*[1, 2, 3])

block resultReferenceDeserNil:
  const nilNode: JsonNode = nil
  assertErr ResultReference.fromJson(nilNode)

# --- createdIds (tested on Request) ---

block createdIdsAbsentKey:
  {.cast(noSideEffect).}:
    let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": []}
    let r = Request.fromJson(j)
    assertOk r
    doAssert r.get().createdIds.isNone

block createdIdsJNull:
  var j = validRequestJson()
  j["createdIds"] = newJNull()
  let r = Request.fromJson(j)
  assertOk r
  doAssert r.get().createdIds.isNone

block createdIdsEmptyObject:
  var j = validRequestJson()
  j["createdIds"] = newJObject()
  let r = Request.fromJson(j)
  assertOk r
  doAssert r.get().createdIds.isSome
  assertEq r.get().createdIds.get().len, 0

block createdIdsPopulatedObject:
  var j = validRequestJson()
  {.cast(noSideEffect).}:
    j["createdIds"] = %*{"k1": "id1", "k2": "id2", "k3": "id3"}
  let r = Request.fromJson(j)
  assertOk r
  doAssert r.get().createdIds.isSome
  assertEq r.get().createdIds.get().len, 3

block createdIdsWrongKindArray:
  var j = validRequestJson()
  {.cast(noSideEffect).}:
    j["createdIds"] = %*[1, 2]
  assertErrContains Request.fromJson(j), "createdIds must be object or null"

block createdIdsWrongKindString:
  var j = validRequestJson()
  {.cast(noSideEffect).}:
    j["createdIds"] = %"not-an-object"
  assertErr Request.fromJson(j)

block createdIdsValueNotString:
  var j = validRequestJson()
  {.cast(noSideEffect).}:
    j["createdIds"] = %*{"k1": 42}
  assertErrContains Request.fromJson(j), "createdIds value must be string"

block createdIdsKeyStartsWithHash:
  var j = validRequestJson()
  {.cast(noSideEffect).}:
    j["createdIds"] = %*{"#k1": "id1"}
  assertErr Request.fromJson(j)

block createdIdsCreationIdHashPrefixInRequest:
  ## CreationId keys starting with '#' must be rejected by parseCreationId.
  ## Verifies the ? operator propagates the error through parseCreatedIds
  ## up to Request.fromJson.
  var j = validRequestJson()
  {.cast(noSideEffect).}:
    j["createdIds"] = %*{"#invalid": "id1"}
  let r = Request.fromJson(j)
  assertErr r

block createdIdsKeyEmpty:
  var j = validRequestJson()
  {.cast(noSideEffect).}:
    j["createdIds"] = %*{"": "id1"}
  assertErr Request.fromJson(j)

block createdIdsValueEmpty:
  var j = validRequestJson()
  {.cast(noSideEffect).}:
    j["createdIds"] = %*{"k1": ""}
  assertErr Request.fromJson(j)

block responseCreatedIdsSameSemantics:
  var j = validResponseJson()
  {.cast(noSideEffect).}:
    j["createdIds"] = %*{"k1": "id1"}
  let r = Response.fromJson(j)
  assertOk r
  doAssert r.get().createdIds.isSome
  assertEq r.get().createdIds.get().len, 1

# =============================================================================
# E. Referencable[T] dispatch tests
# =============================================================================

block referencableDirectValue:
  {.cast(noSideEffect).}:
    let node = %*{"ids": 42}
    let r = fromJsonField[int]("ids", node, fromDirectInt)
    assertOk r
    let v = r.get()
    doAssert v.kind == rkDirect
    assertEq v.value, 42

block referencableReferenceValue:
  {.cast(noSideEffect).}:
    let node = %*{"#ids": {"resultOf": "c0", "name": "Mailbox/query", "path": "/ids"}}
    let r = fromJsonField[int]("ids", node, fromDirectInt)
    assertOk r
    let v = r.get()
    doAssert v.kind == rkReference
    assertEq v.reference.name, "Mailbox/query"
    assertEq v.reference.path, "/ids"
    assertEq v.reference.resultOf, parseMethodCallId("c0").get()

block referencableBothPresentHashTakesPrecedence:
  {.cast(noSideEffect).}:
    let node =
      %*{"ids": 42, "#ids": {"resultOf": "c0", "name": "Mailbox/query", "path": "/ids"}}
    let r = fromJsonField[int]("ids", node, fromDirectInt)
    assertOk r
    doAssert r.get().kind == rkReference

block referencableMissingBothKeys:
  {.cast(noSideEffect).}:
    let node = %*{"other": 99}
    let r = fromJsonField[int]("ids", node, fromDirectInt)
    assertErr r
    assertErrContains r, "missing field"

block referencableHashKeyWrongKind:
  {.cast(noSideEffect).}:
    let nodeStr = %*{"#ids": "x"}
    assertErr fromJsonField[int]("ids", nodeStr, fromDirectInt)
    let nodeInt = %*{"#ids": 42}
    assertErr fromJsonField[int]("ids", nodeInt, fromDirectInt)

block referencableHashKeyMissingResultOf:
  {.cast(noSideEffect).}:
    let node = %*{"#ids": {"name": "Mailbox/query", "path": "/ids"}}
    assertErr fromJsonField[int]("ids", node, fromDirectInt)

block referencableKeyDirect:
  assertEq referencableKey("ids", direct(42)), "ids"

block referencableKeyReference:
  let rref = makeResultReference()
  assertEq referencableKey("ids", referenceTo[int](rref)), "#ids"

# =============================================================================
# F. Property-based round-trip tests
# =============================================================================

checkProperty "Invocation round-trip":
  let inv = rng.genInvocation()
  let rt = Invocation.fromJson(inv.toJson())
  doAssert rt.isOk, "Invocation round-trip failed"
  let v = rt.get()
  doAssert v.name == inv.name
  doAssert v.arguments == inv.arguments
  doAssert v.methodCallId == inv.methodCallId

checkProperty "ResultReference round-trip":
  let mcidStr = "c" & $rng.rand(0 .. 99)
  let mcid = parseMethodCallId(mcidStr).get()
  const paths = ["/ids", "/list/*/id", "/added/*/id", "/created", "/updated"]
  const names = ["Mailbox/get", "Email/query", "Thread/get", "Email/set"]
  let rref =
    ResultReference(resultOf: mcid, name: rng.oneOf(names), path: rng.oneOf(paths))
  assertOkEq ResultReference.fromJson(rref.toJson()), rref

checkProperty "Request round-trip":
  let n = rng.rand(0 .. 5)
  var calls: seq[Invocation] = @[]
  for i in 0 ..< n:
    calls.add rng.genInvocation()
  let req = makeRequest(`using` = @["urn:ietf:params:jmap:core"], methodCalls = calls)
  let rt = Request.fromJson(req.toJson())
  doAssert rt.isOk, "Request round-trip failed"
  let v = rt.get()
  doAssert v.`using` == req.`using`
  doAssert v.methodCalls.len == req.methodCalls.len
  doAssert v.createdIds.isNone == req.createdIds.isNone

checkProperty "Response round-trip":
  let n = rng.rand(0 .. 5)
  var resps: seq[Invocation] = @[]
  for i in 0 ..< n:
    resps.add rng.genInvocation()
  let stateStr = "state" & $rng.rand(0 .. 999)
  let state = parseJmapState(stateStr).get()
  let resp = makeResponse(methodResponses = resps, state = state)
  let rt = Response.fromJson(resp.toJson())
  doAssert rt.isOk, "Response round-trip failed"
  let v = rt.get()
  doAssert v.methodResponses.len == resp.methodResponses.len
  doAssert v.sessionState == resp.sessionState
  doAssert v.createdIds.isNone == resp.createdIds.isNone

# =============================================================================
# G. Additional edge-case and round-trip tests
# =============================================================================

block invocationComplexNestedArgsRoundTrip:
  ## Deep nesting (3+ levels), arrays of objects, null values in arguments.
  {.cast(noSideEffect).}:
    let args = %*{
      "filter": {
        "operator": "AND",
        "conditions":
          [{"subject": "test"}, {"nested": {"deep": {"value": [1, 2, nil]}}}],
      },
      "nullField": nil,
      "emptyArray": [],
    }
    let inv =
      Invocation(name: "Email/query", arguments: args, methodCallId: makeMcid("c1"))
    let rt = Invocation.fromJson(inv.toJson())
    assertOk rt
    assertEq rt.get().name, "Email/query"
    assertEq rt.get().methodCallId, makeMcid("c1")
    # Verify complex arguments survived
    doAssert rt.get().arguments{"filter"} != nil
    doAssert rt.get().arguments{"filter"}{"conditions"} != nil
    doAssert rt.get().arguments{"nullField"} != nil
    doAssert rt.get().arguments{"nullField"}.kind == JNull

block requestRoundTripWithCreatedIds:
  ## Verify CreationId keys and Id values survive toJson/fromJson cycle.
  {.cast(noSideEffect).}:
    var tbl = initTable[CreationId, Id]()
    tbl[makeCreationId("k1")] = makeId("id1")
    tbl[makeCreationId("k2")] = makeId("id2")
    let req = Request(
      `using`: @["urn:ietf:params:jmap:core"],
      methodCalls: @[makeInvocation()],
      createdIds: Opt.some(tbl),
    )
    let rt = Request.fromJson(req.toJson())
    assertOk rt
    assertSome rt.get().createdIds
    let rtTbl = rt.get().createdIds.get()
    assertEq rtTbl.len, 2

block responseRoundTripAllFields:
  ## methodResponses + sessionState + createdIds all present.
  {.cast(noSideEffect).}:
    var tbl = initTable[CreationId, Id]()
    tbl[makeCreationId("new0")] = makeId("created0")
    let resp = Response(
      methodResponses: @[makeInvocation(), makeInvocation("Email/set", makeMcid("c2"))],
      sessionState: makeState("s42"),
      createdIds: Opt.some(tbl),
    )
    let rt = Response.fromJson(resp.toJson())
    assertOk rt
    assertLen rt.get().methodResponses, 2
    assertEq rt.get().sessionState, makeState("s42")
    assertSome rt.get().createdIds

block fromJsonFieldRefInvalidResultOf:
  ## #ids key present but resultOf is empty — error must propagate.
  {.cast(noSideEffect).}:
    let node = %*{"#ids": {"resultOf": "", "name": "Mailbox/get", "path": "/ids"}}
    let r = fromJsonField[int]("ids", node, fromDirectInt)
    assertErr r

block referencableFromJsonFieldMalformedReference:
  ## When a '#'-prefixed key contains a malformed ResultReference (non-string
  ## resultOf), the error must propagate through fromJsonField.
  {.cast(noSideEffect).}:
    let node = %*{"#ids": {"resultOf": 42, "name": "Mailbox/get", "path": "/ids"}}
    let r = fromJsonField[int]("ids", node, fromDirectInt)
    assertErr r
    assertErrContains r, "missing or invalid resultOf"

block fromJsonFieldBothPresentRefTakesPrecedence:
  ## When both "ids" and "#ids" are present, reference takes precedence.
  {.cast(noSideEffect).}:
    let node =
      %*{"ids": 42, "#ids": {"resultOf": "c0", "name": "Mailbox/get", "path": "/ids"}}
    let r = fromJsonField[int]("ids", node, fromDirectInt)
    assertOk r
    doAssert r.get().kind == rkReference

block requestEmptyMethodCalls:
  ## Empty methodCalls array round-trips correctly.
  {.cast(noSideEffect).}:
    let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": []}
    let r = Request.fromJson(j)
    assertOk r
    assertLen r.get().methodCalls, 0
    assertLen r.get().`using`, 1

block requestEmptyUsingArray:
  ## Empty using array is valid per JSON schema.
  {.cast(noSideEffect).}:
    let j = %*{"using": [], "methodCalls": []}
    let r = Request.fromJson(j)
    assertOk r
    assertLen r.get().`using`, 0

# =============================================================================
# H. Phase 3E: Error invocation wire format
# =============================================================================

block errorInvocationWireFormat:
  ## Construct an Invocation with name="error" and MethodError arguments,
  ## serialise it, and verify the ["error", {"type": ...}, "c0"] wire format.
  {.cast(noSideEffect).}:
    let me = methodError("unknownMethod", Opt.some("No such method"))
    let inv =
      Invocation(name: "error", arguments: me.toJson(), methodCallId: makeMcid("c0"))
    let j = inv.toJson()
    # Wire format: 3-element JSON array
    doAssert j.kind == JArray
    assertEq j.len, 3
    let elems = j.getElems(@[])
    assertEq elems[0].getStr(""), "error"
    doAssert elems[1].kind == JObject
    assertEq elems[1]{"type"}.getStr(""), "unknownMethod"
    assertEq elems[1]{"description"}.getStr(""), "No such method"
    assertEq elems[2].getStr(""), "c0"
    # Round-trip: deserialise back to Invocation, then parse arguments as MethodError
    let rt = Invocation.fromJson(j)
    assertOk rt
    let rtInv = rt.get()
    assertEq rtInv.name, "error"
    assertEq rtInv.methodCallId, makeMcid("c0")
    let meRt = MethodError.fromJson(rtInv.arguments)
    assertOk meRt
    doAssert meRt.get().errorType == metUnknownMethod
    assertSomeEq meRt.get().description, "No such method"

block errorInvocationServerFailWireFormat:
  ## Error invocation with serverFail type and extras.
  {.cast(noSideEffect).}:
    let extras = newJObject()
    extras["retryAfter"] = %30
    let me = methodError("serverFail", Opt.some("Try again"), Opt.some(extras))
    let inv =
      Invocation(name: "error", arguments: me.toJson(), methodCallId: makeMcid("c5"))
    let j = inv.toJson()
    let elems = j.getElems(@[])
    assertEq elems[0].getStr(""), "error"
    assertEq elems[1]{"type"}.getStr(""), "serverFail"
    assertEq elems[1]{"retryAfter"}.getBiggestInt(0), 30
    assertEq elems[2].getStr(""), "c5"

# =============================================================================
# I. Phase 3F: Back-reference #-prefix integration test
# =============================================================================

block backReferenceHashPrefixRoundTrip:
  ## Construct a Request-like JSON with #-prefixed argument keys (Referencable
  ## fields), verify the # prefix appears in serialised JSON, and deserialise
  ## back to verify rkReference variant.
  {.cast(noSideEffect).}:
    # Build a method call with a #-prefixed argument containing a ResultReference
    let refObj = %*{"resultOf": "c0", "name": "Mailbox/query", "path": "/ids"}
    var args = newJObject()
    args["#ids"] = refObj
    let inv =
      Invocation(name: "Email/get", arguments: args, methodCallId: makeMcid("c1"))
    let req = Request(
      `using`: @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
      methodCalls: @[inv],
      createdIds: default(Opt[Table[CreationId, Id]]),
    )
    # Serialise the Request
    let j = req.toJson()
    let callsArr = j{"methodCalls"}
    doAssert callsArr != nil
    doAssert callsArr.kind == JArray
    let firstCall = callsArr.getElems(@[])[0]
    let callArgs = firstCall.getElems(@[])[1]
    # Verify the #-prefixed key is present in the serialised arguments
    doAssert callArgs{"#ids"} != nil, "#ids key must be present in serialised JSON"
    assertEq callArgs{"#ids"}{"resultOf"}.getStr(""), "c0"
    assertEq callArgs{"#ids"}{"name"}.getStr(""), "Mailbox/query"
    assertEq callArgs{"#ids"}{"path"}.getStr(""), "/ids"
    # Deserialise back — arguments are preserved as-is in Invocation
    let rtReq = Request.fromJson(j)
    assertOk rtReq
    let rtArgs = rtReq.get().methodCalls[0].arguments
    doAssert rtArgs{"#ids"} != nil
    # Parse the #-prefixed field as a Referencable
    let refResult = fromJsonField[int]("ids", rtArgs, fromDirectInt)
    assertOk refResult
    doAssert refResult.get().kind == rkReference
    assertEq refResult.get().reference.name, "Mailbox/query"
    assertEq refResult.get().reference.path, "/ids"
    assertEq refResult.get().reference.resultOf, makeMcid("c0")

# =============================================================================
# Phase 2C: Wire format golden tests (serialise then compare literal JSON)
# =============================================================================

block requestGoldenWireFormat:
  ## Construct a Request matching the RFC 8620 section 3.3.1 example, serialise
  ## it, and verify the output fields match the expected JSON structure.
  {.cast(noSideEffect).}:
    let args1 = %*{"arg1": "arg1data", "arg2": "arg2data"}
    let args2 = %*{"arg1": "arg1data"}
    let args3 = newJObject()
    let inv1 =
      Invocation(name: "method1", arguments: args1, methodCallId: makeMcid("c1"))
    let inv2 =
      Invocation(name: "method2", arguments: args2, methodCallId: makeMcid("c2"))
    let inv3 =
      Invocation(name: "method3", arguments: args3, methodCallId: makeMcid("c3"))
    let req = Request(
      `using`: @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
      methodCalls: @[inv1, inv2, inv3],
      createdIds: Opt.none(Table[CreationId, Id]),
    )
    let j = req.toJson()
    doAssert j{"using"} != nil
    doAssert j{"using"}.kind == JArray
    assertEq j{"using"}.getElems(@[]).len, 2
    assertEq j{"using"}.getElems(@[])[0].getStr(""), "urn:ietf:params:jmap:core"
    assertEq j{"using"}.getElems(@[])[1].getStr(""), "urn:ietf:params:jmap:mail"
    doAssert j{"methodCalls"} != nil
    doAssert j{"methodCalls"}.kind == JArray
    assertEq j{"methodCalls"}.getElems(@[]).len, 3
    let call0 = j{"methodCalls"}.getElems(@[])[0]
    doAssert call0.kind == JArray
    assertEq call0.getElems(@[]).len, 3
    assertEq call0.getElems(@[])[0].getStr(""), "method1"
    assertEq call0.getElems(@[])[1]{"arg1"}.getStr(""), "arg1data"
    assertEq call0.getElems(@[])[2].getStr(""), "c1"
    let call2 = j{"methodCalls"}.getElems(@[])[2]
    assertEq call2.getElems(@[])[0].getStr(""), "method3"
    assertEq call2.getElems(@[])[2].getStr(""), "c3"
    doAssert j{"createdIds"}.isNil

block responseGoldenWireFormat:
  ## Construct a Response matching the RFC 8620 section 3.4.1 example, serialise
  ## it, and verify the output fields match the expected JSON structure.
  {.cast(noSideEffect).}:
    let args1 = %*{"arg1": 3, "arg2": "foo"}
    let args2 = %*{"isBlah": true}
    let args3 = %*{"data": 10, "yetmoredata": "Hello"}
    let args4 = %*{"type": "unknownMethod"}
    let inv1 =
      Invocation(name: "method1", arguments: args1, methodCallId: makeMcid("c1"))
    let inv2 =
      Invocation(name: "method2", arguments: args2, methodCallId: makeMcid("c2"))
    let inv3 = Invocation(
      name: "anotherResponseFromMethod2", arguments: args3, methodCallId: makeMcid("c2")
    )
    let inv4 = Invocation(name: "error", arguments: args4, methodCallId: makeMcid("c3"))
    let resp = Response(
      methodResponses: @[inv1, inv2, inv3, inv4],
      sessionState: parseJmapState("75128aab4b1b").get(),
      createdIds: Opt.none(Table[CreationId, Id]),
    )
    let j = resp.toJson()
    doAssert j{"methodResponses"} != nil
    doAssert j{"methodResponses"}.kind == JArray
    assertEq j{"methodResponses"}.getElems(@[]).len, 4
    assertEq j{"sessionState"}.getStr(""), "75128aab4b1b"
    doAssert j{"createdIds"}.isNil
    let errInv = j{"methodResponses"}.getElems(@[])[3]
    doAssert errInv.kind == JArray
    assertEq errInv.getElems(@[])[0].getStr(""), "error"
    assertEq errInv.getElems(@[])[1]{"type"}.getStr(""), "unknownMethod"
    assertEq errInv.getElems(@[])[2].getStr(""), "c3"
