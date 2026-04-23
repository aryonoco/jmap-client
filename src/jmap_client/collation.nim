# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 4790 / RFC 5051 collation algorithm identifiers. A sealed sum type
## covering the four IANA-registered algorithms named by JMAP (RFC 8620 §5.1.3)
## plus a ``caOther`` escape-hatch for vendor extensions with lossless
## round-trip.
##
## The domain is finite and well-specified on the wire, so the interior type
## rejects empty identifiers and control characters at construction.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/strutils

import ./validation

type CollationAlgorithmKind* = enum
  ## Discriminator for ``CollationAlgorithm``. Backing strings are the
  ## RFC 4790 / RFC 5051 wire identifiers; ``caOther`` carries an arbitrary
  ## vendor extension whose raw identifier lives alongside.
  caAsciiCasemap = "i;ascii-casemap"
  caOctet = "i;octet"
  caAsciiNumeric = "i;ascii-numeric"
  caUnicodeCasemap = "i;unicode-casemap"
  caOther

type CollationAlgorithm* {.ruleOff: "objects".} = object
  ## Validated RFC 4790 collation algorithm identifier.
  ##
  ## Construction sealed: ``rawKind`` and ``rawIdentifier`` are module-private,
  ## so direct literal construction from outside this module is rejected.
  ## Use ``parseCollationAlgorithm`` for untrusted input, or the named
  ## ``CollationAsciiCasemap`` / ``CollationOctet`` / ``CollationAsciiNumeric``
  ## / ``CollationUnicodeCasemap`` constants for the well-known values.
  case rawKind: CollationAlgorithmKind
  of caOther:
    rawIdentifier: string ## wire identifier for vendor extensions
  of caAsciiCasemap, caOctet, caAsciiNumeric, caUnicodeCasemap:
    discard

func kind*(c: CollationAlgorithm): CollationAlgorithmKind =
  ## Returns the discriminator — one of the four IANA kinds or ``caOther``.
  return c.rawKind

func identifier*(c: CollationAlgorithm): string =
  ## Returns the wire identifier string. For the four known kinds, this is
  ## the enum's backing string; for ``caOther`` it is the vendor extension
  ## identifier captured at parse time.
  case c.rawKind
  of caOther:
    return c.rawIdentifier
  of caAsciiCasemap, caOctet, caAsciiNumeric, caUnicodeCasemap:
    return $c.rawKind

func `$`*(c: CollationAlgorithm): string =
  ## Wire-form string — equivalent to ``identifier``.
  return c.identifier

func `==`*(a, b: CollationAlgorithm): bool =
  ## Structural equality. Two values are equal iff their kinds agree and,
  ## for ``caOther``, their raw identifiers match byte-for-byte.
  ##
  ## Nested case on both operands: strict doesn't propagate the
  ## ``a.rawKind != b.rawKind`` short-circuit across branches, so b's
  ## discriminator must be proved independently before reading
  ## ``b.rawIdentifier``.
  case a.rawKind
  of caOther:
    case b.rawKind
    of caOther:
      a.rawIdentifier == b.rawIdentifier
    of caAsciiCasemap, caOctet, caAsciiNumeric, caUnicodeCasemap:
      false
  of caAsciiCasemap, caOctet, caAsciiNumeric, caUnicodeCasemap:
    case b.rawKind
    of caOther:
      false
    of caAsciiCasemap, caOctet, caAsciiNumeric, caUnicodeCasemap:
      a.rawKind == b.rawKind

func hash*(c: CollationAlgorithm): Hash =
  ## Hash mixing the kind ordinal with the raw identifier for ``caOther``.
  ## Consistent with ``==`` — equal values produce equal hashes.
  var h: Hash = 0
  h = h !& hash(ord(c.rawKind))
  case c.rawKind
  of caOther:
    h = h !& hash(c.rawIdentifier)
  of caAsciiCasemap, caOctet, caAsciiNumeric, caUnicodeCasemap:
    discard
  result = !$h

const CollationAsciiCasemap* = CollationAlgorithm(rawKind: caAsciiCasemap)
  ## RFC 4790 ``i;ascii-casemap`` — ASCII with case folding.
const CollationOctet* = CollationAlgorithm(rawKind: caOctet)
  ## RFC 4790 ``i;octet`` — byte-by-byte.
const CollationAsciiNumeric* = CollationAlgorithm(rawKind: caAsciiNumeric)
  ## RFC 4790 ``i;ascii-numeric`` — numeric comparison on ASCII digits.
const CollationUnicodeCasemap* = CollationAlgorithm(rawKind: caUnicodeCasemap)
  ## RFC 5051 ``i;unicode-casemap`` — Unicode case folding.

type CollationViolationKind = enum
  ## Structural failures of a wire-format collation identifier. Discriminator
  ## for ``CollationViolation``; drives ``toValidationError`` exhaustiveness.
  cavEmpty
  cavNonPrintable

type CollationViolation {.ruleOff: "objects".} = object
  case kind: CollationViolationKind
  of cavEmpty:
    discard
  of cavNonPrintable:
    raw: string
    offender: char

func toValidationError(v: CollationViolation): ValidationError =
  ## Sole domain-to-wire translator for ``CollationViolation``. Adding a new
  ## ``CollationViolationKind`` variant forces a compile error here.
  case v.kind
  of cavEmpty:
    validationError("CollationAlgorithm", "must not be empty", "")
  of cavNonPrintable:
    validationError(
      "CollationAlgorithm",
      "contains non-printable byte 0x" & toHex(ord(v.offender), 2),
      v.raw,
    )

func detectCollation(raw: string): Result[void, CollationViolation] =
  ## RFC 4790 §3.1: collation identifiers are printable US-ASCII. The JMAP
  ## wire format adds a non-empty precondition. First offending byte wins,
  ## matching the reporting order used by adjacent validators.
  if raw.len == 0:
    return err(CollationViolation(kind: cavEmpty))
  for ch in raw:
    if ch < ' ' or ch == '\x7F':
      return err(CollationViolation(kind: cavNonPrintable, raw: raw, offender: ch))
  return ok()

func parseCollationAlgorithm*(
    raw: string
): Result[CollationAlgorithm, ValidationError] =
  ## Validates and constructs a ``CollationAlgorithm``. Rejects empty input
  ## and control characters; otherwise classifies the identifier against the
  ## four IANA-registered kinds, falling back to ``caOther`` for vendor
  ## extensions. Lossless round-trip: ``$(parseCollationAlgorithm(x).get) == x``
  ## holds for every ``x`` that survives detection.
  let detected = detectCollation(raw)
  if detected.isErr:
    return err(toValidationError(detected.error))
  let parsed = strutils.parseEnum[CollationAlgorithmKind](raw, caOther)
  case parsed
  of caAsciiCasemap:
    return ok(CollationAsciiCasemap)
  of caOctet:
    return ok(CollationOctet)
  of caAsciiNumeric:
    return ok(CollationAsciiNumeric)
  of caUnicodeCasemap:
    return ok(CollationUnicodeCasemap)
  of caOther:
    return ok(CollationAlgorithm(rawKind: caOther, rawIdentifier: raw))
