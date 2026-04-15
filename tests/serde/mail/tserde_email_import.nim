# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for EmailImportItem, NonEmptyEmailImportMap, and
## EmailImportResponse (F2 §8.3 import row). Pins the ``Opt.none → key-absent``
## behaviour of ``keywords`` and ``receivedAt``, the ``Opt.some(empty) →
## key-absent`` collapse on ``keywords`` (serde_email.nim:1019-1021), and the
## RFC §4.8 three-state ``created`` parity (absent / null / empty).

{.push raises: [].}

import std/[json, tables]

import jmap_client/mail/email
import jmap_client/mail/keyword
import jmap_client/mail/serde_email
import jmap_client/mail/serde_keyword
import jmap_client/identifiers
import jmap_client/primitives
import jmap_client/serde
import jmap_client/validation

import ../../massertions
import ../../mfixtures

# ============= A. toJson(EmailImportItem) =============

block importItemBlobIdAlwaysEmitted:
  let item = makeEmailImportItem(blobId = makeId("blob1"))
  let node = item.toJson()
  assertJsonFieldEq node, "blobId", makeId("blob1").toJson()

block importItemMailboxIdsAlwaysEmitted:
  let item = makeEmailImportItem()
  let node = item.toJson()
  let mids = node{"mailboxIds"}
  doAssert mids != nil, "expected mailboxIds present"
  doAssert mids.kind == JObject, "expected mailboxIds to serialise as JObject"

block importItemKeywordsOmittedWhenNone:
  ## ``Opt.none`` → key-absent (server applies its default of empty).
  let item = makeEmailImportItem(keywords = Opt.none(KeywordSet))
  assertJsonKeyAbsent item.toJson(), "keywords"

block importItemKeywordsEmittedWhenSome:
  ## ``Opt.some(non-empty)`` → wire object ``{keyword: true, ...}``.
  let ks = initKeywordSet(@[kwSeen])
  let item = makeEmailImportItem(keywords = Opt.some(ks))
  assertJsonFieldEq item.toJson(), "keywords", ks.toJson()

block importItemReceivedAtOmittedWhenNone:
  let item = makeEmailImportItem(receivedAt = Opt.none(UTCDate))
  assertJsonKeyAbsent item.toJson(), "receivedAt"

block importItemReceivedAtEmittedWhenSome:
  let d = parseUtcDate("2026-01-01T00:00:00Z").get()
  let item = makeEmailImportItem(receivedAt = Opt.some(d))
  assertJsonFieldEq item.toJson(), "receivedAt", d.toJson()

# ============= B. toJson(NonEmptyEmailImportMap) =============

block nonEmptyEmailImportMapEmitsCreationIdKeys:
  let cid1 = makeCreationId("k0")
  let cid2 = makeCreationId("k1")
  let m = makeNonEmptyEmailImportMap(
    @[(cid1, makeEmailImportItem()), (cid2, makeEmailImportItem())]
  )
  let node = m.toJson()
  doAssert node.kind == JObject
  assertLen node, 2
  doAssert node{string(cid1)} != nil, "expected " & string(cid1) & " key"
  doAssert node{string(cid2)} != nil, "expected " & string(cid2) & " key"

# ============= C. EmailImportResponse.fromJson =============

block importResponseCreatedObject:
  let node = %*{
    "accountId": "acct1",
    "newState": "s1",
    "created": {"k0": {"id": "e1", "blobId": "b1", "threadId": "t1", "size": 50}},
  }
  let res = EmailImportResponse.fromJson(node)
  assertOk res
  let r = res.get()
  assertLen r.createResults, 1
  doAssert makeCreationId("k0") in r.createResults
  doAssert r.createResults[makeCreationId("k0")].isOk

block importResponseCreatedNull:
  ## RFC 8620 §5.3 tolerates ``null`` on map-valued fields as equivalent to
  ## absent. ``mergeCreatedResults`` treats non-object ``created`` as empty.
  let node = %*{"accountId": "acct1", "newState": "s1", "created": nil}
  let r = EmailImportResponse.fromJson(node).get()
  assertLen r.createResults, 0

block importResponseCreatedEmpty:
  let node = %*{"accountId": "acct1", "newState": "s1", "created": {}}
  let r = EmailImportResponse.fromJson(node).get()
  assertLen r.createResults, 0

block importResponseMalformedSurfacesError:
  ## ``accountId: null`` is type-malformed: the wire-mandatory field has
  ## the wrong kind. The parser must refuse rather than coerce.
  let node = %*{"accountId": nil, "newState": "s1"}
  assertErr EmailImportResponse.fromJson(node)
