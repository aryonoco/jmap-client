# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for EmailUpdate smart constructors — both the six
## protocol-primitive constructors and the five domain-named
## convenience wrappers. Pins F1 §3.2.1 + §3.2.3.1.
##
## Comparisons avoid ``$EmailUpdate`` (case object has no ``$``) and
## ``$KeywordSet`` / ``==KeywordSet`` (Decision B3 suppresses set
## equality on read-model sets). Convenience-equivalence blocks fold
## back to (kind, payload) field-by-field checks — strictly stronger
## than auto-gen ``==`` on the case object and informative on failure.

{.push raises: [].}

import jmap_client/mail/email_update
import jmap_client/mail/keyword
import jmap_client/mail/mailbox
import jmap_client/validation
import jmap_client/primitives

import ../../massertions

# ============= A. Protocol-primitive constructor shape =============

block addKeywordConstructsCorrectKind:
  let k = parseKeyword("$flagged").get()
  let u = addKeyword(k)
  assertEq u.kind, euAddKeyword
  assertEq u.keyword, k

block removeKeywordConstructsCorrectKind:
  let k = parseKeyword("$flagged").get()
  let u = removeKeyword(k)
  assertEq u.kind, euRemoveKeyword
  assertEq u.keyword, k

block setKeywordsConstructsCorrectKind:
  let ks = initKeywordSet(@[kwSeen, kwFlagged])
  let u = setKeywords(ks)
  assertEq u.kind, euSetKeywords
  assertEq u.keywords.len, 2
  doAssert kwSeen in u.keywords, "expected kwSeen in keywords payload"
  doAssert kwFlagged in u.keywords, "expected kwFlagged in keywords payload"

block addToMailboxConstructsCorrectKind:
  let id = parseId("m1").get()
  let u = addToMailbox(id)
  assertEq u.kind, euAddToMailbox
  assertEq u.mailboxId, id

block removeFromMailboxConstructsCorrectKind:
  let id = parseId("m1").get()
  let u = removeFromMailbox(id)
  assertEq u.kind, euRemoveFromMailbox
  assertEq u.mailboxId, id

block setMailboxIdsConstructsCorrectKind:
  let id = parseId("m1").get()
  let ids = parseNonEmptyMailboxIdSet(@[id]).get()
  let u = setMailboxIds(ids)
  assertEq u.kind, euSetMailboxIds
  assertEq u.mailboxes, ids

# ============= B. Convenience-equivalence =============

block markReadEqualsAddKeywordSeen:
  let r = markRead()
  assertEq r.kind, euAddKeyword
  assertEq r.keyword, kwSeen

block markUnreadEqualsRemoveKeywordSeen:
  let r = markUnread()
  assertEq r.kind, euRemoveKeyword
  assertEq r.keyword, kwSeen

block markFlaggedEqualsAddKeywordFlagged:
  let r = markFlagged()
  assertEq r.kind, euAddKeyword
  assertEq r.keyword, kwFlagged

block markUnflaggedEqualsRemoveKeywordFlagged:
  let r = markUnflagged()
  assertEq r.kind, euRemoveKeyword
  assertEq r.keyword, kwFlagged

block moveToMailboxEqualsSetMailboxIdsSingleton: # F21 pin
  let id = parseId("m1").get()
  let expected = parseNonEmptyMailboxIdSet(@[id]).get()
  let u = moveToMailbox(id)
  assertEq u.kind, euSetMailboxIds
  assertEq u.mailboxes, expected

# ============= C. Negative discrimination =============

block moveToMailboxDistinctIds:
  let id1 = parseId("m1").get()
  let id2 = parseId("m2").get()
  let u1 = moveToMailbox(id1)
  let u2 = moveToMailbox(id2)
  assertEq u1.kind, euSetMailboxIds
  assertEq u2.kind, euSetMailboxIds
  doAssert u1.mailboxes != u2.mailboxes,
    "distinct ids must produce distinct mailboxes payloads"

block addKeywordDistinctKeywords:
  let k1 = parseKeyword("$flag1").get()
  let k2 = parseKeyword("$flag2").get()
  let u1 = addKeyword(k1)
  let u2 = addKeyword(k2)
  assertEq u1.kind, euAddKeyword
  assertEq u2.kind, euAddKeyword
  doAssert u1.keyword != u2.keyword,
    "distinct keywords must produce distinct keyword payloads"
