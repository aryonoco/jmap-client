# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Pipeline combinator tests for the convenience module.

{.push ruleOff: "hasDoc".}
{.push ruleOff: "objects".}
{.push ruleOff: "params".}

import std/json
import std/tables

import jmap_client/types
import jmap_client/serialisation
import jmap_client/internal/protocol/methods
import jmap_client/internal/protocol/dispatch
import jmap_client/internal/protocol/builder
import jmap_client/internal/protocol/entity
import jmap_client/convenience
import jmap_client/internal/types/envelope

import ../massertions
import ../mfixtures
import ../mtestblock

# ---------------------------------------------------------------------------
# Mock entity (same pattern as tbuilder.nim)
# ---------------------------------------------------------------------------

type MockFilter = object

type MockQueryable = object

proc methodEntity*(T: typedesc[MockQueryable]): MethodEntity =
  meTest

proc capabilityUri*(T: typedesc[MockQueryable]): CapabilityUri =
  parseCapabilityUri("urn:test:mockqueryable").get()

proc getMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnMailboxGet

proc changesMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnMailboxChanges

proc queryMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnEmailQuery

template filterType*(T: typedesc[MockQueryable]): typedesc =
  MockFilter

proc toJson(c: MockFilter): JsonNode {.noSideEffect, raises: [].} =
  %*{"mock": true}

func fromJson*(
    T: typedesc[MockQueryable], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[MockQueryable, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  ok(MockQueryable())

registerJmapEntity(MockQueryable)
registerQueryableEntity(MockQueryable)

{.pop.} # params
{.pop.} # objects
{.pop.} # hasDoc

# ===========================================================================
# A. addQueryThenGet
# ===========================================================================

testCase addQueryThenGetProducesTwoInvocations:
  ## addQueryThenGet adds both query and get with result reference wiring.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addQueryThenGet[MockQueryable](b0, makeAccountId("a1"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 2
  assertEq req.methodCalls[0].name, mnEmailQuery
  assertEq req.methodCalls[1].name, mnMailboxGet

testCase addQueryThenGetWiresResultReference:
  ## The get invocation references the query's /ids path.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addQueryThenGet[MockQueryable](b0, makeAccountId("a1"))
  let req = b1.freeze().request
  let getArgs = req.methodCalls[1].arguments
  doAssert getArgs{"ids"}.isNil # direct ids NOT present
  let refNode = getArgs{"#ids"}
  doAssert not refNode.isNil
  assertEq refNode{"resultOf"}.getStr(""), "c0"
  assertEq refNode{"name"}.getStr(""), "Email/query"
  assertEq refNode{"path"}.getStr(""), "/ids"

testCase addQueryThenGetHandlesArePhantomTyped:
  ## The returned handles have correct phantom types.
  let b0 = initRequestBuilder(makeBuilderId())
  let (_, handles) = addQueryThenGet[MockQueryable](b0, makeAccountId("a1"))
  # query handle is ResponseHandle[QueryResponse[MockQueryable]]
  doAssert $handles.query == "c0"
  # get handle is ResponseHandle[GetResponse[MockQueryable]]
  doAssert $handles.get == "c1"

testCase addQueryThenGetAutoCollectsCapability:
  ## Capability URI is registered once (not duplicated). The pre-declared
  ## ``urn:ietf:params:jmap:core`` from ``initRequestBuilder`` is also
  ## present (RFC 8620 §3.2).
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addQueryThenGet[MockQueryable](b0, makeAccountId("a1"))
  let req = b1.freeze().request
  assertLen req.`using`, 2
  doAssert "urn:ietf:params:jmap:core" in req.`using`
  doAssert "urn:test:mockqueryable" in req.`using`

# ===========================================================================
# B. addChangesToGet
# ===========================================================================

testCase addChangesToGetProducesTwoInvocations:
  ## addChangesToGet adds changes + get with /created reference.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addChangesToGet[MockQueryable](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 2
  assertEq req.methodCalls[0].name, mnMailboxChanges
  assertEq req.methodCalls[1].name, mnMailboxGet

testCase addChangesToGetWiresCreatedRef:
  ## The get invocation references the changes' /created path.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addChangesToGet[MockQueryable](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  let getArgs = req.methodCalls[1].arguments
  let refNode = getArgs{"#ids"}
  doAssert not refNode.isNil
  assertEq refNode{"path"}.getStr(""), "/created"
  assertEq refNode{"name"}.getStr(""), "Mailbox/changes"

# ===========================================================================
# C. getBoth for QueryGetHandles
# ===========================================================================

testCase getBothQueryGetSuccess:
  ## getBoth extracts both query and get results from a synthetic response.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, handles) = addQueryThenGet[MockQueryable](b0, makeAccountId("a1"))
  let queryJson = makeQueryResponseJson(accountId = "a1", queryState = "qs1")
  let getJson = makeGetResponseJson(accountId = "a1", state = "s1")
  let resp = Response(
    methodResponses: @[
      initInvocation(mnEmailQuery, queryJson, makeMcid("c0")),
      initInvocation(mnMailboxGet, getJson, makeMcid("c1")),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  let results = dr.getBoth(handles)
  assertOk results
  let r = results.get()
  doAssert r.query.accountId == makeAccountId("a1")
  doAssert r.get.accountId == makeAccountId("a1")

testCase getBothQueryGetMethodError:
  ## getBoth fails on the first MethodError (query error = get not attempted).
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, handles) = addQueryThenGet[MockQueryable](b0, makeAccountId("a1"))
  let errorJson = %*{"type": "serverFail"}
  let getJson = makeGetResponseJson(accountId = "a1", state = "s1")
  let resp = Response(
    methodResponses: @[
      parseInvocation("error", errorJson, makeMcid("c0")).get(),
      initInvocation(mnMailboxGet, getJson, makeMcid("c1")),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  let results = dr.getBoth(handles)
  doAssert results.isErr
