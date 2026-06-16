# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the S3 Mailbox role predicates isInbox / hasRole
## (RFC 8621 §2, §10.5.1).

{.push raises: [].}

import jmap_client/internal/mail/mailbox
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation # re-exports nim-results (Opt/.get)

import ../../massertions
import ../../mtestblock

proc mailboxWithRole(role: Opt[MailboxRole]): Mailbox =
  ## A minimal Mailbox carrying just the role under test.
  Mailbox(
    id: parseId("mb1").get(),
    name: "a",
    role: role,
    sortOrder: parseUnsignedInt(0).get(),
    totalEmails: parseUnsignedInt(0).get(),
    unreadEmails: parseUnsignedInt(0).get(),
    totalThreads: parseUnsignedInt(0).get(),
    unreadThreads: parseUnsignedInt(0).get(),
    myRights: MailboxRights(),
    isSubscribed: false,
  )

testCase isInboxTrue:
  let mb = mailboxWithRole(Opt.some(roleInbox))
  assertEq mb.isInbox(), true

testCase isInboxFalseForDrafts:
  let mb = mailboxWithRole(Opt.some(roleDrafts))
  assertEq mb.isInbox(), false

testCase isInboxFalseForNoRole:
  let mb = mailboxWithRole(Opt.none(MailboxRole))
  assertEq mb.isInbox(), false

testCase hasRoleMatches:
  let mb = mailboxWithRole(Opt.some(roleSent))
  assertEq mb.hasRole(mrSent), true
  assertEq mb.hasRole(mrInbox), false

testCase hasRoleNoneIsFalse:
  let mb = mailboxWithRole(Opt.none(MailboxRole))
  assertEq mb.hasRole(mrTrash), false

testCase hasRoleMatchesVendorExtension:
  # A vendor-extension role string — not one of the nine RFC 8621 §2
  # well-known roles — so parseMailboxRole classifies it as mrOther.
  let vendorRole = parseMailboxRole("vnd.example.custom").get()
  let mb = mailboxWithRole(Opt.some(vendorRole))
  assertEq mb.hasRole(mrOther), true
  assertEq mb.hasRole(mrInbox), false
