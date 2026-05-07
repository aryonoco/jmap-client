# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for ``submission_status.nim`` — RFC 8621 §7 per-recipient
## delivery vocabulary. Pins the open-world parsers (G10/G11
## raw-backing preservation), the RFC 5321 §4.2 ``SmtpReply``
## happy-path surface (G12), the ``DeliveryStatus`` composite, and the
## ``DeliveryStatusMap`` domain operations (G9) on three hand-
## constructed maps (all-delivered, mixed, all-failed) per §8.3.
##
## Out of scope: serde round-trips (Step 11), property tests
## (Step 19 groups H/I), adversarial rejection rows (Step 20 block 5).
##
## Design authority: ``docs/design/12-mail-G2-design.md`` §8.3.

{.push raises: [].}

import jmap_client/internal/types/validation
import jmap_client/internal/mail/submission_status

import ../../massertions
import ../../mfixtures

# ===========================================================================
# Section A — DeliveredState round-trip across all five arms
# ===========================================================================

block deliveredStateQueuedRoundTrip:
  ## RFC 8621 §7 ``"queued"`` → ``dsQueued``. Pins the
  ## ``strutils.parseEnum`` mapping for the in-flight state. Confusing
  ## queued for delivered would silently break "N of M delivered"
  ## diagnostics downstream.
  const raw = "queued"
  let p = parseDeliveredState(raw)
  doAssert p.state == dsQueued
  assertEq p.rawBacking, raw

block deliveredStateYesRoundTrip:
  ## RFC 8621 §7 ``"yes"`` → ``dsYes``. The success arm and the only
  ## variant ``countDelivered`` increments on, so the parser→counter
  ## chain is gated here.
  const raw = "yes"
  let p = parseDeliveredState(raw)
  doAssert p.state == dsYes
  assertEq p.rawBacking, raw

block deliveredStateNoRoundTrip:
  ## RFC 8621 §7 ``"no"`` → ``dsNo``. The failure arm gating
  ## ``anyFailed``. Distinct from ``dsUnknown`` (transport-uncertain)
  ## and ``dsOther`` (server-extension): a regression collapsing them
  ## would silently misclassify hard bounces.
  const raw = "no"
  let p = parseDeliveredState(raw)
  doAssert p.state == dsNo
  assertEq p.rawBacking, raw

block deliveredStateUnknownRoundTrip:
  ## RFC 8621 §7 ``"unknown"`` → ``dsUnknown``. Distinct token from
  ## the sentinel ``dsOther`` arm — preserving this distinction lets a
  ## consumer surface "delivery status not yet observed" without
  ## conflating it with "vendor-specific status string".
  const raw = "unknown"
  let p = parseDeliveredState(raw)
  doAssert p.state == dsUnknown
  assertEq p.rawBacking, raw

block deliveredStateOtherPreservesRawBacking:
  ## RFC 8621 §7 + G10 (open-world parser): an unrecognised token
  ## falls through to ``dsOther`` with the original byte sequence
  ## preserved on ``rawBacking`` — NOT a ``$`` round-trip, since the
  ## ``dsOther`` arm has no backing string. Token ``"deferred"`` is a
  ## Postfix soft-bounce idiom not RFC-defined; losing it on the wire
  ## would silently swallow real-world MTA diagnostics.
  const raw = "deferred"
  let p = parseDeliveredState(raw)
  doAssert p.state == dsOther
  assertEq p.rawBacking, raw

# ===========================================================================
# Section B — DisplayedState round-trip across all three arms
# ===========================================================================

block displayedStateYesRoundTrip:
  ## RFC 8621 §7 MDN ``"yes"`` → ``dpYes``. Symmetric with Section A;
  ## pins the ``parseDisplayedState`` mapping for the only
  ## affirmatively-displayed arm.
  const raw = "yes"
  let p = parseDisplayedState(raw)
  doAssert p.state == dpYes
  assertEq p.rawBacking, raw

block displayedStateUnknownRoundTrip:
  ## RFC 8621 §7 MDN ``"unknown"`` → ``dpUnknown``. The default arm
  ## when no MDN has been observed.
  const raw = "unknown"
  let p = parseDisplayedState(raw)
  doAssert p.state == dpUnknown
  assertEq p.rawBacking, raw

block displayedStateOtherPreservesRawBacking:
  ## G11 mirror of block 5: the open-world parser falls through to
  ## ``dpOther`` with raw preserved. Token ``"x-truncated"`` uses the
  ## RFC 6648 reserved-experimental ``x-`` prefix, so future MDN
  ## extensions cannot collide with this token — the test stays stable
  ## across future RFC additions.
  const raw = "x-truncated"
  let p = parseDisplayedState(raw)
  doAssert p.state == dpOther
  assertEq p.rawBacking, raw

# ===========================================================================
# Section C — SmtpReply happy-path Reply-line surface (G12)
# ===========================================================================

block smtpReplyHappy200:
  ## RFC 5321 §4.2 success Reply-line: 3-digit code (2xx), SP, free
  ## textstring. Round-trip through ``$`` (borrowed via
  ## ``defineStringDistinctOps``) must be byte-equal — the parser
  ## validates without rewriting.
  const raw = "250 OK"
  let res = parseSmtpReply(raw)
  assertOk res
  assertEq res.get().raw, raw

block smtpReplyHappy550:
  ## RFC 5321 §4.2 permanent-failure Reply-line. Pins that the parser
  ## does NOT gate acceptance on the success class — a 5xx Reply is
  ## structurally well-formed and ``parseSmtpReply`` must accept it.
  ## Caller policy decides what to do with a failure code.
  const raw = "550 mailbox unavailable"
  let res = parseSmtpReply(raw)
  assertOk res
  assertEq res.get().raw, raw

block smtpReplyMultilineHappy:
  ## RFC 5321 §4.2.1 multi-line continuation: each non-final line
  ## uses ``'-'`` between the Reply-code and the textstring; the
  ## final line uses SP. Both lines MUST share the 3-digit
  ## Reply-code. The CRLF terminator is normalised internally but
  ## preserved on the wire by the round-trip — the parser does not
  ## rewrite line endings.
  const raw = "250-first\r\n250 final"
  let res = parseSmtpReply(raw)
  assertOk res
  assertEq res.get().raw, raw

block smtpReplyEnhancedCodeHappy:
  ## RFC 3463 §2 triple on the final line. ``ParsedSmtpReply.enhanced``
  ## carries the structured triple; ``raw`` preserves ingress bytes.
  const raw = "250 2.1.5 Destination address valid"
  let res = parseSmtpReply(raw)
  assertOk res
  let p = res.get()
  doAssert p.replyCode == ReplyCode(250'u16)
  doAssert p.enhanced.isSome
  let e = p.enhanced.unsafeGet()
  doAssert e.klass == sccSuccess
  assertEq uint16(e.subject), 1'u16
  assertEq uint16(e.detail), 5'u16
  assertEq p.raw, raw

block renderCanonicalReplyIsIdempotent:
  ## Canonical LF input must render back byte-identical (H24).
  const raw = "250 OK"
  let p = parseSmtpReply(raw).get()
  assertEq renderSmtpReply(p), raw

block renderCrlfInputCanonicalisesToLf:
  ## Non-canonical CRLF input: ``raw`` preserves ingress bytes; the
  ## canonical renderer emits LF terminators only (H24, sole documented
  ## normalisation).
  const raw = "250-first\r\n250 final"
  let p = parseSmtpReply(raw).get()
  assertEq p.raw, raw
  assertEq renderSmtpReply(p), "250-first\n250 final"

# ===========================================================================
# Section D — DeliveryStatus composite construction
# ===========================================================================

block deliveryStatusComposite:
  ## All three sub-fields preserved structurally through the
  ## ``makeDeliveryStatus`` fixture. Passes each field explicitly (no
  ## defaulting): a regression that drops or rewrites any of the three
  ## on construction would surface here, not slip through under a
  ## default value silently agreeing with the assertion.
  let reply = makeSmtpReply("250 OK")
  let delivered = parseDeliveredState("yes")
  let displayed = parseDisplayedState("yes")
  let s = makeDeliveryStatus(reply, delivered, displayed)
  assertEq s.smtpReply.raw, "250 OK"
  doAssert s.delivered.state == dsYes
  assertEq s.delivered.rawBacking, "yes"
  doAssert s.displayed.state == dpYes
  assertEq s.displayed.rawBacking, "yes"

# ===========================================================================
# Section E — DeliveryStatusMap domain operations (G9)
# ===========================================================================

block deliveryStatusMapCountDelivered:
  ## ``countDelivered`` counts entries with
  ## ``delivered.state == dsYes``. All-yes map: count == 3. Mixed map
  ## (yes/no/queued): count == 1 — load-bearing, since it pins that
  ## ``dsQueued`` does NOT increment the counter. A regression
  ## treating in-flight as delivered would silently break "N of M
  ## delivered" diagnostics.
  let alice = makeRFC5321Mailbox("alice@example.com")
  let bob = makeRFC5321Mailbox("bob@example.com")
  let carol = makeRFC5321Mailbox("carol@example.com")
  let dYes = makeDeliveryStatus(delivered = parseDeliveredState("yes"))
  let dNo = makeDeliveryStatus(delivered = parseDeliveredState("no"))
  let dQueued = makeDeliveryStatus(delivered = parseDeliveredState("queued"))

  let allYes = makeDeliveryStatusMap(@[(alice, dYes), (bob, dYes), (carol, dYes)])
  assertEq allYes.countDelivered, 3

  let mixed = makeDeliveryStatusMap(@[(alice, dYes), (bob, dNo), (carol, dQueued)])
  assertEq mixed.countDelivered, 1

block deliveryStatusMapAnyFailedFalseWhenAllDelivered:
  ## ``anyFailed`` short-circuits on ``delivered.state == dsNo``. An
  ## all-yes map MUST report ``not anyFailed`` — a regression treating
  ## ``dsQueued`` or ``dsUnknown`` as failure would surface here.
  let alice = makeRFC5321Mailbox("alice@example.com")
  let bob = makeRFC5321Mailbox("bob@example.com")
  let carol = makeRFC5321Mailbox("carol@example.com")
  let dYes = makeDeliveryStatus(delivered = parseDeliveredState("yes"))

  let allYes = makeDeliveryStatusMap(@[(alice, dYes), (bob, dYes), (carol, dYes)])
  doAssert not anyFailed(allYes)

block deliveryStatusMapAnyFailedTrueWhenOneFailed:
  ## All-no map: ``anyFailed == true`` AND ``countDelivered == 0``.
  ## The coupled ``countDelivered`` assertion pins that the all-failed
  ## map isn't accidentally counting failures as deliveries — a
  ## conflated implementation that swapped ``dsYes``/``dsNo`` would
  ## fail here on the count assertion, not on the boolean.
  let alice = makeRFC5321Mailbox("alice@example.com")
  let bob = makeRFC5321Mailbox("bob@example.com")
  let carol = makeRFC5321Mailbox("carol@example.com")
  let dNo = makeDeliveryStatus(delivered = parseDeliveredState("no"))

  let allNo = makeDeliveryStatusMap(@[(alice, dNo), (bob, dNo), (carol, dNo)])
  doAssert anyFailed(allNo)
  assertEq allNo.countDelivered, 0
