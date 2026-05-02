# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for the EmailSubmission entity family (RFC 8621 §7). Covers:
##   * ``AnyEmailSubmission`` fromJson dispatch across the three
##     ``UndoStatus`` phantom variants (G2).
##   * ``EmailSubmissionBlueprint`` toJson-only client → server contract
##     including the ``Opt.none(Envelope)`` passthrough (G22/G26, G27).
##   * ``EmailSubmissionFilterCondition`` toJson-only sparse emission and
##     the structural ``NonEmptyIdSeq`` empty-list rejection (G18, G37).
##   * ``EmailSubmissionComparator`` toJson — the load-bearing wire-token
##     pin: RFC sort token ``"sentAt"`` is emitted, NEVER the entity-field
##     name ``sendAt`` (G19).
##   * ``IdOrCreationRef`` toJson: direct → bare id string, creation →
##     ``"#" & creationId`` per RFC 8620 §5.3 / RFC 8621 §7.5 ¶3 (G35).
##   * ``SetResponse[EmailSubmissionCreatedItem]`` fromJson envelope —
##     fromJson-only because ``EmailSubmissionCreatedItem`` carries no
##     ``toJson`` counterpart (G39).

{.push raises: [].}

import std/json
import std/tables

import jmap_client/mail/email_submission
import jmap_client/mail/serde_email_submission
import jmap_client/mail/submission_envelope
import jmap_client/mail/serde_submission_envelope
import jmap_client/mail/submission_mailbox
import jmap_client/mail/submission_status
import jmap_client/methods
import jmap_client/errors
import jmap_client/identifiers
import jmap_client/primitives
import jmap_client/serde
import jmap_client/types

import ../../massertions
import ../../mfixtures

# ============= A. AnyEmailSubmission fromJson dispatch ======================

block anyEmailSubmissionPendingRoundTrip:
  ## Wire ``"undoStatus": "pending"`` dispatches to the ``usPending``
  ## branch; shared fields survive ``fromJsonShared[usPending]``; absent
  ## ``envelope`` collapses to ``Opt.none`` via ``parseEnvelopeField``
  ## (G27, RFC 8621 §7 ¶2 ``Envelope|null``).
  let wire = %*{
    "id": "es1",
    "identityId": "iden1",
    "emailId": "email1",
    "threadId": "thr1",
    "undoStatus": "pending",
    "sendAt": "2026-01-15T09:00:00Z",
    "dsnBlobIds": [],
    "mdnBlobIds": [],
  }
  let res = AnyEmailSubmission.fromJson(wire)
  assertOk res
  let parsed = res.unsafeGet()
  assertEq parsed.state, usPending
  let pendingOpt = parsed.asPending()
  assertSome pendingOpt
  let sub = pendingOpt.get()
  assertEq sub.id, makeId("es1")
  assertEq sub.identityId, makeId("iden1")
  assertEq sub.emailId, makeId("email1")
  assertEq sub.threadId, makeId("thr1")
  assertEq sub.sendAt, parseUtcDate("2026-01-15T09:00:00Z").get()
  assertNone sub.envelope
  assertNone sub.deliveryStatus

block anyEmailSubmissionFinalRoundTrip:
  ## Wire ``"undoStatus": "final"`` with a populated ``envelope`` field
  ## dispatches to the ``usFinal`` branch. Cross-cuts the envelope
  ## composite — the standalone envelope serde round-trip is pinned in
  ## tserde_submission_envelope.nim; here we only verify it survives
  ## the dispatch boundary. ``makeEnvelope()`` (default single
  ## recipient) suffices — the goal is presence, not coverage.
  let envValue = makeEnvelope()
  let wire = %*{
    "id": "esFinal",
    "identityId": "idenFinal",
    "emailId": "emailFinal",
    "threadId": "thrFinal",
    "undoStatus": "final",
    "sendAt": "2026-02-01T10:15:00Z",
    "envelope": envValue.toJson(),
    "dsnBlobIds": [],
    "mdnBlobIds": [],
  }
  let res = AnyEmailSubmission.fromJson(wire)
  assertOk res
  let parsed = res.unsafeGet()
  assertEq parsed.state, usFinal
  let finalOpt = parsed.asFinal()
  assertSome finalOpt
  let sub = finalOpt.get()
  assertEq sub.id, makeId("esFinal")
  assertSome sub.envelope
  doAssert sub.envelope.get() == envValue, "envelope did not survive dispatch"

block anyEmailSubmissionCanceledRoundTrip:
  ## Wire ``"undoStatus": "canceled"`` with a populated ``deliveryStatus``
  ## recipient map dispatches to the ``usCanceled`` branch and preserves
  ## the per-recipient composite (RFC 8621 §7 ¶8
  ## ``String[DeliveryStatus]|null``).
  let wire = %*{
    "id": "esCan",
    "identityId": "idenCan",
    "emailId": "emailCan",
    "threadId": "thrCan",
    "undoStatus": "canceled",
    "sendAt": "2026-03-10T08:00:00Z",
    "deliveryStatus": {
      "alice@example.com":
        {"smtpReply": "250 OK", "delivered": "yes", "displayed": "unknown"}
    },
    "dsnBlobIds": [],
    "mdnBlobIds": [],
  }
  let res = AnyEmailSubmission.fromJson(wire)
  assertOk res
  let parsed = res.unsafeGet()
  assertEq parsed.state, usCanceled
  let canceledOpt = parsed.asCanceled()
  assertSome canceledOpt
  let sub = canceledOpt.get()
  assertEq sub.id, makeId("esCan")
  assertSome sub.deliveryStatus
  let alice = parseRFC5321MailboxFromServer("alice@example.com").unsafeGet()
  let expectedMap = makeDeliveryStatusMap(
    @[
      (
        alice,
        makeDeliveryStatus(
          smtpReply = makeSmtpReply("250 OK"),
          delivered = parseDeliveredState("yes"),
          displayed = parseDisplayedState("unknown"),
        ),
      )
    ]
  )
  assertDeliveryStatusMapEq sub.deliveryStatus.get(), expectedMap

# ============= B. EmailSubmissionBlueprint toJson-only ======================

block blueprintToJsonOnlyNoFromJson:
  ## G22/G26: Blueprint is the client → server creation model; serde
  ## surface is toJson only. Exercises the coverage-dense full fixture so
  ## every settable field reaches the wire in one pass. Attempting
  ## ``EmailSubmissionBlueprint.fromJson(...)`` is deliberately absent —
  ## the contract-check grep (design-doc §8.14) verifies no such symbol
  ## exists in ``serde_email_submission.nim``.
  let bp = makeFullEmailSubmissionBlueprint()
  let node = bp.toJson()
  doAssert node.kind == JObject
  assertLen node, 3
  assertJsonFieldEq node, "identityId", %($bp.identityId)
  assertJsonFieldEq node, "emailId", %($bp.emailId)
  let envNode = node{"envelope"}
  doAssert envNode != nil and envNode.kind == JObject,
    "envelope must emit as a JObject composite"

block blueprintOptNoneEnvelopePassesThrough:
  ## G27 (RFC 8621 §7.5 ¶4): when the client omits the envelope, the
  ## server synthesises it from the referenced Email's headers.
  ## ``Opt.none(Envelope)`` on the value side MUST elide the key entirely
  ## on the wire — emitting ``null`` would force the server into a
  ## different code path than omission.
  let bp = makeEmailSubmissionBlueprint(
    identityId = makeId("idenP"),
    emailId = makeId("emailP"),
    envelope = Opt.none(Envelope),
  )
  let node = bp.toJson()
  assertLen node, 2
  assertJsonFieldEq node, "identityId", %"idenP"
  assertJsonFieldEq node, "emailId", %"emailP"
  assertJsonKeyAbsent node, "envelope"

# ============= C. EmailSubmissionFilterCondition toJson-only ================

block filterConditionAllFieldsPopulated:
  ## G18: all six fields set. Sparse-emission invariant stays compatible
  ## with the fully-populated case — the emitted object has exactly one
  ## key per non-``Opt.none`` field and no stray null entries.
  let ids1 = parseNonEmptyIdSeq(@[makeId("iden1"), makeId("iden2")]).unsafeGet()
  let ids2 = parseNonEmptyIdSeq(@[makeId("email1")]).unsafeGet()
  let ids3 = parseNonEmptyIdSeq(@[makeId("thr1")]).unsafeGet()
  let fc = EmailSubmissionFilterCondition(
    identityIds: Opt.some(ids1),
    emailIds: Opt.some(ids2),
    threadIds: Opt.some(ids3),
    undoStatus: Opt.some(usPending),
    before: Opt.some(parseUtcDate("2026-04-01T00:00:00Z").get()),
    after: Opt.some(parseUtcDate("2026-01-01T00:00:00Z").get()),
  )
  let node = fc.toJson()
  assertLen node, 6
  let identArr = node{"identityIds"}
  doAssert identArr != nil and identArr.kind == JArray
  assertEq identArr.len, 2
  doAssert node{"emailIds"}.kind == JArray
  doAssert node{"threadIds"}.kind == JArray
  assertJsonFieldEq node, "undoStatus", %"pending"
  assertJsonFieldEq node, "before", %"2026-04-01T00:00:00Z"
  assertJsonFieldEq node, "after", %"2026-01-01T00:00:00Z"

block filterConditionOnlyUndoStatus:
  ## G18: five of six fields ``Opt.none`` emit nothing; the single
  ## populated ``undoStatus`` is the only key on the wire. Mirrors the
  ## ``MailboxFilterCondition`` sparse-emission pattern in
  ## tserde_mail_filters.nim.
  let fc = EmailSubmissionFilterCondition(
    identityIds: Opt.none(NonEmptyIdSeq),
    emailIds: Opt.none(NonEmptyIdSeq),
    threadIds: Opt.none(NonEmptyIdSeq),
    undoStatus: Opt.some(usFinal),
    before: Opt.none(UTCDate),
    after: Opt.none(UTCDate),
  )
  let node = fc.toJson()
  assertLen node, 1
  assertJsonFieldEq node, "undoStatus", %"final"
  assertJsonKeyAbsent node, "identityIds"
  assertJsonKeyAbsent node, "emailIds"
  assertJsonKeyAbsent node, "threadIds"
  assertJsonKeyAbsent node, "before"
  assertJsonKeyAbsent node, "after"

block filterConditionRejectsEmptyIdSeq:
  ## G37: the structural gate is at construction. ``NonEmptyIdSeq``
  ## rejects an empty list via ``parseNonEmptyIdSeq``, so the only path
  ## an empty list could reach ``toJson`` is a ``cast[NonEmptyIdSeq]``
  ## bypass — excluded from G2 per design-doc §8.14. The RFC permits
  ## empty filter arrays on the wire, but an empty list matches nothing
  ## server-side and is almost certainly a caller bug; the client side
  ## enforces strictness without breaking spec compliance.
  let res = parseNonEmptyIdSeq(@[])
  assertErrFields res, "NonEmptyIdSeq", "must not be empty", ""

# ============= D. EmailSubmissionComparator toJson ==========================

block comparatorSentAtTokenNotSendAt:
  ## G19 (load-bearing): the RFC 8621 §7.3 sort-property wire token is
  ## ``"sentAt"`` but the entity field carrying the analogous value is
  ## ``sendAt``. ``toJson`` emits ``rawProperty`` verbatim — any
  ## regression that accidentally stringifies the field name instead
  ## would be undetectable at CI and only surface when a live server
  ## rejects the ``/query`` sort clause.
  let c = parseEmailSubmissionComparator("sentAt").unsafeGet()
  assertEq c.property, esspSentAt
  assertEq c.rawProperty, "sentAt"
  let node = c.toJson()
  assertJsonFieldEq node, "property", %"sentAt"
  assertJsonKeyAbsent node, "sendAt"
  assertJsonFieldEq node, "isAscending", %true
  assertJsonKeyAbsent node, "collation"

block comparatorAscendingByEmailId:
  ## Happy path: ``"emailId"`` is one of the three RFC-defined wire
  ## tokens; it resolves to the ``esspEmailId`` enum variant. Default
  ## ``isAscending`` is ``true`` per RFC 8620 §5.5; ``collation``
  ## defaults to ``Opt.none`` (server's default per RFC 4790 registry)
  ## and stays sparse on the wire.
  let c = parseEmailSubmissionComparator("emailId").unsafeGet()
  assertEq c.property, esspEmailId
  assertEq c.rawProperty, "emailId"
  let node = c.toJson()
  assertLen node, 2
  assertJsonFieldEq node, "property", %"emailId"
  assertJsonFieldEq node, "isAscending", %true
  assertJsonKeyAbsent node, "collation"

# ============= E. IdOrCreationRef toJson ====================================

block idOrCreationRefDirectWire:
  ## G35 / RFC 8620 §5.3: a direct reference to an existing
  ## EmailSubmission serialises as the bare id string (no ``#`` prefix).
  ## Wire shape is ``JString`` — complements the Step 10 unit-layer
  ## ``assertNotCompiles`` probe that pins type-level distinctness from
  ## ``Referencable[T]``.
  let r = makeIdOrCreationRefDirect(makeId("sub1"))
  assertIdOrCreationRefWire r, "sub1"

block idOrCreationRefCreationWire:
  ## G35 / RFC 8620 §5.3: a forward-reference to a sibling create
  ## operation serialises as ``"#"`` concatenated with the creation id.
  ## The ``#`` prefix is a wire concern added at ``toJson`` time, NOT
  ## stored on the ``CreationId``.
  let r = makeIdOrCreationRefCreation(makeCreationId("k0"))
  assertIdOrCreationRefWire r, "#k0"

# ============= F. SetResponse[EmailSubmissionCreatedItem] envelope ==========

block emailSubmissionSetResponseEntityRoundTrip:
  ## G39: full wire envelope for ``EmailSubmission/set``. Mirrors
  ## ``setResponseEmailEnvelopeShape`` in tserde_email_set_response.nim:30.
  ##
  ## This block is fromJson-only because ``EmailSubmissionCreatedItem``
  ## carries no ``toJson`` counterpart — by contrast ``EmailCreatedItem``
  ## DOES, which is why the Email/set tests can do symmetric round-trips
  ## (``setResponseEmailRoundTrip`` at :157). The generic
  ## ``SetResponse[T].toJson`` body calls ``item.toJson()`` via
  ## ``mixin``; for T=EmailSubmissionCreatedItem that resolution fails at
  ## compile time. The contract-check grep (design-doc §8.14 / Step 22)
  ## pins this asymmetry explicitly.
  ##
  ## Server-sent entity subset per RFC 8621 §7.5 ¶2: ``id``, ``threadId``,
  ## ``sendAt``. ``undoStatus`` is deliberately absent on
  ## ``EmailSubmissionCreatedItem`` — delay-send-disabled servers may
  ## flip it immediately, so callers read live state via ``/get``.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s0",
    "newState": "s1",
    "created":
      {"k0": {"id": "sub1", "threadId": "thr1", "sendAt": "2026-04-01T12:00:00Z"}},
    "notCreated": {"k1": {"type": "invalidProperties"}},
    "updated": {"sub2": nil},
    "notUpdated": {"sub3": {"type": "serverFail"}},
    "destroyed": ["sub4"],
    "notDestroyed": {"sub5": {"type": "serverFail"}},
  }
  let res = SetResponse[EmailSubmissionCreatedItem].fromJson(node)
  assertOk res
  let r = res.get()
  assertEq r.accountId, makeAccountId("acct1")
  assertSomeEq r.oldState, makeState("s0")
  assertEq r.newState, makeState("s1")

  # createResults merges wire created + notCreated (RFC 8620 §5.3 per
  # Decision L3-C): one Ok via EmailSubmissionCreatedItem.fromJson, one
  # Err carrying the SetError.
  assertLen r.createResults, 2
  let kOk = makeCreationId("k0")
  let kErr = makeCreationId("k1")
  doAssert kOk in r.createResults, "expected k0 merged from created"
  doAssert kErr in r.createResults, "expected k1 merged from notCreated"
  doAssert r.createResults[kOk].isOk
  doAssert r.createResults[kErr].isErr
  let okItem = r.createResults[kOk].get()
  assertEq okItem.id, makeId("sub1")
  doAssert okItem.threadId.isSome and okItem.threadId.unsafeGet == makeId("thr1")
  doAssert okItem.sendAt.isSome and
    okItem.sendAt.unsafeGet == parseUtcDate("2026-04-01T12:00:00Z").get()

  # updateResults merges wire updated + notUpdated. Null-valued updated
  # entries become ok(Opt.none(JsonNode)); notUpdated entries become
  # err(SetError).
  assertLen r.updateResults, 2
  doAssert r.updateResults[makeId("sub2")].isOk
  doAssert r.updateResults[makeId("sub3")].isErr

  # destroyResults merges wire destroyed + notDestroyed. Listed ids
  # become ok(); notDestroyed entries become err(SetError).
  assertLen r.destroyResults, 2
  doAssert r.destroyResults[makeId("sub4")].isOk
  doAssert r.destroyResults[makeId("sub5")].isErr
