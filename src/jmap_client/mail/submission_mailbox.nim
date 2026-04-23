# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 5321 §4.1.2 ``Mailbox`` (``Local-part "@" ( Domain / address-literal )``)
## with §4.5.3.1.1 (local-part ≤ 64) and §4.5.3.1.2 (domain ≤ 255) length caps.
## Address-literal coverage is the full §4.1.3 grammar: IPv4, IPv6 (all four
## forms — IPv6-full, IPv6-comp, IPv6v4-full, IPv6v4-comp), and General-
## address-literal.
##
## Design authority: ``docs/design/12-mail-G1-design.md`` §2.1.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sequtils
import std/strutils

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

func findClosingQuote(raw: string): Result[Idx, MailboxViolation] =
  ## Returns the index of the closing DQUOTE matching ``raw[0]``. Skips
  ## backslash-escaped chars so ``\"`` does not terminate the scan.
  ## Position-finder only — full quoted-string validation is done later
  ## by ``checkQuotedString`` once the local-part is extracted.
  ## Precondition: ``raw[0] == '"'``.
  var i: Idx = idx(1)
  while i < raw.len:
    case raw[i.toInt]
    of '\\':
      if i + idx(1) >= raw.len:
        return err(mvLocalPartBadQuotedString)
      i += idx(2)
    of '"':
      return ok(i)
    else:
      i = i.succ
  err(mvLocalPartBadQuotedString)

func findSplitAt(raw: string): Result[int, MailboxViolation] =
  ## Returns the index of the Mailbox ``'@'`` separator. A leading
  ## quoted local-part is walked past so that ``'@'`` inside quotes
  ## doesn't split the address. ``searchStart: Idx`` lifts the
  ## non-negative precondition to the type system; ``.toNatural`` is
  ## the explicit stdlib-boundary projection.
  if raw.len == 0:
    return err(mvEmpty)
  let searchStart: Idx =
    if raw[0] == '"':
      (?findClosingQuote(raw)).succ
    else:
      idx(0)
  let atIdx = raw.find('@', start = searchStart.toNatural)
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
