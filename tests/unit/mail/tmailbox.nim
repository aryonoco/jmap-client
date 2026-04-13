# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Mailbox types (scenarios 23-27, 30-31, 50-52;
## Part E §6.1.3 scenarios 24-27a).

{.push raises: [].}

import jmap_client/mail/mailbox
import jmap_client/validation
import jmap_client/primitives

import ../../massertions

# ============= A. parseMailboxRole =============

block parseMailboxRoleValid: # scenario 23
  assertOkEq parseMailboxRole("inbox"), roleInbox

block parseMailboxRoleUppercase: # scenario 24
  assertOkEq parseMailboxRole("INBOX"), roleInbox

block parseMailboxRoleCustom: # scenario 25
  let res = parseMailboxRole("CustomRole")
  assertOk res
  assertEq res.get(), MailboxRole("customrole")

block parseMailboxRoleEmpty: # scenario 26
  assertErrFields parseMailboxRole(""), "MailboxRole", "must not be empty", ""

block mailboxRoleConstants: # scenario 27
  assertOkEq parseMailboxRole("inbox"), roleInbox
  assertOkEq parseMailboxRole("drafts"), roleDrafts
  assertOkEq parseMailboxRole("sent"), roleSent
  assertOkEq parseMailboxRole("trash"), roleTrash
  assertOkEq parseMailboxRole("junk"), roleJunk
  assertOkEq parseMailboxRole("archive"), roleArchive
  assertOkEq parseMailboxRole("important"), roleImportant
  assertOkEq parseMailboxRole("all"), roleAll
  assertOkEq parseMailboxRole("flagged"), roleFlagged
  assertOkEq parseMailboxRole("subscriptions"), roleSubscriptions

# ============= B. MailboxIdSet =============

block initMailboxIdSetWithIds: # scenario 30
  let id1 = parseId("mbx1").get()
  let id2 = parseId("mbx2").get()
  let ms = initMailboxIdSet(@[id1, id2])
  assertLen ms, 2
  doAssert id1 in ms
  doAssert id2 in ms

block initMailboxIdSetEmpty: # scenario 31
  let ms = initMailboxIdSet(@[])
  assertLen ms, 0

# ============= C. MailboxCreate =============

block parseMailboxCreateDefaults: # scenario 50
  let res = parseMailboxCreate("Inbox")
  assertOk res
  let mc = res.get()
  assertEq mc.name, "Inbox"
  assertNone mc.parentId
  assertNone mc.role
  assertEq mc.sortOrder, UnsignedInt(0)
  assertEq mc.isSubscribed, false

block parseMailboxCreateAllFields: # scenario 51
  let pid = parseId("parent1").get()
  let res = parseMailboxCreate(
    "Work",
    parentId = Opt.some(pid),
    role = Opt.some(roleInbox),
    sortOrder = UnsignedInt(10),
    isSubscribed = true,
  )
  assertOk res
  let mc = res.get()
  assertEq mc.name, "Work"
  assertSomeEq mc.parentId, pid
  assertSomeEq mc.role, roleInbox
  assertEq mc.sortOrder, UnsignedInt(10)
  assertEq mc.isSubscribed, true

block parseMailboxCreateEmptyName: # scenario 52
  assertErrFields parseMailboxCreate(""), "MailboxCreate", "name must not be empty", ""

# ============= D. NonEmptyMailboxIdSet (Part E §6.1.3 scenarios 24–27a) =============

block parseNonEmptyMailboxIdSetSingle: # §6.1.3 scenario 24
  let id1 = parseId("mbx1").get()
  let res = parseNonEmptyMailboxIdSet(@[id1])
  assertOk res
  assertLen res.get(), 1

block parseNonEmptyMailboxIdSetEmptyRejected: # §6.1.3 scenario 25
  assertErrType parseNonEmptyMailboxIdSet(@[]), "NonEmptyMailboxIdSet"

block parseNonEmptyMailboxIdSetDedup: # §6.1.3 scenario 26
  let id1 = parseId("mbx1").get()
  let id2 = parseId("mbx2").get()
  let res = parseNonEmptyMailboxIdSet(@[id1, id2, id1])
  assertOk res
  assertLen res.get(), 2

block parseNonEmptyMailboxIdSetEqualityAndHash: # §6.1.3 scenario 27
  let id1 = parseId("mbx1").get()
  let id2 = parseId("mbx2").get()
  let a = parseNonEmptyMailboxIdSet(@[id1, id2]).get()
  let b = parseNonEmptyMailboxIdSet(@[id2, id1]).get()
  assertEq a, b

block parseNonEmptyMailboxIdSetMutabilityGuard: # §6.1.3 scenario 27a
  let id1 = parseId("mbx1").get()
  let s = parseNonEmptyMailboxIdSet(@[id1]).get()
  # Any Id value suffices to probe whether `incl` / `excl` / `clear` are
  # borrowed — the arguments never evaluate at runtime under
  # `assertNotCompiles`.
  assertNotCompiles s.incl(id1)
  assertNotCompiles s.excl(id1)
  assertNotCompiles s.clear()
