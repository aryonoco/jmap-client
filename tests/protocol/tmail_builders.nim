# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Custom Mailbox builder and response tests (RFC 8621 §2). Covers design
## doc scenarios 63-79: MailboxChangesResponse serde, addMailboxChanges,
## addMailboxQuery, addMailboxQueryChanges, addMailboxSet, plus adversarial
## serde tests and builder parameter combination tests.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/types
import jmap_client/serialisation
import jmap_client/methods
import jmap_client/builder
import jmap_client/mail/mailbox
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
  var b = initRequestBuilder()
  discard b.addMailboxChanges(makeAccountId("a1"), makeState("s0"))
  let req = b.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Mailbox/changes"

block addMailboxChangesCapability:
  ## Scenario 71: adds "urn:ietf:params:jmap:mail" to using.
  var b = initRequestBuilder()
  discard b.addMailboxChanges(makeAccountId("a1"), makeState("s0"))
  let req = b.build()
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:mail"

# ===========================================================================
# D. addMailboxQuery builder tests (scenarios 72-74)
# ===========================================================================

block addMailboxQueryInvocationName:
  ## Scenario 72: produces "Mailbox/query".
  var b = initRequestBuilder()
  discard b.addMailboxQuery(makeAccountId("a1"), filterConditionToJson)
  let req = b.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Mailbox/query"

block addMailboxQuerySortAsTree:
  ## Scenario 73: sortAsTree = true → args{"sortAsTree"} == true.
  var b = initRequestBuilder()
  discard
    b.addMailboxQuery(makeAccountId("a1"), filterConditionToJson, sortAsTree = true)
  let req = b.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sortAsTree"}.getBool(false) == true

block addMailboxQueryFilterAsTree:
  ## Scenario 74: filterAsTree = true → args{"filterAsTree"} == true.
  var b = initRequestBuilder()
  discard
    b.addMailboxQuery(makeAccountId("a1"), filterConditionToJson, filterAsTree = true)
  let req = b.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"filterAsTree"}.getBool(false) == true

block addMailboxQueryBothTreeParams:
  ## Both sortAsTree and filterAsTree set independently.
  var b = initRequestBuilder()
  discard b.addMailboxQuery(
    makeAccountId("a1"), filterConditionToJson, sortAsTree = true, filterAsTree = true
  )
  let req = b.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sortAsTree"}.getBool(false) == true
  doAssert args{"filterAsTree"}.getBool(false) == true

# ===========================================================================
# E. addMailboxQueryChanges builder tests (scenarios 75-76)
# ===========================================================================

block addMailboxQueryChangesInvocationName:
  ## Scenario 75: produces "Mailbox/queryChanges".
  var b = initRequestBuilder()
  discard b.addMailboxQueryChanges(
    makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Mailbox/queryChanges"

block addMailboxQueryChangesNoTreeParams:
  ## Scenario 76: no sortAsTree/filterAsTree in args (Decision B12).
  var b = initRequestBuilder()
  discard b.addMailboxQueryChanges(
    makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sortAsTree"}.isNil
  doAssert args{"filterAsTree"}.isNil

# ===========================================================================
# F. addMailboxSet builder tests (scenarios 77-79)
# ===========================================================================

block addMailboxSetInvocationName:
  ## Scenario 77: produces "Mailbox/set".
  var b = initRequestBuilder()
  discard b.addMailboxSet(makeAccountId("a1"))
  let req = b.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Mailbox/set"

block addMailboxSetOnDestroyRemoveEmails:
  ## Scenario 78: onDestroyRemoveEmails = true in args.
  var b = initRequestBuilder()
  discard b.addMailboxSet(makeAccountId("a1"), onDestroyRemoveEmails = true)
  let req = b.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"onDestroyRemoveEmails"}.getBool(false) == true

block addMailboxSetTypedCreate:
  ## Scenario 79: typed MailboxCreate serialised correctly.
  let mc = parseMailboxCreate("Inbox", role = Opt.some(roleInbox)).get()
  var tbl = initTable[CreationId, MailboxCreate]()
  tbl[makeCreationId("k0")] = mc
  var b = initRequestBuilder()
  discard b.addMailboxSet(makeAccountId("a1"), create = Opt.some(tbl))
  let req = b.build()
  let createObj = req.methodCalls[0].arguments{"create"}
  doAssert createObj.kind == JObject
  let k0 = createObj{"k0"}
  doAssert k0.kind == JObject
  assertEq k0{"name"}.getStr(""), "Inbox"
  assertEq k0{"role"}.getStr(""), "inbox"

block addMailboxSetDefaultOnDestroy:
  ## onDestroyRemoveEmails at default (false) → always emitted.
  var b = initRequestBuilder()
  discard b.addMailboxSet(makeAccountId("a1"))
  let req = b.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"onDestroyRemoveEmails"}.getBool(true) == false
