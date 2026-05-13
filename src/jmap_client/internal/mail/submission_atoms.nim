# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Atomic identifier types sharing the RFC 5321 §4.1.1.1 ``esmtp-keyword``
## grammar — ``(ALPHA / DIGIT) *(ALPHA / DIGIT / "-")``.
##
## ``RFC5321Keyword`` wraps §4.1.1.1 ``esmtp-keyword`` with case-insensitive
## equality per §2.4 and §4.1.1.1 ("MUST always be recognized and processed
## in a case-insensitive manner") while preserving original server casing
## in ``$`` for diagnostic round-trip.
##
## ``OrcptAddrType`` wraps the RFC 3461 §4.2 ``addr-type`` atom of the
## ``ORCPT=`` parameter value. Same lexical shape as esmtp-keyword but
## byte-equality, not case-insensitive — RFC 3461 does not mandate case-
## folding for the addr-type atom.
##
## Design authority: ``docs/design/12-mail-G1-design.md`` §2.2.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sequtils
import std/strutils

import ../types/validation

# ---------------------------------------------------------------------------
# Charset constants — shared esmtp-keyword grammar.
# ---------------------------------------------------------------------------

const
  AsciiLetters = {'A' .. 'Z', 'a' .. 'z'}
    ## RFC 5234 §B.1: ``ALPHA = %x41-5A / %x61-7A``.
  AsciiDigits = {'0' .. '9'} ## RFC 5234 §B.1: ``DIGIT = %x30-39``.
  EsmtpKeywordLeadChars = AsciiLetters + AsciiDigits
    ## RFC 5321 §4.1.1.1 esmtp-keyword first character: ``ALPHA / DIGIT``.
  EsmtpKeywordTailChars = AsciiLetters + AsciiDigits + {'-'}
    ## RFC 5321 §4.1.1.1 esmtp-keyword subsequent characters.

# ===========================================================================
# RFC5321Keyword
# ===========================================================================

type RFC5321Keyword* {.ruleOff: "objects".} = object
  ## RFC 5321 §4.1.1.1 ``esmtp-keyword``:
  ## ``(ALPHA / DIGIT) *(ALPHA / DIGIT / "-")``, bounded to 64 octets
  ## (defensive cap — the RFC is silent on an explicit maximum). Case-
  ## insensitive equality and hash per §2.4 and §4.1.1.1; ``$``
  ## preserves the original casing for diagnostic round-trip. Sealed
  ## Pattern-A object — ``rawValue`` is module-private.
  rawValue: string

func `==`*(a, b: RFC5321Keyword): bool =
  ## ASCII case-insensitive equality per RFC 5321 §4.1.1.1. Server
  ## casing preserved in ``$`` for diagnostic round-trip.
  cmpIgnoreCase(a.rawValue, b.rawValue) == 0

func `$`*(a: RFC5321Keyword): string =
  ## Preserves the original casing (unchanged from construction).
  a.rawValue

func hash*(a: RFC5321Keyword): Hash =
  ## Case-fold hash so ``==``-equal values hash identically — required
  ## for correctness of ``Table[RFC5321Keyword, _]`` lookups.
  hash(toLowerAscii(a.rawValue))

func len*(a: RFC5321Keyword): int =
  ## Length in octets (always 1..64 for constructed values).
  a.rawValue.len

type KeywordViolation = enum
  ## Structural failures of an esmtp-keyword. Module-private; translated
  ## at the wire boundary so each failure message lives in one place.
  kvLengthOutOfRange
  kvBadLeadChar
  kvBadTailChar

func toValidationError(v: KeywordViolation, typeName, raw: string): ValidationError =
  ## Sole domain-to-wire translator for ``KeywordViolation``.
  case v
  of kvLengthOutOfRange:
    validationError(typeName, "length must be 1-64 octets", raw)
  of kvBadLeadChar:
    validationError(typeName, "first character must be ALPHA or DIGIT", raw)
  of kvBadTailChar:
    validationError(typeName, "characters must be ALPHA / DIGIT / '-'", raw)

func detectKeyword(raw: string): Result[void, KeywordViolation] =
  ## Composes length, lead-char, and tail-char detection per RFC 5321
  ## §4.1.1.1.
  if raw.len < 1 or raw.len > 64:
    return err(kvLengthOutOfRange)
  if raw[0] notin EsmtpKeywordLeadChars:
    return err(kvBadLeadChar)
  if not raw.allIt(it in EsmtpKeywordTailChars):
    return err(kvBadTailChar)
  ok()

func parseRFC5321Keyword*(raw: string): Result[RFC5321Keyword, ValidationError] =
  ## Strict: ``(ALPHA / DIGIT) *(ALPHA / DIGIT / "-")``, length 1..64
  ## octets. No case normalisation — server casing preserved for
  ## diagnostic round-trip.
  detectKeyword(raw).isOkOr:
    return err(toValidationError(error, "RFC5321Keyword", raw))
  return ok(RFC5321Keyword(rawValue: raw))

# ===========================================================================
# OrcptAddrType — RFC 3461 §4.2 addr-type atom
# ===========================================================================

type OrcptAddrType* {.ruleOff: "objects".} = object
  ## RFC 3461 §4.2 ``addr-type`` atom of the ``ORCPT=`` parameter value.
  ## Shares esmtp-keyword grammar — ``(ALPHA / DIGIT)
  ## *(ALPHA / DIGIT / "-")`` — but preserves server casing for IANA-
  ## registered addr-types (``rfc822``, ``utf-8``, ``x400``, ``unknown``).
  ## Byte-equality, not case-insensitive — RFC 3461 does not mandate
  ## case-folding for the addr-type atom. Sealed Pattern-A object —
  ## ``rawValue`` is module-private.
  rawValue: string

defineSealedStringOps(OrcptAddrType)

type OrcptAddrTypeViolation = enum
  ## Structural failures of an ``addr-type`` atom. Module-private;
  ## translated at the wire boundary via ``toValidationError`` so every
  ## failure message lives in one place and adding a variant forces a
  ## compile error at exactly the translator.
  oatEmpty
  oatBadLeadChar
  oatBadTailChar

func toValidationError(
    v: OrcptAddrTypeViolation, typeName, raw: string
): ValidationError =
  ## Sole domain-to-wire translator for ``OrcptAddrTypeViolation``.
  case v
  of oatEmpty:
    validationError(typeName, "must not be empty", raw)
  of oatBadLeadChar:
    validationError(typeName, "first character must be ALPHA or DIGIT", raw)
  of oatBadTailChar:
    validationError(typeName, "characters must be ALPHA / DIGIT / '-'", raw)

func detectOrcptAddrType(raw: string): Result[void, OrcptAddrTypeViolation] =
  ## Composes emptiness, lead-char, and tail-char detection per RFC 3461
  ## §4.2. No length cap — RFC 3461 is silent on one.
  if raw.len == 0:
    return err(oatEmpty)
  if raw[0] notin EsmtpKeywordLeadChars:
    return err(oatBadLeadChar)
  if not raw.allIt(it in EsmtpKeywordTailChars):
    return err(oatBadTailChar)
  ok()

func parseOrcptAddrType*(raw: string): Result[OrcptAddrType, ValidationError] =
  ## Strict client-side constructor for the addr-type atom of ``ORCPT=``.
  detectOrcptAddrType(raw).isOkOr:
    return err(toValidationError(error, "OrcptAddrType", raw))
  return ok(OrcptAddrType(rawValue: raw))
