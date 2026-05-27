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

import ../types/validation
import ../types/primitives
import ../types/identifiers
import ../types/errors

func notFoundBlobIds*(se: SetError): Opt[seq[BlobId]] =
  ## Unresolved blob IDs from a ``setBlobNotFound`` error (RFC 8621 §4.6).
  ## Exhaustive over ``SetErrorKind``; new variants force a compile error.
  case se.kind
  of setBlobNotFound:
    Opt.some(se.notFound)
  of setForbidden, setOverQuota, setTooLarge, setRateLimit, setNotFound,
      setInvalidPatch, setWillDestroy, setInvalidProperties, setAlreadyExists,
      setSingleton, setMailboxHasChild, setMailboxHasEmail, setTooManyKeywords,
      setTooManyMailboxes, setInvalidEmail, setTooManyRecipients, setNoRecipients,
      setInvalidRecipients, setForbiddenMailFrom, setForbiddenFrom, setForbiddenToSend,
      setCannotUnsend, setUnknown:
    Opt.none(seq[BlobId])

func maxSize*(se: SetError): Opt[UnsignedInt] =
  ## Server's size cap from a ``setTooLarge`` error (RFC 8621 §7.5 SHOULD).
  case se.kind
  of setTooLarge:
    se.maxSizeOctets
  of setForbidden, setOverQuota, setRateLimit, setNotFound, setInvalidPatch,
      setWillDestroy, setInvalidProperties, setAlreadyExists, setSingleton,
      setMailboxHasChild, setMailboxHasEmail, setBlobNotFound, setTooManyKeywords,
      setTooManyMailboxes, setInvalidEmail, setTooManyRecipients, setNoRecipients,
      setInvalidRecipients, setForbiddenMailFrom, setForbiddenFrom, setForbiddenToSend,
      setCannotUnsend, setUnknown:
    Opt.none(UnsignedInt)

func maxRecipients*(se: SetError): Opt[UnsignedInt] =
  ## Server's recipient cap from a ``setTooManyRecipients`` error (RFC 8621 §7.5).
  case se.kind
  of setTooManyRecipients:
    Opt.some(se.maxRecipientCount)
  of setForbidden, setOverQuota, setTooLarge, setRateLimit, setNotFound,
      setInvalidPatch, setWillDestroy, setInvalidProperties, setAlreadyExists,
      setSingleton, setMailboxHasChild, setMailboxHasEmail, setBlobNotFound,
      setTooManyKeywords, setTooManyMailboxes, setInvalidEmail, setNoRecipients,
      setInvalidRecipients, setForbiddenMailFrom, setForbiddenFrom, setForbiddenToSend,
      setCannotUnsend, setUnknown:
    Opt.none(UnsignedInt)

func invalidRecipientAddresses*(se: SetError): Opt[seq[string]] =
  ## Invalid recipient addresses from a ``setInvalidRecipients`` error (RFC 8621 §7.5).
  case se.kind
  of setInvalidRecipients:
    Opt.some(se.invalidRecipients)
  of setForbidden, setOverQuota, setTooLarge, setRateLimit, setNotFound,
      setInvalidPatch, setWillDestroy, setInvalidProperties, setAlreadyExists,
      setSingleton, setMailboxHasChild, setMailboxHasEmail, setBlobNotFound,
      setTooManyKeywords, setTooManyMailboxes, setInvalidEmail, setTooManyRecipients,
      setNoRecipients, setForbiddenMailFrom, setForbiddenFrom, setForbiddenToSend,
      setCannotUnsend, setUnknown:
    Opt.none(seq[string])

func invalidEmailProperties*(se: SetError): Opt[seq[string]] =
  ## Invalid Email property names from a ``setInvalidEmail`` error (RFC 8621 §7.5).
  case se.kind
  of setInvalidEmail:
    Opt.some(se.invalidEmailPropertyNames)
  of setForbidden, setOverQuota, setTooLarge, setRateLimit, setNotFound,
      setInvalidPatch, setWillDestroy, setInvalidProperties, setAlreadyExists,
      setSingleton, setMailboxHasChild, setMailboxHasEmail, setBlobNotFound,
      setTooManyKeywords, setTooManyMailboxes, setTooManyRecipients, setNoRecipients,
      setInvalidRecipients, setForbiddenMailFrom, setForbiddenFrom, setForbiddenToSend,
      setCannotUnsend, setUnknown:
    Opt.none(seq[string])
