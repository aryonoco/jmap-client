# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Mail-specific typed accessors over the central ``SetError`` ADT.
##
## Historically this module carried a separate ``MailSetErrorType`` enum
## and five accessors that walked ``SetError.extras`` (``JsonNode``) on
## every read. The central ``SetError`` now models the thirteen RFC 8621
## mail variants directly; the accessors collapse to one-line case-branch
## reads and stay in the mail layer so mail-specific predicate vocabulary
## lives next to the mail domain.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import ../validation
import ../primitives
import ../identifiers
import ../errors

func notFoundBlobIds*(se: SetError): Opt[seq[BlobId]] =
  ## Unresolved blob IDs from a ``setBlobNotFound`` error (RFC 8621 §4.6).
  case se.errorType
  of setBlobNotFound:
    Opt.some(se.notFound)
  else:
    Opt.none(seq[BlobId])

func maxSize*(se: SetError): Opt[UnsignedInt] =
  ## Server's size cap from a ``setTooLarge`` error (RFC 8621 §7.5 SHOULD).
  case se.errorType
  of setTooLarge:
    se.maxSizeOctets
  else:
    Opt.none(UnsignedInt)

func maxRecipients*(se: SetError): Opt[UnsignedInt] =
  ## Server's recipient cap from a ``setTooManyRecipients`` error (RFC 8621 §7.5).
  case se.errorType
  of setTooManyRecipients:
    Opt.some(se.maxRecipientCount)
  else:
    Opt.none(UnsignedInt)

func invalidRecipientAddresses*(se: SetError): Opt[seq[string]] =
  ## Invalid recipient addresses from a ``setInvalidRecipients`` error (RFC 8621 §7.5).
  case se.errorType
  of setInvalidRecipients:
    Opt.some(se.invalidRecipients)
  else:
    Opt.none(seq[string])

func invalidEmailProperties*(se: SetError): Opt[seq[string]] =
  ## Invalid Email property names from a ``setInvalidEmail`` error (RFC 8621 §7.5).
  case se.errorType
  of setInvalidEmail:
    Opt.some(se.invalidEmailPropertyNames)
  else:
    Opt.none(seq[string])
