# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for Mailbox types (scenarios 28-29, 32-55).

{.push raises: [].}

import std/json

import jmap_client/mail/mailbox
import jmap_client/mail/serde_mailbox
import jmap_client/serde
import jmap_client/validation
import jmap_client/primitives

import ../../massertions
import ../../mfixtures

# ============= A. MailboxRole serde =============

block toJsonMailboxRole: # scenario 28
  let node = roleInbox.toJson()
  assertEq node, newJString("inbox")

block fromJsonMailboxRole: # scenario 29
  assertOkEq MailboxRole.fromJson(newJString("inbox")), roleInbox

# ============= B. MailboxIdSet serde =============

block toJsonMailboxIdSet: # scenario 32
  let id1 = parseId("mbx1").get()
  let id2 = parseId("mbx2").get()
  let ms = initMailboxIdSet(@[id1, id2])
  let node = ms.toJson()
  doAssert node.kind == JObject
  assertJsonFieldEq node, "mbx1", newJBool(true)
  assertJsonFieldEq node, "mbx2", newJBool(true)
  assertLen node, 2

block fromJsonMailboxIdSet: # scenario 33
  let res = MailboxIdSet.fromJson(%*{"mbx1": true, "mbx2": true})
  assertOk res
  let ms = res.get()
  assertLen ms, 2
  doAssert parseId("mbx1").get() in ms
  doAssert parseId("mbx2").get() in ms

block fromJsonMailboxIdSetFalse: # scenario 34
  ## Explicit ``false`` for any mailbox id value is rejected structurally
  ## via ``svkEnumNotRecognised``.
  let res = MailboxIdSet.fromJson(%*{"mbx1": false})
  doAssert res.isErr
  doAssert res.error.kind == svkEnumNotRecognised
  doAssert res.error.rawValue == "false"
  doAssert $res.error.path == "/mbx1"

block roundTripMailboxIdSet: # scenario 35
  let id1 = parseId("mbx1").get()
  let id2 = parseId("mbx2").get()
  let original = initMailboxIdSet(@[id1, id2])
  let roundTripped = MailboxIdSet.fromJson(original.toJson()).get()
  assertLen roundTripped, 2
  doAssert id1 in roundTripped
  doAssert id2 in roundTripped

# ============= C. MailboxRights serde =============

block fromJsonMailboxRights: # scenario 36
  let node = %*{
    "mayReadItems": true,
    "mayAddItems": false,
    "mayRemoveItems": true,
    "maySetSeen": true,
    "maySetKeywords": false,
    "mayCreateChild": true,
    "mayRename": false,
    "mayDelete": true,
    "maySubmit": false,
  }
  let res = MailboxRights.fromJson(node)
  assertOk res
  let mr = res.get()
  assertEq mr.mayReadItems, true
  assertEq mr.mayAddItems, false
  assertEq mr.mayRemoveItems, true
  assertEq mr.maySetSeen, true
  assertEq mr.maySetKeywords, false
  assertEq mr.mayCreateChild, true
  assertEq mr.mayRename, false
  assertEq mr.mayDelete, true
  assertEq mr.maySubmit, false

block fromJsonMailboxRightsMissing: # scenario 37
  let node = %*{
    "mayReadItems": true,
    "mayAddItems": false,
    "mayRemoveItems": true,
    "maySetSeen": true,
    "maySetKeywords": false,
    "mayCreateChild": true,
    "mayRename": false,
    "mayDelete": true, # maySubmit absent
  }
  assertErr MailboxRights.fromJson(node)

block fromJsonMailboxRightsNonBool: # scenario 38
  let node = %*{
    "mayReadItems": "true",
    "mayAddItems": false,
    "mayRemoveItems": true,
    "maySetSeen": true,
    "maySetKeywords": false,
    "mayCreateChild": true,
    "mayRename": false,
    "mayDelete": true,
    "maySubmit": false,
  }
  assertErr MailboxRights.fromJson(node)

block roundTripMailboxRights: # scenario 39
  let original = MailboxRights(
    mayReadItems: true,
    mayAddItems: false,
    mayRemoveItems: true,
    maySetSeen: true,
    maySetKeywords: false,
    mayCreateChild: true,
    mayRename: false,
    mayDelete: true,
    maySubmit: false,
  )
  let roundTripped = MailboxRights.fromJson(original.toJson()).get()
  assertEq roundTripped.mayReadItems, original.mayReadItems
  assertEq roundTripped.mayAddItems, original.mayAddItems
  assertEq roundTripped.mayRemoveItems, original.mayRemoveItems
  assertEq roundTripped.maySetSeen, original.maySetSeen
  assertEq roundTripped.maySetKeywords, original.maySetKeywords
  assertEq roundTripped.mayCreateChild, original.mayCreateChild
  assertEq roundTripped.mayRename, original.mayRename
  assertEq roundTripped.mayDelete, original.mayDelete
  assertEq roundTripped.maySubmit, original.maySubmit

# ============= D. Mailbox serde =============

block fromJsonMailbox: # scenario 40
  let node = %*{
    "id": "mbx1",
    "name": "Inbox",
    "parentId": "parent1",
    "role": "inbox",
    "sortOrder": 0,
    "totalEmails": 100,
    "unreadEmails": 5,
    "totalThreads": 80,
    "unreadThreads": 3,
    "myRights": {
      "mayReadItems": true,
      "mayAddItems": true,
      "mayRemoveItems": true,
      "maySetSeen": true,
      "maySetKeywords": true,
      "mayCreateChild": false,
      "mayRename": false,
      "mayDelete": false,
      "maySubmit": true,
    },
    "isSubscribed": true,
  }
  let res = Mailbox.fromJson(node)
  assertOk res
  let mbx = res.get()
  assertEq $mbx.id, "mbx1"
  assertEq mbx.name, "Inbox"
  assertSomeEq mbx.parentId, parseId("parent1").get()
  assertSomeEq mbx.role, roleInbox
  assertEq mbx.sortOrder, UnsignedInt(0)
  assertEq mbx.totalEmails, UnsignedInt(100)
  assertEq mbx.unreadEmails, UnsignedInt(5)
  assertEq mbx.totalThreads, UnsignedInt(80)
  assertEq mbx.unreadThreads, UnsignedInt(3)
  assertEq mbx.myRights.mayReadItems, true
  assertEq mbx.isSubscribed, true

block fromJsonMailboxNameAbsent: # scenario 41
  let node = %*{
    "id": "mbx1",
    "parentId": nil,
    "role": nil,
    "sortOrder": 0,
    "totalEmails": 0,
    "unreadEmails": 0,
    "totalThreads": 0,
    "unreadThreads": 0,
    "myRights": {
      "mayReadItems": true,
      "mayAddItems": true,
      "mayRemoveItems": true,
      "maySetSeen": true,
      "maySetKeywords": true,
      "mayCreateChild": true,
      "mayRename": true,
      "mayDelete": true,
      "maySubmit": true,
    },
    "isSubscribed": false,
  }
  assertErr Mailbox.fromJson(node)

block fromJsonMailboxNameEmpty: # scenario 42
  let node = %*{
    "id": "mbx1",
    "name": "",
    "parentId": nil,
    "role": nil,
    "sortOrder": 0,
    "totalEmails": 0,
    "unreadEmails": 0,
    "totalThreads": 0,
    "unreadThreads": 0,
    "myRights": {
      "mayReadItems": true,
      "mayAddItems": true,
      "mayRemoveItems": true,
      "maySetSeen": true,
      "maySetKeywords": true,
      "mayCreateChild": true,
      "mayRename": true,
      "mayDelete": true,
      "maySubmit": true,
    },
    "isSubscribed": false,
  }
  assertErr Mailbox.fromJson(node)

block fromJsonMailboxParentIdNull: # scenario 43
  let node = %*{
    "id": "mbx1",
    "name": "Inbox",
    "parentId": nil,
    "role": nil,
    "sortOrder": 0,
    "totalEmails": 0,
    "unreadEmails": 0,
    "totalThreads": 0,
    "unreadThreads": 0,
    "myRights": {
      "mayReadItems": true,
      "mayAddItems": true,
      "mayRemoveItems": true,
      "maySetSeen": true,
      "maySetKeywords": true,
      "mayCreateChild": true,
      "mayRename": true,
      "mayDelete": true,
      "maySubmit": true,
    },
    "isSubscribed": false,
  }
  let mbx = Mailbox.fromJson(node).get()
  assertNone mbx.parentId

block fromJsonMailboxParentIdPresent: # scenario 44
  let node = %*{
    "id": "mbx1",
    "name": "Inbox",
    "parentId": "p1",
    "role": nil,
    "sortOrder": 0,
    "totalEmails": 0,
    "unreadEmails": 0,
    "totalThreads": 0,
    "unreadThreads": 0,
    "myRights": {
      "mayReadItems": true,
      "mayAddItems": true,
      "mayRemoveItems": true,
      "maySetSeen": true,
      "maySetKeywords": true,
      "mayCreateChild": true,
      "mayRename": true,
      "mayDelete": true,
      "maySubmit": true,
    },
    "isSubscribed": false,
  }
  let mbx = Mailbox.fromJson(node).get()
  assertSome mbx.parentId

block fromJsonMailboxRoleNull: # scenario 45
  let node = %*{
    "id": "mbx1",
    "name": "Inbox",
    "parentId": nil,
    "role": nil,
    "sortOrder": 0,
    "totalEmails": 0,
    "unreadEmails": 0,
    "totalThreads": 0,
    "unreadThreads": 0,
    "myRights": {
      "mayReadItems": true,
      "mayAddItems": true,
      "mayRemoveItems": true,
      "maySetSeen": true,
      "maySetKeywords": true,
      "mayCreateChild": true,
      "mayRename": true,
      "mayDelete": true,
      "maySubmit": true,
    },
    "isSubscribed": false,
  }
  let mbx = Mailbox.fromJson(node).get()
  assertNone mbx.role

block fromJsonMailboxRolePresent: # scenario 46
  let node = %*{
    "id": "mbx1",
    "name": "Inbox",
    "parentId": nil,
    "role": "inbox",
    "sortOrder": 0,
    "totalEmails": 0,
    "unreadEmails": 0,
    "totalThreads": 0,
    "unreadThreads": 0,
    "myRights": {
      "mayReadItems": true,
      "mayAddItems": true,
      "mayRemoveItems": true,
      "maySetSeen": true,
      "maySetKeywords": true,
      "mayCreateChild": true,
      "mayRename": true,
      "mayDelete": true,
      "maySubmit": true,
    },
    "isSubscribed": false,
  }
  let mbx = Mailbox.fromJson(node).get()
  assertSomeEq mbx.role, roleInbox

block fromJsonMailboxRoleUppercase: # scenario 47
  let node = %*{
    "id": "mbx1",
    "name": "Inbox",
    "parentId": nil,
    "role": "INBOX",
    "sortOrder": 0,
    "totalEmails": 0,
    "unreadEmails": 0,
    "totalThreads": 0,
    "unreadThreads": 0,
    "myRights": {
      "mayReadItems": true,
      "mayAddItems": true,
      "mayRemoveItems": true,
      "maySetSeen": true,
      "maySetKeywords": true,
      "mayCreateChild": true,
      "mayRename": true,
      "mayDelete": true,
      "maySubmit": true,
    },
    "isSubscribed": false,
  }
  let mbx = Mailbox.fromJson(node).get()
  assertSomeEq mbx.role, roleInbox

block roundTripMailbox: # scenario 48
  let rights = MailboxRights(
    mayReadItems: true,
    mayAddItems: false,
    mayRemoveItems: true,
    maySetSeen: true,
    maySetKeywords: false,
    mayCreateChild: false,
    mayRename: false,
    mayDelete: true,
    maySubmit: false,
  )
  let original = Mailbox(
    id: parseId("mbx1").get(),
    name: "Inbox",
    parentId: Opt.none(Id),
    role: Opt.some(roleInbox),
    sortOrder: UnsignedInt(0),
    totalEmails: UnsignedInt(100),
    unreadEmails: UnsignedInt(5),
    totalThreads: UnsignedInt(80),
    unreadThreads: UnsignedInt(3),
    myRights: rights,
    isSubscribed: true,
  )
  let roundTripped = Mailbox.fromJson(original.toJson()).get()
  assertEq roundTripped.id, original.id
  assertEq roundTripped.name, original.name
  assertEq roundTripped.parentId, original.parentId
  assertEq roundTripped.role, original.role
  assertEq roundTripped.sortOrder, original.sortOrder
  assertEq roundTripped.totalEmails, original.totalEmails
  assertEq roundTripped.unreadEmails, original.unreadEmails
  assertEq roundTripped.totalThreads, original.totalThreads
  assertEq roundTripped.unreadThreads, original.unreadThreads
  assertEq roundTripped.isSubscribed, original.isSubscribed

block fromJsonMailboxMissingField: # scenario 49
  let node = %*{
    "name": "Inbox",
    "parentId": nil,
    "role": nil,
    "sortOrder": 0,
    "totalEmails": 0,
    "unreadEmails": 0,
    "totalThreads": 0,
    "unreadThreads": 0,
    "myRights": {
      "mayReadItems": true,
      "mayAddItems": true,
      "mayRemoveItems": true,
      "maySetSeen": true,
      "maySetKeywords": true,
      "mayCreateChild": true,
      "mayRename": true,
      "mayDelete": true,
      "maySubmit": true,
    },
    "isSubscribed": false,
  }
  assertErr Mailbox.fromJson(node)

# ============= E. MailboxCreate serde =============

block toJsonMailboxCreate: # scenario 53
  let mc = parseMailboxCreate(
      "Work",
      parentId = Opt.some(parseId("parent1").get()),
      role = Opt.some(roleInbox),
      sortOrder = UnsignedInt(10),
      isSubscribed = true,
    )
    .get()
  let node = mc.toJson()
  assertJsonFieldEq node, "name", %"Work"
  assertJsonFieldEq node, "parentId", newJString("parent1")
  assertJsonFieldEq node, "role", newJString("inbox")
  assertJsonFieldEq node, "sortOrder", newJInt(10)
  assertJsonFieldEq node, "isSubscribed", newJBool(true)

block toJsonMailboxCreateNoServerFields: # scenario 54
  let mc = parseMailboxCreate("Inbox").get()
  let node = mc.toJson()
  doAssert node{"id"} == nil, "id must not be present in MailboxCreate JSON"
  doAssert node{"totalEmails"} == nil, "totalEmails must not be present"
  doAssert node{"unreadEmails"} == nil, "unreadEmails must not be present"
  doAssert node{"totalThreads"} == nil, "totalThreads must not be present"
  doAssert node{"unreadThreads"} == nil, "unreadThreads must not be present"
  doAssert node{"myRights"} == nil, "myRights must not be present"

block toJsonMailboxCreateNullOpts: # scenario 55
  let mc = parseMailboxCreate("Inbox").get()
  let node = mc.toJson()
  assertJsonFieldEq node, "parentId", newJNull()
  assertJsonFieldEq node, "role", newJNull()

# ============= F. MailboxUpdate serde =============

block setNameTuple:
  let (key, value) = makeSetName("Renamed").toJson()
  assertEq key, "name"
  assertEq value, %"Renamed"

block setParentIdNoneEmitsJsonNull:
  ## RFC 8621 §2 reparent-to-top-level is expressed as ``parentId: null`` on
  ## the wire — NOT key-absent. Pins the nullable semantic that distinguishes
  ## "clear the parent" from "don't update the parent".
  let (key, value) = makeSetParentId(Opt.none(Id)).toJson()
  assertEq key, "parentId"
  assertEq value, newJNull()

block setParentIdSomeEmitsString:
  let id1 = parseId("parent1").get()
  let (key, value) = makeSetParentId(Opt.some(id1)).toJson()
  assertEq key, "parentId"
  assertEq value, id1.toJson()

block setRoleNoneEmitsJsonNull:
  ## RFC 8621 §2 clear-role is expressed as ``role: null`` on the wire.
  let (key, value) = makeSetRole(Opt.none(MailboxRole)).toJson()
  assertEq key, "role"
  assertEq value, newJNull()

block setRoleSomeEmitsString:
  let (key, value) = makeSetRole(Opt.some(roleInbox)).toJson()
  assertEq key, "role"
  assertEq value, %"inbox"

block mailboxUpdateSetFlattensTuple:
  let us = makeMailboxUpdateSet(@[makeSetName("X"), makeSetIsSubscribed(false)])
  let node = us.toJson()
  doAssert node.kind == JObject
  assertLen node, 2
  assertJsonFieldEq node, "name", %"X"
  assertJsonFieldEq node, "isSubscribed", %false

block mailboxUpdateSetRoundTripsWireOrder:
  ## Re-stringify / re-parse round-trip guards against accidental
  ## key-order mangling by the flatten aggregator.
  let us = makeMailboxUpdateSet(@[makeSetName("X"), makeSetIsSubscribed(false)])
  let node = us.toJson()
  let reparsed = parseJson($node)
  doAssert reparsed.kind == JObject
  assertLen reparsed, 2
  assertJsonFieldEq reparsed, "name", %"X"
  assertJsonFieldEq reparsed, "isSubscribed", %false

# ============= I. MailboxCreatedItem serde =============

block fromJsonMailboxCreatedItemMinimal:
  ## Stalwart 0.15.5 returns Mailbox/set ``created[cid]`` as just
  ## ``{"id": "<id>"}``, omitting all other server-set fields per its
  ## strict-RFC §5.3 minor divergence. ``MailboxCreatedItem.fromJson``
  ## accepts this shape via the ``Opt`` payload fields.
  let node = parseJson("""{"id":"h"}""")
  let r = MailboxCreatedItem.fromJson(node)
  doAssert r.isOk, $r
  let item = r.get()
  assertEq string(item.id), "h"
  doAssert item.totalEmails.isNone
  doAssert item.unreadEmails.isNone
  doAssert item.totalThreads.isNone
  doAssert item.unreadThreads.isNone
  doAssert item.myRights.isNone

block fromJsonMailboxCreatedItemFull:
  ## RFC 8621 §2.1 server-set subset — every field present. Round-trips
  ## through ``toJson`` symmetrically.
  let node = parseJson(
    """{"id":"h","totalEmails":3,"unreadEmails":1,"totalThreads":2,"unreadThreads":1,
        "myRights":{"mayReadItems":true,"mayAddItems":true,"mayRemoveItems":true,
        "maySetSeen":true,"maySetKeywords":true,"mayCreateChild":true,
        "mayRename":true,"mayDelete":true,"maySubmit":true}}"""
  )
  let r = MailboxCreatedItem.fromJson(node)
  doAssert r.isOk, $r
  let item = r.get()
  doAssert item.totalEmails.isSome and item.totalEmails.get() == UnsignedInt(3)
  doAssert item.unreadEmails.isSome and item.unreadEmails.get() == UnsignedInt(1)
  doAssert item.totalThreads.isSome and item.totalThreads.get() == UnsignedInt(2)
  doAssert item.unreadThreads.isSome and item.unreadThreads.get() == UnsignedInt(1)
  doAssert item.myRights.isSome
  let reparsed = MailboxCreatedItem.fromJson(item.toJson())
  doAssert reparsed.isOk, $reparsed
  doAssert reparsed.get().totalEmails == item.totalEmails

block fromJsonMailboxCreatedItemMissingId:
  ## ``id`` is required per RFC 8620 §5.3 — its absence rejects the item.
  let node = parseJson("""{"totalEmails":0}""")
  let r = MailboxCreatedItem.fromJson(node)
  doAssert r.isErr
