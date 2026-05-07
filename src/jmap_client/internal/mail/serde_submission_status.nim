# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde for RFC 8621 §7 EmailSubmission status vocabulary: ``UndoStatus``,
## ``ParsedDeliveredState``, ``ParsedDisplayedState``, ``DeliveryStatus``
## and ``DeliveryStatusMap``.
##
## Direction of flow determines the surface:
##   * ``fromJson``-only for the two ``Parsed*`` open-world enums and for
##     ``DeliveryStatusMap`` (server → client).
##   * ``UndoStatus`` ships ``toJson`` because it appears client → server
##     inside ``EmailSubmissionFilterCondition`` (Step 12).
##   * ``DeliveryStatus`` ships ``toJson`` for the H24 canonicalisation
##     round-trip contract — CRLF/CR ingress is normalised to LF on
##     emission, with the exact ingress bytes preserved in
##     ``ParsedSmtpReply.raw``.
##
## ``parseUndoStatus`` is exported as a named helper so Step 12's
## ``AnyEmailSubmission`` dispatch can reuse the same closed-enum recognition
## that ``fromJson(UndoStatus)`` uses — without a double JString kind check.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../serialisation/serde
import ../../types
import ./submission_envelope
import ./submission_status

# =============================================================================
# UndoStatus — RFC 8621 §7 ¶7 closed lifecycle enum
# =============================================================================

func parseUndoStatus*(raw: string, path: JsonPath): Result[UndoStatus, SerdeViolation] =
  ## Resolve a wire token to the RFC-closed three-state lifecycle enum.
  ## Unknown value → ``svkEnumNotRecognised`` — this is a protocol violation,
  ## not a forwards-compatibility concern (G3).
  case raw
  of "pending":
    return ok(usPending)
  of "final":
    return ok(usFinal)
  of "canceled":
    return ok(usCanceled)
  else:
    return err(
      SerdeViolation(
        kind: svkEnumNotRecognised,
        path: path,
        enumTypeLabel: "UndoStatus",
        rawValue: raw,
      )
    )

func toJson*(s: UndoStatus): JsonNode =
  ## Emit the backing string (``"pending"`` / ``"final"`` / ``"canceled"``).
  ## Only used client → server inside ``EmailSubmissionFilterCondition``.
  return %($s)

func fromJson*(
    T: typedesc[UndoStatus], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[UndoStatus, SerdeViolation] =
  ## JString kind gate, then delegate to ``parseUndoStatus``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JString, path)
  return parseUndoStatus(node.getStr(""), path)

# =============================================================================
# ParsedDeliveredState / ParsedDisplayedState — open-world enums
# =============================================================================

func fromJson*(
    T: typedesc[ParsedDeliveredState], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[ParsedDeliveredState, SerdeViolation] =
  ## Delegate to the infallible L1 parser; unknown tokens fall through to
  ## ``dsOther`` with ``rawBacking`` preserved (G10, Postel's law).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JString, path)
  return ok(parseDeliveredState(node.getStr("")))

func fromJson*(
    T: typedesc[ParsedDisplayedState], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[ParsedDisplayedState, SerdeViolation] =
  ## Symmetric with ``ParsedDeliveredState.fromJson``; ``dpOther`` catch-all
  ## for unknown tokens (G11).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JString, path)
  return ok(parseDisplayedState(node.getStr("")))

# =============================================================================
# DeliveryStatus — three-field composite; owns the SmtpReply parse
# =============================================================================

func fromJson*(
    T: typedesc[DeliveryStatus], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[DeliveryStatus, SerdeViolation] =
  ## Three-field composite. ``smtpReply`` routes through ``parseSmtpReply``
  ## which yields a fully-decomposed ``ParsedSmtpReply``; ingress bytes
  ## are preserved in ``parsed.raw`` for diagnostic fidelity and H24
  ## canonicalisation round-trip (H23).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let smtpReplyNode = ?fieldJString(node, "smtpReply", path)
  let smtpReply =
    ?wrapInner(parseSmtpReply(smtpReplyNode.getStr("")), path / "smtpReply")
  let deliveredNode = ?fieldJString(node, "delivered", path)
  let delivered = ?ParsedDeliveredState.fromJson(deliveredNode, path / "delivered")
  let displayedNode = ?fieldJString(node, "displayed", path)
  let displayed = ?ParsedDisplayedState.fromJson(displayedNode, path / "displayed")
  ok(DeliveryStatus(smtpReply: smtpReply, delivered: delivered, displayed: displayed))

func toJson*(x: DeliveryStatus): JsonNode =
  ## Emit the canonical wire form (H24). ``smtpReply`` renders via
  ## ``renderSmtpReply`` — LF-terminated, no trailing whitespace;
  ## ingress CRLF is normalised out. ``delivered`` / ``displayed``
  ## round-trip via their preserved raw backing tokens.
  result = newJObject()
  result["smtpReply"] = %renderSmtpReply(x.smtpReply)
  result["delivered"] = %x.delivered.rawBacking
  result["displayed"] = %x.displayed.rawBacking

# =============================================================================
# DeliveryStatusMap — recipient-keyed delivery outcome table
# =============================================================================

func fromJson*(
    T: typedesc[DeliveryStatusMap], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[DeliveryStatusMap, SerdeViolation] =
  ## Parse a JSON object into ``Table[RFC5321Mailbox, DeliveryStatus]``.
  ## Keys are parsed via ``parseRFC5321MailboxFromServer`` — lenient by
  ## design (G9, Postel's law): a single malformed server-side mailbox
  ## key should not break ingestion of the rest of the response. An empty
  ## object is a valid status map — the RFC does not mandate ≥1 entry; the
  ## map is keyed by whatever recipients the server has progressed.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  var tbl = initTable[RFC5321Mailbox, DeliveryStatus](node.len)
  for rawKey, valNode in node.pairs:
    let mbx = ?wrapInner(parseRFC5321MailboxFromServer(rawKey), path / rawKey)
    let ds = ?DeliveryStatus.fromJson(valNode, path / rawKey)
    tbl[mbx] = ds
  return ok(DeliveryStatusMap(tbl))
