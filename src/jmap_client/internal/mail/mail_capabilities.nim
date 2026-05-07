# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Mail and submission capability types for RFC 8621 (JMAP Mail).
## MailCapabilities carries the server-advertised limits for the
## urn:ietf:params:jmap:mail capability; SubmissionCapabilities carries
## the limits for urn:ietf:params:jmap:submission.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/sets
import std/tables

import ../types/validation
import ../types/primitives
import ./submission_atoms

type SubmissionExtensionMap* = distinct OrderedTable[RFC5321Keyword, seq[string]]
  ## RFC 5321 §2.2.1 EHLO-name → args map for the
  ## urn:ietf:params:jmap:submission capability's ``submissionExtensions``
  ## field (RFC 8621 §1.3.2). Keys are validated ESMTP keywords with the
  ## case-insensitive equality and hash defined by ``RFC5321Keyword`` —
  ## the underlying ``OrderedTable`` therefore gives structural uniqueness
  ## and wire-order fidelity automatically. Construction is gated by
  ## ``parseSubmissionCapabilities`` serde; direct callers wrap a
  ## validated ``OrderedTable[RFC5321Keyword, seq[string]]`` via the raw
  ## distinct constructor.

func `==`*(a, b: SubmissionExtensionMap): bool {.borrow.}
  ## Structural equality via the underlying ``OrderedTable`` — keys
  ## compare case-insensitively through ``RFC5321Keyword.==``.

func `$`*(a: SubmissionExtensionMap): string {.borrow.}
  ## Table-rendered representation preserving wire order; for diagnostics.

type MailCapabilities* {.ruleOff: "objects".} = object
  ## Server-advertised limits for the urn:ietf:params:jmap:mail capability
  ## (RFC 8621 section 2).
  maxMailboxesPerEmail*: Opt[UnsignedInt] ## Null means no limit; >= 1 when present.
  maxMailboxDepth*: Opt[UnsignedInt] ## Null means no limit.
  maxSizeMailboxName*: Opt[UnsignedInt]
    ## Octets; >= 100 when present per RFC 8621 §1.3.1. Optional —
    ## informational hint, not MUST. Cyrus 3.12.2 omits this field
    ## (`imap/jmap_mail.c:340-347`); the Postel-receive parser surfaces
    ## absence as ``Opt.none`` rather than synthesising a default.
  maxSizeAttachmentsPerEmail*: UnsignedInt ## Octets.
  emailQuerySortOptions*: HashSet[string] ## Supported sort properties.
  mayCreateTopLevelMailbox*: bool ## Whether the client may create top-level mailboxes.

type SubmissionCapabilities* {.ruleOff: "objects".} = object
  ## Server-advertised limits for the urn:ietf:params:jmap:submission
  ## capability (RFC 8621 section 7).
  maxDelayedSend*: UnsignedInt ## Seconds; 0 means delayed send not supported.
  submissionExtensions*: SubmissionExtensionMap ## SMTP extension keywords.
