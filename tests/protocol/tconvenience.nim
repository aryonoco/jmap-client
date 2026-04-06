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
import jmap_client/methods
import jmap_client/dispatch
import jmap_client/builder
import jmap_client/entity
import jmap_client/convenience

import ../massertions
import ../mfixtures

# ---------------------------------------------------------------------------
# Mock entity (same pattern as tbuilder.nim)
# ---------------------------------------------------------------------------

type MockFilter = object

type MockQueryable = object

proc methodNamespace*(T: typedesc[MockQueryable]): string =
  "MockQueryable"

proc capabilityUri*(T: typedesc[MockQueryable]): string =
  "urn:test:mockqueryable"

template filterType*(T: typedesc[MockQueryable]): typedesc =
  MockFilter

proc filterConditionToJson(c: MockFilter): JsonNode {.noSideEffect, raises: [].} =
  %*{"mock": true}

registerJmapEntity(MockQueryable)
registerQueryableEntity(MockQueryable)

{.pop.} # params
{.pop.} # objects
{.pop.} # hasDoc

# ===========================================================================
# A. addQueryThenGet
# ===========================================================================

block addQueryThenGetProducesTwoInvocations:
  ## addQueryThenGet adds both query and get with result reference wiring.
  var b = initRequestBuilder()
  let handles = addQueryThenGet[MockQueryable](b, makeAccountId("a1"))
  let req = b.build()
  assertLen req.methodCalls, 2
  assertEq req.methodCalls[0].name, "MockQueryable/query"
  assertEq req.methodCalls[1].name, "MockQueryable/get"

block addQueryThenGetWiresResultReference:
  ## The get invocation references the query's /ids path.
  var b = initRequestBuilder()
  let handles = addQueryThenGet[MockQueryable](b, makeAccountId("a1"))
  let req = b.build()
  let getArgs = req.methodCalls[1].arguments
  doAssert getArgs{"ids"}.isNil # direct ids NOT present
  let refNode = getArgs{"#ids"}
  doAssert not refNode.isNil
  assertEq refNode{"resultOf"}.getStr(""), "c0"
  assertEq refNode{"name"}.getStr(""), "MockQueryable/query"
  assertEq refNode{"path"}.getStr(""), "/ids"

block addQueryThenGetHandlesArePhantomTyped:
  ## The returned handles have correct phantom types.
  var b = initRequestBuilder()
  let handles = addQueryThenGet[MockQueryable](b, makeAccountId("a1"))
  # query handle is ResponseHandle[QueryResponse[MockQueryable]]
  doAssert $handles.query == "c0"
  # get handle is ResponseHandle[GetResponse[MockQueryable]]
  doAssert $handles.get == "c1"

block addQueryThenGetAutoCollectsCapability:
  ## Capability URI is registered once (not duplicated).
  var b = initRequestBuilder()
  discard addQueryThenGet[MockQueryable](b, makeAccountId("a1"))
  let req = b.build()
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:test:mockqueryable"

# ===========================================================================
# B. addChangesToGet
# ===========================================================================

block addChangesToGetProducesTwoInvocations:
  ## addChangesToGet adds changes + get with /created reference.
  var b = initRequestBuilder()
  let handles = addChangesToGet[MockQueryable](b, makeAccountId("a1"), makeState("s0"))
  let req = b.build()
  assertLen req.methodCalls, 2
  assertEq req.methodCalls[0].name, "MockQueryable/changes"
  assertEq req.methodCalls[1].name, "MockQueryable/get"

block addChangesToGetWiresCreatedRef:
  ## The get invocation references the changes' /created path.
  var b = initRequestBuilder()
  discard addChangesToGet[MockQueryable](b, makeAccountId("a1"), makeState("s0"))
  let req = b.build()
  let getArgs = req.methodCalls[1].arguments
  let refNode = getArgs{"#ids"}
  doAssert not refNode.isNil
  assertEq refNode{"path"}.getStr(""), "/created"
  assertEq refNode{"name"}.getStr(""), "MockQueryable/changes"

# ===========================================================================
# C. getBoth for QueryGetHandles
# ===========================================================================

block getBothQueryGetSuccess:
  ## getBoth extracts both query and get results from a synthetic response.
  var b = initRequestBuilder()
  let handles = addQueryThenGet[MockQueryable](b, makeAccountId("a1"))
  let queryJson = makeQueryResponseJson(accountId = "a1", queryState = "qs1")
  let getJson = makeGetResponseJson(accountId = "a1", state = "s1")
  let resp = Response(
    methodResponses: @[
      initInvocation("MockQueryable/query", queryJson, makeMcid("c0")).get(),
      initInvocation("MockQueryable/get", getJson, makeMcid("c1")).get(),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let results = resp.getBoth(handles)
  assertOk results
  let r = results.get()
  doAssert r.query.accountId == makeAccountId("a1")
  doAssert r.get.accountId == makeAccountId("a1")

block getBothQueryGetMethodError:
  ## getBoth fails on the first MethodError (query error = get not attempted).
  var b = initRequestBuilder()
  let handles = addQueryThenGet[MockQueryable](b, makeAccountId("a1"))
  let errorJson = %*{"type": "serverFail"}
  let getJson = makeGetResponseJson(accountId = "a1", state = "s1")
  let resp = Response(
    methodResponses: @[
      initInvocation("error", errorJson, makeMcid("c0")).get(),
      initInvocation("MockQueryable/get", getJson, makeMcid("c1")).get(),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let results = resp.getBoth(handles)
  doAssert results.isErr
