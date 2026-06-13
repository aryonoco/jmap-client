# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## ResponseHandle extraction tests: get[T], error detection, validation
## error conversion, reference construction, and borrowed operations.

{.push raises: [].}

import std/json
import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import jmap_client/internal/protocol/entity
import jmap_client/internal/protocol/methods
import jmap_client/internal/protocol/dispatch
import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_diagnostics
import jmap_client/internal/serialisation/serde_helpers

import ../massertions
import ../mfixtures
import ../mtestblock

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

{.pop.} # params
{.pop.} # objects
{.pop.} # hasDoc

# ===========================================================================
# A. Handle operations
# ===========================================================================

testCase handleEquality:
  ## Two handles with the same call ID and brand are equal.
  let h1 = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let h2 = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  doAssert h1 == h2

testCase handleToString:
  ## String representation produces the call ID string.
  let h = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  doAssert $h == "c0"

testCase handleHash:
  ## Hash is consistent with equality.
  let h1 = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let h2 = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  doAssert hash(h1) == hash(h2)

testCase callIdAccessor:
  ## callId returns the underlying MethodCallId.
  let mcid = makeMcid("c0")
  let h = makeResponseHandle[GetResponse[MockFoo]](mcid)
  doAssert callId(h) == mcid

# ===========================================================================
# B. get[T] happy path (callback overload)
# ===========================================================================

testCase getHappyPath:
  ## Response with valid GetResponse JSON at c0, get with callback returns ok.
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let result = dr.get(handle)
  assertOk result

testCase getExtractsCorrectInvocation:
  ## Response with multiple invocations (c0, c1); handle c1 extracts the right one.
  let inv0 =
    initInvocation(mnMailboxGet, makeGetResponseJson("acct0", "s0"), makeMcid("c0"))
  let inv1 =
    initInvocation(mnMailboxGet, makeGetResponseJson("acct1", "s1"), makeMcid("c1"))
  let resp =
    initResponse(@[inv0, inv1], Opt.none(Table[CreationId, Id]), makeState("rs1"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c1"))
  let result = dr.get(handle)
  assertOk result
  let gr = result.get()
  doAssert gr.accountId == makeAccountId("acct1")
  doAssert gr.state == makeState("s1")

# ===========================================================================
# C. get[T] error cases (callback overload)
# ===========================================================================

testCase getNotFound:
  ## Call ID c99 not in response produces err(gekMethod) with metServerFail.
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c99"))
  let result = dr.get(handle)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekMethod
  doAssert ge.methodErr.kind == metServerFail

testCase getMethodError:
  ## Invocation name is "error" with type "unknownMethod" produces err(gekMethod)
  ## carrying metUnknownMethod.
  let resp = makeErrorResponse("unknownMethod", makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let result = dr.get(handle)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekMethod
  doAssert ge.methodErr.kind == metUnknownMethod
  doAssert ge.methodErr.rawType == "unknownMethod"

testCase getMalformedErrorResponse:
  ## Error invocation with non-object arguments produces err(gekMethod) with metServerFail.
  let malformedInv = parseInvocation("error", newJArray(), makeMcid("c0")).get()
  let resp =
    initResponse(@[malformedInv], Opt.none(Table[CreationId, Id]), makeState("rs1"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let result = dr.get(handle)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekMethod
  doAssert ge.methodErr.kind == metServerFail

testCase getValidationError:
  ## fromArgs returns err(ValidationError) which is converted to MethodError with metServerFail,
  ## then lifted to GetError(gekMethod).
  let resp = makeTypedResponse("MockFoo/get", %*{"invalid": true}, makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let result = dr.get(handle)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekMethod
  let me = ge.methodErr
  doAssert me.kind == metServerFail
  doAssert me.extras.isSome
  let extras = me.extras.get()
  doAssert extras.kind == JObject
  doAssert extras{"typeName"} != nil
  doAssert extras{"value"} != nil

testCase getHandleMismatch:
  ## A handle issued by builder A applied to a DispatchedResponse from
  ## builder B returns err(gekHandleMismatch) with the two brands and
  ## the handle's callId in the diagnostic payload.
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let drBrand = makeBuilderId(0x1234'u64, 1'u64)
  let handleBrand = makeBuilderId(0x1234'u64, 2'u64) # same client, different serial
  let dr = makeDispatchedResponse(resp, drBrand)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"), handleBrand)
  let result = dr.get(handle)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekHandleMismatch
  doAssert ge.expected == drBrand
  doAssert ge.actual == handleBrand
  doAssert ge.callId == makeMcid("c0")

testCase getHandleMismatchCrossBuilderSameClient:
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
  let result = dr.get(handle)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekHandleMismatch
  doAssert ge.expected.clientBrand == clientBrand
  doAssert ge.actual.clientBrand == clientBrand
  doAssert ge.expected.serial == 1'u64
  doAssert ge.actual.serial == 0'u64

testCase getHandleMismatchCrossClient:
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
  let result = dr.get(handle)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekHandleMismatch
  doAssert ge.expected.clientBrand == 0xBBBB_BBBB_BBBB_BBBB'u64
  doAssert ge.actual.clientBrand == 0xAAAA_AAAA_AAAA_AAAA'u64

# ===========================================================================
# D. get[T] for Echo (JsonNode) with callback
# ===========================================================================

testCase getEchoHappyPath:
  ## Response with Core/echo invocation. ``JsonNode.fromJson`` is the
  ## pass-through identity shim in ``methods.nim`` so the handle parses
  ## back the raw arguments unchanged.
  let echoArgs = %*{"tag": "hello"}
  let resp = makeTypedResponse("Core/echo", echoArgs, makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[JsonNode](makeMcid("c0"))
  let result = dr.get(handle)
  assertOk result
  doAssert result.get(){"tag"}.getStr("") == "hello"

# ===========================================================================
# G. Generic reference (escape hatch)
# ===========================================================================

testCase referenceConstruction:
  ## Generic reference produces a reference-form Referencable whose
  ## ResultReference carries the matching fields. ``U`` is explicit because
  ## it appears only in the return type (A30b).
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let r = reference[seq[Id]](handle, mnEmailQuery, rpIds)
  doAssert r.kind == rkReference
  let rr = r.asReference.get()
  doAssert rr.resultOf == makeMcid("c0")
  doAssert rr.name == mnEmailQuery
  doAssert rr.path == rpIds
