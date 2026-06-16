# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for plainTextBody: the S3 plain-text send-body smart
## constructor (RFC 8621 §4.6). Proves the produced body validates through
## parseEmailBlueprint.

{.push raises: [].}

import jmap_client/internal/mail/email_blueprint
import jmap_client/internal/mail/body
import jmap_client/internal/mail/mailbox
import jmap_client/internal/types/primitives # parseId
import jmap_client/internal/types/validation # re-exports nim-results (Opt/.get)

import ../../massertions
import ../../mtestblock

proc oneMailbox(): NonEmptyMailboxIdSet =
  ## A single-mailbox set for the through-blueprint validation case.
  parseNonEmptyMailboxIdSet(@[parseId("mb1").get()]).get()

testCase plainTextBodyShape:
  let body = plainTextBody("hello world")
  assertEq body.kind, ebkFlat
  assertSome body.textBody
  let part = body.textBody.get()
  assertEq part.contentType, "text/plain"
  case part.isMultipart
  of false:
    case part.leaf.source
    of bpsInline:
      assertEq part.leaf.value.value, "hello world"
    of bpsBlobRef:
      assertFalse true, "expected an inline leaf"
  of true:
    assertFalse true, "expected a leaf part"

testCase plainTextBodyValidatesThroughBlueprint:
  let res = parseEmailBlueprint(oneMailbox(), body = plainTextBody("hi"))
  assertOk res
