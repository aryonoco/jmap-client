# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Email smart constructor and isLeaf predicate
## (§12.1, scenarios 1–2, plus isLeaf).

{.push raises: [].}

import jmap_client/mail/email
import jmap_client/mail/body
import jmap_client/mail/mailbox
import jmap_client/validation
import jmap_client/primitives
import jmap_client/identifiers

import ../../massertions
import ../../mfixtures

# ============= A. parseEmail =============

block parseEmailValid: # scenario 1
  assertOk parseEmail(makeEmail())

block parseEmailEmptyMailboxIds: # scenario 2
  var email = makeEmail()
  email.mailboxIds = initMailboxIdSet(@[])
  let res = parseEmail(email)
  doAssert res.isErr, "expected Err result, got Ok"
  # unsafeError avoids raiseResultDefect whose $Email has side effects
  # due to Table fields; safe because we verified isErr above.
  let e = res.unsafeError
  doAssert e.typeName == "Email", "typeName: expected Email, got " & e.typeName
  doAssert e.message == "mailboxIds must not be empty",
    "message: expected 'mailboxIds must not be empty', got " & e.message
  doAssert e.value == "", "value: expected empty, got " & e.value

# ============= B. isLeaf =============

block isLeafTrue:
  let leaf = makeLeafBodyPart()
  doAssert isLeaf(leaf) == true

block isLeafFalseForMultipart:
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

block initNonEmptyEmailImportMapEmpty:
  let res = initNonEmptyEmailImportMap(@[])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "NonEmptyEmailImportMap"
  assertEq res.error[0].message, "must contain at least one entry"
  assertEq res.error[0].value, ""

block initNonEmptyEmailImportMapSingleValid:
  let cid = parseCreationId("c1").get()
  let blob = parseBlobId("blob1").get()
  let mbxs = parseNonEmptyMailboxIdSet(@[parseId("m1").get()]).get()
  let item = initEmailImportItem(blob, mbxs)
  assertOk initNonEmptyEmailImportMap(@[(cid, item)])

block initNonEmptyEmailImportMapTwoSameCreationId:
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

block initNonEmptyEmailImportMapThreeSameCreationId:
  ## Three occurrences of the same CreationId still yield ONE error.
  let cid = parseCreationId("c1").get()
  let blob = parseBlobId("blob1").get()
  let mbxs = parseNonEmptyMailboxIdSet(@[parseId("m1").get()]).get()
  let item = initEmailImportItem(blob, mbxs)
  let res = initNonEmptyEmailImportMap(@[(cid, item), (cid, item), (cid, item)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].value, "c1"

block initNonEmptyEmailImportMapTwoDistinctRepeated:
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
