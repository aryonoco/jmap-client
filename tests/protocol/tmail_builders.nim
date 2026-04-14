# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Custom Mailbox and Email builder and response tests (RFC 8621 §2, §4).
## Covers design doc scenarios 63-83: MailboxChangesResponse serde,
## addMailboxChanges, addMailboxQuery, addMailboxQueryChanges, addMailboxSet,
## addEmailGet, addEmailQuery, addEmailQueryChanges, plus adversarial serde
## tests and builder parameter combination tests.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/types
import jmap_client/serialisation
import jmap_client/methods
import jmap_client/builder
import jmap_client/mail/mailbox
import jmap_client/mail/email
import jmap_client/mail/mail_entities
import jmap_client/mail/mail_builders

import ../massertions
import ../mfixtures

# ===========================================================================
# A. MailboxChangesResponse fromJson (scenarios 63-67)
# ===========================================================================

block mailboxChangesResponseWithUpdatedProperties:
  ## Scenario 63: updatedProperties present with values.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
    "updatedProperties": ["name", "sortOrder"],
  }
  let res = MailboxChangesResponse.fromJson(node)
  doAssert res.isOk
  let resp = res.get()
  assertSome resp.updatedProperties
  let props = resp.updatedProperties.get()
  assertLen props, 2
  assertEq props[0], "name"
  assertEq props[1], "sortOrder"

block mailboxChangesResponseWithoutUpdatedProperties:
  ## Scenario 64: updatedProperties absent → Opt.none.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  let res = MailboxChangesResponse.fromJson(node)
  doAssert res.isOk
  assertNone res.get().updatedProperties

block mailboxChangesResponseWithNullUpdatedProperties:
  ## Scenario 65: updatedProperties: null → Opt.none.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  node["updatedProperties"] = newJNull()
  let res = MailboxChangesResponse.fromJson(node)
  doAssert res.isOk
  assertNone res.get().updatedProperties

block mailboxChangesResponseForwardingAccessors:
  ## Scenario 66: UFCS forwarding accessors return base field values.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": true,
    "created": ["id1"],
    "updated": ["id2"],
    "destroyed": ["id3"],
    "updatedProperties": ["name"],
  }
  let resp = MailboxChangesResponse.fromJson(node).get()
  assertEq $resp.accountId, "acct1"
  assertEq $resp.oldState, "s1"
  assertEq $resp.newState, "s2"
  doAssert resp.hasMoreChanges
  assertLen resp.created, 1
  assertLen resp.updated, 1
  assertLen resp.destroyed, 1

block mailboxChangesResponseMissingBaseField:
  ## Scenario 67: missing required base field → err.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  assertErr MailboxChangesResponse.fromJson(node)

# ===========================================================================
# B. Adversarial MailboxChangesResponse serde tests
# ===========================================================================

block mailboxChangesResponseUpdatedPropertiesWrongType:
  ## updatedProperties: "name" (string, not array) → err.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
    "updatedProperties": "name",
  }
  assertErr MailboxChangesResponse.fromJson(node)

block mailboxChangesResponseUpdatedPropertiesNonStringElement:
  ## updatedProperties: ["name", 123] (non-string element) → err.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
    "updatedProperties": ["name", 123],
  }
  assertErr MailboxChangesResponse.fromJson(node)

block mailboxChangesResponseEmptyUpdatedProperties:
  ## updatedProperties: [] (empty array) → Opt.some(@[]).
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
    "updatedProperties": [],
  }
  let res = MailboxChangesResponse.fromJson(node)
  doAssert res.isOk
  assertSome res.get().updatedProperties
  assertLen res.get().updatedProperties.get(), 0

# ===========================================================================
# C. addMailboxChanges builder tests (scenarios 70-71)
# ===========================================================================

block addMailboxChangesInvocationName:
  ## Scenario 70: produces "Mailbox/changes".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxChanges(makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxChanges

block addMailboxChangesCapability:
  ## Scenario 71: adds "urn:ietf:params:jmap:mail" to using.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxChanges(makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:mail"

# ===========================================================================
# D. addMailboxQuery builder tests (scenarios 72-74)
# ===========================================================================

block addMailboxQueryInvocationName:
  ## Scenario 72: produces "Mailbox/query".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxQuery(makeAccountId("a1"), filterConditionToJson)
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxQuery

block addMailboxQuerySortAsTree:
  ## Scenario 73: sortAsTree = true → args{"sortAsTree"} == true.
  let b0 = initRequestBuilder()
  let (b1, _) =
    b0.addMailboxQuery(makeAccountId("a1"), filterConditionToJson, sortAsTree = true)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sortAsTree"}.getBool(false) == true

block addMailboxQueryFilterAsTree:
  ## Scenario 74: filterAsTree = true → args{"filterAsTree"} == true.
  let b0 = initRequestBuilder()
  let (b1, _) =
    b0.addMailboxQuery(makeAccountId("a1"), filterConditionToJson, filterAsTree = true)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"filterAsTree"}.getBool(false) == true

block addMailboxQueryBothTreeParams:
  ## Both sortAsTree and filterAsTree set independently.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxQuery(
    makeAccountId("a1"), filterConditionToJson, sortAsTree = true, filterAsTree = true
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sortAsTree"}.getBool(false) == true
  doAssert args{"filterAsTree"}.getBool(false) == true

# ===========================================================================
# E. addMailboxQueryChanges builder tests (scenarios 75-76)
# ===========================================================================

block addMailboxQueryChangesInvocationName:
  ## Scenario 75: produces "Mailbox/queryChanges".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxQueryChanges(
    makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxQueryChanges

block addMailboxQueryChangesNoTreeParams:
  ## Scenario 76: no sortAsTree/filterAsTree in args (Decision B12).
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxQueryChanges(
    makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sortAsTree"}.isNil
  doAssert args{"filterAsTree"}.isNil

# ===========================================================================
# F. addMailboxSet builder tests (scenarios 77-79)
# ===========================================================================

block addMailboxSetInvocationName:
  ## Scenario 77: produces "Mailbox/set".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxSet(makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxSet

block addMailboxSetOnDestroyRemoveEmails:
  ## Scenario 78: onDestroyRemoveEmails = true in args.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxSet(makeAccountId("a1"), onDestroyRemoveEmails = true)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"onDestroyRemoveEmails"}.getBool(false) == true

block addMailboxSetTypedCreate:
  ## Scenario 79: typed MailboxCreate serialised correctly.
  let mc = parseMailboxCreate("Inbox", role = Opt.some(roleInbox)).get()
  var tbl = initTable[CreationId, MailboxCreate]()
  tbl[makeCreationId("k0")] = mc
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxSet(makeAccountId("a1"), create = Opt.some(tbl))
  let req = b1.build()
  let createObj = req.methodCalls[0].arguments{"create"}
  doAssert createObj.kind == JObject
  let k0 = createObj{"k0"}
  doAssert k0.kind == JObject
  assertEq k0{"name"}.getStr(""), "Inbox"
  assertEq k0{"role"}.getStr(""), "inbox"

block addMailboxSetDefaultOnDestroy:
  ## onDestroyRemoveEmails at default (false) → always emitted.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxSet(makeAccountId("a1"))
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"onDestroyRemoveEmails"}.getBool(true) == false

# ===========================================================================
# G. addEmailGet builder tests (scenarios 75-76)
# ===========================================================================

block addEmailGetInvocationName:
  ## Scenario 75: produces "Email/get" with mail capability.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailGet(makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailGet
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addEmailGetDefaultBodyFetch:
  ## Scenario 75: default EmailBodyFetchOptions produces no body-fetch keys.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailGet(makeAccountId("a1"))
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"fetchTextBodyValues"}.isNil
  doAssert args{"fetchHTMLBodyValues"}.isNil
  doAssert args{"fetchAllBodyValues"}.isNil
  doAssert args{"bodyProperties"}.isNil
  doAssert args{"maxBodyValueBytes"}.isNil

block addEmailGetWithBodyFetchOptions:
  ## Scenario 76: bvsText emits fetchTextBodyValues: true.
  let opts = EmailBodyFetchOptions(
    bodyProperties: Opt.none(seq[PropertyName]),
    fetchBodyValues: bvsText,
    maxBodyValueBytes: Opt.none(UnsignedInt),
  )
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailGet(makeAccountId("a1"), bodyFetchOptions = opts)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"fetchTextBodyValues"}.getBool(false) == true
  doAssert args{"fetchHTMLBodyValues"}.isNil
  doAssert args{"fetchAllBodyValues"}.isNil

# ===========================================================================
# H. addEmailQuery builder tests (scenarios 78-81)
# ===========================================================================

block addEmailQueryInvocationName:
  ## Scenario 78: produces "Email/query" with mail capability.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQuery(makeAccountId("a1"), filterConditionToJson)
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailQuery
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addEmailQueryCollapseThreadsTrue:
  ## Scenario 79: collapseThreads = true in args.
  let b0 = initRequestBuilder()
  let (b1, _) =
    b0.addEmailQuery(makeAccountId("a1"), filterConditionToJson, collapseThreads = true)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"collapseThreads"}.getBool(false) == true

block addEmailQueryCollapseThreadsDefault:
  ## Scenario 80: default collapseThreads = false always emitted.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQuery(makeAccountId("a1"), filterConditionToJson)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"collapseThreads"}.getBool(true) == false

block addEmailQueryWithSort:
  ## Scenario 81: EmailComparator sort serialised correctly.
  let comp = plainComparator(pspReceivedAt, isAscending = Opt.some(false))
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQuery(
    makeAccountId("a1"), filterConditionToJson, sort = Opt.some(@[comp])
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  let sortArr = args{"sort"}
  doAssert not sortArr.isNil
  doAssert sortArr.kind == JArray
  assertLen sortArr.getElems(@[]), 1
  let sortObj = sortArr[0]
  assertEq sortObj{"property"}.getStr(""), "receivedAt"
  doAssert sortObj{"isAscending"}.getBool(true) == false

block addEmailQueryNoSort:
  ## sort: Opt.none → no sort key in args.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQuery(makeAccountId("a1"), filterConditionToJson)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sort"}.isNil

# ===========================================================================
# I. addEmailQueryChanges builder tests (scenarios 82-83)
# ===========================================================================

block addEmailQueryChangesInvocationName:
  ## Scenario 82: produces "Email/queryChanges" with mail capability.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQueryChanges(
    makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailQueryChanges
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addEmailQueryChangesCollapseAndSort:
  ## Scenario 83: both collapseThreads and sort in args.
  let comp = plainComparator(pspSize)
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQueryChanges(
    makeAccountId("a1"),
    makeState("qs0"),
    filterConditionToJson,
    sort = Opt.some(@[comp]),
    collapseThreads = true,
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"collapseThreads"}.getBool(false) == true
  let sortArr = args{"sort"}
  doAssert not sortArr.isNil
  assertLen sortArr.getElems(@[]), 1
  assertEq sortArr[0]{"property"}.getStr(""), "size"

block addEmailQueryChangesSinceState:
  ## sinceQueryState appears in args.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQueryChanges(
    makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  assertEq args{"sinceQueryState"}.getStr(""), "qs0"
