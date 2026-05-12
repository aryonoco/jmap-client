# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the RFC 5321 atom parsers shared by the G1 submission
## algebra: ``parseRFC5321Mailbox`` / ``parseRFC5321MailboxFromServer``
## (submission_mailbox.nim), ``parseRFC5321Keyword`` (case-insensitive
## equality per §4.1.1.1), and ``parseOrcptAddrType`` (byte-equal, per
## RFC 3461 §4.2). The last two share the esmtp-keyword grammar but
## differ in equality semantics — the G6 contract pins that the
## distinction is nominal at the type level, not collapsed to a shared
## ``==``.
##
## Coverage strategy: six representative cells of the strict-parser
## conceptual 4 × 4 grid (local-part shape × domain-form shape), two
## strict/lenient divergence blocks, and two G6 equality pins. Property
## group A (Step 19) exhausts the remaining cells and off-boundary
## failure cases.
##
## Design authority: ``docs/design/12-mail-G2-design.md`` §8.3 (mandated
## block names); RFC 5321 §4.1.2, §4.1.3, §4.1.1.1; RFC 3461 §4.2.

{.push raises: [].}

import jmap_client/internal/types/validation
import jmap_client/internal/mail/submission_atoms
import jmap_client/internal/mail/submission_mailbox

import ../../massertions
import ../../mtestblock

# ===========================================================================
# Section A — Dot-string local-part × four domain forms
# ===========================================================================

testCase mailboxDotStringPlainDomain:
  ## Cell (Dot-string × Domain): the canonical well-formed Mailbox. Pins
  ## byte-level round-trip through ``$`` — the distinct wrapper must not
  ## rewrite or normalise on construction.
  const raw = "user@example.com"
  let res = parseRFC5321Mailbox(raw)
  assertOk res
  assertEq $res.get(), raw

testCase mailboxDotStringIPv4Literal:
  ## Cell (Dot-string × IPv4-address-literal). Negative boundary: an
  ## octet value above the 0..255 range pins that ``parseSnum`` enforces
  ## the decoded-value bound, not merely the lexical ``1*3DIGIT`` shape.
  ## The rejection must surface as ``mvAddressLiteralBadIPv4``, not a
  ## generic domain-label failure.
  const raw = "user@[192.0.2.1]"
  let res = parseRFC5321Mailbox(raw)
  assertOk res
  assertEq $res.get(), raw

  const bad = "user@[999.0.2.1]"
  assertErrFields parseRFC5321Mailbox(bad),
    "RFC5321Mailbox", "address-literal has invalid IPv4 form", bad

testCase mailboxDotStringIPv6Literal:
  ## Cell (Dot-string × IPv6-address-literal). Negative boundary: two
  ## ``"::"`` compressions in the body. ``classifyIPv6`` splits on
  ## ``"::"`` and rejects when ``compParts.len > 2`` — removing that
  ## guard would silently accept multi-compressed forms (disallowed by
  ## RFC 4291 §2.2).
  const raw = "user@[IPv6:2001:db8::1]"
  let res = parseRFC5321Mailbox(raw)
  assertOk res
  assertEq $res.get(), raw

  const bad = "user@[IPv6:2001::db8::1]"
  assertErrFields parseRFC5321Mailbox(bad),
    "RFC5321Mailbox", "address-literal has invalid IPv6 form", bad

testCase mailboxDotStringGeneralLiteral:
  ## Cell (Dot-string × General-address-literal). Pins that a
  ## well-formed Standardized-tag (``X-NewTag``) + non-empty dcontent
  ## succeeds. Negative boundary: a leading hyphen on the tag violates
  ## RFC 5321 §4.1.2 ``Let-dig`` at the label boundary. The rejection
  ## routes through ``checkGeneralLiteral`` which REPROJECTS the
  ## ``mvDomainBadLabel`` to ``mvAddressLiteralBadGeneral`` — without
  ## that reprojection, the tag error would surface as if it were a
  ## domain-name label failure, which is semantically wrong.
  const raw = "user@[X-NewTag:private-body-content]"
  let res = parseRFC5321Mailbox(raw)
  assertOk res
  assertEq $res.get(), raw

  const bad = "user@[-BadTag:content]"
  assertErrFields parseRFC5321Mailbox(bad),
    "RFC5321Mailbox", "address-literal has invalid general form", bad

# ===========================================================================
# Section B — Quoted-string local-part × two domain forms
# ===========================================================================

testCase mailboxQuotedPlainDomain:
  ## Cell (Quoted-string × Domain). Positive: SP and ``.`` inside
  ## qtextSMTP are legal. Negative boundary pins the error-priority
  ## ordering: ``detectMailboxNoControlChars`` runs BEFORE
  ## ``checkQuotedString`` in ``detectStrictMailbox``, so a control
  ## char inside the quoted body surfaces as the top-level CTL message,
  ## NOT the quoted-string-specific variant. Reordering the detectors
  ## would break this pin.
  const raw = "\"Joe Q. Public\"@example.com"
  let res = parseRFC5321Mailbox(raw)
  assertOk res
  assertEq $res.get(), raw

  const bad = "\"Joe\x01Public\"@example.com"
  assertErrFields parseRFC5321Mailbox(bad),
    "RFC5321Mailbox", "contains control characters", bad

testCase mailboxQuotedIPv6Literal:
  ## Cell (Quoted-string × IPv6-address-literal). The domain path reuses
  ## ``checkAddressLiteral`` verified in Block 3; this block's value is
  ## pinning that the ``'@'`` inside the quoted part does NOT split
  ## prematurely — ``findSplitAt`` walks past the closing DQUOTE via
  ## ``findClosingQuote`` before searching for ``'@'``.
  const raw = "\"Joe Q. Public\"@[IPv6:2001:db8::1]"
  let res = parseRFC5321Mailbox(raw)
  assertOk res
  assertEq $res.get(), raw

# ===========================================================================
# Section C — Strict / lenient parser divergence (Postel's law)
# ===========================================================================

testCase mailboxStrictLenientSupersetOnPlainDomain:
  ## Both parsers accept a well-formed input; pins that the lenient
  ## parser does NOT rewrite or canonicalise. The two ``$`` round-trips
  ## must be byte-equal to the original ``raw`` — a lenient parser that
  ## normalises case or strips whitespace would break this assertion
  ## and silently corrupt server-side data on its way back to the wire.
  const raw = "admin@example.com"
  let strict = parseRFC5321Mailbox(raw)
  let lenient = parseRFC5321MailboxFromServer(raw)
  assertOk strict
  assertOk lenient
  assertEq $strict.get(), raw
  assertEq $lenient.get(), raw

testCase mailboxStrictLenientSupersetOnMalformedLocalPart:
  ## An interior space in an unquoted local-part isolates the
  ## strict/lenient divergence. Strict rejects at
  ## ``mvLocalPartBadDotString`` because ``' '`` is not in
  ## ``AtextChars``. Lenient accepts: ``detectLenientToken`` passes
  ## (space is 0x20, not a control character; 23 octets ≤ 255) and
  ## ``'@'`` is present. Without this divergence, a "simplify lenient
  ## to reuse strict" refactor would silently collapse Postel's-law
  ## interop for non-conformant servers. Step 7 is the regression
  ## pin that forces such a refactor to fail here.
  const raw = "bad address@example.com"
  assertErrFields parseRFC5321Mailbox(raw),
    "RFC5321Mailbox", "local-part is not a valid dot-string", raw

  let lenient = parseRFC5321MailboxFromServer(raw)
  assertOk lenient
  assertEq $lenient.get(), raw

# ===========================================================================
# Section D — RFC5321Keyword case-insensitive equality (G6 half 1)
# ===========================================================================

testCase rfc5321KeywordCaseInsensitive:
  ## RFC 5321 §4.1.1.1 mandates case-insensitive recognition of
  ## esmtp-keyword values. The type preserves server casing in ``$``
  ## for diagnostic round-trip but case-folds on equality AND hash —
  ## the latter is required so ``Table[RFC5321Keyword, _]`` lookups
  ## agree with ``==``. A regression that removed the case-fold from
  ## ``hash`` but kept it on ``==`` would silently corrupt
  ## identity-table lookups for extension keywords.
  let kwUpper = parseRFC5321Keyword("X-FOO").get()
  let kwLower = parseRFC5321Keyword("x-foo").get()
  let kwOther = parseRFC5321Keyword("X-BAR").get()

  doAssert kwUpper == kwLower
  assertEq $kwUpper, "X-FOO"
  assertEq $kwLower, "x-foo"
  assertEq hash(kwUpper), hash(kwLower)

  # Non-collapse — different keywords must remain distinct. Pins that
  # ``==`` isn't a constant ``true``.
  doAssert kwUpper != kwOther

# ===========================================================================
# Section E — OrcptAddrType byte-equal (G6 half 2)
# ===========================================================================

testCase orcptAddrTypeByteEqual:
  ## RFC 3461 §4.2 addr-type atom shares the esmtp-keyword grammar but
  ## is silent on case-folding. The G6 decision keeps ``OrcptAddrType``
  ## byte-equal: IANA-registered addr-types (``rfc822``, ``utf-8``,
  ## ``x400``, ``unknown``) are all lowercase, and preserving server
  ## casing with byte-equality avoids conflating registered
  ## lowercase-only values with hypothetical mixed-casing extensions.
  let rfcLower = parseOrcptAddrType("rfc822").get()
  let rfcUpper = parseOrcptAddrType("RFC822").get()
  let rfcSecond = parseOrcptAddrType("rfc822").get()

  doAssert rfcLower != rfcUpper
  doAssert rfcLower == rfcSecond
  assertEq $rfcLower, "rfc822"
  assertEq $rfcUpper, "RFC822"

  # Cross-type compile-time distinctness. ``OrcptAddrType`` and
  # ``RFC5321Keyword`` share the esmtp-keyword grammar but have
  # nominally distinct ``==`` overloads: ``defineStringDistinctOps``
  # borrows a byte-equal ``==`` from ``string`` on ``OrcptAddrType``,
  # while ``RFC5321Keyword`` installs an explicit case-insensitive
  # ``==``. Nim does NOT auto-generate a cross-type overload, so
  # ``rfcLower == kw`` cannot type-check. Adding such an overload —
  # even inadvertently — would silently merge the types' semantics.
  # ``not compiles`` is the only regression pin that would surface
  # such a mistake at compile time.
  let kw = parseRFC5321Keyword("rfc822").get()
  assertNotCompiles(rfcLower == kw)
