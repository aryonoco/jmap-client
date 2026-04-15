# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for EmailCopyItem and EmailCopyResponse (F2 §8.3 copy row,
## F1 §2.2 type-level exclusion). Pins the ``Opt.none → key-absent`` override
## semantics, the ``created`` / ``notCreated`` merge, the required
## ``fromAccountId`` field, and the compile-time guarantee that
## ``EmailCopyResponse`` omits the ``/set``-specific ``updated`` /
## ``destroyed`` fields.

{.push raises: [].}

import std/[json, tables]

import jmap_client/mail/email
import jmap_client/mail/keyword
import jmap_client/mail/serde_email
import jmap_client/identifiers
import jmap_client/primitives
import jmap_client/serde
import jmap_client/validation

import ../../massertions
import ../../mfixtures

# ============= A. toJson(EmailCopyItem) =============

block emailCopyItemMinimalEmitsIdOnly:
  let id = makeId("src1")
  let node = makeEmailCopyItem(id).toJson()
  doAssert node.kind == JObject
  assertLen node, 1
  assertJsonFieldEq node, "id", id.toJson()

block emailCopyItemFullOverrideEmitsThreeKeys:
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

block emailCopyItemOptNoneOmitsKeys:
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

# ============= B. EmailCopyResponse.fromJson =============

block emailCopyResponseCreatedOnly:
  let node = %*{
    "fromAccountId": "src",
    "accountId": "dst",
    "newState": "s1",
    "created": {"k0": {"id": "e1", "blobId": "b1", "threadId": "t1", "size": 100}},
  }
  let res = EmailCopyResponse.fromJson(node)
  assertOk res
  let r = res.get()
  assertLen r.createResults, 1
  doAssert makeCreationId("k0") in r.createResults
  doAssert r.createResults[makeCreationId("k0")].isOk

block emailCopyResponseNotCreatedOnly:
  let node = %*{
    "fromAccountId": "src",
    "accountId": "dst",
    "newState": "s1",
    "notCreated": {"k1": {"type": "invalidProperties"}},
  }
  let r = EmailCopyResponse.fromJson(node).get()
  assertLen r.createResults, 1
  doAssert makeCreationId("k1") in r.createResults
  doAssert r.createResults[makeCreationId("k1")].isErr

block emailCopyResponseCombined:
  let node = %*{
    "fromAccountId": "src",
    "accountId": "dst",
    "newState": "s1",
    "created": {"k0": {"id": "e1", "blobId": "b1", "threadId": "t1", "size": 100}},
    "notCreated": {"k1": {"type": "invalidProperties"}},
  }
  let r = EmailCopyResponse.fromJson(node).get()
  assertLen r.createResults, 2
  doAssert r.createResults[makeCreationId("k0")].isOk
  doAssert r.createResults[makeCreationId("k1")].isErr

# ============= C. Required field =============

block emailCopyResponseRequiresFromAccountId:
  ## RFC 8621 §4.7: ``fromAccountId`` is mandatory (it names the source
  ## account the copy originated from). Parser must reject its absence.
  let node = %*{"accountId": "dst", "newState": "s1"}
  assertErr EmailCopyResponse.fromJson(node)

# ============= D. Type-level exclusion (compile-time pin) =============

block emailCopyResponseHasNoUpdatedField:
  ## Pins F1 §2.2's type-level guarantee: ``EmailCopyResponse`` has NO
  ## ``updated`` (nor ``destroyed``) field — those belong to ``/set`` only.
  ## Structured as ``assertNotCompiles`` so an accidental field addition
  ## to the type breaks the test rather than a runtime assertion.
  assertNotCompiles(
    block:
      let r: EmailCopyResponse = default(EmailCopyResponse)
      discard r.updated
  )
