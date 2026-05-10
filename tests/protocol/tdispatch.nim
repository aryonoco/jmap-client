# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## ResponseHandle extraction tests: get[T], error detection, validation
## error conversion, reference construction, and borrowed operations.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/types
import jmap_client/serialisation
import jmap_client/internal/protocol/entity
import jmap_client/internal/protocol/methods
import jmap_client/internal/protocol/dispatch

import ../massertions
import ../mfixtures

# ---------------------------------------------------------------------------
# Mock entity types (local -- compile-time verification only)
# ---------------------------------------------------------------------------

{.push ruleOff: "hasDoc".}
{.push ruleOff: "objects".}
{.push ruleOff: "params".}

type MockFoo = object

proc methodEntity*(T: typedesc[MockFoo]): MethodEntity =
  meTest

proc capabilityUri*(T: typedesc[MockFoo]): string =
  "urn:test:mockfoo"

proc getMethodName*(T: typedesc[MockFoo]): MethodName =
  ## Aliased to mnMailboxGet; the dispatch tests exercise handle-type
  ## discrimination, not the specific wire name. Production entities
  ## register their own distinct MethodName variants.
  mnMailboxGet

proc changesMethodName*(T: typedesc[MockFoo]): MethodName =
  mnMailboxChanges

registerJmapEntity(MockFoo)

type MockFilter = object

type MockQueryable = object

proc methodEntity*(T: typedesc[MockQueryable]): MethodEntity =
  meTest

proc capabilityUri*(T: typedesc[MockQueryable]): string =
  "urn:test:mockqueryable"

proc queryMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnEmailQuery

proc queryChangesMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnEmailQueryChanges

template filterType*(T: typedesc[MockQueryable]): typedesc =
  MockFilter

func toJson(c: MockFilter): JsonNode =
  newJObject()

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
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = resp.get(handle, fromGetResponse)
  assertOk result

block getExtractsCorrectInvocation:
  ## Response with multiple invocations (c0, c1); handle c1 extracts the right one.
  let inv0 =
    initInvocation(mnMailboxGet, makeGetResponseJson("acct0", "s0"), makeMcid("c0"))
  let inv1 =
    initInvocation(mnMailboxGet, makeGetResponseJson("acct1", "s1"), makeMcid("c1"))
  let resp = Response(
    methodResponses: @[inv0, inv1],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c1"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
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
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
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
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = resp.get(handle, fromGetResponse)
  assertErr result
  doAssert result.error().errorType == metUnknownMethod
  doAssert result.error().rawType == "unknownMethod"

block getMalformedErrorResponse:
  ## Error invocation with non-object arguments produces err with metServerFail.
  let malformedInv = parseInvocation("error", newJArray(), makeMcid("c0")).get()
  let resp = Response(
    methodResponses: @[malformedInv],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
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
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
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
  ): Result[JsonNode, SerdeViolation] {.noSideEffect, raises: [].} =
    ok(n)
  let result = resp.get(handle, echoParser)
  assertOk result
  doAssert result.get(){"tag"}.getStr("") == "hello"

# ===========================================================================
# F. Type-safe reference functions
# ===========================================================================

block idsRefOnQueryHandle:
  ## ResponseHandle[QueryResponse[MockQueryable]] produces Referencable with
  ## path /ids. The mock's queryMethodName resolves to mnEmailQuery.
  let handle = ResponseHandle[QueryResponse[MockQueryable]](makeMcid("c0"))
  let r = idsRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == rpIds
  doAssert r.reference.name == mnEmailQuery
  doAssert r.reference.resultOf == makeMcid("c0")

block listIdsRefOnGetHandle:
  ## ResponseHandle[GetResponse[MockFoo]] produces Referencable with
  ## path /list/*/id. The mock's getMethodName resolves to mnMailboxGet.
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let r = listIdsRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == rpListIds
  doAssert r.reference.name == mnMailboxGet
  doAssert r.reference.resultOf == makeMcid("c0")

block addedIdsRefOnQueryChangesHandle:
  ## ResponseHandle[QueryChangesResponse[MockQueryable]] produces Referencable
  ## with path /added/*/id. queryChangesMethodName resolves to mnEmailQueryChanges.
  let handle = ResponseHandle[QueryChangesResponse[MockQueryable]](makeMcid("c0"))
  let r = addedIdsRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == rpAddedIds
  doAssert r.reference.name == mnEmailQueryChanges
  doAssert r.reference.resultOf == makeMcid("c0")

block idsRefRejectsGetHandle:
  ## A GetResponse handle cannot call idsRef (type-safe rejection).
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  assertNotCompiles idsRef(handle)

block listIdsRefRejectsQueryHandle:
  ## A QueryResponse handle cannot call listIdsRef (type-safe rejection).
  let handle = ResponseHandle[QueryResponse[MockQueryable]](makeMcid("c0"))
  assertNotCompiles listIdsRef(handle)

block createdRefOnChangesHandle:
  ## ResponseHandle[ChangesResponse[MockFoo]] produces Referencable with
  ## path /created. changesMethodName resolves to mnMailboxChanges.
  let handle = ResponseHandle[ChangesResponse[MockFoo]](makeMcid("c0"))
  let r = createdRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == rpCreated
  doAssert r.reference.name == mnMailboxChanges
  doAssert r.reference.resultOf == makeMcid("c0")

block updatedRefOnChangesHandle:
  ## ResponseHandle[ChangesResponse[MockFoo]] produces Referencable with
  ## path /updated. changesMethodName resolves to mnMailboxChanges.
  let handle = ResponseHandle[ChangesResponse[MockFoo]](makeMcid("c0"))
  let r = updatedRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == rpUpdated
  doAssert r.reference.name == mnMailboxChanges
  doAssert r.reference.resultOf == makeMcid("c0")

block createdRefRejectsGetHandle:
  ## A GetResponse handle cannot call createdRef (type-safe rejection).
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  assertNotCompiles createdRef(handle)

block createdRefRejectsQueryHandle:
  ## A QueryResponse handle cannot call createdRef (type-safe rejection).
  let handle = ResponseHandle[QueryResponse[MockQueryable]](makeMcid("c0"))
  assertNotCompiles createdRef(handle)

block updatedRefRejectsSetHandle:
  ## A SetResponse handle cannot call updatedRef (type-safe rejection).
  let handle = ResponseHandle[SetResponse[MockFoo]](makeMcid("c0"))
  assertNotCompiles updatedRef(handle)

# ===========================================================================
# G. Generic reference (escape hatch)
# ===========================================================================

block referenceConstruction:
  ## Generic reference produces correct ResultReference with matching fields.
  let handle = ResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let rr = reference(handle, mnEmailQuery, rpIds)
  doAssert rr.resultOf == makeMcid("c0")
  doAssert rr.name == mnEmailQuery
  doAssert rr.path == rpIds
