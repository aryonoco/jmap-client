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
##   3. ``ParsedSmtpReply`` + ``DeliveryStatus`` + ``DeliveryStatusMap``
##      — per-recipient delivery outcome (RFC 8621 §7 ¶8) with
##      ``ParsedSmtpReply`` validated against the RFC 5321 §4.2 Reply-
##      code surface shape AND the RFC 3463 §2 enhanced-status-code
##      triple, parsed once at the serde boundary (H1 ``parse-once``
##      invariant, H23).
##
## Design authority: ``docs/design/12-mail-G1-design.md`` §3.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sequtils
import std/strutils
import std/tables

import ../types/validation
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
# SmtpReply — RFC 5321 §4.2 Reply-line + RFC 3463 §2 enhanced status code
# ===========================================================================

type ReplyCode* = distinct uint16
  ## RFC 5321 §4.2.3 three-digit Reply-code. Validated via
  ## ``detectReplyCodeGrammar``. First digit ∈ {2,3,4,5}, second ∈
  ## {0..5}, third ∈ {0..9}.

type StatusCodeClass* = enum
  ## RFC 3463 §3.1 class digit. String-backed for lossless round-trip;
  ## closed — RFC 3463 cannot extend this digit.
  sccSuccess = "2"
  sccTransientFailure = "4"
  sccPermanentFailure = "5"

type SubjectCode* = distinct uint16
  ## RFC 3463 §4 subject sub-code. Bounded 0..999 (H19 — lenient within
  ## the IANA registry's extensibility policy).

type DetailCode* = distinct uint16
  ## RFC 3463 §4 detail sub-code. Bounded 0..999, same rationale.

func `==`*(a, b: ReplyCode): bool {.borrow.}
  ## Equality comparison delegated to the underlying ``uint16``.

func `$`*(a: ReplyCode): string {.borrow.}
  ## Decimal stringification delegated to the underlying ``uint16``.

func hash*(a: ReplyCode): Hash {.borrow.} ## Hash delegated to the underlying ``uint16``.

func `==`*(a, b: SubjectCode): bool {.borrow.}
  ## Equality comparison delegated to the underlying ``uint16``.

func `$`*(a: SubjectCode): string {.borrow.}
  ## Decimal stringification delegated to the underlying ``uint16``.

func hash*(a: SubjectCode): Hash {.borrow.}
  ## Hash delegated to the underlying ``uint16``.

func `==`*(a, b: DetailCode): bool {.borrow.}
  ## Equality comparison delegated to the underlying ``uint16``.

func `$`*(a: DetailCode): string {.borrow.}
  ## Decimal stringification delegated to the underlying ``uint16``.

func hash*(a: DetailCode): Hash {.borrow.}
  ## Hash delegated to the underlying ``uint16``.

type EnhancedStatusCode* {.ruleOff: "objects".} = object
  ## RFC 3463 §2 triple ``class.subject.detail``. Plain object —
  ## structural equality is auto-derived and correct (no case
  ## discriminator).
  klass*: StatusCodeClass
  subject*: SubjectCode
  detail*: DetailCode

type ParsedSmtpReply* {.ruleOff: "objects".} = object
  ## RFC 5321 §4.2 multi-line Reply parsed once, plus optional RFC 3463
  ## §2 enhanced-status-code triple from the final line. ``raw``
  ## preserves the exact ingress bytes (H24 canonicalisation
  ## contract); ``renderSmtpReply`` emits the canonical LF form.
  replyCode*: ReplyCode
  enhanced*: Opt[EnhancedStatusCode]
  text*: string
  raw*: string

type SmtpReplyViolation* = enum
  ## Structural and enhanced-code grammatical failures of the RFC 5321
  ## §4.2 Reply-line surface and the RFC 3463 §2 enhanced status-code
  ## triple. Module-public in H1 for test introspection (H25); the
  ## public parser projects these to ``ValidationError`` via
  ## ``toValidationError`` at the wire boundary — one translation site,
  ## one compile error per new variant.

  # Surface grammar — unchanged from G1 (10 variants).
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

  # Enhanced-status-code grammar — new in H1 (5 variants).
  srEnhancedMalformedTriple
  srEnhancedClassInvalid
  srEnhancedSubjectOverflow
  srEnhancedDetailOverflow
  srEnhancedMultilineMismatch

func toValidationError(v: SmtpReplyViolation, raw: string): ValidationError =
  ## Sole domain-to-wire translator for ``SmtpReplyViolation``. Adding
  ## a variant forces a compile error here and nowhere else (H20).
  case v
  of srEmpty:
    validationError("SmtpReply", "must not be empty", raw)
  of srControlChars:
    validationError("SmtpReply", "contains disallowed control characters", raw)
  of srLineTooShort:
    validationError("SmtpReply", "line shorter than 3-digit Reply-code", raw)
  of srBadReplyCodeDigit1:
    validationError("SmtpReply", "first Reply-code digit must be in 2..5", raw)
  of srBadReplyCodeDigit2:
    validationError("SmtpReply", "second Reply-code digit must be in 0..5", raw)
  of srBadReplyCodeDigit3:
    validationError("SmtpReply", "third Reply-code digit must be in 0..9", raw)
  of srBadSeparator:
    validationError(
      "SmtpReply", "character after Reply-code must be SP, HT, or '-'", raw
    )
  of srMultilineCodeMismatch:
    validationError("SmtpReply", "multi-line reply has inconsistent Reply-codes", raw)
  of srMultilineContinuation:
    validationError("SmtpReply", "non-final reply line must use '-' continuation", raw)
  of srMultilineFinalHyphen:
    validationError("SmtpReply", "final reply line must not use '-' continuation", raw)
  of srEnhancedMalformedTriple:
    validationError(
      "SmtpReply", "enhanced status code not a numeric dot-separated triple", raw
    )
  of srEnhancedClassInvalid:
    validationError("SmtpReply", "enhanced status-code class must be 2, 4, or 5", raw)
  of srEnhancedSubjectOverflow:
    validationError("SmtpReply", "enhanced status-code subject out of 0..999", raw)
  of srEnhancedDetailOverflow:
    validationError("SmtpReply", "enhanced status-code detail out of 0..999", raw)
  of srEnhancedMultilineMismatch:
    validationError(
      "SmtpReply", "multi-line reply has inconsistent enhanced status codes", raw
    )

# --- Atomic detectors ------------------------------------------------------

func detectReplyCodeGrammar*(line: string): Result[ReplyCode, SmtpReplyViolation] =
  ## Three-digit Reply-code grammar (RFC 5321 §4.2.3). Precondition
  ## ``line.len >= 3`` (caller-enforced). Returns the numeric Reply-
  ## code; the ``StatusCodeClass`` is derivable from the first digit
  ## when the caller needs it.
  if line[0] notin {'2' .. '5'}:
    return err(srBadReplyCodeDigit1)
  if line[1] notin {'0' .. '5'}:
    return err(srBadReplyCodeDigit2)
  if line[2] notin {'0' .. '9'}:
    return err(srBadReplyCodeDigit3)
  let n =
    uint16(ord(line[0]) - ord('0')) * 100'u16 + uint16(ord(line[1]) - ord('0')) * 10'u16 +
    uint16(ord(line[2]) - ord('0'))
  ok(ReplyCode(n))

func detectSeparator*(line: string, isFinal: bool): Result[void, SmtpReplyViolation] =
  ## Byte after the Reply-code: SP/HT on the final line, ``'-'`` on a
  ## continuation. A bare 3-char line with no separator is legal only
  ## as the final line.
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

func detectClassDigit*(c: char): Result[StatusCodeClass, SmtpReplyViolation] =
  ## RFC 3463 §3.1 class digit.
  case c
  of '2':
    ok(sccSuccess)
  of '4':
    ok(sccTransientFailure)
  of '5':
    ok(sccPermanentFailure)
  else:
    err(srEnhancedClassInvalid)

func detectSubjectInRange*(n: uint16): Result[SubjectCode, SmtpReplyViolation] =
  ## Bounds check for RFC 3463 §4 subject sub-code.
  if n > 999'u16:
    return err(srEnhancedSubjectOverflow)
  ok(SubjectCode(n))

func detectDetailInRange*(n: uint16): Result[DetailCode, SmtpReplyViolation] =
  ## Bounds check for RFC 3463 §4 detail sub-code.
  if n > 999'u16:
    return err(srEnhancedDetailOverflow)
  ok(DetailCode(n))

func detectConsistentItems*[T](
    per: openArray[T], violation: SmtpReplyViolation
): Result[void, SmtpReplyViolation] =
  ## Verifies every element of ``per`` compares equal to the first.
  ## Used for RFC 5321 §4.2.1 Reply-code consistency across multi-line
  ## replies AND for RFC 3463 §2 enhanced-code consistency across
  ## those lines that carry a triple (H22 — one helper, two call
  ## sites).
  if per.len <= 1:
    return ok()
  let first = per[0]
  for i in 1 ..< per.len:
    if per[i] != first:
      return err(violation)
  ok()

func parseEnhancedComponent(raw: string): Opt[uint16] =
  ## Parses ``raw`` as a run of ASCII digits into a ``uint16``. Returns
  ## ``none`` on empty input, any non-digit byte, or on overflow of
  ## ``uint16``. Never raises. Used only by ``detectEnhancedTriple`` to
  ## split an enhanced-status-code triple into its three numeric
  ## components before range-checking. The 5-digit cap is the widest
  ## string that can fit in ``uint16``; 6+ digits is malformed (not
  ## computed) because stdlib ``parseInt`` raises ``ValueError``, which
  ## is unusable under ``{.raises: [].}``.
  if raw.len == 0 or raw.len > 5:
    return Opt.none(uint16)
  var n: uint32 = 0
  for c in raw:
    if c notin {'0' .. '9'}:
      return Opt.none(uint16)
    n = n * 10'u32 + uint32(ord(c) - ord('0'))
  if n > 0xFFFF'u32:
    return Opt.none(uint16)
  Opt.some(uint16(n))

func detectEnhancedTriple(raw: string): Result[EnhancedStatusCode, SmtpReplyViolation] =
  ## RFC 3463 §2 ``class "." subject "." detail``. Splits the triple,
  ## validates the class digit, parses and bounds-checks subject and
  ## detail. Caller has already stripped the Reply-code prefix and
  ## separator.
  let parts = raw.split('.')
  if parts.len != 3 or parts[0].len != 1:
    return err(srEnhancedMalformedTriple)
  let klass = ?detectClassDigit(parts[0][0])
  let subjectNum = parseEnhancedComponent(parts[1]).valueOr:
    return err(srEnhancedMalformedTriple)
  let subject = ?detectSubjectInRange(subjectNum)
  let detailNum = parseEnhancedComponent(parts[2]).valueOr:
    return err(srEnhancedMalformedTriple)
  let detail = ?detectDetailInRange(detailNum)
  ok(EnhancedStatusCode(klass: klass, subject: subject, detail: detail))

# --- Composite detector (phases decomposed from the composer) --------------

func splitReplyLines(raw: string): Result[seq[string], SmtpReplyViolation] =
  ## Normalise CRLF/LF/CR to LF, drop a trailing empty segment from a
  ## CRLF-terminated payload, and return the non-empty line set.
  ## ``err(srEmpty)`` on input that degenerates to zero content lines.
  let normalised = raw.replace("\r\n", "\n").replace("\r", "\n")
  let allLines = normalised.split('\n')
  let lineCount =
    if allLines[^1].len == 0:
      allLines.len - 1
    else:
      allLines.len
  if lineCount == 0:
    return err(srEmpty)
  ok(allLines[0 ..< lineCount])

func detectLineGrammar(
    lines: openArray[string]
): Result[seq[ReplyCode], SmtpReplyViolation] =
  ## Per-line surface grammar: length floor, three-digit Reply-code,
  ## separator dispatch. Returns the Reply-code sequence for the
  ## caller's consistency check.
  var codes: seq[ReplyCode] = @[]
  for i, line in lines:
    if line.len < 3:
      return err(srLineTooShort)
    let code = ?detectReplyCodeGrammar(line)
    codes.add code
    ?detectSeparator(line, i == lines.high)
  ok(codes)

func extractTextstrings(lines: openArray[string]): seq[string] =
  ## Per-line textstring — bytes after the Reply-code separator, empty
  ## for a bare 3-char final line.
  result = @[]
  for line in lines:
    if line.len == 3:
      result.add ""
    else:
      result.add line[4 .. line.high]

func detectEnhancedOnLine(
    text: string
): Result[Opt[EnhancedStatusCode], SmtpReplyViolation] =
  ## Extract an optional RFC 3463 §2 triple from the head of ``text``.
  ## ``Opt.none`` when no candidate is present; ``Opt.some(triple)``
  ## when a dot-containing leading token parses. A candidate that
  ## looks like a triple but fails the grammar fails the whole reply.
  let endOfTriple = text.find(' ')
  let candidate =
    if endOfTriple < 0:
      text
    else:
      text[0 ..< endOfTriple]
  if candidate.len == 0 or not candidate.contains('.'):
    return ok(Opt.none(EnhancedStatusCode))
  let triple = ?detectEnhancedTriple(candidate)
  ok(Opt.some(triple))

func collectEnhanced(
    perLine: openArray[Opt[EnhancedStatusCode]]
): seq[EnhancedStatusCode] =
  ## Projection of only those lines that carry an enhanced triple,
  ## for the cross-line consistency check.
  result = @[]
  for opt in perLine:
    case opt.isOk
    of true:
      result.add opt.unsafeValue
    of false:
      discard

func assembleText(
    texts: openArray[string], perLineEnhanced: openArray[Opt[EnhancedStatusCode]]
): string =
  ## Concatenate the per-line textstrings (LF-joined) with the
  ## enhanced-status-code prefix stripped from lines that carried one.
  var textLines: seq[string] = @[]
  for i, text in texts:
    case perLineEnhanced[i].isOk
    of true:
      let endOfTriple = text.find(' ')
      textLines.add(
        if endOfTriple < 0:
          ""
        else:
          text[endOfTriple + 1 .. text.high]
      )
    of false:
      textLines.add text
  textLines.join("\n")

func detectParsedSmtpReply(raw: string): Result[ParsedSmtpReply, SmtpReplyViolation] =
  ## Composer: emptiness, global byte-set, line splitting, per-line
  ## surface grammar, Reply-code consistency, optional enhanced-
  ## status-code triple per line, enhanced-code consistency, and
  ## final assembly. Each phase is delegated to a helper so this
  ## function reads as the RFC's layered pipeline.
  if raw.len == 0:
    return err(srEmpty)
  if not raw.allIt(it in ReplyAllowedBytes):
    return err(srControlChars)
  let lines = ?splitReplyLines(raw)
  let codes = ?detectLineGrammar(lines)
  ?detectConsistentItems(codes, srMultilineCodeMismatch)
  let texts = extractTextstrings(lines)
  var perLineEnhanced: seq[Opt[EnhancedStatusCode]] = @[]
  for text in texts:
    perLineEnhanced.add ?detectEnhancedOnLine(text)
  let enhancedLinesOnly = collectEnhanced(perLineEnhanced)
  ?detectConsistentItems(enhancedLinesOnly, srEnhancedMultilineMismatch)
  let text = assembleText(texts, perLineEnhanced)
  let enhanced =
    if enhancedLinesOnly.len > 0:
      Opt.some(enhancedLinesOnly[0])
    else:
      Opt.none(EnhancedStatusCode)
  ok(ParsedSmtpReply(replyCode: codes[0], enhanced: enhanced, text: text, raw: raw))

func parseSmtpReply*(raw: string): Result[ParsedSmtpReply, ValidationError] =
  ## Public entry point for the RFC 5321 §4.2 + RFC 3463 §2 parse.
  ## Returns ``Result[ParsedSmtpReply, ValidationError]`` (H1 shape).
  let parsed = detectParsedSmtpReply(raw).valueOr:
    return err(toValidationError(error, raw))
  ok(parsed)

func renderSmtpReply*(p: ParsedSmtpReply): string =
  ## Deterministic canonical rendering (H24). Not equal to ``p.raw`` in
  ## general — ``p.raw`` preserves the ingress bytes (including CRLF);
  ## this emits LF-terminated lines only, with no trailing whitespace,
  ## and the enhanced-status-code prefix (when present) re-emitted on
  ## the final line between the SP separator and ``p.text``.
  let codeStr = $p.replyCode
  let textLines = p.text.split('\n')
  let enhancedPrefix =
    case p.enhanced.isOk
    of true:
      let e = p.enhanced.unsafeValue
      $e.klass & "." & $e.subject & "." & $e.detail & " "
    of false:
      ""
  if textLines.len <= 1:
    let text =
      if textLines.len == 1:
        textLines[0]
      else:
        ""
    if text.len == 0 and enhancedPrefix.len == 0:
      codeStr
    else:
      codeStr & " " & enhancedPrefix & text
  else:
    var parts: seq[string] = @[]
    for i in 0 ..< textLines.high:
      parts.add codeStr & "-" & textLines[i]
    parts.add codeStr & " " & enhancedPrefix & textLines[^1]
    parts.join("\n")

# ===========================================================================
# DeliveryStatus + DeliveryStatusMap — per-recipient delivery outcome
# ===========================================================================

type DeliveryStatus* {.ruleOff: "objects".} = object
  ## RFC 8621 §7 ``deliveryStatus`` entry. Composes the fully-parsed
  ## SMTP Reply-line (with RFC 3463 §2 enhanced status code, when
  ## present) with the two parsed recipient-state classifications.
  smtpReply*: ParsedSmtpReply
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
