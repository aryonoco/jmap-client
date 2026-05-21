# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for the per-entity pipeline combinators in
## ``jmap_client/convenience`` — the query-then-get / changes-to-get
## wrappers and the ``getBoth`` paired extraction. Each test drives a
## real entity (Email, Mailbox) through ``initRequestBuilder``, then
## asserts the emitted two-invocation wire shape and back-reference, or
## extracts both responses from a synthetic ``Response``.

{.push raises: [].}

import std/json
import std/tables

import jmap_client
import jmap_client/convenience
import jmap_client/internal/protocol/builder
import jmap_client/internal/types/envelope

import ../massertions
import ../mfixtures
import ../mtestblock

# ===========================================================================
# A. addEmailQueryThenGet
# ===========================================================================

testCase addEmailQueryThenGetEmitsQueryAndGet:
  ## addEmailQueryThenGet adds Email/query followed by Email/get.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addEmailQueryThenGet(b0, makeAccountId("a1"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 2
  assertEq req.methodCalls[0].name, mnEmailQuery
  assertEq req.methodCalls[1].name, mnEmailGet

testCase addEmailQueryThenGetWiresIdsReference:
  ## The Email/get invocation back-references the query's /ids path.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addEmailQueryThenGet(b0, makeAccountId("a1"))
  let req = b1.freeze().request
  let getArgs = req.methodCalls[1].arguments
  doAssert getArgs{"ids"}.isNil # direct ids NOT present
  let refNode = getArgs{"#ids"}
  doAssert not refNode.isNil
  assertEq refNode{"resultOf"}.getStr(""), "c0"
  assertEq refNode{"name"}.getStr(""), "Email/query"
  assertEq refNode{"path"}.getStr(""), "/ids"

# ===========================================================================
# B. addEmailChangesToGet
# ===========================================================================

testCase addEmailChangesToGetEmitsChangesAndGet:
  ## addEmailChangesToGet adds Email/changes followed by Email/get.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addEmailChangesToGet(b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 2
  assertEq req.methodCalls[0].name, mnEmailChanges
  assertEq req.methodCalls[1].name, mnEmailGet

testCase addEmailChangesToGetWiresCreatedReference:
  ## The Email/get invocation back-references the changes' /created path.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addEmailChangesToGet(b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  let refNode = req.methodCalls[1].arguments{"#ids"}
  doAssert not refNode.isNil
  assertEq refNode{"name"}.getStr(""), "Email/changes"
  assertEq refNode{"path"}.getStr(""), "/created"

# ===========================================================================
# C. addMailboxChangesToGet
# ===========================================================================

testCase addMailboxChangesToGetEmitsChangesAndGet:
  ## addMailboxChangesToGet adds Mailbox/changes + Mailbox/get and returns
  ## the bespoke MailboxChangesGetHandles pair.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, handles) = addMailboxChangesToGet(b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 2
  assertEq req.methodCalls[0].name, mnMailboxChanges
  assertEq req.methodCalls[1].name, mnMailboxGet
  doAssert $handles.changes == "c0"
  doAssert $handles.get == "c1"

testCase addMailboxChangesToGetWiresCreatedReference:
  ## The Mailbox/get invocation back-references the changes' /created path.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addMailboxChangesToGet(b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  let refNode = req.methodCalls[1].arguments{"#ids"}
  doAssert not refNode.isNil
  assertEq refNode{"name"}.getStr(""), "Mailbox/changes"
  assertEq refNode{"path"}.getStr(""), "/created"

# ===========================================================================
# D. getBoth — paired extraction
# ===========================================================================

testCase getBothQueryGetSuccess:
  ## getBoth over QueryGetHandles[Email] extracts both responses.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, handles) = addEmailQueryThenGet(b0, makeAccountId("a1"))
  let resp = Response(
    methodResponses: @[
      initInvocation(
        mnEmailQuery, makeQueryResponseJson(accountId = "a1"), makeMcid("c0")
      ),
      initInvocation(mnEmailGet, makeGetResponseJson(accountId = "a1"), makeMcid("c1")),
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

testCase getBothChangesGetSuccess:
  ## getBoth over ChangesGetHandles[Email] extracts both responses.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, handles) = addEmailChangesToGet(b0, makeAccountId("a1"), makeState("s0"))
  let resp = Response(
    methodResponses: @[
      initInvocation(
        mnEmailChanges, makeChangesResponseJson(accountId = "a1"), makeMcid("c0")
      ),
      initInvocation(mnEmailGet, makeGetResponseJson(accountId = "a1"), makeMcid("c1")),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  let results = dr.getBoth(handles)
  assertOk results
  doAssert results.get().changes.accountId == makeAccountId("a1")

testCase getBothMailboxChangesGetSuccess:
  ## getBoth over MailboxChangesGetHandles extracts both responses.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, handles) = addMailboxChangesToGet(b0, makeAccountId("a1"), makeState("s0"))
  let resp = Response(
    methodResponses: @[
      initInvocation(
        mnMailboxChanges, makeChangesResponseJson(accountId = "a1"), makeMcid("c0")
      ),
      initInvocation(
        mnMailboxGet, makeGetResponseJson(accountId = "a1"), makeMcid("c1")
      ),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  let results = dr.getBoth(handles)
  assertOk results
  doAssert results.get().get.accountId == makeAccountId("a1")

testCase getBothShortCircuitsOnFirstError:
  ## getBoth fails on the first error — a query MethodError means the get
  ## response is never extracted.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, handles) = addEmailQueryThenGet(b0, makeAccountId("a1"))
  let resp = Response(
    methodResponses: @[
      parseInvocation("error", %*{"type": "serverFail"}, makeMcid("c0")).get(),
      initInvocation(mnEmailGet, makeGetResponseJson(accountId = "a1"), makeMcid("c1")),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  doAssert dr.getBoth(handles).isErr
