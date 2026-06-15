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
  ## Response with valid GetResponse JSON at c0; get returns ok carrying a
  ## ``mokValue`` outcome (the method ran and produced a typed result).
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let result = dr.get(handle)
  assertOk result
  doAssert result.get().kind == mokValue

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
  let outcome = result.get()
  doAssert outcome.kind == mokValue
  let gr = outcome.value
  doAssert gr.accountId == makeAccountId("acct1")
  doAssert gr.state == makeState("s1")

# ===========================================================================
# C. get[T] error cases (callback overload)
# ===========================================================================

testCase getNotFound:
  ## Call ID c99 absent from the response: no invocation to extract, so the
  ## dispatch rides ``jeProtocol`` / ``pfMissingCall`` (the former synthetic
  ## ``serverFail`` MethodError was a protocol fault masquerading as a method
  ## error).
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c99"))
  let result = dr.get(handle)
  assertErr result
  let je = result.error()
  doAssert je.kind == jeProtocol
  doAssert je.protocol.kind == pfMissingCall
  doAssert je.protocol.callId == Opt.some(makeMcid("c99"))

testCase getMethodError:
  ## Invocation name is "error" with type "unknownMethod". A method-level error
  ## is DATA now: the result is ok, carrying ``mokMethodError`` with the typed
  ## ``MethodError`` preserved verbatim.
  let resp = makeErrorResponse("unknownMethod", makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let result = dr.get(handle)
  assertOk result
  let outcome = result.get()
  doAssert outcome.kind == mokMethodError
  doAssert outcome.error.kind == metUnknownMethod
  doAssert outcome.error.rawType == "unknownMethod"

testCase getMalformedErrorResponse:
  ## Error invocation with non-object arguments cannot parse as a MethodError,
  ## so it is a protocol fault: ``jeProtocol`` / ``pfMalformedError``.
  let malformedInv = parseInvocation("error", newJArray(), makeMcid("c0")).get()
  let resp =
    initResponse(@[malformedInv], Opt.none(Table[CreationId, Id]), makeState("rs1"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let result = dr.get(handle)
  assertErr result
  let je = result.error()
  doAssert je.kind == jeProtocol
  doAssert je.protocol.kind == pfMalformedError
  doAssert je.protocol.callId == Opt.some(makeMcid("c0"))

testCase getValidationError:
  ## A normal invocation whose arguments fail typed decoding rides
  ## ``jeProtocol`` / ``pfDecode`` carrying the structured ``SerdeViolation``,
  ## localised to the call id.
  let resp = makeTypedResponse("MockFoo/get", %*{"invalid": true}, makeMcid("c0"))
  let dr = makeDispatchedResponse(resp)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"))
  let result = dr.get(handle)
  assertErr result
  let je = result.error()
  doAssert je.kind == jeProtocol
  doAssert je.protocol.kind == pfDecode
  doAssert je.protocol.callId == Opt.some(makeMcid("c0"))

testCase getHandleMismatch:
  ## A handle issued by builder A applied to a DispatchedResponse from
  ## builder B returns err(jeMisuse) with the two brands and the handle's
  ## callId in the diagnostic payload.
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let drBrand = makeBuilderId(0x1234'u64, 1'u64)
  let handleBrand = makeBuilderId(0x1234'u64, 2'u64) # same client, different serial
  let dr = makeDispatchedResponse(resp, drBrand)
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"), handleBrand)
  let result = dr.get(handle)
  assertErr result
  let je = result.error()
  doAssert je.kind == jeMisuse
  doAssert je.misuse.expected == drBrand
  doAssert je.misuse.actual == handleBrand
  doAssert je.misuse.callId == makeMcid("c0")

testCase getHandleMismatchCrossBuilderSameClient:
  ## A6 — cross-builder within the same JmapClient. Two newBuilder() calls
  ## mint serial=0 and serial=1 sharing the same clientBrand; a handle
  ## from the first builder applied to the second's dispatched response
  ## returns err(jeMisuse) with differing serial halves but matching
  ## clientBrand. Mirrors the failure mode the A6 brand check was designed
  ## to catch.
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
  let je = result.error()
  doAssert je.kind == jeMisuse
  doAssert je.misuse.expected.clientBrand == clientBrand
  doAssert je.misuse.actual.clientBrand == clientBrand
  doAssert je.misuse.expected.serial == 1'u64
  doAssert je.misuse.actual.serial == 0'u64

testCase getHandleMismatchCrossClient:
  ## A6 — cross-client across two JmapClient instances. Each client
  ## draws its own random clientBrand at init; a handle from client A's
  ## builder applied to a DispatchedResponse from client B returns
  ## err(jeMisuse) with differing clientBrand halves. Models the
  ## multi-account email client scenario the composite brand was designed
  ## to catch.
  let bidA = makeBuilderId(0xAAAA_AAAA_AAAA_AAAA'u64, 0'u64) # client A's first builder
  let bidB = makeBuilderId(0xBBBB_BBBB_BBBB_BBBB'u64, 0'u64) # client B's first builder
  doAssert bidA.clientBrand != bidB.clientBrand
  let resp = makeTypedResponse("MockFoo/get", makeGetResponseJson(), makeMcid("c0"))
  let dr = makeDispatchedResponse(resp, bidB) # response from client B
  let handle = makeResponseHandle[GetResponse[MockFoo]](makeMcid("c0"), bidA)
  let result = dr.get(handle)
  assertErr result
  let je = result.error()
  doAssert je.kind == jeMisuse
  doAssert je.misuse.expected.clientBrand == 0xBBBB_BBBB_BBBB_BBBB'u64
  doAssert je.misuse.actual.clientBrand == 0xAAAA_AAAA_AAAA_AAAA'u64

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
  let outcome = result.get()
  doAssert outcome.kind == mokValue
  doAssert outcome.value{"tag"}.getStr("") == "hello"

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
