# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for initEmailUpdateSet. Pins F1 §3.2.4 conflict-algebra
## shape enumeration per F2 §8.7, plus the Class 2-wins-over-Class 1
## overlap policy (§8.7.2) and the "one error per detected conflict"
## accumulation contract.

{.push raises: [].}

import jmap_client/internal/mail/email_update
import jmap_client/internal/mail/keyword
import jmap_client/internal/mail/mailbox
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives

import ../../massertions

# ============= A. Empty input =============

block emailUpdateSetEmpty: # F22
  let res = initEmailUpdateSet(@[])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "EmailUpdateSet"
  assertEq res.error[0].message, "must contain at least one update"
  assertEq res.error[0].value, ""

# ============= B. Class 1 — duplicate target path (6 shapes) =============

block class1TwoAddKeyword: # §8.7.1 row 1
  let k = parseKeyword("$seen").get()
  let res = initEmailUpdateSet(@[addKeyword(k), addKeyword(k)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "EmailUpdateSet"
  assertEq res.error[0].message, "duplicate target path"
  assertEq res.error[0].value, "keywords/$seen"

block class1TwoRemoveKeyword: # §8.7.1 row 2
  let k = parseKeyword("$seen").get()
  let res = initEmailUpdateSet(@[removeKeyword(k), removeKeyword(k)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "duplicate target path"
  assertEq res.error[0].value, "keywords/$seen"

block class1TwoSetKeywords: # §8.7.1 row 3
  let ks1 = initKeywordSet(@[kwSeen])
  let ks2 = initKeywordSet(@[kwFlagged])
  let res = initEmailUpdateSet(@[setKeywords(ks1), setKeywords(ks2)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "duplicate target path"
  assertEq res.error[0].value, "keywords"

block class1TwoAddToMailbox: # §8.7.1 row 4
  let id = parseId("m1").get()
  let res = initEmailUpdateSet(@[addToMailbox(id), addToMailbox(id)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "duplicate target path"
  assertEq res.error[0].value, "mailboxIds/m1"

block class1TwoRemoveFromMailbox: # §8.7.1 row 5
  let id = parseId("m1").get()
  let res = initEmailUpdateSet(@[removeFromMailbox(id), removeFromMailbox(id)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "duplicate target path"
  assertEq res.error[0].value, "mailboxIds/m1"

block class1TwoSetMailboxIds: # §8.7.1 row 6
  let id1 = parseId("m1").get()
  let id2 = parseId("m2").get()
  let ids1 = parseNonEmptyMailboxIdSet(@[id1]).get()
  let ids2 = parseNonEmptyMailboxIdSet(@[id2]).get()
  let res = initEmailUpdateSet(@[setMailboxIds(ids1), setMailboxIds(ids2)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "duplicate target path"
  assertEq res.error[0].value, "mailboxIds"

# ============= C. Class 2 — opposite operations (2 shapes) =============

block class2KeywordOpposite: # §8.7.2 row 1
  let k = parseKeyword("$seen").get()
  let res = initEmailUpdateSet(@[addKeyword(k), removeKeyword(k)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "EmailUpdateSet"
  assertEq res.error[0].message, "opposite operations on same sub-path"
  assertEq res.error[0].value, "keywords/$seen"

block class2MailboxOpposite: # §8.7.2 row 2
  let id = parseId("m1").get()
  let res = initEmailUpdateSet(@[addToMailbox(id), removeFromMailbox(id)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "opposite operations on same sub-path"
  assertEq res.error[0].value, "mailboxIds/m1"

# ============= D. Class 3 — sub-path alongside full-replace (4 shapes) =============

block class3AddKeywordSetKeywords: # §8.7.3 row 1
  let k = parseKeyword("$seen").get()
  let ks = initKeywordSet(@[kwFlagged])
  let res = initEmailUpdateSet(@[addKeyword(k), setKeywords(ks)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "EmailUpdateSet"
  assertEq res.error[0].message,
    "sub-path operation alongside full-replace on same parent"
  assertEq res.error[0].value, "keywords"

block class3RemoveKeywordSetKeywords: # §8.7.3 row 2
  let k = parseKeyword("$seen").get()
  let ks = initKeywordSet(@[kwFlagged])
  let res = initEmailUpdateSet(@[removeKeyword(k), setKeywords(ks)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message,
    "sub-path operation alongside full-replace on same parent"
  assertEq res.error[0].value, "keywords"

block class3AddToMailboxSetMailboxIds: # §8.7.3 row 3
  let id1 = parseId("m1").get()
  let id2 = parseId("m2").get()
  let ids = parseNonEmptyMailboxIdSet(@[id2]).get()
  let res = initEmailUpdateSet(@[addToMailbox(id1), setMailboxIds(ids)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message,
    "sub-path operation alongside full-replace on same parent"
  assertEq res.error[0].value, "mailboxIds"

block class3RemoveFromMailboxSetMailboxIds: # §8.7.3 row 4
  let id1 = parseId("m1").get()
  let id2 = parseId("m2").get()
  let ids = parseNonEmptyMailboxIdSet(@[id2]).get()
  let res = initEmailUpdateSet(@[removeFromMailbox(id1), setMailboxIds(ids)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message,
    "sub-path operation alongside full-replace on same parent"
  assertEq res.error[0].value, "mailboxIds"

# ============= E. Class 1 + 2 overlap (Class 2 wins) =============

block class1And2Overlap: # F2 §8.12 policy row
  ## Same sub-path + opposite kinds. The shipped samePathConflicts
  ## emits ckOppositeOps (not ckDuplicatePath) when kinds differ —
  ## Class 2 strictly dominates Class 1 here.
  let k = parseKeyword("$seen").get()
  let res = initEmailUpdateSet(@[addKeyword(k), removeKeyword(k)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "EmailUpdateSet"
  assertEq res.error[0].message, "opposite operations on same sub-path"
  assertEq res.error[0].value, "keywords/$seen"

# ============= F. Independent — positive §8.7.4 (4 shapes) =============

block independentSetKeywordsSetMailboxIds: # §8.7.4 row 1
  let ks = initKeywordSet(@[kwSeen])
  let id = parseId("m1").get()
  let ids = parseNonEmptyMailboxIdSet(@[id]).get()
  assertOk initEmailUpdateSet(@[setKeywords(ks), setMailboxIds(ids)])

block independentDistinctAddKeywords: # §8.7.4 row 2
  let k1 = parseKeyword("$a").get()
  let k2 = parseKeyword("$b").get()
  assertOk initEmailUpdateSet(@[addKeyword(k1), addKeyword(k2)])

block independentAddKeywordAddToMailbox: # §8.7.4 row 3
  let k = parseKeyword("$seen").get()
  let id = parseId("m1").get()
  assertOk initEmailUpdateSet(@[addKeyword(k), addToMailbox(id)])

block independentDistinctMailboxOpposite: # §8.7.4 row 4 (diagonal closure)
  let id1 = parseId("m1").get()
  let id2 = parseId("m2").get()
  assertOk initEmailUpdateSet(@[addToMailbox(id1), removeFromMailbox(id2)])

# ============= G. Accumulation =============

block accumulateMixedClasses:
  ## One Class 1 + one Class 2 + one Class 3 = 3 errors.
  ## Classes are constructed on independent parents so they don't
  ## further collide with each other.
  let k1 = parseKeyword("$a").get() # Class 1 duplicate target
  let k2 = parseKeyword("$b").get() # Class 2 opposite-op
  let id = parseId("m1").get() # Class 3 sub-path + full-replace
  let ids = parseNonEmptyMailboxIdSet(@[id]).get()
  let res = initEmailUpdateSet(
    @[
      addKeyword(k1),
      addKeyword(k1), # duplicates with line above → Class 1
      addKeyword(k2),
      removeKeyword(k2), # opposite of line above → Class 2
      addToMailbox(id),
      setMailboxIds(ids), # Class 3 on mailboxIds parent
    ]
  )
  assertErr res
  assertLen res.error, 3

block accumulateClass3TwoDistinctParents:
  ## Two distinct Class 3 violations, one per parent. ``parentPrefixConflicts``
  ## emits per-parent in the (replaced ∩ sub-pathed) intersection — the
  ## number of sub-path ops sharing a parent with a full-replace does NOT
  ## multiply the emission, so two sub-path ops on ``keywords`` + one
  ## full-replace on ``keywords`` still yields ONE Class 3 on the
  ## ``keywords`` parent. Per-op granularity would require a different
  ## detection algorithm.
  let k1 = parseKeyword("$a").get()
  let k2 = parseKeyword("$b").get()
  let ks = initKeywordSet(@[kwSeen])
  let id = parseId("m1").get()
  let ids = parseNonEmptyMailboxIdSet(@[id]).get()
  let res = initEmailUpdateSet(
    @[
      addKeyword(k1),
      removeKeyword(k2),
      setKeywords(ks), # Class 3 on keywords parent (1 emission)
      addToMailbox(id),
      setMailboxIds(ids), # Class 3 on mailboxIds parent (1 emission)
    ]
  )
  assertErr res
  assertLen res.error, 2

# ============= F. parseNonEmptyEmailUpdates =============

block parseNonEmptyEmailUpdatesRejectsEmpty:
  ## Empty input is rejected — the /set builder's ``update`` slot has
  ## exactly one "no updates" representation (``Opt.none``).
  let res = parseNonEmptyEmailUpdates(newSeq[(Id, EmailUpdateSet)]())
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "NonEmptyEmailUpdates"
  assertEq res.error[0].message, "must contain at least one entry"

block parseNonEmptyEmailUpdatesRejectsDuplicateId:
  ## Duplicate ``Id`` keys are rejected — silent last-wins shadowing at
  ## Table construction would swallow caller data.
  let id1 = parseId("e1").get()
  let us1 = initEmailUpdateSet(@[markRead()]).get()
  let us2 = initEmailUpdateSet(@[markFlagged()]).get()
  let res = parseNonEmptyEmailUpdates(@[(id1, us1), (id1, us2)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "duplicate email id"
