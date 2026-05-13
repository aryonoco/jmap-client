# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for ``EmailBlueprint`` (Design §3.6). Creation type —
## ``toJson`` only (R1-3); no ``fromJson``. ``Opt.none`` fields and empty
## collections are omitted from wire output (R4-2, R4-3).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../serialisation/serde
import ../types
import ./addresses
import ./body
import ./email_blueprint
import ./headers
import ./keyword
import ./serde_addresses
import ./serde_body
import ./serde_headers
import ./serde_keyword
import ./serde_mailbox

# =============================================================================
# Optional-field emitters (R4-2: Opt.none → omit; R4-3: empty collection → omit)
# =============================================================================

func emitSender(node: var JsonNode, opt: Opt[EmailAddress]) =
  ## RFC 5322 §3.6.2 names Sender as a singular mailbox; R4-1 forces the
  ## wire shape to a 1-element JArray for consistency with the other
  ## address-list fields. ``Opt.none`` → omit.
  for s in opt:
    var arr = newJArray()
    arr.add(s.toJson())
    node["sender"] = arr

func emitOptAddrSeq(node: var JsonNode, key: string, opt: Opt[seq[EmailAddress]]) =
  ## Emit the address-list convenience fields (from/to/cc/bcc/replyTo).
  ## ``Opt.none`` → omit. ``Opt.some(@[])`` is domain-legal and emitted as
  ## an empty JArray — the smart constructor decides whether such a state
  ## is reachable, not the serialiser.
  for addrs in opt:
    var arr = newJArray()
    for a in addrs:
      arr.add(a.toJson())
    node[key] = arr

func emitOptStringSeq(node: var JsonNode, key: string, opt: Opt[seq[string]]) =
  ## Emit message-id / in-reply-to / references convenience fields.
  ## ``Opt.none`` → omit (R4-2).
  for strs in opt:
    var arr = newJArray()
    for s in strs:
      arr.add(%s)
    node[key] = arr

# =============================================================================
# extraHeaders — composes wire keys via ``composeHeaderKey`` (Design §4.5.3)
# =============================================================================

func emitExtraHeaders(
    node: var JsonNode, eh: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]
) =
  ## For each ``(name, mv)`` pair, compose the ``"header:<name>[:as<Form>][:all]"``
  ## wire key and pair it with the variant-dispatched value. Empty table →
  ## no emission. ``Table`` iteration order is not observable-meaningful per
  ## JSON spec, so no sort is applied.
  for name, mv in eh:
    let isAll = multiLen(mv) > 1
    node[composeHeaderKey(name, mv.form, isAll)] = blueprintMultiValueToJson(mv)

# =============================================================================
# Body variant — delegates to serde_body.toJson (existing public entry)
# =============================================================================

func emitStructuredBody(node: var JsonNode, root: BlueprintBodyPart) =
  ## Emit the ``ebkStructured`` branch as a single ``bodyStructure`` key
  ## whose value is the recursive body-part tree. The tree-walker
  ## (serde_body.bpToJsonImpl) applies the depth limit; this helper only
  ## places the result on the aggregate.
  node["bodyStructure"] = root.toJson()

func emitFlatBody(
    node: var JsonNode,
    textBody: Opt[BlueprintBodyPart],
    htmlBody: Opt[BlueprintBodyPart],
    attachments: seq[BlueprintBodyPart],
) =
  ## Emit the ``ebkFlat`` branch — each of ``textBody`` / ``htmlBody`` /
  ## ``attachments`` is omitted when its slot is ``Opt.none`` or empty
  ## (R4-3). ``textBody`` and ``htmlBody`` are JArrays of length 1 when
  ## present (wire schema forces array, even though the domain type carries
  ## at most one leaf). Caller deconstructs the case object at the
  ## ``ebkFlat`` branch so this helper has no case-object access surface
  ## (FFI panic-surface contract per §6.4.4).
  for tb in textBody:
    var arr = newJArray()
    arr.add(tb.toJson())
    node["textBody"] = arr
  for hb in htmlBody:
    var arr = newJArray()
    arr.add(hb.toJson())
    node["htmlBody"] = arr
  if attachments.len > 0:
    var arr = newJArray()
    for att in attachments:
      arr.add(att.toJson())
    node["attachments"] = arr

# =============================================================================
# bodyValues harvest — derived accessor (Design §5.4)
# =============================================================================

func emitBodyValues(node: var JsonNode, bv: Table[PartId, BlueprintBodyValue]) =
  ## Project the ``bodyValues`` table onto a ``{partId: {"value": ...}}``
  ## object. Empty table → omit (R4-3). Duplicate ``partId`` across the
  ## body tree is a documented gap (§7 E30); the ``bodyValues`` accessor
  ## resolves duplicates via ``Table`` last-wins, so this serialiser only
  ## sees one entry per partId by construction.
  if bv.len == 0:
    return
  var values = newJObject()
  for partId, value in bv:
    values[$partId] = value.toJson()
  node["bodyValues"] = values

# =============================================================================
# EmailBlueprint — public entry
# =============================================================================

func toJson*(bp: EmailBlueprint): JsonNode =
  ## Serialise ``EmailBlueprint`` to the JSON shape consumed by
  ## ``Email/set`` (Design §3.6). Field emission order follows the R4-1
  ## mapping table. ``Opt.none`` fields (R4-2) and empty collections
  ## (R4-3) are omitted entirely — not emitted as ``null``.
  var node = newJObject()

  node["mailboxIds"] = bp.mailboxIds.toJson()
  if bp.keywords.card > 0:
    node["keywords"] = bp.keywords.toJson()
  for v in bp.receivedAt:
    node["receivedAt"] = v.toJson()

  emitOptAddrSeq(node, "from", bp.fromAddr)
  emitOptAddrSeq(node, "to", bp.to)
  emitOptAddrSeq(node, "cc", bp.cc)
  emitOptAddrSeq(node, "bcc", bp.bcc)
  emitOptAddrSeq(node, "replyTo", bp.replyTo)
  emitSender(node, bp.sender)

  for s in bp.subject:
    node["subject"] = %s
  for d in bp.sentAt:
    node["sentAt"] = d.toJson()

  emitOptStringSeq(node, "messageId", bp.messageId)
  emitOptStringSeq(node, "inReplyTo", bp.inReplyTo)
  emitOptStringSeq(node, "references", bp.references)

  emitExtraHeaders(node, bp.extraHeaders)

  # Let-bind bp.body so strict tracks one EmailBlueprintBody value across
  # the case and field reads — each call of bp.body() would return an
  # independent copy, breaking strict's flow analysis.
  let body = bp.body
  case body.kind
  of ebkStructured:
    emitStructuredBody(node, body.bodyStructure)
  of ebkFlat:
    emitFlatBody(node, body.textBody, body.htmlBody, body.attachments)

  emitBodyValues(node, bp.bodyValues)

  return node
