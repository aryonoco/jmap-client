# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Email isLeaf predicate and Email/import smart
## constructors (§12.1).

{.push raises: [].}

import results

import jmap_client/internal/mail/email
import jmap_client/internal/mail/body
import jmap_client/internal/mail/mailbox
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers

import ../../massertions
import ../../mfixtures
import ../../mtestblock

# ============= B. isLeaf =============

testCase isLeafTrue:
  let leaf = makeLeafBodyPart()
  doAssert isLeaf(leaf) == true

testCase isLeafFalseForMultipart:
  let multipart = EmailBodyPart(
    isMultipart: true,
    subParts: @[],
    headers: @[],
    name: Opt.none(string),
    contentType: "multipart/mixed",
    charset: Opt.none(string),
    disposition: Opt.none(ContentDisposition),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
    size: zeroUint(),
  )
  doAssert isLeaf(multipart) == false

# ============= C. initNonEmptyEmailImportMap =============
#
# Uniqueness-by-CreationId contract: each distinct repeated key yields
# exactly one error regardless of occurrence count.

testCase initNonEmptyEmailImportMapEmpty:
  let res = initNonEmptyEmailImportMap(@[])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "NonEmptyEmailImportMap"
  assertEq res.error[0].message, "must contain at least one entry"
  assertEq res.error[0].value, ""

testCase initNonEmptyEmailImportMapSingleValid:
  let cid = parseCreationId("c1").get()
  let blob = parseBlobId("blob1").get()
  let mbxs = parseNonEmptyMailboxIdSet(@[parseId("m1").get()]).get()
  let item = initEmailImportItem(blob, mbxs)
  assertOk initNonEmptyEmailImportMap(@[(cid, item)])

testCase initNonEmptyEmailImportMapTwoSameCreationId:
  let cid = parseCreationId("c1").get()
  let blob = parseBlobId("blob1").get()
  let mbxs = parseNonEmptyMailboxIdSet(@[parseId("m1").get()]).get()
  let item = initEmailImportItem(blob, mbxs)
  let res = initNonEmptyEmailImportMap(@[(cid, item), (cid, item)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "NonEmptyEmailImportMap"
  assertEq res.error[0].message, "duplicate CreationId"
  assertEq res.error[0].value, "c1"

testCase initNonEmptyEmailImportMapThreeSameCreationId:
  ## Three occurrences of the same CreationId still yield ONE error.
  let cid = parseCreationId("c1").get()
  let blob = parseBlobId("blob1").get()
  let mbxs = parseNonEmptyMailboxIdSet(@[parseId("m1").get()]).get()
  let item = initEmailImportItem(blob, mbxs)
  let res = initNonEmptyEmailImportMap(@[(cid, item), (cid, item), (cid, item)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].value, "c1"

testCase initNonEmptyEmailImportMapTwoDistinctRepeated:
  ## Two distinct repeated CreationIds → TWO errors, one per distinct
  ## duplicate key.
  let cid1 = parseCreationId("c1").get()
  let cid2 = parseCreationId("c2").get()
  let blob = parseBlobId("blob1").get()
  let mbxs = parseNonEmptyMailboxIdSet(@[parseId("m1").get()]).get()
  let item = initEmailImportItem(blob, mbxs)
  let res = initNonEmptyEmailImportMap(
    @[(cid1, item), (cid1, item), (cid2, item), (cid2, item)]
  )
  assertErr res
  assertLen res.error, 2
  var c1Seen = false
  var c2Seen = false
  for e in res.error:
    assertEq e.typeName, "NonEmptyEmailImportMap"
    assertEq e.message, "duplicate CreationId"
    if e.value == "c1":
      c1Seen = true
    elif e.value == "c2":
      c2Seen = true
  doAssert c1Seen and c2Seen
