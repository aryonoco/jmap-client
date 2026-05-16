# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for EmailCopyItem and CopyResponse[EmailCreatedItem] (F2 §8.3 copy row,
## F1 §2.2 type-level exclusion). Pins the ``Opt.none → key-absent`` override
## semantics, the ``created`` / ``notCreated`` merge, the required
## ``fromAccountId`` field, and the compile-time guarantee that
## ``CopyResponse[EmailCreatedItem]`` omits the ``/set``-specific ``updated`` /
## ``destroyed`` fields.

{.push raises: [].}

import std/[json, tables]

import jmap_client/internal/mail/email
import jmap_client/internal/mail/keyword
import jmap_client/internal/mail/serde_email
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives
import jmap_client/internal/protocol/methods
import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_primitives
import jmap_client/internal/types/validation

import ../../massertions
import ../../mfixtures
import ../../mtestblock

# ============= A. toJson(EmailCopyItem) =============

testCase emailCopyItemMinimalEmitsIdOnly:
  let id = makeId("src1")
  let node = makeEmailCopyItem(id).toJson()
  doAssert node.kind == JObject
  assertLen node, 1
  assertJsonFieldEq node, "id", id.toJson()

testCase emailCopyItemFullOverrideEmitsThreeKeys:
  ## "Full" here means every override supplied: id + mailboxIds + keywords +
  ## receivedAt — four wire keys. The block name keeps the design-doc wording
  ## ("three overrides on top of the required id"); the assertion pins the
  ## four-key reality.
  let node = makeFullEmailCopyItem().toJson()
  doAssert node.kind == JObject
  assertLen node, 4
  doAssert node{"id"} != nil
  doAssert node{"mailboxIds"} != nil
  doAssert node{"keywords"} != nil
  doAssert node{"receivedAt"} != nil

testCase emailCopyItemOptNoneOmitsKeys:
  ## ``Opt.none`` overrides MUST be omitted, not emitted as ``null`` —
  ## the RFC 8621 §4.7 wire semantics of ``null`` vs key-absent differ:
  ## key-absent = "preserve the source value", null = (not legal here).
  let item = makeEmailCopyItem(
    makeId("src1"),
    mailboxIds = Opt.some(makeNonEmptyMailboxIdSet()),
    keywords = Opt.none(KeywordSet),
    receivedAt = Opt.none(UTCDate),
  )
  let node = item.toJson()
  doAssert node{"mailboxIds"} != nil, "expected mailboxIds present"
  assertJsonKeyAbsent node, "keywords"
  assertJsonKeyAbsent node, "receivedAt"

# ============= B. CopyResponse[EmailCreatedItem].fromJson =============

testCase emailCopyResponseCreatedOnly:
  let node = %*{
    "fromAccountId": "src",
    "accountId": "dst",
    "newState": "s1",
    "created": {"k0": {"id": "e1", "blobId": "b1", "threadId": "t1", "size": 100}},
  }
  let res = CopyResponse[EmailCreatedItem].fromJson(node)
  assertOk res
  let r = res.get()
  assertLen r.createResults, 1
  doAssert makeCreationId("k0") in r.createResults
  doAssert r.createResults[makeCreationId("k0")].isOk

testCase emailCopyResponseNotCreatedOnly:
  let node = %*{
    "fromAccountId": "src",
    "accountId": "dst",
    "newState": "s1",
    "notCreated": {"k1": {"type": "invalidProperties"}},
  }
  let r = CopyResponse[EmailCreatedItem].fromJson(node).get()
  assertLen r.createResults, 1
  doAssert makeCreationId("k1") in r.createResults
  doAssert r.createResults[makeCreationId("k1")].isErr

testCase emailCopyResponseCombined:
  let node = %*{
    "fromAccountId": "src",
    "accountId": "dst",
    "newState": "s1",
    "created": {"k0": {"id": "e1", "blobId": "b1", "threadId": "t1", "size": 100}},
    "notCreated": {"k1": {"type": "invalidProperties"}},
  }
  let r = CopyResponse[EmailCreatedItem].fromJson(node).get()
  assertLen r.createResults, 2
  doAssert r.createResults[makeCreationId("k0")].isOk
  doAssert r.createResults[makeCreationId("k1")].isErr

# ============= C. Required field =============

testCase emailCopyResponseRequiresFromAccountId:
  ## RFC 8621 §4.7: ``fromAccountId`` is mandatory (it names the source
  ## account the copy originated from). Parser must reject its absence.
  let node = %*{"accountId": "dst", "newState": "s1"}
  assertErr CopyResponse[EmailCreatedItem].fromJson(node)

# ============= D. Type-level exclusion (compile-time pin) =============

testCase emailCopyResponseHasNoUpdatedField:
  ## Pins F1 §2.2's type-level guarantee: ``CopyResponse[EmailCreatedItem]`` has NO
  ## ``updated`` (nor ``destroyed``) field — those belong to ``/set`` only.
  ## Structured as ``assertNotCompiles`` so an accidental field addition
  ## to the type breaks the test rather than a runtime assertion.
  assertNotCompiles(
    block:
      let r: CopyResponse[EmailCreatedItem] = default(CopyResponse[EmailCreatedItem])
      discard r.updated
  )
