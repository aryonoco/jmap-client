# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for Layer 2 envelope serialisation: Invocation, Request, Response,
## ResultReference, and Referencable[T] dispatch tests.

import std/json
import std/random
import std/strutils
import std/tables

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

proc fromDirectInt(n: JsonNode): int {.raises: [].} =
  ## Parse a JSON integer for Referencable[int] tests.
  discard checkJsonKind(n, JInt, "int")
  n.getInt(0)

# Golden and valid Request/Response JSON fixtures are in mfixtures.nim:
# goldenRequestJson(), goldenResponseJson(), validRequestJson(), validResponseJson()

# =============================================================================
# A. Round-trip tests
# =============================================================================

block roundTripInvocation:
  let original = makeInvocation()
  assertOkEq Invocation.fromJson(original.toJson()), original

block roundTripInvocationComplexArguments:
  let args =
    %*{"accountId": "A1", "list": [1, 2, 3], "filter": {"nested": {"deep": newJNull()}}}
  let original = initInvocation("Email/get", args, makeMcid("c1"))
  let v = Invocation.fromJson(original.toJson()).get()
  doAssert v.name == original.name
  doAssert v.arguments == original.arguments
  doAssert v.methodCallId == original.methodCallId

block roundTripRequest:
  let original = makeRequest()
  let v = Request.fromJson(original.toJson()).get()
  assertEq v.`using`, original.`using`
  assertEq v.methodCalls.len, original.methodCalls.len
  doAssert v.createdIds.isNone == original.createdIds.isNone

block roundTripRequestWithCreatedIds:
  var tbl = initTable[CreationId, Id]()
  tbl[makeCreationId("k1")] = makeId("id1")
  tbl[makeCreationId("k2")] = makeId("id2")
  tbl[makeCreationId("k3")] = makeId("id3")
  let original = makeRequest(createdIds = Opt.some(tbl))
  let v = Request.fromJson(original.toJson()).get()
  doAssert v.createdIds.isSome
  assertEq v.createdIds.get().len, 3

block roundTripResponse:
  let original = makeResponse()
  let v = Response.fromJson(original.toJson()).get()
  assertEq v.methodResponses.len, original.methodResponses.len
  assertEq v.sessionState, original.sessionState
  doAssert v.createdIds.isNone == original.createdIds.isNone

block roundTripResponseWithCreatedIds:
  var tbl = initTable[CreationId, Id]()
  tbl[makeCreationId("k1")] = makeId("id1")
  tbl[makeCreationId("k2")] = makeId("id2")
  tbl[makeCreationId("k3")] = makeId("id3")
  let original = makeResponse(createdIds = Opt.some(tbl))
  let v = Response.fromJson(original.toJson()).get()
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
  let req = Request.fromJson(j).get()
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
  let v = Request.fromJson(first.toJson()).get()
  assertEq v.`using`, first.`using`
  assertEq v.methodCalls.len, first.methodCalls.len
  for i in 0 ..< v.methodCalls.len:
    assertEq v.methodCalls[i].name, first.methodCalls[i].name
    assertEq v.methodCalls[i].methodCallId, first.methodCalls[i].methodCallId

block responseDeserGoldenRfc:
  let j = goldenResponseJson()
  let resp = Response.fromJson(j).get()
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
  let v = Response.fromJson(first.toJson()).get()
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
  assertErr Invocation.fromJson(%*{"name": "x", "args": {}, "id": "c1"})

block invocationDeserTwoElements:
  assertErr Invocation.fromJson(%*["Mailbox/get", {}])

block invocationDeserFourElements:
  assertErr Invocation.fromJson(%*["Mailbox/get", {}, "c1", "extra"])

block invocationDeserIntMethodName:
  assertErr Invocation.fromJson(%*[42, {}, "c1"])

block invocationDeserStringArguments:
  assertErr Invocation.fromJson(%*["Mailbox/get", "notobject", "c1"])

block invocationDeserIntCallId:
  assertErr Invocation.fromJson(%*["Mailbox/get", {}, 42])

block invocationDeserEmptyMethodName:
  assertErrContains Invocation.fromJson(%*["", {}, "c1"]), "must not be empty"

block invocationDeserEmptyCallId:
  assertErrContains Invocation.fromJson(%*["Mailbox/get", {}, ""]), "must not be empty"

block invocationDeserNil:
  const nilNode: JsonNode = nil
  assertErr Invocation.fromJson(nilNode)

block invocationDeserJNull:
  assertErr Invocation.fromJson(newJNull())

# --- Request ---

block requestDeserMissingUsing:
  let j = %*{"methodCalls": [["Mailbox/get", {}, "c0"]]}
  assertErrContains Request.fromJson(j), "missing or invalid using"

block requestDeserMissingMethodCalls:
  let j = %*{"using": ["urn:ietf:params:jmap:core"]}
  assertErrContains Request.fromJson(j), "missing or invalid methodCalls"

block requestDeserUsingNotArray:
  let j =
    %*{"using": "urn:ietf:params:jmap:core", "methodCalls": [["Mailbox/get", {}, "c0"]]}
  assertErr Request.fromJson(j)

block requestDeserMethodCallsNotArray:
  let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": {}}
  assertErr Request.fromJson(j)

block requestDeserUsingElementNotString:
  let j = %*{"using": [42], "methodCalls": [["Mailbox/get", {}, "c0"]]}
  assertErrContains Request.fromJson(j), "using element must be string"

block requestDeserNotObject:
  assertErr Request.fromJson(%*[1, 2, 3])

block requestDeserNil:
  const nilNode: JsonNode = nil
  assertErr Request.fromJson(nilNode)

block requestDeserEmptyMethodCalls:
  let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": []}
  let r = Request.fromJson(j).get()
  assertEq r.methodCalls.len, 0

block requestDeserEmptyUsing:
  let j = %*{"using": [], "methodCalls": [["Mailbox/get", {}, "c0"]]}
  let r = Request.fromJson(j).get()
  assertEq r.`using`.len, 0

block requestDeserDeepInvalidInvocation:
  let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": [["", {}, "c0"]]}
  assertErrContains Request.fromJson(j), "must not be empty"

# --- Response ---

block responseDeserMissingMethodResponses:
  let j = %*{"sessionState": "s1"}
  assertErrContains Response.fromJson(j), "missing or invalid methodResponses"

block responseDeserMissingSessionState:
  let j = %*{"methodResponses": [["Mailbox/get", {}, "c0"]]}
  assertErrContains Response.fromJson(j), "missing or invalid sessionState"

block responseDeserMethodResponsesNotArray:
  let j = %*{"methodResponses": {}, "sessionState": "s1"}
  assertErr Response.fromJson(j)

block responseDeserSessionStateNotString:
  let j = %*{"methodResponses": [["Mailbox/get", {}, "c0"]], "sessionState": 42}
  assertErr Response.fromJson(j)

block responseDeserNotObject:
  assertErr Response.fromJson(%*[1, 2, 3])

block responseDeserNil:
  const nilNode: JsonNode = nil
  assertErr Response.fromJson(nilNode)

block responseDeserEmptyMethodResponses:
  let j = %*{"methodResponses": [], "sessionState": "s1"}
  let r = Response.fromJson(j).get()
  assertEq r.methodResponses.len, 0

block responseDeserDeepInvalidInvocation:
  let j = %*{"methodResponses": [["", {}, "c0"]], "sessionState": "s1"}
  assertErrContains Response.fromJson(j), "must not be empty"

# --- ResultReference ---

block resultReferenceDeserMissingResultOf:
  let j = %*{"name": "Mailbox/get", "path": "/ids"}
  assertErrContains ResultReference.fromJson(j), "missing or invalid resultOf"

block resultReferenceDeserMissingName:
  let j = %*{"resultOf": "c0", "path": "/ids"}
  assertErrContains ResultReference.fromJson(j), "missing or invalid name"

block resultReferenceDeserMissingPath:
  let j = %*{"resultOf": "c0", "name": "Mailbox/get"}
  assertErrContains ResultReference.fromJson(j), "missing or invalid path"

block resultReferenceDeserEmptyName:
  let j = %*{"resultOf": "c0", "name": "", "path": "/ids"}
  assertErrContains ResultReference.fromJson(j), "must not be empty"

block resultReferenceDeserEmptyPath:
  let j = %*{"resultOf": "c0", "name": "Mailbox/get", "path": ""}
  assertErrContains ResultReference.fromJson(j), "must not be empty"

block resultReferenceDeserNotObject:
  assertErr ResultReference.fromJson(%*[1, 2, 3])

block resultReferenceDeserNil:
  const nilNode: JsonNode = nil
  assertErr ResultReference.fromJson(nilNode)

# --- createdIds (tested on Request) ---

block createdIdsAbsentKey:
  let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": []}
  let r = Request.fromJson(j).get()
  doAssert r.createdIds.isNone

block createdIdsJNull:
  var j = validRequestJson()
  j["createdIds"] = newJNull()
  let r = Request.fromJson(j).get()
  doAssert r.createdIds.isNone

block createdIdsEmptyObject:
  var j = validRequestJson()
  j["createdIds"] = newJObject()
  let r = Request.fromJson(j).get()
  doAssert r.createdIds.isSome
  assertEq r.createdIds.get().len, 0

block createdIdsPopulatedObject:
  var j = validRequestJson()
  j["createdIds"] = %*{"k1": "id1", "k2": "id2", "k3": "id3"}
  let r = Request.fromJson(j).get()
  doAssert r.createdIds.isSome
  assertEq r.createdIds.get().len, 3

block createdIdsWrongKindArray:
  var j = validRequestJson()
  j["createdIds"] = %*[1, 2]
  assertErrContains Request.fromJson(j), "createdIds must be object or null"

block createdIdsWrongKindString:
  var j = validRequestJson()
  j["createdIds"] = %"not-an-object"
  assertErr Request.fromJson(j)

block createdIdsValueNotString:
  var j = validRequestJson()
  j["createdIds"] = %*{"k1": 42}
  assertErrContains Request.fromJson(j), "createdIds value must be string"

block createdIdsKeyStartsWithHash:
  var j = validRequestJson()
  j["createdIds"] = %*{"#k1": "id1"}
  assertErr Request.fromJson(j)

block createdIdsCreationIdHashPrefixInRequest:
  ## CreationId keys starting with '#' must be rejected by parseCreationId.
  ## Verifies the error propagates through parseCreatedIds up to Request.fromJson.
  var j = validRequestJson()
  j["createdIds"] = %*{"#invalid": "id1"}
  assertErr Request.fromJson(j)

block createdIdsKeyEmpty:
  var j = validRequestJson()
  j["createdIds"] = %*{"": "id1"}
  assertErr Request.fromJson(j)

block createdIdsValueEmpty:
  var j = validRequestJson()
  j["createdIds"] = %*{"k1": ""}
  assertErr Request.fromJson(j)

block responseCreatedIdsSameSemantics:
  var j = validResponseJson()
  j["createdIds"] = %*{"k1": "id1"}
  let r = Response.fromJson(j).get()
  doAssert r.createdIds.isSome
  assertEq r.createdIds.get().len, 1

# =============================================================================
# E. Referencable[T] dispatch tests
# =============================================================================

block referencableDirectValue:
  let node = %*{"ids": 42}
  let v = fromJsonField[int]("ids", node, fromDirectInt).get()
  doAssert v.kind == rkDirect
  assertEq v.value, 42

block referencableReferenceValue:
  let node = %*{"#ids": {"resultOf": "c0", "name": "Mailbox/query", "path": "/ids"}}
  let v = fromJsonField[int]("ids", node, fromDirectInt).get()
  doAssert v.kind == rkReference
  assertEq v.reference.name, "Mailbox/query"
  assertEq v.reference.path, "/ids"
  assertEq v.reference.resultOf, parseMethodCallId("c0").get()

block referencableBothPresentConflictRejected:
  ## RFC 8620 section 3.7: both direct and referenced forms present must be rejected.
  let node =
    %*{"ids": 42, "#ids": {"resultOf": "c0", "name": "Mailbox/query", "path": "/ids"}}
  assertErrContains fromJsonField[int]("ids", node, fromDirectInt),
    "cannot specify both"

block referencableMissingBothKeys:
  let node = %*{"other": 99}
  assertErrContains fromJsonField[int]("ids", node, fromDirectInt), "missing field"

block referencableHashKeyWrongKind:
  let nodeStr = %*{"#ids": "x"}
  assertErr fromJsonField[int]("ids", nodeStr, fromDirectInt)
  let nodeInt = %*{"#ids": 42}
  assertErr fromJsonField[int]("ids", nodeInt, fromDirectInt)

block referencableHashKeyMissingResultOf:
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
  let v = Invocation.fromJson(inv.toJson()).get()
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
  let v = Request.fromJson(req.toJson()).get()
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
  let v = Response.fromJson(resp.toJson()).get()
  doAssert v.methodResponses.len == resp.methodResponses.len
  doAssert v.sessionState == resp.sessionState
  doAssert v.createdIds.isNone == resp.createdIds.isNone

# =============================================================================
# G. Additional edge-case and round-trip tests
# =============================================================================

block invocationComplexNestedArgsRoundTrip:
  ## Deep nesting (3+ levels), arrays of objects, null values in arguments.
  let args = %*{
    "filter": {
      "operator": "AND",
      "conditions": [{"subject": "test"}, {"nested": {"deep": {"value": [1, 2, nil]}}}],
    },
    "nullField": nil,
    "emptyArray": [],
  }
  let inv = initInvocation("Email/query", args, makeMcid("c1"))
  let v = Invocation.fromJson(inv.toJson()).get()
  assertEq v.name, "Email/query"
  assertEq v.methodCallId, makeMcid("c1")
  # Verify complex arguments survived
  doAssert v.arguments{"filter"} != nil
  doAssert v.arguments{"filter"}{"conditions"} != nil
  doAssert v.arguments{"nullField"} != nil
  doAssert v.arguments{"nullField"}.kind == JNull

block requestRoundTripWithCreatedIds:
  ## Verify CreationId keys and Id values survive toJson/fromJson cycle.
  var tbl = initTable[CreationId, Id]()
  tbl[makeCreationId("k1")] = makeId("id1")
  tbl[makeCreationId("k2")] = makeId("id2")
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core"],
    methodCalls: @[makeInvocation()],
    createdIds: Opt.some(tbl),
  )
  let v = Request.fromJson(req.toJson()).get()
  assertSome v.createdIds
  let rtTbl = v.createdIds.get()
  assertEq rtTbl.len, 2

block responseRoundTripAllFields:
  ## methodResponses + sessionState + createdIds all present.
  var tbl = initTable[CreationId, Id]()
  tbl[makeCreationId("new0")] = makeId("created0")
  let resp = Response(
    methodResponses: @[makeInvocation(), makeInvocation("Email/set", makeMcid("c2"))],
    sessionState: makeState("s42"),
    createdIds: Opt.some(tbl),
  )
  let v = Response.fromJson(resp.toJson()).get()
  assertLen v.methodResponses, 2
  assertEq v.sessionState, makeState("s42")
  assertSome v.createdIds

block fromJsonFieldRefInvalidResultOf:
  ## #ids key present but resultOf is empty — error must propagate.
  let node = %*{"#ids": {"resultOf": "", "name": "Mailbox/get", "path": "/ids"}}
  assertErr fromJsonField[int]("ids", node, fromDirectInt)

block referencableFromJsonFieldMalformedReference:
  ## When a '#'-prefixed key contains a malformed ResultReference (non-string
  ## resultOf), the error must propagate through fromJsonField.
  let node = %*{"#ids": {"resultOf": 42, "name": "Mailbox/get", "path": "/ids"}}
  assertErrContains fromJsonField[int]("ids", node, fromDirectInt),
    "missing or invalid resultOf"

block requestEmptyMethodCalls:
  ## Empty methodCalls array round-trips correctly.
  let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": []}
  let r = Request.fromJson(j).get()
  assertLen r.methodCalls, 0
  assertLen r.`using`, 1

block requestEmptyUsingArray:
  ## Empty using array is valid per JSON schema.
  let j = %*{"using": [], "methodCalls": []}
  let r = Request.fromJson(j).get()
  assertLen r.`using`, 0

# =============================================================================
# H. Phase 3E: Error invocation wire format
# =============================================================================

block errorInvocationWireFormat:
  ## Construct an Invocation with name="error" and MethodError arguments,
  ## serialise it, and verify the ["error", {"type": ...}, "c0"] wire format.
  let me = methodError("unknownMethod", Opt.some("No such method"))
  let inv = initInvocation("error", me.toJson(), makeMcid("c0"))
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
  let rtInv = Invocation.fromJson(j).get()
  assertEq rtInv.name, "error"
  assertEq rtInv.methodCallId, makeMcid("c0")
  let meRt = MethodError.fromJson(rtInv.arguments).get()
  doAssert meRt.errorType == metUnknownMethod
  assertSomeEq meRt.description, "No such method"

block errorInvocationServerFailWireFormat:
  ## Error invocation with serverFail type and extras.
  let extras = newJObject()
  extras["retryAfter"] = %30
  let me = methodError("serverFail", Opt.some("Try again"), Opt.some(extras))
  let inv = initInvocation("error", me.toJson(), makeMcid("c5"))
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
  # Build a method call with a #-prefixed argument containing a ResultReference
  let refObj = %*{"resultOf": "c0", "name": "Mailbox/query", "path": "/ids"}
  var args = newJObject()
  args["#ids"] = refObj
  let inv = initInvocation("Email/get", args, makeMcid("c1"))
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
    methodCalls: @[inv],
    createdIds: Opt.none(Table[CreationId, Id]),
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
  let rtReq = Request.fromJson(j).get()
  let rtArgs = rtReq.methodCalls[0].arguments
  doAssert rtArgs{"#ids"} != nil
  # Parse the #-prefixed field as a Referencable
  let refResult = fromJsonField[int]("ids", rtArgs, fromDirectInt).get()
  doAssert refResult.kind == rkReference
  assertEq refResult.reference.name, "Mailbox/query"
  assertEq refResult.reference.path, "/ids"
  assertEq refResult.reference.resultOf, makeMcid("c0")

# =============================================================================
# Phase 2C: Wire format golden tests (serialise then compare literal JSON)
# =============================================================================

block requestGoldenWireFormat:
  ## Construct a Request matching the RFC 8620 section 3.3.1 example, serialise
  ## it, and verify the output fields match the expected JSON structure.
  let args1 = %*{"arg1": "arg1data", "arg2": "arg2data"}
  let args2 = %*{"arg1": "arg1data"}
  let args3 = newJObject()
  let inv1 = initInvocation("method1", args1, makeMcid("c1"))
  let inv2 = initInvocation("method2", args2, makeMcid("c2"))
  let inv3 = initInvocation("method3", args3, makeMcid("c3"))
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
  let args1 = %*{"arg1": 3, "arg2": "foo"}
  let args2 = %*{"isBlah": true}
  let args3 = %*{"data": 10, "yetmoredata": "Hello"}
  let args4 = %*{"type": "unknownMethod"}
  let inv1 = initInvocation("method1", args1, makeMcid("c1"))
  let inv2 = initInvocation("method2", args2, makeMcid("c2"))
  let inv3 = initInvocation("anotherResponseFromMethod2", args3, makeMcid("c2"))
  let inv4 = initInvocation("error", args4, makeMcid("c3"))
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
