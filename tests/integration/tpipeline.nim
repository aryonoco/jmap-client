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
import jmap_client/internal/protocol/methods
import jmap_client/internal/protocol/dispatch
import jmap_client/internal/protocol/builder
import jmap_client/client
import jmap_client/internal/mail/mail_builders
import jmap_client/internal/mail/mailbox
import jmap_client/internal/types/envelope

import ../massertions
import ../mfixtures
import ../mtest_entity
import ../mtestblock
import ../mtransport

# ===========================================================================
# A. Builder -> build -> Request JSON
# ===========================================================================

testCase builderToRequestJson:
  ## Build a GetRequest for TestWidget and verify Request JSON structure.
  ## ``initRequestBuilder`` pre-declares ``urn:ietf:params:jmap:core``
  ## (RFC 8620 §3.2 obligation) so the ``using`` set carries both core
  ## and the entity-specific URI.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, gh) = addGet[TestWidget](b0, accountId = makeAccountId("A1"))
  let req = b1.freeze().request
  doAssert req.`using` == @["urn:ietf:params:jmap:core", "urn:test:widget"]
  assertLen req.methodCalls, 1
  doAssert req.methodCalls[0].name == mnMailboxGet
  let args = req.methodCalls[0].arguments
  doAssert args{"accountId"}.getStr("") == "A1"
  doAssert $gh == "c0"

# ===========================================================================
# B. Builder -> build -> Response -> get[T] (full round-trip)
# ===========================================================================

testCase fullRoundTrip:
  ## Build request, construct synthetic response, extract typed result.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, gh) = addGet[TestWidget](b0, accountId = makeAccountId("A1"))
  # Synthetic response with a GetResponse containing a TestWidget
  let getJson = %*{
    "accountId": "A1",
    "state": "s1",
    "list": [{"id": "w1", "name": "Widget One"}],
    "notFound": [],
  }
  let resp = makeTypedResponse("TestWidget/get", getJson, makeMcid("c0"))
  let dr = makeDispatchedResponse(resp, bid)
  let result = dr.get(gh)
  assertOk result
  let gr = result.get()
  doAssert gr.accountId == makeAccountId("A1")
  doAssert gr.state == makeState("s1")
  assertLen gr.list, 1

# ===========================================================================
# C. Multi-method pipeline with result references
# ===========================================================================

testCase multiMethodWithResultReference:
  ## addQuery -> idsRef -> addGet with referenced ids.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (b1, qh) = addQuery[TestWidget, TestWidgetFilter, Comparator](
    b0, accountId = makeAccountId("A1")
  )
  # Use type-safe idsRef -- auto-derives name "TestWidget/query"
  let idsRefVal = qh.idsRef()
  let (b2, gh) =
    addGet[TestWidget](b1, accountId = makeAccountId("A1"), ids = Opt.some(idsRefVal))
  let req = b2.freeze().request
  assertLen req.methodCalls, 2
  doAssert req.methodCalls[0].name == mnEmailQuery
  doAssert req.methodCalls[1].name == mnMailboxGet
  # Verify the #ids key in the get invocation
  let getArgs = req.methodCalls[1].arguments
  doAssert getArgs{"ids"}.isNil # direct "ids" should NOT be present
  let refNode = getArgs{"#ids"}
  doAssert not refNode.isNil
  doAssert refNode{"resultOf"}.getStr("") == "c0"
  doAssert refNode{"name"}.getStr("") == "Email/query"
  doAssert refNode{"path"}.getStr("") == "/ids"
  # Construct synthetic multi-invocation response and extract both
  let queryJson = makeQueryResponseJson(accountId = "A1", queryState = "qs1")
  let getJson = makeGetResponseJson(accountId = "A1", state = "s1")
  let resp = Response(
    methodResponses: @[
      initInvocation(mnEmailQuery, queryJson, makeMcid("c0")),
      initInvocation(mnMailboxGet, getJson, makeMcid("c1")),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  assertOk dr.get(qh)
  assertOk dr.get(gh)

# ===========================================================================
# D. Error pipeline
# ===========================================================================

testCase errorPipeline:
  ## Method error detection through the pipeline.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, gh) = addGet[TestWidget](b0, accountId = makeAccountId("A1"))
  let resp = makeErrorResponse("unknownMethod", makeMcid("c0"))
  let dr = makeDispatchedResponse(resp, bid)
  let result = dr.get(gh)
  assertErr result
  let ge = result.error()
  doAssert ge.kind == gekMethod
  doAssert ge.methodErr.errorType == metUnknownMethod

# ===========================================================================
# E. Mixed success/error pipeline
# ===========================================================================

testCase mixedSuccessError:
  ## Two method calls: first succeeds, second returns error.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (b1, gh) = addGet[TestWidget](b0, accountId = makeAccountId("A1"))
  let (_, sh) = addMailboxSet(b1, accountId = makeAccountId("A1"))
  let getJson = makeGetResponseJson(accountId = "A1", state = "s1")
  let resp = Response(
    methodResponses: @[
      initInvocation(mnMailboxGet, getJson, makeMcid("c0")),
      parseInvocation("error", %*{"type": "stateMismatch"}, makeMcid("c1")).get(),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  assertOk dr.get(gh) # first succeeds
  assertErr dr.get(sh) # second is error
  let err2 = dr.get(sh).error()
  doAssert err2.kind == gekMethod
  doAssert err2.methodErr.errorType == metStateMismatch

# ===========================================================================
# F. Builder -> send convenience (Layer 4 integration)
# ===========================================================================

testCase builderSendConvenience:
  ## Verify client.send(builder.freeze()) compiles and exercises pre-flight
  ## validation through a canned Transport. The default POST response is
  ## parser-valid (empty methodResponses), so the send completes Ok.
  let client = newClientWithSessionCaps(realisticCoreCaps())
  let b0 = client.newBuilder()
  let (b1, _) = b0.addEcho(%*{"test": true})
  let result = client.send(b1.freeze())
  assertOk result

# ===========================================================================
# G. Query with filter (TestWidget)
# ===========================================================================

testCase queryWithFilter:
  ## Build a query with TestWidgetFilter and verify filter serialisation.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let f = TestWidgetFilter(name: Opt.some("test"))
  let (b1, qh) = addQuery[TestWidget, TestWidgetFilter, Comparator](
    b0, accountId = makeAccountId("A1"), filter = Opt.some(filterCondition(f))
  )
  let req = b1.freeze().request
  let args = req.methodCalls[0].arguments
  let filterNode = args{"filter"}
  doAssert not filterNode.isNil
  doAssert filterNode{"name"}.getStr("") == "test"
  # Extract from synthetic response
  let queryJson = makeQueryResponseJson(accountId = "A1", queryState = "qs1")
  let resp = makeTypedResponse("TestWidget/query", queryJson, makeMcid("c0"))
  let dr = makeDispatchedResponse(resp, bid)
  assertOk dr.get(qh)

# ===========================================================================
# H. SetResponse with unified Result maps (Decision 3.9B)
# ===========================================================================

testCase setResponseUnifiedMaps:
  ## Build a set request and verify unified Result map extraction.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, sh) = addMailboxSet(b0, accountId = makeAccountId("A1"))
  # Synthetic SetResponse with mixed success/failure. The ``created``
  # entry is a complete Mailbox wire object — typed ``SetResponse[Mailbox]``
  # parses it via ``Mailbox.fromJson``, so every RFC 8621 §2 required
  # field must be present.
  let mailboxRights = %*{
    "mayReadItems": true,
    "mayAddItems": true,
    "mayRemoveItems": true,
    "maySetSeen": true,
    "maySetKeywords": true,
    "mayCreateChild": true,
    "mayRename": true,
    "mayDelete": true,
    "maySubmit": true,
  }
  let setJson = %*{
    "accountId": "A1",
    "newState": "s2",
    "created": {
      "k1": {
        "id": "w-new",
        "name": "New Mailbox",
        "parentId": nil,
        "role": nil,
        "sortOrder": 0,
        "totalEmails": 0,
        "unreadEmails": 0,
        "totalThreads": 0,
        "unreadThreads": 0,
        "myRights": mailboxRights,
        "isSubscribed": true,
      }
    },
    "notCreated": {"k2": {"type": "forbidden"}},
    "destroyed": ["w-old"],
    "notDestroyed": {"w-keep": {"type": "notFound"}},
  }
  let resp = makeTypedResponse("Mailbox/set", setJson, makeMcid("c0"))
  let dr = makeDispatchedResponse(resp, bid)
  let result = dr.get(sh)
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
