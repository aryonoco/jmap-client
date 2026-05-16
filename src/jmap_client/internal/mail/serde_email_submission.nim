# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde for the RFC 8621 §7 EmailSubmission entity, creation blueprint,
## update algebra, filter + comparator, and ``IdOrCreationRef`` map key.
##
## ``AnyEmailSubmission`` uses a private ``fromJsonShared[S: static UndoStatus]``
## helper so the shared field list is written once and monomorphised at
## dispatch. The helper does not read ``undoStatus`` itself — the caller
## (``AnyEmailSubmission.fromJson``) has already parsed it to pick the
## phantom branch.
##
## Surface:
##   * ``fromJson``-only: ``AnyEmailSubmission``,
##     ``EmailSubmissionCreatedItem`` (the generic ``SetResponse[T, U]``
##     serde picks the latter up via ``mixin`` — ``T`` resolves the
##     create rail, ``U`` resolves the partial-update rail per A4
##     D1/D2; ``U = PartialEmailSubmission`` for EmailSubmission/set).
##   * ``fromJson`` + ``toJson``: ``PartialEmailSubmission`` (A4 + A3.6
##     D7 — receive-only at the public surface; ``toJson`` exists for
##     D3.7 round-trip symmetry).
##   * ``toJson``-only: ``EmailSubmissionBlueprint``,
##     ``EmailSubmissionUpdate``, ``NonEmptyEmailSubmissionUpdates``,
##     ``EmailSubmissionFilterCondition``, ``EmailSubmissionComparator``,
##     ``IdOrCreationRef``.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../serialisation/serde
import ../serialisation/serde_diagnostics
import ../serialisation/serde_field_echo
import ../serialisation/serde_helpers
import ../serialisation/serde_primitives
import ../types
import ./email_submission
import ./submission_envelope
import ./submission_status
import ./serde_email_update
import ./serde_submission_envelope
import ./serde_submission_status

# Re-export the L2 serde foundation and sibling serde modules so that
# ``PartialEmailSubmission.fromJson`` resolves transitively through
# ``BlobId.fromJson`` / ``UTCDate.fromJson`` (L2 hub) and
# ``Envelope.fromJson`` / ``DeliveryStatusMap.fromJson`` /
# ``UndoStatus.fromJson`` at every callsite (including the mixin chain
# through ``SetResponse[T, U].fromJson`` and ``seq[BlobId].fromJson``).
export serde_submission_envelope
export serde_submission_status

# =============================================================================
# Field helpers — nullable composites
# =============================================================================

func parseEnvelopeField(
    node: JsonNode, path: JsonPath
): Result[Opt[Envelope], SerdeViolation] =
  ## Nullable ``envelope`` field: absent or ``null`` collapses to
  ## ``Opt.none`` (G27, matching RFC 8621 §7 ¶2 ``Envelope|null`` — absent
  ## case treated leniently, Postel's law).
  let field = node{"envelope"}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(Envelope))
  let env = ?Envelope.fromJson(field, path / "envelope")
  return ok(Opt.some(env))

func parseDeliveryStatusMapField(
    node: JsonNode, path: JsonPath
): Result[Opt[DeliveryStatusMap], SerdeViolation] =
  ## Nullable ``deliveryStatus`` field: absent or ``null`` collapses to
  ## ``Opt.none`` (RFC 8621 §7 ¶8 ``String[DeliveryStatus]|null``).
  let field = node{"deliveryStatus"}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(DeliveryStatusMap))
  let m = ?DeliveryStatusMap.fromJson(field, path / "deliveryStatus")
  return ok(Opt.some(m))

# =============================================================================
# EmailSubmission — shared-field read path
# =============================================================================

func fromJsonShared[S: static UndoStatus](
    node: JsonNode, path: JsonPath
): Result[EmailSubmission[S], SerdeViolation] =
  ## Shared reader for the phantom-indexed entity. The ``S`` parameter is a
  ## compile-time ``UndoStatus`` selecting the return type arm; the caller
  ## is responsible for parsing ``undoStatus`` from the same ``node`` and
  ## dispatching to the matching instantiation. The phantom erases at
  ## runtime, so the three monomorphisations compile to effectively the
  ## same body differing only in return-type metadata.
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  let identityIdNode = ?fieldJString(node, "identityId", path)
  let identityId = ?Id.fromJson(identityIdNode, path / "identityId")
  let emailIdNode = ?fieldJString(node, "emailId", path)
  let emailId = ?Id.fromJson(emailIdNode, path / "emailId")
  let threadIdNode = ?fieldJString(node, "threadId", path)
  let threadId = ?Id.fromJson(threadIdNode, path / "threadId")
  let envelope = ?parseEnvelopeField(node, path)
  let sendAtNode = ?fieldJString(node, "sendAt", path)
  let sendAt = ?UTCDate.fromJson(sendAtNode, path / "sendAt")
  let deliveryStatus = ?parseDeliveryStatusMapField(node, path)
  let dsnBlobIds =
    ?collapseNullToEmptySeq[BlobId](node, "dsnBlobIds", parseBlobId, path)
  let mdnBlobIds =
    ?collapseNullToEmptySeq[BlobId](node, "mdnBlobIds", parseBlobId, path)
  return ok(
    EmailSubmission[S](
      id: id,
      identityId: identityId,
      emailId: emailId,
      threadId: threadId,
      envelope: envelope,
      sendAt: sendAt,
      deliveryStatus: deliveryStatus,
      dsnBlobIds: dsnBlobIds,
      mdnBlobIds: mdnBlobIds,
    )
  )

func fromJson*(
    T: typedesc[AnyEmailSubmission], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[AnyEmailSubmission, SerdeViolation] =
  ## Peek at ``undoStatus`` once, pick the phantom branch, then delegate the
  ## shared field list to ``fromJsonShared``. Construction flows through the
  ## ``toAny`` overload family — the canonical gateway for the sealed
  ## ``AnyEmailSubmission``. Each ``toAny`` overload internally uses a
  ## literal ``state:`` per arm (Pattern 4 in nim-functional-core.md).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let statusNode = ?fieldJString(node, "undoStatus", path)
  let status = ?parseUndoStatus(statusNode.getStr(""), path / "undoStatus")
  case status
  of usPending:
    let sub = ?fromJsonShared[usPending](node, path)
    return ok(toAny(sub))
  of usFinal:
    let sub = ?fromJsonShared[usFinal](node, path)
    return ok(toAny(sub))
  of usCanceled:
    let sub = ?fromJsonShared[usCanceled](node, path)
    return ok(toAny(sub))

# =============================================================================
# EmailSubmissionCreatedItem — /set created-map value
# =============================================================================

func fromJson*(
    T: typedesc[EmailSubmissionCreatedItem],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[EmailSubmissionCreatedItem, SerdeViolation] =
  ## Deserialise the partial EmailSubmission payload sent in
  ## EmailSubmission/set ``created[cid]``. ``id`` is required (RFC 8620
  ## §5.3); ``threadId``, ``sendAt``, and ``undoStatus`` are ``Opt``
  ## because servers diverge on what they include in the
  ## acknowledgement.  Stalwart 0.15.5 emits only ``{"id": "<id>"}``;
  ## Cyrus 3.12.2 emits ``{"id", "undoStatus", "sendAt"}`` because its
  ## submission lifecycle is fire-and-forget (the server may have
  ## finalised and discarded the record by the time the client could
  ## call ``/get``, so the create response carries the live state).
  ## Postel's-law accommodation per ``.claude/rules/nim-conventions.md``
  ## §"Serde Conventions". The ``mixin``-resolved ``SetResponse[
  ## EmailSubmissionCreatedItem, PartialEmailSubmission].fromJson``
  ## drives this at the dispatch site.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  let threadIdField = node{"threadId"}
  var threadId = Opt.none(Id)
  if not threadIdField.isNil and threadIdField.kind != JNull:
    ?expectKind(threadIdField, JString, path / "threadId")
    let parsed = ?Id.fromJson(threadIdField, path / "threadId")
    threadId = Opt.some(parsed)
  let sendAtField = node{"sendAt"}
  var sendAt = Opt.none(UTCDate)
  if not sendAtField.isNil and sendAtField.kind != JNull:
    ?expectKind(sendAtField, JString, path / "sendAt")
    let parsed = ?UTCDate.fromJson(sendAtField, path / "sendAt")
    sendAt = Opt.some(parsed)
  let undoField = node{"undoStatus"}
  var undoStatus = Opt.none(UndoStatus)
  if not undoField.isNil and undoField.kind != JNull:
    ?expectKind(undoField, JString, path / "undoStatus")
    let parsed = ?parseUndoStatus(undoField.getStr(""), path / "undoStatus")
    undoStatus = Opt.some(parsed)
  return ok(
    EmailSubmissionCreatedItem(
      id: id, threadId: threadId, sendAt: sendAt, undoStatus: undoStatus
    )
  )

# =============================================================================
# EmailSubmissionBlueprint — /set create value
# =============================================================================

func toJson*(bp: EmailSubmissionBlueprint): JsonNode =
  ## RFC 8621 §7.5 create value: ``{identityId, emailId, envelope?}``.
  ## Absent ``envelope`` is omitted entirely — the server synthesises it
  ## from the referenced Email's headers per §7.5 ¶4 (RFC 8620 §5.3 also
  ## mandates the client MUST omit any server-only property; the blueprint
  ## carries none by design, so there is nothing additional to strip).
  var node = newJObject()
  node["identityId"] = bp.identityId.toJson()
  node["emailId"] = bp.emailId.toJson()
  for env in bp.envelope:
    node["envelope"] = env.toJson()
  return node

# =============================================================================
# EmailSubmissionUpdate / NonEmptyEmailSubmissionUpdates — /set update value
# =============================================================================

when EmailSubmissionUpdateVariantKind.low != EmailSubmissionUpdateVariantKind.high:
  {.
    error:
      "a new EmailSubmissionUpdate variant was added; rewrite toJson as a case dispatch"
  .}

func toJson*(u: EmailSubmissionUpdate): (string, JsonNode) =
  ## Emit one PatchObject entry as ``(JSON-Pointer key, wire value)``. RFC
  ## 8620 §5.3 PatchObject keys carry an implicit leading ``/``, so the
  ## bare ``"undoStatus"`` is spec-conformant. The module-scope ``when``
  ## guard above breaks the build the moment a second
  ## ``EmailSubmissionUpdateVariantKind`` is introduced — that is the
  ## signal to rewrite this body as a ``case`` dispatch. Today's single-
  ## arm form is direct because nimalyzer forbids a ``case`` with fewer
  ## than two branches, and the ``tno_asserts_in_src`` compliance test
  ## forbids runtime ``doAssert`` calls in ``src/`` even inside
  ## ``static:`` (invariants belong in the type system).
  discard u
  ("undoStatus", %"canceled")

func toJson*(us: NonEmptyEmailSubmissionUpdates): JsonNode =
  ## Wire shape ``{subId: {patchKey: patchVal, ...}, ...}``. The L1
  ## container maps one ``EmailSubmissionUpdate`` per id, so each inner
  ## PatchObject has exactly one key — today ``undoStatus``.
  var node = newJObject()
  for id, update in pairs(us.toTable):
    let (key, value) = update.toJson()
    var patch = newJObject()
    patch[key] = value
    node[$id] = patch
  return node

# =============================================================================
# IdOrCreationRef — creation-reference key for onSuccessUpdate/Destroy maps
# =============================================================================

func idOrCreationRefWireKey*(r: IdOrCreationRef): string =
  ## Raw wire string form — the ``Id`` verbatim or ``"#"`` +
  ## ``CreationId`` per RFC 8620 §5.3 / RFC 8621 §7.5 ¶3. Exported for
  ## Table-key stringification by Step 18's compound builder, where the
  ## wrapping ``JsonNode`` layer is unnecessary.
  case r.kind
  of icrDirect:
    # invariant: kind == icrDirect proves Ok
    $r.asDirectRef.get()
  of icrCreation:
    # invariant: kind == icrCreation proves Ok
    "#" & $r.asCreationRef.get()

func toJson*(r: IdOrCreationRef): JsonNode =
  ## JSON string form of ``idOrCreationRefWireKey`` — used when
  ## ``IdOrCreationRef`` appears as a list element (e.g.,
  ## ``onSuccessDestroyEmail``) rather than a map key.
  return %idOrCreationRefWireKey(r)

func toJson*(v: NonEmptyOnSuccessUpdateEmail): JsonNode =
  ## Flatten to RFC 8621 §7.5 ¶3 wire shape
  ## ``{idOrCreationRefKey: patchObj, ...}``. Non-empty + distinct-key
  ## invariants enforced by ``parseNonEmptyOnSuccessUpdateEmail``.
  var node = newJObject()
  for k, patchSet in v.toTable:
    node[idOrCreationRefWireKey(k)] = patchSet.toJson()
  return node

func toJson*(v: NonEmptyOnSuccessDestroyEmail): JsonNode =
  ## Flatten to RFC 8621 §7.5 ¶3 wire shape
  ## ``[idOrCreationRefKey, ...]``.
  var arr = newJArray()
  for r in v.toSeq:
    arr.add(%idOrCreationRefWireKey(r))
  return arr

# =============================================================================
# EmailSubmissionFilterCondition — /query filter (RFC 8621 §7.3)
# =============================================================================

func emitNonEmptyIdArray(node: JsonNode, key: string, opt: Opt[NonEmptyIdSeq]) =
  ## Sparse emission: ``Opt.none`` leaves the key out; ``Opt.some`` expands
  ## the non-empty id sequence to a JSON array.
  for v in opt:
    var arr = newJArray()
    for id in v:
      arr.add(id.toJson())
    node[key] = arr

func toJson*(fc: EmailSubmissionFilterCondition): JsonNode =
  ## Sparse-emission filter condition. ``Opt.none`` fields disappear from
  ## the wire entirely — same convention as ``EmailFilterCondition``.
  ## ``NonEmptyIdSeq`` is stricter than the RFC (G37): the wire permits
  ## empty arrays but an empty filter list matches nothing, almost always
  ## a client bug. Strictness on the client side is RFC-compliant.
  var node = newJObject()
  node.emitNonEmptyIdArray("identityIds", fc.identityIds)
  node.emitNonEmptyIdArray("emailIds", fc.emailIds)
  node.emitNonEmptyIdArray("threadIds", fc.threadIds)
  for v in fc.undoStatus:
    node["undoStatus"] = v.toJson()
  for v in fc.before:
    node["before"] = v.toJson()
  for v in fc.after:
    node["after"] = v.toJson()
  return node

# =============================================================================
# EmailSubmissionComparator — /query sort criterion (RFC 8621 §7.3)
# =============================================================================

func toJson*(c: EmailSubmissionComparator): JsonNode =
  ## Emit ``rawProperty`` verbatim — it is authoritative for ``esspOther``
  ## vendor tokens and equal to ``$c.property`` for the three RFC-defined
  ## properties (``emailId``, ``threadId``, ``sentAt``). The wire token is
  ## ``sentAt``, deliberately NOT the entity field name ``sendAt`` (G19,
  ## an RFC quirk preserved verbatim). ``isAscending`` is always explicit
  ## for debuggability; ``collation`` is sparse.
  var node = newJObject()
  node["property"] = %c.rawProperty
  node["isAscending"] = %c.isAscending
  for col in c.collation:
    node["collation"] = %($col)
  return node

# =============================================================================
# PartialEmailSubmission (A4 + A3.6)
# =============================================================================

func fromJson*(
    T: typedesc[PartialEmailSubmission],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[PartialEmailSubmission, SerdeViolation] =
  ## Deserialise a partial EmailSubmission echo (RFC 8621 §7). Lenient
  ## on missing fields; strict on wrong-kind present fields and strict-
  ## on-wire-token for closed-enum ``undoStatus`` (D4).
  discard $T
  ?expectKind(node, JObject, path)
  let id = ?parsePartialOptField[Id](node, "id", path)
  let identityId = ?parsePartialOptField[Id](node, "identityId", path)
  let emailId = ?parsePartialOptField[Id](node, "emailId", path)
  let threadId = ?parsePartialOptField[Id](node, "threadId", path)
  let envelope = ?parsePartialFieldEcho[Envelope](node, "envelope", path)
  let sendAt = ?parsePartialOptField[UTCDate](node, "sendAt", path)
  let undoStatus = ?parsePartialOptField[UndoStatus](node, "undoStatus", path)
  let deliveryStatus =
    ?parsePartialFieldEcho[DeliveryStatusMap](node, "deliveryStatus", path)
  let dsnBlobIds = ?parsePartialOptField[seq[BlobId]](node, "dsnBlobIds", path)
  let mdnBlobIds = ?parsePartialOptField[seq[BlobId]](node, "mdnBlobIds", path)
  return ok(
    PartialEmailSubmission(
      id: id,
      identityId: identityId,
      emailId: emailId,
      threadId: threadId,
      envelope: envelope,
      sendAt: sendAt,
      undoStatus: undoStatus,
      deliveryStatus: deliveryStatus,
      dsnBlobIds: dsnBlobIds,
      mdnBlobIds: mdnBlobIds,
    )
  )

func toJson*(p: PartialEmailSubmission): JsonNode =
  ## Emit a partial EmailSubmission echo — D5/D3.7 unidirectional serde
  ## symmetry. ``fekAbsent`` and ``Opt.none`` omit the key.
  var node = newJObject()
  for v in p.id:
    node["id"] = v.toJson()
  for v in p.identityId:
    node["identityId"] = v.toJson()
  for v in p.emailId:
    node["emailId"] = v.toJson()
  for v in p.threadId:
    node["threadId"] = v.toJson()
  emitPartialFieldEcho[Envelope](node, "envelope", p.envelope)
  for v in p.sendAt:
    node["sendAt"] = v.toJson()
  for v in p.undoStatus:
    node["undoStatus"] = v.toJson()
  emitPartialFieldEcho[DeliveryStatusMap](node, "deliveryStatus", p.deliveryStatus)
  for v in p.dsnBlobIds:
    node["dsnBlobIds"] = v.toJson()
  for v in p.mdnBlobIds:
    node["mdnBlobIds"] = v.toJson()
  return node
