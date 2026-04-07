# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Mail and submission capability types for RFC 8621 (JMAP Mail).
## MailCapabilities carries the server-advertised limits for the
## urn:ietf:params:jmap:mail capability; SubmissionCapabilities carries
## the limits for urn:ietf:params:jmap:submission.

{.push raises: [].}

import std/sets
import std/tables

import ../validation
import ../primitives

type MailCapabilities* {.ruleOff: "objects".} = object
  ## Server-advertised limits for the urn:ietf:params:jmap:mail capability
  ## (RFC 8621 section 2).
  maxMailboxesPerEmail*: Opt[UnsignedInt] ## Null means no limit; >= 1 when present.
  maxMailboxDepth*: Opt[UnsignedInt] ## Null means no limit.
  maxSizeMailboxName*: UnsignedInt ## Octets; >= 100 per RFC.
  maxSizeAttachmentsPerEmail*: UnsignedInt ## Octets.
  emailQuerySortOptions*: HashSet[string] ## Supported sort properties.
  mayCreateTopLevelMailbox*: bool ## Whether the client may create top-level mailboxes.

type SubmissionCapabilities* {.ruleOff: "objects".} = object
  ## Server-advertised limits for the urn:ietf:params:jmap:submission
  ## capability (RFC 8621 section 7).
  maxDelayedSend*: UnsignedInt ## Seconds; 0 means delayed send not supported.
  submissionExtensions*: OrderedTable[string, seq[string]] ## SMTP extension keywords.
