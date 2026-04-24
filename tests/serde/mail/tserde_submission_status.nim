# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for the RFC 8621 §7 EmailSubmission status vocabulary:
## ``UndoStatus`` (closed-enum + client-side ``toJson``), ``DeliveryStatus``
## (three-field composite), and ``DeliveryStatusMap`` (distinct
## ``Table[RFC5321Mailbox, DeliveryStatus]``). Pins G3's closed-enum
## commitment (unknown values must ``Err``, not silently fall through) and
## G10/G11's ``rawBacking`` round-trip preservation for the two parsed-state
## types. Companion to the shipped unit-tier file ``tsubmission_status.nim``.

{.push raises: [].}

import std/json

import jmap_client/mail/serde_submission_status
import jmap_client/mail/submission_mailbox
import jmap_client/mail/submission_status
import jmap_client/serde
import jmap_client/types

import ../../massertions
import ../../mfixtures

# ============= A. UndoStatus round-trip + closed-enum gate =============

block undoStatusPendingRoundTrip:
  ## ``usPending`` ↔ ``"pending"`` symmetric round-trip. Covers the wire
  ## token both directions: ``fromJson`` recognises the backing string,
  ## ``toJson`` emits it.
  let wire = %"pending"
  let parsed = UndoStatus.fromJson(wire)
  assertOk parsed
  assertEq parsed.unsafeGet(), usPending
  assertEq usPending.toJson(), wire

block undoStatusFinalRoundTrip:
  ## ``usFinal`` ↔ ``"final"``.
  let wire = %"final"
  let parsed = UndoStatus.fromJson(wire)
  assertOk parsed
  assertEq parsed.unsafeGet(), usFinal
  assertEq usFinal.toJson(), wire

block undoStatusCanceledRoundTrip:
  ## ``usCanceled`` ↔ ``"canceled"``. Note the single-``l`` spelling per
  ## RFC 8621 §7 — a vendor extension using ``"cancelled"`` would be
  ## rejected by the closed-enum gate below.
  let wire = %"canceled"
  let parsed = UndoStatus.fromJson(wire)
  assertOk parsed
  assertEq parsed.unsafeGet(), usCanceled
  assertEq usCanceled.toJson(), wire

block undoStatusUnknownIsRejected:
  ## G3 closed-enum commitment. Unknown wire value ``"deferred"`` MUST
  ## surface as ``svkEnumNotRecognised`` — NOT silently fall through to
  ## an ``usOther`` catch-all. Quiet-fallback here would break the
  ## phantom-type contract (``EmailSubmission[S: static UndoStatus]``
  ## requires ``S`` to be one of the three RFC-blessed variants at
  ## compile time).
  let wire = %"deferred"
  let res = UndoStatus.fromJson(wire)
  assertSvKind res, svkEnumNotRecognised
  assertSvPath res, ""

# ============= B. DeliveryStatus composite parse + rawBacking =============

block deliveryStatusRoundTrip:
  ## G10 / G11: the two ``Parsed*`` subfields must preserve ``rawBacking``
  ## byte-for-byte on both RFC-canonical and unknown values. This block
  ## exercises both halves in one shot: an unknown ``"deferred"`` delivered
  ## state and an unknown ``"partial"`` displayed state fall through to
  ## their respective ``*Other`` catch-alls with the original wire tokens
  ## retained; a canonical ``"yes"`` / ``"yes"`` pair routes to ``dsYes`` /
  ## ``dpYes``. The SmtpReply half is validated via the L1 smart
  ## constructor — ``"250 Queued"`` is a well-formed RFC 5321 §4.2 reply.
  let unknownWire =
    %*{"smtpReply": "250 Queued", "delivered": "deferred", "displayed": "partial"}
  let parsedUnknown = DeliveryStatus.fromJson(unknownWire)
  assertOk parsedUnknown
  let dsUnknown = parsedUnknown.unsafeGet()
  assertEq dsUnknown.smtpReply.raw, "250 Queued"
  assertEq dsUnknown.delivered.state, dsOther
  assertEq dsUnknown.delivered.rawBacking, "deferred"
  assertEq dsUnknown.displayed.state, dpOther
  assertEq dsUnknown.displayed.rawBacking, "partial"

  let canonicalWire = %*{"smtpReply": "250 OK", "delivered": "yes", "displayed": "yes"}
  let parsedCanonical = DeliveryStatus.fromJson(canonicalWire)
  assertOk parsedCanonical
  let dsCanonical = parsedCanonical.unsafeGet()
  assertEq dsCanonical.smtpReply.raw, "250 OK"
  assertEq dsCanonical.delivered.state, dsYes
  assertEq dsCanonical.delivered.rawBacking, "yes"
  assertEq dsCanonical.displayed.state, dpYes
  assertEq dsCanonical.displayed.rawBacking, "yes"

# ============= C. DeliveryStatusMap recipient-keyed entries =============

block deliveryStatusMapRoundTripPreservesOrder:
  ## G9: every ``(mailbox, status)`` pair in the wire object must appear
  ## in the parsed map exactly once under byte-equal ``RFC5321Mailbox``
  ## key semantics. ``assertDeliveryStatusMapEq`` compares via the
  ## distinct table's borrowed ``==`` — structural key-set equality, not
  ## positional iteration order (the underlying ``Table`` is hash-based).
  ## An empty object parses to an empty map (RFC does not mandate ≥1
  ## recipient; server progress may report zero).
  let wire = %*{
    "alice@example.com":
      {"smtpReply": "250 OK", "delivered": "yes", "displayed": "unknown"},
    "bob@example.org": {
      "smtpReply": "550 Mailbox unavailable", "delivered": "no", "displayed": "unknown"
    },
    "carol@example.net":
      {"smtpReply": "250 Queued", "delivered": "queued", "displayed": "yes"},
  }
  let parsed = DeliveryStatusMap.fromJson(wire)
  assertOk parsed

  let alice = parseRFC5321MailboxFromServer("alice@example.com").unsafeGet()
  let bob = parseRFC5321MailboxFromServer("bob@example.org").unsafeGet()
  let carol = parseRFC5321MailboxFromServer("carol@example.net").unsafeGet()
  let expected = makeDeliveryStatusMap(
    @[
      (
        alice,
        makeDeliveryStatus(
          smtpReply = makeSmtpReply("250 OK"),
          delivered = parseDeliveredState("yes"),
          displayed = parseDisplayedState("unknown"),
        ),
      ),
      (
        bob,
        makeDeliveryStatus(
          smtpReply = makeSmtpReply("550 Mailbox unavailable"),
          delivered = parseDeliveredState("no"),
          displayed = parseDisplayedState("unknown"),
        ),
      ),
      (
        carol,
        makeDeliveryStatus(
          smtpReply = makeSmtpReply("250 Queued"),
          delivered = parseDeliveredState("queued"),
          displayed = parseDisplayedState("yes"),
        ),
      ),
    ]
  )
  assertDeliveryStatusMapEq parsed.unsafeGet(), expected

  let emptyWire = %*{}
  let parsedEmpty = DeliveryStatusMap.fromJson(emptyWire)
  assertOk parsedEmpty
  let expectedEmpty = makeDeliveryStatusMap(@[])
  assertDeliveryStatusMapEq parsedEmpty.unsafeGet(), expectedEmpty

# ============= D. DeliveryStatus toJson CRLF→LF canonicalisation =============

block deliveryStatusToJsonCanonicalisesSmtpReplyLineEndings:
  ## H24 canonicalisation contract: ``ParsedSmtpReply.raw`` preserves
  ## ingress bytes (including CRLF); ``toJson`` emits the canonical LF
  ## form via ``renderSmtpReply``. Pins the sole documented
  ## normalisation on the serde boundary.
  let wire =
    %*{"smtpReply": "250-first\r\n250 final", "delivered": "yes", "displayed": "yes"}
  let parsed = DeliveryStatus.fromJson(wire)
  assertOk parsed
  let ds = parsed.unsafeGet()
  assertEq ds.smtpReply.raw, "250-first\r\n250 final"
  let emitted = ds.toJson()
  assertEq emitted["smtpReply"].getStr(), "250-first\n250 final"
