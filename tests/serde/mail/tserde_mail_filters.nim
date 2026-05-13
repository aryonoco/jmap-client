# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for MailboxFilterCondition (scenarios 56-62),
## EmailBodyFetchOptions (scenarios 46-52), EmailHeaderFilter (scenarios 53-54),
## and EmailFilterCondition (scenarios 55-63).

{.push raises: [].}

import std/json

import jmap_client/internal/mail/email
import jmap_client/internal/mail/keyword
import jmap_client/internal/mail/mailbox
import jmap_client/internal/mail/mail_filters
import jmap_client/internal/mail/serde_email
import jmap_client/internal/mail/serde_mail_filters
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives
import jmap_client/internal/types/framework

import ../../massertions
import ../../mfixtures
import ../../mtestblock

# ============= A. MailboxFilterCondition toJson =============

testCase toJsonAllNone: # scenario 56
  let fc = MailboxFilterCondition(
    parentId: Opt.none(Opt[Id]),
    name: Opt.none(string),
    role: Opt.none(Opt[MailboxRole]),
    hasAnyRole: Opt.none(bool),
    isSubscribed: Opt.none(bool),
  )
  let node = fc.toJson()
  doAssert node.kind == JObject
  assertLen node, 0

testCase toJsonParentIdNull: # scenario 57
  let fc = MailboxFilterCondition(
    parentId: Opt.some(Opt.none(Id)),
    name: Opt.none(string),
    role: Opt.none(Opt[MailboxRole]),
    hasAnyRole: Opt.none(bool),
    isSubscribed: Opt.none(bool),
  )
  let node = fc.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "parentId", newJNull()

testCase toJsonParentIdValue: # scenario 58
  let id1 = parseIdFromServer("id1").get()
  let fc = MailboxFilterCondition(
    parentId: Opt.some(Opt.some(id1)),
    name: Opt.none(string),
    role: Opt.none(Opt[MailboxRole]),
    hasAnyRole: Opt.none(bool),
    isSubscribed: Opt.none(bool),
  )
  let node = fc.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "parentId", newJString("id1")

testCase toJsonRoleNull: # scenario 59
  let fc = MailboxFilterCondition(
    parentId: Opt.none(Opt[Id]),
    name: Opt.none(string),
    role: Opt.some(Opt.none(MailboxRole)),
    hasAnyRole: Opt.none(bool),
    isSubscribed: Opt.none(bool),
  )
  let node = fc.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "role", newJNull()

testCase toJsonRoleValue: # scenario 60
  let fc = MailboxFilterCondition(
    parentId: Opt.none(Opt[Id]),
    name: Opt.none(string),
    role: Opt.some(Opt.some(roleInbox)),
    hasAnyRole: Opt.none(bool),
    isSubscribed: Opt.none(bool),
  )
  let node = fc.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "role", newJString("inbox")

testCase toJsonName: # scenario 61
  let fc = MailboxFilterCondition(
    parentId: Opt.none(Opt[Id]),
    name: Opt.some("test"),
    role: Opt.none(Opt[MailboxRole]),
    hasAnyRole: Opt.none(bool),
    isSubscribed: Opt.none(bool),
  )
  let node = fc.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "name", %"test"

testCase toJsonMixed: # scenario 62
  let fc = MailboxFilterCondition(
    parentId: Opt.some(Opt.none(Id)),
    name: Opt.none(string),
    role: Opt.none(Opt[MailboxRole]),
    hasAnyRole: Opt.some(true),
    isSubscribed: Opt.none(bool),
  )
  let node = fc.toJson()
  assertLen node, 2
  assertJsonFieldEq node, "parentId", newJNull()
  assertJsonFieldEq node, "hasAnyRole", newJBool(true)

# ============= B. EmailBodyFetchOptions toJson =============

testCase bodyFetchDefaultEmpty: # scenario 46
  let opts = default(EmailBodyFetchOptions)
  let node = opts.toJson()
  doAssert node.kind == JObject
  assertLen node, 0

testCase bodyFetchText: # scenario 47
  let opts = EmailBodyFetchOptions(
    bodyProperties: Opt.none(seq[PropertyName]),
    fetchBodyValues: bvsText,
    maxBodyValueBytes: Opt.none(UnsignedInt),
  )
  let node = opts.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "fetchTextBodyValues", %true

testCase bodyFetchHtml: # scenario 48
  let opts = EmailBodyFetchOptions(
    bodyProperties: Opt.none(seq[PropertyName]),
    fetchBodyValues: bvsHtml,
    maxBodyValueBytes: Opt.none(UnsignedInt),
  )
  let node = opts.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "fetchHTMLBodyValues", %true

testCase bodyFetchTextAndHtml: # scenario 49
  let opts = EmailBodyFetchOptions(
    bodyProperties: Opt.none(seq[PropertyName]),
    fetchBodyValues: bvsTextAndHtml,
    maxBodyValueBytes: Opt.none(UnsignedInt),
  )
  let node = opts.toJson()
  assertLen node, 2
  assertJsonFieldEq node, "fetchTextBodyValues", %true
  assertJsonFieldEq node, "fetchHTMLBodyValues", %true

testCase bodyFetchAll: # scenario 50
  let opts = EmailBodyFetchOptions(
    bodyProperties: Opt.none(seq[PropertyName]),
    fetchBodyValues: bvsAll,
    maxBodyValueBytes: Opt.none(UnsignedInt),
  )
  let node = opts.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "fetchAllBodyValues", %true

testCase bodyFetchMaxBytes: # scenario 51
  let opts = EmailBodyFetchOptions(
    bodyProperties: Opt.none(seq[PropertyName]),
    fetchBodyValues: bvsNone,
    maxBodyValueBytes: Opt.some(parseUnsignedInt(1024).get()),
  )
  let node = opts.toJson()
  assertLen node, 1
  doAssert node{"maxBodyValueBytes"} != nil, "maxBodyValueBytes must be present"

testCase bodyFetchProperties: # scenario 52
  let pn = parsePropertyName("partId").get()
  let opts = EmailBodyFetchOptions(
    bodyProperties: Opt.some(@[pn]),
    fetchBodyValues: bvsNone,
    maxBodyValueBytes: Opt.none(UnsignedInt),
  )
  let node = opts.toJson()
  assertLen node, 1
  let arr = node{"bodyProperties"}
  doAssert arr != nil, "bodyProperties must be present"
  doAssert arr.kind == JArray, "bodyProperties must be JArray"
  assertLen arr.getElems(@[]), 1

# ============= C. EmailHeaderFilter =============

testCase headerFilterValid: # scenario 53
  let res = parseEmailHeaderFilter("Subject")
  assertOk res
  assertEq res.get().name, "Subject"

testCase headerFilterEmpty: # scenario 54
  assertErrContains parseEmailHeaderFilter(""), "header name must not be empty"

testCase headerFilterToJsonNameOnly:
  let ehf = makeEmailHeaderFilter("Subject")
  let node = ehf.toJson()
  doAssert node.kind == JArray, "EmailHeaderFilter.toJson must be JArray"
  assertLen node.getElems(@[]), 1
  assertEq node.getElems(@[])[0].getStr(""), "Subject"

testCase headerFilterToJsonNameAndValue:
  let ehf = makeEmailHeaderFilter("Subject", Opt.some("test"))
  let node = ehf.toJson()
  doAssert node.kind == JArray, "EmailHeaderFilter.toJson must be JArray"
  assertLen node.getElems(@[]), 2
  assertEq node.getElems(@[])[0].getStr(""), "Subject"
  assertEq node.getElems(@[])[1].getStr(""), "test"

# ============= D. EmailFilterCondition toJson =============

testCase filterAllNone: # scenario 55
  let fc = makeEmailFilterCondition()
  let node = fc.toJson()
  doAssert node.kind == JObject
  assertLen node, 0

testCase filterInMailbox: # scenario 56
  let fc = EmailFilterCondition(inMailbox: Opt.some(makeId("mbx1")))
  let node = fc.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "inMailbox", %"mbx1"

testCase filterHasKeyword: # scenario 57
  let fc = EmailFilterCondition(hasKeyword: Opt.some(kwSeen))
  let node = fc.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "hasKeyword", %"$seen"

testCase filterAllKeywords: # scenario 58
  let fc = EmailFilterCondition(
    hasKeyword: Opt.some(kwSeen),
    notKeyword: Opt.some(kwFlagged),
    allInThreadHaveKeyword: Opt.some(kwAnswered),
    someInThreadHaveKeyword: Opt.some(kwDraft),
    noneInThreadHaveKeyword: Opt.some(kwForwarded),
  )
  let node = fc.toJson()
  assertLen node, 5
  assertJsonFieldEq node, "hasKeyword", %"$seen"
  assertJsonFieldEq node, "notKeyword", %"$flagged"
  assertJsonFieldEq node, "allInThreadHaveKeyword", %"$answered"
  assertJsonFieldEq node, "someInThreadHaveKeyword", %"$draft"
  assertJsonFieldEq node, "noneInThreadHaveKeyword", %"$forwarded"

testCase filterFromAddr: # scenario 59
  let fc = EmailFilterCondition(fromAddr: Opt.some("alice"))
  let node = fc.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "from", %"alice"
  doAssert node{"fromAddr"}.isNil, "fromAddr key must not appear"

testCase filterHeaderBothForms: # scenario 60
  # Name only
  let ehfNameOnly = makeEmailHeaderFilter("X-Custom")
  let fc1 = EmailFilterCondition(header: Opt.some(ehfNameOnly))
  let node1 = fc1.toJson()
  assertLen node1, 1
  let arr1 = node1{"header"}
  doAssert arr1 != nil and arr1.kind == JArray
  assertLen arr1.getElems(@[]), 1
  assertEq arr1.getElems(@[])[0].getStr(""), "X-Custom"

  # Name + value
  let ehfNameValue = makeEmailHeaderFilter("X-Custom", Opt.some("val"))
  let fc2 = EmailFilterCondition(header: Opt.some(ehfNameValue))
  let node2 = fc2.toJson()
  let arr2 = node2{"header"}
  doAssert arr2 != nil and arr2.kind == JArray
  assertLen arr2.getElems(@[]), 2
  assertEq arr2.getElems(@[])[1].getStr(""), "val"

testCase filterMixed: # scenario 61
  let fc = EmailFilterCondition(
    inMailbox: Opt.some(makeId("mbx1")),
    hasKeyword: Opt.some(kwSeen),
    subject: Opt.some("hello"),
    hasAttachment: Opt.some(true),
  )
  let node = fc.toJson()
  assertLen node, 4
  assertJsonFieldEq node, "inMailbox", %"mbx1"
  assertJsonFieldEq node, "hasKeyword", %"$seen"
  assertJsonFieldEq node, "subject", %"hello"
  assertJsonFieldEq node, "hasAttachment", %true

testCase filterEmptyMailboxOtherThan: # scenario 62
  let fc = EmailFilterCondition(inMailboxOtherThan: Opt.some(newSeq[Id]()))
  let node = fc.toJson()
  assertLen node, 1
  let arr = node{"inMailboxOtherThan"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(@[]), 0

testCase filterAll20Fields: # scenario 63
  let fc = EmailFilterCondition(
    inMailbox: Opt.some(makeId("mbx1")),
    inMailboxOtherThan: Opt.some(@[makeId("mbx2")]),
    before: Opt.some(parseUtcDate("2025-06-01T00:00:00Z").get()),
    after: Opt.some(parseUtcDate("2025-01-01T00:00:00Z").get()),
    minSize: Opt.some(parseUnsignedInt(100).get()),
    maxSize: Opt.some(parseUnsignedInt(50000).get()),
    allInThreadHaveKeyword: Opt.some(kwSeen),
    someInThreadHaveKeyword: Opt.some(kwFlagged),
    noneInThreadHaveKeyword: Opt.some(kwDraft),
    hasKeyword: Opt.some(kwAnswered),
    notKeyword: Opt.some(kwForwarded),
    hasAttachment: Opt.some(true),
    text: Opt.some("search term"),
    fromAddr: Opt.some("alice@example.com"),
    to: Opt.some("bob@example.com"),
    cc: Opt.some("carol@example.com"),
    bcc: Opt.some("dave@example.com"),
    subject: Opt.some("test subject"),
    body: Opt.some("body text"),
    header: Opt.some(makeEmailHeaderFilter("X-Priority")),
  )
  let node = fc.toJson()
  assertLen node, 20
  # Spot-check a few keys for correct types
  assertJsonFieldEq node, "inMailbox", %"mbx1"
  assertJsonFieldEq node, "hasAttachment", %true
  assertJsonFieldEq node, "from", %"alice@example.com"
  doAssert node{"header"} != nil and node{"header"}.kind == JArray
  doAssert node{"before"} != nil and node{"before"}.kind == JString
  doAssert node{"minSize"} != nil and node{"minSize"}.kind == JInt
