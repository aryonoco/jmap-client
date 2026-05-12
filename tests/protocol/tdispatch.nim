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

proc capabilityUri*(T: typedesc[MockFoo]): CapabilityUri =
  parseCapabilityUri("urn:test:mockfoo").get()

proc getMethodName*(T: typedesc[MockFoo]): MethodName =
  ## Aliased to mnMailboxGet; the dispatch tests exercise handle-type
  ## discrimination, not the specific wire name. Production entities
  ## register their own distinct MethodName variants.
  mnMailboxGet

proc changesMethodName*(T: typedesc[MockFoo]): MethodName =
  mnMailboxChanges

func fromJson*(
    T: typedesc[MockFoo], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[MockFoo, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  ok(MockFoo())

registerJmapEntity(MockFoo)

type MockFilter = object

type MockQueryable = object

proc methodEntity*(T: typedesc[MockQueryable]): MethodEntity =
  meTest

proc capabilityUri*(T: typedesc[MockQueryable]): CapabilityUri =
  parseCapabilityUri("urn:test:mockqueryable").get()

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
  ## Two handles with the same call ID and brand are equal.
  let h1 = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let h2 = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  doAssert h1 == h2

block handleToString:
  ## String representation produces the call ID string.
  let h = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  doAssert $h == "c0"

block handleHash:
  ## Hash is consistent with equality.
  let h1 = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let h2 = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  doAssert hash(h1) == hash(h2)

block callIdAccessor:
  ## callId returns the underlying MethodCallId.
  let mcid = makeMcid("c0")
  let h = makeResponseHandle[GetResponse[MockFoo]](mcid)
  doAssert callId(h) == mcid

# ===========================================================================
# B. get[T] happy path (callback overload)
# ===========================================================================

block getHappyPath:
  ## Response with valid GetResponse JSON at c0, get with callback returns ok.
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = dr.get(handle, fromGetResponse)
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
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c1"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = dr.get(handle, fromGetResponse)
  assertOk result
  let gr = result.get()
  doAssert gr.accountId == makeAccountId("acct1")
  doAssert gr.state == makeState("s1")

# ===========================================================================
# C. get[T] error cases (callback overload)
# ===========================================================================

block getNotFound:
  ## Call ID c99 not in response produces err(gekMethod) with metServerFail.
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c99"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = dr.get(handle, fromGetResponse)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekMethod
  doAssert ge.methodErr.errorType == metServerFail

block getMethodError:
  ## Invocation name is "error" with type "unknownMethod" produces err(gekMethod)
  ## carrying metUnknownMethod.
  let resp = makeErrorResponse("unknownMethod", makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = dr.get(handle, fromGetResponse)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekMethod
  doAssert ge.methodErr.errorType == metUnknownMethod
  doAssert ge.methodErr.rawType == "unknownMethod"

block getMalformedErrorResponse:
  ## Error invocation with non-object arguments produces err(gekMethod) with metServerFail.
  let malformedInv = parseInvocation("error", newJArray(), makeMcid("c0")).get()
  let resp = Response(
    methodResponses: @[malformedInv],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = dr.get(handle, fromGetResponse)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekMethod
  doAssert ge.methodErr.errorType == metServerFail

block getValidationError:
  ## fromArgs returns err(ValidationError) which is converted to MethodError with metServerFail,
  ## then lifted to GetError(gekMethod).
  let resp = makeTypedResponse("MockFoo/get", %*{"invalid": true}, makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = dr.get(handle, fromGetResponse)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekMethod
  let me = ge.methodErr
  doAssert me.errorType == metServerFail
  doAssert me.extras.isSome
  let extras = me.extras.get()
  doAssert extras.kind == JObject
  doAssert extras{"typeName"} != nil
  doAssert extras{"value"} != nil

block getHandleMismatch:
  ## A handle issued by builder A applied to a DispatchedResponse from
  ## builder B returns err(gekHandleMismatch) with the two brands and
  ## the handle's callId in the diagnostic payload.
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let drBrand = makeBuilderId(0x1234'u64, 1'u64)
  let handleBrand = makeBuilderId(0x1234'u64, 2'u64) # same client, different serial
  let dr = makeDispatchedResponse(resp, drBrand)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"), handleBrand)
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = dr.get(handle, fromGetResponse)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekHandleMismatch
  doAssert ge.expected == drBrand
  doAssert ge.actual == handleBrand
  doAssert ge.callId == makeMcid("c0")

block getHandleMismatchCrossBuilderSameClient:
  ## A6 — cross-builder within the same JmapClient. Two newBuilder() calls
  ## mint serial=0 and serial=1 sharing the same clientBrand; a handle
  ## from the first builder applied to the second's dispatched response
  ## returns err(gekHandleMismatch) with differing serial halves but
  ## matching clientBrand. Mirrors the failure mode the A6 brand check
  ## was designed to catch.
  const clientBrand = 0x9ABCDEF012345678'u64
  let bid0 = makeBuilderId(clientBrand, 0'u64) # first newBuilder()
  let bid1 = makeBuilderId(clientBrand, 1'u64) # second newBuilder()
  doAssert bid0.clientBrand == bid1.clientBrand
  doAssert bid0.serial != bid1.serial
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let dr = makeDispatchedResponse(resp, bid1)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"), bid0)
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = dr.get(handle, fromGetResponse)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekHandleMismatch
  doAssert ge.expected.clientBrand == clientBrand
  doAssert ge.actual.clientBrand == clientBrand
  doAssert ge.expected.serial == 1'u64
  doAssert ge.actual.serial == 0'u64

block getHandleMismatchCrossClient:
  ## A6 — cross-client across two JmapClient instances. Each client
  ## draws its own random clientBrand at init; a handle from client A's
  ## builder applied to a DispatchedResponse from client B returns
  ## err(gekHandleMismatch) with differing clientBrand halves. Models
  ## the multi-account email client scenario the composite brand was
  ## designed to catch.
  let bidA = makeBuilderId(0xAAAA_AAAA_AAAA_AAAA'u64, 0'u64) # client A's first builder
  let bidB = makeBuilderId(0xBBBB_BBBB_BBBB_BBBB'u64, 0'u64) # client B's first builder
  doAssert bidA.clientBrand != bidB.clientBrand
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let dr = makeDispatchedResponse(resp, bidB) # response from client B
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"), bidA)
  let fromGetResponse = proc(
      n: JsonNode
  ): Result[GetResponse[MockFoo], SerdeViolation] {.noSideEffect, raises: [].} =
    GetResponse[MockFoo].fromJson(n)
  let result = dr.get(handle, fromGetResponse)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekHandleMismatch
  doAssert ge.expected.clientBrand == 0xBBBB_BBBB_BBBB_BBBB'u64
  doAssert ge.actual.clientBrand == 0xAAAA_AAAA_AAAA_AAAA'u64

# ===========================================================================
# D. get[T] for Echo (JsonNode) with callback
# ===========================================================================

block getEchoHappyPath:
  ## Response with Core/echo invocation, trivial fromArgs callback returns ok(JsonNode).
  let echoArgs = %*{"tag": "hello"}
  let resp = makeTypedResponse("Core/echo", echoArgs, makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[JsonNode](makeMcid("c0"))
  let echoParser = proc(
      n: JsonNode
  ): Result[JsonNode, SerdeViolation] {.noSideEffect, raises: [].} =
    ok(n)
  let result = dr.get(handle, echoParser)
  assertOk result
  doAssert result.get(){"tag"}.getStr("") == "hello"

# ===========================================================================
# F. Type-safe reference functions
# ===========================================================================

block idsRefOnQueryHandle:
  ## ResponseHandle[QueryResponse[MockQueryable]] produces Referencable with
  ## path /ids. The mock's queryMethodName resolves to mnEmailQuery.
  let handle = makeResponseHandle[QueryResponse[MockQueryable]](makeMcid("c0"))
  let r = idsRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == rpIds
  doAssert r.reference.name == mnEmailQuery
  doAssert r.reference.resultOf == makeMcid("c0")

block listIdsRefOnGetHandle:
  ## ResponseHandle[GetResponse[MockFoo]] produces Referencable with
  ## path /list/*/id. The mock's getMethodName resolves to mnMailboxGet.
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let r = listIdsRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == rpListIds
  doAssert r.reference.name == mnMailboxGet
  doAssert r.reference.resultOf == makeMcid("c0")

block addedIdsRefOnQueryChangesHandle:
  ## ResponseHandle[QueryChangesResponse[MockQueryable]] produces Referencable
  ## with path /added/*/id. queryChangesMethodName resolves to mnEmailQueryChanges.
  let handle = makeResponseHandle[QueryChangesResponse[MockQueryable]](makeMcid("c0"))
  let r = addedIdsRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == rpAddedIds
  doAssert r.reference.name == mnEmailQueryChanges
  doAssert r.reference.resultOf == makeMcid("c0")

block idsRefRejectsGetHandle:
  ## A GetResponse handle cannot call idsRef (type-safe rejection).
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  assertNotCompiles idsRef(handle)

block listIdsRefRejectsQueryHandle:
  ## A QueryResponse handle cannot call listIdsRef (type-safe rejection).
  let handle = makeResponseHandle[QueryResponse[MockQueryable]](makeMcid("c0"))
  assertNotCompiles listIdsRef(handle)

block createdRefOnChangesHandle:
  ## ResponseHandle[ChangesResponse[MockFoo]] produces Referencable with
  ## path /created. changesMethodName resolves to mnMailboxChanges.
  let handle = makeResponseHandle[ChangesResponse[MockFoo]](makeMcid("c0"))
  let r = createdRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == rpCreated
  doAssert r.reference.name == mnMailboxChanges
  doAssert r.reference.resultOf == makeMcid("c0")

block updatedRefOnChangesHandle:
  ## ResponseHandle[ChangesResponse[MockFoo]] produces Referencable with
  ## path /updated. changesMethodName resolves to mnMailboxChanges.
  let handle = makeResponseHandle[ChangesResponse[MockFoo]](makeMcid("c0"))
  let r = updatedRef(handle)
  doAssert r.kind == rkReference
  doAssert r.reference.path == rpUpdated
  doAssert r.reference.name == mnMailboxChanges
  doAssert r.reference.resultOf == makeMcid("c0")

block createdRefRejectsGetHandle:
  ## A GetResponse handle cannot call createdRef (type-safe rejection).
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  assertNotCompiles createdRef(handle)

block createdRefRejectsQueryHandle:
  ## A QueryResponse handle cannot call createdRef (type-safe rejection).
  let handle = makeResponseHandle[QueryResponse[MockQueryable]](makeMcid("c0"))
  assertNotCompiles createdRef(handle)

block updatedRefRejectsSetHandle:
  ## A SetResponse handle cannot call updatedRef (type-safe rejection).
  let handle = makeResponseHandle[SetResponse[MockFoo, MockFoo]](makeMcid("c0"))
  assertNotCompiles updatedRef(handle)

# ===========================================================================
# G. Generic reference (escape hatch)
# ===========================================================================

block referenceConstruction:
  ## Generic reference produces correct ResultReference with matching fields.
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let rr = reference(handle, mnEmailQuery, rpIds)
  doAssert rr.resultOf == makeMcid("c0")
  doAssert rr.name == mnEmailQuery
  doAssert rr.path == rpIds
