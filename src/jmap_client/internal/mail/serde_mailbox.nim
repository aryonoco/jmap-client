# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Mailbox entity and supporting types (RFC 8621 §2).
## MailboxCreate is toJson-only — creation models flow client-to-server only.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/sets
import std/tables

import ../serialisation/serde
import ../../types
import ./mailbox

# =============================================================================
# MailboxRole
# =============================================================================

func toJson*(r: MailboxRole): JsonNode =
  ## Serialise ``MailboxRole`` to its RFC 8621 §2 wire identifier. For the
  ## ten well-known kinds this is the enum backing string; for ``mrOther``
  ## it is the captured vendor-extension identifier.
  return %r.identifier

func fromJson*(
    T: typedesc[MailboxRole], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[MailboxRole, SerdeViolation] =
  ## Deserialise a JSON string to ``MailboxRole`` via ``parseMailboxRole``.
  ## Rejects non-string nodes with ``svkWrongKind``; wraps any parser
  ## violation (empty, control chars) as ``svkFieldParserFailed``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JString, path)
  return wrapInner(parseMailboxRole(node.getStr("")), path)

# =============================================================================
# Helpers
# =============================================================================

func parseBoolField(
    node: JsonNode, key: string, path: JsonPath
): Result[bool, SerdeViolation] =
  ## Extracts a required boolean field.
  let field = ?fieldJBool(node, key, path)
  return ok(field.getBool(false))

func parseOptId(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[Id], SerdeViolation] =
  ## Extracts an optional Id field: nil/JNull yields Opt.none, otherwise parses via Id.fromJson.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(Id))
  return ok(Opt.some(?Id.fromJson(field, path / key)))

func parseOptMailboxRole(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[MailboxRole], SerdeViolation] =
  ## Extracts an optional MailboxRole field: nil/JNull yields Opt.none, otherwise parses via MailboxRole.fromJson.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(MailboxRole))
  return ok(Opt.some(?MailboxRole.fromJson(field, path / key)))

func parseOptUnsignedInt(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[UnsignedInt], SerdeViolation] =
  ## Extracts an optional UnsignedInt field: nil/JNull yields Opt.none,
  ## otherwise parses via UnsignedInt.fromJson. Used for the
  ## ``MailboxCreatedItem`` count fields, which Stalwart 0.15.5 omits
  ## from the Mailbox/set ``created[cid]`` payload.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(UnsignedInt))
  return ok(Opt.some(?UnsignedInt.fromJson(field, path / key)))

# =============================================================================
# MailboxIdSet
# =============================================================================

func toJson*(ms: MailboxIdSet): JsonNode =
  ## Serialise MailboxIdSet as ``{"id": true, ...}``. Empty set yields ``{}``.
  var node = newJObject()
  for id in ms:
    node[$id] = newJBool(true)
  return node

func fromJson*(
    T: typedesc[MailboxIdSet], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[T, SerdeViolation] =
  ## Deserialise ``{"id": true, ...}`` to MailboxIdSet. Rejects non-object,
  ## non-boolean values, and explicit ``false``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  var hs = initHashSet[Id](node.len)
  for key, val in node.pairs:
    if val.kind != JBool:
      return err(
        SerdeViolation(
          kind: svkWrongKind,
          path: path / key,
          expectedKind: JBool,
          actualKind: val.kind,
        )
      )
    if not val.getBool(false):
      return err(
        SerdeViolation(
          kind: svkEnumNotRecognised,
          path: path / key,
          enumTypeLabel: "mailbox id value",
          rawValue: "false",
        )
      )
    let id = ?wrapInner(parseIdFromServer(key), path / key)
    hs.incl(id)
  return ok(MailboxIdSet(hs))

# =============================================================================
# NonEmptyMailboxIdSet (Part E §4.2)
# =============================================================================
# Creation-context distinct HashSet: toJson-only per R1-3. The non-empty
# invariant is guaranteed by ``parseNonEmptyMailboxIdSet`` at construction;
# the serialiser simply projects the backing set onto the ``{id: true, ...}``
# wire shape — identical to ``MailboxIdSet`` but retyped at the signature.

func toJson*(ms: NonEmptyMailboxIdSet): JsonNode =
  ## Serialise NonEmptyMailboxIdSet as ``{"id": true, ...}``. Wire shape
  ## matches ``MailboxIdSet``; the non-empty invariant is enforced at
  ## construction, not here.
  var node = newJObject()
  for id in ms:
    node[$id] = newJBool(true)
  return node

# =============================================================================
# MailboxRights
# =============================================================================

func toJson*(mr: MailboxRights): JsonNode =
  ## Serialise MailboxRights to JSON with all 9 boolean fields.
  var node = newJObject()
  node["mayReadItems"] = %mr.mayReadItems
  node["mayAddItems"] = %mr.mayAddItems
  node["mayRemoveItems"] = %mr.mayRemoveItems
  node["maySetSeen"] = %mr.maySetSeen
  node["maySetKeywords"] = %mr.maySetKeywords
  node["mayCreateChild"] = %mr.mayCreateChild
  node["mayRename"] = %mr.mayRename
  node["mayDelete"] = %mr.mayDelete
  node["maySubmit"] = %mr.maySubmit
  return node

func fromJson*(
    T: typedesc[MailboxRights], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[MailboxRights, SerdeViolation] =
  ## Deserialise JSON object to MailboxRights. All 9 boolean fields are required.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let mayReadItems = ?parseBoolField(node, "mayReadItems", path)
  let mayAddItems = ?parseBoolField(node, "mayAddItems", path)
  let mayRemoveItems = ?parseBoolField(node, "mayRemoveItems", path)
  let maySetSeen = ?parseBoolField(node, "maySetSeen", path)
  let maySetKeywords = ?parseBoolField(node, "maySetKeywords", path)
  let mayCreateChild = ?parseBoolField(node, "mayCreateChild", path)
  let mayRename = ?parseBoolField(node, "mayRename", path)
  let mayDelete = ?parseBoolField(node, "mayDelete", path)
  let maySubmit = ?parseBoolField(node, "maySubmit", path)
  return ok(
    MailboxRights(
      mayReadItems: mayReadItems,
      mayAddItems: mayAddItems,
      mayRemoveItems: mayRemoveItems,
      maySetSeen: maySetSeen,
      maySetKeywords: maySetKeywords,
      mayCreateChild: mayCreateChild,
      mayRename: mayRename,
      mayDelete: mayDelete,
      maySubmit: maySubmit,
    )
  )

# =============================================================================
# Mailbox
# =============================================================================

func toJson*(mbx: Mailbox): JsonNode =
  ## Serialise Mailbox to JSON. All fields emitted; parentId/role as value or null.
  var node = newJObject()
  node["id"] = mbx.id.toJson()
  node["name"] = %mbx.name
  for pid in mbx.parentId:
    node["parentId"] = pid.toJson()
  if mbx.parentId.isNone:
    node["parentId"] = newJNull()
  for r in mbx.role:
    node["role"] = r.toJson()
  if mbx.role.isNone:
    node["role"] = newJNull()
  node["sortOrder"] = mbx.sortOrder.toJson()
  node["totalEmails"] = mbx.totalEmails.toJson()
  node["unreadEmails"] = mbx.unreadEmails.toJson()
  node["totalThreads"] = mbx.totalThreads.toJson()
  node["unreadThreads"] = mbx.unreadThreads.toJson()
  node["myRights"] = mbx.myRights.toJson()
  node["isSubscribed"] = %mbx.isSubscribed
  return node

func fromJson*(
    T: typedesc[Mailbox], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Mailbox, SerdeViolation] =
  ## Deserialise JSON object to Mailbox. Validates all required fields.
  ## Rejects absent, null, or empty name. Absent or null parentId/role
  ## yield Opt.none.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  let nameNode = ?fieldJString(node, "name", path)
  let name = nameNode.getStr("")
  ?nonEmptyStr(name, "name", path / "name")
  let parentId = ?parseOptId(node, "parentId", path)
  let role = ?parseOptMailboxRole(node, "role", path)
  let sortOrderNode = ?fieldJInt(node, "sortOrder", path)
  let sortOrder = ?UnsignedInt.fromJson(sortOrderNode, path / "sortOrder")
  let totalEmailsNode = ?fieldJInt(node, "totalEmails", path)
  let totalEmails = ?UnsignedInt.fromJson(totalEmailsNode, path / "totalEmails")
  let unreadEmailsNode = ?fieldJInt(node, "unreadEmails", path)
  let unreadEmails = ?UnsignedInt.fromJson(unreadEmailsNode, path / "unreadEmails")
  let totalThreadsNode = ?fieldJInt(node, "totalThreads", path)
  let totalThreads = ?UnsignedInt.fromJson(totalThreadsNode, path / "totalThreads")
  let unreadThreadsNode = ?fieldJInt(node, "unreadThreads", path)
  let unreadThreads = ?UnsignedInt.fromJson(unreadThreadsNode, path / "unreadThreads")
  let myRightsNode = ?fieldJObject(node, "myRights", path)
  let myRights = ?MailboxRights.fromJson(myRightsNode, path / "myRights")
  let isSubscribed = ?parseBoolField(node, "isSubscribed", path)
  return ok(
    Mailbox(
      id: id,
      name: name,
      parentId: parentId,
      role: role,
      sortOrder: sortOrder,
      totalEmails: totalEmails,
      unreadEmails: unreadEmails,
      totalThreads: totalThreads,
      unreadThreads: unreadThreads,
      myRights: myRights,
      isSubscribed: isSubscribed,
    )
  )

# =============================================================================
# MailboxCreatedItem — Mailbox/set ``created[cid]`` payload (RFC 8620 §5.3)
# =============================================================================

func parseOptMailboxRights(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[MailboxRights], SerdeViolation] =
  ## Extracts an optional MailboxRights field: nil/JNull yields Opt.none,
  ## otherwise parses via MailboxRights.fromJson. Local to this section
  ## because it must be declared after MailboxRights.fromJson; the four
  ## count-field helpers live in the global Helpers block above.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(MailboxRights))
  return ok(Opt.some(?MailboxRights.fromJson(field, path / key)))

func toJson*(item: MailboxCreatedItem): JsonNode =
  ## Serialise ``MailboxCreatedItem`` to JSON. Emits ``id`` always; the
  ## five server-set fields only when present (round-trips Stalwart's
  ## elision symmetrically — Postel's law on send too).
  var node = newJObject()
  node["id"] = item.id.toJson()
  for v in item.totalEmails:
    node["totalEmails"] = v.toJson()
  for v in item.unreadEmails:
    node["unreadEmails"] = v.toJson()
  for v in item.totalThreads:
    node["totalThreads"] = v.toJson()
  for v in item.unreadThreads:
    node["unreadThreads"] = v.toJson()
  for v in item.myRights:
    node["myRights"] = v.toJson()
  return node

func fromJson*(
    T: typedesc[MailboxCreatedItem], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[MailboxCreatedItem, SerdeViolation] =
  ## Deserialise the partial Mailbox payload sent in Mailbox/set
  ## ``created[cid]``. ``id`` is required (RFC 8620 §5.3); the four
  ## count fields and ``myRights`` are ``Opt`` because Stalwart 0.15.5
  ## omits them (strict-RFC minor divergence, accommodated here per
  ## Postel's law). Other Mailbox fields are not expected — the client
  ## already sent them in ``create``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  let totalEmails = ?parseOptUnsignedInt(node, "totalEmails", path)
  let unreadEmails = ?parseOptUnsignedInt(node, "unreadEmails", path)
  let totalThreads = ?parseOptUnsignedInt(node, "totalThreads", path)
  let unreadThreads = ?parseOptUnsignedInt(node, "unreadThreads", path)
  let myRights = ?parseOptMailboxRights(node, "myRights", path)
  return ok(
    MailboxCreatedItem(
      id: id,
      totalEmails: totalEmails,
      unreadEmails: unreadEmails,
      totalThreads: totalThreads,
      unreadThreads: unreadThreads,
      myRights: myRights,
    )
  )

# =============================================================================
# MailboxCreate
# =============================================================================

func toJson*(mc: MailboxCreate): JsonNode =
  ## Serialise MailboxCreate to JSON. ``parentId`` is always emitted
  ## (value or null) because the wire shape distinguishes "top-level
  ## mailbox" (null) from "nested under X" (value). ``role`` and
  ## ``sortOrder`` are emitted only when explicitly set: Stalwart
  ## accepts both omitted and explicit-null/zero forms, but James 3.9
  ## treats either field as a server-set property and rejects creation
  ## with ``invalidArguments`` whenever they appear in the payload
  ## (``MailboxSetMethod.scala`` allow-list). RFC 8621 §2.5 leaves
  ## both as optional client suggestions, so omitting them when the
  ## caller did not supply a value is RFC-conformant on both targets.
  var node = newJObject()
  node["name"] = %mc.name
  for pid in mc.parentId:
    node["parentId"] = pid.toJson()
  if mc.parentId.isNone:
    node["parentId"] = newJNull()
  for r in mc.role:
    node["role"] = r.toJson()
  if mc.sortOrder != UnsignedInt(0):
    node["sortOrder"] = mc.sortOrder.toJson()
  node["isSubscribed"] = %mc.isSubscribed
  return node

# =============================================================================
# MailboxUpdate
# =============================================================================

func toJson*(u: MailboxUpdate): (string, JsonNode) =
  ## Emit the ``(wire-key, wire-value)`` pair for a single Mailbox update.
  ## RFC 8621 §2 settable Mailbox properties are whole-value replace — each
  ## variant maps to exactly one top-level property, no sub-path flattening.
  case u.kind
  of muSetName:
    ("name", %u.name)
  of muSetParentId:
    ("parentId", u.parentId.optToJsonOrNull())
  of muSetRole:
    ("role", u.role.optToJsonOrNull())
  of muSetSortOrder:
    ("sortOrder", u.sortOrder.toJson())
  of muSetIsSubscribed:
    ("isSubscribed", %u.isSubscribed)

func toJson*(us: MailboxUpdateSet): JsonNode =
  ## Flatten the validated update-set to an RFC 8620 §5.3 wire patch.
  ## ``initMailboxUpdateSet`` has already rejected duplicate target
  ## properties, so blind aggregation cannot shadow a prior entry.
  var node = newJObject()
  for u in seq[MailboxUpdate](us):
    let (key, value) = u.toJson()
    node[key] = value
  return node

func toJson*(upd: NonEmptyMailboxUpdates): JsonNode =
  ## Flatten the whole-container update algebra to the RFC 8620 §5.3
  ## wire ``update`` value — ``{mailboxId: patchObj, ...}``.
  ## ``parseNonEmptyMailboxUpdates`` has already enforced non-empty
  ## input and distinct ids, so blind aggregation cannot shadow a
  ## prior entry.
  var node = newJObject()
  for id, patchSet in Table[Id, MailboxUpdateSet](upd):
    node[string(id)] = patchSet.toJson()
  return node
