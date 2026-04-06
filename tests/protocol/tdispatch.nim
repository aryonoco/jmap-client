# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## ResponseHandle extraction tests: get[T], error detection, validation
## error conversion, reference construction, and borrowed operations.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/types
import jmap_client/serialisation
import jmap_client/entity
import jmap_client/methods
import jmap_client/dispatch

import ../massertions
import ../mfixtures

# ---------------------------------------------------------------------------
# Mock entity types (local -- compile-time verification only)
# ---------------------------------------------------------------------------

{.push ruleOff: "hasDoc".}
{.push ruleOff: "objects".}
{.push ruleOff: "params".}

type MockFoo = object

proc methodNamespace*(T: typedesc[MockFoo]): string =
  "MockFoo"

proc capabilityUri*(T: typedesc[MockFoo]): string =
  "urn:test:mockfoo"

registerJmapEntity(MockFoo)

type MockFilter = object

type MockQueryable = object

proc methodNamespace*(T: typedesc[MockQueryable]): string =
  "MockQueryable"

proc capabilityUri*(T: typedesc[MockQueryable]): string =
  "urn:test:mockqueryable"

template filterType*(T: typedesc[MockQueryable]): typedesc =
  MockFilter

registerJmapEntity(MockQueryable)
registerQueryableEntity(MockQueryable)

{.pop.} # params
{.pop.} # objects
{.pop.} # hasDoc

# ===========================================================================
# A. Handle operations
# ===========================================================================

block handleEquality:
  ## Two handles with the same call ID are equal.
  let h1 = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let h2 = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  doAssert h1 == h2

block handleToString:
  ## String representation produces the call ID string.
  let h = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  doAssert $h == "c0"

block handleHash:
  ## Hash is consistent with equality.
  let h1 = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let h2 = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  doAssert hash(h1) == hash(h2)

block callIdAccessor:
  ## callId returns the underlying MethodCallId.
  let mcid = makeMcid("c0")
  let h = ResponseHandle[GetResponse[MockFoo]](mcid)
  doAssert callId(h) == mcid

# ===========================================================================
# B. get[T] happy path (callback overload)
# ===========================================================================

block getHappyPath:
  ## Response with valid GetResponse JSON at c0, get with callback returns ok.
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], ValidationError] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = resp.get(handle, fromGetResponse)
  assertOk result

block getExtractsCorrectInvocation:
  ## Response with multiple invocations (c0, c1); handle c1 extracts the right one.
  let inv0 =
    initInvocation("MockFoo/get", makeGetResponseJson("acct0", "s0"), makeMcid("c0"))
  let inv1 =
    initInvocation("MockFoo/get", makeGetResponseJson("acct1", "s1"), makeMcid("c1"))
  let resp = Response(
    methodResponses: @[inv0, inv1],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c1"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], ValidationError] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = resp.get(handle, fromGetResponse)
  assertOk result
  let gr = result.get()
  doAssert gr.accountId == makeAccountId("acct1")
  doAssert gr.state == makeState("s1")

# ===========================================================================
# C. get[T] error cases (callback overload)
# ===========================================================================

block getNotFound:
  ## Call ID c99 not in response produces err with metServerFail.
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c99"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], ValidationError] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = resp.get(handle, fromGetResponse)
  assertErr result
  doAssert result.error().errorType == metServerFail

block getMethodError:
  ## Invocation name is "error" with type "unknownMethod" produces err with metUnknownMethod.
  let resp = makeErrorResponse("unknownMethod", makeMcid("c0"))
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], ValidationError] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = resp.get(handle, fromGetResponse)
  assertErr result
  doAssert result.error().errorType == metUnknownMethod
  doAssert result.error().rawType == "unknownMethod"

block getMalformedErrorResponse:
  ## Error invocation with non-object arguments produces err with metServerFail.
  let malformedInv = initInvocation("error", newJArray(), makeMcid("c0"))
  let resp = Response(
    methodResponses: @[malformedInv],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], ValidationError] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = resp.get(handle, fromGetResponse)
  assertErr result
  doAssert result.error().errorType == metServerFail

block getValidationError:
  ## fromArgs returns err(ValidationError) which is converted to MethodError with metServerFail.
  let resp = makeTypedResponse("MockFoo/get", %*{"invalid": true}, makeMcid("c0"))
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], ValidationError] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = resp.get(handle, fromGetResponse)
  assertErr result
  let me = result.error()
  doAssert me.errorType == metServerFail
  doAssert me.extras.isSome
  let extras = me.extras.get()
  doAssert extras.kind == JObject
  doAssert extras{"typeName"} != nil
  doAssert extras{"value"} != nil

# ===========================================================================
# D. get[T] for Echo (JsonNode) with callback
# ===========================================================================

block getEchoHappyPath:
  ## Response with Core/echo invocation, trivial fromArgs callback returns ok(JsonNode).
  let echoArgs = %*{"tag": "hello"}
  let resp = makeTypedResponse("Core/echo", echoArgs, makeMcid("c0"))
  let handle = ResponseHandle[JsonNode](makeMcid("c0"))
  let echoParser = proc(
      n: JsonNode
  ): Result[JsonNode, ValidationError] {.noSideEffect, raises: [].} =
    ok(n)
  let result = resp.get(handle, echoParser)
  assertOk result
  doAssert result.get(){"tag"}.getStr("") == "hello"

# ===========================================================================
# E. validationToMethodError
# ===========================================================================

block validationToMethodErrorPreservation:
  ## Verify errorType is metServerFail, description contains the validation
  ## message, and extras is a JObject containing typeName and value keys.
  let ve = validationError("AccountId", "length must be 1-255 octets", "")
  let me = validationToMethodError(ve)
  doAssert me.errorType == metServerFail
  doAssert me.rawType == "serverFail"
  doAssert me.description.isSome
  doAssert me.description.get() == "length must be 1-255 octets"
  doAssert me.extras.isSome
  let extras = me.extras.get()
  doAssert extras.kind == JObject
  doAssert extras{"typeName"}.getStr("") == "AccountId"
  doAssert extras{"value"}.getStr("?") == ""

# ===========================================================================
# F. Type-safe reference functions
# ===========================================================================

block idsRefOnQueryHandle:
  ## ResponseHandle[QueryResponse[MockQueryable]] produces Referencable with
  ## path /ids and name MockQueryable/query.
  let handle = ResponseHandle[QueryResponse[MockQueryable]](makeMcid("c0"))
  let r = idsRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == RefPathIds
  doAssert r.reference.name == "MockQueryable/query"
  doAssert r.reference.resultOf == makeMcid("c0")

block listIdsRefOnGetHandle:
  ## ResponseHandle[GetResponse[MockFoo]] produces Referencable with
  ## path /list/*/id and name MockFoo/get.
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let r = listIdsRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == RefPathListIds
  doAssert r.reference.name == "MockFoo/get"
  doAssert r.reference.resultOf == makeMcid("c0")

block addedIdsRefOnQueryChangesHandle:
  ## ResponseHandle[QueryChangesResponse[MockQueryable]] produces Referencable
  ## with path /added/*/id and name MockQueryable/queryChanges.
  let handle = ResponseHandle[QueryChangesResponse[MockQueryable]](makeMcid("c0"))
  let r = addedIdsRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == RefPathAddedIds
  doAssert r.reference.name == "MockQueryable/queryChanges"
  doAssert r.reference.resultOf == makeMcid("c0")

block idsRefRejectsGetHandle:
  ## A GetResponse handle cannot call idsRef (type-safe rejection).
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  assertNotCompiles idsRef(handle)

block listIdsRefRejectsQueryHandle:
  ## A QueryResponse handle cannot call listIdsRef (type-safe rejection).
  let handle = ResponseHandle[QueryResponse[MockQueryable]](makeMcid("c0"))
  assertNotCompiles listIdsRef(handle)

# ===========================================================================
# G. Generic reference (escape hatch)
# ===========================================================================

block referenceConstruction:
  ## Generic reference produces correct ResultReference with matching fields.
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let rr = reference(handle, "Foo/query", "/ids")
  doAssert rr.resultOf == makeMcid("c0")
  doAssert rr.name == "Foo/query"
  doAssert rr.path == "/ids"
