# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for the per-entity pipeline combinators surfaced through
## ``import jmap_client`` — the query-then-get / changes-to-get
## wrappers and the ``getBoth`` paired extraction. Each test drives a
## real entity (Email, Mailbox) through ``initRequestBuilder``, then
## asserts the emitted two-invocation wire shape and back-reference, or
## extracts both responses from a synthetic ``Response``.

{.push raises: [].}

import std/json
import std/tables

import jmap_client
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

testCase addEmailChangesToGetAllEmitsThreeInvocations:
  ## Changes plus BOTH back-referenced gets, in dispatch order.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, handles) = addEmailChangesToGetAll(b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 3
  assertEq req.methodCalls[0].name, mnEmailChanges
  assertEq req.methodCalls[1].name, mnEmailGet
  assertEq req.methodCalls[2].name, mnEmailGet
  doAssert $handles.changes == "c0",
    "expected changes handle c0, got " & $handles.changes
  doAssert $handles.created == "c1",
    "expected created handle c1, got " & $handles.created
  doAssert $handles.updated == "c2",
    "expected updated handle c2, got " & $handles.updated

testCase addEmailChangesToGetAllWiresBothReferences:
  ## /created feeds the first get, /updated the second — sync needs
  ## both halves of the fetchable delta.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addEmailChangesToGetAll(b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  let createdRef = req.methodCalls[1].arguments{"#ids"}
  doAssert not createdRef.isNil, "expected #ids back-reference on the created get"
  assertEq createdRef{"name"}.getStr(""), "Email/changes"
  assertEq createdRef{"path"}.getStr(""), "/created"
  let updatedRef = req.methodCalls[2].arguments{"#ids"}
  doAssert not updatedRef.isNil, "expected #ids back-reference on the updated get"
  assertEq updatedRef{"name"}.getStr(""), "Email/changes"
  assertEq updatedRef{"path"}.getStr(""), "/updated"

testCase addEmailChangesToGetAllThreadsFetchOptionsToBothGets:
  ## The one bodyFetchOptions argument reaches BOTH gets — a sync asking
  ## for text bodies must not receive them on the created half alone.
  let opts = EmailBodyFetchOptions(
    bodyProperties: Opt.none(NonEmptySeq[EmailBodyProperty]),
    fetchBodyValues: bvsText,
    maxBodyValueBytes: Opt.none(UnsignedInt),
  )
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addEmailChangesToGetAll(
    b0, makeAccountId("a1"), makeState("s0"), bodyFetchOptions = opts
  )
  let req = b1.freeze().request
  doAssert req.methodCalls[1].arguments{"fetchTextBodyValues"}.getBool(false),
    "expected fetchTextBodyValues on the created get"
  doAssert req.methodCalls[2].arguments{"fetchTextBodyValues"}.getBool(false),
    "expected fetchTextBodyValues on the updated get"

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
  let resp = initResponse(
    @[
      initInvocation(
        mnEmailQuery, makeQueryResponseJson(accountId = "a1"), makeMcid("c0")
      ),
      initInvocation(mnEmailGet, makeGetResponseJson(accountId = "a1"), makeMcid("c1")),
    ],
    Opt.none(Table[CreationId, Id]),
    makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  let results = dr.getBoth(handles)
  assertOk results
  let r = results.get()
  doAssert r.query.kind == mokValue
  doAssert r.get.kind == mokValue
  doAssert r.query.value.accountId == makeAccountId("a1")
  doAssert r.get.value.accountId == makeAccountId("a1")

testCase getBothChangesGetSuccess:
  ## getBoth over ChangesGetHandles[Email] extracts both responses.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, handles) = addEmailChangesToGet(b0, makeAccountId("a1"), makeState("s0"))
  let resp = initResponse(
    @[
      initInvocation(
        mnEmailChanges, makeChangesResponseJson(accountId = "a1"), makeMcid("c0")
      ),
      initInvocation(mnEmailGet, makeGetResponseJson(accountId = "a1"), makeMcid("c1")),
    ],
    Opt.none(Table[CreationId, Id]),
    makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  let results = dr.getBoth(handles)
  assertOk results
  let r = results.get()
  doAssert r.changes.kind == mokValue
  doAssert r.changes.value.accountId == makeAccountId("a1")

testCase getBothMailboxChangesGetSuccess:
  ## getBoth over MailboxChangesGetHandles extracts both responses.
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, handles) = addMailboxChangesToGet(b0, makeAccountId("a1"), makeState("s0"))
  let resp = initResponse(
    @[
      initInvocation(
        mnMailboxChanges, makeChangesResponseJson(accountId = "a1"), makeMcid("c0")
      ),
      initInvocation(
        mnMailboxGet, makeGetResponseJson(accountId = "a1"), makeMcid("c1")
      ),
    ],
    Opt.none(Table[CreationId, Id]),
    makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  let results = dr.getBoth(handles)
  assertOk results
  let r = results.get()
  doAssert r.get.kind == mokValue
  doAssert r.get.value.accountId == makeAccountId("a1")

testCase getBothMethodErrorRidesDataNotRail:
  ## A server method error on the query side rides ``MethodOutcome.mokMethodError``
  ## (data), NOT the rail — so getBoth still extracts the sibling get response
  ## rather than short-circuiting (RFC 8620 §3.6.2: a method erroring must not
  ## discard its successful siblings).
  let b0 = initRequestBuilder(makeBuilderId())
  let bid = b0.builderId
  let (_, handles) = addEmailQueryThenGet(b0, makeAccountId("a1"))
  let resp = initResponse(
    @[
      parseInvocation("error", %*{"type": "serverFail"}, makeMcid("c0")).get(),
      initInvocation(mnEmailGet, makeGetResponseJson(accountId = "a1"), makeMcid("c1")),
    ],
    Opt.none(Table[CreationId, Id]),
    makeState("rs1"),
  )
  let dr = makeDispatchedResponse(resp, bid)
  let results = dr.getBoth(handles)
  assertOk results
  let r = results.get()
  doAssert r.query.kind == mokMethodError
  doAssert r.query.error.kind == metServerFail
  doAssert r.get.kind == mokValue
