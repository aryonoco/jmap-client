# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for EmailCopyItem. Pins F1 §6.1 type-level rejection
## of empty / wrong-distinct mailbox-id overrides, plus structural
## readback for minimal and full-override construction.

{.push raises: [].}

import jmap_client/mail/email
import jmap_client/mail/mailbox
import jmap_client/mail/keyword
import jmap_client/validation
import jmap_client/primitives

import ../../massertions

# ============= A. Type-level rejection =============

block copyItemTypeRejectsEmptyMailboxIdSet: # F1 §6.1
  ## initMailboxIdSet returns MailboxIdSet; override slot is
  ## Opt[NonEmptyMailboxIdSet]. An empty MailboxIdSet literal fails
  ## at the distinct-type gate, not at a runtime check.
  let id1 = parseId("m1").get()
  discard id1 # reference to keep scope under assertNotCompiles tight
  assertNotCompiles(
    initEmailCopyItem(id = id1, mailboxIds = Opt.some(initMailboxIdSet(@[])))
  )

block copyItemTypeRejectsNonEmptyMailboxIdSetWrongDistinct: # F1 §6.1
  ## Populated MailboxIdSet is STILL the wrong distinct — the slot
  ## demands NonEmptyMailboxIdSet. Separates the empty-rejection
  ## axis from the distinct-type axis.
  let id1 = parseId("m1").get()
  assertNotCompiles(
    initEmailCopyItem(id = id1, mailboxIds = Opt.some(initMailboxIdSet(@[id1])))
  )

# ============= B. Structural readback =============

block copyItemIdOnlyRoundTrip:
  let id = parseId("e1").get()
  let ci = initEmailCopyItem(id = id)
  assertEq ci.id, id
  assertNone ci.mailboxIds
  assertNone ci.keywords
  assertNone ci.receivedAt

block copyItemAllOverridesPopulated:
  let id = parseId("e1").get()
  let mbx = parseId("m1").get()
  let ids = parseNonEmptyMailboxIdSet(@[mbx]).get()
  let ks = initKeywordSet(@[kwSeen])
  let dt = parseUtcDate("2026-04-15T12:00:00Z").get()
  let ci = initEmailCopyItem(
    id = id,
    mailboxIds = Opt.some(ids),
    keywords = Opt.some(ks),
    receivedAt = Opt.some(dt),
  )
  assertEq ci.id, id
  assertSomeEq ci.mailboxIds, ids
  assertSome ci.keywords
  assertEq ci.keywords.get().len, 1
  doAssert kwSeen in ci.keywords.get()
  assertSomeEq ci.receivedAt, dt
