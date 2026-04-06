# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Full-stack pipeline integration tests exercising the complete Layer 1-4
## path: builder construction, request building, response extraction via
## phantom-typed handles, result references, error handling, and unified
## Result maps (Decision 3.9B).

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
import jmap_client/client

import ../massertions
import ../mfixtures
import ../mtest_entity

# ===========================================================================
# A. Builder -> build -> Request JSON
# ===========================================================================

block builderToRequestJson:
  ## Build a GetRequest for TestWidget and verify Request JSON structure.
  var b = initRequestBuilder()
  let gh = addGet[TestWidget](b, accountId = makeAccountId("A1"))
  let req = b.build()
  doAssert req.`using` == @["urn:test:widget"]
  assertLen req.methodCalls, 1
  doAssert req.methodCalls[0].name == "TestWidget/get"
  let args = req.methodCalls[0].arguments
  doAssert args{"accountId"}.getStr("") == "A1"
  doAssert $gh == "c0"

# ===========================================================================
# B. Builder -> build -> Response -> get[T] (full round-trip)
# ===========================================================================

block fullRoundTrip:
  ## Build request, construct synthetic response, extract typed result.
  var b = initRequestBuilder()
  let gh = addGet[TestWidget](b, accountId = makeAccountId("A1"))
  # Synthetic response with a GetResponse containing a TestWidget
  let getJson = %*{
    "accountId": "A1",
    "state": "s1",
    "list": [{"id": "w1", "name": "Widget One"}],
    "notFound": [],
  }
  let resp = makeTypedResponse("TestWidget/get", getJson, makeMcid("c0"))
  let result = resp.get(gh)
  assertOk result
  let gr = result.get()
  doAssert gr.accountId == makeAccountId("A1")
  doAssert gr.state == makeState("s1")
  assertLen gr.list, 1

# ===========================================================================
# C. Multi-method pipeline with result references
# ===========================================================================

block multiMethodWithResultReference:
  ## addQuery -> idsRef -> addGet with referenced ids.
  var b = initRequestBuilder()
  let qh = addQuery[TestWidget, TestWidgetFilter](
    b, accountId = makeAccountId("A1"), filterConditionToJson = widgetFilterToJson
  )
  # Use type-safe idsRef -- auto-derives name "TestWidget/query"
  let idsRefVal = qh.idsRef()
  let gh =
    addGet[TestWidget](b, accountId = makeAccountId("A1"), ids = Opt.some(idsRefVal))
  let req = b.build()
  assertLen req.methodCalls, 2
  doAssert req.methodCalls[0].name == "TestWidget/query"
  doAssert req.methodCalls[1].name == "TestWidget/get"
  # Verify the #ids key in the get invocation
  let getArgs = req.methodCalls[1].arguments
  doAssert getArgs{"ids"}.isNil # direct "ids" should NOT be present
  let refNode = getArgs{"#ids"}
  doAssert not refNode.isNil
  doAssert refNode{"resultOf"}.getStr("") == "c0"
  doAssert refNode{"name"}.getStr("") == "TestWidget/query"
  doAssert refNode{"path"}.getStr("") == "/ids"
  # Construct synthetic multi-invocation response and extract both
  let queryJson = makeQueryResponseJson(accountId = "A1", queryState = "qs1")
  let getJson = makeGetResponseJson(accountId = "A1", state = "s1")
  let resp = Response(
    methodResponses: @[
      initInvocation("TestWidget/query", queryJson, makeMcid("c0")),
      initInvocation("TestWidget/get", getJson, makeMcid("c1")),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  assertOk resp.get(qh)
  assertOk resp.get(gh)

# ===========================================================================
# D. Error pipeline
# ===========================================================================

block errorPipeline:
  ## Method error detection through the pipeline.
  var b = initRequestBuilder()
  let gh = addGet[TestWidget](b, accountId = makeAccountId("A1"))
  let resp = makeErrorResponse("unknownMethod", makeMcid("c0"))
  let result = resp.get(gh)
  assertErr result
  doAssert result.error().errorType == metUnknownMethod

# ===========================================================================
# E. Mixed success/error pipeline
# ===========================================================================

block mixedSuccessError:
  ## Two method calls: first succeeds, second returns error.
  var b = initRequestBuilder()
  let gh = addGet[TestWidget](b, accountId = makeAccountId("A1"))
  let sh = addSet[TestWidget](b, accountId = makeAccountId("A1"))
  let getJson = makeGetResponseJson(accountId = "A1", state = "s1")
  let resp = Response(
    methodResponses: @[
      initInvocation("TestWidget/get", getJson, makeMcid("c0")),
      initInvocation("error", %*{"type": "stateMismatch"}, makeMcid("c1")),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  assertOk resp.get(gh) # first succeeds
  assertErr resp.get(sh) # second is error
  doAssert resp.get(sh).error().errorType == metStateMismatch

# ===========================================================================
# F. Builder -> send convenience (Layer 4 integration)
# ===========================================================================

block builderSendConvenience:
  ## Verify client.send(builder) compiles and exercises pre-flight validation.
  ## Uses setSessionForTest to inject a session with limits.
  var client = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "test-token"
    )
    .get()
  # Inject a session so send() does not need network for session fetch
  let sessionArgs = makeSessionArgs()
  let session = parseSessionFromArgs(sessionArgs)
  client.setSessionForTest(session)
  # Build a simple echo request
  var b = initRequestBuilder()
  discard b.addEcho(%*{"test": true})
  # send(client, builder) will fail at HTTP POST (no real server), but
  # the pre-flight validation and serialisation paths are exercised.
  # We expect a transport error, not a panic or compile error.
  let result = client.send(b)
  # The result should be an error (network failure), not a panic
  assertErr result

# ===========================================================================
# G. Query with filter (TestWidget)
# ===========================================================================

block queryWithFilter:
  ## Build a query with TestWidgetFilter and verify filter serialisation.
  var b = initRequestBuilder()
  let f = TestWidgetFilter(name: Opt.some("test"))
  let qh = addQuery[TestWidget, TestWidgetFilter](
    b,
    accountId = makeAccountId("A1"),
    filterConditionToJson = widgetFilterToJson,
    filter = Opt.some(filterCondition(f)),
  )
  let req = b.build()
  let args = req.methodCalls[0].arguments
  let filterNode = args{"filter"}
  doAssert not filterNode.isNil
  doAssert filterNode{"name"}.getStr("") == "test"
  # Extract from synthetic response
  let queryJson = makeQueryResponseJson(accountId = "A1", queryState = "qs1")
  let resp = makeTypedResponse("TestWidget/query", queryJson, makeMcid("c0"))
  assertOk resp.get(qh)

# ===========================================================================
# H. SetResponse with unified Result maps (Decision 3.9B)
# ===========================================================================

block setResponseUnifiedMaps:
  ## Build a set request and verify unified Result map extraction.
  var b = initRequestBuilder()
  let sh = addSet[TestWidget](b, accountId = makeAccountId("A1"))
  # Synthetic SetResponse with mixed success/failure
  let setJson = %*{
    "accountId": "A1",
    "newState": "s2",
    "created": {"k1": {"id": "w-new", "name": "New Widget"}},
    "notCreated": {"k2": {"type": "forbidden"}},
    "destroyed": ["w-old"],
    "notDestroyed": {"w-keep": {"type": "notFound"}},
  }
  let resp = makeTypedResponse("TestWidget/set", setJson, makeMcid("c0"))
  let result = resp.get(sh)
  assertOk result
  let sr = result.get()
  # Unified createResults: k1 ok, k2 err
  assertLen sr.createResults, 2
  doAssert sr.createResults[makeCreationId("k1")].isOk
  doAssert sr.createResults[makeCreationId("k2")].isErr
  doAssert sr.createResults[makeCreationId("k2")].error().errorType == setForbidden
  # Unified destroyResults: w-old ok, w-keep err
  assertLen sr.destroyResults, 2
  doAssert sr.destroyResults[makeId("w-old")].isOk
  doAssert sr.destroyResults[makeId("w-keep")].isErr
  doAssert sr.destroyResults[makeId("w-keep")].error().errorType == setNotFound

{.pop.} # params
{.pop.} # objects
{.pop.} # hasDoc
