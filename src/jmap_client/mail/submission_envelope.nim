# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 5321 lexical primitives for JMAP EmailSubmission (RFC 8621 §7).
##
## ``RFC5321Mailbox`` wraps RFC 5321 §4.1.2 ``Mailbox`` (``Local-part "@"
## ( Domain / address-literal )``) with §4.5.3.1.1 (local-part ≤ 64) and
## §4.5.3.1.2 (domain ≤ 255) length caps. Address-literal coverage is the
## full §4.1.3 grammar: IPv4, IPv6 (all four forms — IPv6-full, IPv6-comp,
## IPv6v4-full, IPv6v4-comp), and General-address-literal.
##
## ``RFC5321Keyword`` wraps §4.1.1.1 ``esmtp-keyword`` with case-insensitive
## equality per §2.4 and §4.1.1.1 ("MUST always be recognized and processed
## in a case-insensitive manner") while preserving original server casing
## in ``$`` for diagnostic round-trip.
##
## Design authority: ``docs/design/12-mail-G1-design.md`` §2.1–2.2.

{.push raises: [], noSideEffect.}

import std/hashes
import std/sequtils
import std/sets
import std/strutils
import std/tables

import ../primitives
import ../validation

# ---------------------------------------------------------------------------
# Charset constants — each lineage traced back to governing ABNF.
# ---------------------------------------------------------------------------

const
  AsciiLetters = {'A' .. 'Z', 'a' .. 'z'}
    ## RFC 5234 §B.1: ``ALPHA = %x41-5A / %x61-7A``.
  AsciiDigits = {'0' .. '9'} ## RFC 5234 §B.1: ``DIGIT = %x30-39``.
  AsciiHexDigits = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    ## RFC 5234 §B.1 literal HEXDIG is uppercase-only; case-insensitive
    ## acceptance is a deliberate divergence matching RFC 4291 §2.2
    ## prose and universal interop practice (see design §2.1).
  AtextChars = {
    'A' .. 'Z',
    'a' .. 'z',
    '0' .. '9',
    '!',
    '#',
    '$',
    '%',
    '&',
    '\'',
    '*',
    '+',
    '-',
    '/',
    '=',
    '?',
    '^',
    '_',
    '`',
    '{',
    '|',
    '}',
    '~',
  }
    ## RFC 5322 §3.2.3 ``atext``, imported by RFC 5321 §4.1.2's
    ## ``Atom = 1*atext``.
  QtextSMTPChars = {' ', '!', '#' .. '[', ']' .. '~'}
    ## RFC 5321 §4.1.2 ``qtextSMTP``: ``%d32-33 / %d35-91 / %d93-126`` —
    ## printable US-ASCII plus SP, excluding ``"`` and ``\``.
  DcontentChars = {'!' .. 'Z', '^' .. '~'}
    ## RFC 5321 §4.1.3 ``dcontent``: ``%d33-90 / %d94-126`` — printable
    ## US-ASCII excluding ``[``, ``\``, ``]``.
  LetDigChars = AsciiLetters + AsciiDigits
    ## RFC 5321 §4.1.2 ``Let-dig``: ``ALPHA / DIGIT``.
  LdhStrChars = AsciiLetters + AsciiDigits + {'-'}
    ## RFC 5321 §4.1.2 ``Ldh-str`` characters: ``ALPHA / DIGIT / "-"``.
  EsmtpKeywordLeadChars = AsciiLetters + AsciiDigits
    ## RFC 5321 §4.1.1.1 esmtp-keyword first character: ``ALPHA / DIGIT``.
  EsmtpKeywordTailChars = AsciiLetters + AsciiDigits + {'-'}
    ## RFC 5321 §4.1.1.1 esmtp-keyword subsequent characters.

# ===========================================================================
# RFC5321Mailbox
# ===========================================================================

type RFC5321Mailbox* = distinct string
  ## RFC 5321 §4.1.2 ``Mailbox``. Distinct from RFC 5322 addr-spec
  ## (``EmailAddress.email``) at the type level. Byte equality; a fully
  ## §2.4-faithful equality would case-fold only the domain half — callers
  ## needing semantic equality should lowercase the domain before
  ## comparing (see design §2.1).

defineStringDistinctOps(RFC5321Mailbox)

type MailboxViolation = enum
  ## Structural failures of the RFC 5321 §4.1.2 Mailbox grammar. Module-
  ## private; the public parsers translate these to ``ValidationError``
  ## at the wire boundary (``toValidationError``) so every failure
  ## message lives in exactly one place and adding a variant forces a
  ## compile error at the translator, not at every detector.
  mvEmpty
  mvControlChars
  mvNoAtSign
  mvLocalPartEmpty
  mvLocalPartTooLong
  mvLocalPartBadDotString
  mvLocalPartBadQuotedString
  mvDomainEmpty
  mvDomainTooLong
  mvDomainBadLabel
  mvAddressLiteralUnclosed
  mvAddressLiteralBadIPv4
  mvAddressLiteralBadIPv6
  mvAddressLiteralBadGeneral

func toValidationError(v: MailboxViolation, typeName, raw: string): ValidationError =
  ## Sole domain-to-wire translator for ``MailboxViolation``. Adding a
  ## variant forces a compile error here, not at every detector site.
  case v
  of mvEmpty:
    validationError(typeName, "must not be empty", raw)
  of mvControlChars:
    validationError(typeName, "contains control characters", raw)
  of mvNoAtSign:
    validationError(typeName, "missing '@' separator", raw)
  of mvLocalPartEmpty:
    validationError(typeName, "local-part must not be empty", raw)
  of mvLocalPartTooLong:
    validationError(typeName, "local-part exceeds 64 octets", raw)
  of mvLocalPartBadDotString:
    validationError(typeName, "local-part is not a valid dot-string", raw)
  of mvLocalPartBadQuotedString:
    validationError(typeName, "local-part is not a valid quoted-string", raw)
  of mvDomainEmpty:
    validationError(typeName, "domain must not be empty", raw)
  of mvDomainTooLong:
    validationError(typeName, "domain exceeds 255 octets", raw)
  of mvDomainBadLabel:
    validationError(typeName, "domain contains an invalid label", raw)
  of mvAddressLiteralUnclosed:
    validationError(typeName, "address-literal missing closing ']'", raw)
  of mvAddressLiteralBadIPv4:
    validationError(typeName, "address-literal has invalid IPv4 form", raw)
  of mvAddressLiteralBadIPv6:
    validationError(typeName, "address-literal has invalid IPv6 form", raw)
  of mvAddressLiteralBadGeneral:
    validationError(typeName, "address-literal has invalid general form", raw)

# --- Leaf detectors --------------------------------------------------------

func detectMailboxNoControlChars(raw: string): Result[void, MailboxViolation] =
  ## Rejects bytes below SP (0x20) and DEL (0x7F). No length bound — a
  ## strict Mailbox may be up to 64 + 1 + 255 = 320 octets. Mirrors
  ## ``validation.nim``'s module-private ``detectNoControlChars`` so the
  ## atomic-detector boundary of that module is preserved.
  if raw.anyIt(it < ' ' or it == '\x7F'):
    return err(mvControlChars)
  ok()

func findClosingQuote(raw: string): Result[int, MailboxViolation] =
  ## Returns the index of the closing DQUOTE matching ``raw[0]``. Skips
  ## backslash-escaped chars so ``\"`` does not terminate the scan.
  ## Position-finder only — full quoted-string validation is done later
  ## by ``checkQuotedString`` once the local-part is extracted.
  ## Precondition: ``raw[0] == '"'``.
  var i = 1
  while i < raw.len:
    case raw[i]
    of '\\':
      if i + 1 >= raw.len:
        return err(mvLocalPartBadQuotedString)
      i += 2
    of '"':
      return ok(i)
    else:
      inc i
  err(mvLocalPartBadQuotedString)

func findSplitAt(raw: string): Result[int, MailboxViolation] =
  ## Returns the index of the Mailbox ``'@'`` separator. A leading
  ## quoted local-part is walked past so that ``'@'`` inside quotes
  ## doesn't split the address.
  if raw.len == 0:
    return err(mvEmpty)
  let searchStart =
    if raw[0] == '"':
      (?findClosingQuote(raw)) + 1
    else:
      0
  let atIdx = raw.find('@', start = searchStart)
  if atIdx < 0:
    return err(mvNoAtSign)
  ok(atIdx)

func checkIPv6Hex(token: string): Result[void, MailboxViolation] =
  ## ``1*4HEXDIG`` (case-insensitive per the deliberate divergence
  ## documented in the module's scope / design §2.1).
  if token.len < 1 or token.len > 4:
    return err(mvAddressLiteralBadIPv6)
  if not token.allIt(it in AsciiHexDigits):
    return err(mvAddressLiteralBadIPv6)
  ok()

func checkLdhLabel(raw: string): Result[void, MailboxViolation] =
  ## ``sub-domain = Let-dig [Ldh-str]`` — starts and ends with a Let-dig,
  ## interior permits hyphens. Also the shape of ``Standardized-tag``
  ## inside General-address-literal.
  if raw.len == 0:
    return err(mvDomainBadLabel)
  if raw[0] notin LetDigChars or raw[^1] notin LetDigChars:
    return err(mvDomainBadLabel)
  if not raw.allIt(it in LdhStrChars):
    return err(mvDomainBadLabel)
  ok()

func snumValue(raw: string): int =
  ## Decimal value of a 1*3DIGIT string. Caller has verified all chars
  ## are ``AsciiDigits`` and length is 1..3, so overflow is structurally
  ## impossible (max 999).
  raw.foldl(a * 10 + (ord(b) - ord('0')), 0)

func parseSnum(raw: string): Result[void, MailboxViolation] =
  ## RFC 5321 §4.1.3 ``Snum = 1*3DIGIT`` with value constrained to
  ## 0..255. Expressed as a conjunction of three predicates: length
  ## bound, digit-only charset, and decoded-value bound.
  if raw.len notin 1 .. 3 or not raw.allIt(it in AsciiDigits) or raw.snumValue > 255:
    return err(mvAddressLiteralBadIPv4)
  ok()

# --- IPv4 literal ---------------------------------------------------------

func checkIPv4Literal(raw: string): Result[void, MailboxViolation] =
  ## ``IPv4-address-literal = Snum 3("." Snum)``.
  let parts = raw.split('.')
  if parts.len != 4:
    return err(mvAddressLiteralBadIPv4)
  for p in parts:
    ?parseSnum(p)
  ok()

# --- IPv6 literal ---------------------------------------------------------

type IPv6FormKind = enum
  ## Four mutually-exclusive RFC 5321 §4.1.3 IPv6 grammar forms. Named
  ## so the dispatch in ``validateIPv6Form`` is an exhaustive ``case``
  ## over a discriminator — adding a form forces a compile error at the
  ## validator, never at the classification site.
  i6Full ## IPv6-full: 8 hex groups, no "::"
  i6Comp ## IPv6-comp: L "::" R, no IPv4 tail
  i6V4Full ## IPv6v4-full: 6 hex groups ":" IPv4
  i6V4Comp ## IPv6v4-comp: L "::" R [":"] IPv4

type IPv6Form {.ruleOff: "objects".} = object
  ## Classified shape of an IPv6 literal body. The validator pattern-
  ## matches on ``kind`` to apply the form-specific group-count
  ## constraints. Each side of ``"::"`` is stored as its raw colon-
  ## separated body string; an empty string means "zero groups on this
  ## side", which is legal in the compressed forms.
  case kind: IPv6FormKind
  of i6Full:
    fullBody: string
  of i6Comp:
    compLeft, compRight: string
  of i6V4Full:
    v4FullHex: string
    v4FullAddr: string
  of i6V4Comp:
    v4CompLeft, v4CompRight: string
    v4CompAddr: string

func splitV4Tail(body: string): tuple[hex: string, v4: string] =
  ## Splits ``body`` at the last ``':'`` into the hex prefix and the
  ## IPv4 tail. With no ``':'`` at all, ``hex`` is empty and ``v4`` is
  ## the whole body — the ``::IPv4`` case where the right side of
  ## ``"::"`` is just the IPv4 literal.
  let lastColon = body.rfind(':')
  if lastColon < 0:
    ("", body)
  else:
    (body[0 ..< lastColon], body[lastColon + 1 .. body.high])

func containsV4Tail(body: string): bool =
  ## ``true`` iff the last ``':'``-delimited segment of ``body``
  ## contains a ``'.'`` — the signature of an IPv4 literal tail. Falls
  ## back to "any ``.`` in body" when there is no ``':'`` at all (covers
  ## the ``::IPv4`` case where the right side is just the IPv4 literal).
  let lastColon = body.rfind(':')
  if lastColon < 0:
    '.' in body
  else:
    '.' in body[lastColon + 1 .. body.high]

func classifyIPv6(body: string): Result[IPv6Form, MailboxViolation] =
  ## Single 2×2 dispatch on (has ``"::"``, has IPv4 tail). Rejects more
  ## than one ``"::"``. Returns a fully-decomposed ``IPv6Form`` that the
  ## validator can ``case`` over exhaustively.
  let compParts = body.split("::")
  if compParts.len > 2:
    return err(mvAddressLiteralBadIPv6)
  let hasComp = compParts.len == 2
  let hasV4 = containsV4Tail(body)

  if hasComp and hasV4:
    let (rHex, v4) = splitV4Tail(compParts[1])
    return ok(
      IPv6Form(
        kind: i6V4Comp, v4CompLeft: compParts[0], v4CompRight: rHex, v4CompAddr: v4
      )
    )
  if hasComp:
    return ok(IPv6Form(kind: i6Comp, compLeft: compParts[0], compRight: compParts[1]))
  if hasV4:
    let (hex, v4) = splitV4Tail(body)
    if hex.len == 0:
      return err(mvAddressLiteralBadIPv6)
    return ok(IPv6Form(kind: i6V4Full, v4FullHex: hex, v4FullAddr: v4))
  ok(IPv6Form(kind: i6Full, fullBody: body))

func checkHexGroups(
    body: string, minGroups, maxGroups: int
): Result[int, MailboxViolation] =
  ## Validates each ``':'``-delimited token of ``body`` as ``1*4HEXDIG``.
  ## Empty ``body`` yields 0 groups (legal when ``minGroups == 0``).
  ## Enforces ``minGroups <= count <= maxGroups`` and returns ``count``
  ## so compressed forms can apply the combined-bound rule.
  if body.len == 0:
    if minGroups > 0:
      return err(mvAddressLiteralBadIPv6)
    return ok(0)
  let parts = body.split(':')
  if parts.len < minGroups or parts.len > maxGroups:
    return err(mvAddressLiteralBadIPv6)
  for p in parts:
    ?checkIPv6Hex(p)
  ok(parts.len)

func validateIPv6Form(form: IPv6Form): Result[void, MailboxViolation] =
  ## Exhaustive ``case`` over ``IPv6FormKind``. Adding a variant forces
  ## a compile error here. Each branch applies the form-specific bound:
  ## ``i6Full`` — exactly 8 groups; ``i6Comp`` — each side 0..6,
  ## combined ≤ 6; ``i6V4Full`` — exactly 6 hex groups + valid IPv4
  ## tail; ``i6V4Comp`` — each side 0..4, combined ≤ 4, plus valid IPv4
  ## tail. IPv4-tail failure is reprojected to ``mvAddressLiteralBadIPv6``
  ## because a bad tail invalidates the whole IPv6 literal, not the
  ## IPv4 specifically.
  case form.kind
  of i6Full:
    discard ?checkHexGroups(form.fullBody, 8, 8)
    ok()
  of i6Comp:
    let l = ?checkHexGroups(form.compLeft, 0, 6)
    let r = ?checkHexGroups(form.compRight, 0, 6)
    if l + r > 6:
      return err(mvAddressLiteralBadIPv6)
    ok()
  of i6V4Full:
    discard ?checkHexGroups(form.v4FullHex, 6, 6)
    checkIPv4Literal(form.v4FullAddr).isOkOr:
      return err(mvAddressLiteralBadIPv6)
    ok()
  of i6V4Comp:
    let l = ?checkHexGroups(form.v4CompLeft, 0, 4)
    let r = ?checkHexGroups(form.v4CompRight, 0, 4)
    if l + r > 4:
      return err(mvAddressLiteralBadIPv6)
    checkIPv4Literal(form.v4CompAddr).isOkOr:
      return err(mvAddressLiteralBadIPv6)
    ok()

func checkIPv6Literal(raw: string): Result[void, MailboxViolation] =
  ## ``IPv6-address-literal = "IPv6:" IPv6-addr``. The ``"IPv6:"``
  ## prefix is consumed by ``classifyAddressLiteral``; this function
  ## runs the classify-then-validate pipeline on the residual body.
  let form = ?classifyIPv6(raw)
  validateIPv6Form(form)

# --- Address literal dispatch --------------------------------------------

type AddressLiteralKind = enum
  alV4
  alV6
  alGeneral

type AddressLiteral {.ruleOff: "objects".} = object
  ## RFC 5321 §4.1.3 ``address-literal`` classified by prefix. Each
  ## variant carries the bracket-stripped, prefix-stripped content
  ## needed by its validator. The ``"IPv6:"`` prefix is consumed during
  ## classification so the validator sees only the grammar body.
  case kind: AddressLiteralKind
  of alV4:
    v4Body: string
  of alV6:
    v6Body: string
  of alGeneral:
    genTag, genContent: string

func classifyAddressLiteral(inner: string): Result[AddressLiteral, MailboxViolation] =
  ## Single-pass dispatch by prefix / colon presence. ``inner`` is the
  ## bracket-stripped body of ``"[" ... "]"``. The ``"IPv6:"`` prefix
  ## branch runs first, so a literal tag of ``"IPv6"`` can never reach
  ## the general-literal branch — structural invariant, not a check.
  if inner.len == 0:
    return err(mvAddressLiteralBadGeneral)
  if inner.startsWith("IPv6:"):
    return ok(AddressLiteral(kind: alV6, v6Body: inner[5 .. inner.high]))
  if ':' in inner:
    let colonIdx = inner.find(':')
    if colonIdx <= 0 or colonIdx >= inner.high:
      return err(mvAddressLiteralBadGeneral)
    return ok(
      AddressLiteral(
        kind: alGeneral,
        genTag: inner[0 ..< colonIdx],
        genContent: inner[colonIdx + 1 .. inner.high],
      )
    )
  ok(AddressLiteral(kind: alV4, v4Body: inner))

func checkGeneralLiteral(tag, content: string): Result[void, MailboxViolation] =
  ## ``General-address-literal = Standardized-tag ":" 1*dcontent``.
  ## ``tag`` and ``content`` have already been split by
  ## ``classifyAddressLiteral``; ``tag`` is known non-empty and cannot
  ## equal ``"IPv6"`` by the classification order.
  checkLdhLabel(tag).isOkOr:
    return err(mvAddressLiteralBadGeneral)
  if not content.allIt(it in DcontentChars):
    return err(mvAddressLiteralBadGeneral)
  ok()

func validateAddressLiteral(al: AddressLiteral): Result[void, MailboxViolation] =
  ## Exhaustive ``case`` over ``AddressLiteralKind``. Adding a variant
  ## forces a compile error here.
  case al.kind
  of alV4:
    checkIPv4Literal(al.v4Body)
  of alV6:
    checkIPv6Literal(al.v6Body)
  of alGeneral:
    checkGeneralLiteral(al.genTag, al.genContent)

func checkAddressLiteral(raw: string): Result[void, MailboxViolation] =
  ## Classify-then-validate pipeline for the bracket-stripped body of
  ## an address-literal.
  let al = ?classifyAddressLiteral(raw)
  validateAddressLiteral(al)

# --- Domain and local-part ------------------------------------------------

func checkDomainName(raw: string): Result[void, MailboxViolation] =
  ## ``Domain = sub-domain *("." sub-domain)`` with §4.5.3.1.2 length
  ## cap of 255 octets.
  if raw.len == 0:
    return err(mvDomainEmpty)
  if raw.len > 255:
    return err(mvDomainTooLong)
  for label in raw.split('.'):
    ?checkLdhLabel(label)
  ok()

func checkDotString(raw: string): Result[void, MailboxViolation] =
  ## ``Dot-string = Atom *("." Atom)`` with ``Atom = 1*atext``. No
  ## leading/trailing ``'.'``, no empty atoms between dots.
  if raw.len == 0:
    return err(mvLocalPartEmpty)
  if raw[0] == '.' or raw[^1] == '.':
    return err(mvLocalPartBadDotString)
  if ".." in raw:
    return err(mvLocalPartBadDotString)
  if not raw.allIt(it == '.' or it in AtextChars):
    return err(mvLocalPartBadDotString)
  ok()

type QuotedState = enum
  ## Two-state machine for RFC 5321 §4.1.2 Quoted-string content (the
  ## chars between the outer DQUOTEs). ``qsNormal`` is the default
  ## state; ``qsEscape`` means the previous char was ``'\\'`` and the
  ## current char must be a ``quoted-pairSMTP`` body (any %d32-126).
  qsNormal
  qsEscape

func stepQuoted(state: QuotedState, ch: char): Result[QuotedState, MailboxViolation] =
  ## Pure transition function for the Quoted-string content state
  ## machine. Total: every ``(state, ch)`` pair either yields a next
  ## state or a structural violation.
  case state
  of qsNormal:
    if ch == '\\':
      ok(qsEscape)
    elif ch in QtextSMTPChars:
      ok(qsNormal)
    else:
      err(mvLocalPartBadQuotedString)
  of qsEscape:
    if ch >= ' ' and ch <= '~':
      ok(qsNormal)
    else:
      err(mvLocalPartBadQuotedString)

func checkQuotedString(raw: string): Result[void, MailboxViolation] =
  ## ``Quoted-string = DQUOTE *QcontentSMTP DQUOTE`` where
  ## ``QcontentSMTP = qtextSMTP / quoted-pairSMTP``. Empty-content
  ## ``""`` rejected as ``mvLocalPartEmpty`` — no routable content and
  ## universal MTA behaviour. Content is folded through ``stepQuoted``;
  ## a terminal state of ``qsEscape`` means the string ended mid-
  ## escape, which is a structural failure.
  if raw.len < 2 or raw[0] != '"' or raw[^1] != '"':
    return err(mvLocalPartBadQuotedString)
  if raw.len == 2:
    return err(mvLocalPartEmpty)
  var state = qsNormal
  for i in 1 ..< raw.high:
    state = ?stepQuoted(state, raw[i])
  if state != qsNormal:
    return err(mvLocalPartBadQuotedString)
  ok()

func checkLocalPart(raw: string): Result[void, MailboxViolation] =
  ## ``Local-part = Dot-string / Quoted-string`` with §4.5.3.1.1 length
  ## cap of 64 octets. Dispatches on the leading DQUOTE.
  if raw.len == 0:
    return err(mvLocalPartEmpty)
  if raw.len > 64:
    return err(mvLocalPartTooLong)
  if raw[0] == '"':
    return checkQuotedString(raw)
  checkDotString(raw)

func detectStrictMailbox(raw: string): Result[void, MailboxViolation] =
  ## Top-level composer: emptiness + control-chars + split + local-part
  ## + domain / address-literal. Fails fast with the first violation.
  if raw.len == 0:
    return err(mvEmpty)
  ?detectMailboxNoControlChars(raw)
  let atIdx = ?findSplitAt(raw)
  let localPart = raw[0 ..< atIdx]
  let domain = raw[atIdx + 1 .. raw.high]
  ?checkLocalPart(localPart)
  if domain.len == 0:
    return err(mvDomainEmpty)
  if domain[0] == '[':
    if domain.len < 2 or domain[^1] != ']':
      return err(mvAddressLiteralUnclosed)
    return checkAddressLiteral(domain[1 .. domain.high - 1])
  checkDomainName(domain)

func parseRFC5321Mailbox*(raw: string): Result[RFC5321Mailbox, ValidationError] =
  ## Strict client-side constructor: full RFC 5321 §4.1.2 Mailbox grammar
  ## (Dot-string / Quoted-string local-part, Domain / address-literal
  ## domain, all four IPv6 forms) with §4.5.3.1.1 local-part ≤ 64 and
  ## §4.5.3.1.2 domain ≤ 255 length caps. Returns a ``ValidationError``
  ## on the error rail.
  detectStrictMailbox(raw).isOkOr:
    return err(toValidationError(error, "RFC5321Mailbox", raw))
  return ok(RFC5321Mailbox(raw))

func parseRFC5321MailboxFromServer*(
    raw: string
): Result[RFC5321Mailbox, ValidationError] =
  ## Lenient server-side constructor (Postel's law): 1..255 octets, no
  ## control characters, must contain ``'@'``. Accepts UTF-8 bytes and
  ## structural variations that the strict parser rejects.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "RFC5321Mailbox", raw))
  if '@' notin raw:
    return err(toValidationError(mvNoAtSign, "RFC5321Mailbox", raw))
  return ok(RFC5321Mailbox(raw))

# ===========================================================================
# RFC5321Keyword
# ===========================================================================

type RFC5321Keyword* = distinct string
  ## RFC 5321 §4.1.1.1 ``esmtp-keyword``:
  ## ``(ALPHA / DIGIT) *(ALPHA / DIGIT / "-")``, bounded to 64 octets
  ## (defensive cap — the RFC is silent on an explicit maximum). Case-
  ## insensitive equality and hash per §2.4 and §4.1.1.1; ``$`` preserves
  ## the original casing for diagnostic round-trip.

func `==`*(a, b: RFC5321Keyword): bool =
  ## ASCII case-insensitive equality per RFC 5321 §4.1.1.1. Server
  ## casing preserved in ``$`` for diagnostic round-trip.
  cmpIgnoreCase(string(a), string(b)) == 0

func `$`*(a: RFC5321Keyword): string {.borrow.}
  ## Preserves the original casing (unchanged from construction).

func hash*(a: RFC5321Keyword): Hash =
  ## Case-fold hash so ``==``-equal values hash identically — required
  ## for correctness of ``Table[RFC5321Keyword, _]`` lookups.
  hash(toLowerAscii(string(a)))

func len*(a: RFC5321Keyword): int {.borrow.}
  ## Length in octets (always 1..64 for constructed values).

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
  return ok(RFC5321Keyword(raw))

# ===========================================================================
# SMTP parameter payload leaves — design §2.3
# ===========================================================================

type BodyEncoding* = enum
  ## RFC 1652 / RFC 6152 ``BODY=`` parameter values. Selects whether the
  ## submission MTA treats the message as 7-bit, 8-bit-clean MIME, or
  ## binary MIME. Backing strings are the IANA-registered tokens.
  beSevenBit = "7BIT"
  beEightBitMime = "8BITMIME"
  beBinaryMime = "BINARYMIME"

type DsnRetType* = enum
  ## RFC 3461 §4.3 ``RET=`` parameter value. ``FULL`` requests return of
  ## the whole message on failure; ``HDRS`` requests return of headers
  ## only.
  retFull = "FULL"
  retHdrs = "HDRS"

type DsnNotifyFlag* = enum
  ## RFC 3461 §4.1 ``NOTIFY=`` parameter flag. A non-empty ``set`` of
  ## these flags forms the wire value; ``dnfNever`` is mutually exclusive
  ## with the other three — enforced by ``notifyParam``.
  dnfNever = "NEVER"
  dnfSuccess = "SUCCESS"
  dnfFailure = "FAILURE"
  dnfDelay = "DELAY"

type DeliveryByMode* = enum
  ## RFC 2852 §3 ``BY=`` parameter mode suffix. ``R`` / ``N`` request
  ## return-on-deadline / notify-on-deadline; the ``T`` variants also
  ## request trace-header insertion on deadline expiry.
  dbmReturn = "R"
  dbmNotify = "N"
  dbmReturnTrace = "RT"
  dbmNotifyTrace = "NT"

# ===========================================================================
# OrcptAddrType — RFC 3461 §4.2 addr-type atom
# ===========================================================================

type OrcptAddrType* = distinct string
  ## RFC 3461 §4.2 ``addr-type`` atom of the ``ORCPT=`` parameter value.
  ## Shares esmtp-keyword grammar — ``(ALPHA / DIGIT)
  ## *(ALPHA / DIGIT / "-")`` — but preserves server casing for IANA-
  ## registered addr-types (``rfc822``, ``utf-8``, ``x400``, ``unknown``).
  ## Byte-equality, not case-insensitive — RFC 3461 does not mandate
  ## case-folding for the addr-type atom.

defineStringDistinctOps(OrcptAddrType)

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
  return ok(OrcptAddrType(raw))

# ===========================================================================
# HoldForSeconds — RFC 4865 FUTURERELEASE delay form
# ===========================================================================

type HoldForSeconds* = distinct UnsignedInt
  ## Delay-in-seconds payload for the RFC 4865 ``HOLDFOR=`` extension.
  ## Narrows ``UnsignedInt`` at the type level so mixing an arbitrary
  ## ``UnsignedInt`` with a HOLDFOR value at the call site is a compile
  ## error.

defineIntDistinctOps(HoldForSeconds)

func parseHoldForSeconds*(raw: UnsignedInt): Result[HoldForSeconds, ValidationError] =
  ## Infallible typed wrap — ``UnsignedInt`` already enforces the JSON-
  ## safe bound ``0 .. 2^53 - 1`` at its own smart constructor, so there
  ## is nothing left to reject here. The ``Result``-returning signature
  ## mirrors the other ``parse*`` functions so callers compose uniformly
  ## with ``?`` / ``valueOr:``.
  return ok(HoldForSeconds(raw))

# ===========================================================================
# MtPriority — RFC 6710 MT-PRIORITY
# ===========================================================================

type MtPriority* = distinct int
  ## RFC 6710 §2 ``MT-PRIORITY=`` parameter value, constrained to the
  ## inclusive range ``-9 .. 9``. A raw ``int`` field would let an out-
  ## of-range value slip past construction; ``range[int]`` was rejected
  ## because ``RangeDefect`` is fatal under ``--panics:on``
  ## (``.claude/rules/nim-type-safety.md``).

defineIntDistinctOps(MtPriority)

func parseMtPriority*(raw: int): Result[MtPriority, ValidationError] =
  ## Strict: enforces the inclusive ``-9 .. 9`` bound of RFC 6710 §2.
  if raw < -9 or raw > 9:
    return err(validationError("MtPriority", "must be in range -9..9", $raw))
  return ok(MtPriority(raw))

# ===========================================================================
# SubmissionParam — typed SMTP parameter algebra (design §2.3)
# ===========================================================================

type SubmissionParamKind* = enum
  ## Discriminator for ``SubmissionParam``. Eleven well-known variants
  ## cover IANA-registered RFC 5321 / RFC 3461 / RFC 1652 / RFC 6152 /
  ## RFC 1870 / RFC 2852 / RFC 6710 / RFC 4865 / RFC 6531 extensions;
  ## ``spkExtension`` is the open-world escape hatch for unregistered or
  ## vendor tokens (RFC 8621 §7 ¶5). Backing strings match the wire key
  ## preserved upper-case per SMTP convention.
  spkBody = "BODY"
  spkSmtpUtf8 = "SMTPUTF8"
  spkSize = "SIZE"
  spkEnvid = "ENVID"
  spkRet = "RET"
  spkNotify = "NOTIFY"
  spkOrcpt = "ORCPT"
  spkHoldFor = "HOLDFOR"
  spkHoldUntil = "HOLDUNTIL"
  spkBy = "BY"
  spkMtPriority = "MT-PRIORITY"
  spkExtension

type SubmissionParam* {.ruleOff: "objects".} = object
  ## Validated SMTP parameter value as carried on an
  ## ``EmailSubmission.Envelope.Address`` entry. Twelve variants — eleven
  ## well-known plus one open-world ``spkExtension`` — lift each
  ## parameter's subordinate-RFC structural invariants into the type so
  ## detection and serialisation share a single source of truth.
  case kind*: SubmissionParamKind
  of spkBody:
    bodyEncoding*: BodyEncoding
  of spkSmtpUtf8:
    discard
  of spkSize:
    sizeOctets*: UnsignedInt
  of spkEnvid:
    envid*: string
  of spkRet:
    retType*: DsnRetType
  of spkNotify:
    notifyFlags*: set[DsnNotifyFlag]
  of spkOrcpt:
    orcptAddrType*: OrcptAddrType
    orcptOrigRecipient*: string
  of spkHoldFor:
    holdFor*: HoldForSeconds
  of spkHoldUntil:
    holdUntil*: UTCDate
  of spkBy:
    byDeadline*: JmapInt
    byMode*: DeliveryByMode
  of spkMtPriority:
    mtPriority*: MtPriority
  of spkExtension:
    extName*: RFC5321Keyword
    extValue*: Opt[string]

# ---------------------------------------------------------------------------
# Smart constructors (alphabetical by SubmissionParamKind for reviewability)
# ---------------------------------------------------------------------------

func bodyParam*(e: BodyEncoding): SubmissionParam =
  ## ``BODY=7BIT|8BITMIME|BINARYMIME`` — RFC 1652 / RFC 6152.
  SubmissionParam(kind: spkBody, bodyEncoding: e)

func byParam*(deadline: JmapInt, mode: DeliveryByMode): SubmissionParam =
  ## ``BY=<deadline>;<mode>`` — RFC 2852 §3 deliver-by parameter.
  SubmissionParam(kind: spkBy, byDeadline: deadline, byMode: mode)

func envidParam*(envid: string): SubmissionParam =
  ## ``ENVID=`` — RFC 3461 §4.4 envelope identifier. The xtext wire
  ## encoding belongs to the serde layer (design §7.2); L1 carries the
  ## decoded bytes.
  SubmissionParam(kind: spkEnvid, envid: envid)

func extensionParam*(name: RFC5321Keyword, value: Opt[string]): SubmissionParam =
  ## Open-world escape hatch for unregistered / vendor SMTP parameters
  ## (RFC 8621 §7 ¶5). ``name`` already carries esmtp-keyword invariants;
  ## ``value`` is ``Opt.none`` for valueless tokens.
  SubmissionParam(kind: spkExtension, extName: name, extValue: value)

func holdForParam*(seconds: HoldForSeconds): SubmissionParam =
  ## ``HOLDFOR=<seconds>`` — RFC 4865 FUTURERELEASE delay form.
  SubmissionParam(kind: spkHoldFor, holdFor: seconds)

func holdUntilParam*(d: UTCDate): SubmissionParam =
  ## ``HOLDUNTIL=<RFC 3339 Zulu>`` — RFC 4865 FUTURERELEASE absolute-time
  ## form.
  SubmissionParam(kind: spkHoldUntil, holdUntil: d)

func mtPriorityParam*(p: MtPriority): SubmissionParam =
  ## ``MT-PRIORITY=<-9..9>`` — RFC 6710 §2.
  SubmissionParam(kind: spkMtPriority, mtPriority: p)

func notifyParam*(flags: set[DsnNotifyFlag]): Result[SubmissionParam, ValidationError] =
  ## ``NOTIFY=<flag[,flag...]>`` — RFC 3461 §4.1. Rejects the empty set
  ## and the mutually-exclusive combination ``NEVER`` with any of
  ## ``SUCCESS``/``FAILURE``/``DELAY``.
  if flags == {}:
    return err(validationError("SubmissionParam", "NOTIFY flags must not be empty", ""))
  if dnfNever in flags and flags != {dnfNever}:
    return err(
      validationError(
        "SubmissionParam",
        "NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY", "",
      )
    )
  return ok(SubmissionParam(kind: spkNotify, notifyFlags: flags))

func orcptParam*(at: OrcptAddrType, origRecipient: string): SubmissionParam =
  ## ``ORCPT=<addr-type>;<orig-recipient>`` — RFC 3461 §4.2. The
  ## original-recipient xtext encoding belongs to the serde layer; L1
  ## carries the decoded bytes.
  SubmissionParam(kind: spkOrcpt, orcptAddrType: at, orcptOrigRecipient: origRecipient)

func retParam*(t: DsnRetType): SubmissionParam =
  ## ``RET=FULL|HDRS`` — RFC 3461 §4.3.
  SubmissionParam(kind: spkRet, retType: t)

func sizeParam*(octets: UnsignedInt): SubmissionParam =
  ## ``SIZE=<octets>`` — RFC 1870 advisory octet count.
  SubmissionParam(kind: spkSize, sizeOctets: octets)

func smtpUtf8Param*(): SubmissionParam =
  ## ``SMTPUTF8`` — RFC 6531 §3.4 valueless parameter.
  SubmissionParam(kind: spkSmtpUtf8)

# ---------------------------------------------------------------------------
# SubmissionParamKey — identity key for structural uniqueness
# ---------------------------------------------------------------------------

type SubmissionParamKey* {.ruleOff: "objects".} = object
  ## Structural identity of a ``SubmissionParam`` — the wire-key axis on
  ## which uniqueness is enforced by ``SubmissionParams``. Eleven well-
  ## known arms are nullary; ``spkExtension`` carries the validated
  ## ``RFC5321Keyword`` name so two extensions with distinct names remain
  ## distinct keys.
  case kind*: SubmissionParamKind
  of spkExtension:
    extName*: RFC5321Keyword
  of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
      spkHoldUntil, spkBy, spkMtPriority:
    discard

func `==`*(a, b: SubmissionParamKey): bool =
  ## Equal iff the discriminators agree and, for ``spkExtension``, the
  ## keyword names are case-insensitively equal (delegated to
  ## ``RFC5321Keyword.==``).
  if a.kind != b.kind:
    return false
  case a.kind
  of spkExtension:
    a.extName == b.extName
  of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
      spkHoldUntil, spkBy, spkMtPriority:
    true

func hash*(k: SubmissionParamKey): Hash =
  ## Delegates the ``spkExtension`` payload to ``hash(RFC5321Keyword)``,
  ## which case-folds before hashing — otherwise two keys that compare
  ## equal case-insensitively would land in different buckets and silently
  ## break ``Table.contains`` / ``[]=`` lookups (Table contract:
  ## ``a == b`` ⇒ ``hash(a) == hash(b)``).
  case k.kind
  of spkExtension:
    var h: Hash = 0
    h = h !& hash(spkExtension.ord)
    h = h !& hash(k.extName)
    !$h
  of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
      spkHoldUntil, spkBy, spkMtPriority:
    hash(k.kind.ord)

func paramKey*(p: SubmissionParam): SubmissionParamKey =
  ## Derives the identity key for a ``SubmissionParam``. Nullary arms
  ## collapse to a kind-only key; ``spkExtension`` carries its validated
  ## keyword name. Functional-core Pattern 6 "derived-not-stored" —
  ## one source of truth per fact.
  case p.kind
  of spkExtension:
    SubmissionParamKey(kind: spkExtension, extName: p.extName)
  of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
      spkHoldUntil, spkBy, spkMtPriority:
    SubmissionParamKey(kind: p.kind)

# ---------------------------------------------------------------------------
# SubmissionParams — structural uniqueness with wire-order fidelity
# ---------------------------------------------------------------------------

type SubmissionParams* = distinct OrderedTable[SubmissionParamKey, SubmissionParam]
  ## Validated, duplicate-free collection of ``SubmissionParam`` values
  ## carrying a single ``Envelope.Address`` parameter bag. Construction
  ## is gated by ``parseSubmissionParams`` — the raw distinct constructor
  ## is not part of the public surface. Serde (Step 10) and per-address
  ## lookups (Step 3) cast back to the underlying ``OrderedTable`` at
  ## use sites; accessors are intentionally not borrowed because mutable
  ## stdlib containers don't borrow subscripts cleanly.

func detectDuplicateParamKeys(items: openArray[SubmissionParam]): seq[ValidationError] =
  ## One ``ValidationError`` per repeated ``SubmissionParamKey``, each
  ## key reported at most once. Empty input is accepted —
  ## ``parseSubmissionParams`` does not reject an empty
  ## ``SubmissionParams``. Functional-core Pattern 7 "imperative kernel
  ## inside a functional shell": two local ``HashSet``s are invisible
  ## outside the call.
  var seen = initHashSet[SubmissionParamKey]()
  var reported = initHashSet[SubmissionParamKey]()
  result = @[]
  for item in items:
    let k = paramKey(item)
    if seen.containsOrIncl(k):
      if not reported.containsOrIncl(k):
        let label =
          case k.kind
          of spkExtension:
            "extension " & $k.extName
          of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt,
              spkHoldFor, spkHoldUntil, spkBy, spkMtPriority:
            $k.kind
        result.add(
          validationError("SubmissionParams", "duplicate parameter key", label)
        )

func parseSubmissionParams*(
    items: openArray[SubmissionParam]
): Result[SubmissionParams, seq[ValidationError]] =
  ## Strict client-side constructor (design §2.4 G8a): rejects duplicate
  ## keys accumulatingly — every repeated key produces exactly one
  ## ``ValidationError``. Empty input is accepted — an empty
  ## ``SubmissionParams`` represents the wire JSON object ``{}`` and is
  ## distinct from ``Opt.none(SubmissionParams)`` representing ``null``
  ## (design §2.4 G34).
  let errs = detectDuplicateParamKeys(items)
  if errs.len > 0:
    return err(errs)
  var t = initOrderedTable[SubmissionParamKey, SubmissionParam]()
  for item in items:
    t[paramKey(item)] = item
  return ok(SubmissionParams(t))
