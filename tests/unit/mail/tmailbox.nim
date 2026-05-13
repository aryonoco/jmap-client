# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Mailbox types (scenarios 23-27, 30-31, 50-52;
## Part E §6.1.3 scenarios 24-27a).

{.push raises: [].}

import jmap_client/internal/mail/mailbox
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives

import ../../massertions
import ../../mtestblock

# ============= A. parseMailboxRole =============

testCase parseMailboxRoleValid: # scenario 23
  assertOkEq parseMailboxRole("inbox"), roleInbox

testCase parseMailboxRoleUppercase: # scenario 24
  assertOkEq parseMailboxRole("INBOX"), roleInbox

testCase parseMailboxRoleCustom: # scenario 25
  let res = parseMailboxRole("CustomRole")
  assertOk res
  let role = res.get()
  assertEq role.kind, mrOther
  assertEq role.identifier, "customrole"

testCase parseMailboxRoleEmpty: # scenario 26
  assertErrFields parseMailboxRole(""), "MailboxRole", "must not be empty", ""

testCase mailboxRoleConstants: # scenario 27
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

testCase initMailboxIdSetWithIds: # scenario 30
  let id1 = parseIdFromServer("mbx1").get()
  let id2 = parseIdFromServer("mbx2").get()
  let ms = initMailboxIdSet(@[id1, id2])
  assertLen ms, 2
  doAssert id1 in ms
  doAssert id2 in ms

testCase initMailboxIdSetEmpty: # scenario 31
  let ms = initMailboxIdSet(@[])
  assertLen ms, 0

# ============= C. MailboxCreate =============

testCase parseMailboxCreateDefaults: # scenario 50
  let res = parseMailboxCreate("Inbox")
  assertOk res
  let mc = res.get()
  assertEq mc.name, "Inbox"
  assertNone mc.parentId
  assertNone mc.role
  assertEq mc.sortOrder, parseUnsignedInt(0).get()
  assertEq mc.isSubscribed, false

testCase parseMailboxCreateAllFields: # scenario 51
  let pid = parseIdFromServer("parent1").get()
  let res = parseMailboxCreate(
    "Work",
    parentId = Opt.some(pid),
    role = Opt.some(roleInbox),
    sortOrder = parseUnsignedInt(10).get(),
    isSubscribed = true,
  )
  assertOk res
  let mc = res.get()
  assertEq mc.name, "Work"
  assertSomeEq mc.parentId, pid
  assertSomeEq mc.role, roleInbox
  assertEq mc.sortOrder, parseUnsignedInt(10).get()
  assertEq mc.isSubscribed, true

testCase parseMailboxCreateEmptyName: # scenario 52
  assertErrFields parseMailboxCreate(""), "MailboxCreate", "name must not be empty", ""

# ============= D. NonEmptyMailboxIdSet (Part E §6.1.3 scenarios 24–27a) =============

testCase parseNonEmptyMailboxIdSetSingle: # §6.1.3 scenario 24
  let id1 = parseIdFromServer("mbx1").get()
  let res = parseNonEmptyMailboxIdSet(@[id1])
  assertOk res
  assertLen res.get(), 1

testCase parseNonEmptyMailboxIdSetEmptyRejected: # §6.1.3 scenario 25
  assertErrType parseNonEmptyMailboxIdSet(@[]), "NonEmptyMailboxIdSet"

testCase parseNonEmptyMailboxIdSetDedup: # §6.1.3 scenario 26
  let id1 = parseIdFromServer("mbx1").get()
  let id2 = parseIdFromServer("mbx2").get()
  let res = parseNonEmptyMailboxIdSet(@[id1, id2, id1])
  assertOk res
  assertLen res.get(), 2

testCase parseNonEmptyMailboxIdSetEqualityAndHash: # §6.1.3 scenario 27
  let id1 = parseIdFromServer("mbx1").get()
  let id2 = parseIdFromServer("mbx2").get()
  let a = parseNonEmptyMailboxIdSet(@[id1, id2]).get()
  let b = parseNonEmptyMailboxIdSet(@[id2, id1]).get()
  assertEq a, b

testCase parseNonEmptyMailboxIdSetMutabilityGuard: # §6.1.3 scenario 27a
  let id1 = parseIdFromServer("mbx1").get()
  let s = parseNonEmptyMailboxIdSet(@[id1]).get()
  # Any Id value suffices to probe whether `incl` / `excl` / `clear` are
  # borrowed — the arguments never evaluate at runtime under
  # `assertNotCompiles`.
  assertNotCompiles s.incl(id1)
  assertNotCompiles s.excl(id1)
  assertNotCompiles s.clear()

# ============= E. initMailboxUpdateSet =============
#
# Uniqueness-by-kind contract: each distinct repeated ``kind`` yields
# exactly one error regardless of how many times it occurs. N
# duplicates of the same kind therefore produce ONE error, not N-1.

testCase initMailboxUpdateSetEmpty:
  let res = initMailboxUpdateSet(@[])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "MailboxUpdateSet"
  assertEq res.error[0].message, "must contain at least one update"
  assertEq res.error[0].value, ""

testCase initMailboxUpdateSetSingleValid:
  assertOk initMailboxUpdateSet(@[setName("Inbox")])

testCase initMailboxUpdateSetTwoSameKind:
  let res = initMailboxUpdateSet(@[setName("A"), setName("B")])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "MailboxUpdateSet"
  assertEq res.error[0].message, "duplicate target property"
  assertEq res.error[0].value, "muSetName"

testCase initMailboxUpdateSetThreeSameKind:
  ## Three occurrences of the same kind still yield ONE error —
  ## the Haskell-style "each repeated key reported once" contract.
  let res = initMailboxUpdateSet(@[setName("A"), setName("B"), setName("C")])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].value, "muSetName"

testCase initMailboxUpdateSetTwoDistinctRepeated:
  ## Two distinct repeated kinds → TWO errors, one per distinct
  ## duplicate key. Verifies the output set via set-membership so the
  ## test does not depend on error ordering.
  let pid = parseIdFromServer("p1").get()
  let res = initMailboxUpdateSet(
    @[setName("A"), setName("B"), setParentId(Opt.some(pid)), setParentId(Opt.none(Id))]
  )
  assertErr res
  assertLen res.error, 2
  var seen: set[MailboxUpdateVariantKind] = {}
  for e in res.error:
    assertEq e.typeName, "MailboxUpdateSet"
    assertEq e.message, "duplicate target property"
    if e.value == "muSetName":
      seen.incl muSetName
    elif e.value == "muSetParentId":
      seen.incl muSetParentId
  doAssert muSetName in seen
  doAssert muSetParentId in seen

# ============= F. MailboxUpdate setter-shape =============

testCase setNameConstructsCorrectKind:
  let u = setName("Inbox")
  assertEq u.kind, muSetName
  assertEq u.name, "Inbox"

testCase setParentIdNoneConstructsCorrectKind:
  let u = setParentId(Opt.none(Id))
  assertEq u.kind, muSetParentId
  assertNone u.parentId

testCase setParentIdSomeConstructsCorrectKind:
  let pid = parseIdFromServer("parent1").get()
  let u = setParentId(Opt.some(pid))
  assertEq u.kind, muSetParentId
  assertSomeEq u.parentId, pid

testCase setRoleConstructsCorrectKind:
  let u = setRole(Opt.some(roleInbox))
  assertEq u.kind, muSetRole
  assertSomeEq u.role, roleInbox

testCase setSortOrderConstructsCorrectKind:
  let u = setSortOrder(parseUnsignedInt(5).get())
  assertEq u.kind, muSetSortOrder
  assertEq u.sortOrder, parseUnsignedInt(5).get()

testCase setIsSubscribedConstructsCorrectKind:
  let u = setIsSubscribed(true)
  assertEq u.kind, muSetIsSubscribed
  assertEq u.isSubscribed, true

# ============= F. parseNonEmptyMailboxUpdates =============

testCase parseNonEmptyMailboxUpdatesRejectsEmpty:
  ## Empty input is explicitly rejected — the /set builder has exactly
  ## one "no updates" representation (``Opt.none``), so an empty wrapper
  ## is structurally forbidden.
  let res = parseNonEmptyMailboxUpdates(newSeq[(Id, MailboxUpdateSet)]())
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "NonEmptyMailboxUpdates"
  assertEq res.error[0].message, "must contain at least one entry"

testCase parseNonEmptyMailboxUpdatesRejectsDuplicateId:
  ## Duplicate ``Id`` keys are rejected — silent last-wins shadowing at
  ## Table construction would swallow caller data. The ``openArray`` input
  ## preserves duplicates for inspection.
  let id1 = parseIdFromServer("mb1").get()
  let us1 = initMailboxUpdateSet(@[setName("A")]).get()
  let us2 = initMailboxUpdateSet(@[setName("B")]).get()
  let res = parseNonEmptyMailboxUpdates(@[(id1, us1), (id1, us2)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "duplicate mailbox id"
