# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for EmailImportItem. Pins F1 §6.1 constraints:
## mailboxIds is non-Opt (required per RFC §4.8), and keywords is
## Opt[KeywordSet] with three distinguishable states.

{.push raises: [].}

import jmap_client/mail/email
import jmap_client/mail/mailbox
import jmap_client/mail/keyword
import jmap_client/validation
import jmap_client/primitives

import ../../massertions

# ============= A. Type-level rejection =============

block importItemRejectsOptNoneMailboxIds: # F1 §6.1
  ## mailboxIds is non-Opt NonEmptyMailboxIdSet. Passing Opt.none
  ## (or any Opt wrapper) is a compile error at the call-site.
  let b = parseId("blob1").get()
  assertNotCompiles(
    initEmailImportItem(blobId = b, mailboxIds = Opt.none(NonEmptyMailboxIdSet))
  )

# ============= B. Minimal construction =============

block importItemMinimalConstruction:
  let b = parseId("blob1").get()
  let mbx = parseId("m1").get()
  let ids = parseNonEmptyMailboxIdSet(@[mbx]).get()
  let i = initEmailImportItem(b, ids)
  assertEq i.blobId, b
  assertEq i.mailboxIds, ids
  assertNone i.keywords
  assertNone i.receivedAt

# ============= C. keywords three states =============

block importItemKeywordsThreeStates:
  ## Opt.none / Opt.some(empty) / Opt.some(non-empty) are three
  ## distinguishable states at the value layer. Phase 3 serde pins
  ## the first two collapse to "omit the key" on the wire.
  let b = parseId("blob1").get()
  let mbx = parseId("m1").get()
  let ids = parseNonEmptyMailboxIdSet(@[mbx]).get()
  let absent = initEmailImportItem(b, ids)
  assertNone absent.keywords

  let emptySet = initKeywordSet(@[])
  let withEmpty = initEmailImportItem(b, ids, keywords = Opt.some(emptySet))
  assertSome withEmpty.keywords
  assertEq withEmpty.keywords.get().len, 0

  let fullSet = initKeywordSet(@[kwSeen, kwFlagged])
  let withFull = initEmailImportItem(b, ids, keywords = Opt.some(fullSet))
  assertSome withFull.keywords
  assertEq withFull.keywords.get().len, 2
