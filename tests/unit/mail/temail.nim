# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Email smart constructor and isLeaf predicate
## (§12.1, scenarios 1–2, plus isLeaf).

{.push raises: [].}

import jmap_client/mail/email
import jmap_client/mail/body
import jmap_client/mail/mailbox
import jmap_client/validation

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
    disposition: Opt.none(string),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
    size: zeroUint(),
  )
  doAssert isLeaf(multipart) == false
