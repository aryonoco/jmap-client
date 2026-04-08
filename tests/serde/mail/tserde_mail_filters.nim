# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for MailboxFilterCondition (scenarios 56-62).

{.push raises: [].}

import std/json

import jmap_client/mail/mailbox
import jmap_client/mail/mail_filters
import jmap_client/mail/serde_mail_filters
import jmap_client/validation
import jmap_client/primitives

import ../../massertions

# ============= A. MailboxFilterCondition toJson =============

block toJsonAllNone: # scenario 56
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

block toJsonParentIdNull: # scenario 57
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

block toJsonParentIdValue: # scenario 58
  let id1 = parseId("id1").get()
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

block toJsonRoleNull: # scenario 59
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

block toJsonRoleValue: # scenario 60
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

block toJsonName: # scenario 61
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

block toJsonMixed: # scenario 62
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
