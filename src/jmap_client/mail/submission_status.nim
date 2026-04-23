# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 8621 §7 EmailSubmission status vocabulary.
##
## Three concerns in one L1 module:
##   1. ``UndoStatus`` — the closed 3-state lifecycle discriminator
##      (RFC 8621 §7 ¶7) which doubles as the phantom type parameter
##      for ``EmailSubmission[S: static UndoStatus]`` (G3).
##   2. ``DeliveredState`` / ``DisplayedState`` — open-world server-sent
##      enums with a catch-all arm plus a raw-preserving wrapper per the
##      ``MethodErrorType`` precedent (G10, G11).
##   3. ``SmtpReply`` + ``DeliveryStatus`` + ``DeliveryStatusMap`` —
##      per-recipient delivery outcome (RFC 8621 §7 ¶8) with
##      ``SmtpReply`` validated against the RFC 5321 §4.2 Reply-code
##      surface shape (multi-line Reply-lines, continuation via ``'-'``,
##      terminated by SP/HT/EOL; deeper enhanced-status-code
##      decomposition per RFC 3463 deferred — G12).
##
## Design authority: ``docs/design/12-mail-G1-design.md`` §3.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sequtils
import std/strutils
import std/tables

import ../validation
import ./submission_envelope

# ---------------------------------------------------------------------------
# Charset — RFC 5321 §4.2 Reply-line body lineage.
# ---------------------------------------------------------------------------

const ReplyAllowedBytes = {'\t', '\n', '\r', ' ' .. '~'}
  ## Bytes legal in a raw multi-line Reply: HT (%d09) and printable US-
  ## ASCII (%d32-126) per RFC 5321 §4.2.1 ``textstring``, plus CR/LF which
  ## delimit Reply-lines. DEL (0x7F) is deliberately excluded.

# ===========================================================================
# UndoStatus — RFC 8621 §7 ¶7 closed lifecycle discriminator
# ===========================================================================

type UndoStatus* = enum
  ## Lifecycle state of an ``EmailSubmission``. Doubles as the phantom
  ## type parameter for ``EmailSubmission[S: static UndoStatus]`` (G3):
  ## ``cancel`` only accepts ``EmailSubmission[usPending]`` at the type
  ## level. Closed enum by design — new variants would be a spec change.
  ## No L1 smart constructor: serde (Step 11) owns the string↔variant
  ## mapping via ``parseUndoStatus``. Duplicating at L1 would create two
  ## sources of truth with no L1 consumer.
  usPending = "pending"
  usFinal = "final"
  usCanceled = "canceled"

# ===========================================================================
# DeliveredState / DisplayedState — open-world enums with raw preservation
# ===========================================================================

type DeliveredState* = enum
  ## RFC 8621 §7 per-recipient delivery outcome. Four RFC-defined arms
  ## plus a catch-all ``dsOther`` for server extensions (G10) — mirrors
  ## the ``MethodErrorType`` precedent where unknown tokens fall through
  ## to ``metUnknown`` with ``rawBacking`` preserving the anomaly for
  ## diagnostics.
  dsQueued = "queued"
  dsYes = "yes"
  dsNo = "no"
  dsUnknown = "unknown"
  dsOther

type ParsedDeliveredState* {.ruleOff: "objects".} = object
  ## ``DeliveredState`` classification plus the exact byte sequence
  ## observed on the wire. ``rawBacking`` is lossless: equal to the
  ## matched backing string for recognised arms, and to the unrecognised
  ## token for ``dsOther`` — round-trippable for logging and re-emission.
  state*: DeliveredState
  rawBacking*: string

type DisplayedState* = enum
  ## RFC 8621 §7 per-recipient MDN-displayed outcome. Two RFC-defined
  ## arms plus ``dpOther`` catch-all (G11) — symmetric with
  ## ``DeliveredState``.
  dpUnknown = "unknown"
  dpYes = "yes"
  dpOther

type ParsedDisplayedState* {.ruleOff: "objects".} = object
  ## ``DisplayedState`` classification plus the exact wire byte sequence.
  ## Round-trippable for logging and re-emission.
  state*: DisplayedState
  rawBacking*: string

# ===========================================================================
# SmtpReply — RFC 5321 §4.2 Reply-code / Reply-line surface shape
# ===========================================================================

type SmtpReply* = distinct string
  ## RFC 5321 §4.2 Reply-line(s): one or more lines each prefixed by a
  ## 3-digit Reply-code (``%x32-35 %x30-35 %x30-39``) followed by SP,
  ## HT, ``'-'`` (continuation), or end-of-line, then optional textstring
  ## (HT and printable US-ASCII). Multi-line replies MUST share the same
  ## Reply-code across all lines; every non-final line uses ``'-'``; the
  ## final line uses SP/HT/EOL. ``SmtpReply`` is constructed only via
  ## ``parseSmtpReply``; the raw constructor is not part of the public
  ## surface.

defineStringDistinctOps(SmtpReply)

type SmtpReplyViolation = enum
  ## Structural failures of the RFC 5321 §4.2 Reply-line surface shape.
  ## Module-private; the public parser translates these to
  ## ``ValidationError`` at the wire boundary via ``toValidationError`` —
  ## every failure message lives in one place, and adding a variant
  ## forces a compile error at the translator (never silently at a
  ## detector).
  srEmpty
  srControlChars
  srLineTooShort
  srBadReplyCodeDigit1
  srBadReplyCodeDigit2
  srBadReplyCodeDigit3
  srBadSeparator
  srMultilineCodeMismatch
  srMultilineContinuation
  srMultilineFinalHyphen

func toValidationError(v: SmtpReplyViolation, typeName, raw: string): ValidationError =
  ## Sole domain-to-wire translator for ``SmtpReplyViolation``. Adding a
  ## variant forces a compile error here, not at every detector site.
  case v
  of srEmpty:
    validationError(typeName, "must not be empty", raw)
  of srControlChars:
    validationError(typeName, "contains disallowed control characters", raw)
  of srLineTooShort:
    validationError(typeName, "line shorter than 3-digit Reply-code", raw)
  of srBadReplyCodeDigit1:
    validationError(typeName, "first Reply-code digit must be in 2..5", raw)
  of srBadReplyCodeDigit2:
    validationError(typeName, "second Reply-code digit must be in 0..5", raw)
  of srBadReplyCodeDigit3:
    validationError(typeName, "third Reply-code digit must be in 0..9", raw)
  of srBadSeparator:
    validationError(typeName, "character after Reply-code must be SP, HT, or '-'", raw)
  of srMultilineCodeMismatch:
    validationError(typeName, "multi-line reply has inconsistent Reply-codes", raw)
  of srMultilineContinuation:
    validationError(typeName, "non-final reply line must use '-' continuation", raw)
  of srMultilineFinalHyphen:
    validationError(typeName, "final reply line must not use '-' continuation", raw)

func detectReplyCode(line: string): Result[void, SmtpReplyViolation] =
  ## RFC 5321 §4.2 ``Reply-code = %x32-35 %x30-35 %x30-39``. Precondition
  ## ``line.len >= 3`` — established by the caller so this function can
  ## focus on per-digit range checks.
  if line[0] notin {'2' .. '5'}:
    return err(srBadReplyCodeDigit1)
  if line[1] notin {'0' .. '5'}:
    return err(srBadReplyCodeDigit2)
  if line[2] notin {'0' .. '9'}:
    return err(srBadReplyCodeDigit3)
  ok()

func detectReplySeparator(
    line: string, isFinal: bool
): Result[void, SmtpReplyViolation] =
  ## Dispatches on the character immediately following the Reply-code.
  ## A line with exactly the Reply-code (no separator) is legal as the
  ## final line (``"250"`` alone) but not as a continuation.
  ## ``'-'`` marks a continuation; SP/HT mark the final text segment.
  if line.len == 3:
    if isFinal:
      return ok()
    return err(srMultilineContinuation)
  case line[3]
  of '-':
    if isFinal:
      err(srMultilineFinalHyphen)
    else:
      ok()
  of ' ', '\t':
    if isFinal:
      ok()
    else:
      err(srMultilineContinuation)
  else:
    err(srBadSeparator)

func detectSmtpReplyLine(
    line: string, isFinal: bool, expectedCode: string
): Result[void, SmtpReplyViolation] =
  ## Validates a single Reply-line body (CR/LF already stripped by the
  ## caller). ``expectedCode`` is empty on the first line and the 3-digit
  ## code captured from line 0 on subsequent lines — enforcing the RFC
  ## 5321 §4.2.1 rule that every line of a multi-line reply carries the
  ## same Reply-code. Sequences the three phases: length floor, digit
  ## grammar, code consistency, separator dispatch.
  if line.len < 3:
    return err(srLineTooShort)
  ?detectReplyCode(line)
  if expectedCode.len > 0 and line[0 .. 2] != expectedCode:
    return err(srMultilineCodeMismatch)
  detectReplySeparator(line, isFinal)

func detectSmtpReply(raw: string): Result[void, SmtpReplyViolation] =
  ## Composer: emptiness + global byte-set + CRLF/LF normalisation +
  ## per-line validation with code-consistency enforcement. Accepts
  ## CRLF, bare LF, and bare CR as line terminators (Postel's law —
  ## matches ``parseRFC5321MailboxFromServer`` leniency). One optional
  ## trailing empty segment from a CRLF-terminated payload is dropped.
  if raw.len == 0:
    return err(srEmpty)
  if not raw.allIt(it in ReplyAllowedBytes):
    return err(srControlChars)
  let normalised = raw.replace("\r\n", "\n").replace("\r", "\n")
  let allLines = normalised.split('\n')
  let lineCount =
    if allLines[^1].len == 0:
      allLines.len - 1
    else:
      allLines.len
  if lineCount == 0:
    return err(srEmpty)
  ?detectSmtpReplyLine(allLines[0], lineCount == 1, "")
  if lineCount == 1:
    return ok()
  let expectedCode = allLines[0][0 .. 2]
  for i in 1 ..< lineCount:
    ?detectSmtpReplyLine(allLines[i], i == lineCount - 1, expectedCode)
  ok()

func parseSmtpReply*(raw: string): Result[SmtpReply, ValidationError] =
  ## Smart constructor: enforces the RFC 5321 §4.2 Reply-line surface
  ## shape (3-digit Reply-code per line, consistent code across lines,
  ## ``'-'`` on every non-final line, SP/HT/EOL on the final line, body
  ## bytes in {HT, SP..~}). Deeper parsing of the textstring (e.g.,
  ## enhanced status codes per RFC 3463) is deferred (G12).
  detectSmtpReply(raw).isOkOr:
    return err(toValidationError(error, "SmtpReply", raw))
  return ok(SmtpReply(raw))

# ===========================================================================
# DeliveryStatus + DeliveryStatusMap — per-recipient delivery outcome
# ===========================================================================

type DeliveryStatus* {.ruleOff: "objects".} = object
  ## RFC 8621 §7 ``deliveryStatus`` entry. Composes the validated SMTP
  ## Reply-line with the two parsed recipient-state classifications.
  smtpReply*: SmtpReply
  delivered*: ParsedDeliveredState
  displayed*: ParsedDisplayedState

type DeliveryStatusMap* = distinct Table[RFC5321Mailbox, DeliveryStatus]
  ## Recipient-keyed delivery outcome table (G9). Key equality is byte-
  ## equality on ``RFC5321Mailbox`` — two addresses differing only in
  ## local-part casing are distinct keys, matching the RFC 5321 §2.4
  ## "local-part case is server-defined" semantics. Consumption is via
  ## the named domain operations (``countDelivered``, ``anyFailed``);
  ## serde (Step 11) casts to the underlying ``Table`` at its own call
  ## site.

func `==`*(a, b: DeliveryStatusMap): bool {.borrow.}
  ## Structural equality delegated to the underlying ``Table``.

func `$`*(a: DeliveryStatusMap): string {.borrow.}
  ## Textual form delegated to the underlying ``Table`` (diagnostic only).

func countDelivered*(m: DeliveryStatusMap): int =
  ## Number of recipients with ``delivered.state == dsYes``. Useful for
  ## "N of M successfully delivered" diagnostics at the consumer layer.
  result = 0
  for ds in (Table[RFC5321Mailbox, DeliveryStatus])(m).values:
    if ds.delivered.state == dsYes:
      inc result

func anyFailed*(m: DeliveryStatusMap): bool =
  ## ``true`` iff any recipient has ``delivered.state == dsNo`` — the
  ## short-circuit predicate for surfacing at-least-one-failure in a
  ## batched submission.
  for ds in (Table[RFC5321Mailbox, DeliveryStatus])(m).values:
    if ds.delivered.state == dsNo:
      return true
  false

# ===========================================================================
# Infallible parsers for the open-world enums
# ===========================================================================

func parseDeliveredState*(raw: string): ParsedDeliveredState =
  ## Total function: case-sensitive match against the four RFC-defined
  ## backing strings; unrecognised input falls through to ``dsOther``
  ## with ``rawBacking`` preserving the original token. Mirrors the
  ## ``parseMethodErrorType`` precedent (``errors.nim``) exactly —
  ## case-insensitivity, if ever required, is the caller's job
  ## upstream (``toLowerAscii``), not a single-arg ``parseEnum`` overload
  ## (which would raise ``ValueError`` and break the module's
  ## ``raises: []`` contract).
  ParsedDeliveredState(
    state: strutils.parseEnum[DeliveredState](raw, dsOther), rawBacking: raw
  )

func parseDisplayedState*(raw: string): ParsedDisplayedState =
  ## Total function symmetric with ``parseDeliveredState``; unknown
  ## tokens fall through to ``dpOther`` with raw preserved.
  ParsedDisplayedState(
    state: strutils.parseEnum[DisplayedState](raw, dpOther), rawBacking: raw
  )
